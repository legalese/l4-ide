module Compiler (
  compileBundle,
  computeVersion,
  toDecl,
) where

import qualified Backend.Jl4 as Jl4
import qualified L4.IgnoredAnnotation as IA
import Backend.Jl4 (ModuleContext, buildCompiledFromShared, typecheckAndEvalBundle)
import qualified L4.Evaluate.ValueLazy as EvalEnv (Environment)
import Backend.Api (EvalBackend (..), FunctionDeclaration (..))
import Shared (validateNoSanitizationCollisions)
import Backend.CodeGen (isDeonticType)
import L4.FunctionSchema (Parameters (..), Parameter (..), typeToParameter, declaresFromModule, typicallyToJson)
import L4.TypeCheck.Types (CheckErrorWithContext (..), CheckError (..), CheckWarning (..), Severity (..))
import L4.TypeCheck (prettyCheckErrorWithContext, severity)
import Types
import Control.Monad (forM, forM_, unless)
import qualified Crypto.Hash.SHA256 as SHA256
import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as Builder
import qualified Data.ByteString.Lazy as LBS
import Data.Aeson (toJSON)
import Data.List (sortBy)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Ord (comparing)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text.Encoding
import Data.Time (getCurrentTime)
import L4.Export (ExportedFunction (..), ExportedParam (..), getExportedFunctions, enrichReturnTypes, extractImplicitAssumeParams, honouredDefault, isRequiredInput)
import L4.Print (prettyTypeForDisplay)
import L4.Syntax (Resolved, Declare(..), Type'(..), RawName(..), Name, LifecyclePoint, getActual, lifecyclePointNoun, lifecyclePointWords, rawName, rawNameToText)
import L4.Parser.SrcSpan (SrcPos (..), SrcRange (..))
import Logging (Logger, logInfo, logWarn)
import qualified LSP.L4.Rules as Rules
import qualified L4.API.EmbeddedLibraries as EmbeddedLibraries
import System.FilePath (takeBaseName, takeExtension)

-- | Say, at WARN, which files of a bundle have the name of a standard library
-- module and a different text.
--
-- A bundle's own files are consulted before the stdlib, so an importer that can
-- see such a file (one beside it, or at the bundle root) gets that file where
-- the stdlib's module was meant. That is a right a bundle has, and sometimes
-- uses on purpose, but nothing else in the service says it happened: the
-- resolver reports a shadowing copy only when one is found on the filesystem
-- tiers, and the bundle's files are not. A copy of the stdlib's own text is
-- not a stand-in and is not reported.
logStdlibStandIns :: Logger -> Text -> [(FilePath, Text)] -> IO ()
logStdlibStandIns logger deployId l4Files =
  forM_ l4Files $ \(path, content) ->
    case EmbeddedLibraries.lookupEmbeddedLibrary (Text.pack (takeBaseName path)) of
      Just stdlib | stdlib /= content ->
        logWarn logger "Bundle file stands in for a standard library module"
          [ ("deploymentId", toJSON deployId)
          , ("file", toJSON path)
          , ("module", toJSON (takeBaseName path))
          ]
      _ -> pure ()

-- | Say, at WARN, which IMPORTs of a bundle resolved to nothing: the importing
-- file and the module name, under the deployment's ID.
--
-- A deployment resolves its IMPORTs against its own files and the stdlib built
-- into the service, and nothing from the host, so a module that is in neither
-- is not there for any caller. The deploy still goes through: the file
-- typechecks, and only a call that reaches something the missing module should
-- have defined fails, with a message about the identifier rather than the
-- module. Until this was logged nothing in the service said so, on a compile or
-- on a restart (ruled 2026-10-12, bench "Main Wave Rulings", card R5: a WARN
-- now, a refusal only by a later ruling).
logUnresolvedImports :: Logger -> Text -> [(FilePath, Text)] -> IO ()
logUnresolvedImports logger deployId unresolved =
  forM_ unresolved $ \(path, modName) ->
    logWarn logger "Bundle IMPORT resolves to nothing: no bundle file and no built-in standard library module has this name"
      [ ("deploymentId", toJSON deployId)
      , ("file", toJSON path)
      , ("module", toJSON modName)
      ]

-- | Compile an in-memory source map into a deployment-ready function registry.
--
-- Uses a SINGLE Shake session for the entire bundle: all files are typechecked
-- and evaluated together, so Shake automatically shares parse/typecheck/eval
-- results across the import graph. This avoids creating N independent IDE
-- sessions that redundantly re-process overlapping imports.
--
-- A deploy and a restart both come through here: the service keeps no cache
-- of a compiled deployment, so what it serves after a restart is what a deploy
-- of the same sources would serve, and is refused for the same reasons.
compileBundle
  :: Logger
  -> Text  -- ^ deployment ID for logging
  -> Map FilePath Text
  -> IO (Either Text (Map Text ValidatedFunction, DeploymentMetadata))
compileBundle logger deployId sources = do
  let l4Files = Map.toList $ Map.filterWithKey (\k _ -> takeExtension k == ".l4") sources
  if null l4Files
    then pure $ Left "No .l4 files found in bundle"
    else do
      let moduleContext = sources
          allPaths = map fst l4Files

      logStdlibStandIns logger deployId l4Files

      -- Phase 1: Typecheck ALL files in one Shake session.
      -- Pass all paths as needing eval environments — we'll discover which have
      -- exports from the typecheck results, then only the eval envs for those
      -- files will actually be used.
      (errs, tcMap, evalMap, unresolved, ignored) <- typecheckAndEvalBundle moduleContext allPaths
      logUnresolvedImports logger deployId unresolved

      -- Phase 2: Process typecheck results per file
      results <- forM l4Files $ \(filepath, content) ->
        case Map.lookup filepath tcMap of
          Just (Just tcResult) ->
            processTypecheckedFile logger deployId filepath content moduleContext tcResult evalMap
          _ -> do
            -- No result at all: the file did not parse, or did not get as far
            -- as being checked. The reason is in what the session reported.
            let why = [msg | (path, msg) <- errs, path == filepath]
            logWarn logger "Typecheck failed"
              [ ("deploymentId", toJSON deployId)
              , ("file", toJSON filepath)
              , ("errors", toJSON why)
              ]
            pure (filepath, Left (Text.intercalate "\n" (("Typecheck failed: " <> Text.pack filepath) : why)))

      -- An annotation line this version ignores is a warning in the editor and
      -- in `l4 check`, and here a REFUSAL. The lexer lets one through so that a
      -- file written for a newer L4 still opens in an older one; but a
      -- deployment is what the service PUBLISHES, and a misspelt `@export` is a
      -- rule that silently is not (the deploy was "applied" with no functions).
      -- The service refused every such line as a lexer error until then, and
      -- refuses the same ones still, now saying which annotation and what was
      -- probably meant. Nothing already stored can hold one, for that reason, so
      -- a restart, which comes through here too, refuses nothing it accepted.
      -- Every one is logged as well.
      forM_ ignored $ \(path, a) ->
        logWarn logger "Ignored annotation"
          [ ("deploymentId", toJSON deployId)
          , ("file", toJSON path)
          , ("message", toJSON (IA.renderIgnoredAnnotation a))
          ]
      let ignoredErrors =
            [ Text.pack path <> ":" <> IA.renderIgnoredAnnotation a
            | (path, a) <- ignored
            ]

      let allFunctionsWithFile = [ (fp, fn) | (fp, Right fns) <- results, fn <- fns ]
          allFunctions = map snd allFunctionsWithFile
          errors = [err | (_, Left err) <- results] <> ignoredErrors

      -- Any file that failed to compile (typecheck errors, unsupported
      -- @export inputs, …) fails the whole deploy. Previously this only
      -- rejected when NO file produced functions, so a bundle with one broken
      -- file and one good file would deploy the good half and silently drop
      -- the error — and a single broken file would deploy a garbage schema
      -- built from unresolved inference variables.
      if not (null errors)
        then pure $ Left $ Text.intercalate "\n" errors
        else do
          let fnMap = Map.fromList [(fn.fnImpl.name, fn) | fn <- allFunctions]

          now <- getCurrentTime
          let summaries = [FunctionSummary { fsName = fn.fnImpl.name, fsDescription = fn.fnImpl.description, fsParameters = fn.fnImpl.parameters, fsReturnType = fn.fnImpl.returnType, fsReturnSchema = fn.fnImpl.returnSchema, fsSection = Nothing, fsIsDeontic = fn.fnImpl.isDeontic, fsSourceFile = Just (Text.pack fp) } | (fp, fn) <- allFunctionsWithFile]
              version = computeVersion sources
              fileEntries = buildFileEntries deployId sources summaries
              meta = DeploymentMetadata
                { metaFunctions = summaries
                , metaFiles = fileEntries
                , metaVersion = version
                , metaCreatedAt = now
                -- compileBundle has no access to the operator-supplied
                -- description or the deploy-time version counters; callers
                -- inject them from the multipart field (deploy) or persisted
                -- StoredMetadata (restart).
                , metaDescription = Nothing
                , metaServiceVersion = ""
                , metaDeploymentVersion = ""
                }

          unless (null allFunctions) $
            logInfo logger "Compilation complete"
              [ ("deploymentId", toJSON deployId)
              , ("functionCount", toJSON (length allFunctions))
              ]

          pure $ Right (fnMap, meta)

-- | Process a single typechecked file: discover exports, build CompiledModules.
-- The typecheck result and evaluator import environment come from the shared
-- Shake session (not from per-file oneshot sessions).
processTypecheckedFile
  :: Logger
  -> Text  -- ^ deployment ID
  -> FilePath
  -> Text  -- ^ source content
  -> ModuleContext
  -> Rules.TypeCheckResult
  -> Map FilePath EvalEnv.Environment  -- ^ Import environments from shared session
  -> IO (FilePath, Either Text [ValidatedFunction])
processTypecheckedFile logger deployId filepath content moduleContext
  tcResult@Rules.TypeCheckResult{module' = resolvedModule, environment = env, entityInfo = ei, errors = tcErrors, infos = tcInfos}
  evalMap = do
    let exports = enrichReturnTypes ei $ getExportedFunctions resolvedModule
        -- Both spellings of "this export's input is a rule, not a value", so
        -- the deploy names the real cause instead of falling through to the
        -- generic type-error arm below (R-X4, 2026-09-07). Without the second
        -- pattern the new diagnostic still blocks the deploy, via blockingErrs,
        -- but is logged as "module has type errors".
        exportFnTypeErrs =
          [ msg
          | MkCheckErrorWithContext{kind} <- tcErrors
          , Just msg <- [exportInputRefusal kind]
          ]
        exportInputRefusal = \case
          ExportFunctionTypeInput fnName paramName -> Just $
            "Function type inputs are not supported for @export (parameter "
              <> resolvedText paramName <> " of " <> resolvedText fnName <> ")"
          ExportAssumeArityInput fnName paramName arity -> Just $
            "An @export input must be a value, not a rule: "
              <> resolvedText fnName <> " reads " <> resolvedText paramName
              <> ", which is assumed and takes " <> Text.pack (show arity)
              <> " input(s) of its own"
          _ -> Nothing
        -- Genuine type errors that must block the deploy. We deliberately
        -- tolerate OutOfScopeError: it's repurposed by extractImplicitAssumeParams
        -- to derive implicit ASSUME parameters, so a clean model with implicit
        -- ASSUMEs legitimately carries those. Anything else at SError severity
        -- (e.g. AmbiguousTermError, IncorrectArgsNumberApp) means the module
        -- didn't typecheck — compiling it anyway yields a garbage schema with
        -- unresolved inference variables (e.g. a return type of "res184"), which
        -- then trips the breaking-change check with a baffling message instead
        -- of surfacing the real error.
        blockingErrs =
          [ Text.intercalate " " (prettyCheckErrorWithContext e)
          | e@MkCheckErrorWithContext{kind} <- tcErrors
          , severity e == SError
          , not (isOutOfScope kind)
          ]
        -- THE JOIN / THE DEADLINE / THE ARMING written where the program has
        -- its own value of that spelling. The editor and `l4 check` warn; the
        -- service REFUSES (EVERY-EACH-QUANTIFIER-SPEC §2.6, B1a, ruled
        -- 2026-10-24), as it refuses an ignored annotation above: until
        -- 2026-10-24 that THE was an optional article, so such a module may
        -- mean the program's value, and under a HENCE the change is a
        -- different number with no error. A deployment stored before then that
        -- holds one is refused when a restart recompiles it, which is the
        -- point: its answers would have moved silently. A warning is in
        -- 'infos', not 'errors', which carries only what blocks 'success'.
        hidesNameErrs =
          [ hidesNameRefusal filepath p mr defined imported
          | MkCheckErrorWithContext{kind = CheckWarning (LifecycleNounHidesName p mr defined imported)} <- tcInfos
          ]
    if not (null exportFnTypeErrs)
      then do
        logWarn logger "Deploy rejected: an @export input is a rule, not a value"
          [ ("deploymentId", toJSON deployId)
          , ("file", toJSON filepath)
          , ("errors", toJSON exportFnTypeErrs)
          ]
        pure (filepath, Left (Text.intercalate "; " exportFnTypeErrs))
      else if not (null blockingErrs)
      then do
        logWarn logger "Deploy rejected: module has type errors"
          [ ("deploymentId", toJSON deployId)
          , ("file", toJSON filepath)
          , ("errors", toJSON blockingErrs)
          ]
        pure (filepath, Left (Text.intercalate "\n" blockingErrs))
      else if not (null hidesNameErrs)
      then do
        logWarn logger "Deploy rejected: THE before a noun hides a name"
          [ ("deploymentId", toJSON deployId)
          , ("file", toJSON filepath)
          , ("errors", toJSON hidesNameErrs)
          ]
        pure (filepath, Left (Text.intercalate "\n" hidesNameErrs))
      else if null exports
      then pure (filepath, Right [])
      else do
        let implicitParams = extractImplicitAssumeParams tcErrors
            allDeclares = collectAllDeclares tcResult
            -- Look up the import environment from the shared session
            importEnv = Map.findWithDefault Jl4.emptyEvalEnvironment filepath evalMap

        -- Build shared context for all functions from this file.
        -- `collectAllDeclares` walks the entry file + every
        -- transitively-imported module's DECLAREs. We stash the full
        -- list on the shared context so the direct-AST evaluator
        -- ('buildModuleInfo') can resolve record parameter types that
        -- live in IMPORT'd files — e.g. the ASEAN Cosmetic Directive's
        -- `Cosmetic Product` record declared in ACD_Declarations.l4
        -- while the @export lives in ACD_Information.l4.
        let shared = Jl4.SharedModuleContext
              { Jl4.sharedModule = resolvedModule
              , Jl4.sharedEnvironment = env
              , Jl4.sharedEntityInfo = ei
              , Jl4.sharedModuleContext = moduleContext
              , Jl4.sharedImportEnv = importEnv
              , Jl4.sharedSource = content
              , Jl4.sharedAllDeclares = Map.elems allDeclares
              }

        fns <- forM exports $ \export -> do
          let fnDecl = exportToFunction allDeclares implicitParams export
              apiDecl = toDecl fnDecl

          let collisions = validateNoSanitizationCollisions fnDecl.name fnDecl.parameters
          unless (null collisions) $ do
            let collisionMsg = Text.intercalate "\n  " collisions
            logWarn logger "Property name sanitization collision"
              [ ("deploymentId", toJSON deployId)
              , ("function", toJSON fnDecl.name)
              , ("collisions", toJSON collisions)
              ]
            error $ Text.unpack $ "Compilation failed for function '" <> fnDecl.name
              <> "': field name collision after sanitization (spaces and hyphens "
              <> "become indistinguishable in API/MCP schemas):\n  " <> collisionMsg

          let funRawName = NormalName apiDecl.name
          mCompiled <- buildCompiledFromShared shared funRawName
          case mCompiled of
            Right compiled -> do
              let runFn = Jl4.createRunFunctionFromCompiled filepath apiDecl compiled content moduleContext
              pure ValidatedFunction
                { fnImpl = fnDecl
                , fnEvaluator = Map.fromList [(JL4, runFn)]
                , fnCompiled = Just compiled
                , fnSourceText = content
                , fnModuleContext = moduleContext
                , fnDecisionQueryCache = Nothing
                }
            Left _err -> do
              -- Fallback: use original createFunction path (per-file session)
              (runFn, mComp) <- Jl4.createFunction filepath apiDecl content moduleContext
              pure ValidatedFunction
                { fnImpl = fnDecl
                , fnEvaluator = Map.fromList [(JL4, runFn)]
                , fnCompiled = mComp
                , fnSourceText = content
                , fnModuleContext = moduleContext
                , fnDecisionQueryCache = Nothing
                }

        logInfo logger "Found exports"
          [ ("deploymentId", toJSON deployId)
          , ("file", toJSON filepath)
          , ("exportCount", toJSON (length fns))
          ]
        pure (filepath, Right fns)

-- | Convert an ExportedFunction to our Function type.
exportToFunction :: Map Text (Declare Resolved) -> [(Text, Type' Resolved)] -> ExportedFunction -> Function
exportToFunction declares implicitParams export =
  let baseParams = parametersFromExport declares export.exportParams
      -- Merge implicit params, avoiding duplicates
      implicitParamMap = Map.fromList
        [ (pname, (typeToParameter declares Set.empty ty) {parameterDescription = "", parameterAlias = Nothing})
        | (pname, ty) <- implicitParams
        , pname `Map.notMember` baseParams.parameterMap
        ]
      mergedParams = baseParams
        { parameterMap = baseParams.parameterMap <> implicitParamMap
        , required = baseParams.required <> Map.keys implicitParamMap
        }
      -- Detect deontic return type and extract party/action type names
      isDeontic = case export.exportReturnType of
        Just ty -> isDeonticType ty
        Nothing -> False
      (mPartyType, mActionType) = case export.exportReturnType of
        Just ty -> case extractDeonticTypeNames ty of
          Just (p, a) -> (Just p, Just a)
          Nothing -> (Nothing, Nothing)
        Nothing -> (Nothing, Nothing)
      -- Build typed event schema using actual party/action types
      (partyParam, actionParam) = case export.exportReturnType of
        Just (TyApp _ _ [partyTy, actionTy]) ->
          ( (typeToParameter declares Set.empty partyTy) { parameterDescription = "The party performing the action" }
          , (typeToParameter declares Set.empty actionTy) { parameterDescription = "The action performed" }
          )
        _ -> ( Parameter "object" Nothing Nothing [] "The party performing the action" Nothing Nothing Nothing Nothing Nothing Nothing
             , Parameter "object" Nothing Nothing [] "The action performed" Nothing Nothing Nothing Nothing Nothing Nothing
             )
      finalParams = if isDeontic
        then mergedParams
          { parameterMap = mergedParams.parameterMap <> Map.fromList
              [ ("startTime", Parameter "number" Nothing Nothing [] "Start time for contract simulation" Nothing Nothing Nothing Nothing Nothing Nothing)
              , ("events", Parameter
                  { parameterType = "array"
                  , parameterAlias = Nothing
                  , parameterFormat = Nothing
                  , parameterEnum = []
                  , parameterDescription = "Events for contract simulation (each: {party, action, at})"
                  , parameterProperties = Nothing
                  , parameterPropertyOrder = Nothing
                  , parameterItems = Just $ Parameter
                      { parameterType = "object"
                      , parameterAlias = Nothing
                      , parameterFormat = Nothing
                      , parameterEnum = []
                      , parameterDescription = "A trace event"
                      , parameterProperties = Just $ Map.fromList
                          [ ("party", partyParam)
                          , ("action", actionParam)
                          , ("at", Parameter "number" Nothing Nothing [] "Timestamp" Nothing Nothing Nothing Nothing Nothing Nothing)
                          ]
                      , parameterPropertyOrder = Just ["party", "action", "at"]
                      , parameterItems = Nothing
                      , parameterRequired = Just ["party", "action", "at"]
                      , parameterL4Type = Nothing
                      , parameterDefault = Nothing
                      }
                  , parameterRequired = Nothing
                  , parameterL4Type = Nothing
                  , parameterDefault = Nothing
                  })
              ]
          , required = mergedParams.required <> ["startTime", "events"]
          }
        else mergedParams
      -- Structured return schema (with x-l4-type annotations on record/enum nodes).
      -- For DEONTIC functions the surface return shape is the simulation envelope,
      -- not the user's record type, so we leave the structured schema unset there.
      mReturnSchema = case export.exportReturnType of
        Just retTy | not isDeontic -> Just (typeToParameter declares Set.empty retTy)
        _ -> Nothing
  in Function
    { name = export.exportName
    , description =
        let desc = Text.strip export.exportDescription
        in if Text.null desc then "Exported function" else desc
    , parameters = finalParams
    , supportedEvalBackend = [JL4]
    , deonticPartyType = mPartyType
    , deonticActionType = mActionType
    , returnType = returnTypeDisplay export.exportReturnType
    , returnSchema = mReturnSchema
    , isDeontic = isDeontic
    }

-- | Build Parameters from ExportedParam list.
--
-- An input with a default a request may leave out is not @required@, and the
-- default is published as the JSON Schema @default@ keyword (W2 of
-- specs/todo/TYPICALLY-ONE-BEHAVIOUR-SPEC.md; R8's schema surface). The
-- schema describes presumption soft, the default; a @"presumption": "hard"@
-- request must supply every input.
parametersFromExport :: Map Text (Declare Resolved) -> [ExportedParam] -> Parameters
parametersFromExport declares params =
  MkParameters
    { parameterMap = Map.fromList [(param.paramName, paramToParameter declares param) | param <- params]
    , required = [param.paramName | param <- params, isRequiredInput param]
    }

-- | Convert an ExportedParam to a Parameter.
paramToParameter :: Map Text (Declare Resolved) -> ExportedParam -> Parameter
paramToParameter declares param =
  let p0 = maybe
              (Parameter "object" Nothing Nothing [] "" Nothing Nothing Nothing Nothing Nothing Nothing)
              (typeToParameter declares Set.empty)
              param.paramType
  in p0
    { parameterAlias = Nothing
    , parameterDescription = Text.strip $ maybe "" id param.paramDescription
    , parameterDefault = typicallyToJson =<< honouredDefault param
    }

-- | Convert a Function to a FunctionDeclaration for the Backend.
toDecl :: Function -> FunctionDeclaration
toDecl fn =
  FunctionDeclaration
    { Backend.Api.name = fn.name
    , Backend.Api.description = fn.description
    , Backend.Api.longNames = Map.keysSet fn.parameters.parameterMap
    , Backend.Api.nameMapping = shortToLongNameMapping
    }
 where
  shortToLongNameMapping :: Map Text Text
  shortToLongNameMapping =
    Map.fromList
      [ (alias, long)
      | (long, param) <- Map.toList fn.parameters.parameterMap
      , Just alias <- [param.parameterAlias]
      ]

-- | Extract party and action type names from a DEONTIC return type.
-- Given: DEONTIC Party `Contract Action` → Just ("Party", "Contract Action")
extractDeonticTypeNames :: Type' Resolved -> Maybe (Text, Text)
extractDeonticTypeNames ty@(TyApp _ _ [partyTy, actionTy])
  | isDeonticType ty = Just (typeName partyTy, typeName actionTy)
  where
    typeName :: Type' Resolved -> Text
    typeName (TyApp _ n _) = rawNameToText (rawName (getActual n))
    typeName _ = "Unknown"
extractDeonticTypeNames _ = Nothing

-- | Extract display text from a Resolved name.
resolvedText :: Resolved -> Text
resolvedText = rawNameToText . rawName . getActual

-- | OutOfScopeError is not a deploy-blocking error: it's how the type checker
-- reports references the compiler turns into implicit ASSUME parameters (see
-- 'extractImplicitAssumeParams'). Every other SError-severity kind is genuine.
isOutOfScope :: CheckError -> Bool
isOutOfScope OutOfScopeError{} = True
isOutOfScope _                 = False

-- | Collect all DECLARE entries from a TypeCheckResult and its transitive imports.
--
-- Each module is read once ('Rules.transitiveDependencies'), in the order the
-- old recursion into @tc.dependencies@ first met it, so the left-biased union
-- keeps the same entry for a name declared twice. That recursion read a module
-- once per import path, exponentially many times in the depth of the imports
-- (smucclaw\/l4-ide#1008).
collectAllDeclares :: Rules.TypeCheckResult -> Map Text (Declare Resolved)
collectAllDeclares tc =
  foldMap (declaresFromModule . (.module')) (tc : Rules.transitiveDependencies tc)

-- | Display the return type of an exported function as a user-facing string.
-- Delegates to 'prettyTypeForDisplay' so the rendering matches exactly what the
-- LSP reports for the same type (the deploy-sidebar diff compares the two
-- strings) AND so residual inference variables render as stable type-variable
-- names rather than edit-order-dependent ids like @res184@. The previous
-- bespoke renderer collapsed @DEONTIC P A@ to just @"DEONTIC"@ and dropped the
-- @OF@ keyword for other parameterized types (e.g. @LIST NUMBER@ instead of
-- @LIST OF NUMBER@), causing spurious "return type changed" warnings on every
-- redeploy.
returnTypeDisplay :: Maybe (Type' Resolved) -> Text
returnTypeDisplay Nothing = "unknown"
returnTypeDisplay (Just ty) = prettyTypeForDisplay ty

-- | Compute SHA-256 version from sorted source contents.
computeVersion :: Map FilePath Text -> Text
computeVersion sources =
  let sorted = sortBy (comparing fst) (Map.toList sources)
      payload = LBS.toStrict $ Builder.toLazyByteString $ mconcat
        [ Builder.byteString (Text.Encoding.encodeUtf8 $ Text.pack path)
          <> Builder.word8 0
          <> Builder.byteString (Text.Encoding.encodeUtf8 content)
          <> Builder.word8 0
        | (path, content) <- sorted
        ]
      digest = SHA256.hash payload
  in Text.pack $ concatMap (\b -> let h = showHex b "" in if length h == 1 then '0':h else h) (BS.unpack digest)

showHex :: Integral a => a -> ShowS
showHex n
  | n < 16 = showChar (intToDigit (fromIntegral n))
  | otherwise = showHex (n `div` 16) . showChar (intToDigit (fromIntegral (n `mod` 16)))
 where
  intToDigit :: Int -> Char
  intToDigit i
    | i < 10 = toEnum (fromEnum '0' + i)
    | otherwise = toEnum (fromEnum 'a' + i - 10)

-- | Build file entries from the source map and function summaries.
-- Every .l4 file gets an entry; exports are populated from summaries that
-- have a matching 'fsSourceFile'.
buildFileEntries :: Text -> Map FilePath Text -> [FunctionSummary] -> [FileEntry]
buildFileEntries deployId sources summaries =
  let l4Paths = [fp | fp <- Map.keys sources, takeExtension fp == ".l4"]
      exportsByFile = Map.fromListWith (++)
        [ (sf, [fs.fsName])
        | fs <- summaries
        , Just sf <- [fs.fsSourceFile]
        ]
  in [ FileEntry
         { fePath = "/deployments/" <> deployId <> "/files/" <> Text.pack fp
         , feExports = maybe [] id (Map.lookup (Text.pack fp) exportsByFile)
         }
     | fp <- sortBy (comparing id) l4Paths
     ]

-- | Why a module whose @THE JOIN@ (or @THE DEADLINE@, @THE ARMING@) hides a
-- name of the program's own is not deployed ('LifecycleNounHidesName'): which
-- name is hidden, and that dropping THE reaches it. Renaming is offered only
-- when this module defines every such name; an imported one may be defined in
-- a file the deployer does not own.
hidesNameRefusal :: FilePath -> LifecyclePoint -> Maybe SrcRange -> [Name] -> [Name] -> Text
hidesNameRefusal filepath p mr defined imported =
  Text.pack filepath <> at <> ": " <> words' <> " here is the lifecycle position, and it hides "
    <> Text.intercalate ", " names <> ", which this module " <> whose <> "."
    <> " Write " <> noun <> " without THE to reach the program's own " <> firstName <> rename <> "."
  where
    at = maybe "" (\ r -> ":" <> Text.pack (show r.start.line) <> ":" <> Text.pack (show r.start.column)) mr
    words' = lifecyclePointWords p
    noun = lifecyclePointNoun p
    names = [ "`" <> rawNameToText (rawName n) <> "`" | n <- defined <> imported ]
    firstName = case names of
      n : _ -> n
      []    -> "`" <> noun <> "`"
    whose = case (defined, imported) of
      (_ : _, _ : _) -> "defines and imports"
      ([], _)        -> "imports"
      (_, [])        -> "defines"
    rename
      | null imported = ", or rename it to keep " <> words'
      | otherwise     = ""
