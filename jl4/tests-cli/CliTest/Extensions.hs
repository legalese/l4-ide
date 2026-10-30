-- | Black-box tests for the extension hook of the @l4@ command line
-- ("L4.Cli.Extensions"). The community @l4@ is @mainWith noExtensions@, so
-- nothing in it reaches the hook; these tests build an executable that does.
--
-- That executable is this test suite itself. When the environment variable
-- 'probeEnv' is set, 'Main.main' runs 'probeMain' instead of hspec, and the
-- tests spawn the test binary with the variable set to one of the variants
-- of 'probeExtensions', then assert on exit status and output as for any
-- other command. A variant is an 'Extensions' that is good ("all"), is empty
-- ("none"), or has the fault its name says.
module CliTest.Extensions (spec, probeMain, probeEnv) where

import qualified Base.Map as Map
import Data.List (isInfixOf, isSuffixOf)
import Data.Maybe (fromMaybe, isJust)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import Options.Applicative (helper, info, progDesc, strArgument, metavar)
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist)
import System.Environment (getEnvironment, getExecutablePath)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec

import L4.Cli.Common (FixedNowOpt (..), LoadedModule (..), TypeCheckResult (..), loadChecked, loadCheckedEvaluated, makeEvalConfig)
import L4.Cli.Extensions
import L4.Cli.Main (mainWith)
import L4.EvaluateLazy (AssertionOutcome (..), EvalDirectiveResult (..), EvalDirectiveValue (..))
import L4.Lts.Explore.Emit.Model (EmitInput (..))

import CliTest.Common

-- | The environment variable that makes the test binary run as the probe.
probeEnv :: String
probeEnv = "L4_EXT_PROBE"

-- | The probe: the community command line with the variant's extensions.
probeMain :: String -> IO ()
probeMain variant = mainWith (probeExtensions variant)

probeExtensions :: String -> Extensions
probeExtensions = \ case
  "none" -> noExtensions
  "all" -> good { extEmitTargets = [alpha, beta] }
  "sharp-s" -> good { extEmitTargets = [target "alpha" \ _ -> [Right ("STRASSE.TXT", "a\n"), Right ("straße.txt", "b\n")]] }
  "bad-names" -> good { extEmitTargets = [target "alpha" \ _ -> [Right (".", "x"), Right ("CON.txt", "x"), Right ("ok.txt", "x\n")]] }
  "write-fails" -> good { extEmitTargets = [target "alpha" \ _ -> [Right ("blocked.txt", "x"), Right ("after.txt", "y\n")]] }
  "text-error" -> good { extEmitTargets = [alpha, target "gamma" \ _ -> [Right ("t1.txt", error "boom"), Right ("t2.txt", "fine\n")]] }
  "spine-error" -> good { extEmitTargets = [alpha, target "delta" \ _ -> Right ("s1.txt", "one\n") : error "spine boom"] }
  "case-clash" -> good { extEmitTargets = [target "alpha" \ ei -> [Right (T.toUpper ei.eiBase <> ".DOT", "x\n"), Right ("x.txt", "x\n")]] }
  "path" -> good { extEmitTargets = [target "alpha" \ _ -> [Right ("sub/a.txt", "x"), Right ("../a.txt", "x"), Right ("a:b.txt", "x"), Right ("ok.txt", "x\n")]] }
  "same-twice" -> good { extEmitTargets = [target "alpha" \ ei -> [Right (ei.eiBase <> ".same.txt", "a\n")], target "beta" \ ei -> [Right (ei.eiBase <> ".same.txt", "b\n")]] }
  "failing" -> good { extEmitTargets = [alpha, target "gamma" \ _ -> [Left "gamma is broken"]] }
  "dup-target" -> good { extEmitTargets = [alpha, alpha] }
  "dot-target" -> good { extEmitTargets = [target "a.b" \ _ -> []] }
  "dup-command" -> good { extCommands = [command "x" "one", command "x" "two"] }
  "dot-command" -> good { extCommands = [command "foo.l4" "dotted"] }
  "cmd-clash" -> good { extCommands = [command "verify" "shadow"] }
  "export-clash" -> good { extExports = [command "dmn" "shadow"] }
  v -> error ("no such probe variant: " <> v)
  where
    good = noExtensions { extEdition = Just "probe", extCommands = [command "probe-cmd" "probe command ran"], extExports = [exportFormat, evalFormat] }
    command n out = MkExtCommand { ecName = n, ecInfo = info (helper <*> pure (putStrLn out)) (progDesc ("test command " <> n)) }
    -- an export format that reads its file with the shared loader
    exportFormat = MkExtCommand
      { ecName = "probe-fmt"
      , ecInfo = info (helper <*> fmap load (strArgument (metavar "FILE"))) (progDesc "test export format")
      }
    -- an export format that also needs the evaluator's verdicts
    evalFormat = MkExtCommand
      { ecName = "probe-eval"
      , ecInfo = info (helper <*> fmap verdicts (strArgument (metavar "FILE"))) (progDesc "test export format with verdicts")
      }
    verdicts :: FilePath -> IO ()
    verdicts fp = do
      cfg <- makeEvalConfig (FixedNowOpt Nothing)
      (_, loaded) <- loadCheckedEvaluated cfg fp
      case loaded of
        Nothing -> putStrLn "not loaded"
        Just (_, rs) -> putStrLn (unwords [ case r.result of { Assertion Holds -> "holds"; Assertion Fails -> "fails"; _ -> "other" } | r <- rs ])
    load :: FilePath -> IO ()
    load fp = do
      cfg <- makeEvalConfig (FixedNowOpt Nothing)
      (_, loaded) <- loadChecked cfg fp
      case loaded of
        Nothing -> putStrLn "not loaded"
        Just lm -> putStrLn ("loaded: " <> show lm.lmCheck.success <> ", " <> show (length lm.lmImports) <> " imports")
    target n f = MkEmitTarget { etName = n, etFiles = \ _ ei -> f ei }
    alpha = MkEmitTarget
      { etName = "alpha"
      , etFiles = \ opts ei -> [Right (ei.eiBase <> ".alpha.txt", fromMaybe "hello" (Map.lookup "greeting" opts) <> "\n")]
      }
    beta = target "beta" \ ei -> [Right (ei.eiBase <> ".beta.txt", "beta\n")]

