{-# LANGUAGE OverloadedStrings #-}

-- | Where a bare @IMPORT@ looks in a bundle that has folders.
--
-- A bundle is a tree of files that were uploaded, and the service registers
-- each at @./<its path>@. An @IMPORT zdefs@ finds a module in two places: beside
-- the importing file, and at the /root/ of the bundle, which is @.@, the place
-- every file is registered under. The session used to take as its root the
-- folder of whichever file sorted first in the bundle (or, for a call that goes
-- through the generated wrapper, the folder of the function's own file), so a
-- flat bundle, whose files are all in @.@, never showed it, and a bundle with
-- folders found a module at its top only when the first file in sort order
-- happened to be there. The deploy said "ready" and every call then answered
-- @zmark is not in scope@.
--
-- Each case is called twice, because the two ways the service evaluates a call
-- open different sessions: the direct path uses the environment built when the
-- bundle was compiled, and a request that holds a @{}@ goes through a wrapper
-- that is typechecked and evaluated in a session of its own.
--
-- The root is named at four places in "Backend.Jl4", and the cases above reach
-- two of them: the compile of the whole bundle (@typecheckAndEvalBundle@, which
-- a deploy runs) and the evaluation of the wrapper (@evaluateModule@, which a
-- call that holds a @{}@ runs). The other two, 'typecheckModule' and
-- 'buildImportEnvironment', are the two halves of @precompileModule@, which
-- 'createFunction' calls. The compiler reaches 'createFunction' only as the
-- fallback for a function that @buildCompiledFromShared@ could not build (the
-- @Left@ arm in @processTypecheckedFile@, @Compiler.hs@), so no request in the
-- cases above gets there. The cases at the end call each of the two directly,
-- and then 'createFunction' as a whole.
module BundleRootSpec (spec) where

import Test.Hspec

import Backend.Api (EvaluatorError (..), FnLiteral (..), FunctionDeclaration (..), Presumption (..), ResponseWithReason (..), RunFunction (..), TraceLevel (..))
import Backend.Jl4 (buildImportEnvironment, createFunction, emptyEvalEnvironment, typecheckModule)
import IntegrationSpec (evalFunction, withServiceFromSources)
import LSP.L4.Rules (TypeCheckResult (..))
import Types (SimpleResponse (..))

import Control.Exception (finally)
import Control.Monad.Trans.Except (runExceptT)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Maybe (isJust)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text.Encoding
import Network.HTTP.Client (Response, responseBody, responseStatus)
import Network.HTTP.Types.Status (statusCode)
import System.Directory (createDirectoryIfMissing, removePathForcibly, withCurrentDirectory)
import System.FilePath ((</>))
import System.IO.Temp (createTempDirectory, getCanonicalTemporaryDirectory)

-- | What a call came to. A call that cannot find its module is told apart from
-- one that fails for another reason, so that a case expected to fail cannot
-- pass on, say, a compile error.
data Outcome
  = Answers FnLiteral
  | Unresolved Text  -- ^ the module was not found, so what it defines is undefined
  | Failed Int Text  -- ^ anything else, with the HTTP status and the body
  deriving (Eq, Show)

-- | The two ways an import that found nothing shows in a call: the direct path
-- says that the name it should have got from the module "is not in scope", and
-- the wrapper path, which runs a session of its own, returns that session's
-- log, which says "Module not found".
outcomeOf :: Response LBS.ByteString -> Outcome
outcomeOf resp = case Aeson.decode (responseBody resp) of
  Just (SimpleResponse r)
    | Just v <- Map.lookup "value" r.fnResult -> Answers v
  Just (SimpleError (InterpreterError msg))
    | any (`Text.isInfixOf` msg) ["is not in scope", "Module not found"] -> Unresolved msg
  _ -> Failed (statusCode (responseStatus resp)) (Text.Encoding.decodeUtf8 (LBS.toStrict (responseBody resp)))

-- | An exported rule that adds @zmark@, which the imported module defines, to
-- its input. @flag@ is read by nothing: it is there so that a call can send
-- @{}@ for it, which takes the wrapper path.
importing :: Text -> Text
importing moduleName = Text.unlines
  [ "IMPORT " <> moduleName
  , ""
  , "@export Add the marker"
  , "GIVEN x    IS A NUMBER"
  , "      flag IS A BOOLEAN"
  , "GIVETH A NUMBER"
  , "DECIDE addmark x flag IS x PLUS zmark"
  ]

-- | The module the rule above reads.
defining :: Text
defining = "zmark MEANS 100\n"

-- | A file that exports nothing and defines nothing the others read.
filler :: Text
filler = "unrelated MEANS 1\n"

args :: Aeson.Value -> Aeson.Value
args flag = Aeson.object
  [ "arguments" Aeson..= Aeson.object [ "x" Aeson..= (5 :: Int), "flag" Aeson..= flag ] ]

-- | Deploy the files and call @addmark@ with 5, twice: directly, and by way of
-- the wrapper.
bothPaths :: Text -> [(FilePath, Text)] -> IO (Outcome, Outcome)
bothPaths deployId files = withServiceFromSources deployId files \baseUrl mgr -> do
  direct  <- outcomeOf <$> evalFunction baseUrl mgr deployId "addmark" (args (Aeson.toJSON True))
  wrapped <- outcomeOf <$> evalFunction baseUrl mgr deployId "addmark" (args (Aeson.object []))
  pure (direct, wrapped)

answers105 :: (Outcome, Outcome)
answers105 = (Answers (FnLitInt 105), Answers (FnLitInt 105))

spec :: Spec
spec = bundleSpec >> entryPointSpec

bundleSpec :: Spec
bundleSpec = describe "a bare IMPORT in a bundle resolves beside the importer, then at the bundle's root" do

  it "finds a sibling in a flat bundle (control: the bundle has no folders)" do
    bothPaths "root-flat" [("x.l4", importing "zdefs"), ("zdefs.l4", defining)]
      `shouldReturn` answers105

  it "finds a sibling in a folder" do
    bothPaths "root-siblings" [("a/x.l4", importing "zdefs"), ("a/zdefs.l4", defining)]
      `shouldReturn` answers105

  it "finds a module at the top of the bundle from a file in a folder" do
    bothPaths "root-top" [("a/x.l4", importing "zdefs"), ("zdefs.l4", defining)]
      `shouldReturn` answers105

  it "finds a module at the top of the bundle from a file in a folder whose name has a space" do
    -- What `l4 deploy` and the extension's deploy rely on when they let a file
    -- in such a folder through: a lookup that ends at the top is not affected
    -- by the name of the importer's folder (measured 2026-10-26).
    bothPaths "root-top-space" [("my dir/x.l4", importing "zdefs"), ("zdefs.l4", defining)]
      `shouldReturn` answers105

  it "finds a sibling in a folder whose name has a space" do
    -- PENDING, a defect in the resolver shared with the language server and
    -- not in this module, and a residual of the fix for smucclaw/l4-ide#971
    -- (closed; no issue tracks the residual yet): the candidate beside the
    -- importer is the relative path `my dir/helper.l4`, which `file:` URIs
    -- cannot spell (`roundTrippingFileUri` in LSP/L4/Rules.hs falls back to an
    -- absolute path, which is not the key the bundle's files are registered
    -- under), so the module is never found. The deploy says "ready" and every
    -- call answers "zmark is not in scope". Measured 2026-10-26 on this
    -- service, with throwaway cases in this harness that are not kept: the
    -- first folder of the path decides (`ok/my dir` is found, `my dir`,
    -- `a b/c`, `dossier é` and a Hebrew name are not; `a`, `my-dir_2.x` and
    -- `v1.2` are), and so does the file's own name at the top (`my mod.l4` is
    -- not found, `a/my mod.l4` is). `l4 deploy` and the extension's deploy
    -- refuse such a folder until this passes: delete the next line, and the
    -- refusal with it (`UnsafeFolder` in DeployPlan.hs, `collectBundle` in
    -- deploy-bundle.ts).
    pendingWith "a residual of the fix for smucclaw/l4-ide#971 (closed), tracked by no issue yet: a relative path whose first part needs a percent-escape cannot be spelled in a file: URI that reads back, so the candidate beside the importer is lost"
    bothPaths "root-siblings-space" [("my dir/x.l4", importing "helper"), ("my dir/helper.l4", defining)]
      `shouldReturn` answers105

  it "does not depend on which file sorts first" do
    -- `aaa.l4` is the file the service used to take the root from. The importer
    -- is in a folder, so the root its own call opened was that folder.
    bothPaths "root-first" [("aaa.l4", filler), ("sub/x.l4", importing "zdefs"), ("zdefs.l4", defining)]
      `shouldReturn` answers105

  it "does not find a module in a folder that is neither the importer's nor the root" do
    -- The one case here in which a module that was found is no longer found,
    -- and the owner has not ruled on it. The compile of the bundle and a call
    -- on the direct path used to find it, because `a/helper.l4` sorts first and
    -- so its folder was the root of the whole-bundle session: with the folder
    -- called `c`, or any other file ahead of it, they did not. A call on the
    -- wrapper path did not find it before either, because its session took the
    -- function's own folder (`b`) as its root (see the header). The module is
    -- beside neither the importer (`b`) nor the top of the bundle, so a bare
    -- name does not reach it. This version of the language has no import that
    -- names a file in another folder: IMPORT `a/helper` is read as the bare
    -- name `helper`.
    (direct, wrapped) <- bothPaths "root-elsewhere" [("a/helper.l4", defining), ("b/x.l4", importing "helper")]
    direct `shouldSatisfy` isUnresolved
    wrapped `shouldSatisfy` isUnresolved

  it "lets a prelude.l4 at the top of the bundle stand in for the stdlib's, for importers in folders too" do
    -- The bundle's own `sum` answers a STRING and the rule declares a STRING,
    -- so the bundle compiles only if `IMPORT prelude` reached the bundle's file.
    -- `a/main.l4` sorts before `prelude.l4`, as `aaa.l4` does above.
    let bundlePrelude = Text.unlines
          [ "GIVEN xs IS A LIST OF NUMBER"
          , "GIVETH A STRING"
          , "sum xs MEANS \"the bundle's own sum\""
          ]
        usesIt = Text.unlines
          [ "IMPORT prelude"
          , ""
          , "@export Which sum"
          , "GIVEN xs IS A LIST OF NUMBER"
          , "GIVETH A STRING"
          , "DECIDE which_sum xs IS sum xs"
          ]
    withServiceFromSources "root-prelude" [("a/main.l4", usesIt), ("prelude.l4", bundlePrelude)] \baseUrl mgr -> do
      resp <- evalFunction baseUrl mgr "root-prelude" "which_sum"
        (Aeson.object [ "arguments" Aeson..= Aeson.object [ "xs" Aeson..= [1, 2, 3 :: Int] ] ])
      outcomeOf resp `shouldBe` Answers (FnLitString "the bundle's own sum")

  it "does not read the service's working directory, which is where the root points (positive control: the bundle's own file is found)" do
    -- The root is `.`, which for the process is its working directory. A module
    -- of that name on the host is not part of the deployment (the same rule as
    -- for the stdlib, see "StdlibResolutionSpec").
    tmp <- getCanonicalTemporaryDirectory
    host <- createTempDirectory tmp "jl4-service-bundle-root-spec"
    (do
        createDirectoryIfMissing True host
        writeFile (host </> "stray.l4") "zmark MEANS 7\n"
        withCurrentDirectory host do
          strayInFolder <- bothPaths "root-stray" [("a/x.l4", importing "stray")]
          strayInFolder `shouldSatisfy` bothUnresolved
          owned <- bothPaths "root-stray-owned" [("a/x.l4", importing "stray"), ("stray.l4", defining)]
          owned `shouldBe` answers105)
      `finally` removePathForcibly host
  where
    isUnresolved = \case
      Unresolved _ -> True
      _            -> False
    bothUnresolved (a, b) = isUnresolved a && isUnresolved b

-- | The two halves of @precompileModule@ and @createFunction@, which the cases
-- above do not reach (see the header). Each takes the same bundle the cases
-- above deploy, @{a/x.l4 (IMPORT zdefs), zdefs.l4}@, and the file in the
-- folder as the one to compile.
entryPointSpec :: Spec
entryPointSpec = describe "the single-file entry points resolve a bare IMPORT from the bundle's root too" do
  let atTop = [("a/x.l4", importing "zdefs"), ("zdefs.l4", defining)]
      flat = [("x.l4", importing "zdefs"), ("zdefs.l4", defining)]
      elsewhere = [("a/helper.l4", defining), ("b/x.l4", importing "helper")]

      -- Whether the file at @path@, which imports @moduleName@, typechecks.
      typechecks path moduleName files = do
        (_, mTc) <- typecheckModule path (importing moduleName) (Map.fromList files)
        pure (fmap (.success) mTc)

      importEnvSize path moduleName files = do
        env <- buildImportEnvironment path (importing moduleName) (Map.fromList files) Map.empty
        pure (Map.size env)

  describe "typecheckModule" do
    it "finds a module at the top of the bundle from a file in a folder (control: the same files, flat)" do
      typechecks "x.l4" "zdefs" flat `shouldReturn` Just True
      typechecks "a/x.l4" "zdefs" atTop `shouldReturn` Just True

    it "does not find a module in a folder that is neither the importer's nor the top (so the cases above can fail)" do
      typechecks "b/x.l4" "helper" elsewhere `shouldReturn` Just False

  describe "buildImportEnvironment" do
    it "evaluates the imports of a file in a folder that imports a module at the top, as it does when the files are flat" do
      folder <- importEnvSize "a/x.l4" "zdefs" atTop
      control <- importEnvSize "x.l4" "zdefs" flat
      -- An import that is not found falls back to an environment that holds
      -- nothing of the module (`emptyEnvironment`), silently.
      folder `shouldSatisfy` (> Map.size emptyEvalEnvironment)
      folder `shouldBe` control

  describe "createFunction" do
    it "answers a call to a file in a folder that imports a module at the top, on the path that uses the compiled import environment" do
      let decl = FunctionDeclaration
            { name = "addmark"
            , description = "Add the marker"
            , longNames = Set.fromList ["x", "flag"]
            , nameMapping = Map.empty
            }
      (runFn, compiled) <- createFunction "a/x.l4" decl (importing "zdefs") (Map.fromList atTop)
      -- The fast path: the module was precompiled, not left to the slow path.
      isJust compiled `shouldBe` True
      r <- runExceptT (runFn.runFunction [("x", Just (FnLitInt 5)), ("flag", Just (FnLitBool True))] Nothing TraceNone False PresumeSoft)
      case r of
        Right rwr -> Map.lookup "value" rwr.fnResult `shouldBe` Just (FnLitInt 105)
        Left _ -> expectationFailure "the call did not answer"
