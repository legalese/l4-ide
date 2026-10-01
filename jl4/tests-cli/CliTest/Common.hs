-- | Helpers shared across the @l4@ CLI black-box suite (@l4-cli-test@):
-- locating the binary, running it, the @expect*@ assertions, JSON envelopes,
-- and the fixtures that more than one area reads.
--
-- The core tests are in @Main.hs@; each backend's tests are in their own
-- @CliTest.*@ module beside this one, so a release can be sliced per backend.
module CliTest.Common where

import Control.Concurrent (forkIO)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Monad (unless, when)
import Data.List (findIndex, isInfixOf, isPrefixOf)
import Data.Maybe (fromMaybe)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy.Char8 as BSL8
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Aeson (Value(..), eitherDecode)
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Aeson.Key as Key
import System.Directory
  ( createDirectoryIfMissing
  , doesFileExist
  , getTemporaryDirectory
  , makeAbsolute
  )
import System.Environment (getEnvironment, lookupEnv)
import System.Exit (ExitCode(..), exitFailure)
import System.FilePath ((</>))
import System.IO (hClose, hSetBinaryMode)
import System.Process
  ( CreateProcess(..)
  , StdStream(..)
  , createProcess
  , proc
  , readCreateProcessWithExitCode
  , waitForProcess
  )
import Test.Hspec

----------------------------------------------------------------------------
-- Locating the l4 binary
----------------------------------------------------------------------------

-- | Find the @l4@ binary to test against.
--
-- Priority:
--
-- 1. @L4_BIN@ environment variable (useful in CI and for manual runs).
-- 2. @cabal list-bin exe:l4@ output (when running under cabal).
-- 3. Walk up from the test binary's path to @dist-newstyle/.../l4@.
--
-- The result is always absolute: some tests run the binary from a different
-- working directory (to exercise the @l4 check main.l4@ invocation form), and a
-- relative binary path would not survive that.
locateL4Binary :: IO FilePath
locateL4Binary = makeAbsolute =<< locateL4Binary'

locateL4Binary' :: IO FilePath
locateL4Binary' = do
  fromEnv <- lookupEnv "L4_BIN"
  case fromEnv of
    Just p -> do
      ok <- doesFileExist p
      if ok then pure p else failWith ("L4_BIN set but not a file: " ++ p)
    Nothing -> do
      tryCabal <- cabalListBin
      case tryCabal of
        Just p -> pure p
        Nothing -> failWith
          "Could not find the l4 binary. Set L4_BIN or run via 'cabal test'."
  where
    failWith msg = do
      putStrLn ("ERROR: " ++ msg)
      exitFailure

    -- Best-effort: try `cabal list-bin exe:l4` from cwd.
    cabalListBin :: IO (Maybe FilePath)
    cabalListBin = do
      (code, out, _err) <- readCreateProcessWithExitCode
        (proc "cabal" ["list-bin", "exe:l4"]) ""
      case code of
        ExitSuccess ->
          let path = trim out
          in do
            ok <- doesFileExist path
            pure (if ok then Just path else Nothing)
        _ -> pure Nothing

    trim = reverse . dropWhile isSpace . reverse . dropWhile isSpace
    isSpace c = c == ' ' || c == '\n' || c == '\r' || c == '\t'

----------------------------------------------------------------------------
-- Helpers for running the CLI
----------------------------------------------------------------------------

notInfixOf :: String -> String -> Bool
notInfixOf needle hay = not (needle `isInfixOf` hay)

data Output = Output
  { outExit   :: ExitCode
  , outStdout :: String
  , outStderr :: String
  } deriving (Eq, Show)

