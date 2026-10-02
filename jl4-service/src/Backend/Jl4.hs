{-# LANGUAGE ViewPatterns #-}
module Backend.Jl4 (createFunction, createRunFunctionFromCompiled, getFunctionDefinition, buildFunDecide, ModuleContext, CompiledModule(..), SharedModuleContext(..), precompileModule, buildSharedContext, buildCompiledFromShared, evaluateWithCompiled, evaluateWithCompiledDeontic, typecheckModule, buildImportEnvironment, typecheckAndEvalBundle, emptyEvalEnvironment) where

import Base hiding (trace)
import qualified Base.DList as DList
import qualified Base.Map as Map
import qualified Base.Text as Text

import L4.Annotation
-- import qualified L4.Evaluate.Value as Eval
import qualified L4.Evaluate.ValueLazy as Eval
import qualified L4.EvaluateLazy as Eval
import L4.EvaluateLazy.Machine (EvalException, emptyEnvironment, parseDateText, parseTimeText, parseDatetimeText)
import qualified L4.Evaluate.ValueLazy as EvalEnv (Environment)
import L4.EvaluateLazy.Trace
import qualified L4.EvaluateLazy.GraphViz2 as GraphViz
import L4.TracePolicy (apiDefaultPolicy, TracePolicy(..))
import qualified L4.TracePolicy as TracePolicy
import L4.Names
import L4.Print
import qualified L4.Print as Print
import L4.Syntax
import qualified L4.TypeCheck as TypeCheck
import L4.TypeCheck.Types (EntityInfo, Environment)
import L4.Utils.Ratio
import qualified LSP.Core.Shake as Shake
import Control.Exception (throwIO)
import EvalLimits (currentAllocationLimit)
import GHC.IO.Exception (AllocationLimitExceeded (..))
import LSP.L4.Oneshot (oneshotL4ActionAndErrors)
import qualified LSP.L4.Rules as Rules
import Optics ((^.), (%))

import Language.LSP.Protocol.Types (normalizedFilePathToUri, toNormalizedFilePath)
import System.FilePath ((<.>), takeFileName)
import qualified Data.Map.Strict as StrictMap
import qualified Data.Set as Set
import qualified L4.API.EmbeddedLibraries as EmbeddedLibraries

import Backend.Api
import Backend.CodeGen (generateEvalWrapper, generateDeonticEvalWrapper, GeneratedCode(..), AnswerShape(..), RequiredInput(..))
import L4.Export (AssumeRewrite(..), extractAssumeParamResolveds, rewriteModuleAssumes)
import L4.Discharge (Binder (..), sectionBinders)
import L4.Presumption
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Aeson
import qualified Data.Scientific as Scientific
import qualified Data.Vector as Vector
import Data.Either (lefts, rights)

-- | Map from file path to file content for module resolution
type ModuleContext = Map FilePath Text

-- | Pre-compiled L4 module ready for fast evaluation.
-- Note: source text and module context are intentionally NOT stored here.
-- They are stored once per deployment (not per function) and passed
-- explicitly to evaluation functions that need them, to avoid retaining
-- N copies across N compiled functions from the same file.
data CompiledModule = CompiledModule
  { compiledModule :: !(Module Resolved)
  , compiledEnvironment :: !Environment              -- ^ Typechecker environment (for type info)
  , compiledEntityInfo :: !EntityInfo
  , compiledDecide :: !(Decide Resolved)
  , compiledImportEnv :: !EvalEnv.Environment        -- ^ Evaluator environment from imports
  , compiledAllDeclares :: ![Declare Resolved]       -- ^ DECLAREs from the entry file AND every transitively-imported file.
                                                     -- Consulted by 'buildModuleInfo' so a record parameter
                                                     -- whose type is defined in an IMPORT'd file resolves —
                                                     -- the entry module's own 'flattenDeclares' wouldn't see it.
  }
  deriving (Generic)

-- | Empty evaluator environment (for files with no imports)
emptyEvalEnvironment :: EvalEnv.Environment
emptyEvalEnvironment = emptyEnvironment

-- | Shared context for all functions compiled from the same source file.
-- Stored once per file and referenced by each CompiledModule to avoid
-- duplicating the AST, environments, and source text per function.
data SharedModuleContext = SharedModuleContext
  { sharedModule :: !(Module Resolved)
  , sharedEnvironment :: !Environment
  , sharedEntityInfo :: !EntityInfo
  , sharedModuleContext :: !ModuleContext
  , sharedImportEnv :: !EvalEnv.Environment
  , sharedSource :: !Text
  , sharedAllDeclares :: ![Declare Resolved]
    -- ^ DECLAREs from the entry file + every transitively-imported
    --   file. Carried through into 'CompiledModule.compiledAllDeclares'
    --   so direct-AST evaluation can resolve cross-file record types.
  }

-- | Build shared context from an already-typechecked module.
-- Call once per source file, then use 'buildCompiledFromShared' per function.
buildSharedContext
  :: FilePath
  -> Text
  -> ModuleContext
  -> Module Resolved
  -> Environment
  -> EntityInfo
  -> IO SharedModuleContext
buildSharedContext filepath source moduleContext resolvedModule env entityInfo = do
  importEnv <- buildImportEnvironment filepath source moduleContext entityInfo
  pure SharedModuleContext
    { sharedModule = resolvedModule
    , sharedEnvironment = env
    , sharedEntityInfo = entityInfo
    , sharedModuleContext = moduleContext
    , sharedImportEnv = importEnv
    , sharedSource = source
    -- Fallback path (single-file compile, no bundle info): the best we
    -- can do is the entry module's own DECLAREs. The bundle-compile
    -- path in Compiler.hs overrides this with the full cross-file set
    -- via 'buildSharedContextWithDeclares'.
    , sharedAllDeclares = moduleDeclaresOnly resolvedModule
    }

-- | Build a CompiledModule for a single function, reusing shared context.
-- Only extracts the function-specific Decide; everything else is shared.
buildCompiledFromShared :: SharedModuleContext -> RawName -> IO (Either Text CompiledModule)
buildCompiledFromShared shared funName = runExceptT $ do
  decide <- withExceptT evalErrorToText $ getFunctionDefinition funName shared.sharedModule
  pure CompiledModule
    { compiledModule = shared.sharedModule
    , compiledEnvironment = shared.sharedEnvironment
    , compiledEntityInfo = shared.sharedEntityInfo
    , compiledDecide = decide
    , compiledImportEnv = shared.sharedImportEnv
    , compiledAllDeclares = shared.sharedAllDeclares
    }
 where
  evalErrorToText :: EvaluatorError -> Text
  evalErrorToText (InterpreterError t) = t
  evalErrorToText (EvaluatorRefused reason _) = "The model refuses to answer: " <> reason
  evalErrorToText (EvaluatorLimited _ msg) = msg
  evalErrorToText (RequiredParameterMissing pm) = "Required parameter missing: expected " <> Text.textShow pm.expected <> ", got " <> Text.textShow pm.actual
  evalErrorToText (UnknownArguments args) = "Unknown arguments: " <> Text.intercalate ", " args
  evalErrorToText (CannotHandleParameterType lit) = "Cannot handle parameter type: " <> Text.textShow lit
  evalErrorToText CannotHandleUnknownVars = "Cannot handle unknown variables"

-- | Typecheck and evaluate all files in a bundle in a SINGLE Shake session.
-- This avoids creating N independent IDE sessions that redundantly re-parse
-- and re-typecheck overlapping imports. Shake caches intermediate results
-- (parse, import resolution, typecheck) and shares them across all files.
--
-- Returns per-file typecheck results and per-file evaluator environments
-- (for files that have exports and need import environments).
typecheckAndEvalBundle
  :: ModuleContext
  -- ^ All source files in the bundle (filepath -> content)
  -> [FilePath]
  -- ^ Files that need evaluator import environments (i.e., files with exports).
  -- Pass empty list to skip evaluation entirely (typecheck only).
  -> IO ( [Text]
        -- ^ Diagnostic/error messages from the session
        , Map FilePath (Maybe Rules.TypeCheckResult)
        -- ^ Typecheck results per file (Nothing if typecheck failed)
        , Map FilePath EvalEnv.Environment
        -- ^ Evaluator import environments for requested files
        )
typecheckAndEvalBundle moduleContext evalFiles = do
  fixedNow <- Eval.readFixedNowEnv
  evalConfig <- Eval.resolveEvalConfig fixedNow apiDefaultPolicy

  -- Core libraries (prelude, …) to register as stable virtual files, unless the
  -- deployment ships its own copy of the same name (which then shadows the
  -- embedded one). Registering them up front means `IMPORT prelude` resolves via
  -- the VFS, instead of the resolver's on-demand embedded fallback
  -- (LSP.L4.Rules). That fallback used to mutate the VFS mid-rule and — under
  -- -O, in the multi-pass compileBundle/eval path — yielded an
  -- unstable/duplicate prelude module and spurious overload ambiguity (e.g.
  -- `count xs >= n` → "ambiguous __GEQ__"). Verified: the same source is
  -- rejected via the embedded fallback and accepted when the library is a real
  -- virtual file. The libraries stay *dependencies* (NOT added to `allUris`),
  -- so they are never serialized or surfaced as deployment files — only
  -- resolved when imported.
  --
  -- They are registered at `Shake.embeddedLibraryUri`, the one URI the resolver
  -- hands back for an embedded winner. Registering them anywhere else would
  -- give a bundle two `prelude` modules whenever some importer resolves via the
  -- VFS tier and another falls through to the embedded tier — which is how the
  -- duplicate-module ambiguity above arises.
  let bundleBasenames = Set.fromList (map takeFileName (StrictMap.keys moduleContext))
      embeddedLibFiles =
        [ (name, content)
        | (name, content) <- StrictMap.toList EmbeddedLibraries.embeddedLibraries
        , not ((Text.unpack name <.> "l4") `Set.member` bundleBasenames)
        ]

  -- Use the first file's directory as the session root (arbitrary but required)
  let allFiles = StrictMap.toList moduleContext
  case allFiles of
    [] -> pure ([], StrictMap.empty, StrictMap.empty)
    ((firstPath, _) : _) -> do
      (errs, (tcMap, evalMap)) <- oneshotL4ActionAndErrors evalConfig firstPath $ \_nfp -> do
        -- Register ALL bundle files as virtual files in one go.
        -- Use the full path from the bundle (not just the basename) to avoid
        -- collisions when multiple files share the same filename in different dirs.
        fileNfps <- forM allFiles $ \(path, content) -> do
          let nfp = toNormalizedFilePath ("./" <> path)
          _ <- Shake.addVirtualFile nfp content
          pure (path, nfp, normalizedFilePathToUri nfp)

        -- Register embedded core libraries as stable virtual files (dependencies
        -- only — deliberately NOT added to allUris, see note above).
        forM_ embeddedLibFiles $ \(libName, content) ->
          void $ Shake.addVirtualFileUri (Shake.embeddedLibraryUri libName) content

        -- Typecheck ALL bundle files in one batch — Shake shares import resolution
        let allUris = [uri | (_, _, uri) <- fileNfps]
        tcResults <- Shake.uses Rules.TypeCheck allUris

        let tcMap = StrictMap.fromList
              [(path, mTc) | ((path, _, _), mTc) <- zip fileNfps (toList tcResults)]

        -- Build evaluator import environments for files that need them.
        -- Uses GetLazyEvaluationDependencies which recursively evaluates imports.
        -- Within the same session, Shake reuses already-evaluated imports: the
        -- rule ignores the call stack in its key and evaluates each file once
        -- (GetLazyEvaluationDependenciesFile, smucclaw/l4-ide#1008). Before
        -- that, the stack made each file's imports separate keys, and nothing
        -- was shared between bundle files.
        let evalUriMap = [(path, uri) | (path, _, uri) <- fileNfps
                                      , path `elem` evalFiles]
        evalPairs <- forM evalUriMap $ \(path, uri) -> do
          mResult <- Shake.use (Shake.AttachCallStack [uri] Rules.GetLazyEvaluationDependencies) uri
          pure (path, mResult)

        let evalMap = StrictMap.fromList
              [ (path, env)
              | (path, Just (env, _dirResults)) <- evalPairs
              ]

        pure (tcMap, evalMap)

      pure (errs, tcMap, evalMap)

buildFunDecide :: Text -> FunctionDeclaration -> ExceptT EvaluatorError IO (Decide Resolved)
buildFunDecide fnImpl fnDecl = do
  (initErrs, mTcRes) <- typecheckModule file fnImpl Map.empty

  tcRes <- case mTcRes of
    Nothing -> throwError $ InterpreterError (mconcat initErrs)
    Just tcRes -> pure tcRes

  getFunctionDefinition funRawName tcRes.module'
 where
  file = Text.unpack fnDecl.name <.> "l4"
  funRawName = mkNormalName fnDecl.name

-- | Precompile an L4 module for fast repeated evaluation
precompileModule
  :: FilePath
  -> Text
  -> ModuleContext
  -> RawName
  -> IO (Either Text CompiledModule)
precompileModule filepath source moduleContext funName = runExceptT $ do
  -- Parse and typecheck once
  (errs, mTcRes) <- liftIO $ typecheckModule filepath source moduleContext
  tcRes <- case mTcRes of
    Nothing -> throwError $ mconcat errs
    Just tcRes -> pure tcRes

  -- Extract the function definition
  decide <- withExceptT evalErrorToText $ getFunctionDefinition funName tcRes.module'

  -- Pre-evaluate import dependencies to get the evaluator Environment
  -- This is needed because execEvalExprInContextOfModule expects the import
  -- environment to be pre-computed (it only evaluates the current module fresh)
  importEnv <- liftIO $ buildImportEnvironment filepath source moduleContext tcRes.entityInfo

  -- Build the compiled module. precompileModule is the single-file
  -- fallback — bundle compilation populates `compiledAllDeclares` from
  -- the full import graph in Compiler.hs. Here we only have the entry
  -- module's AST, so we fall back to its own declarations; that's the
  -- best we can do without re-running the whole bundle typecheck.
  pure CompiledModule
    { compiledModule = tcRes.module'
    , compiledEnvironment = tcRes.environment
    , compiledEntityInfo = tcRes.entityInfo
    , compiledDecide = decide
    , compiledImportEnv = importEnv
    , compiledAllDeclares = moduleDeclaresOnly tcRes.module'
    }
 where
  evalErrorToText :: EvaluatorError -> Text
  evalErrorToText (InterpreterError t) = t
  evalErrorToText (EvaluatorRefused reason _) = "The model refuses to answer: " <> reason
  evalErrorToText (EvaluatorLimited _ msg) = msg
  evalErrorToText (RequiredParameterMissing pm) = "Required parameter missing: expected " <> Text.textShow pm.expected <> ", got " <> Text.textShow pm.actual
  evalErrorToText (UnknownArguments args) = "Unknown arguments: " <> Text.intercalate ", " args
  evalErrorToText (CannotHandleParameterType lit) = "Cannot handle parameter type: " <> Text.textShow lit
  evalErrorToText CannotHandleUnknownVars = "Cannot handle unknown variables"

-- ----------------------------------------------------------------------------
-- Direct AST evaluation (avoiding text round-trip)
-- ----------------------------------------------------------------------------

-- | Integer literal shortcut.
numLit :: Int -> Expr Resolved
numLit n = Lit emptyAnno (NumericLit emptyAnno (fromIntegral n))

-- | Is this 'Type' Resolved' a nullary application of the given
-- built-in 'Unique'? Works for DATE / TIME / DATETIME / NUMBER / etc.
isTypeUnique :: Unique -> Type' Resolved -> Bool
isTypeUnique u (TyApp _ name _) = getUnique name == u
isTypeUnique _ _                = False

-- | Parse 'YYYY-MM-DD' (optionally followed by more characters, which
-- are ignored). Returns '(year, month, day)'.
parseIsoDate :: Text -> Maybe (Int, Int, Int)
parseIsoDate t = do
  let prefix = Text.take 10 t
  case Text.splitOn "-" prefix of
    [ys, ms, ds] -> do
      y <- readInt ys
      m <- readInt ms
      d <- readInt ds
      pure (y, m, d)
    _ -> Nothing

-- | Parse 'HH:MM[:SS[.fraction]]'. Ignores trailing timezone suffix.
parseIsoTime :: Text -> Maybe (Int, Int, Int)
parseIsoTime t = case Text.splitOn ":" (Text.takeWhile (\c -> c /= ' ' && c /= '+' && c /= 'Z') t) of
  [hs, ms]      -> do
    h <- readInt hs
    m <- readInt ms
    pure (h, m, 0)
  [hs, ms, ss]  -> do
    h  <- readInt hs
    m  <- readInt ms
    s  <- readInt (Text.takeWhile (/= '.') ss)
    pure (h, m, s)
  _ -> Nothing

-- | Parse a range of common ISO-8601-ish datetime strings. The
-- returned timezone is either the explicit IANA name, a '±HH:MM'
-- offset as text, or 'UTC' as a fallback. Supports both
-- 'YYYY-MM-DDTHH:MM:SSZ' and the service's 'YYYY-MM-DD HH:MM:SS UTC'
-- output shape.
parseIsoDatetime :: Text -> Maybe ((Int, Int, Int), (Int, Int, Int), Text)
parseIsoDatetime t = do
  (y, m, d) <- parseIsoDate t
  let afterDate = Text.drop 10 t
  let afterSep  = if Text.null afterDate
                    then afterDate
                    else if Text.head afterDate == 'T' || Text.head afterDate == ' '
                           then Text.drop 1 afterDate
                           else afterDate
  (h, mi, s) <- parseIsoTime afterSep
  let tzPart = Text.dropWhile (\c -> c /= ' ' && c /= 'Z' && c /= '+' && c /= '-') (Text.drop 8 afterSep)
      tz     = case Text.strip tzPart of
                 "" -> "UTC"
                 "Z" -> "UTC"
                 other -> other
  pure ((y, m, d), (h, mi, s), tz)

readInt :: Text -> Maybe Int
readInt t = case reads (Text.unpack t) of
  [(n, "")] -> Just n
  _ -> Nothing

-- | Cache of record / enum type information gathered once from the
-- typechecked 'Module Resolved'. Used by 'fnLiteralToExprTyped' to
-- convert 'FnObject' into @App recordCtorRef [fieldExpr,...]@ (in
-- declaration order) and 'FnLitString' into an enum constructor ref
-- when the expected type is an enum.
data ModuleInfo = ModuleInfo
  { miRecords      :: Map Unique (Resolved, [(Text, Type' Resolved, Maybe (Expr Resolved))])
    -- ^ record type unique -> (type-constructor ref, [(field name, field type, its TYPICALLY)])
  , miEnumVariants :: Map Unique [(Text, Resolved)]
    -- ^ enum type unique -> [(variant name, variant constructor ref)]
  , miSynonyms     :: Map Unique ([Unique], Type' Resolved)
    -- ^ synonym type unique -> (its parameters, its body)
  }

-- | Flatten a module's own top-level + nested DECLAREs. Does not
-- follow IMPORTs — use 'compiledAllDeclares' (populated at bundle
-- compile time) when cross-file types need to resolve.
moduleDeclaresOnly :: Module Resolved -> [Declare Resolved]
moduleDeclaresOnly (MkModule _ _ section) = flattenDeclares section
  where
    flattenDeclares :: Section Resolved -> [Declare Resolved]
    flattenDeclares (MkSection _ _ _ _ decls) = concatMap step decls
      where
        step (Declare _ d)  = [d]
        step (Section _ s') = flattenDeclares s'
        step _              = []

buildModuleInfo :: [Declare Resolved] -> ModuleInfo
buildModuleInfo decls = ModuleInfo
  { miRecords      = Map.fromList [ r | Just r <- map recordFor decls ]
  , miEnumVariants = Map.fromList [ r | Just r <- map enumFor   decls ]
  , miSynonyms     = Map.fromList
      [ (getUnique tyName, (map getUnique params, body))
      | MkDeclare _ _ (MkAppForm _ tyName params _) (SynonymDecl _ body) <- decls ]
  }
  where

    recordFor :: Declare Resolved -> Maybe (Unique, (Resolved, [(Text, Type' Resolved, Maybe (Expr Resolved))]))
    -- A 'RecordDecl' carries its value-level constructor in the 'Maybe n'
    -- slot — *not* the type name in the outer 'AppForm'. The evaluator
    -- binds the record builder under that constructor's unique in
    -- 'evalConDecl', so we key our cache off the type name but build the
    -- 'App' using the constructor Resolved.
    recordFor (MkDeclare _ _ (MkAppForm _ tyName _ _) (RecordDecl _ (Just ctor) fields)) =
      Just (getUnique tyName, (ctor, map fieldOf fields))
      where
        fieldOf (MkTypedName _ fn fty mTypically _) = (rawNameToText (rawName (getActual fn)), fty, mTypically)
    recordFor _ = Nothing

    enumFor :: Declare Resolved -> Maybe (Unique, [(Text, Resolved)])
    enumFor (MkDeclare _ _ (MkAppForm _ tyName _ _) (EnumDecl _ ctors)) =
      Just (getUnique tyName, map ctorOf ctors)
      where
        ctorOf (MkConDecl _ c _) = (rawNameToText (rawName (getActual c)), c)
    enumFor _ = Nothing

-- | Is this @TyApp@ the built-in MAYBE / LIST type?
stripMaybe :: Type' Resolved -> Maybe (Type' Resolved)
stripMaybe (TyApp _ name [inner]) | getUnique name == TypeCheck.maybeUnique = Just inner
stripMaybe _ = Nothing

stripList :: Type' Resolved -> Maybe (Type' Resolved)
stripList (TyApp _ name [inner]) | getUnique name == TypeCheck.listUnique = Just inner
stripList _ = Nothing

-- | A type with its synonyms expanded at the head, so that a synonym for MAYBE
-- is a MAYBE when deciding what a missing or @null@ value means (T3), and a
-- synonym for a record or an enum is found. The JSON decoder does the same
-- ('L4.EvaluateLazy.Machine.expandTypeSynonyms').
expandSyn :: ModuleInfo -> Type' Resolved -> Type' Resolved
expandSyn mi = go (16 :: Int)
  where
    go 0 ty = ty
    go n ty@(TyApp _ name args)
      | Just (params, body) <- Map.lookup (getUnique name) mi.miSynonyms
      , length params == length args =
          go (n - 1) (subst (Map.fromList (zip params args)) body)
      | otherwise = ty
    go _ ty = ty
    subst sub = \case
      TyApp ann r []
        | Just t <- Map.lookup (getUnique r) sub -> t
        | otherwise -> TyApp ann r []
      TyApp ann r ts -> TyApp ann r (map (subst sub) ts)
      other -> other

-- | Look up an enum or record type by unique.
lookupEnum :: ModuleInfo -> Type' Resolved -> Maybe [(Text, Resolved)]
lookupEnum mi (TyApp _ name _) = Map.lookup (getUnique name) mi.miEnumVariants
lookupEnum _ _                 = Nothing

lookupRecord :: ModuleInfo -> Type' Resolved -> Maybe (Resolved, [(Text, Type' Resolved, Maybe (Expr Resolved))])
lookupRecord mi (TyApp _ name _) = Map.lookup (getUnique name) mi.miRecords
lookupRecord _ _                 = Nothing

-- | A @TYPICALLY@ default the direct path filled at the root, for an input
-- (or a record field inside one) the request left out (W3, T1b). It becomes a
-- 0-ary definition added to the module, and the input refers to it, so that
-- the evaluator reports the default when, and only when, it is forced (T6;
-- 'L4.EvaluateLazy.RootFills').
data RootFill = RootFill
  { fillRef      :: Resolved
  , fillBody     :: Expr Resolved
  , fillPresumed :: Eval.Presumed
  }

-- | Converting a request's values to AST, collecting the root fills it made.
-- The 'Int' numbers the fills, so that each gets its own 'Unique'.
type Fills = StateT (Int, [RootFill]) (Either Text)

fillError :: Text -> Fills a
fillError = lift . Left

-- | Where fills are minted, and whether they may be (T4).
data FillCtx = FillCtx
  { fcSoft :: Bool
  , fcUri  :: NormalizedUri
  }

-- | Fill a default at the root: a fresh 0-ary definition holding it, which
-- the input refers to.
rootFill :: FillCtx -> [Text] -> Expr Resolved -> Fills (Expr Resolved)
rootFill ctx path d = do
  (i, fills) <- get
  let -- Sort char @'p'@: no other minter uses it (see the list in
      -- 'L4.Discharge.dischargeModule'), so a fill cannot collide with a name
      -- the module already has.
      ref = Def (MkUnique 'p' i ctx.fcUri)
              (MkName emptyAnno (NormalName ("presumed " <> Eval.renderPresumedPath path)))
      fill = RootFill
        { fillRef = ref
        , fillBody = d
        , fillPresumed = Eval.MkPresumed
            { Eval.path = path
            , Eval.declaredAt = rangeOf d
            , Eval.origin = Eval.FromRootFill
            }
        }
  put (i + 1, fill : fills)
  pure (App emptyAnno ref [])

-- | What a request said about one input ('L4.Presumption.Supplied'): nothing
-- (the key is absent), @null@, or a value. Absent and @null@ differ: absent
-- may take a default, and @null@ never does (T3). The request map keeps the
-- difference from the wire: @"x": null@ is a key with no value.
suppliedIn :: Map Text (Maybe FnLiteral) -> Text -> Supplied FnLiteral
suppliedIn m name = case Map.lookup name m of
  Nothing       -> Absent
  Just Nothing  -> SuppliedNull "null"
  Just (Just v) -> suppliedValue v

-- | A value inside a request: @null@ and @{}@ are "not known" (T3).
suppliedValue :: FnLiteral -> Supplied FnLiteral
suppliedValue = \case
  FnUnknown   -> SuppliedNull "null"
  FnUncertain -> SuppliedNull "{}"
  v           -> Supplied v

-- | Convert one top-level input of the request, filling its default if it is
-- absent, has one, and presumption is soft. The decision is
-- 'L4.Presumption.fillDecision', the one the JSON decoder takes; this path
-- carries it out with root fills instead of a decoded record. Messages lead
-- with @label@ (\"Parameter 'x'\").
rootInputExpr
  :: ModuleInfo
  -> FillCtx
  -> Map Text (Expr Resolved)   -- ^ the defaults a request may leave an input out for
  -> Text                       -- ^ how a message names the input
  -> Text
  -> Type' Resolved
  -> Supplied FnLiteral
  -> Fills (Expr Resolved)
rootInputExpr mi ctx defaults label name ty0 supplied =
  case fillDecision ctx.fcSoft (isJust (stripMaybe ty)) (Map.lookup name defaults) supplied of
    UseDefault d                   -> rootFill ctx [name] d
    -- D7.3's NOTHING for a MAYBE input left out is a presumption too (T1b
    -- puts it under the switch), so it is filled, and reported, the same way.
    UseNothing                     -> rootFill ctx [name] nothingExpr
    NullIsNothing                  -> pure nothingExpr
    RefuseMissing why              -> fillError (label <> ": missing required parameter" <> withheldText why)
    RefuseNull spelling hasDefault -> fillError (label <> " " <> nullRefusalText spelling hasDefault)
    UseValue                       -> case supplied of
      Supplied v -> withPrefix (label <> ": ") (fnLiteralToExprTyped mi ctx [name] ty (Just v))
      _          -> fillError (label <> ": missing required parameter")
  where
    ty = expandSyn mi ty0

-- | Prefix a conversion's failure.
withPrefix :: Text -> Fills a -> Fills a
withPrefix prefix act = StateT \ st -> either (Left . (prefix <>)) Right (runStateT act st)

nothingExpr :: Expr Resolved
nothingExpr = App emptyAnno TypeCheck.nothingRef []

-- | Run a conversion, keeping its failure as a value, so that every input's
-- failure can be reported together rather than only the first.
attempt :: Fills a -> Fills (Either Text a)
attempt act = StateT \ st -> case runStateT act st of
  Left err       -> Right (Left err, st)
  Right (a, st') -> Right (Right a, st')

-- | Convert an 'FnLiteral' (possibly missing) to an L4 AST expression
-- that matches the expected 'Type' Resolved'. Handles MAYBE wrapping /
-- unwrapping, record construction (via declaration-order field lookup),
-- enum constructor coercion from 'FnLitString', and nested lists /
-- records. Fails for cases that can't be represented as a pure
-- AST value ('FnUnknown' / 'FnUncertain' against a non-MAYBE type); such a
-- failure is a refusal, not a fallback. With 'requiresWrapperEvaluation' in
-- front, a request holding either value does not get here.
--
-- A record field the value leaves out takes its @DECLARE@'s @TYPICALLY@ while
-- presumption is soft (T1b), as a root fill named by its path.
fnLiteralToExprTyped
  :: ModuleInfo
  -> FillCtx
  -> [Text]          -- ^ the path to this value, from the request's argument
  -> Type' Resolved
  -> Maybe FnLiteral
  -> Fills (Expr Resolved)
fnLiteralToExprTyped mi ctx path ty0 mVal
  -- MAYBE type: map missing / null / explicit NOTHING literal to NOTHING,
  -- anything else to JUST <recurse with inner type>.
  | Just inner <- stripMaybe ty =
      case mVal of
        Nothing                  -> pure (App emptyAnno TypeCheck.nothingRef [])
        Just FnUnknown           -> pure (App emptyAnno TypeCheck.nothingRef [])
        Just (FnLitString "NOTHING") ->
          pure (App emptyAnno TypeCheck.nothingRef [])
        Just v -> do
          e <- fnLiteralToExprTyped mi ctx path inner (Just v)
          pure (App emptyAnno TypeCheck.justRef [e])
  | otherwise = case mVal of
      Nothing          -> fillError "missing required parameter"
      Just FnUnknown   -> fillError "unknown value for a non-MAYBE parameter"
      Just FnUncertain -> fillError "uncertain value is not supported in direct evaluation"
      Just v           -> nonMaybeValue mi ctx path ty v
  where
    ty = expandSyn mi ty0

nonMaybeValue
  :: ModuleInfo
  -> FillCtx
  -> [Text]
  -> Type' Resolved
  -> FnLiteral
  -> Fills (Expr Resolved)
nonMaybeValue mi ctx path ty = \case
  FnLitInt i     -> pure (Lit emptyAnno (NumericLit emptyAnno (fromIntegral i)))
  FnLitDouble d  -> pure (Lit emptyAnno (NumericLit emptyAnno
                            (toRational (Scientific.fromFloatDigits d))))
  FnLitBool True  -> pure (App emptyAnno TypeCheck.trueRef [])
  FnLitBool False -> pure (App emptyAnno TypeCheck.falseRef [])
  FnLitString s
    -- If the expected type is an enum, resolve the string to a variant.
    | Just variants <- lookupEnum mi ty ->
        case lookup s variants of
          Just ref -> pure (App emptyAnno ref [])
          Nothing  -> fillError ("unknown enum variant: " <> s)
    -- ISO date / time / datetime strings against a temporal parameter.
    -- The wire format mirrors JSON Schema ('date', 'time', 'date-time'
    -- formats); parse here and emit the primitive constructor so the
    -- evaluator sees a real temporal value instead of a rejected
    -- STRING literal.
    | isTypeUnique TypeCheck.dateUnique ty, Just (y, m, d) <- parseIsoDate s ->
        pure (App emptyAnno TypeCheck.dateFromDMYRef
                 [numLit d, numLit m, numLit y])
    | isTypeUnique TypeCheck.timeUnique ty, Just (h, m, sec) <- parseIsoTime s ->
        pure (App emptyAnno TypeCheck.timeFromHMSRef
                 [numLit h, numLit m, numLit sec])
    | isTypeUnique TypeCheck.datetimeUnique ty
    , Just ((yy, mo, dd), (hh, mn, ss), tz) <- parseIsoDatetime s ->
        pure (App emptyAnno TypeCheck.datetimeFromDTZRef
                 [ App emptyAnno TypeCheck.dateFromDMYRef [numLit dd, numLit mo, numLit yy]
                 , App emptyAnno TypeCheck.timeFromHMSRef [numLit hh, numLit mn, numLit ss]
                 , Lit emptyAnno (StringLit emptyAnno tz)
                 ])
    -- Otherwise treat as a plain STRING literal.
    | otherwise -> pure (Lit emptyAnno (StringLit emptyAnno s))
  FnArray xs ->
    case stripList ty of
      Just elemTy ->
        List emptyAnno <$> traverse
          (\ (i, v) -> fnLiteralToExprTyped mi ctx (path <> ["[" <> Text.textShow i <> "]"]) elemTy (Just v))
          (zip [0 :: Int ..] xs)
      Nothing     -> fillError "FnArray but expected type is not LIST"
  FnObject fields
    | Just (ctorRef, decl) <- lookupRecord mi ty -> do
        -- Walk the record's fields in declaration order and pick each
        -- value from the supplied FnObject, by the same decision the JSON
        -- decoder takes for a field ('L4.Presumption.fillDecision'): a field
        -- left out takes its TYPICALLY, or a MAYBE NOTHING, while presumption
        -- is soft (T1b); one that nothing fills is refused, by its path.
        let fieldMap = Map.fromList fields
            decided =
              [ (fname, fty, fieldPath, fillDecision ctx.fcSoft (isJust (stripMaybe fty)) mDefault given)
              | (fname, fty0, mDefault) <- decl
              , let fieldPath = path <> [fname]
                    fty       = expandSyn mi fty0
                    given     = maybe Absent suppliedValue (Map.lookup fname fieldMap)
              ]
            -- where a field left out takes its default, a key that matches no
            -- field is refused, as the JSON decoder refuses it (review M1;
            -- decided overnight 2026-10-02, pending Meng's review)
            declNames = [ f | (f, _, _) <- decl ]
            unknown   = [ k | (k, _) <- fields, k `notElem` declNames ]
            pathTo k  = Eval.renderPresumedPath (path <> [k])
            tookDefault = or [ True | (_, _, _, UseDefault _) <- decided ]
        when (tookDefault && not (null unknown)) $
          fillError (unrecognisedMessage "field" [ (pathTo k, pathTo <$> nearestName k declNames) | k <- unknown ])
        argExprs <- forM decided $ \(fname, fty, fieldPath, decision) -> do
          let fieldTxt  = "field '" <> Eval.renderPresumedPath fieldPath <> "'"
          case decision of
            UseDefault d                   -> rootFill ctx fieldPath d
            UseNothing                     -> rootFill ctx fieldPath nothingExpr
            NullIsNothing                  -> pure nothingExpr
            RefuseMissing why              -> fillError (fieldTxt <> " is missing" <> withheldText why)
            RefuseNull spelling hasDefault -> fillError (fieldTxt <> " " <> nullRefusalText spelling hasDefault)
            UseValue                       -> fnLiteralToExprTyped mi ctx fieldPath fty (Map.lookup fname fieldMap)
        pure (App emptyAnno ctorRef argExprs)
    | otherwise ->
        fillError "FnObject but expected type is not a known record"
  FnUnknown   -> fillError "unknown value for a non-MAYBE parameter"
  FnUncertain -> fillError "uncertain value is not supported in direct evaluation"

-- | Get the function's Resolved name from the compiled decide
getFunctionResolved :: Decide Resolved -> Resolved
getFunctionResolved (MkDecide _ _ (MkAppForm _ funName _ _) _) = funName

-- | Build the function call expression from function name and argument expressions
-- Arguments must be in the correct order (matching the function signature)
buildFunctionCallExpr :: Resolved -> [Expr Resolved] -> Expr Resolved
buildFunctionCallExpr funName args =
  App emptyAnno funName args

-- | In 'evaluateWithCompiled', whether a request takes the wrapper path:
-- when any supplied value holds an 'FnUncertain' (@{}@) or an 'FnUnknown'
-- (@null@), anywhere in it, the top level included, and in a slot of any
-- type. The test is conservative: the direct path could express some of
-- these (a @null@ in a MAYBE slot is NOTHING in 'fnLiteralToExprTyped'), but
-- not all. It handles everything else, records, enums and lists included.
-- A DEONTIC function called on @/evaluation@, and a module that did not
-- precompile, take the wrapper path whatever this says
-- ('evaluateWithCompiledDeontic', 'createFunction'); MCP and batch call a
-- DEONTIC function through 'evaluateWithCompiled' like any other.
--
-- A 'Nothing' does not take it. That is a parameter left out, a top-level
-- @null@ on the single evaluation endpoint, which 'FnArguments' decodes as a
-- key with no value, or an MCP argument that fails to parse
-- ('parseFnLiteral'). The direct path then fills the input's default, makes
-- a MAYBE NOTHING, or refuses it ('L4.Presumption.fillDecision'). MCP and
-- the batch endpoint decode a top-level @null@ as 'FnUnknown' instead, so
-- they take the wrapper path for it (smucclaw/l4-ide#1021).
requiresWrapperEvaluation :: [(Text, Maybe FnLiteral)] -> Bool
requiresWrapperEvaluation = any (\(_, mVal) -> maybe False needsWrapper mVal)
  where
    needsWrapper :: FnLiteral -> Bool
    needsWrapper FnUncertain    = True
    needsWrapper FnUnknown      = True
    needsWrapper (FnArray xs)   = any needsWrapper xs
    needsWrapper (FnObject kvs) = any (needsWrapper . snd) kvs
    needsWrapper _              = False

-- | The defaults a request may leave an input out for, by input name: the
-- export's own GIVENs that carry a TYPICALLY, and the section GIVENs it reads
-- that carry one (W3 of specs/todo/TYPICALLY-ONE-BEHAVIOUR-SPEC.md). A written
-- ASSUME's TYPICALLY is not one yet, because @#EVAL@ does not honour it either
-- (W6; 'L4.Export.honouredDefault').
inputDefaults :: Module Resolved -> Decide Resolved -> Map Text (Expr Resolved)
inputDefaults m decide@(MkDecide _ (MkTypeSig _ (MkGivenSig _ otns) _) _ _) =
  Map.fromList $
    [ (nameText r, d) | MkOptionallyTypedName _ r _ (Just d) <- otns ]
    <> [ (nameText r, d)
       | (r, _) <- extractAssumeParamResolveds m decide
       , Just b <- [Map.lookup (getUnique r) binders]
       , Just d <- [b.typically]
       ]
  where
    binders = sectionBinders m
    nameText r = rawNameToText (rawName (getActual r))

-- | Where an input left out of the request takes its default (presumption
-- soft), an argument that names no input is refused, naming it and the
-- nearest input, rather than ignored: it may misspell the input left out,
-- which would otherwise take its default with no error (review M1; decided
-- overnight 2026-10-02, pending Meng's review, spec §4.1). Where no default is
-- taken, an unknown argument is ignored as before. Checked once for the
-- request's top level on every path; the decoders check the records inside.
refuseUnknownArguments
  :: Monad m
  => Presumption
  -> Map Text (Expr Resolved)   -- ^ the defaults a request may leave an input out for
  -> [Text]                     -- ^ the inputs, in declaration order
  -> [(Text, Maybe FnLiteral)]
  -> ExceptT EvaluatorError m ()
refuseUnknownArguments presumption defaults inputs params =
  when (tookDefault && not (null unknown)) $
    throwError $ InterpreterError $
      unrecognisedMessage "parameter" [ (k, nearestName k inputs) | k <- unknown ]
  where
    given       = map fst params
    tookDefault = presumption == PresumeSoft && any (`notElem` given) (Map.keys defaults)
    unknown     = [ k | k <- given, k `notElem` inputs ]

-- | A function's inputs in declaration order: its GIVENs, then the ASSUMEs
-- (section GIVENs included) it reads.
inputNames :: Module Resolved -> Decide Resolved -> [Text]
inputNames m decide =
  map fst (extractParamTypes decide)
    <> [ rawNameToText (rawName (getActual r)) | (r, _) <- extractAssumeParamResolveds m decide ]

-- | Every input name a function takes: its GIVENs and the ASSUMEs (section
-- GIVENs included) it reads.
functionInputs :: CompiledModule -> Set.Set Text
functionInputs compiled =
  Set.fromList $
    map fst (extractParamTypes compiled.compiledDecide)
    <> [ rawNameToText (rawName (getActual r))
       | (r, _) <- extractAssumeParamResolveds compiled.compiledModule compiled.compiledDecide ]

-- | The evaluator's configuration for one request: the presumption switch
-- (T4) goes to discharge and the JSON decoder alike. A wrapper decodes the
-- request into 'requestRecordName', and that decode is the one the switch
-- reaches (T4b); the direct path has no request decode.
requestEvalConfig :: TracePolicy -> Presumption -> Bool -> IO Eval.EvalConfig
requestEvalConfig policy presumption viaWrapper = do
  fixedNow <- Eval.readFixedNowEnv
  cfg <- Eval.resolveEvalConfig fixedNow policy
  -- Only the wrapper path evaluates off the calling thread (a Shake rule), so
  -- only there does the evaluator have to set the allocation limit itself;
  -- the direct path runs under the counter 'withEvalLimits' set, and setting
  -- it again would reset that counter (smucclaw/l4-ide#1018).
  limit <- if viaWrapper
    then do
      mBytes <- currentAllocationLimit
      for mBytes \bytes -> Eval.MkAllocationLimit bytes <$> newIORef False
    else pure Nothing
  pure cfg
    { Eval.presumeDefaults = presumption == PresumeSoft
    , Eval.requestRecord   = if viaWrapper then Just requestRecordName else Nothing
    , Eval.allocationLimit = limit
    }

-- | Evaluate using precompiled module (fast path) - direct AST evaluation
-- This avoids the text round-trip through prettyLayout and re-parsing
-- Sends a request to the wrapper path instead when it holds a @{}@ anywhere,
-- or a @null@ the decoder kept as a value: inside a record or list, or at
-- the top level from MCP and batch ('requiresWrapperEvaluation').
evaluateWithCompiled
  :: FilePath
  -> FunctionDeclaration
  -> CompiledModule
  -> Text  -- ^ Original source text (for wrapper fallback)
  -> ModuleContext  -- ^ Module context (for wrapper fallback IMPORT resolution)
  -> [(Text, Maybe FnLiteral)]
  -> TraceLevel
  -> Bool
  -> Presumption
  -> ExceptT EvaluatorError IO ResponseWithReason
evaluateWithCompiled filepath fnDecl compiled sourceText modContext params traceLevel includeGraphViz presumption = do
  -- One entry per GIVEN: Nothing for one left out, or for a top-level null on
  -- /evaluation, which 'FnArguments' decodes the same way.
  let expectedParams = map fst (extractParamTypes compiled.compiledDecide)
      inputMap = Map.fromList params
      -- join flattens Maybe (Maybe FnLiteral) -> Maybe FnLiteral
      fullParams = [(name, join $ Map.lookup name inputMap) | name <- expectedParams]
      -- ASSUMEs referenced by the function body — promoted to parameters in
      -- the schema, and bound by 'rewriteModuleAssumes' in 'evaluateDirectAST'.
      assumeRefs = extractAssumeParamResolveds compiled.compiledModule compiled.compiledDecide
      assumeNameOf r = rawNameToText (rawName (getActual r))
      assumeValues = [(assumeNameOf r, join $ Map.lookup (assumeNameOf r) inputMap) | (r, _) <- assumeRefs]

  refuseUnknownArguments presumption
    (inputDefaults compiled.compiledModule compiled.compiledDecide)
    (inputNames compiled.compiledModule compiled.compiledDecide) params

  -- Take the wrapper path only for a @{}@ anywhere, or a @null@ the decoder
  -- kept as a value: inside a record or list, or at the top level from MCP
  -- and batch ('requiresWrapperEvaluation'). A parameter left out, or a
  -- top-level @null@ on /evaluation, stays on the direct path, and so do the
  -- ASSUMEs, which 'evaluateDirectAST' binds by 'rewriteModuleAssumes'.
  if requiresWrapperEvaluation (fullParams ++ assumeValues)
    then evaluateWithWrapper filepath fnDecl compiled sourceText modContext params traceLevel includeGraphViz presumption
    else evaluateDirectAST compiled inputMap assumeRefs traceLevel includeGraphViz presumption

-- | How the wrapper path decodes one request, decided once for the three
-- places that build a wrapper ('evaluateWithWrapper', the deontic one, and
-- 'createFunction''s fallback).
data WrapperPlan = WrapperPlan
  { wpBinders   :: [(Text, Type' Resolved)]
    -- ^ the section GIVENs the wrapper still supplies with @WITH@
  , wpFields    :: Map Text (Maybe Text)
    -- ^ the inputs whose @InputArgs@ field keeps the input's own type, not
    -- lifted to MAYBE, each with its @TYPICALLY@ as source text if it has one
  , wpArguments :: [(Text, Maybe FnLiteral)]
    -- ^ what the wrapper decodes
  , wpInputs    :: Set.Set Text
  }

-- | The plan. W1 lifts every input to MAYBE and binds NOTHING to "not
-- supplied", which suits a BOOLEAN (its placeholder is lazy, TU-wire-b) and
-- nothing else: any other input left out, or sent as @null@, made the whole
-- answer NOTHING and the request failed with "Evaluation produced unknown
-- value", naming nothing. So:
--
-- * a section GIVEN left out with a default, presumption soft, is not
--   supplied at all, and discharge fills it at the root (T6b);
-- * a BOOLEAN keeps W1's lifting (a defaulted one left out under soft is the
--   exception, filled from its TYPICALLY), and a left-out one is sent as
--   @null@ so that its NOTHING is W1's placeholder;
-- * a DATE, TIME or DATETIME keeps W1's lifting too, because the wrapper
--   converts it from a string, and is likewise sent as @null@;
-- * a MAYBE the author declared is decoded as itself and left absent, so
--   that the decoder fills its NOTHING (D7.3, reported) or, under hard,
--   refuses it (T1b);
-- * every other input keeps its own type and its TYPICALLY, so that the
--   decoder fills a left-out one, and refuses a missing or @null@ one by name
--   (T3) instead of the answer quietly becoming NOTHING.
wrapperPlan
  :: Presumption
  -> Module Resolved
  -> Decide Resolved
  -> [(Text, Maybe FnLiteral)]
  -> ([(Text, Type' Resolved)], [(Text, Type' Resolved)], [(Text, Type' Resolved)])
     -- ^ GIVENs, section GIVENs, ASSUMEs
  -> WrapperPlan
wrapperPlan presumption m decide params (givens, binders, assumes) =
  WrapperPlan
    { wpBinders   = filter (not . discharged) binders
    , wpFields    = Map.fromList
        [ (n, prettyLayout <$> Map.lookup n defaults)
        | (n, ty) <- givens <> filter (not . discharged) binders <> assumes
        , ownType n ty
        ]
    , wpArguments = params <>
        [ (n, Nothing)
        | i@(n, ty) <- givens <> binders <> assumes
        , not (supplied n), not (discharged i)
        , isNothing (stripMaybe ty), not (ownType n ty)
        ]
    , wpInputs    = Set.fromList (map fst (givens <> binders <> assumes))
    }
  where
    soft        = presumption == PresumeSoft
    defaults    = inputDefaults m decide
    supplied n  = n `elem` map fst params
    hasDefault n = Map.member n defaults
    discharged (n, _) = soft && not (supplied n) && hasDefault n && n `elem` map fst binders
    isBoolean (TyApp _ name []) = getUnique name == TypeCheck.booleanUnique
    isBoolean _                 = False
    isTemporal (TyApp _ name []) =
      getUnique name `elem` [TypeCheck.dateUnique, TypeCheck.timeUnique, TypeCheck.datetimeUnique]
    isTemporal _ = False
    ownType n ty
      | isJust (stripMaybe ty) = False
      | isBoolean ty           = soft && not (supplied n) && hasDefault n
      | isTemporal ty          = False
      | otherwise              = True

-- | The request's @presumed@ list on the wrapper path ('Eval.requestPresumed'),
-- mapping the wrapper's field names back to the inputs'.
wrapperPresumed :: Presumption -> WrapperPlan -> [Eval.Presumed] -> [Text]
wrapperPresumed presumption plan =
  Eval.requestPresumed (presumption == PresumeSoft) unInputField plan.wpInputs

-- | The wrapper names a field @x (input)@ ('Backend.CodeGen.inputFieldName');
-- messages and @presumed@ name the input.
unInputField :: Text -> Text
unInputField n = fromMaybe n (Text.stripSuffix " (input)" n)

-- | A decode error from the wrapper, with the wrapper's field names put back
-- to the inputs' (review m6): @'cfg (input).timeout'@ is @'cfg.timeout'@, and
-- @'people (input)[0]'@ is @'people[0]'@.
unInputFieldsIn :: Text -> Text
unInputFieldsIn =
  Text.replace " (input)." "." . Text.replace " (input)[" "[" . Text.replace " (input)'" "'"

-- | Evaluate a deontic function with startTime and events via EVALTRACE wrapper.
-- Always uses the wrapper path since events need to go through L4 typechecking.
evaluateWithCompiledDeontic
  :: FilePath
  -> FunctionDeclaration
  -> CompiledModule
  -> Text  -- ^ Original source text
  -> ModuleContext  -- ^ Module context for IMPORT resolution
  -> [(Text, Maybe FnLiteral)]
  -> Scientific.Scientific   -- ^ Start time for contract simulation
  -> [TraceEvent]             -- ^ Events to replay
  -> Maybe Text               -- ^ Party type name (for formatting events)
  -> Maybe Text               -- ^ Action type name (for formatting events)
  -> TraceLevel
  -> Bool
  -> Presumption
  -> ExceptT EvaluatorError IO ResponseWithReason
evaluateWithCompiledDeontic filepath fnDecl compiled sourceText modContext params startTime traceEvents mPartyType mActionType traceLevel includeGraphViz presumption = do
  let givenParamTypes = extractParamTypes compiled.compiledDecide
      (binderParamTypes0, assumeParamTypes) = splitAssumeParams compiled.compiledModule compiled.compiledDecide
      plan = wrapperPlan presumption compiled.compiledModule compiled.compiledDecide params
               (givenParamTypes, binderParamTypes0, assumeParamTypes)

  refuseUnknownArguments presumption
    (inputDefaults compiled.compiledModule compiled.compiledDecide)
    (inputNames compiled.compiledModule compiled.compiledDecide) params

  refuseEventRecordGaps (buildModuleInfo compiled.compiledAllDeclares) mPartyType mActionType traceEvents

  -- Convert input parameters to JSON
  inputJson <- paramsToJson plan.wpArguments

  -- Generate deontic wrapper code with EVALTRACE
  genCode <- case generateDeonticEvalWrapper fnDecl.name givenParamTypes plan.wpBinders assumeParamTypes plan.wpFields inputJson startTime traceEvents mPartyType mActionType traceLevel of
    Left err -> throwError $ InterpreterError err
    Right gc -> pure gc

  -- Evaluate the wrapper in the context of the precompiled module
  (errs, mEvalRes) <- liftIO $ evaluateWrapperInContext presumption filepath genCode.generatedWrapper sourceText modContext

  -- Handle result
  case mEvalRes of
    Nothing -> throwError $ InterpreterError (mconcat errs)
    Just [r@Eval.MkEvalDirectiveResult{result, trace}] ->
      handleEvalResult compiled.compiledEntityInfo result trace fnDecl.name genCode plan.wpArguments traceLevel includeGraphViz compiled.compiledModule
        (wrapperPresumed presumption plan r.presumed)
    Just [] -> throwError $ InterpreterError "L4: No #EVAL found in the program."
    Just _xs -> throwError $ InterpreterError "L4: More than ONE #EVAL found in the program."

-- | Refuse an event whose party or action record leaves out a field that has a
-- @TYPICALLY@ default (W5, T4b; review silent F2, 2026-10-03).
--
-- The wrapper turns each event's record into SOURCE
-- (@`event party 0` MEANS Driver WITH name IS "Alice"@, 'Backend.CodeGen.prepareEvents'),
-- and since W5 the checker fills a field a construction leaves out from its
-- @TYPICALLY@. That would make a request's own record take a default the request
-- could have supplied, under @"presumption": "hard"@ as well, and list it as a
-- default "no request could supply": the answer changes (the event no longer
-- matches the party it names) and the switch that exists to withdraw such
-- defaults does nothing. Before W5 the omission failed to check, loudly.
--
-- So an event's record keeps what it always had: every field is written. The
-- request's arguments are not affected, because their records are decoded from
-- JSON, where the switch applies. _Decided by Claude overnight 2026-10-03,
-- pending Meng's review._ Alternative: decode the event records as the
-- arguments are, so that soft takes a default and lists it as
-- @events[0].party.licence@, and hard refuses it.
refuseEventRecordGaps
  :: Monad m
  => ModuleInfo -> Maybe Text -> Maybe Text -> [TraceEvent] -> ExceptT EvaluatorError m ()
refuseEventRecordGaps mi mParty mAction events =
  unless (null gaps) $
    throwError $ InterpreterError $ Text.intercalate "\n"
      [ "Missing required field '" <> role <> "." <> field <> "' (" <> con <> "): "
          <> "an event's record is part of the request, so it never takes the field's TYPICALLY default. "
          <> "Give every field of it."
      | (role, con, field) <- gaps
      ]
  where
    -- constructor name -> its fields that have a TYPICALLY
    defaultedFields :: Map Text [Text]
    defaultedFields = Map.fromList
      [ (rawNameToText (rawName (getActual ctor)), [ f | (f, _, Just _) <- fields ])
      | (ctor, fields) <- Map.elems mi.miRecords
      ]

    gaps =
      [ ("events[" <> Text.textShow i <> "]." <> label, con, field)
      | (i, ev) <- zip [0 :: Int ..] events
      , (label, mType, lit) <- [("party", mParty, ev.party), ("action", mAction, ev.action)]
      , Just (con, given) <- [recordShape mType lit]
      , field <- Map.findWithDefault [] con defaultedFields
      , field `notElem` given
      ]

    -- The shapes 'Backend.CodeGen.fnLiteralToL4ExprWithType' and
    -- 'Backend.CodeGen.fnLiteralToL4Expr' turn into @Con WITH field IS value, ...@:
    -- with the type name known, any object is a record of that type; without it,
    -- a one-key object whose value is an object names the constructor itself.
    recordShape :: Maybe Text -> FnLiteral -> Maybe (Text, [Text])
    recordShape (Just t) (FnObject fs@(_ : _))    = Just (t, map fst fs)
    recordShape Nothing  (FnObject [(c, FnObject fs)]) = Just (c, map fst fs)
    recordShape _ _                               = Nothing

-- | Direct AST evaluation (fast path) - for simple types without FnObject.

-- | Direct AST evaluation (fast path), for a request with no @{}@ in it and
-- no @null@ the decoder kept as a value ('requiresWrapperEvaluation');
-- records, enums and lists included.
-- Each supplied ASSUME is bound by installing a nullary DECIDE at the
-- ASSUME's own address in the module ('rewriteModuleAssumes'): the
-- exported body and every helper it reaches resolve the ASSUME by its
-- 'Unique', and the module's own definitions are evaluated fresh per
-- call, so all of them see the supplied value. A LET around the call (or
-- around the inlined body) would not: a helper's closure captures the
-- module environment, where the ASSUME is still 'ValAssumed'.
--
-- An input the request left out that has a default takes it while
-- presumption is soft (W3): a GIVEN, or a record field inside any input, by a
-- root fill ('RootFill'), and a section GIVEN by leaving its ASSUME in place,
-- so that discharge fills it at the root as it does for @#EVAL@ (T6b). Either
-- way the evaluator reports the default only if it is forced.
evaluateDirectAST
  :: CompiledModule
  -> Map Text (Maybe FnLiteral)           -- ^ the request's arguments: absent, @null@ ('Nothing'), or a value
  -> [(Resolved, Type' Resolved)]         -- ^ ASSUMEs read by the export (transitively)
  -> TraceLevel
  -> Bool
  -> Presumption
  -> ExceptT EvaluatorError IO ResponseWithReason
evaluateDirectAST compiled inputMap assumeRefs traceLevel includeGraphViz presumption = do
  -- Build once per call: a lookup of every record / enum declaration in
  -- the compiled module so 'fnLiteralToExprTyped' can construct record
  -- literals and enum variants without re-running the typechecker.
  let moduleInfo = buildModuleInfo compiled.compiledAllDeclares
      paramTypes = extractParamTypes compiled.compiledDecide
      defaults   = inputDefaults compiled.compiledModule compiled.compiledDecide
      binders    = sectionBinders compiled.compiledModule
      soft       = presumption == PresumeSoft
      MkModule _ moduleUri _ = compiled.compiledModule
      ctx        = FillCtx { fcSoft = soft, fcUri = moduleUri }
      nameOf r   = rawNameToText (rawName (getActual r))

  ((argExprs, assumeExprList), (_, fills)) <- either (throwError . InterpreterError) pure $ runStateT
    ( do
        args <- forM paramTypes $ \(name, ty) ->
          attempt $ rootInputExpr moduleInfo ctx defaults ("Parameter '" <> name <> "'") name ty (suppliedIn inputMap name)
        assumes <- forM assumeRefs $ \(assumeRes, assumeTy) -> do
          let nm = nameOf assumeRes
              supplied = suppliedIn inputMap nm
              isBinder = Map.member (getUnique assumeRes) binders
              -- a section GIVEN is a parameter of the function, as the
              -- schema publishes it; only a written ASSUME is called one
              label | isBinder  = "Parameter '" <> nm <> "'"
                    | otherwise = "ASSUME '" <> nm <> "'"
          case supplied of
            -- a section GIVEN the request left out, with a default: discharge fills it
            Absent
              | soft
              , isBinder
              , Map.member nm defaults -> pure (Right Nothing)
            _ -> attempt $
                   Just . (getUnique assumeRes,) <$> rootInputExpr moduleInfo ctx defaults label nm assumeTy supplied
        -- every input that cannot be converted is named, not just the first
        case lefts args <> lefts assumes of
          []   -> pure (rights args, catMaybes (rights assumes))
          errs -> fillError (Text.intercalate "\n" errs)
    ) (0, [])
  let assumeExprs = Map.fromList assumeExprList

  -- The replacement DECIDE keeps the ASSUME's own type signature and app
  -- form (hence its Resolved and Unique), so every reference in the
  -- module — in the export or in a helper — now finds a value there.
  let bindAssume (MkAssume _ tySig appForm@(MkAppForm _ r _ _) _ _) =
        case Map.lookup (getUnique r) assumeExprs of
          Nothing        -> KeepAssume
          Just valueExpr -> ReplaceAssume (Decide emptyAnno (MkDecide emptyAnno tySig appForm valueExpr))
      boundModule = addRootFills fills (rewriteModuleAssumes bindAssume compiled.compiledModule)
      rootFills = Map.fromList [ (getUnique f.fillRef, f.fillPresumed) | f <- fills ]
      callExpr = buildFunctionCallExpr (getFunctionResolved compiled.compiledDecide) argExprs

  -- Configure evaluation with tracing based on trace level
  let evalTracePolicy = case traceLevel of
        TraceNone -> apiDefaultPolicy
        TraceFull -> TracePolicy
          { evalDirectiveTrace = TracePolicy.CollectTrace (TracePolicy.TraceOptions TracePolicy.TextTrace TracePolicy.ApiResponse GraphViz.defaultGraphVizOptions)
          , evaltraceDirectiveTrace = TracePolicy.CollectTrace (TracePolicy.TraceOptions TracePolicy.TextTrace TracePolicy.ApiResponse GraphViz.defaultGraphVizOptions)
          }

  -- Evaluate the expression directly using the precompiled module
  evalConfig <- liftIO $ requestEvalConfig evalTracePolicy presumption False

  -- Pass the pre-computed import environment
  -- The module's own definitions are evaluated fresh each time, but imports
  -- need their References to be pre-allocated
  -- The bundle's DECLAREs, the imports' included, so that a decode the rules
  -- make into an imported record fills its field defaults here as it does on
  -- the wrapper path and in batch (review M3).
  mResult <- liftIO $ Eval.execEvalExprInContextOfModuleWith
    evalConfig
    compiled.compiledEntityInfo
    rootFills
    compiled.compiledAllDeclares
    callExpr
    (compiled.compiledImportEnv, boundModule)

  -- Handle result
  case mResult of
    Nothing -> throwError $ InterpreterError "L4: Expression evaluation failed."
    Just r@Eval.MkEvalDirectiveResult{result, trace} ->
      handleEvalResultDirect compiled.compiledEntityInfo result trace traceLevel includeGraphViz compiled.compiledModule
        (Eval.requestPresumed soft id (functionInputs compiled) r.presumed)

-- | Add each root fill to the module as a 0-ary definition of its default.
-- At the top of the module, so nothing it is appended to can capture it.
addRootFills :: [RootFill] -> Module Resolved -> Module Resolved
addRootFills [] m = m
addRootFills fills (MkModule ann uri (MkSection sann n aka g decls)) =
  MkModule ann uri (MkSection sann n aka g (map fillDecl (reverse fills) <> decls))
  where
    fillDecl f =
      Decide emptyAnno
        (MkDecide emptyAnno
          (MkTypeSig emptyAnno (MkGivenSig emptyAnno []) Nothing)
          (MkAppForm emptyAnno f.fillRef [] Nothing)
          f.fillBody)

-- | Handle evaluation result (simplified version for direct evaluation)
handleEvalResultDirect
  :: EntityInfo
  -> Eval.EvalDirectiveValue
  -> Maybe EvalTrace
  -> TraceLevel
  -> Bool
  -> Module Resolved
  -> [Text]
  -> ExceptT EvaluatorError IO ResponseWithReason
handleEvalResultDirect ei result trace traceLevel includeGraphViz mModule presumed = case result of
  Eval.Assertion _ -> throwError $ InterpreterError "L4: Got an assertion instead of a normal result."
  Eval.Reduction (Eval.ReducedRefused ref) -> throwError $ EvaluatorRefused ref.message presumed
  Eval.Reduction (Eval.ReducedErrored evalExc) -> throwError $ InterpreterError $ Text.unlines (Eval.prettyEvalException evalExc)
  -- as the Stuck it used to be (UNKNOWN-EVALUATION-SPEC §4.7.4)
  Eval.Reduction o@(Eval.ReducedUndetermined _) -> throwError $ InterpreterError $ Eval.prettyReductionOutcome o
  Eval.Reduction (Eval.Reduced val) -> do
    r <- nfToFnLiteral ei val
    pure $ ResponseWithReason
      { fnResult = Map.singleton "value" r
      , reasoning = case traceLevel of
          TraceNone -> emptyTree
          TraceFull -> buildReasoningTree trace
      , graphviz =
          if includeGraphViz && traceLevel == TraceFull
            then
              fmap
                ( \tr ->
                    GraphVizResponse
                      { dot = GraphViz.traceToGraphViz GraphViz.defaultGraphVizOptions (Just mModule) tr
                      }
                )
                trace
            else Nothing
      , presumed = presumed
      }

-- | Wrapper-based evaluation (fallback for FnObject parameters)
-- Uses JSONDECODE to handle complex record types
-- | The inputs a function reads that are not its own GIVENs, split into
-- section GIVENs, which the wrapper supplies with WITH, and genuine ASSUMEs,
-- which it can only shadow with a LET. Both arrive as ASSUMEs, because a
-- section GIVEN is elaborated into one ('L4.Desugar.elaborateSectionBinder').
splitAssumeParams
  :: Module Resolved
  -> Decide Resolved
  -> ([(Text, Type' Resolved)], [(Text, Type' Resolved)])
splitAssumeParams m decide =
  let binders = sectionBinders m
      named = [ (rawNameToText (rawName (getActual r)), ty, Map.member (getUnique r) binders)
              | (r, ty) <- extractAssumeParamResolveds m decide ]
  in ( [ (n, ty) | (n, ty, True) <- named ]
     , [ (n, ty) | (n, ty, False) <- named ] )

evaluateWithWrapper
  :: FilePath
  -> FunctionDeclaration
  -> CompiledModule
  -> Text  -- ^ Original source text
  -> ModuleContext  -- ^ Module context for IMPORT resolution
  -> [(Text, Maybe FnLiteral)]
  -> TraceLevel
  -> Bool
  -> Presumption
  -> ExceptT EvaluatorError IO ResponseWithReason
evaluateWithWrapper filepath fnDecl compiled sourceText modContext params traceLevel includeGraphViz presumption = do
  -- Extract parameter types from the compiled function definition
  let givenParamTypes = extractParamTypes compiled.compiledDecide
      (binderParamTypes0, assumeParamTypes) = splitAssumeParams compiled.compiledModule compiled.compiledDecide
      plan = wrapperPlan presumption compiled.compiledModule compiled.compiledDecide params
               (givenParamTypes, binderParamTypes0, assumeParamTypes)

  -- Convert input parameters to JSON
  inputJson <- paramsToJson plan.wpArguments

  -- Generate wrapper code using existing code generation
  genCode <- case generateEvalWrapper fnDecl.name givenParamTypes plan.wpBinders assumeParamTypes plan.wpFields inputJson traceLevel of
    Left err -> throwError $ InterpreterError err
    Right gc -> pure gc

  -- The wrapper contains JSONDECODE and function application
  -- We evaluate the wrapper in the context of the precompiled module
  -- This avoids re-parsing and re-typechecking the main module
  (errs, mEvalRes) <- liftIO $ evaluateWrapperInContext presumption filepath genCode.generatedWrapper sourceText modContext

  -- Handle result
  case mEvalRes of
    Nothing -> throwError $ InterpreterError (mconcat errs)
    Just [r@Eval.MkEvalDirectiveResult{result, trace}] ->
      handleEvalResult compiled.compiledEntityInfo result trace fnDecl.name genCode plan.wpArguments traceLevel includeGraphViz compiled.compiledModule
        (wrapperPresumed presumption plan r.presumed)
    Just [] -> throwError $ InterpreterError "L4: No #EVAL found in the program."
    Just _xs -> throwError $ InterpreterError "L4: More than ONE #EVAL found in the program."

-- | Evaluate wrapper code in the context of a precompiled module
-- This combines the wrapper (small) with the precompiled module and evaluates
evaluateWrapperInContext
  :: Presumption
  -> FilePath
  -> Text  -- ^ Wrapper code containing #EVAL directive
  -> Text  -- ^ Original source text (preserves layout)
  -> ModuleContext  -- ^ Module context for IMPORT resolution
  -> IO ([Text], Maybe [Eval.EvalDirectiveResult])
evaluateWrapperInContext presumption filepath wrapperCode sourceText modContext = do
  -- Use original source text to preserve layout-sensitive formatting
  -- L4 is layout-sensitive (like Python), so prettyLayout can break indentation
  -- We filter IDE directives (#EVAL, #TRACE, etc.) using text-based filtering
  let filteredSource = filterIdeDirectivesText sourceText
      combinedProgram = filteredSource <> wrapperCode

  -- Evaluate the combined program using the original module context
  -- This ensures IMPORT statements can be resolved correctly
  evaluateModule presumption filepath combinedProgram modContext

-- | Filter IDE directives from source text while preserving layout
-- Removes lines starting with #EVAL, #TRACE, #EVALTRACE, #ASSERT, #CHECK
-- Also removes continuation lines for multiline directives (#TRACE ... WITH)
-- A continuation line is one that:
-- 1. Immediately follows a directive line or another continuation
-- 2. Is more indented than the directive line (or is a blank/comment line)
filterIdeDirectivesText :: Text -> Text
filterIdeDirectivesText = Text.unlines . filterLines . Text.lines
  where
    -- Filter lines, tracking whether we're inside a multiline directive
    filterLines :: [Text] -> [Text]
    filterLines = go Nothing
      where
        -- mIndent = Nothing: not in a directive
        -- mIndent = Just indent: in a directive with given base indentation
        go :: Maybe Int -> [Text] -> [Text]
        go _ [] = []
        go mIndent (line:rest)
          | isDirectiveLine line =
              -- Start of a directive - skip it and enter directive state
              let baseIndent = lineIndentation line
              in go (Just baseIndent) rest
          | Just baseIndent <- mIndent, isContinuationLine baseIndent line =
              -- Continuation of a multiline directive - skip it
              go mIndent rest
          | otherwise =
              -- Not a directive or continuation - keep it and reset state
              line : go Nothing rest

    -- Check if line starts a directive (with optional leading whitespace)
    -- Also matches @desc annotations since they annotate the following directive
    -- and become orphaned when the directive is removed.
    isDirectiveLine :: Text -> Bool
    isDirectiveLine line =
      let stripped = Text.stripStart line
      in any (`Text.isPrefixOf` stripped)
           ["#EVAL", "#EVALTRACE", "#TRACE", "#ASSERT", "#CHECK", "@desc"]

    -- Check if line is a continuation of a multiline directive
    -- Continuation lines are either:
    -- 1. More indented than the base directive
    -- 2. Empty or whitespace-only (blank lines within directive)
    -- 3. Comment-only lines (starting with --) that are more indented
    isContinuationLine :: Int -> Text -> Bool
    isContinuationLine baseIndent line
      | Text.all isSpace line = True  -- Blank line - include in directive block
      | lineIndentation line > baseIndent = True  -- More indented = continuation
      | otherwise = False

    -- Get the indentation (number of leading spaces/tabs) of a line
    lineIndentation :: Text -> Int
    lineIndentation = Text.length . Text.takeWhile isSpace

    isSpace :: Char -> Bool
    isSpace c = c == ' ' || c == '\t'

-- | Convert FnLiteral parameters to Aeson.Value
-- Missing parameters (Nothing) become FnUnknown -> Aeson.Null for partial evaluation
paramsToJson :: (Monad m) => [(Text, Maybe FnLiteral)] -> ExceptT EvaluatorError m Aeson.Value
paramsToJson params =
  let pairs = [(name, fnLiteralToJson (maybe FnUnknown id mVal)) | (name, mVal) <- params]
  in pure $ Aeson.object [(Aeson.fromText k, v) | (k, v) <- pairs]

-- | Convert FnLiteral to Aeson.Value
fnLiteralToJson :: FnLiteral -> Aeson.Value
fnLiteralToJson = \case
  FnLitInt i -> Aeson.Number (fromIntegral i)
  FnLitDouble d -> Aeson.Number (realToFrac d)
  FnLitBool b -> Aeson.Bool b
  FnLitString s -> Aeson.String s
  FnArray arr -> Aeson.Array (Vector.fromList (map fnLiteralToJson arr))
  FnObject fields -> Aeson.object [(Aeson.fromText k, fnLiteralToJson v) | (k, v) <- fields]
  -- {} means "not known" as null does (T3), records included (review M2),
  -- and is sent as itself so that a refusal says what the request sent
  FnUncertain -> Aeson.object []
  FnUnknown -> Aeson.Null

-- | Handle the result of a generated wrapper.
--
-- The wrapper answers @JUST answer@, or @NOTHING@ when it could not call the
-- function (see 'AnswerShape'). That envelope is taken apart here, at the
-- 'Eval.Value' level, and the answer inside it is then handled exactly as the
-- direct path handles its own, by 'handleEvalResultDirect'. Taking it apart
-- after conversion does not work: 'valueToFnLiteral' dissolves every @JUST@,
-- the envelope's included, so @JUST NOTHING@ arrived as no value at all and
-- @JUST (LIST x)@ as a one-element list that was then unwrapped to @x@
-- (smucclaw/l4-ide#1003).
--
-- So a top-level answer that converts to 'FnUnknown' is returned as @null@
-- with status 200, as on the direct path. Before the fix for #1003 this
-- path's handler refused it with "Evaluation produced unknown value";
-- dropping that refusal is deliberate.
-- 'FnUnknown' at the top level is now @NOTHING@ or @JUST NOTHING@, which are
-- answers: refusing it here would refuse on this path an answer the direct
-- path gives. "Could not compute" does not arrive as @null@ on either path:
-- an evaluation that fails is 'Eval.ReducedErrored' and is refused. Nor can
-- the top-level value be the evaluator's 'Eval.Omitted' truncation marker:
-- 'Eval.nf' starts at depth 'maximumStackSize' (200) and marks 'Eval.Omitted'
-- only below depth 0, so the direct path's answer is read at depth 200 and
-- this path's, one level inside the envelope, at 199. 'Eval.Omitted' appears
-- only nested, as the @null@s that end a list answer cut short at the README's
-- limit on list answers.
handleEvalResult
  :: EntityInfo
  -> Eval.EvalDirectiveValue
  -> Maybe EvalTrace
  -> Text  -- ^ the function's name, for a NOTHING no input explains
  -> GeneratedCode
  -> [(Text, Maybe FnLiteral)]  -- ^ the request's inputs, to say why a NOTHING came back
  -> TraceLevel
  -> Bool
  -> Module Resolved
  -> [Text]
  -> ExceptT EvaluatorError IO ResponseWithReason
handleEvalResult ei result trace fnName genCode params traceLevel includeGraphViz mModule presumed = do
  answer <- case (genCode.answerShape, result) of
    (WrappedInJust, Eval.Reduction (Eval.Reduced envelope)) ->
      openEnvelope envelope >>= \ case
        -- a bare unknown input inside the JUST is undetermined, as on the direct
        -- path (UNKNOWN-EVALUATION-SPEC §2.5; decided by Claude 2026-10-07,
        -- pending Meng's review)
        Eval.MkNF (Eval.ValAssumed r ty) ->
          throwError $ InterpreterError $ unInputFieldsIn $ Eval.prettyReductionOutcome $
            Eval.ReducedUndetermined (Eval.TInput r ty :| [])
        inner -> pure (Eval.Reduction (Eval.Reduced inner))
    -- the wrapper names an input's field @x (input)@: say @x@, as the direct path does
    (_, Eval.Reduction (Eval.ReducedErrored evalExc)) ->
      throwError $ InterpreterError $ unInputFieldsIn $ Text.unlines (Eval.prettyEvalException evalExc)
    -- an input still waited on was a 'Stuck' error before step 3 and said so the same way
    (_, Eval.Reduction o@(Eval.ReducedUndetermined _)) ->
      throwError $ InterpreterError $ unInputFieldsIn $ Eval.prettyReductionOutcome o
    _ -> pure result
  handleEvalResultDirect ei answer trace traceLevel includeGraphViz mModule presumed
  where
    openEnvelope = \case
      Eval.MkNF (Eval.ValConstructor con [inner])
        | getUnique con == TypeCheck.justUnique -> pure inner
      Eval.MkNF (Eval.ValConstructor con [])
        | getUnique con == TypeCheck.nothingUnique -> throwError (wrapperDeclined fnName genCode params)
      _ -> throwError $ InterpreterError "L4: the generated wrapper answered neither JUST nor NOTHING."

-- | Why a wrapper answered NOTHING. It does so without calling the function
-- for one of the two reasons given at 'requiredInputs': a required input is
-- absent, which here means left out, @null@ or @{}@; or a required DATE, TIME
-- or DATETIME string does not parse. A value of the wrong JSON type is not
-- one of them: it stops JSONDECODE with an error of its own. An absent input
-- is reported with the message the direct path gives for it. When both happen,
-- the absent input is named, though the wrapper may have stopped earlier, at
-- a string it could not parse.
wrapperDeclined :: Text -> GeneratedCode -> [(Text, Maybe FnLiteral)] -> EvaluatorError
wrapperDeclined fnName genCode params = InterpreterError $
  case (filter (absent . valueOf) required, if null failing then unparsed else failing) of
    (input : _, _) -> label input <> ": missing required parameter"
    ([], [(input, ty, s)]) -> label input <> ": could not read " <> Text.textShow s <> " as a " <> ty
    ([], candidates@(_ : _)) ->
      "One of these inputs could not be read: "
        <> Text.intercalate ", " [ label input <> " as a " <> ty | (input, ty, _) <- candidates ]
    -- Defensive: no request is known to reach this. A wrapper answers NOTHING
    -- only for a required input that is absent or a temporal string it cannot
    -- parse, and both are caught above; a value of the wrong JSON type stops
    -- JSONDECODE with an error of its own before the envelope is read. No
    -- test pins this message.
    ([], []) ->
      "L4: the generated wrapper did not call '" <> fnName
        <> "', and no input explains why. The inputs it checked: "
        <> (if null required then "none" else Text.intercalate ", " (map label required))
        <> "."
  where
    required = genCode.requiredInputs
    valueOf input = join (lookup input.inputName params)
    unparsed =
      [ (input, ty, s)
      | input <- required, Just ty <- [input.parsedAs], Just (FnLitString s) <- [valueOf input] ]
    -- The wrapper's own parsers, those of TODATE, TOTIME and TODATETIME, pick
    -- out the string that failed. The direct path's ISO parsers are stricter
    -- ("2026/01/31" is a DATE to TODATE and not to parseIsoDate), so with two
    -- such inputs they could blame one the wrapper had read.
    failing = [ c | c@(_, ty, s) <- unparsed, not (parses ty s) ]
    parses = \case
      "DATE"     -> isJust . parseDateText
      "TIME"     -> isJust . parseTimeText
      "DATETIME" -> isJust . parseDatetimeText
      _          -> const False
    -- the direct path's labels: only an ASSUME the author wrote is called one
    label input
      | input.isWrittenAssume = "ASSUME '" <> input.inputName <> "'"
      | otherwise = "Parameter '" <> input.inputName <> "'"
    absent = \case
      Nothing          -> True
      Just FnUnknown   -> True
      Just FnUncertain -> True
      Just _           -> False

createFunction ::
  FilePath ->
  FunctionDeclaration ->
  Text ->
  ModuleContext ->
  IO (RunFunction, Maybe CompiledModule)
createFunction filepath fnDecl fnImpl moduleContext = do
  -- Try to precompile for fast path
  let funRawName = mkNormalName fnDecl.name
  precompileResult <- precompileModule filepath fnImpl moduleContext funRawName

  case precompileResult of
    Right compiled -> do
      -- Fast path: use precompiled module
      -- Capture fnImpl and moduleContext in the closure for wrapper fallback
      let runFn = RunFunction
            { runFunction = \params' _outFilter traceLevel includeGraphViz presumption ->
                evaluateWithCompiled filepath fnDecl compiled fnImpl moduleContext params' traceLevel includeGraphViz presumption
            }
      pure (runFn, Just compiled)

    Left _err -> do
      -- Slow path fallback: use original implementation
      let runFn = RunFunction
            { runFunction = \params' _outFilter traceLevel includeGraphViz presumption -> do
                -- 1. Typecheck original source to get function signature
                (initErrs, mTcRes) <- typecheckModule filepath fnImpl moduleContext

                tcRes <- case mTcRes of
                  Nothing -> throwError $ InterpreterError (mconcat initErrs)
                  Just tcRes -> pure tcRes

                -- 2. Get function definition and extract parameter types
                funDecide <- getFunctionDefinition funRawName tcRes.module'
                let givenParamTypes = extractParamTypes funDecide
                    (binderParamTypes0, assumeParamTypes) = splitAssumeParams tcRes.module' funDecide
                    plan = wrapperPlan presumption tcRes.module' funDecide params'
                             (givenParamTypes, binderParamTypes0, assumeParamTypes)
                refuseUnknownArguments presumption (inputDefaults tcRes.module' funDecide)
                  (inputNames tcRes.module' funDecide) params'

                -- 3. Filter IDE directives from the original source text
                -- L4 is layout-sensitive, so we must preserve the original formatting
                let filteredSource = filterIdeDirectivesText fnImpl

                -- 4. Convert input parameters to JSON
                inputJson <- paramsToJson plan.wpArguments

                -- 5. Generate wrapper code
                genCode <- case generateEvalWrapper fnDecl.name givenParamTypes plan.wpBinders assumeParamTypes plan.wpFields inputJson traceLevel of
                  Left err -> throwError $ InterpreterError err
                  Right gc -> pure gc

                -- 6. Concatenate: filtered source + generated wrapper
                let l4Program = filteredSource <> genCode.generatedWrapper

                -- 7. Evaluate
                (errs, mEvalRes) <- evaluateModule presumption filepath l4Program moduleContext

                -- 8. Handle result
                case mEvalRes of
                  Nothing -> throwError $ InterpreterError (mconcat errs)
                  Just [r@Eval.MkEvalDirectiveResult{result, trace}] ->
                    handleEvalResult tcRes.entityInfo result trace fnDecl.name genCode plan.wpArguments traceLevel includeGraphViz tcRes.module'
                      (wrapperPresumed presumption plan r.presumed)
                  Just [] -> throwError $ InterpreterError "L4: No #EVAL found in the program."
                  Just _xs -> throwError $ InterpreterError "L4: More than ONE #EVAL found in the program."
            }
      pure (runFn, Nothing)

-- | Create a 'RunFunction' from an already-compiled module.
-- Source text and module context are captured in the closure (once per file)
-- rather than stored in every CompiledModule, to reduce retained memory.
createRunFunctionFromCompiled :: FilePath -> FunctionDeclaration -> CompiledModule -> Text -> ModuleContext -> RunFunction
createRunFunctionFromCompiled filepath fnDecl compiled sourceText modContext =
  RunFunction
    { runFunction = \params' _outFilter traceLevel includeGraphViz presumption ->
        evaluateWithCompiled filepath fnDecl compiled sourceText modContext params' traceLevel includeGraphViz presumption
    }

-- | Extract parameter names and types from a DECIDE's GIVEN clause
extractParamTypes :: Decide Resolved -> [(Text, Type' Resolved)]
extractParamTypes (MkDecide _ (MkTypeSig _ (MkGivenSig _ typedNames) _) _ _) =
  mapMaybe extractTypedName typedNames
  where
    extractTypedName (MkOptionallyTypedName _ resolved (Just ty) _) =
      Just (rawNameToText (rawName $ getActual resolved), ty)
    extractTypedName (MkOptionallyTypedName _ resolved Nothing _) =
      -- Try to get type from resolved info
      case getAnno (getName resolved) ^. #extra % #resolvedInfo of
        Just (TypeInfo ty _) -> Just (rawNameToText (rawName $ getActual resolved), ty)
        _ -> Nothing

-- | Find the first function with the given name in the module.
getFunctionDefinition :: (Monad m) => RawName -> Module Resolved -> ExceptT EvaluatorError m (Decide Resolved)
getFunctionDefinition name (MkModule _ _ sect) = case goSection sect of
  Nothing -> throwError $ InterpreterError $ "L4: No function with name " <> prettyLayout name <> " found."
  Just dec -> pure dec
 where
  goSection (MkSection _ _ _ _ decls) =
    listToMaybe $ mapMaybe (goTopDecl) decls

  rawNameOfDecide = rawNameToText . rawName . getActual . nameOf

  goTopDecl = \case
    Decide _ dec ->
      if rawNameOfDecide dec == rawNameToText name
        then Just dec
        else Nothing
    Declare _ _ -> Nothing
    Assume _ _ -> Nothing
    Directive _ _ -> Nothing
    Import _ _ -> Nothing
    Section _ s -> goSection s
    Timezone _ _ -> Nothing

  nameOf (MkDecide _ _ (MkAppForm _ n _ _) _) = n

-- | Build the evaluator Environment for imported modules
-- This evaluates all imports and returns their combined environment
-- so that execEvalExprInContextOfModule can reference imported definitions
buildImportEnvironment
  :: FilePath
  -> Text
  -> ModuleContext
  -> EntityInfo
  -> IO EvalEnv.Environment
buildImportEnvironment filepath source moduleContext _entityInfo = do
  fixedNow <- Eval.readFixedNowEnv
  evalConfig <- Eval.resolveEvalConfig fixedNow apiDefaultPolicy

  result <- oneshotL4ActionAndErrors evalConfig filepath $ \nfp -> do
    let uri = normalizedFilePathToUri nfp
    -- Add all module files as virtual files for IMPORT resolution
    -- Note: embedded libraries are resolved by the import resolver via
    -- JL4_LIBRARY_PATH or Paths_jl4_core data-dir; no need to register
    -- them as virtual files here.
    forM_ (Map.toList moduleContext) $ \(path, content) -> do
      let modulePath = toNormalizedFilePath ("./" <> path)
      _ <- Shake.addVirtualFile modulePath content
      pure ()
    -- Add the main file
    _ <- Shake.addVirtualFile nfp source
    -- Use GetLazyEvaluationDependencies which returns (Environment, [EvalDirectiveResult])
    Shake.use (Shake.AttachCallStack [uri] Rules.GetLazyEvaluationDependencies) uri

  case result of
    (_errs, Just (importEnv, _dirResults)) ->
      -- Successfully built import environment
      pure importEnv
    (_errs, Nothing) ->
      -- Fall back to empty environment if evaluation fails
      pure emptyEnvironment

-- ----------------------------------------------------------------------------
-- Helpers and other non-generic functions
-- ----------------------------------------------------------------------------

nfToFnLiteral :: (Monad m) => EntityInfo -> Eval.NF -> ExceptT EvaluatorError m FnLiteral
nfToFnLiteral ei (Eval.MkNF v) = valueToFnLiteral ei v
nfToFnLiteral _  Eval.Omitted  = pure FnUnknown

valueToFnLiteral :: (Monad m) => EntityInfo -> Eval.Value Eval.NF -> ExceptT EvaluatorError m FnLiteral
valueToFnLiteral ei = \case
  Eval.ValNumber i ->
    pure $ case isInteger i of
      Just int -> FnLitInt int
      Nothing -> FnLitDouble $ fromRational i
  Eval.ValDate day ->
    pure $ FnLitString (Text.textShow day)
  Eval.ValTime tod ->
    pure $ FnLitString (Text.textShow tod)
  Eval.ValDateTime utc _tzName ->
    pure $ FnLitString (Text.textShow utc)
  Eval.ValString t -> pure $ FnLitString t
  Eval.ValNil -> pure $ FnArray []
  Eval.ValCons v1 v2 -> nfToFnLiteral ei v1 >>= \ l1 -> listToFnLiteral ei (DList.singleton l1) v2
  Eval.ValClosure{} -> throwError $ InterpreterError "#EVAL produced function closure."
  Eval.ValConnective{} -> throwError $ InterpreterError "#EVAL produced function closure."
  Eval.ValNullaryBuiltinFun{} -> throwError $ InterpreterError "#EVAL produced builtin closure."
  Eval.ValBinaryBuiltinFun{} -> throwError $ InterpreterError "#EVAL produced function closure."
  Eval.ValUnaryBuiltinFun{} -> throwError $ InterpreterError "#EVAL produced builtin closure."
  Eval.ValTernaryBuiltinFun{} -> throwError $ InterpreterError "#EVAL produced builtin closure."
  Eval.ValPartialTernary{} -> throwError $ InterpreterError "#EVAL produced partial closure."
  Eval.ValPartialTernary2{} -> throwError $ InterpreterError "#EVAL produced partial closure."
  -- Deontic values: serialize as structured JSON objects
  Eval.ValObligation _env party action opens due _followup _lest -> do
    partyLit <- serializeEitherValue ei party
    let actionLit = serializeRAction action
    opensLit <- serializeOpening ei opens
    dueLit <- serializeDue ei due
    pure $ FnObject
      [ ("OBLIGATION", FnObject
          ( [ ("party", partyLit)
            , ("modal", actionLit.modal)
            , ("action", actionLit.actionPat)
            ]
            -- the window's opening edge (EVERY-EACH-QUANTIFIER-SPEC §5.1.2),
            -- present only when the obligation has one still to reach, so
            -- the object of an obligation without an AFTER is unchanged
            <> [ ("opens", o) | Just o <- [opensLit] ]
            <> [ ("deadline", dueLit) ]
          ))
      ]

  Eval.ValBreached reason -> do
    reasonLit <- serializeBreachReason ei reason
    pure $ FnObject [("BREACH", reasonLit)]

  Eval.ValROp _env op left right -> do
    leftLit <- serializeEitherValue ei left
    rightLit <- serializeEitherValue ei right
    let opStr = case op of
          Eval.ValROr  -> "OR" :: Text
          Eval.ValRAnd -> "AND"
    pure $ FnObject
      [ (opStr, FnArray [leftLit, rightLit])
      ]

  -- An armed-but-unrun EVERY: the cast has not been drawn yet, so there are no
  -- member obligations to serialize. Report the source form.
  Eval.ValQuantified _env deonton ->
    pure $ FnObject [("EVERY", FnLitString (prettyLayout deonton))]

  Eval.ValEnvironment{} -> throwError $ InterpreterError "#EVAL produced environment."
  Eval.ValUnappliedConstructor name ->
    pure $ FnLitString $ prettyLayout name
  -- NOTHING is the absence of a value, and JSON spells that null.
  -- Emitting the string "NOTHING" made an optional field's empty case
  -- indistinguishable from a genuine string answer, and made
  -- `MAYBE NUMBER` unusable for exactly the job it is for: saying that
  -- a limit does not apply without naming a number that could be
  -- mistaken for one.
  --
  -- NOTHING and JUST are recognised by their uniques, not their names: a
  -- rule may declare its own constructor called @Nothing@ or @Just@, and
  -- that is an answer, not the absence of one.
  Eval.ValConstructor resolved []
    | getUnique resolved == TypeCheck.nothingUnique -> pure FnUnknown
  Eval.ValConstructor resolved [] ->
    -- Special case boolean constructors (preserve original casing for others)
    let name = constructorText resolved
     in case Text.toUpper name of
          "TRUE" -> pure $ FnLitBool True
          "FALSE" -> pure $ FnLitBool False
          -- Other nullary constructors become strings (original casing preserved)
          _ -> pure $ FnLitString name
  -- JUST x is x. The Maybe wrapper is L4's, not the caller's, and wrapping it
  -- in an object would make every optional field a tagged union the client has
  -- to unwrap. This matches 'L4.Evaluate.ValueLazyJSON', which the LSP uses.
  Eval.ValConstructor resolved [v]
    | getUnique resolved == TypeCheck.justUnique -> nfToFnLiteral ei v
  Eval.ValConstructor resolved vals -> do
    lits <- traverse (nfToFnLiteral ei) vals
    let name = constructorText resolved
        fieldNames = lookupFieldNames ei resolved
    pure $ case fieldNames of
      Just names | length names == length lits ->
        -- Constructor has named fields: produce an object with field names
        FnObject
          [ (name, FnObject (zip names lits))
          ]
      _ ->
        -- No field names available or count mismatch: fall back to array
        FnObject
          [ (name, FnArray lits)
          ]
  Eval.ValAssumed var _ ->
    throwError $ InterpreterError $ "#EVAL produced ASSUME: " <> prettyLayout var
  -- a result that holds a term is undetermined, not a value, so this is only
  -- for completeness
  Eval.ValTerm t ->
    throwError $ InterpreterError $ "#EVAL produced an unknown: " <> prettyLayout t

-- | A constructor's name, as a JSON payload should carry it.
--
-- NOT 'prettyLayout': that renders a 'Name' as L4 /source/, so an identifier
-- with spaces in it comes back backtick-quoted — and this value is compared by
-- clients against the @enum@ the service itself declared in its
-- @returnSchema@, which is built by 'L4.FunctionSchema.resolvedNameText' and
-- carries no backticks. So the service was handing out a schema and then
-- returning values that fail it: declared
-- @\"financial statements reviewed by an independent public accountant\"@,
-- returned
-- @\"\`financial statements reviewed by an independent public accountant\`\"@.
--
-- 'getActual' rather than 'getOriginal', matching 'L4.FunctionSchema', so that
-- the two agree by construction rather than by coincidence.
constructorText :: Resolved -> Text
constructorText = rawNameToText . rawName . getActual

-- | Look up field names for a constructor from the EntityInfo.
-- Returns 'Just' field names if the constructor has named fields, 'Nothing' otherwise.
-- First tries Unique-based lookup (fast, works for direct evaluation path),
-- then falls back to name-based lookup (for wrapper evaluation path where
-- re-typechecking generates different Uniques).
lookupFieldNames :: EntityInfo -> Resolved -> Maybe [Text]
lookupFieldNames ei resolved =
  case Map.lookup (getUnique resolved) ei of
    Just (_name, TypeCheck.KnownTerm conType Constructor) ->
      extractNonEmpty conType
    _ ->
      -- Fallback: search by name (wrapper path generates fresh Uniques)
      let targetName = nameToText (getActual resolved)
       in listToMaybe $ mapMaybe (matchByName targetName) (Map.elems ei)
  where
    extractNonEmpty conType =
      let names = extractFieldNamesFromType conType
       in if null names then Nothing else Just names
    matchByName target (name, TypeCheck.KnownTerm conType Constructor)
      | nameToText name == target = extractNonEmpty conType
    matchByName _ _ = Nothing

-- | Extract field names from a constructor's function type.
-- The constructor type is typically: forall args. (field1: Type1, field2: Type2, ...) -> ResultType
extractFieldNamesFromType :: Type' Resolved -> [Text]
extractFieldNamesFromType ty = case ty of
  Forall _ _ innerTy -> extractFieldNamesFromType innerTy
  Fun _ argTypes _resultTy -> mapMaybe getFieldName argTypes
  _ -> []
  where
    getFieldName :: OptionallyNamedType Resolved -> Maybe Text
    getFieldName (MkOptionallyNamedType _ maybeName _ty) =
      nameToText . TypeCheck.getName <$> maybeName

listToFnLiteral :: Monad m => EntityInfo -> DList FnLiteral -> Eval.NF -> ExceptT EvaluatorError m FnLiteral
listToFnLiteral _  acc Eval.Omitted                     = pure (FnArray (toList (DList.snoc acc FnUnknown)))
listToFnLiteral _  acc (Eval.MkNF Eval.ValNil)          = pure (FnArray (toList acc))
listToFnLiteral ei acc (Eval.MkNF (Eval.ValCons v1 v2)) = do
  l1 <- nfToFnLiteral ei v1
  listToFnLiteral ei (DList.snoc acc l1) v2
listToFnLiteral _  _acc (Eval.MkNF _)                   =
  throwError $ InterpreterError "#EVAL produced a type-incorrect list."

-- | Helper: serialized action info
data SerializedAction = SerializedAction
  { modal :: FnLiteral
  , actionPat :: FnLiteral
  }

-- | Serialize a regulative action (MUST/MAY/SHANT/DO action) to FnLiteral
serializeRAction :: RAction Resolved -> SerializedAction
serializeRAction (MkAction _ deonticModal pat _) =
  SerializedAction
    { modal = FnLitString $ case deonticModal of
        DMust    -> "MUST"
        DMay     -> "MAY"
        DMustNot -> "SHANT"
        DDo      -> "DO"
    , actionPat = FnLitString (Print.prettyLayout pat)
    }

-- | Serialize Either RExpr (Value NF) — used for obligation party and ROp operands
serializeEitherValue :: (Monad m) => EntityInfo -> Either (Expr Resolved) (Eval.Value Eval.NF) -> ExceptT EvaluatorError m FnLiteral
serializeEitherValue _  (Left expr)  = pure $ FnLitString (Print.prettyLayout expr)
serializeEitherValue ei (Right val)  = valueToFnLiteral ei val

-- | Serialize the deadline/due field of an obligation
--
-- An unevaluated deadline is its source form, @5@ or — anchored (R-Q7,
-- EVERY-EACH-QUANTIFIER-SPEC §5.1.1) — @5 OF THE JOIN@; an evaluated one is
-- the remaining due, a number.
serializeDue :: (Monad m) => EntityInfo -> Either (Maybe (Deadline Resolved)) (Eval.Value Eval.NF) -> ExceptT EvaluatorError m FnLiteral
serializeDue _  (Left Nothing)   = pure FnUnknown
serializeDue _  (Left (Just dl)) = pure $ FnLitString (closingText dl)
  where
    -- a BEFORE carries its keyword, so that a client can tell the absolute
    -- edge from a duration; a WITHIN is its body, as before (R-Q7)
    closingText = \ case
      d@MkDeadline{} -> Print.prettyLayout d
      d@MkBefore{}   -> "BEFORE " <> Print.prettyLayout d
serializeDue ei (Right val)      = valueToFnLiteral ei val

-- | Serialize the window's opening edge (EVERY-EACH-QUANTIFIER-SPEC §5.1.2,
-- built 2026-09-16): its source form before the first event (@3 OF THE
-- JOIN@), the time still to run until it opens after — and nothing at all
-- when there is no opening edge or the window has already opened.
serializeOpening :: (Monad m) => EntityInfo -> Either (Maybe (Opening Resolved)) (Maybe (Eval.Value Eval.NF)) -> ExceptT EvaluatorError m (Maybe FnLiteral)
serializeOpening _  (Left Nothing)    = pure Nothing
serializeOpening _  (Left (Just o))   = pure (Just (FnLitString (Print.prettyLayout o)))
serializeOpening _  (Right Nothing)   = pure Nothing
serializeOpening ei (Right (Just val)) = Just <$> valueToFnLiteral ei val

-- | Serialize a breach reason to FnLiteral.
--
-- The blame set (R-T3, EVERY-EACH-QUANTIFIER-SPEC §6.1, built 2026-09-15;
-- per-entry detail and no dedup RULED the same day): a breach names every
-- obligation that failed. On this wire the scalars (@obligatedParty@ \/
-- @obligationAction@ \/ @deadline@, or @party@ \/ @detail@) describe the
-- ANCHOR — the failure the breach's time comes from, one coherent obligation
-- — the array @obligatedParties@ \/ @parties@ is every party named in
-- operand \/ roll order with duplicates, @failures@ is one object per failed
-- obligation in the same order, and @anchor@ is the anchor's index into it.
-- For a single obligation's breach the arrays are one-element. The jl4-mlir
-- runtime mirrors this object byte-for-byte
-- (@jl4-mlir/runtime/jl4-runtime.mjs@, 'deonticBreachToWire'), so a key added
-- here is added there in the same change.
serializeBreachReason :: (Monad m) => EntityInfo -> Eval.ReasonForBreach Eval.NF -> ExceptT EvaluatorError m FnLiteral
serializeBreachReason ei = \case
  Eval.DeadlineMissed evParty evAction evTimestamp blame -> do
    evPartyLit <- nfToFnLiteral ei evParty
    evActionLit <- nfToFnLiteral ei evAction
    anchorLits <- case blame.anchor of
      Eval.MissedDeadline party action deadline -> do
        partyLit <- nfToFnLiteral ei party
        pure
          [ ("obligatedParty", partyLit)
          , ("obligationAction", (serializeRAction action).actionPat)
          , ("deadline", FnLitDouble $ fromRational deadline)
          ]
      -- unreachable by construction (a DeadlineMissed is anchored at a
      -- missed deadline); still a well-formed object rather than a crash
      Eval.DeclaredBreach mParty mReason -> do
        partyLit <- maybe (pure FnUnknown) (nfToFnLiteral ei) mParty
        reasonLit <- maybe (pure FnUnknown) (nfToFnLiteral ei) mReason
        pure [ ("obligatedParty", partyLit), ("detail", reasonLit) ]
    arrays <- blameLits "obligatedParties" blame
    pure $ FnObject $
      [ ("reason", FnLitString "deadline_missed")
      , ("eventParty", evPartyLit)
      , ("eventAction", evActionLit)
      , ("timestamp", FnLitDouble $ fromRational evTimestamp)
      ]
      <> anchorLits <> arrays
  Eval.ExplicitBreach blame -> do
    anchorLits <- case blame.anchor of
      Eval.DeclaredBreach mParty mReason -> do
        partyLit <- maybe (pure FnUnknown) (nfToFnLiteral ei) mParty
        reasonLit <- maybe (pure FnUnknown) (nfToFnLiteral ei) mReason
        pure [ ("party", partyLit), ("detail", reasonLit) ]
      -- unreachable by construction, as above
      Eval.MissedDeadline party action deadline -> do
        partyLit <- nfToFnLiteral ei party
        pure
          [ ("party", partyLit)
          , ("obligationAction", (serializeRAction action).actionPat)
          , ("deadline", FnLitDouble $ fromRational deadline)
          ]
    arrays <- blameLits "parties" blame
    pure $ FnObject $ [ ("reason", FnLitString "explicit") ] <> anchorLits <> arrays
  where
    -- the parties (under the given key), the failures, and the anchor's index
    blameLits partiesKey blame = do
      partyLits <- traverse (nfToFnLiteral ei) (Eval.blameParties blame)
      failureLits <- traverse failureLit (toList (Eval.blameList blame))
      pure
        [ (partiesKey, FnArray partyLits)
        , ("failures", FnArray failureLits)
        , ("anchor", FnLitInt (fromIntegral (Eval.anchorIndex blame)))
        ]
    failureLit = \case
      Eval.MissedDeadline party action deadline -> do
        partyLit <- nfToFnLiteral ei party
        pure $ FnObject
          [ ("reason", FnLitString "deadline_missed")
          , ("party", partyLit)
          , ("action", (serializeRAction action).actionPat)
          , ("deadline", FnLitDouble $ fromRational deadline)
          ]
      Eval.DeclaredBreach mParty mReason -> do
        partyLit <- maybe (pure FnUnknown) (nfToFnLiteral ei) mParty
        reasonLit <- maybe (pure FnUnknown) (nfToFnLiteral ei) mReason
        pure $ FnObject
          [ ("reason", FnLitString "explicit")
          , ("party", partyLit)
          , ("detail", reasonLit)
          ]

-- ----------------------------------------------------------------------------
-- L4 helpers
-- ----------------------------------------------------------------------------

typecheckModule :: (MonadIO m) => FilePath -> Text -> ModuleContext -> m ([Text], Maybe Rules.TypeCheckResult)
typecheckModule file input moduleContext = do
  fixedNow <- liftIO Eval.readFixedNowEnv
  evalConfig <- liftIO $ Eval.resolveEvalConfig fixedNow apiDefaultPolicy
  liftIO $ oneshotL4ActionAndErrors evalConfig file \nfp -> do
    let
      uri = normalizedFilePathToUri nfp
    -- Add all module files as virtual files for IMPORT resolution
    -- Note: embedded libraries are resolved by the import resolver via
    -- JL4_LIBRARY_PATH or Paths_jl4_core data-dir; no need to register
    -- them as virtual files here.
    forM_ (Map.toList moduleContext) $ \(path, content) -> do
      let modulePath = toNormalizedFilePath ("./" <> path)
      _ <- Shake.addVirtualFile modulePath content
      pure ()
    -- Add the main file
    _ <- Shake.addVirtualFile nfp input
    Shake.use Rules.TypeCheck uri

evaluateModule :: (MonadIO m) => Presumption -> FilePath -> Text -> ModuleContext -> m ([Text], Maybe [Eval.EvalDirectiveResult])
evaluateModule presumption file input moduleContext = do
  evalConfig <- liftIO $ requestEvalConfig apiDefaultPolicy presumption True
  result <- liftIO $ oneshotL4ActionAndErrors evalConfig file \nfp -> do
    let
      uri = normalizedFilePathToUri nfp
    -- Add all module files as virtual files for IMPORT resolution
    -- Note: embedded libraries are resolved by the import resolver via
    -- JL4_LIBRARY_PATH or Paths_jl4_core data-dir; no need to register
    -- them as virtual files here.
    forM_ (Map.toList moduleContext) $ \(path, content) -> do
      let modulePath = toNormalizedFilePath ("./" <> path)
      _ <- Shake.addVirtualFile modulePath content
      pure ()
    -- Add the main file
    _ <- Shake.addVirtualFile nfp input
    Shake.use Rules.EvaluateLazy uri
  -- The evaluator hit the allocation limit on a Shake thread, which reports
  -- an exception as a diagnostic. Raise it again here, on the calling thread,
  -- where 'withEvalLimits' answers it as the memory limit (smucclaw/l4-ide#1018).
  hit <- liftIO $ maybe (pure False) (readIORef . (.exceeded)) evalConfig.allocationLimit
  when hit $ liftIO (throwIO AllocationLimitExceeded)
  pure result

-- ----------------------------------------------------------------------------
-- L4 syntax builders
-- ----------------------------------------------------------------------------

mkNormalName :: Text -> RawName
mkNormalName = NormalName

-- ----------------------------------------------------------------------------
-- Trace builders
-- ----------------------------------------------------------------------------

buildReasoningTree :: Maybe EvalTrace -> Reasoning
buildReasoningTree Nothing  = emptyReasoning
buildReasoningTree (Just t) = traceToReasoning t

traceToReasoning :: EvalTrace -> Reasoning
traceToReasoning (Trace lbl [] val) =
  Reasoning
    { exampleCode = labelExample lbl
    , explanation = [resultLine val]
    , children = []
    }
traceToReasoning (Trace lbl [(expr, kids)] val) =
  Reasoning
    { exampleCode = labelExample lbl <> [Print.prettyLayout expr]
    , explanation = [resultLine val]
    , children = fmap traceToReasoning kids
    }
traceToReasoning (Trace lbl ((expr, kids) : rest) val) =
  traceToReasoning (Trace lbl [(expr, kids ++ [Trace lbl rest val])] val)

labelExample :: Maybe Resolved -> [Text]
labelExample = maybe [] (\resolved -> [nameToText (getOriginal resolved)])

resultLine :: Either EvalException Eval.NF -> Text
resultLine val =
  "Result: " <> case val of
    Left exc -> Text.unlines (Eval.prettyEvalException exc)
    Right v -> Print.prettyLayout v