-- | Run the probe, as the given variant, with these arguments.
probe :: String -> [String] -> IO Output
probe variant args = do
  exe <- getExecutablePath
  env <- getEnvironment
  runL4WithEnv (Just ((probeEnv, variant) : filter ((/= probeEnv) . fst) env)) exe args

explored :: FilePath
explored = "examples" </> "explore" </> "brief" </> "d1-naive.l4"

-- | @explore@ of 'explored', with the files written into the directory.
exploreInto :: FilePath -> [String] -> [String]
exploreInto dir extra = ["explore", explored, "--until", "75600", "--emit", dir] <> extra

-- | Run the action with an output directory inside a fresh temporary one. The
-- directory itself does not exist yet: @--emit@ makes it.
withOut :: (FilePath -> IO a) -> IO a
withOut act = withSystemTempDirectory "l4-ext-test" \ tmp -> act (tmp </> "out")

spec :: Spec
spec = describe "extension hook (L4.Cli.Extensions)" do
  describe "help and version" do
    it "adds a command, an export format and the explore flags, and the edition to --version" do
      h <- probe "all" ["--help"]
      h.outExit `shouldBe` ExitSuccess
      h.outStdout `shouldSatisfy` ("probe-cmd" `isInfixOf`)
      e <- probe "all" ["export", "--help"]
      e.outStdout `shouldSatisfy` ("probe-fmt" `isInfixOf`)
      x <- probe "all" ["explore", "--help"]
      mapM_ (\ needle -> x.outStdout `shouldSatisfy` (needle `isInfixOf`)) ["--target NAME", "--target-opt NAME.KEY=VALUE", "alpha, beta"]
      v <- probe "all" ["--version"]
      v.outExit `shouldBe` ExitSuccess
      filter (/= '\r') v.outStdout `shouldSatisfy` (" (probe edition)\n" `isSuffixOf`)
    it "adds nothing to an executable without extensions" do
      x <- probe "none" ["explore", "--help"]
      x.outStdout `shouldSatisfy` (not . ("--target" `isInfixOf`))
      v <- probe "none" ["--version"]
      v.outStdout `shouldSatisfy` (not . ("edition" `isInfixOf`))

  describe "running" do
    it "runs an extension command" do
      o <- probe "all" ["probe-cmd"]
      (o.outExit, filter (/= '\r') o.outStdout) `shouldBe` (ExitSuccess, "probe command ran\n")
    it "runs an extension export format, which reads its file with the shared loader" do
      o <- probe "all" ["export", "probe-fmt", explored]
      o.outExit `shouldBe` ExitSuccess
      o.outStdout `shouldSatisfy` ("loaded: " `isInfixOf`)
    it "tells an extension export format that its file did not load" do
      withSystemTempDirectory "l4-ext-test" \ tmp -> do
        let bad = tmp </> "bad.l4"
        writeFile bad "this is not L4\n"
        o <- probe "all" ["export", "probe-fmt", bad]
        filter (/= '\r') o.outStdout `shouldBe` "not loaded\n"
    it "gives an extension export format the evaluator's verdicts from the same load, and none for a file that does not check" do
      ok <- probe "all" ["export", "probe-eval", "examples" </> "ok" </> "assert.l4"]
      (ok.outExit, unwords (words ok.outStdout)) `shouldBe` (ExitSuccess, "holds fails")
      withSystemTempDirectory "l4-ext-test" \ tmp -> do
        let bad = tmp </> "bad.l4"
        writeFile bad "this is not L4\n"
        o <- probe "all" ["export", "probe-eval", bad]
        unwords (words o.outStdout) `shouldBe` "not loaded"
    it "writes every target's file beside the built-in ones" do
      withOut \ dir -> do
        o <- probe "all" (exploreInto dir [])
        o.outStderr `shouldSatisfy` ("d1_naive.alpha.txt" `isInfixOf`)
        mapM_ (\ f -> doesFileExist (dir </> f) `shouldReturn` True) ["d1_naive.dot", "d1_naive.tla", "d1_naive.alpha.txt", "d1_naive.beta.txt"]
        TIO.readFile (dir </> "d1_naive.alpha.txt") `shouldReturn` "hello\n"
    it "writes only the files of the targets --target names" do
      withOut \ dir -> do
        _ <- probe "all" (exploreInto dir ["--target", "alpha"])
        doesFileExist (dir </> "d1_naive.alpha.txt") `shouldReturn` True
        doesFileExist (dir </> "d1_naive.beta.txt") `shouldReturn` False
    it "gives a target the options --target-opt names" do
      withOut \ dir -> do
        _ <- probe "all" (exploreInto dir ["--target-opt", "alpha.greeting=hi"])
        TIO.readFile (dir </> "d1_naive.alpha.txt") `shouldReturn` "hi\n"

  describe "refusals at --emit" do
    let refuses variant extra check = withOut \ dir -> do
          o <- probe variant (exploreInto dir extra)
          o.outExit `shouldBe` ExitFailure 1
          check dir (o.outStderr)
    it "refuses a --target that names no target, listing the ones there are" $
      refuses "all" ["--target", "nope"] \ _ err -> do
        err `shouldSatisfy` ("--target nope: names no emit target; this edition has: alpha, beta" `isInfixOf`)
    it "refuses a --target-opt that names no target" $
      refuses "all" ["--target-opt", "nope.k=v"] \ _ err ->
        err `shouldSatisfy` ("names no emit target" `isInfixOf`)
    it "refuses a --target-opt for a target that --target leaves out" $
      refuses "all" ["--target", "beta", "--target-opt", "alpha.greeting=hi"] \ _ err ->
        err `shouldSatisfy` ("--target leaves out alpha" `isInfixOf`)
    it "refuses a --target-opt given twice" $
      refuses "all" ["--target-opt", "alpha.greeting=a", "--target-opt", "alpha.greeting=b"] \ _ err ->
        err `shouldSatisfy` ("given twice" `isInfixOf`)
    it "refuses a --target-opt that is not NAME.KEY=VALUE" $
      refuses "all" ["--target-opt", "alpha"] \ _ err ->
        err `shouldSatisfy` ("expected NAME.KEY=VALUE" `isInfixOf`)
    it "refuses --target without --emit" do
      o <- probe "all" ["explore", explored, "--target", "alpha"]
      o.outExit `shouldBe` ExitFailure 1
      o.outStderr `shouldSatisfy` ("need --emit DIR" `isInfixOf`)
    it "refuses a file whose name differs from a built-in's only in case, naming the target and the file, and leaves the built-in's alone" $
      refuses "case-clash" [] \ dir err -> do
        err `shouldSatisfy` ("target alpha: file `D1_NAIVE.DOT` is the same file as `d1_naive.dot`, written by a built-in emitter" `isInfixOf`)
        doesFileExist (dir </> "x.txt") `shouldReturn` True
        dot <- TIO.readFile (dir </> "d1_naive.dot")
        T.unpack dot `shouldSatisfy` ("digraph" `isInfixOf`)
    it "refuses a file name that could leave the directory, and writes nothing outside it" $
      withSystemTempDirectory "l4-ext-test" \ tmp -> do
        let dir = tmp </> "out"
        o <- probe "path" (exploreInto dir [])
        o.outExit `shouldBe` ExitFailure 1
        mapM_ (\ n -> o.outStderr `shouldSatisfy` (("target alpha: file `" <> n <> "`") `isInfixOf`)) ["sub/a.txt", "../a.txt", "a:b.txt"]
        doesFileExist (dir </> "ok.txt") `shouldReturn` True
        doesDirectoryExist (dir </> "sub") `shouldReturn` False
        doesFileExist (tmp </> "a.txt") `shouldReturn` False
    it "refuses names that differ only as ß and SS do, which only full case folding sees" $
      refuses "sharp-s" [] \ dir err -> do
        err `shouldSatisfy` ("target alpha: file `straße.txt` is the same file as `STRASSE.TXT`, written by target alpha" `isInfixOf`)
        doesFileExist (dir </> "STRASSE.TXT") `shouldReturn` True
        TIO.readFile (dir </> "STRASSE.TXT") `shouldReturn` "a\n"
    it "refuses a name that is the directory or a Windows device, naming the target and the file, and writes the rest" $
      refuses "bad-names" [] \ dir err -> do
        err `shouldSatisfy` ("target alpha: file `.`: the name is `.`, the directory itself; not written" `isInfixOf`)
        err `shouldSatisfy` ("target alpha: file `CON.txt`: the name is `CON`, a device name that Windows reserves; not written" `isInfixOf`)
        TIO.readFile (dir </> "ok.txt") `shouldReturn` "x\n"
    it "reports a file that cannot be written with the target and the file named, and writes the others" $
      withOut \ dir -> do
        createDirectoryIfMissing True (dir </> "blocked.txt")
        o <- probe "write-fails" (exploreInto dir [])
        o.outExit `shouldBe` ExitFailure 1
        o.outStderr `shouldSatisfy` ("--emit: not written: target alpha: file `blocked.txt`: " `isInfixOf`)
        TIO.readFile (dir </> "after.txt") `shouldReturn` "y\n"
        doesFileExist (dir </> "d1_naive.dot") `shouldReturn` True
        o.outStderr `shouldSatisfy` ("after.txt" `isInfixOf`)
    it "reports an exception raised while a file's contents are computed, with the target and the file, and writes the rest" $
      refuses "text-error" [] \ dir err -> do
        err `shouldSatisfy` ("--emit: not written: target gamma: file `t1.txt`: boom" `isInfixOf`)
        doesFileExist (dir </> "t1.txt") `shouldReturn` False
        TIO.readFile (dir </> "t2.txt") `shouldReturn` "fine\n"
        doesFileExist (dir </> "d1_naive.alpha.txt") `shouldReturn` True
    it "reports an exception raised while a target's list is read, with the target, and keeps what came before it" $
      refuses "spine-error" [] \ dir err -> do
        err `shouldSatisfy` ("--emit: not written: target delta: spine boom" `isInfixOf`)
        TIO.readFile (dir </> "s1.txt") `shouldReturn` "one\n"
        doesFileExist (dir </> "d1_naive.alpha.txt") `shouldReturn` True
    it "refuses a file another target wrote first, naming both" $
      refuses "same-twice" [] \ dir err -> do
        err `shouldSatisfy` ("target beta: file `d1_naive.same.txt` is the same file as `d1_naive.same.txt`, written by target alpha" `isInfixOf`)
        TIO.readFile (dir </> "d1_naive.same.txt") `shouldReturn` "a\n"
    it "names a failing target, and a target --target leaves out cannot fail the run" $ do
      refuses "failing" [] \ _ err -> err `shouldSatisfy` ("target gamma: gamma is broken" `isInfixOf`)
      baseline <- withOut \ dir -> probe "none" (exploreInto dir [])
      withOut \ dir -> do
        o <- probe "failing" (exploreInto dir ["--target", "alpha"])
        o.outExit `shouldBe` baseline.outExit
        o.outStderr `shouldSatisfy` (not . ("gamma" `isInfixOf`))
      -- the baseline is not a failure by luck: it must not be exit 1
      baseline.outExit `shouldNotBe` ExitFailure 1

  describe "emitNameProblem" do
    let longAscii = T.replicate 255 "a"
        twoByte = T.replicate 127 "\233" <> "a"
    it "accepts ordinary names, 255 bytes, and the near misses of the device names" $
      mapM_ (\ n -> (n, emitNameProblem n) `shouldBe` (n, Nothing))
        ["a.txt", "d1_naive.dot", ".hidden", "CONSOLE", "con-sole.txt", "COM0", "COM10", "NULL.txt", "xCON", "LPT", longAscii, twoByte]
    it "refuses the directory itself, control characters including NUL, and names over 255 bytes" $
      mapM_ (\ (n, why) -> (n, fmap (why `T.isInfixOf`) (emitNameProblem n)) `shouldBe` (n, Just True))
        [ (".", "the directory itself")
        , (T.pack ['a', '\0', 'b'], "control character")
        , ("a\nb", "control character")
        , ("a\DELb", "control character")
        , (longAscii <> "a", "255 bytes")
        , (T.replicate 128 "\233", "255 bytes")
        ]
    it "refuses Windows device names as they stand and before the first dot, in any case" $
      mapM_ (\ (n, device) -> (n, fmap (device `T.isInfixOf`) (emitNameProblem n)) `shouldBe` (n, Just True))
        [("CON", "`CON`"), ("con", "`CON`"), ("Nul.txt", "`NUL`"), ("com1.tar.gz", "`COM1`"), ("LPT9.x", "`LPT9`"), ("aux.", "`AUX`"), ("PRN", "`PRN`")]
    it "still refuses the names it refused before" $
      mapM_ (\ n -> (n, isJust (emitNameProblem n)) `shouldBe` (n, True))
        ["", "sub/a.txt", "..\\a.txt", "../a.txt", "a:b.txt", "/abs.txt", "a..b"]

  describe "combining extensions" do
    let ed n = noExtensions { extEdition = Just n }
        a = ed "A"
        b = ed "B"
    it "reads a repeated edition once, in the order first met, however the editions are bracketed" $ do
      (a <> a <> b).extEdition `shouldBe` Just "A+B"
      ((a <> a) <> b).extEdition `shouldBe` Just "A+B"
      (a <> (a <> b)).extEdition `shouldBe` Just "A+B"
      ((a <> b) <> (b <> a)).extEdition `shouldBe` Just "A+B"
      (b <> a <> a).extEdition `shouldBe` Just "B+A"
    it "keeps the one edition there is, and has noExtensions as its identity" $ do
      (mempty <> a).extEdition `shouldBe` Just "A"
      (a <> mempty).extEdition `shouldBe` Just "A"
      (a <> a).extEdition `shouldBe` Just "A"
      (mempty :: Extensions).extEdition `shouldBe` Nothing

  describe "faults of the extensions stop the program before an argument is read" do
    let stops variant message = do
          mapM_ (\ args -> do
                    o <- probe variant args
                    o.outExit `shouldBe` ExitFailure 1
                    o.outStderr `shouldSatisfy` (message `isInfixOf`)
                    o.outStdout `shouldBe` "")
                [["--version"], ["--help"], ["probe-cmd"]]
    it "a command named like a built-in, naming the extension" $
      stops "cmd-clash" "two commands are named `verify`: a name added by the probe extension cannot be one that a built-in or another extension already has"
    it "an export format named like a built-in" $
      stops "export-clash" "two export formats are named `dmn`: a name added by the probe extension"
    it "two emit targets of one name" $
      stops "dup-target" "the probe extension adds two emit targets named `alpha`"
    it "two commands of one name" $
      stops "dup-command" "the probe extension adds two commands named `x`"
    it "a command name with a dot in it" $
      stops "dot-command" "the probe extension adds a command named `foo.l4`"
    it "an emit target name that --target-opt cannot address" $
      stops "dot-target" "the probe extension adds an emit target named `a.b`"