-- | Run the l4 binary and capture its stdout + stderr.
--
-- Reads both streams as raw bytes and decodes them as UTF-8 leniently,
-- bypassing @readCreateProcessWithExitCode@'s reliance on the system
-- locale encoding. On Windows CI runners the locale is typically CP1252,
-- which rejects the UTF-8 lead bytes (0xC2, 0xE2, …) that @l4.exe@
-- writes for section markers (§) and en/em-dashes in help text — that
-- is the @hGetContents: cannot decode byte sequence starting from 194@
-- failure we saw on the first Windows build.
runL4 :: FilePath -> [String] -> IO Output
runL4 = runL4WithEnv Nothing

-- | Like 'runL4', but run the child process with an explicit environment.
--
-- @Nothing@ inherits the parent environment (the default). @Just env@ replaces
-- it wholesale, which lets a test force a particular library-resolution regime
-- (e.g. dropping @JL4_LIBRARY_PATH@ to exercise the embedded-library fallback)
-- regardless of what CI happens to export into the parent process.
runL4WithEnv :: Maybe [(String, String)] -> FilePath -> [String] -> IO Output
runL4WithEnv = runL4In Nothing

-- | Like 'runL4WithEnv', but also lets a test choose the child's working
-- directory.
--
-- This matters for library resolution: the CLI derives its root directory from
-- @takeDirectory@ of the entry path, so @l4 check main.l4@ run from inside the
-- project (root directory @"."@) exercises a different resolution path than
-- @l4 check some/dir/main.l4@ run from the package root. Every fixture path in
-- this suite carries a directory component, so without this the @"."@ case is
-- never covered — which is how the embedded stdlib came to outrank
-- project-local libraries for a whole release without a red test.
runL4In :: Maybe FilePath -> Maybe [(String, String)] -> FilePath -> [String] -> IO Output
runL4In mCwd mEnv bin args = do
  let cp = (proc bin args)
        { std_in  = CreatePipe
        , std_out = CreatePipe
        , std_err = CreatePipe
        , env     = mEnv
        , cwd     = mCwd
        }
  (Just hin, Just hout, Just herr, ph) <- createProcess cp
  hClose hin
  hSetBinaryMode hout True
  hSetBinaryMode herr True
  -- Drain the two pipes CONCURRENTLY. 'BS.hGetContents' is strict, so reading
  -- stdout to EOF and only then reading stderr deadlocks the moment the child
  -- writes more to stderr than the pipe buffer holds (~16 KB on macOS): the
  -- child blocks on the stderr write, so it never closes stdout, so the parent
  -- never returns. That is not hypothetical — `l4 export blawx` on a seed whose
  -- assumed predicates are refused for publication emits ~22 KB of diagnostics
  -- on a run that exits 0, and it hung this suite until it was killed, with no
  -- output and no failure to point at.
  serrVar <- newEmptyMVar
  _ <- forkIO (BS.hGetContents herr >>= putMVar serrVar)
  soutBytes <- BS.hGetContents hout
  serrBytes <- takeMVar serrVar
  code <- waitForProcess ph
  pure Output
    { outExit   = code
    , outStdout = T.unpack (TE.decodeUtf8Lenient soutBytes)
    , outStderr = T.unpack (TE.decodeUtf8Lenient serrBytes)
    }

-- | Run l4 with @XDG_DATA_HOME@ pointed at a caller-controlled directory and
-- @JL4_LIBRARY_PATH@ dropped (so 'resolveLibrary' reports
-- @hasExplicitPath = False@ and the resolver consults the embedded stdlib and
-- the ambient tiers). This is the dev regime the LIBRARY-RESOLUTION-SHADOW
-- tests exercise — CI normally exports @JL4_LIBRARY_PATH@, which hides it.
runL4WithXdgHome :: FilePath -> FilePath -> [String] -> IO Output
runL4WithXdgHome = runL4WithXdgHomeIn Nothing

runL4WithXdgHomeIn :: Maybe FilePath -> FilePath -> FilePath -> [String] -> IO Output
runL4WithXdgHomeIn mCwd xdgHome bin args = do
  parentEnv <- getEnvironment
  let childEnv =
        ("XDG_DATA_HOME", xdgHome)
          : filter (\(k, _) -> k /= "JL4_LIBRARY_PATH" && k /= "XDG_DATA_HOME")
                   parentEnv
  runL4In mCwd (Just childEnv) bin args

