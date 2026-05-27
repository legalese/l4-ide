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
  , rewriteDataImports
  , DataImportError(..)
  ) where

import Base
import qualified Base.Text as Text
import qualified Data.Text as T

import L4.DataImport.Csv
import L4.DataImport.Synthesize
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
  | DataFileNoSchema !Text
    -- ^ The IMPORT lacked an @AS@ clause; auto-sense is not yet
    -- implemented.
  deriving stock (Eq, Show)

-- | Walk a parsed 'Module' and rewrite every 'MkDataImport' into the
-- corresponding 'Declare' + 'Decide' pair. Imports that are not
-- data imports (i.e. plain 'MkImport') are left untouched.
--
-- The pass is /shallow/: it only inspects top-level declarations. It
-- does not descend into nested sections (the parser doesn't currently
-- allow IMPORT statements inside sections anyway).
rewriteDataImports
  :: forall m. Monad m
  => DataFileLookup m
  -> Module Name
  -> m (Either [DataImportError] (Module Name))
rewriteDataImports lookupData (MkModule mAnn uri (MkSection sAnn sName sAka topdecls)) = do
  rewritten <- traverse (rewriteOne lookupData uri) topdecls
  let (errs, decls) = partitionEithers (concatMapPreserve rewritten)
  if null errs
    then pure $ Right $ MkModule mAnn uri (MkSection sAnn sName sAka decls)
    else pure $ Left errs

-- | Per-top-decl rewrite. A plain decl passes through as @Right [d]@;
-- a data import either expands to a list of synthesized decls or
-- contributes a 'Left' error. We use a list of 'Either' so that the
-- caller can collect errors across all imports rather than bailing on
-- the first.
rewriteOne
  :: Monad m
  => DataFileLookup m
  -> NormalizedUri
  -> TopDecl Name
  -> m [Either DataImportError (TopDecl Name)]
rewriteOne lookupData uri = \case
  Import iAnn (MkDataImport _ fnN schema _) ->
    expandDataImport lookupData uri iAnn fnN schema
  d ->
    pure [Right d]

-- ----------------------------------------------------------------------------
-- Per-import expansion
-- ----------------------------------------------------------------------------

expandDataImport
  :: Monad m
  => DataFileLookup m
  -> NormalizedUri
  -> Anno
  -> Name           -- ^ filename token
  -> DataImportSchema
  -> m [Either DataImportError (TopDecl Name)]
expandDataImport lookupData uri _iAnn fnN schema = do
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
              case synthesizeFromCsv fnText schema doc of
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

-- avoid an unused-import warning if T isn't referenced
_unusedT :: Text -> Text
_unusedT = T.strip
