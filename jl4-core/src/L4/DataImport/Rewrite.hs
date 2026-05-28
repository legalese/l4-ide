{-# LANGUAGE OverloadedStrings #-}
-- | Rewrite @IMPORT \`file.csv\` AS Row HAS …@ statements in a parsed
-- module into the equivalent inlined @DECLARE@ + value binding by
-- reading the file content, running it through the synthesizer, and
-- re-parsing the result.
--
-- This is the integration point that turns the parser- and AST-level
-- support for data imports (added in earlier commits) into a real
-- end-to-end feature: after this pass, the type-checker sees plain
-- 'Declare' and 'Decide' top-level declarations rather than
-- 'MkDataImport' nodes.
--
-- The pass is parameterised over the lookup monad so that the LSP
-- backend (Shake / filesystem) and the WASM backend (pure / VFS) can
-- share the same logic.
module L4.DataImport.Rewrite
  ( DataFileLookup
  , RewriteResult(..)
  , rewriteDataImports
  , mkAugmentedLookup
  , DataImportError(..)
  ) where

import Base
import qualified Base.Text as Text
import qualified Data.Map.Strict as Map

import L4.DataImport.Csv
import L4.DataImport.Synthesize
  ( buildDeclareEnv
  , buildDeclareEnvs
  , mergeDeclareEnvs
  , DeclareEnv
  , CoerceError
  , synthesizeFromCsv
  )
import L4.Lexer (PError(..))
import L4.Parser (execProgramParserWithHintPass)
import L4.Syntax


-- | How to look up the raw text of a CSV / TSV data file by its
-- filename token (e.g. @\"trades.csv\"@). Returns 'Nothing' when the
-- file cannot be found.
type DataFileLookup m = Text -> m (Maybe Text)

-- | Errors a data-import rewrite can produce.
data DataImportError
  = DataFileNotFound !Text
    -- ^ The lookup function returned 'Nothing' for this filename.
  | DataFileUnsupportedExtension !Text
    -- ^ Filename does not end in @.csv@ or @.tsv@.
  | DataFileParseFailed !Text !CsvParseError
    -- ^ The CSV/TSV parser rejected the file content.
  | DataFileCoerceFailed !Text !CoerceError
    -- ^ The synthesizer rejected the file content against the declared schema.
  | DataFileSynthesisUnparseable !Text ![Text]
    -- ^ The synthesized L4 snippet failed to re-parse. Indicates a
    -- bug in the synthesizer, not a user error.
  deriving stock (Eq, Show)

-- | The output of 'rewriteDataImports'.
--
-- Carries the rewritten parent module plus a map of /synthesized
-- module sources/ that the caller should make visible to the import
-- resolver (typically by wrapping its 'ModuleLookup' with
-- 'mkAugmentedLookup'). The synthesized-source map is keyed by
-- module name (the same string the resolver looks up).
--
-- Today the rewriter still inlines synthesized declarations into the
-- parent module and the map is therefore always empty — the structure
-- is in place to support the upcoming switch to a virtual-module
-- representation without further API churn at the call sites.
data RewriteResult = MkRewriteResult
  { rrParent             :: !(Module Name)
  , rrSynthesizedSources :: !(Map Text Text)
  }

-- | Walk a parsed 'Module' and rewrite every 'MkDataImport' into a
-- value binding by reading the named file, looking up the row type
-- in the module's @DECLARE@ environment, and coercing each CSV row.
-- Imports that are not data imports (i.e. plain 'MkImport') are
-- left untouched.
--
-- The DECLARE environment is built from the local module plus any
-- additional parsed modules the caller chooses to expose
-- (typically: the parent's resolved imports, so a row type
-- declared in an imported module is in scope for the rewriter).
-- The local module's DECLAREs shadow imported ones on duplicate
-- names — see 'mergeDeclareEnvs' for the precise rule.
--
-- The pass walks top-level decls only (it does not descend into
-- nested sections — IMPORT statements at the top level are the
-- normal case).
rewriteDataImports
  :: forall m. Monad m
  => DataFileLookup m
  -> [Module Name]      -- ^ additional modules to include in the DECLARE environment (typically the parent's imports)
  -> Module Name        -- ^ the parent module to rewrite
  -> m (Either [DataImportError] RewriteResult)
rewriteDataImports lookupData additional m@(MkModule mAnn uri (MkSection sAnn sName sAka topdecls)) = do
  let env = mergeDeclareEnvs (buildDeclareEnv m) (buildDeclareEnvs additional)
  rewritten <- traverse (rewriteOne lookupData env uri) topdecls
  let (errs, decls) = partitionEithers (concatMapPreserve rewritten)
  if null errs
    then pure $ Right MkRewriteResult
      { rrParent             = MkModule mAnn uri (MkSection sAnn sName sAka decls)
      , rrSynthesizedSources = Map.empty
      }
    else pure $ Left errs

-- | Wrap a 'ModuleLookup'-shaped lookup function with a map of
-- pre-resolved sources. The wrapper consults the map first; only on a
-- miss does it fall through to the underlying lookup. Used by the
-- import-resolution pipeline to expose 'rrSynthesizedSources' to the
-- resolver as if those modules existed in the regular VFS / filesystem.
--
-- The lookup type is spelled out inline rather than using
-- 'L4.Import.Resolution.ModuleLookup' so that 'L4.DataImport.Rewrite'
-- stays below 'L4.Import.Resolution' in the import graph (Resolution
-- depends on Rewrite, not the other way around).
mkAugmentedLookup
  :: Monad m
  => (Text -> m (Maybe Text))
  -> Map Text Text
  -> (Text -> m (Maybe Text))
mkAugmentedLookup baseLookup extras name =
  case Map.lookup name extras of
    Just src -> pure (Just src)
    Nothing  -> baseLookup name

-- | Per-top-decl rewrite. A plain decl passes through as @Right [d]@;
-- a data import either expands to a list of synthesized decls or
-- contributes a 'Left' error. We use a list of 'Either' so that the
-- caller can collect errors across all imports rather than bailing on
-- the first.
rewriteOne
  :: Monad m
  => DataFileLookup m
  -> DeclareEnv
  -> NormalizedUri
  -> TopDecl Name
  -> m [Either DataImportError (TopDecl Name)]
rewriteOne lookupData env uri = \case
  Import iAnn (MkDataImport _ fnN ty _) ->
    expandDataImport lookupData env uri iAnn fnN ty
  d ->
    pure [Right d]

-- ----------------------------------------------------------------------------
-- Per-import expansion
-- ----------------------------------------------------------------------------

expandDataImport
  :: Monad m
  => DataFileLookup m
  -> DeclareEnv
  -> NormalizedUri
  -> Anno
  -> Name           -- ^ filename token
  -> Type' Name     -- ^ the @IS A …@ type expression
  -> m [Either DataImportError (TopDecl Name)]
expandDataImport lookupData env uri _iAnn fnN ty = do
  let fnText = rawNameToText (rawName fnN)
  mContent <- lookupData fnText
  case mContent of
    Nothing -> pure [Left (DataFileNotFound fnText)]
    Just content
      | not (isSupportedExtension fnText) ->
          pure [Left (DataFileUnsupportedExtension fnText)]
      | otherwise ->
          case parseFile fnText content of
            Left e -> pure [Left (DataFileParseFailed fnText e)]
            Right doc ->
              case synthesizeFromCsv fnText ty env doc of
                Left e -> pure [Left (DataFileCoerceFailed fnText e)]
                Right l4Source ->
                  pure $ parseAndExtractTopDecls fnText uri l4Source

-- | Parse the data file using the parser appropriate to its extension.
parseFile :: Text -> Text -> Either CsvParseError CsvDoc
parseFile fname content
  | Text.isSuffixOf ".tsv" fname = parseTsv content
  | otherwise                     = parseCsv content

isSupportedExtension :: Text -> Bool
isSupportedExtension t = Text.isSuffixOf ".csv" t || Text.isSuffixOf ".tsv" t

-- | Re-parse the synthesized snippet and return its top-level
-- declarations, each wrapped in 'Right'. Parse failure indicates a
-- bug in the synthesizer (since it produced the source itself).
parseAndExtractTopDecls
  :: Text                       -- ^ originating filename, for diagnostics
  -> NormalizedUri              -- ^ URI of the importing module (reused as the synthetic module URI)
  -> Text                       -- ^ synthesized L4 source
  -> [Either DataImportError (TopDecl Name)]
parseAndExtractTopDecls fname uri src =
  case execProgramParserWithHintPass uri src of
    Left errs ->
      [Left $ DataFileSynthesisUnparseable fname
        [ msg | PError msg _ _ <- toList errs ]
      ]
    Right (MkModule _ _ (MkSection _ _ _ decls), _, _) ->
      map Right decls

-- ----------------------------------------------------------------------------
-- Small helpers
-- ----------------------------------------------------------------------------

-- | @concatMap id@ on a list whose elements are already lists,
-- but without forcing the caller to flatten manually.
concatMapPreserve :: [[a]] -> [a]
concatMapPreserve = concat

partitionEithers :: [Either a b] -> ([a], [b])
partitionEithers = foldr step ([], [])
  where
    step (Left  a) (as, bs) = (a : as, bs)
    step (Right b) (as, bs) = (as, b : bs)