-- | Run l4 with library resolution forced onto the embedded-library fallback:
-- no @JL4_LIBRARY_PATH@, and an /empty/ XDG store (so no user-level
-- @~/.local/share/jl4/libraries@ on the runner interferes). This is the exact
-- regime issue #906 is about.
runL4EmbeddedOnly :: FilePath -> [String] -> IO Output
runL4EmbeddedOnly = runL4EmbeddedOnlyIn Nothing

-- | 'runL4EmbeddedOnly' from a caller-chosen working directory. Used to run the
-- CLI the way a user does — @l4 check main.l4@ from inside the project — which
-- makes the resolver's root directory @"."@.
runL4EmbeddedOnlyIn :: Maybe FilePath -> FilePath -> [String] -> IO Output
runL4EmbeddedOnlyIn mCwd bin args = do
  tmp <- getTemporaryDirectory
  let emptyXdg = tmp </> "l4-embedded-only-xdg"
  createDirectoryIfMissing True emptyXdg
  runL4WithXdgHomeIn mCwd emptyXdg bin args

-- | Assert the CLI exited 0 with a given substring on stdout.
expectOk :: FilePath -> [String] -> String -> IO ()
expectOk bin args expectedSubstring = do
  Output code sout serr <- runL4 bin args
  case code of
    ExitSuccess ->
      unless (expectedSubstring `isInfixOf` sout) $
        expectationFailure $
          "Expected stdout to contain " ++ show expectedSubstring
          ++ "\n--- stdout ---\n" ++ sout
          ++ "\n--- stderr ---\n" ++ serr
    ExitFailure n -> expectationFailure $
      "Expected success but exited " ++ show n
      ++ "\n--- stdout ---\n" ++ sout
      ++ "\n--- stderr ---\n" ++ serr

-- | Assert the CLI exited non-zero.
expectFail :: FilePath -> [String] -> IO ()
expectFail bin args = do
  Output code _ _ <- runL4 bin args
  case code of
    ExitFailure _ -> pure ()
    ExitSuccess   -> expectationFailure "Expected non-zero exit; got success"

-- | Assert @l4 verify@ exits 1 on a fixture AND names the expected finding
-- kind. Both halves are needed: exit 1 alone would be satisfied by a fixture
-- that fails to typecheck, which would make the negative control a control over
-- nothing.
expectVerifyFinding :: FilePath -> FilePath -> String -> IO ()
expectVerifyFinding bin fixture kind = do
  Output code sout serr <- runL4 bin ["verify", fixture, "--format", "json"]
  case code of
    ExitFailure 1 -> pure ()
    other -> expectationFailure $
      "Expected exit 1 (findings present) but got " ++ show other
      ++ "\n--- stdout ---\n" ++ sout ++ "\n--- stderr ---\n" ++ serr
  unless (("\"" ++ kind ++ "\"") `isInfixOf` sout) $
    expectationFailure $
      "Expected a " ++ show kind ++ " finding in the JSON envelope"
      ++ "\n--- stdout ---\n" ++ sout

-- | Assert the CLI exits 0 and its stdout exactly matches a committed golden
-- file. Used for the OpenFisca backend, whose emit is fully deterministic.
expectGolden :: FilePath -> [String] -> FilePath -> IO ()
expectGolden bin args goldenPath = do
  Output code sout serr <- runL4 bin args
  goldenBytes <- BS.readFile goldenPath
  let golden = T.unpack (TE.decodeUtf8Lenient goldenBytes)
  case code of
    ExitSuccess ->
      unless (sout == golden) $
        expectationFailure $
          "Generated output does not match golden " ++ goldenPath
          ++ "\n(to update: l4 " ++ unwords args ++ " -o " ++ goldenPath ++ ")"
          ++ "\n--- got ---\n" ++ sout
          ++ "\n--- golden ---\n" ++ golden
    ExitFailure n -> expectationFailure $
      "Expected success but exited " ++ show n ++ "\n--- stderr ---\n" ++ serr

-- | Read a file as UTF-8 regardless of the ambient locale — same reasoning as
-- 'runL4': the fidelity goldens are full of em-dashes and typographic quotes,
-- which a CP1252 Windows runner cannot decode through 'readFile'.
readUtf8 :: FilePath -> IO String
readUtf8 fp = T.unpack . TE.decodeUtf8Lenient <$> BS.readFile fp

-- | Index of the first line containing a needle.
--
-- An ABSENT needle yields 'maxBound' rather than a negative sentinel, so it
-- sorts LAST: a fixture that lost its @\<itemDefinition\>@ altogether then
-- fails the \"before\" assertion instead of vacuously satisfying it.
firstLineWith :: String -> String -> Int
firstLineWith needle = fromMaybe maxBound . findIndex (needle `isInfixOf`) . lines

-- | Parse the stdout of a --json run as a JSON envelope.
--
-- Re-encodes as UTF-8 rather than using @BSL8.pack@, which truncates each Char
-- to eight bits: an em-dash in a decision name (regcf is full of them) came back
-- as byte 0x14 and aeson rejected it as a control character inside a string
-- literal. Every envelope this suite parsed before was ASCII, so the bug was
-- latent until a JSON mode started echoing corpus identifiers.
jsonEnvelope :: FilePath -> [String] -> IO Value
jsonEnvelope bin args = do
  Output _ sout _ <- runL4 bin args
  case eitherDecode (BSL8.fromStrict (TE.encodeUtf8 (T.pack sout))) of
    Right v  -> pure v
    Left err -> do
      expectationFailure ("JSON parse failed: " ++ err ++ "\nstdout:\n" ++ sout)
      error "unreachable"

objField :: Value -> String -> Maybe Value
objField (Object km) k = KeyMap.lookup (Key.fromString k) km
objField _ _ = Nothing

----------------------------------------------------------------------------
-- Fixtures
----------------------------------------------------------------------------

fixtureDir :: FilePath
fixtureDir = "tests-cli/fixtures"

cleanFixture, evalFixture, errorFixture, garbageFixture :: FilePath
cleanFixture   = fixtureDir </> "clean.l4"
evalFixture    = fixtureDir </> "eval.l4"
errorFixture   = fixtureDir </> "typecheck-error.l4"
garbageFixture = fixtureDir </> "garbage.l4"

-- | Split an emitted docassemble interview into its @---@-separated blocks.
-- docassemble itself splits on the whole-line regex @^--- *$@ before YAML ever
-- sees the file (@parse.py:138@), so this is the same unit the engine reasons
-- about.
yamlBlocks :: String -> [String]
yamlBlocks = map unlines . splitBlocks . lines
 where
  splitBlocks ls = case break isSep ls of
    (chunk, [])       -> [chunk]
    (chunk, _ : rest) -> chunk : splitBlocks rest
  isSep ln = "---" `isPrefixOf` ln && all (== ' ') (drop 3 ln)

-- | Assert a needle occurs in a haystack, reporting the haystack on failure.
shouldContain' :: String -> String -> String -> IO ()
shouldContain' what haystack needle =
  unless (needle `isInfixOf` haystack) $
    expectationFailure $
      what ++ " does not contain " ++ show needle ++ "\n--- got ---\n" ++ haystack

-- | Assert a needle does NOT occur — the half that catches a citation
-- attributed to the wrong rule.
shouldNotContain' :: String -> String -> String -> IO ()
shouldNotContain' what haystack needle =
  when (needle `isInfixOf` haystack) $
    expectationFailure $
      what ++ " unexpectedly contains " ++ show needle ++ "\n--- got ---\n" ++ haystack
