-- | Black-box test suite for the @l4@ CLI.
--
-- Each test spawns the @l4@ binary as a subprocess (via cabal's
-- @build-tool-depends@ wiring) and asserts on exit code, stdout, stderr,
-- and — for JSON modes — the shape of the parsed envelope.
--
-- The goal is coverage of /observable behavior/: does @l4 run FILE@ do
-- what the user expects when the file is clean, has eval directives,
-- fails typechecking, or is empty?  Golden-text tests would be brittle
-- against small wording changes; this suite checks *structure* instead.
module Main where

import Control.Concurrent (forkIO)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Exception (IOException, finally, throwIO, try)
import Control.Monad (forM_, unless, void, when)
import qualified Data.Char as Char
import Data.Foldable (toList)
import Data.List (intercalate, isInfixOf, isPrefixOf, isSuffixOf, tails)
import Data.Maybe (fromMaybe)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Lazy.Char8 as BSL8
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Aeson as Aeson
import Data.Aeson (Value(..), eitherDecode)
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Aeson.Key as Key
import System.Directory
  ( canonicalizePath
  , createDirectoryIfMissing
  , createFileLink
  , doesFileExist
  , emptyPermissions
  , findExecutable
  , getTemporaryDirectory
  , makeAbsolute
  , removeFile
  , removePathForcibly
  , setOwnerReadable
  , setOwnerSearchable
  , setOwnerWritable
  , setPermissions
  )
import System.Environment (getEnvironment, lookupEnv)
import System.Exit (ExitCode(..), exitFailure)
import System.FilePath ((</>), takeFileName)
import qualified System.Info as Info
import System.IO (Handle, hClose, hFlush, hSetBinaryMode)
import System.IO.Error (isPermissionError)
import System.Process
  ( CreateProcess(..)
  , StdStream(..)
  , createProcess
  , proc
  , readCreateProcessWithExitCode
  , terminateProcess
  , waitForProcess
  )
import System.Timeout (timeout)
import Test.Hspec
import Data.Aeson (toJSON)
import Data.Char (isDigit)
import System.IO (hPutStr)
import System.IO.Temp (withSystemTempDirectory)

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
-- never covered — which is how a bare @l4 run total.l4@ lost the stdlib's names
-- (measured on plain main) without a red test.
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
  soutBytes <- BS.hGetContents hout
  serrBytes <- BS.hGetContents herr
  code <- waitForProcess ph
  pure Output
    { outExit   = code
    , outStdout = T.unpack (TE.decodeUtf8Lenient soutBytes)
    , outStderr = T.unpack (TE.decodeUtf8Lenient serrBytes)
    }

-- | Run l4 with @XDG_DATA_HOME@ pointed at a caller-controlled directory and
-- @JL4_LIBRARY_PATH@ dropped (so 'resolveLibrary' reports
-- @hasExplicitPath = False@ and the resolver consults the embedded stdlib and
-- the ambient tiers). This is the dev regime the library-shadow
-- tests exercise — CI normally exports @JL4_LIBRARY_PATH@, which hides it.
-- | Try to create a symbolic link; 'Left' says why it could not be made. On
-- Windows an account without the symlink privilege gets "permission denied".
-- Any other failure is a real one and is rethrown.
tryLink :: FilePath -> FilePath -> IO (Either String ())
tryLink target link = do
  r <- try (createFileLink target link) :: IO (Either IOException ())
  case r of
    Right () -> pure (Right ())
    Left e
      | isPermissionError e -> pure (Left ("cannot create a symbolic link here (" <> show e <> ")"))
      | otherwise -> throwIO e

-- | Create a symbolic link, or mark the example pending where this account may
-- not: the example is about what @l4@ does with a link, not about whether the
-- platform lets a test make one.
linkOrPending :: FilePath -> FilePath -> IO ()
linkOrPending target link = tryLink target link >>= either pendingWith pure

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
-- regime smucclaw/l4-ide#906 is about.
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

-- | Assert the CLI exited with status 1, which is what a failed check or run
-- gives on every platform.
expectExit1 :: FilePath -> [String] -> IO ()
expectExit1 bin args = do
  Output code _ _ <- runL4 bin args
  code `shouldBe` ExitFailure 1

-- | Assert a command run with @--json@ reports @ok: false@ and says why: the
-- envelope must carry at least one diagnostic.
expectJsonNotOk :: FilePath -> [String] -> IO ()
expectJsonNotOk bin args = do
  env <- jsonEnvelope bin (args ++ ["--json"])
  objField env "ok" `shouldBe` Just (Bool False)
  case objField env "diagnostics" of
    Just (Array ds) -> length ds `shouldSatisfy` (> 0)
    other -> expectationFailure ("Expected a diagnostics array, got " ++ show other)

-- | Whether some line of the text ends with the needle. Written against text
-- whose carriage returns are already gone, so a needle never has to span a line
-- break (and so never has to name one).
endsLine :: String -> String -> Bool
endsLine needle = any (needle `isSuffixOf`) . lines

-- | The lines joined by line feeds, for a needle that spans several of them.
joinLines :: [String] -> String
joinLines = intercalate "\n"

-- | Assert @l4 nlg SOURCE@ exits 0 and prints exactly the committed golden,
-- line endings aside: on Windows the output, or a golden checked out there, can
-- end its lines with a carriage return.
expectNlgGolden :: FilePath -> FilePath -> FilePath -> IO ()
expectNlgGolden bin source golden = do
  Output code sout serr <- runL4 bin ["nlg", source]
  expected <- T.unpack . TE.decodeUtf8Lenient <$> BS.readFile golden
  code `shouldBe` ExitSuccess
  unless (filter (/= '\r') sout == filter (/= '\r') expected) $
    expectationFailure $
      "l4 nlg " ++ source ++ " differs from " ++ golden
      ++ "\n--- stdout ---\n" ++ sout
      ++ "\n--- stderr ---\n" ++ serr

-- | Parse the stdout of a --json run as a JSON envelope.
jsonEnvelope :: FilePath -> [String] -> IO Value
jsonEnvelope bin args = do
  Output _ sout _ <- runL4 bin args
  case eitherDecode (BSL8.pack sout) of
    Right v  -> pure v
    Left err -> do
      expectationFailure ("JSON parse failed: " ++ err ++ "\nstdout:\n" ++ sout)
      error "unreachable"

objField :: Value -> String -> Maybe Value
objField (Object km) k = KeyMap.lookup (Key.fromString k) km
objField _ _ = Nothing

-- | The text of the @Evaluation[n]@ block in the output of @l4 run@: from its
-- header up to the next block's header, or to the end. Empty when there is no
-- such block. Written against text whose carriage returns are already gone.
evalBlock :: Int -> String -> T.Text
evalBlock n out =
  let marker = T.pack ("Evaluation[" <> show n <> "]")
      (_, fromHere) = T.breakOn marker (T.pack out)
  in fst (T.breakOn "Evaluation[" (T.drop (T.length marker) fromHere))

-- | The diagnostic that @l4 run@ printed on standard error against a range
-- starting at column 1 of the given line: from its @Range:@ row to the next
-- @File:@ row. Empty when none starts there.
diagnosticAtLine :: Int -> String -> T.Text
diagnosticAtLine line err =
  fst $ T.breakOn "File:" $ T.drop 1 $
    snd $ T.breakOn (T.pack ("Range:    " <> show line <> ":1-")) (T.pack err)

-- | @l4 run FILE@ on a three-directive file whose middle directive, on the given
-- line, cannot be evaluated: the run fails, and the other two directives still
-- print their results (2 and 4). The middle one's message is in its own
-- @Evaluation[2]@ block and is also printed on standard error against its line,
-- as an error.
expectMiddleLostInText :: FilePath -> FilePath -> Int -> [String] -> IO ()
expectMiddleLostInText bin fixture midLine messages = do
  Output code sout0 serr0 <- runL4 bin ["run", fixture]
  let sout = filter (/= '\r') sout0
      serr = filter (/= '\r') serr0
  code `shouldBe` ExitFailure 1
  evalBlock 1 sout `shouldSatisfy` T.isInfixOf "Result:\n  2\n"
  evalBlock 3 sout `shouldSatisfy` T.isInfixOf "Result:\n  4\n"
  forM_ messages \m -> do
    evalBlock 2 sout `shouldSatisfy` T.isInfixOf (T.pack m)
    diagnosticAtLine midLine serr `shouldSatisfy` T.isInfixOf "DiagnosticSeverity_Error"
    diagnosticAtLine midLine serr `shouldSatisfy` T.isInfixOf (T.pack m)

-- | The same file with @--json@: @ok@ is false, there are three results, and the
-- two outer ones are 2 and 4. The middle one carries the message, as its @value@
-- or, for an @#ASSERT@, its @error@.
expectMiddleLostInJson :: FilePath -> FilePath -> [String] -> IO ()
expectMiddleLostInJson bin fixture messages = do
  expectExit1 bin ["run", "--json", fixture]
  env <- jsonEnvelope bin ["run", "--json", fixture]
  objField env "ok" `shouldBe` Just (Bool False)
  case [ r | Array rs <- maybe [] pure (objField env "results"), r <- toList rs ] of
    [first, middle, final] -> do
      objField first "value" `shouldBe` Just (String "2")
      objField final "value" `shouldBe` Just (String "4")
      let said = T.concat [ s | k <- ["value", "error"], Just (String s) <- [objField middle k] ]
      forM_ messages \m -> said `shouldSatisfy` T.isInfixOf (T.pack m)
    other -> expectationFailure ("Expected three results, got " ++ show (length other))

----------------------------------------------------------------------------
-- Fixtures
----------------------------------------------------------------------------

fixtureDir :: FilePath
fixtureDir = "tests-cli/fixtures"

-- The eleven-plus-two placement rows for an @nlg on a rule's head. Its
-- `.nlg.golden` pins the `l4 nlg` columns; `l4 render` has no golden anywhere in
-- the tree, so the tests below are the only thing pinning that the two
-- projections agree (smucclaw/l4-ide#972).
nlgHeadPlacementSource :: FilePath
nlgHeadPlacementSource = "examples/ok/nlg-head-placement.l4"

-- The `l4 nlg` differential pairs: a corpus module and the golden jl4-test
-- wrote for it.
nlgPromissorySource, nlgPromissoryGolden, nlgShowcaseSource, nlgShowcaseGolden :: FilePath
nlgPromissorySource = "examples/legal/promissory-note.l4"
nlgPromissoryGolden = "examples/legal/tests/promissory-note.nlg.golden"
nlgShowcaseSource   = "examples/legal/directive-showcase.l4"
nlgShowcaseGolden   = "examples/legal/tests/directive-showcase.nlg.golden"

bilingualFixture :: FilePath
bilingualFixture = fixtureDir </> "bilingual.l4"

bilingualFramesFixture :: FilePath
bilingualFramesFixture = fixtureDir </> "bilingual-frames.l4"

bilingualFramesRegionFixture :: FilePath
bilingualFramesRegionFixture = fixtureDir </> "bilingual-frames-region.l4"

cleanFixture, evalFixture, errorFixture, garbageFixture :: FilePath
cleanFixture   = fixtureDir </> "clean.l4"
evalFixture    = fixtureDir </> "eval.l4"
errorFixture   = fixtureDir </> "typecheck-error.l4"
garbageFixture = fixtureDir </> "garbage.l4"

-- | A module that declares @\@lang en@, which a module that declares nothing
-- already is; and one that declares @en@ and then @he@, so is not redundant.
langEnHintFixture, langEnThenHeFixture :: FilePath
langEnHintFixture   = fixtureDir </> "lang-en-hint.l4"
langEnThenHeFixture = fixtureDir </> "lang-en-then-he.l4"

-- | A French module whose one wording is tagged @FR@, which differs from the
-- declared @fr@ only in case.
langTagCaseFixture :: FilePath
langTagCaseFixture = fixtureDir </> "lang-tag-case.l4"

evalTraceFixture, evalTraceLineBreakFixture :: FilePath
evalTraceFixture = fixtureDir </> "evaltrace.l4"
evalTraceLineBreakFixture = fixtureDir </> "evaltrace-line-break.l4"

batchEligFixture, batchDataJson, batchDataCsv, batchMixedJson :: FilePath
batchEligFixture = fixtureDir </> "batch-elig.l4"
batchDataJson    = fixtureDir </> "batch-data.json"
batchDataCsv     = fixtureDir </> "batch-data.csv"
batchMixedJson   = fixtureDir </> "batch-mixed.json"

batchCodeFixture, batchExponentCsv, batchMaybeFixture, batchMaybeBadJson, batchMaybeTextJson :: FilePath
batchCodeFixture  = fixtureDir </> "batch-code.l4"
batchExponentCsv  = fixtureDir </> "batch-exponent.csv"
batchMaybeFixture = fixtureDir </> "batch-maybe.l4"
batchMaybeBadJson = fixtureDir </> "batch-maybe-bad.json"
batchMaybeTextJson = fixtureDir </> "batch-maybe-text.json"

-- | A CSV with columns no input declares, run against 'batchEligFixture'.
batchUndeclaredColumnCsv :: FilePath
batchUndeclaredColumnCsv = fixtureDir </> "batch-undeclared-column.csv"

-- | Blank CSV cells (T3c): one STRING input that has to be given and one MAYBE
-- STRING input that need not be, and an income column left blank.
batchBlankFixture, batchBlankCsv, batchBlankIncomeCsv, batchSingleObjectJson :: FilePath
batchBlankFixture   = fixtureDir </> "batch-blank.l4"
batchBlankCsv       = fixtureDir </> "batch-blank.csv"
batchBlankIncomeCsv = fixtureDir </> "batch-blank-income.csv"

-- | A cases file that holds one object, not an array.
batchSingleObjectJson = fixtureDir </> "batch-single-object.json"

-- | CSV cells for inputs that are neither a NUMBER nor a BOOLEAN: a choice
-- (@DECLARE Answer IS ONE OF True, False, Unknown@), a @MAYBE@ choice, a DATE,
-- and synonyms of a NUMBER and a BOOLEAN, which are still read as those.
batchDeclaredText, batchDeclaredTextAnswers, batchDeclaredTextOptional, batchDeclaredTextDates, batchDeclaredTextSynonyms :: FilePath
batchDeclaredText         = fixtureDir </> "batch-declared-text.l4"
batchDeclaredTextAnswers  = fixtureDir </> "batch-declared-text-answers.csv"
batchDeclaredTextOptional = fixtureDir </> "batch-declared-text-optional.csv"
batchDeclaredTextDates    = fixtureDir </> "batch-declared-text-dates.csv"
batchDeclaredTextSynonyms = fixtureDir </> "batch-declared-text-synonyms.csv"

-- | Inputs declared through a type synonym (@DECLARE Year IS A NUMBER@, a
-- BOOLEAN, a MAYBE), with the plain types beside them as the control, and the
-- cases for each.
batchSynonym, batchSynonymYearJson, batchSynonymFlagJson, batchSynonymYearCsv, batchSynonymFlagCsv :: FilePath
batchSynonym         = fixtureDir </> "batch-synonym.l4"
batchSynonymYearJson = fixtureDir </> "batch-synonym-year.json"
batchSynonymFlagJson = fixtureDir </> "batch-synonym-flag.json"
batchSynonymYearCsv  = fixtureDir </> "batch-synonym-year.csv"
batchSynonymFlagCsv  = fixtureDir </> "batch-synonym-flag.csv"

-- | CSV files that cannot be read: a stray quote, an empty file, and a quote
-- that opens a cell and is never closed (at the end of the file, in the middle
-- of it, with Windows line ends, as half of a doubled quote, in the header),
-- with the control of a cell that closes at the very end of the file.
batchCsvBadQuote, batchCsvEmpty, batchCsvOpenQuoteEof, batchCsvOpenQuoteMid, batchCsvOpenQuoteCrlf
  , batchCsvOpenQuoteDoubled, batchCsvOpenQuoteHeader, batchCsvQuoteClosesAtEof :: FilePath
batchCsvBadQuote     = fixtureDir </> "batch-csv-bad-quote.csv"
batchCsvEmpty        = fixtureDir </> "batch-csv-empty.csv"
batchCsvOpenQuoteEof     = fixtureDir </> "batch-csv-open-quote-eof.csv"
batchCsvOpenQuoteMid     = fixtureDir </> "batch-csv-open-quote-mid.csv"
batchCsvOpenQuoteCrlf    = fixtureDir </> "batch-csv-open-quote-crlf.csv"
batchCsvOpenQuoteDoubled = fixtureDir </> "batch-csv-open-quote-doubled.csv"
batchCsvOpenQuoteHeader  = fixtureDir </> "batch-csv-open-quote-header.csv"
batchCsvQuoteClosesAtEof = fixtureDir </> "batch-csv-quote-closes-at-eof.csv"

-- | CSV files whose shape the reader has to get right: a file with one column
-- (where a row of one empty cell and a blank line look alike), a UTF-8
-- byte-order mark before the header, records with too few or too many cells,
-- and CRLF line ends with a quoted cell that holds a line break.
batchOneColFixture, batchOneColCsv, batchOneColSpacesCsv, batchBomCsv, batchRaggedCsv, batchCrlfCsv :: FilePath
batchOneColFixture   = fixtureDir </> "batch-onecol.l4"
batchOneColCsv       = fixtureDir </> "batch-onecol.csv"
batchOneColSpacesCsv = fixtureDir </> "batch-onecol-spaces.csv"
batchBomCsv          = fixtureDir </> "batch-bom.csv"
batchRaggedCsv       = fixtureDir </> "batch-ragged.csv"
batchCrlfCsv         = fixtureDir </> "batch-crlf.csv"

-- | A string literal holding a line break and a tab (smucclaw/l4-ide#1028).
batchLineBreakFixture, batchLineBreakJson :: FilePath
batchLineBreakFixture = fixtureDir </> "batch-string-line-break.l4"
batchLineBreakJson    = fixtureDir </> "batch-string-line-break.json"

-- | Cases that send text for a NUMBER or BOOLEAN input (@"25"@, @"false"@) or a
-- CSV cell for a STRING input, run against 'batchEligFixture' and
-- 'batchCodeFixture'.
batchDeclaredStringsJson, batchDeclaredStringsYaml, batchDeclaredStringCellsCsv, batchDeclaredBadNumberJson, batchDeclaredNumberForStringJson :: FilePath
batchDeclaredStringsJson           = fixtureDir </> "batch-declared-strings.json"
batchDeclaredStringsYaml           = fixtureDir </> "batch-declared-strings.yaml"
batchDeclaredStringCellsCsv        = fixtureDir </> "batch-declared-string-cells.csv"
batchDeclaredBadNumberJson         = fixtureDir </> "batch-declared-bad-number.json"
batchDeclaredNumberForStringJson   = fixtureDir </> "batch-declared-number-for-string.json"

-- | Decode stdout as a single JSON array (for @l4 batch --format json@).
decodeArray :: String -> IO [Value]
decodeArray sout =
  case eitherDecode (BSL8.pack sout) of
    Right (Array v)  -> pure (foldr (:) [] v)
    Right other      -> do
      expectationFailure ("Expected a JSON array, got: " ++ show other)
      error "unreachable"
    Left err         -> do
      expectationFailure ("JSON array parse failed: " ++ err ++ "\nstdout:\n" ++ sout)
      error "unreachable"

-- | Count non-blank lines (each NDJSON row is one line).
nonBlankLines :: String -> Int
nonBlankLines = length . filter (not . all (`elem` (" \t\r" :: String))) . lines

batchEscapeFixture, batchEscapeInput, batchEscapeRoundtripJson, batchEscapeCellsCsv :: FilePath
batchEscapeFixture = fixtureDir </> "batch-escape.l4"
batchEscapeInput   = fixtureDir </> "batch-escape-input.json"
batchEscapeRoundtripJson = fixtureDir </> "batch-escape-roundtrip.json"
batchEscapeCellsCsv = fixtureDir </> "batch-escape-cells.csv"

-- Diamond over the embedded-library fallback (smucclaw/l4-ide#906): main imports two
-- embedded siblings that share the embedded 'daydate' bottom.
embeddedDiamondEntry :: FilePath
embeddedDiamondEntry = fixtureDir </> "embedded-diamond" </> "main.l4"

-- Library-shadow fixtures (specs/as-built/import-resolution.md): a bare `IMPORT prelude` with no
-- project-scoped copy (embedded must win over a poisoned XDG store), and a
-- companion with a project-local prelude override (which must win over the
-- embedded stdlib).
shadowEmbeddedEntry, shadowSiblingEntry, shadowExtraEntry :: FilePath
shadowEmbeddedEntry = fixtureDir </> "library-shadow" </> "embedded-wins" </> "main.l4"
shadowSiblingEntry  = fixtureDir </> "library-shadow" </> "sibling-wins"  </> "main.l4"
shadowExtraEntry    = fixtureDir </> "library-shadow" </> "xdg-extra"     </> "main.l4"

-- Directories of the shadow fixtures, for the tests that run the CLI from
-- INSIDE the project (@l4 check main.l4@) rather than naming the fixture by a
-- path with a directory component.
shadowEmbeddedDir, shadowSiblingDir, shadowImporterDir :: FilePath
shadowEmbeddedDir = fixtureDir </> "library-shadow" </> "embedded-wins"
shadowSiblingDir  = fixtureDir </> "library-shadow" </> "sibling-wins"
shadowImporterDir = fixtureDir </> "library-shadow" </> "embedded-importer"

-- A project-local override of a module that an EMBEDDED library imports.
shadowImporterEntry :: FilePath
shadowImporterEntry = shadowImporterDir </> "main.l4"

-- | A @\@ref@ that trails its code (line 4) and one with nothing after it
-- (line 8): two warnings, no error.
refTrailingFixture :: FilePath
refTrailingFixture = fixtureDir </> "ref-trailing.l4"

-- | Multi-clause groups whose compiled form, printed back as source for
-- @l4 batch@, met a drafter's name or depended on the source text around it
-- (review of legalese/l4-ide#545 and #581); see the fixtures.
batchClauses, batchClausesCapture, batchClausesCatchAll, batchClausesDitto, batchClausesDittoHead
  , batchClausesTabs, batchClausesString
  , batchClausesColours, batchClausesBooleans, batchClausesB :: FilePath
batchClauses          = fixtureDir </> "batch-multi-clause.l4"
batchClausesCapture   = fixtureDir </> "batch-multi-clause-capture.l4"
batchClausesCatchAll  = fixtureDir </> "batch-multi-clause-catch-all.l4"
batchClausesDitto     = fixtureDir </> "batch-multi-clause-ditto.l4"
batchClausesDittoHead = fixtureDir </> "batch-multi-clause-ditto-head.l4"
batchClausesTabs      = fixtureDir </> "batch-multi-clause-tabs.l4"
batchClausesString    = fixtureDir </> "batch-multi-clause-string.l4"
batchClausesColours   = fixtureDir </> "batch-multi-clause-colours.json"
batchClausesBooleans  = fixtureDir </> "batch-multi-clause-booleans.json"
batchClausesB         = fixtureDir </> "batch-multi-clause-b.json"

-- | Two multi-clause groups, for how @l4 render@ and a trace name their parts.
multiClauseRenderFixture :: FilePath
multiClauseRenderFixture = fixtureDir </> "multi-clause-render.l4"

-- Import-cycle fixtures: entry points of small multi-file rings, and one whose
-- entry file imports a ring without being part of it.
cycle3Entry, cycle3OutsideEntry, cycle2Entry, selfImportEntry :: FilePath
cycle3Entry        = fixtureDir </> "cycle3"     </> "cyca.l4"
cycle3OutsideEntry = fixtureDir </> "cycle3"     </> "outside.l4"
cycle2Entry        = fixtureDir </> "cycle2"     </> "dua.l4"
selfImportEntry    = fixtureDir </> "selfimport" </> "solo.l4"

-- An exported rule with a DEONTIC input, which a request cannot supply; and the
-- reference page's example of what to write instead, which `l4 check` accepts.
exportDeonticFixture, deonticExportExample :: FilePath
exportDeonticFixture = fixtureDir </> "export-deontic.l4"
deonticExportExample = "../doc/reference/regulative/deontic-export-example.l4"

-- An exported rule whose DEONTIC input has no written type, and one that reads
-- an ASSUME of type DEONTIC that an imported module declares: a request cannot
-- supply either.
exportUntypedFixture, exportUntypedInputs, exportAssumeImportedFixture :: FilePath
exportUntypedFixture         = fixtureDir </> "export-untyped.l4"
exportUntypedInputs          = fixtureDir </> "export-untyped-input.json"
exportAssumeImportedFixture  = fixtureDir </> "export-assume-imported" </> "main.l4"

-- Multi-file imports that are not rings: a clean one, one whose imported module
-- only warns, and four that cannot be loaded cleanly: an imported module with a
-- type error, with a syntax error, and with a string that is never closed, and an
-- IMPORT of a module that does not exist. In each of those the entry file is
-- itself fine, and never uses anything from the import. The first two are guards
-- against the import check over-firing.
cleanImportEntry, warningImportEntry, brokenImportEntry :: FilePath
cleanImportEntry   = fixtureDir </> "imports-ok"      </> "main.l4"
warningImportEntry = fixtureDir </> "imports-warning" </> "main.l4"
brokenImportEntry  = fixtureDir </> "imports-error"   </> "main.l4"

syntaxImportEntry, lexImportEntry, missingImportEntry :: FilePath
syntaxImportEntry  = fixtureDir </> "imports-syntax"  </> "main.l4"
lexImportEntry     = fixtureDir </> "imports-lex"     </> "main.l4"
missingImportEntry = fixtureDir </> "imports-missing" </> "main.l4"

----------------------------------------------------------------------------
-- Tests
----------------------------------------------------------------------------

main :: IO ()
main = do
  bin <- locateL4Binary
  putStrLn ("Using l4 binary: " ++ bin)
  -- Sanity check fixtures exist (test suite must be run from repo root).
  for_ [ cleanFixture, evalFixture, errorFixture, garbageFixture
       , batchEscapeFixture, batchEscapeInput, batchEscapeRoundtripJson, batchEscapeCellsCsv
       , evalTraceFixture, refTrailingFixture
       , langEnHintFixture, langEnThenHeFixture, langTagCaseFixture
       , bilingualFixture, bilingualFramesFixture
       , batchClauses, batchClausesCapture, batchClausesCatchAll, batchClausesDitto
       , batchClausesDittoHead, batchClausesTabs, batchClausesString
       , batchClausesColours, batchClausesBooleans, batchClausesB
       , multiClauseRenderFixture
       , exportDeonticFixture, deonticExportExample
       , exportUntypedFixture, exportUntypedInputs, exportAssumeImportedFixture
       , cycle3Entry, cycle3OutsideEntry, cycle2Entry, selfImportEntry
       , cleanImportEntry, warningImportEntry, brokenImportEntry
       , syntaxImportEntry, lexImportEntry, missingImportEntry
       , nlgPromissorySource, nlgPromissoryGolden, nlgShowcaseSource, nlgShowcaseGolden
       , nlgHeadPlacementSource
       , buildIdentityScript, buildIdentityPackageJson ] \fp -> do
    ok <- doesFileExist fp
    unless ok $ do
      putStrLn ("Missing fixture: " ++ fp)
      putStrLn "Run this suite from the repository root (jl4/ is the working directory)."
      exitFailure
  hspec (spec bin)
  where
    for_ xs f = mapM_ f xs

spec :: FilePath -> Spec
spec bin = do
  describe "l4 --help" $ do
    it "lists every subcommand" $ do
      Output code sout _ <- runL4 bin ["--help"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("run" `isInfixOf`)
      sout `shouldSatisfy` ("check" `isInfixOf`)
      sout `shouldSatisfy` ("format" `isInfixOf`)
      sout `shouldSatisfy` ("ast" `isInfixOf`)
      sout `shouldSatisfy` ("batch" `isInfixOf`)
      sout `shouldSatisfy` ("trace" `isInfixOf`)
      sout `shouldSatisfy` ("state-graph" `isInfixOf`)
      sout `shouldSatisfy` ("nlg" `isInfixOf`)

  describe "l4 deploy / redeploy / undeploy / deployments (no network)" $ do
    let expectStderr args mEnv needle = do
          Output code _ serr <- runL4In Nothing mEnv bin args
          code `shouldNotBe` ExitSuccess
          unless (needle `isInfixOf` serr) $
            expectationFailure ("Expected stderr to contain " ++ show needle ++ "\n--- stderr ---\n" ++ serr)
        -- Nothing listens on the discard port; every case below must stop
        -- before connecting.
        noServer = ["--server", "http://127.0.0.1:9"]

    it "are listed in --help, and each takes --help" $ do
      Output _ sout _ <- runL4 bin ["--help"]
      mapM_ (\c -> sout `shouldSatisfy` (c `isInfixOf`)) ["deploy", "redeploy", "undeploy", "deployments", "install"]
      expectOk bin ["deploy", "--help"] "--name"
      expectOk bin ["install", "legalese", "--help"] "--dir"

    it "refuses a deployment name the service would reject" $
      expectStderr (["deploy", cleanFixture, "--name", "bad name!"] ++ noServer) Nothing "may only contain"

    it "refuses to deploy a file that doesn't typecheck" $
      expectStderr (["deploy", errorFixture] ++ noServer) Nothing "doesn't typecheck"

    it "only takes --api-key-file with --server" $
      expectStderr ["deployments", "--api-key-file", cleanFixture] Nothing "--api-key-file only applies with --server"

    it "won't send an API key over plain http to another host" $
      expectStderr ["deployments", "--server", "http://example.com"] (Just [("L4_API_KEY", "k")]) "over plain http"

    it "needs the legalese CLI for Legalese Cloud" $ do
      tmp <- getTemporaryDirectory
      let emptyPath = tmp </> "l4-cli-test-empty-path"
      createDirectoryIfMissing True emptyPath
      expectStderr ["deployments"] (Just [("PATH", emptyPath)]) "l4 install legalese"

    it "won't undeploy without a terminal unless --yes" $
      expectStderr (["undeploy", "anything"] ++ noServer) Nothing "Pass --yes"

  describe "l4 run" $ do
    it "succeeds on a clean file" $
      expectOk bin ["run", cleanFixture] "Checking succeeded."

    it "emits a well-shaped JSON envelope on a clean file" $ do
      env <- jsonEnvelope bin ["run", cleanFixture, "--json"]
      objField env "ok" `shouldBe` Just (Bool True)
      objField env "diagnostics" `shouldSatisfy` (/= Nothing)
      objField env "results" `shouldSatisfy` (/= Nothing)

    it "prints evaluation results for #EVAL directives" $ do
      Output code sout _ <- runL4 bin ["run", evalFixture]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("Evaluation[1]" `isInfixOf`)
      sout `shouldSatisfy` ("Evaluation[2]" `isInfixOf`)

    it "reports #EVAL results in JSON" $ do
      env <- jsonEnvelope bin ["run", evalFixture, "--json"]
      case objField env "results" of
        Just (Array v) -> length v `shouldBe` 2
        other          -> expectationFailure ("Expected results array, got " ++ show other)

    it "fails on a typecheck error" $
      expectFail bin ["run", errorFixture]

    it "returns ok=false in JSON on a typecheck error" $ do
      env <- jsonEnvelope bin ["run", errorFixture, "--json"]
      objField env "ok" `shouldBe` Just (Bool False)

    it "reports an evaluation error in JSON in the drafter's terms, not as Haskell" $ do
      env <- jsonEnvelope bin ["run", fixtureDir </> "multi-clause-no-match.l4", "--json"]
      case objField env "results" of
        Just (Array v) | [Object r] <- foldr (:) [] v -> case KeyMap.lookup (Key.fromString "value") r of
          Just (String msg) -> do
            T.unpack msg `shouldSatisfy` ("No clause of `price` matches" `isInfixOf`)
            T.unpack msg `shouldSatisfy` (not . ("MkPmGroup" `isInfixOf`))
            T.unpack msg `shouldSatisfy` (not . ("NonExhaustivePatterns" `isInfixOf`))
          other -> expectationFailure ("Expected an error string, got " ++ show other)
        other -> expectationFailure ("Expected one result, got " ++ show other)

    it "falls through from a bare positional argument (backward-compat)" $
      expectOk bin [cleanFixture] "Checking succeeded."

  describe "l4 check" $ do
    it "succeeds on a clean file" $
      expectOk bin ["check", cleanFixture] "Check succeeded."

    it "returns ok=true in JSON on a clean file" $ do
      env <- jsonEnvelope bin ["check", cleanFixture, "--json"]
      objField env "ok" `shouldBe` Just (Bool True)

    it "fails on a typecheck error" $
      expectFail bin ["check", errorFixture]

    it "returns ok=false in JSON on a typecheck error" $ do
      env <- jsonEnvelope bin ["check", errorFixture, "--json"]
      objField env "ok" `shouldBe` Just (Bool False)

    it "fails on unparseable garbage input" $ do
      Output code _ _ <- runL4 bin ["check", garbageFixture]
      code `shouldSatisfy` (/= ExitSuccess)

    -- The two warnings of the @ref pass, as the LSP renders them (their text is
    -- quoted in doc/reference/syntax/README.md, which is the page to change
    -- with it). They are warnings, so the check still succeeds.
    it "warns about a @ref after code and a @ref with nothing after it, and still succeeds" $ do
      Output code sout serr <- runL4 bin ["check", refTrailingFixture]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("Check succeeded." `isInfixOf`)
      let err = filter (/= '\r') serr
      err `shouldSatisfy` isInfixOf "Range:    4:18-4:49"
      err `shouldSatisfy` isInfixOf
        "This @ref (`Section 4(1)(a) of the Act`) follows code on its line, but a @ref refers to what follows it, so this one is attached to nothing. Put it on the line above `GIVETH A BOOLEAN`."
      err `shouldSatisfy` isInfixOf "Range:    8:1-8:15"
      err `shouldSatisfy` isInfixOf
        "This @ref (`Section 9`) is at the end of the file, so there is nothing after it to attach to."
      length (filter (isInfixOf "Severity: DiagnosticSeverity_Warning") (lines err)) `shouldBe` 2

    it "warns that a multi-clause DECIDE misses a case, and still succeeds" $ do
      let fixture = fixtureDir </> "multi-clause-missing.l4"
      Output code sout serr <- runL4 bin ["check", fixture]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("Check succeeded." `isInfixOf`)
      serr `shouldSatisfy` ("does not cover all cases" `isInfixOf`)
      serr `shouldSatisfy` ("DECIDE `price` Blue IS" `isInfixOf`)

  -- A DEONTIC has no JSON form, so an exported rule that takes one is refused
  -- at check time, as one that takes an EVENT is. The guard is the example that
  -- the DEONTIC reference page recommends instead: a helper that takes a
  -- DEONTIC and a list of events, and exported rules that take plain facts.
  describe "l4 check: an @export with a DEONTIC input" $ do
    it "fails and says what is wrong and what to do" $ do
      Output code sout serr0 <- runL4 bin ["check", exportDeonticFixture]
      let serr = filter (/= '\r') serr0
      code `shouldBe` ExitFailure 1
      sout `shouldSatisfy` (not . isInfixOf "Check succeeded.")
      serr `shouldSatisfy` isInfixOf "Severity: DiagnosticSeverity_Error"
      serr `shouldSatisfy` isInfixOf "DEONTIC inputs are not supported for @export."
      serr `shouldSatisfy` isInfixOf
        "The input `the duty` has a type that contains a DEONTIC, and a request has no JSON form for a DEONTIC."
      serr `shouldSatisfy` isInfixOf
        "Give the rule the plain facts that the DEONTIC is made from as inputs, and build the DEONTIC inside it."

    it "returns ok=false in JSON" $ do
      env <- jsonEnvelope bin ["check", exportDeonticFixture, "--json"]
      objField env "ok" `shouldBe` Just (Bool False)

    it "accepts the page's example of what to write instead, and its two #EVALs still answer TRUE and FALSE" $ do
      expectOk bin ["check", deonticExportExample] "Check succeeded."
      Output code sout _ <- runL4 bin ["run", deonticExportExample]
      code `shouldBe` ExitSuccess
      let outLines = lines (filter (/= '\r') sout)
          results = [ trim l | (prev, l) <- zip outLines (drop 1 outLines), prev == "Result:" ]
          trim = reverse . dropWhile (== ' ') . reverse . dropWhile (== ' ')
      results `shouldBe` ["TRUE", "FALSE"]

  -- An input needs no written type, and an ASSUME can be declared in another
  -- module: neither is a way round the refusal. The input that the checker
  -- infers to be a DEONTIC is refused, and so is the imported ASSUME that the
  -- rule reads, by `l4 check`, and by `l4 batch` before it runs a row.
  describe "l4 check: an @export with a DEONTIC that it takes without a written type, or reads from an import" $ do
    forM_ [ ("an input with no written type", exportUntypedFixture, "the duty")
          , ("an ASSUME of an imported module", exportAssumeImportedFixture, "imported duty")
          ] \(what, fixture, input) ->
      it ("fails on " <> what <> ", naming it") $ do
        Output code sout serr0 <- runL4 bin ["check", fixture]
        let serr = filter (/= '\r') serr0
        code `shouldBe` ExitFailure 1
        sout `shouldSatisfy` (not . isInfixOf "Check succeeded.")
        serr `shouldSatisfy` isInfixOf "DEONTIC inputs are not supported for @export."
        serr `shouldSatisfy` isInfixOf
          ("The input `" <> input <> "` has a type that contains a DEONTIC, and a request has no JSON form for a DEONTIC.")

    it "makes l4 batch refuse the file before it runs a row, as it refuses a written type" $ do
      Output code sout serr0 <- runL4 bin ["batch", exportUntypedFixture, "--inputs", exportUntypedInputs]
      let out = filter (/= '\r') (sout <> serr0)
      code `shouldBe` ExitFailure 1
      out `shouldSatisfy` isInfixOf "DEONTIC inputs are not supported for @export."
      out `shouldSatisfy` isInfixOf "The input `the duty` has a type that contains a DEONTIC"
      out `shouldNotSatisfy` isInfixOf "\"status\""

  -- An import ring used to pass `l4 check` and `l4 run` with exit 0 and "Check
  -- succeeded." printed under the cycle's own error. The engine reports the
  -- cycle as an Error on a module that is IMPORTED, not on the file named on the
  -- command line, and the verdict looked only at the named file's typecheck. A
  -- self-import is the exception: there the error lands on the entry file, so
  -- it already failed, which makes it the positive control for the rest.
  describe "l4 import cycles" $ do
    forM_ ["check", "run"] \cmd -> do
      it ("fails " <> cmd <> " on a 3-module import ring") $
        expectExit1 bin [cmd, cycle3Entry]

      it ("fails " <> cmd <> " on a 2-module import ring") $
        expectExit1 bin [cmd, cycle2Entry]

      it ("fails " <> cmd <> " on a self-import") $
        expectExit1 bin [cmd, selfImportEntry]

      -- The file named on the command line is not in the ring, so the error
      -- cannot land on it.
      it ("fails " <> cmd <> " when the entry file imports a ring without being in it") $
        expectExit1 bin [cmd, cycle3OutsideEntry]

      it ("reports ok=false in JSON from " <> cmd <> " on a cyclic import") $
        expectJsonNotOk bin [cmd, cycle3Entry]

    -- `l4 FILE` with no command is `l4 run FILE`.
    it "fails the bare `l4 FILE` form on a 3-module import ring" $
      expectExit1 bin [cycle3Entry]

  -- The verdict now also looks at the modules a file imports. These are the
  -- cases it must NOT turn into a failure, so that the check above cannot be
  -- satisfied by failing everything that has an IMPORT.
  describe "l4 check and run on imports that are not cycles" $ do
    it "still succeeds on a clean multi-file import" $ do
      expectOk bin ["check", cleanImportEntry] "Check succeeded."
      expectOk bin ["run", cleanImportEntry] "Checking succeeded."

    -- A warning in an imported module is a warning, as it is in the entry file.
    it "still succeeds when an imported module only warns" $ do
      expectOk bin ["check", warningImportEntry] "Check succeeded."
      expectOk bin ["run", warningImportEntry] "Checking succeeded."

    -- A failed #ASSERT is published as an Error diagnostic of the evaluator's
    -- own. It is a verdict about the rules, not a fault in the file, so it must
    -- not become one now that every Error in the closure counts; the plain-text
    -- case is "leaves a clean FALSE #ASSERT at exit 0" under `l4 run`.
    it "still reports ok=true in JSON for a failed #ASSERT" $ do
      env <- jsonEnvelope bin ["run", fixtureDir </> "assert-clean.l4", "--json"]
      objField env "ok" `shouldBe` Just (Bool True)

  -- Not a ring, but the same blind spot: the entry file typechecks against the
  -- modules it imports, and an error INSIDE one of them, or an IMPORT that
  -- finds no module at all, did not fail the run. In each case the entry file is
  -- fine and uses nothing from the import, so only the import's own error can
  -- fail it. The unresolved IMPORT is reported as a module that could not be
  -- found, and not also as a module that depends on itself.
  describe "l4 check and run on an import that cannot be loaded" $
    forM_ [ ("a type error in an imported module", brokenImportEntry)
          , ("a syntax error in an imported module", syntaxImportEntry)
          , ("an unclosed string in an imported module", lexImportEntry)
          , ("an IMPORT that resolves to no module", missingImportEntry)
          ] \(what, entry) ->
      forM_ ["check", "run"] \cmd -> do
        it ("fails " <> cmd <> " on " <> what) $
          expectExit1 bin [cmd, entry]

        it ("reports ok=false in JSON from " <> cmd <> " on " <> what) $
          expectJsonNotOk bin [cmd, entry]

  -- `l4 deploy` and `l4 redeploy` refuse a file for the reasons `l4 check`
  -- does, and say so before they touch the network. Nothing listens on the
  -- discard port, so a command that gets past the local check stops at the
  -- first request with "Could not reach", and one that refuses never gets that
  -- far. The refusal carries the same diagnostics `l4 check` prints.
  describe "l4 deploy and redeploy refuse what l4 check refuses" $ do
    let noServer = ["--server", "http://127.0.0.1:9"]
        refusal = "doesn't typecheck; fix it before deploying (see `l4 check`)."
        errorLabel = "Severity: DiagnosticSeverity_Error"
        textBefore needle = go []
          where
            go acc s
              | needle `isPrefixOf` s = Just (reverse acc)
              | otherwise = case s of
                  [] -> Nothing
                  c : cs -> go (c : acc) cs

    forM_ [ ("a type error in an imported module", brokenImportEntry)
          , ("a syntax error in an imported module", syntaxImportEntry)
          , ("an unclosed string in an imported module", lexImportEntry)
          , ("an IMPORT that resolves to no module", missingImportEntry)
          , ("a 3-module import ring", cycle3Entry)
          , ("a file that imports a ring without being in it", cycle3OutsideEntry)
          , ("a 2-module import ring", cycle2Entry)
          , ("a self-import", selfImportEntry)
          , ("an @export with a DEONTIC input", exportDeonticFixture)
          , ("an @export with a DEONTIC input that has no written type", exportUntypedFixture)
          , ("an @export that reads a DEONTIC ASSUME of an imported module", exportAssumeImportedFixture)
          ] \(what, entry) ->
      forM_ ["deploy", "redeploy"] \cmd ->
        it ("refuses " <> cmd <> " of " <> what <> ", with the diagnostics, before the network") $ do
          Output check _ _ <- runL4 bin ["check", entry]
          check `shouldBe` ExitFailure 1
          Output code sout serr0 <- runL4 bin ([cmd, entry] ++ noServer)
          let serr = filter (/= '\r') serr0
          code `shouldBe` ExitFailure 1
          sout `shouldBe` ""
          serr `shouldSatisfy` isInfixOf refusal
          serr `shouldNotSatisfy` isInfixOf "Could not reach"
          -- The error comes first, then the refusal that says what to do.
          case textBefore refusal serr of
            Just printed -> printed `shouldSatisfy` isInfixOf errorLabel
            Nothing -> expectationFailure ("no refusal in:\n" ++ serr)

    -- The guards: a file `l4 check` accepts, and one it accepts with a warning
    -- from an imported module, must get past the local check, or the refusal
    -- above could be satisfied by refusing every file that has an IMPORT.
    forM_ [ ("a clean multi-file import", cleanImportEntry)
          , ("an imported module that only warns", warningImportEntry)
          ] \(what, entry) ->
      forM_ ["deploy", "redeploy"] \cmd ->
        it ("lets " <> cmd <> " of " <> what <> " past the local check") $ do
          Output check _ _ <- runL4 bin ["check", entry]
          check `shouldBe` ExitSuccess
          Output code _ serr <- runL4 bin ([cmd, entry] ++ noServer)
          code `shouldBe` ExitFailure 1
          serr `shouldSatisfy` isInfixOf "Could not reach http://127.0.0.1:9"
          serr `shouldNotSatisfy` isInfixOf "doesn't typecheck"

  -- The names a multi-clause group is compiled to are spelled so that no
  -- source can write them ('L4.Parser.generatedName'), and say what they are.
  describe "multi-clause groups: the names they are compiled to" $ do
    let generatedSpellings = ["_pm_", "__pm_", "pm arg", "pm_fallthrough"]
        mentionsOldName out = any (`isInfixOf` out) generatedSpellings

    it "reads the clauses as one list of cases in l4 render" $ do
      Output code sout0 _ <- runL4 bin ["render", "--format", "text", multiClauseRenderFixture]
      code `shouldBe` ExitSuccess
      -- Windows ends lines with a carriage return, as in the l4 format test.
      let sout = filter (/= '\r') sout0
      sout `shouldSatisfy` ("- if it is Green: 2\n    - otherwise: 3" `isInfixOf`)
      sout `shouldSatisfy` ("depending on input 1:" `isInfixOf`)
      sout `shouldSatisfy` ("- otherwise: the result of clause 2" `isInfixOf`)
      sout `shouldSatisfy` ("The result of clause 2 is determined by:" `isInfixOf`)
      sout `shouldNotSatisfy` mentionsOldName

    it "names no generated input in the HTML rendering either" $ do
      Output code sout _ <- runL4 bin ["render", multiClauseRenderFixture]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("input 1" `isInfixOf`)
      sout `shouldNotSatisfy` mentionsOldName

    it "names the later clauses by the clauses they hold in a trace" $ do
      Output code sout _ <- runL4 bin ["trace", multiClauseRenderFixture]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("`the result of clauses 2 to 3`" `isInfixOf`)
      sout `shouldNotSatisfy` mentionsOldName

  -- `l4 batch` runs a module printed back as source. A multi-clause group
  -- prints as its clauses, from the AST ('L4.Print.writtenClauses'), so that
  -- no name the desugarer made up is written out as source, where a
  -- drafter's name could capture it, and nothing depends on the text around
  -- the clauses in the source (dittos, indentation).
  describe "l4 batch: re-prints a multi-clause group as its clauses" $ do
    let results args = do
          Output code sout _ <- runL4 bin (["batch"] <> args)
          code `shouldBe` ExitSuccess
          pure [ (objField row "status", outResult row)
               | l <- lines sout
               , Right row <- [eitherDecode (BSL8.pack l) :: Either String Value]
               ]
        outResult row = case objField row "output" of
          Just (Array os) | [o] <- foldr (:) [] os -> objField o "result"
          _ -> Nothing
        ok v = (Just (String "success"), Just v)
    it "reads a drafter's definition named like the binding of the later clauses" $
      results [batchClauses, "-e", "later", "--inputs", batchClausesColours]
        >>= (`shouldBe` map ok [Number 7, Number 2, Number 3])
    it "reads a drafter's definition named like the binding of the last clause" $
      results [batchClauses, "-e", "fee", "--inputs", batchClausesColours]
        >>= (`shouldBe` map ok [Number 1, Number 101, Number 3])
    it "reads a drafter's definition named like an input of a group with no GIVEN" $
      results [batchClauses, "-e", "through", "--inputs", batchClausesColours]
        >>= (`shouldBe` map ok [String "Blue", String "Red", String "Green"])
    it "reads a drafter's `input 1` in a group whose only clause left matches anything" $ do
      results [batchClausesCatchAll, "-e", "one", "--inputs", batchClausesColours]
        >>= (`shouldBe` map ok [String "Blue", String "Blue", String "Blue"])
      results [batchClausesCatchAll, "-e", "two", "--inputs", batchClausesColours]
        >>= (`shouldBe` map ok [String "Blue", String "Blue", String "Blue"])
    it "tests the input a pattern variable is named after, not the variable" $
      results [batchClausesCapture, "-e", "capture", "--inputs", batchClausesBooleans]
        >>= (`shouldBe` map ok [Number 1, Number 2, Number 1, Number 2])
    it "keeps what a ditto in a clause body copies" $
      results [batchClausesDitto, "--inputs", batchClausesColours]
        >>= (`shouldBe` map ok [Number 1, Number 0, Number 0])
    it "keeps what a ditto in a clause head copies" $
      results [batchClausesDittoHead, "--inputs", batchClausesB]
        >>= (`shouldBe` map ok [Number 1, Number 2])
    it "reads clauses indented with tabs" $
      results [batchClausesTabs, "--inputs", batchClausesColours]
        >>= (`shouldBe` map ok [Number 1, Number 3, Number 3])
    -- A string that spans lines keeps the later lines as the source wrote
    -- them: printed back as source, its line break is written as an escape
    -- (#595), so the printer's indentation cannot enter the string. `l4 run`
    -- gives "a\n      b".
    it "keeps a string that spans lines in a clause body" $ do
      results [batchClausesString, "--inputs", batchClausesColours]
        >>= (`shouldBe` map ok [String "a\n      b", String "z", String "z"])

  describe "l4 run on a definition whose evaluation raised" $ do
    -- A thunk whose evaluation raised is evaluated again on its next use, and
    -- raises again. It used to keep the mark of the aborted force, so its
    -- second use was reported as an infinite loop.
    it "raises the same error again on a second use" $ do
      Output _ sout _ <- runL4 bin ["run", fixtureDir </> "raise-twice.l4"]
      T.count "Division by zero" (T.pack sout) `shouldBe` 2
      sout `shouldNotSatisfy` ("Infinite loop" `isInfixOf`)

    -- The control: the check is still on. A definition that is its own operand,
    -- and a pair that are each other's, are infinite loops at every use.
    it "still reports a genuine loop as a loop, at every use" $ do
      Output _ sout _ <- runL4 bin ["run", fixtureDir </> "loop-twice.l4"]
      T.count "Infinite loop detected" (T.pack sout) `shouldBe` 4
      sout `shouldNotSatisfy` ("Division by zero" `isInfixOf`)

  describe "l4 run on an #ASSERT whose expression raises" $ do
    -- Typechecks cleanly; every @#ASSERT@ in it RAISES instead of deciding.
    let assertRaisesFixture = fixtureDir </> "assert-raises.l4"
        -- @#ASSERT P@ and @#ASSERT NOT P@ for a @P@ that raises, then one clean
        -- TRUE and one clean FALSE as controls.
        assertRaisesPairFixture = fixtureDir </> "assert-raises-pair.l4"
        -- Every @#ASSERT@ decides: one holds, one does not.
        assertCleanFixture = fixtureDir </> "assert-clean.l4"

    -- An #ASSERT whose expression RAISES is a distinct outcome from one that
    -- evaluates to FALSE. Before this was pinned, `#ASSERT P` and
    -- `#ASSERT NOT P` both reported "assertion failed" whenever P raised
    -- (division by zero, an assumed term, …), so a test suite could not tell
    -- a wrong answer from an error.
    it "reports an #ASSERT that raises as unevaluable, with the reason, never as failed" $ do
      Output _ sout _ <- runL4 bin ["run", assertRaisesFixture]
      sout `shouldSatisfy` ("assertion could not be evaluated" `isInfixOf`)
      sout `shouldSatisfy` ("Division by zero" `isInfixOf`)
      sout `shouldSatisfy` ("assumed term" `isInfixOf`)
      sout `shouldNotSatisfy` ("assertion failed" `isInfixOf`)

    -- It did not evaluate cleanly, so it is the crash that fails the run, as a
    -- #EVAL that raises does. A clean FALSE (below) stays exit 0.
    it "fails the run when an #ASSERT raises" $
      expectFail bin ["run", assertRaisesFixture]

    it "keeps kind \"assertion\", a null value and the reason in JSON when an #ASSERT raises" $ do
      env <- jsonEnvelope bin ["run", assertRaisesFixture, "--json"]
      objField env "ok" `shouldBe` Just (Bool False)
      case objField env "results" of
        Just (Array v) -> do
          length v `shouldBe` 2
          mapM_ (\r -> do
                   objField r "kind"  `shouldBe` Just (String "assertion")
                   objField r "value" `shouldBe` Just Null
                   case objField r "error" of
                     Just (String s) -> s `shouldSatisfy` ("assertion could not be evaluated" `T.isInfixOf`)
                     other -> expectationFailure ("Expected an error string, got " ++ show other))
                v
        other -> expectationFailure ("Expected results array, got " ++ show other)

    it "still typechecks the raising fixture — l4 check succeeds on it" $
      expectOk bin ["check", assertRaisesFixture] "Check succeeded."

    -- A bare assumed BOOLEAN is neither TRUE nor FALSE. `#ASSERT NOT b`
    -- forces b and raises; `#ASSERT b` (and `#ASSERT TRUE AND b`, which is just
    -- b) reduces to the symbolic b WITHOUT raising, and used to fall through to
    -- "assertion failed" -- so the polarities disagreed about the same
    -- undecidable term.
    it "reports an #ASSERT on a bare assumed BOOLEAN as undecided, in every spelling" $ do
      Output _ sout _ <- runL4 bin ["run", fixtureDir </> "assert-assumed.l4"]
      length (filter ("assertion could not be evaluated" `isInfixOf`) (lines sout)) `shouldBe` 3
      sout `shouldSatisfy` ("assumed term" `isInfixOf`)
      sout `shouldNotSatisfy` ("assertion failed" `isInfixOf`)
      sout `shouldNotSatisfy` ("assertion satisfied" `isInfixOf`)

    -- Alone, so that it cannot be the `NOT b` (which raises either way) that
    -- fails the run.
    it "fails the run when an #ASSERT is stuck on a bare assumed BOOLEAN" $
      expectFail bin ["run", fixtureDir </> "assert-assumed-bare.l4"]

    -- The second #ASSERT over a definition that raised must say what it raised.
    it "reports both polarities over one raising definition with what it raised" $ do
      Output _ sout _ <- runL4 bin ["run", fixtureDir </> "assert-twice.l4"]
      T.count "assertion could not be evaluated" (T.pack sout) `shouldBe` 2
      T.count "Division by zero" (T.pack sout) `shouldBe` 2
      sout `shouldNotSatisfy` ("assertion failed" `isInfixOf`)
      sout `shouldNotSatisfy` ("Infinite loop" `isInfixOf`)

    -- The control: a genuine loop is still a loop at every use.
    it "reports an #ASSERT over a genuine loop as a loop, at every use" $ do
      Output _ sout _ <- runL4 bin ["run", fixtureDir </> "assert-loop.l4"]
      T.count "assertion could not be evaluated" (T.pack sout) `shouldBe` 2
      T.count "Infinite loop detected" (T.pack sout) `shouldBe` 2
      sout `shouldNotSatisfy` ("assertion failed" `isInfixOf`)

    it "does not report P and NOT P as failed when P raises, and keeps the clean verdicts" $ do
      Output _ sout _ <- runL4 bin ["run", assertRaisesPairFixture]
      let out = T.pack sout
      T.count "assertion could not be evaluated" out `shouldBe` 2
      -- the one clean FALSE (boom 2) is the only "failed"
      T.count "assertion failed" out `shouldBe` 1
      T.count "assertion satisfied" out `shouldBe` 1

    it "gives P and NOT P a null value and a reason in JSON, and the controls true and false" $ do
      env <- jsonEnvelope bin ["run", assertRaisesPairFixture, "--json"]
      objField env "ok" `shouldBe` Just (Bool False)
      case objField env "results" of
        Just (Array v) -> do
          length v `shouldBe` 4
          case foldr (:) [] v of
            [p, notP, holds, fails] -> do
              mapM_ (\r -> do
                       objField r "value" `shouldBe` Just Null
                       case objField r "error" of
                         Just (String s) -> s `shouldSatisfy` ("assertion could not be evaluated" `T.isInfixOf`)
                         other -> expectationFailure ("Expected an error string, got " ++ show other))
                    [p, notP]
              objField holds "value" `shouldBe` Just (Bool True)
              objField holds "error" `shouldBe` Nothing
              objField fails "value" `shouldBe` Just (Bool False)
              objField fails "error" `shouldBe` Nothing
            other -> expectationFailure ("Expected four results, got " ++ show other)
        other -> expectationFailure ("Expected results array, got " ++ show other)

    -- The editor's squiggles come from these diagnostics. A raising #ASSERT is
    -- an Error that says why, and a satisfied one stays Information.
    it "publishes a raising #ASSERT as an Error diagnostic that says it could not be evaluated" $ do
      env <- jsonEnvelope bin ["run", assertRaisesPairFixture, "--json"]
      case objField env "diagnostics" of
        Just (Array ds) -> do
          let diag = T.intercalate "\n" [ s | String s <- foldr (:) [] ds ]
              -- the published diagnostic that starts at the given line, column 1
              at line = fst $ T.breakOn "File:" $
                T.drop 1 $ snd $ T.breakOn ("Range:    " <> line <> ":1-") diag
          at "7" `shouldSatisfy` ("DiagnosticSeverity_Error" `T.isInfixOf`)
          at "7" `shouldSatisfy` ("assertion could not be evaluated" `T.isInfixOf`)
          at "8" `shouldSatisfy` ("DiagnosticSeverity_Error" `T.isInfixOf`)
          at "8" `shouldSatisfy` ("assertion could not be evaluated" `T.isInfixOf`)
          at "9" `shouldSatisfy` ("DiagnosticSeverity_Information" `T.isInfixOf`)
          at "9" `shouldSatisfy` ("assertion satisfied" `T.isInfixOf`)
          at "10" `shouldSatisfy` ("assertion failed" `T.isInfixOf`)
        other -> expectationFailure ("Expected a diagnostics array, got " ++ show other)

    -- The other side of the line: a clean FALSE is a verdict, not a crash.
    it "leaves a clean FALSE #ASSERT at exit 0, reported as failed" $ do
      Output code sout _ <- runL4 bin ["run", assertCleanFixture]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("assertion failed" `isInfixOf`)
      sout `shouldSatisfy` ("assertion satisfied" `isInfixOf`)
      sout `shouldNotSatisfy` ("could not be evaluated" `isInfixOf`)

  -- A directive that cannot be evaluated is not always the same failure. A
  -- CONSIDER with no matching branch, a division by zero and an #ASSERT whose
  -- expression raises are caught for that one directive: the run fails, but the
  -- other directives still print. A POST or FETCH that fails throws an HTTP
  -- exception that nothing catches there, so the whole file loses its results.
  -- doc/tutorials/getting-started/l4-cli.md and
  -- doc/reference/builtins/http-json.md say both. The same file used to exit 0
  -- and print "Checking succeeded." after a failed request.
  --
  -- The failing address is 127.0.0.1: it is an address, so nothing is looked
  -- up, and nothing is expected to listen on its https port. Nothing below
  -- depends on the operating system's wording of why the connection failed.
  describe "l4 run on a directive that cannot be evaluated" $ do
    forM_ [ ("POST", "request-post-fails.l4"), ("FETCH", "request-fetch-fails.l4") ] \(verb, file) -> do
      let fixture = fixtureDir </> file

      it ("fails the run and prints no result for any directive when a " <> verb <> " cannot connect") $ do
        Output code sout serr0 <- runL4 bin ["run", fixture]
        let serr = filter (/= '\r') serr0
        code `shouldBe` ExitFailure 1
        sout `shouldNotSatisfy` ("Evaluation[" `isInfixOf`)
        sout `shouldNotSatisfy` ("Result:" `isInfixOf`)
        sout `shouldNotSatisfy` ("Checking succeeded." `isInfixOf`)
        -- one message, which names the host and is against the first line of
        -- the file, not against the directive (line 6) that made the request
        T.count "VanillaHttpException" (T.pack serr) `shouldBe` 1
        serr `shouldSatisfy` ("\"127.0.0.1\"" `isInfixOf`)
        diagnosticAtLine 1 serr `shouldSatisfy` T.isInfixOf "DiagnosticSeverity_Error"
        diagnosticAtLine 1 serr `shouldSatisfy` T.isInfixOf "VanillaHttpException"
        diagnosticAtLine 6 serr `shouldBe` ""

      it ("reports ok=false, no results and one diagnostic in JSON when a " <> verb <> " cannot connect") $ do
        expectExit1 bin ["run", "--json", fixture]
        env <- jsonEnvelope bin ["run", "--json", fixture]
        objField env "ok" `shouldBe` Just (Bool False)
        objField env "results" `shouldBe` Just (Array mempty)
        case objField env "diagnostics" of
          Just (Array ds) -> do
            length ds `shouldBe` 1
            T.concat [ s | String s <- toList ds ] `shouldSatisfy` T.isInfixOf "VanillaHttpException"
          other -> expectationFailure ("Expected a diagnostics array, got " ++ show other)

      -- `l4 check` does not evaluate, so it makes no request.
      it ("does not make the " <> verb <> " under l4 check") $
        expectOk bin ["check", fixture] "Check succeeded."

    -- The control: take the request out and both results print.
    it "prints both results and exits 0 for the same file without the request" $ do
      Output code sout _ <- runL4 bin ["run", fixtureDir </> "request-none.l4"]
      code `shouldBe` ExitSuccess
      let out = filter (/= '\r') sout
      evalBlock 1 out `shouldSatisfy` T.isInfixOf "Result:\n  2\n"
      evalBlock 2 out `shouldSatisfy` T.isInfixOf "Result:\n  4\n"

    it "reports ok=true and both results in JSON for the same file without the request" $ do
      env <- jsonEnvelope bin ["run", "--json", fixtureDir </> "request-none.l4"]
      objField env "ok" `shouldBe` Just (Bool True)
      case objField env "results" of
        Just (Array v) -> length v `shouldBe` 2
        other          -> expectationFailure ("Expected a results array, got " ++ show other)

    -- These fail the run too, but only for the one directive.
    forM_ [ ("a CONSIDER with no matching branch", "eval-consider-mid.l4", 14, ["reached a CONSIDER that has no branch for it"])
          , ("a division by zero",                 "eval-div0-mid.l4",     5, ["Division by zero"])
          , ("an #ASSERT whose expression raises", "assert-raises-mid.l4", 5, ["assertion could not be evaluated", "Division by zero"])
          ] \(what, file, midLine, messages) -> do
      let fixture = fixtureDir </> file

      it ("fails the run but keeps the other directives' results for " <> what) $
        expectMiddleLostInText bin fixture midLine messages

      it ("reports ok=false and all three results in JSON for " <> what) $
        expectMiddleLostInJson bin fixture messages

    -- An address that does not start with https:// is not a failed request: the
    -- evaluator reports it for that directive, and the others keep their results.
    forM_ [ ("POST", "request-post-http.l4"), ("FETCH", "request-fetch-http.l4") ] \(verb, file) -> do
      let fixture = fixtureDir </> file
          messages = ["Internal error", verb <> " only supports https"]

      it ("fails the run but keeps the other directives' results for a " <> verb <> " to an address that is not https") $
        expectMiddleLostInText bin fixture 6 messages

      it ("reports ok=false and all three results in JSON for a " <> verb <> " to an address that is not https") $
        expectMiddleLostInJson bin fixture messages

  -- `@lang en` says what a module that declares nothing already is, so
  -- `l4 check` hints that the line can go. It is a HINT: the check still
  -- succeeds, with the same exit code and the same JSON verdict it would give
  -- without the line. Without the controls below a hint that fired on every
  -- module would pass the first case, so they are the half that matters.
  describe "l4 check: a redundant @lang en" $ do
    let hintText = "A module that declares nothing is English; this line can go."

    it "hints that the line can go, at Hint severity, and the check still succeeds" $ do
      Output code sout serr <- runL4 bin ["check", langEnHintFixture]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("Check succeeded." `isInfixOf`)
      serr `shouldSatisfy` (hintText `isInfixOf`)
      serr `shouldSatisfy` ("DiagnosticSeverity_Hint" `isInfixOf`)
      -- not a warning, and not anything louder
      serr `shouldNotSatisfy` ("DiagnosticSeverity_Warning" `isInfixOf`)
      serr `shouldNotSatisfy` ("DiagnosticSeverity_Error" `isInfixOf`)

    it "points at the @lang line" $ do
      Output _ _ serr <- runL4 bin ["check", langEnHintFixture]
      -- the fixture's third line, from its first column, and it ends on that
      -- same line: the range is rendered "line:col-line:col"
      serr `shouldSatisfy` ("3:1-3:" `isInfixOf`)

    it "leaves the JSON verdict at ok=true" $ do
      env <- jsonEnvelope bin ["check", langEnHintFixture, "--json"]
      objField env "ok" `shouldBe` Just (Bool True)
      case objField env "diagnostics" of
        Just (Array v) -> [t | String t <- toList v] `shouldSatisfy` any (T.pack hintText `T.isInfixOf`)
        other -> expectationFailure ("Expected diagnostics array, got " ++ show other)

    it "says nothing to a module that declares another language" $ do
      Output code _ serr <- runL4 bin ["check", "examples/ok/nlg-module-lang.l4"]   -- `@lang he`
      code `shouldBe` ExitSuccess
      serr `shouldNotSatisfy` (hintText `isInfixOf`)

    it "says nothing to a module that declares nothing" $ do
      Output code _ serr <- runL4 bin ["check", cleanFixture]
      code `shouldBe` ExitSuccess
      serr `shouldNotSatisfy` (hintText `isInfixOf`)

    it "says nothing on an `en` line in a module that also declares `he`" $ do
      Output code _ serr <- runL4 bin ["check", langEnThenHeFixture]
      code `shouldBe` ExitSuccess
      serr `shouldNotSatisfy` (hintText `isInfixOf`)

    it "warns that the earlier of two different `@lang` lines is overridden, naming both" $ do
      Output code _ serr <- runL4 bin ["check", langEnThenHeFixture]
      code `shouldBe` ExitSuccess
      serr `shouldSatisfy`
        ("declares two different languages with @lang: `en` here and `he` on line 4." `isInfixOf`)

    it "does not warn when every `@lang` line names the same language" $ do
      Output code _ serr <- runL4 bin ["check", langEnHintFixture]
      code `shouldBe` ExitSuccess
      serr `shouldNotSatisfy` ("two different languages" `isInfixOf`)

    it "warns that a percent pair with spaces inside it is plain text, naming the slot to write" $ do
      Output code _ serr <- runL4 bin ["check", "examples/not-ok/nlg/nlg_spaced_slot.l4"]
      code `shouldBe` ExitSuccess
      serr `shouldSatisfy`
        ("This wording has `% amount %`, with spaces inside the percent signs, so it prints as plain text." `isInfixOf`)
      serr `shouldSatisfy` ("A slot is written `%amount%`, with no spaces." `isInfixOf`)

    it "warns that a language tag nothing else backs may be the first word of a sentence" $ do
      Output code _ serr <- runL4 bin ["check", "examples/not-ok/nlg/nlg_lone_tag.l4"]
      code `shouldBe` ExitSuccess
      serr `shouldSatisfy`
        ("`@nlg:the` tags the wording on `over limit` as language `the`" `isInfixOf`)
      serr `shouldSatisfy` ("write `@nlg the …` with no colon." `isInfixOf`)

    it "names the declared tag when a lone tag differs from it only in case" $ do
      Output code _ serr <- runL4 bin ["check", langTagCaseFixture]
      code `shouldBe` ExitSuccess
      serr `shouldSatisfy`
        ("the module declares `@lang fr`: `FR` and `fr` differ only in case." `isInfixOf`)
      serr `shouldSatisfy` ("Write `@nlg:fr`, or leave the tag off" `isInfixOf`)
      serr `shouldNotSatisfy` ("add `@lang" `isInfixOf`)

  describe "l4 format" $ do
    it "prints a clean file to stdout as written" $ do
      src <- readFile cleanFixture
      Output code sout _ <- runL4 bin ["format", cleanFixture]
      code `shouldBe` ExitSuccess
      -- Carriage returns are dropped on both sides: the checkout may have
      -- CRLF line endings, which 'readFile' turns into LF on Windows.
      filter (/= '\r') sout `shouldBe` filter (/= '\r') src

    -- The output has the file's own line endings, compared byte for byte. On
    -- Windows, reading the file or writing stdout in text mode would turn LF
    -- into CRLF or the other way round.
    it "keeps LF and CRLF line endings as they are in the file" $
      withSystemTempDirectory "l4-format-line-endings" \dir ->
        forM_ [("lf.l4", "\n"), ("crlf.l4", "\r\n")] \(name, eol) -> do
          let file = dir </> name
              bytes = TE.encodeUtf8 $ T.intercalate eol
                [ "GIVETH A STRING"
                , "DECIDE `the city` IS \"São Paulo\""
                , ""
                ]
          BS.writeFile file bytes
          Output code sout _ <- runL4 bin ["format", file]
          code `shouldBe` ExitSuccess
          sout `shouldBe` T.unpack (TE.decodeUtf8 bytes)

    -- A postfix call used to lose its argument, and a call written between its
    -- arguments used to be printed head first, with exit code 0 and output that
    -- no longer checked (smucclaw/l4-ide#918). Each fixture covers one of the two.
    -- Carriage returns are dropped before comparing, as the file may be checked
    -- out with CRLF line endings (Windows).
    let formatsAsWritten fixture = do
          src <- readFile fixture
          Output code sout _ <- runL4 bin ["format", fixture]
          code `shouldBe` ExitSuccess
          filter (/= '\r') sout `shouldBe` filter (/= '\r') src
          tmp <- getTemporaryDirectory
          let formatted = tmp </> ("l4-cli-test-" ++ takeFileName fixture)
          writeFile formatted sout
          Output checkCode _ _ <- runL4 bin ["check", formatted]
          removePathForcibly formatted
          checkCode `shouldBe` ExitSuccess

    it "prints a postfix mixfix call back with its argument, and the output checks" $
      formatsAsWritten (fixtureDir </> "format-mixfix-postfix.l4")

    it "prints a binary and a chained mixfix call back in source order, and the output checks" $
      formatsAsWritten (fixtureDir </> "format-mixfix-infix.l4")

    it "writes nothing to stdout and exits non-zero on a broken file" $ do
      Output code _ _ <- runL4 bin ["format", garbageFixture]
      code `shouldSatisfy` (/= ExitSuccess)

    it "reproduces multi-clause DECIDE and MEANS groups byte-for-byte" $ do
      -- The parser fuses a clause group into one definition; formatting must
      -- still print every clause as written. Carriage returns are dropped on
      -- both sides so a CRLF checkout on Windows compares equal.
      let fixture = fixtureDir </> "multi-clause-format.l4"
      src <- readFile fixture
      Output code sout _ <- runL4 bin ["format", fixture]
      code `shouldBe` ExitSuccess
      filter (/= '\r') sout `shouldBe` filter (/= '\r') src

  ----------------------------------------------------------------------------
  -- One encoding, several languages.
  --
  -- The property that matters is not just "--lang he prints Hebrew" but the
  -- pair with it: a rule that has NO rendering in the requested language falls
  -- back to its default, so a half-finished translation produces a whole
  -- document rather than one with holes in it. The fixture carries one rule
  -- with both renderings and one with only English, so a single run shows
  -- both halves.
  --
  -- Asserted at the CLI rather than only in `NlgMultiplicitySpec` because the
  -- flag is the user surface, and because `l4 render` reaches the annotation
  -- through a completely different path from `l4 nlg` — the exporter in
  -- `L4.Export.Document`, not the linearizer. Both are language-aware for the
  -- same reason (`L4.Nlg.selectLanguage` moves the chosen rendering into the
  -- slot each already reads), and that shared reason is exactly the kind that
  -- looks fine until one of the two paths is changed.
  ----------------------------------------------------------------------------
  describe "l4 --lang (one encoding, several languages)" $ do
    it "l4 nlg selects the requested language" $ do
      Output code sout _ <- runL4 bin ["nlg", "--lang", "he", bilingualFixture]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("עולה על הסף" `isInfixOf`)

    it "l4 nlg falls back for a rule with no rendering in that language" $ do
      Output code sout _ <- runL4 bin ["nlg", "--lang", "he", bilingualFixture]
      code `shouldBe` ExitSuccess
      -- `is small` is English-only; asking for Hebrew must still render it.
      sout `shouldSatisfy` ("is under the threshold" `isInfixOf`)

    it "l4 nlg with no --lang uses the default rendering" $ do
      Output code sout _ <- runL4 bin ["nlg", bilingualFixture]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("exceeds the threshold" `isInfixOf`)
      sout `shouldNotSatisfy` ("עולה על הסף" `isInfixOf`)

    -- The frame words: the ones the linearizer supplies, not the author.
    -- `--lang he` renders them from the Hebrew phrasebook, a phrase at a time;
    -- the maqaf-final "ל־" meets its value with no space; a month is a frame
    -- word too; and a word with no entry stays English and is NAMED on stderr,
    -- so the gap is visible. With no flag nothing changes.
    it "l4 nlg --lang he renders the frame words from the phrasebook" $ do
      Output code sout serr <- runL4 bin ["nlg", "--lang", "he", bilingualFramesFixture]
      code `shouldBe` ExitSuccess
      map (filter (/= '\r')) (lines sout) `shouldBe`
        [ "150 עולה על הסף שווה ל־`TRUE`"
        , "לא 5 עולה על הסף"
        , "16 ביולי 2025"
        , "150 as string"
        ]
      serr `shouldSatisfy` ("have no he rendering and stay English: as, string" `isInfixOf`)

    -- A region on the tag, or on the request, changes neither the wording
    -- picked nor the frame words: one language, one set of frame words.
    it "l4 nlg --lang he and --lang he-IL both read a he-IL wording, with Hebrew frame words" $
      forM_ ["he", "he-IL"] $ \ lang -> do
        Output code sout _ <- runL4 bin ["nlg", "--lang", lang, bilingualFramesRegionFixture]
        code `shouldBe` ExitSuccess
        map (filter (/= '\r')) (lines sout) `shouldBe`
          [ "150 עולה על הסף שווה ל־`TRUE`"
          , "לא 5 עולה על הסף"
          ]

    it "l4 nlg with no --lang keeps English frame words and reports nothing" $ do
      Output code sout serr <- runL4 bin ["nlg", bilingualFramesFixture]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("exceeds the threshold is equal to `TRUE`" `isInfixOf`)
      sout `shouldSatisfy` ("16 July 2025" `isInfixOf`)
      serr `shouldNotSatisfy` ("stay English" `isInfixOf`)

    it "l4 render reaches the same annotations, through the exporter" $ do
      Output code sout _ <- runL4 bin ["render", "--format", "text", "--lang", "he", bilingualFixture]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("עולה על הסף" `isInfixOf`)
      sout `shouldSatisfy` ("is under the threshold" `isInfixOf`)

    it "a language the file does not carry leaves the output unchanged" $ do
      -- The safety property for every existing caller: selection can only ever
      -- swap in a rendering that is actually there. `zz` is carried by nothing,
      -- so this must equal the no-flag output byte for byte.
      Output _ plain _ <- runL4 bin ["render", "--format", "text", bilingualFixture]
      Output _ asked _ <- runL4 bin ["render", "--format", "text", "--lang", "zz", bilingualFixture]
      asked `shouldBe` plain

  ----------------------------------------------------------------------------
  -- The HTML wrapper's own language (smucclaw/l4-ide#970).
  --
  -- `<html lang=...>` used to be the literal "en" whatever was rendered, so a
  -- Hebrew document arrived labelled English and with no `dir`, leaving the
  -- browser to guess direction from the characters. The label is what a screen
  -- reader picks a voice from and what `dir` hangs off, so it is not cosmetic.
  --
  -- Asserted here rather than as a golden because NO golden captures
  -- `renderHtml` at all (measured 2026-09-21: its only callers are this CLI
  -- verb and the LSP export handler), so a black-box CLI assertion is the only
  -- guard this wrapper has.
  ----------------------------------------------------------------------------
  describe "l4 render --format html (document language)" $ do
    let langModule = "examples/ok/nlg-module-lang.l4"   -- carries `@lang he`
        -- The `<html>` wrapper ALONE, not the whole document. Asserting "no
        -- `dir=` anywhere" would also forbid a per-element `dir="auto"` on a
        -- prose span, which is the natural remedy for a MIXED document and is
        -- not what any of these cases is about.
        -- (A Windows process ends the line with a carriage return; drop it.)
        htmlTag s = unwords [ filter (/= '\r') l | l <- lines s, "<html" `isPrefixOf` l ]

    it "labels a Hebrew rendering he and marks it right-to-left" $ do
      Output code sout _ <- runL4 bin ["render", "--format", "html", "--lang", "he", langModule]
      code `shouldBe` ExitSuccess
      htmlTag sout `shouldBe` "<html lang=\"he\" dir=\"rtl\">"

    it "labels the document en when English is asked for, and puts no dir on the wrapper" $ do
      -- NOT "an English rendering", which is what this case used to be called:
      -- the fixture's own comment says `is small` has no English herald, so
      -- asking for English still renders that clause in Hebrew. The document is
      -- MIXED and the label follows the REQUEST — ruled 2026-09-21 and written
      -- up on doc/tutorials/natural-language-functions/optimising-natural-language-generation.md.
      Output code sout _ <- runL4 bin ["render", "--format", "html", "--lang", "en", langModule]
      code `shouldBe` ExitSuccess
      -- The absence of `dir` is half the assertion: `ltr` is the HTML default,
      -- so the attribute appearing at all is what means "this runs the other way".
      htmlTag sout `shouldBe` "<html lang=\"en\">"
      -- … and this is the mixture the label is being honest about.
      sout `shouldSatisfy` ("קטן מן הסף" `isInfixOf`)

    it "falls back to the module's own @lang when no --lang is given" $ do
      Output code sout _ <- runL4 bin ["render", "--format", "html", langModule]
      code `shouldBe` ExitSuccess
      htmlTag sout `shouldBe` "<html lang=\"he\" dir=\"rtl\">"

    it "falls back to en for a module that declares no language" $ do
      -- bilingual.l4 tags its heralds individually and declares no `@lang`.
      Output code sout _ <- runL4 bin ["render", "--format", "html", bilingualFixture]
      code `shouldBe` ExitSuccess
      htmlTag sout `shouldBe` "<html lang=\"en\">"

    ------------------------------------------------------------------------
    -- A label the document cannot support.
    --
    -- `--lang he` on an all-English encoding used to emit
    -- `<html lang="he" dir="rtl">`: not merely a wrong label but a layout
    -- instruction, which moves an English full stop to the left end of its
    -- line. Measured with fribidi on regcf.l4, which has 0 Hebrew codepoints.
    -- Ruled 2026-09-21: when NOTHING in the module renders in the asked-for
    -- language, the document keeps the language it declares and stderr says so.
    ------------------------------------------------------------------------
    it "does not relabel a document for a language nothing in it renders" $ do
      -- clean.l4 carries no @nlg at all and declares no @lang.
      Output code sout serr <- runL4 bin ["render", "--format", "html", "--lang", "he", cleanFixture]
      code `shouldBe` ExitSuccess
      htmlTag sout `shouldBe` "<html lang=\"en\">"
      serr `shouldSatisfy` ("no renderings in \"he\"" `isInfixOf`)
      serr `shouldSatisfy` ("labelled \"en\"" `isInfixOf`)

    it "keeps the module's declared language when the asked-for one is carried by nothing" $ do
      Output code sout serr <- runL4 bin ["render", "--format", "html", "--lang", "zz", langModule]
      code `shouldBe` ExitSuccess
      htmlTag sout `shouldBe` "<html lang=\"he\" dir=\"rtl\">"
      serr `shouldSatisfy` ("no renderings in \"zz\"" `isInfixOf`)

    it "says nothing on stderr for a format that does not label its language" $ do
      -- `text`, `json` and `plan` carry the chosen WORDINGS and say nothing
      -- about which language they are, so the note would be noise — and this
      -- keeps `--format text --lang zz` byte-identical on both streams.
      Output code _ serr <- runL4 bin ["render", "--format", "text", "--lang", "zz", langModule]
      code `shouldBe` ExitSuccess
      serr `shouldNotSatisfy` ("no renderings" `isInfixOf`)

    ------------------------------------------------------------------------
    -- The flag's own hygiene. Before this, `--lang` was echoed verbatim into
    -- the attribute: `--lang 'he '` labelled the document `he ` AND silently
    -- lost `dir="rtl"`, because the direction lookup compared `"he "` against
    -- the table and missed. Exit 0, no diagnostic — a trailing space out of a
    -- shell variable is how it arrives.
    ------------------------------------------------------------------------
    it "trims a --lang value, so a trailing space does not cost the direction" $ do
      Output code sout _ <- runL4 bin ["render", "--format", "html", "--lang", "he ", langModule]
      code `shouldBe` ExitSuccess
      htmlTag sout `shouldBe` "<html lang=\"he\" dir=\"rtl\">"

    it "lowercases the primary subtag, which also makes --lang HE select the Hebrew heralds" $ do
      Output code sout _ <- runL4 bin ["render", "--format", "html", "--lang", "HE", langModule]
      code `shouldBe` ExitSuccess
      htmlTag sout `shouldBe` "<html lang=\"he\" dir=\"rtl\">"
      sout `shouldSatisfy` ("עולה על הסף" `isInfixOf`)

    it "labels the document with a region its Hebrew answers" $ do
      -- The module's wordings are `he`, and a request for `he-IL` reads them
      -- (`L4.Lexer.langMatchRank`), so the document is honestly `he-IL`, as
      -- typed, and nothing is reported.
      Output code sout serr <- runL4 bin ["render", "--format", "html", "--lang", "he-IL", langModule]
      code `shouldBe` ExitSuccess
      htmlTag sout `shouldBe` "<html lang=\"he-IL\" dir=\"rtl\">"
      serr `shouldNotSatisfy` ("no renderings" `isInfixOf`)

    it "passes a region subtag through unmangled, and falls back because nothing carries it" $ do
      -- Two things at once, and the name says both because the label alone would
      -- mislead: the reader keeps `fr-CA` as typed (the stderr note quotes it
      -- back verbatim), and the LABEL is still the module's `he`, because no
      -- wording in the module is in French.
      Output code sout serr <- runL4 bin ["render", "--format", "html", "--lang", "fr-CA", langModule]
      code `shouldBe` ExitSuccess
      htmlTag sout `shouldBe` "<html lang=\"he\" dir=\"rtl\">"
      serr `shouldSatisfy` ("no renderings in \"fr-CA\"" `isInfixOf`)

    it "rejects an empty or malformed --lang instead of putting it in the markup" $ do
      -- `he-`, `he--IL` and the over-long subtag are the SHAPE cases: every
      -- character is legal and the tag is still not one, so a character-class
      -- check alone would have let them into the attribute.
      forM_ ["", "  ", "-he", "he-", "he--IL", "abcdefghij", "he_IL", "en\"><script>"] \bad -> do
        Output code _ serr <- runL4 bin ["render", "--format", "html", "--lang", bad, langModule]
        code `shouldNotBe` ExitSuccess
        serr `shouldSatisfy` ("Invalid --lang value" `isInfixOf`)

  ----------------------------------------------------------------------------
  -- The AKN document's own language.
  --
  -- Akoma Ntoso identifies an EXPRESSION by `/akn/doc/main/<lang>@<version>`,
  -- where `<lang>` is an ISO 639-2 code. That literal was `eng` whatever was
  -- rendered, so a Hebrew act was identified as an English expression — the same
  -- defect as `<html lang="en">` (smucclaw/l4-ide#970), in the neighbouring
  -- writer, and equally silent: the XML is well formed either way.
  ----------------------------------------------------------------------------
  describe "l4 render --format akn (expression language)" $ do
    let langModule = "examples/ok/nlg-module-lang.l4"   -- carries `@lang he`
        frbrOf s = unwords [ l | l <- lines s, "FRBRExpression" `isInfixOf` l ]

    it "identifies a Hebrew expression as heb, from the module's own @lang" $ do
      Output code sout _ <- runL4 bin ["render", "--format", "akn", langModule]
      code `shouldBe` ExitSuccess
      frbrOf sout `shouldSatisfy` ("/akn/doc/main/heb@" `isInfixOf`)
      frbrOf sout `shouldNotSatisfy` ("/akn/doc/main/eng@" `isInfixOf`)

    it "follows --lang, translating the subtag to the ISO 639-2 code" $ do
      Output _ he _ <- runL4 bin ["render", "--format", "akn", "--lang", "he", langModule]
      Output _ en _ <- runL4 bin ["render", "--format", "akn", "--lang", "en", langModule]
      frbrOf he `shouldSatisfy` ("/akn/doc/main/heb@" `isInfixOf`)
      frbrOf en `shouldSatisfy` ("/akn/doc/main/eng@" `isInfixOf`)

    it "says eng for a module that declares nothing" $ do
      Output code sout _ <- runL4 bin ["render", "--format", "akn", bilingualFixture]
      code `shouldBe` ExitSuccess
      frbrOf sout `shouldSatisfy` ("/akn/doc/main/eng@" `isInfixOf`)

    it "puts the same language in the Manifestation URIs" $ do
      Output _ sout _ <- runL4 bin ["render", "--format", "akn", langModule]
      sout `shouldSatisfy` ("/akn/doc/main/heb@.xml" `isInfixOf`)
      sout `shouldNotSatisfy` ("eng@" `isInfixOf`)

  describe "l4 ast" $ do
    it "dumps a parsed AST for a clean file" $ do
      Output code sout _ <- runL4 bin ["ast", cleanFixture]
      code `shouldBe` ExitSuccess
      -- The dumper uses pretty-simple; any module will start with "MkModule".
      sout `shouldSatisfy` ("MkModule" `isInfixOf`)

  -- `l4 batch` and the REPL re-print the module and run the printed text. A
  -- CONSIDER's arms were printed comma-separated on one hanging indent, so in a
  -- CONSIDER inside an arm of another, the outer's later arms were read as more
  -- arms of the inner one, and an arm that ended in a comma list took the comma
  -- after it for another element. The expected answers are what `l4 run` gives
  -- on the fixture's own #EVALs, which the first test of each group pins.
  --
  -- Everything this needs is local to the block, so that it shares no line with
  -- the rest of the file: the fixtures are named here, and an answer is a
  -- `Value`, with a string standing for an exception or for text that is none
  -- of TRUE, FALSE, a number or a LIST of numbers.
  describe "a CONSIDER whose arms are printed back" $ do
    mRepl <- runIO $ do
      fromEnv <- lookupEnv "L4_REPL_BIN"
      case fromEnv of
        Just p  -> do ok <- doesFileExist p
                      pure (if ok then Just p else Nothing)
        Nothing -> do
          (code, out, _) <- readCreateProcessWithExitCode (proc "cabal" ["list-bin", "exe:jl4-repl"]) ""
          let path = takeWhile (`notElem` ("\r\n" :: String)) out
          ok <- doesFileExist path
          pure (if code == ExitSuccess && ok then Just path else Nothing)
    let noBranch = String "<a CONSIDER with no branch for its value>"
        one n    = Number n
        -- the answer a block of output spells
        answerOf :: T.Text -> Value
        answerOf t
          | Just rest <- T.stripPrefix "LIST " t
          , let elems = T.splitOn ", " rest
          , all (\e -> not (T.null e) && T.all isDigit e) elems
          = toJSON (map (read . T.unpack) elems :: [Integer])
          | t == "TRUE"  = Bool True
          | t == "FALSE" = Bool False
          | not (T.null t), T.all isDigit t = Number (fromInteger (read (T.unpack t)))
          | "has no branch" `T.isInfixOf` t = noBranch
          | otherwise = String ("<" <> t <> ">")
        -- what `l4 run` gives for each #EVAL of a file, in order
        runAnswers file = do
          Output _ sout _ <- runL4 bin ["run", file]
          let blocks = drop 1 (T.splitOn "Evaluation[" (T.pack (filter (/= '\r') sout)))
              result b = T.strip (fst (T.breakOn "Trace:" (T.drop (T.length "Result:") (snd (T.breakOn "Result:" b)))))
          pure (map (answerOf . result) blocks)
        -- what each row of `l4 batch` gives. A row that raises is `"status":"error"`
        -- with its message in the result, and it stops the batch unless `-c` says to
        -- go on; so a file with a raising row is run with `-c`, and every row is read.
        batchAnswers file inputs entry = do
          Output _ sout _ <- runL4 bin ["batch", "-c", file, "-i", inputs, "-e", entry]
          let result row = case objField row "output" of
                Just (Array outs) | (o : _) <- foldr (:) [] outs -> objField o "result"
                _ -> Nothing
              rowAnswer row = case (objField row "status", result row) of
                (_, Just (Object o))
                  | Just (String e) <- KeyMap.lookup (Key.fromString "error") o -> answerOf e
                (Just (String "success"), Just v) -> v
                _ -> String ("<" <> T.pack (take 300 (show (objField row "diagnostics"))) <> ">")
          pure [ rowAnswer row | l <- map (filter (/= '\r')) (lines sout)
                               , Right row <- [eitherDecode (BSL8.pack l)] ]
        -- what the REPL gives to each query, loading the file first. It runs in a
        -- directory of its own, because it keeps a history file in the one it is in.
        replAnswers repl file queries = withSystemTempDirectory "l4-repl-consider-arms" \work -> do
          absFile <- makeAbsolute file
          (Just hin, Just hout, Just herr, ph) <- createProcess (proc repl [absFile])
            { std_in = CreatePipe, std_out = CreatePipe, std_err = CreatePipe, cwd = Just work }
          hPutStr hin (unlines (queries <> [":quit"]))
          hClose hin
          hSetBinaryMode hout True
          hSetBinaryMode herr True
          soutBytes <- BS.hGetContents hout
          _ <- BS.hGetContents herr
          _ <- waitForProcess ph
          -- the banner, then one reply after each prompt, then the last prompt's goodbye
          let out = T.pack (filter (/= '\r') (T.unpack (TE.decodeUtf8Lenient soutBytes)))
          pure (map (answerOf . T.strip) (take (length queries) (drop 1 (T.splitOn "jl4> " out))))
        inRepl file queries expected = case mRepl of
          Nothing   -> pendingWith "jl4-repl was not found: set L4_REPL_BIN, or build it with `cabal build jl4-repl`"
          Just repl -> replAnswers repl file queries `shouldReturn` expected

        types    = fixtureDir </> "batch-nested-consider-types.l4"
        silent   = fixtureDir </> "batch-nested-consider-silent.l4"
        listArms = fixtureDir </> "batch-consider-list-arms.l4"
        rows f   = fixtureDir </> ("batch-" ++ f ++ ".json")

        typesWant  = [one 1, one 2, one 3, one 4]
        -- Red Red, Red Blue (no arm for Blue in the inner one), Green, Blue
        silentWant = [Bool True, noBranch, Bool False, Bool True]
        listsWant  = [toJSON [1, 2 :: Integer], toJSON [3 :: Integer], toJSON [4, 5 :: Integer]]

        -- a WHERE under an arm; the three files differ in which arm holds it
        whereFile n = fixtureDir </> ("batch-consider-where-" ++ n ++ ".l4")
        whereRows n = rows ("consider-where-" ++ n)
        whereWant   = [one 0, one 20, one 50]
        whereQueries = [ "`late fee` 1000 0", "`late fee` 1000 10", "`late fee` 1000 45" ]
        whereArms   = ["first", "middle", "last"]

    -- the inner CONSIDER is on another type, so the outer's later arms did not
    -- type-check as its arms and every row was an error
    it "is read by l4 run as the rule says" $ do
      runAnswers types  `shouldReturn` typesWant
      runAnswers silent `shouldReturn` (silentWant <> [one 4])
      runAnswers listArms `shouldReturn` listsWant

    it "is read as written by l4 batch, when the inner one is on another type" $
      batchAnswers types (rows "nested-consider-types") "inner on another type" `shouldReturn` typesWant

    -- the inner CONSIDER is on the same type, so they did type-check, and the
    -- printed rule answered differently with no diagnostic
    it "is read as written by l4 batch, when the inner one is on the same type" $
      batchAnswers silent (rows "nested-consider-silent") "inner on the same type" `shouldReturn` silentWant

    -- the control: an inner CONSIDER that is the last arm was always printed right
    it "is read as written by l4 batch, when it is the last arm" $
      batchAnswers silent (rows "nested-consider-last") "inner last" `shouldReturn` [one 4]

    -- no nesting at all: the comma after an arm was read as the next element of
    -- the LIST the arm ended in
    it "is read as written by l4 batch, when an arm ends in a comma list" $
      batchAnswers listArms (rows "consider-list-arms") "list arms" `shouldReturn` listsWant

    it "is read as written by the REPL, when the inner one is on another type" $
      inRepl types
        [ "`inner on another type` 0 1", "`inner on another type` 0 9"
        , "`inner on another type` 1 1", "`inner on another type` 2 9" ]
        typesWant

    it "is read as written by the REPL, when the inner one is on the same type" $
      inRepl silent
        [ "`inner on the same type` 0 0", "`inner on the same type` 0 2"
        , "`inner on the same type` 1 0", "`inner on the same type` 2 0" ]
        silentWant

    it "is read as written by the REPL, when an arm ends in a comma list" $
      inRepl listArms [ "`list arms` 0", "`list arms` 1", "`list arms` 2" ] listsWant

    -- a WHERE under an arm: its line stood at the column of the arm's WHEN, which
    -- ends the definition, so any arm after it did not parse and every row failed.
    -- The last arm has none after it, and was always printed right.
    it "is read by l4 run as the rule says, with a WHERE under an arm" $
      forM_ whereArms \n -> runAnswers (whereFile n) `shouldReturn` whereWant

    forM_ whereArms \n -> do
      it ("is read as written by l4 batch, with a WHERE under the " ++ n ++ " arm") $
        batchAnswers (whereFile n) (whereRows n) "late fee" `shouldReturn` whereWant

      it ("is read as written by the REPL, with a WHERE under the " ++ n ++ " arm") $
        inRepl (whereFile n) whereQueries whereWant

  describe "l4 trace" $ do
    it "refuses --format png without --output-dir" $ do
      Output code _ serr <- runL4 bin ["trace", cleanFixture, "--format", "png"]
      code `shouldSatisfy` (/= ExitSuccess)
      serr `shouldSatisfy` ("requires --output-dir" `isInfixOf`)

    it "refuses --format svg without --output-dir" $ do
      Output code _ serr <- runL4 bin ["trace", cleanFixture, "--format", "svg"]
      code `shouldSatisfy` (/= ExitSuccess)
      serr `shouldSatisfy` ("requires --output-dir" `isInfixOf`)

    it "defaults to DOT on stdout (redirect with >)" $ do
      -- trace on the eval fixture shouldn't error even without #EVALTRACE —
      -- it just produces no output but still exits 0.
      Output code _ _ <- runL4 bin ["trace", evalFixture]
      code `shouldBe` ExitSuccess

  describe "l4 state-graph" $ do
    it "fails on a file without regulative rules" $ do
      Output code _ serr <- runL4 bin ["state-graph", cleanFixture]
      code `shouldSatisfy` (/= ExitSuccess)
      serr `shouldSatisfy` ("regulative" `isInfixOf`)

  -- `l4 nlg` must reproduce what jl4-test writes into a committed
  -- `.nlg.golden`, byte for byte: that equality is what lets anyone regenerate
  -- a golden without running the whole golden suite.
  describe "l4 nlg" $ do
    it "linearizes a clean module and exits 0" $ do
      Output code sout _ <- runL4 bin ["nlg", cleanFixture]
      code `shouldBe` ExitSuccess
      -- clean.l4 has no directives, so the payload is empty. That is the
      -- correct answer and not a failure: `nlg` linearizes DIRECTIVES.
      sout `shouldBe` ""

    it "refuses to emit prose for a module that does not typecheck" $
      expectFail bin ["nlg", errorFixture]

    it "reproduces the committed promissory-note NLG golden byte for byte" $
      expectNlgGolden bin nlgPromissorySource nlgPromissoryGolden

    it "reproduces the committed directive-showcase NLG golden byte for byte" $
      expectNlgGolden bin nlgShowcaseSource nlgShowcaseGolden

  -- An @nlg on a rule head's INPUT, which is the one placement the two
  -- projections used to disagree about (smucclaw/l4-ide#972). `l4 render` read it
  -- as the rule's sentence and `l4 nlg` as the input's gloss, so a positional
  -- call printed the rule's bare name. These assert the AGREEMENT, from both
  -- sides, because only one side has a golden: the `.nlg.golden` beside the
  -- fixture pins the `l4 nlg` column and nothing anywhere pins `l4 render`'s.
  --
  -- Rows 5, 7, 8 and 12 of the fixture are the repaired ones; row 13 and the
  -- `AKA` rows are the controls, and they are the assertions that fail if the
  -- repair is widened into an unconditional promotion.
  describe "an @nlg on a rule head's input" $ do
    -- Windows ends a process's lines with a carriage return, which would sit
    -- between a needle and the line break it expects; drop it on the way in.
    let lf (Output c o e) = Output c (filter (/= '\r') o) e
        nlgOf   = lf <$> runL4 bin ["nlg", nlgHeadPlacementSource]
        renderOf = lf <$> runL4 bin ["render", "--format", "text", nlgHeadPlacementSource]

    it "reaches l4 nlg at a POSITIONAL call site, whichever side of the input it sits" $ do
      Output code sout _ <- nlgOf
      code `shouldBe` ExitSuccess
      -- Trailing the head (row 5), under the input (row 7), the DECIDE spelling
      -- (row 8) and the two-input case (row 12). The argument sits in the
      -- sentence's slot — a heralded call in a directive reads as its sentence
      -- (`L4.Nlg.substituteNlgDirective`) — so these pin the sentence as the
      -- whole line, with nothing appended.
      sout `shouldSatisfy` endsLine "row five saw 200"
      sout `shouldSatisfy` endsLine "row seven saw 200"
      sout `shouldSatisfy` endsLine "row eight saw 200"
      sout `shouldSatisfy` endsLine "row twelve saw 200 over 100"

    it "reaches l4 nlg at a NAMED-argument call site without printing twice" $ do
      Output _ sout _ <- nlgOf
      -- The sentence MOVES rather than being copied: leaving it on the input as
      -- well printed it once as the heading and again as the input's gloss.
      sout `shouldSatisfy` ("row five saw `amount` where `amount` is 200" `isInfixOf`)
      sout `shouldSatisfy` ("row seven saw `amount` where `amount` is 200" `isInfixOf`)

    it "renders the same sentences through l4 render, which is the point" $ do
      Output code sout _ <- renderOf
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("row five saw amount" `isInfixOf`)
      sout `shouldSatisfy` ("row seven saw amount" `isInfixOf`)
      sout `shouldSatisfy` ("row eight saw amount" `isInfixOf`)
      sout `shouldSatisfy` ("row twelve saw amount over floor" `isInfixOf`)

    it "reads the placements that already worked the same way, argument in the slot" $ do
      Output _ sout _ <- nlgOf
      sout `shouldSatisfy` endsLine "row one saw 200"
      sout `shouldSatisfy` endsLine "row three saw 200"
      sout `shouldSatisfy` endsLine "row four saw 200"
      sout `shouldSatisfy` endsLine "row six saw 200"
      sout `shouldSatisfy` endsLine "row nine saw 200"

    it "keeps a rule's OWN sentence when it also heralds itself (row 13)" $ do
      Output _ sout _ <- nlgOf
      -- The rule's own annotation is found first, so nothing is moved and the
      -- inner herald stays the input's gloss. An unconditional promotion would
      -- overwrite the outer one with the inner.
      sout `shouldSatisfy` endsLine "row thirteen the rule saw 200"
      sout `shouldSatisfy` ("row thirteen the input" `isInfixOf`)

    it "reads a herald on an AKA head as the rule's sentence at every call shape (#978)" $ do
      Output _ nlgOut _ <- nlgOf
      Output _ renOut _ <- renderOf
      -- Row 10: the herald lands on the AKA's NAME. `L4.Nlg.decideNlg` searches
      -- that position, so `l4 render` finds it and `l4 nlg` fills its slot;
      -- before, render lost it and nlg printed "row ten saw `amount` with 200".
      -- A call through the alias reads the same.
      nlgOut `shouldNotSatisfy` ("row ten saw `amount` with 200" `isInfixOf`)
      nlgOut `shouldSatisfy` (unlines ["row ten saw 200", "row ten saw `amount` where `amount` is 200", "row ten saw 200"] `isInfixOf`)
      renOut `shouldSatisfy` ("row ten saw amount" `isInfixOf`)
      -- Row 11: the herald above the head lands on the declaration. A `WITH`
      -- call used to print the bare name, "`row eleven` where ...".
      nlgOut `shouldSatisfy` endsLine "row eleven saw 200"
      nlgOut `shouldSatisfy` ("row eleven saw `amount` where `amount` is 200" `isInfixOf`)
      nlgOut `shouldNotSatisfy` ("`row eleven` where" `isInfixOf`)
      renOut `shouldSatisfy` ("row eleven saw amount" `isInfixOf`)

    it "heads a WITH call with the herald without re-expanding an input's gloss (row 13)" $ do
      Output _ nlgOut _ <- nlgOf
      nlgOut `shouldSatisfy` ("row thirteen the rule saw `amount` where row thirteen the input is 200" `isInfixOf`)

    it "reads a GIVEN gloss as the input's label, never as the rule's sentence (row 14)" $ do
      Output _ nlgOut _ <- nlgOf
      Output _ renOut _ <- renderOf
      -- The head names no input, so the type checker hoists the GIVEN name
      -- into it; the gloss must not be taken for the rule's herald on that
      -- account (smucclaw/l4-ide#977). Positional: the bare name. WITH: the
      -- gloss labels the input. Render: the rule's own body.
      nlgOut `shouldSatisfy` endsLine "`row fourteen` with 200"
      nlgOut `shouldSatisfy` ("`row fourteen` where the sum of money is 200" `isInfixOf`)
      nlgOut `shouldNotSatisfy` ("the sum of money with 200" `isInfixOf`)
      renOut `shouldNotSatisfy` ("holds if the sum of money" `isInfixOf`)
      renOut `shouldSatisfy` ("Row fourteen holds if amount is more than 100" `isInfixOf`)

    it "reads an own-line gloss under a GIVEN list's LAST input as that input's (rows 15, 16)" $ do
      Output _ nlgOut _ <- nlgOf
      Output _ renOut _ <- renderOf
      -- Ruled 2026-10-02: indented past the GIVEN keyword, it describes the
      -- input above it, with a GIVETH next (row 15) or without (row 16).
      -- Before, row 15's was dropped and row 16's became the rule's sentence.
      nlgOut `shouldSatisfy` ("`row fifteen` where `floor` is 100 and the sum of money is 200" `isInfixOf`)
      nlgOut `shouldSatisfy` (joinLines ["`row sixteen` with 200", "`row sixteen` where the sum of money is 200"] `isInfixOf`)
      -- Render describes each rule by its own body.
      renOut `shouldSatisfy` ("Row fifteen holds if amount is more than floor" `isInfixOf`)
      renOut `shouldSatisfy` ("Row sixteen means amount is more than 100" `isInfixOf`)
      renOut `shouldNotSatisfy` ("means the sum of money" `isInfixOf`)

    it "still reads one at the GIVEN keyword's column as the rule's sentence (row 17)" $ do
      Output _ nlgOut _ <- nlgOf
      Output _ renOut _ <- renderOf
      nlgOut `shouldSatisfy` endsLine "row seventeen saw 200"
      renOut `shouldSatisfy` ("Row seventeen means row seventeen saw amount" `isInfixOf`)

  describe "l4 batch" $ do
    it "streams one NDJSON row per input (default format)" $ do
      Output code sout _ <- runL4 bin ["batch", batchEligFixture, "--inputs", batchDataJson]
      code `shouldBe` ExitSuccess
      nonBlankLines sout `shouldBe` 2
      sout `shouldSatisfy` ("\"status\":\"success\"" `isInfixOf`)

    it "reads a CSV cell for a NUMBER or BOOLEAN input as the number or boolean it spells" $ do
      -- If age/income stayed strings, JSONDECODE into NUMBER would fail and
      -- the rows would come back status=error; success proves the declared
      -- types were applied. (Every column here is declared, so this does not
      -- reach 'inferCsvCell'; the undeclared-column test below does.)
      Output code sout _ <-
        runL4 bin ["batch", batchEligFixture, "--inputs", batchDataCsv, "--format", "json"]
      code `shouldBe` ExitSuccess
      rows <- decodeArray sout
      length rows `shouldBe` 2
      let statuses = [ s | Object o <- rows
                         , Just (String s) <- [KeyMap.lookup (Key.fromString "status") o] ]
      statuses `shouldBe` ["success", "success"]

    it "reads a cases file that holds one object as one case" $ do
      -- Plain main answered a JSON object where it expected an array with
      -- "failed to parse inputs: ... expected Array, but encountered Object".
      Output code sout _ <- runL4 bin ["batch", batchEligFixture, "--inputs", batchSingleObjectJson]
      code `shouldBe` ExitSuccess
      nonBlankLines sout `shouldBe` 1
      sout `shouldSatisfy` ("\"status\":\"success\"" `isInfixOf`)

    it "emits a single JSON array with --format json" $ do
      Output code sout _ <-
        runL4 bin ["batch", batchEligFixture, "--inputs", batchDataJson, "--format", "json"]
      code `shouldBe` ExitSuccess
      rows <- decodeArray sout
      length rows `shouldBe` 2

    it "emits a CSV table with flattened input_* columns via --format csv" $ do
      Output code sout _ <-
        runL4 bin ["batch", batchEligFixture, "--inputs", batchDataJson, "--format", "csv"]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("input_age" `isInfixOf`)
      sout `shouldSatisfy` ("status" `isInfixOf`)

    it "writes results to a file with --output" $ do
      tmp <- getTemporaryDirectory
      let outFile = tmp </> "l4-batch-out.json"
      Output code sout _ <-
        runL4 bin [ "batch", batchEligFixture, "--inputs", batchDataJson
                  , "--format", "json", "--output", outFile ]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` null                    -- nothing on stdout
      exists <- doesFileExist outFile
      exists `shouldBe` True
      contents <- readFile outFile
      rows <- decodeArray contents
      length rows `shouldBe` 2
      removeFile outFile

    it "stops at the first failing row by default (and exits non-zero)" $ do
      -- Row 2 has a non-numeric income; row 3 must NOT be processed.
      Output code sout _ <- runL4 bin ["batch", batchEligFixture, "--inputs", batchMixedJson]
      code `shouldSatisfy` (/= ExitSuccess)
      nonBlankLines sout `shouldBe` 2
      sout `shouldSatisfy` ("\"status\":\"error\"" `isInfixOf`)

    it "processes every row with --continue-on-error (still exits non-zero)" $ do
      Output code sout _ <-
        runL4 bin ["batch", batchEligFixture, "--inputs", batchMixedJson, "--continue-on-error"]
      code `shouldSatisfy` (/= ExitSuccess)
      nonBlankLines sout `shouldBe` 3

    it "validate-only reports schema mismatches without evaluating" $ do
      Output code sout _ <-
        runL4 bin [ "batch", batchEligFixture, "--inputs", batchMixedJson
                  , "--validate-only", "--continue-on-error" ]
      code `shouldSatisfy` (/= ExitSuccess)
      sout `shouldSatisfy` ("\"status\":\"invalid\"" `isInfixOf`)
      sout `shouldSatisfy` ("Type mismatch" `isInfixOf`)

    it "keeps an exponent-form CSV cell (1E5) for a STRING input as written, not a number" $ do
      -- A product/lot code like 1E5 is a valid JSON number (1e5 = 100000),
      -- but must survive as the string "1E5" against a STRING param rather
      -- than being coerced to 100000. (A STRING input is read by its declared
      -- type, so this does not reach 'inferCsvCell' either.)
      Output code sout _ <-
        runL4 bin ["batch", batchCodeFixture, "--inputs", batchExponentCsv]
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("\"code\":\"1E5\"" `isInfixOf`)
      sout `shouldSatisfy` (not . ("100000" `isInfixOf`))

    -- The one place a CSV cell is still typed by how it looks ('inferCsvCell'):
    -- a column that no input declares, which the case echoes under `input`.
    -- The columns are `lot`, `flag` and `serial`; batchEligFixture declares
    -- none of them. The exponent form must stay text here too, because JSON's
    -- number grammar would otherwise turn the lot code 1E5 into 100000.
    it "types a CSV cell by how it looks when no input declares its column, and keeps 1E5 text" $ do
      Output code sout _ <-
        runL4 bin ["batch", batchEligFixture, "--inputs", batchUndeclaredColumnCsv, "--format", "json"]
      code `shouldBe` ExitSuccess
      rows <- decodeArray sout
      let cell k r = objField r "input" >>= (`objField` k)
      map (cell "lot")    rows `shouldBe` [Just (String "1E5"), Just (Number 123456)]
      map (cell "flag")   rows `shouldBe` [Just (Bool True), Just (Bool False)]
      -- 007 is not a JSON number, and a date is text
      map (cell "serial") rows `shouldBe` [Just (String "007"), Just (String "2026-10-13")]

    -- T3c (ruled, specs/todo/TYPICALLY-ONE-BEHAVIOUR-SPEC.md on unstable): a
    -- blank CSV cell is ABSENT, exactly like a column missing from the file, for
    -- every kind of input. Plain main answered an empty STRING cell with "" and
    -- a blank MAYBE STRING cell with JUST "", and an empty NUMBER cell with a
    -- decode error under status "success".
    describe "a blank CSV cell is absent, not null and not an empty string" $ do
      let blankRows args = do
            Output code sout _ <- runL4 bin (["batch"] <> args <> ["--continue-on-error"])
            pure ( code
                 , [ row | l <- map (filter (/= '\r')) (lines sout)
                         , Right row <- [eitherDecode (BSL8.pack l) :: Either String Value] ] )
          diagnosticsOf row = show (objField row "diagnostics")
          resultOfRow row = case objField row "output" of
            Just (Array outs) | (o : _) <- foldr (:) [] outs -> objField o "result"
            _ -> Nothing

      it "makes a required STRING input missing, and a MAYBE STRING input NOTHING" $ do
        (code, rows) <- blankRows [batchBlankFixture, "--inputs", batchBlankCsv]
        code `shouldSatisfy` (/= ExitSuccess)
        map (`objField` "status") rows
          `shouldBe` map (Just . String) ["error", "error", "success", "success", "success"]
        case rows of
          [empty, spaces, noNote, blankNote, note] -> do
            diagnosticsOf empty  `shouldSatisfy` ("Missing required field 'code'" `isInfixOf`)
            diagnosticsOf spaces `shouldSatisfy` ("Missing required field 'code'" `isInfixOf`)
            resultOfRow noNote    `shouldBe` Just (String "nothing")
            resultOfRow blankNote `shouldBe` Just (String "nothing")
            resultOfRow note      `shouldBe` Just (String "hello")
            -- the case as read leaves the blank cell out
            (objField noNote "input" >>= (`objField` "note")) `shouldBe` Nothing
            (objField empty "input" >>= (`objField` "code")) `shouldBe` Nothing
          other -> expectationFailure ("expected 5 rows, got " ++ show (length other))

      it "makes a required NUMBER input missing too" $ do
        (code, rows) <- blankRows [batchEligFixture, "--inputs", batchBlankIncomeCsv]
        code `shouldSatisfy` (/= ExitSuccess)
        map (`objField` "status") rows `shouldBe` map (Just . String) ["error", "error", "success"]
        map diagnosticsOf (take 2 rows) `shouldSatisfy` all ("Missing required field 'income'" `isInfixOf`)

      it "is reported by --validate-only as a missing field" $ do
        Output code sout _ <-
          runL4 bin ["batch", batchEligFixture, "--inputs", batchBlankIncomeCsv, "--validate-only", "--continue-on-error"]
        code `shouldSatisfy` (/= ExitSuccess)
        length (filter ("Missing required field: 'income'" `isInfixOf`) (lines sout)) `shouldBe` 2

    -- Ruled 2026-10-12: a blank CSV cell (empty, spaces only, or a quoted "")
    -- is absent, and `l4 batch` reads a CSV file with the reader that unstable
    -- has, not cassava's `decodeByName`, which drops every record that parses
    -- to one empty field. These are the shapes where the two readers differ.
    -- Each of the first four fails on the `decodeByName` reader.
    describe "the CSV reader" $ do
      let csvRowsOf args = do
            Output code sout _ <- runL4 bin (["batch"] <> args <> ["--continue-on-error"])
            pure ( code
                 , sout
                 , [ row | l <- map (filter (/= '\r')) (lines sout)
                         , Right row <- [eitherDecode (BSL8.pack l) :: Either String Value] ] )
          statusesOf = map (`objField` "status")
          diagnosticsOf row = show (objField row "diagnostics")
          inputOf row k = objField row "input" >>= (`objField` k)

      -- A line holding only `""` and a blank line both parse to one empty
      -- field, and `decodeByName` drops both: three rows in, two rows out, exit
      -- 0. The `""` row is a row whose one cell is empty, so absent (T3c), and
      -- the required input is missing.
      it "reads a one-column row whose only cell is \"\" as a row, with its input missing" $ do
        (code, _, rows) <- csvRowsOf [batchOneColFixture, "--inputs", batchOneColCsv]
        code `shouldSatisfy` (/= ExitSuccess)
        statusesOf rows `shouldBe` map (Just . String) ["success", "error", "success"]
        map (`inputOf` "name") rows `shouldBe` [Just (String "alice"), Nothing, Just (String "bob")]
        diagnosticsOf (rows !! 1) `shouldSatisfy` ("Missing required field 'name'" `isInfixOf`)

      -- An unquoted line of spaces is not a row, any more than a blank line is;
      -- `decodeByName` made it a row of one blank cell, so an error. Ruled by
      -- Meng on 2026-10-13 (legalese/l4-ide#653): to give an empty value in a
      -- one-column file, write `""`, which is a row whose cell is absent (the
      -- case above).
      it "does not read a line of spaces, or a blank line, as a row" $ do
        (code, _, rows) <- csvRowsOf [batchOneColFixture, "--inputs", batchOneColSpacesCsv]
        code `shouldBe` ExitSuccess
        statusesOf rows `shouldBe` map (Just . String) ["success", "success"]
        map (`inputOf` "name") rows `shouldBe` [Just (String "alice"), Just (String "bob")]

      -- Excel's "CSV UTF-8" export starts with a byte-order mark, which
      -- `decodeByName` left in the first column's name: the input `age` was then
      -- missing from every row.
      it "reads a CSV that starts with a UTF-8 byte-order mark" $ do
        (code, _, rows) <- csvRowsOf [batchEligFixture, "--inputs", batchBomCsv]
        code `shouldBe` ExitSuccess
        statusesOf rows `shouldBe` [Just (String "success")]
        map (`inputOf` "age") rows `shouldBe` [Just (Number 25)]

      -- Ruled by Meng on 2026-10-13 (legalese/l4-ide#653): a record with fewer
      -- or more cells than the header is refused, naming its line. A short
      -- record used to leave its last input missing, and a long one lost its
      -- extra cells and was a success. The line of a tab and a space is blank,
      -- so it is skipped and still counted.
      it "refuses a record whose cell count is not the header's, naming its line" $ do
        (code, sout, rows) <- csvRowsOf [batchEligFixture, "--inputs", batchRaggedCsv]
        code `shouldSatisfy` (/= ExitSuccess)
        statusesOf rows `shouldBe` map (Just . String) ["success", "error", "error"]
        -- the message says what the reader would otherwise have done, which on
        -- main is to leave the missing cell out (there are no defaults to take)
        let reason = ", so the row is refused: a cell missing from a short row would otherwise"
                     <> " be read as left out (NOTHING for a MAYBE input, a missing field for any"
                     <> " other), and a long row's extra cells would be dropped"
        sout `shouldSatisfy` (("Line 3 has 2 cells, but the header has 3" <> reason) `isInfixOf`)
        sout `shouldSatisfy` (("Line 5 has 4 cells, but the header has 3" <> reason) `isInfixOf`)
        Output vcode vout _ <-
          runL4 bin ["batch", batchEligFixture, "--inputs", batchRaggedCsv, "--validate-only", "--continue-on-error"]
        vcode `shouldSatisfy` (/= ExitSuccess)
        vout `shouldSatisfy` ("Line 3 has 2 cells" `isInfixOf`)

      -- Not a change: the new reader has to keep reading what cassava read. CRLF
      -- line ends are not part of a cell, and a quoted cell may hold a line break.
      -- The rule `echoCode` returns the cell, so the line break must also survive
      -- the generated wrapper, which needs the exact quoting this change adds
      -- (see the round-trip test further down).
      it "reads CRLF line ends, and a quoted cell holding a line break, as one row each" $ do
        (code, _, rows) <- csvRowsOf [batchCodeFixture, "--inputs", batchCrlfCsv]
        code `shouldBe` ExitSuccess
        map (`inputOf` "code") rows
          `shouldBe` [Just (String "plain"), Just (String "line one\nline two")]
        let resultOf row = case objField row "output" of
              Just (Array outs) | (o : _) <- foldr (:) [] outs -> objField o "result"
              _ -> Nothing
        map resultOf rows
          `shouldBe` [Just (String "plain"), Just (String "line one\nline two")]

    -- A CSV file that cannot be read stops the command before any case runs.
    -- It used to say only what the parser was called (`endOfInput`, `13: not
    -- enough input`); cassava's own reader, before `csvRows`, named the input
    -- it stopped at.
    it "names the line of a CSV file it cannot read" $ do
      Output code sout _ <- runL4 bin ["batch", batchCodeFixture, "--inputs", batchCsvBadQuote]
      code `shouldSatisfy` (/= ExitSuccess)
      -- the stray quote is on line 2, after `ab`
      sout `shouldSatisfy` ("line 2 of the CSV file is not valid CSV, near `\"c`" `isInfixOf`)
      sout `shouldNotSatisfy` ("endOfInput" `isInfixOf`)

    it "says that an empty CSV file is empty" $ do
      Output code sout _ <- runL4 bin ["batch", batchCodeFixture, "--inputs", batchCsvEmpty]
      code `shouldSatisfy` (/= ExitSuccess)
      sout `shouldSatisfy` ("the CSV file is empty" `isInfixOf`)
      sout `shouldNotSatisfy` ("not enough input" `isInfixOf`)

    -- A quote that opens a cell and is never closed. cassava's reader of a
    -- quoted cell takes everything to the end of the file and drops the last
    -- byte, taking it for the closing quote: `"abc` was the text `ab` with
    -- status success, and in the middle of a file the cell swallowed every row
    -- after it. Each is refused, at the line where the quote opens.
    describe "a quote that opens a CSV cell and is never closed" $ do
      let refusedAt n file = do
            Output code sout _ <- runL4 bin ["batch", batchCodeFixture, "--inputs", file]
            code `shouldSatisfy` (/= ExitSuccess)
            sout `shouldSatisfy` (("line " <> show (n :: Int) <> " of the CSV file is not valid CSV: a quote that opens a cell there is never closed") `isInfixOf`)
            -- and no row is run
            sout `shouldNotSatisfy` ("\"status\"" `isInfixOf`)

      it "is refused at the end of the file, naming the line" $ refusedAt 2 batchCsvOpenQuoteEof
      it "is refused in the middle of a file, rather than taking the rows after it" $ refusedAt 2 batchCsvOpenQuoteMid
      it "is refused in a file with Windows line ends" $ refusedAt 2 batchCsvOpenQuoteCrlf
      it "is refused when the last quote is half of a doubled one" $ refusedAt 2 batchCsvOpenQuoteDoubled
      it "is refused in the header" $ refusedAt 1 batchCsvOpenQuoteHeader

      -- The control: a cell that closes at the very end of the file, with no
      -- line end after it, is a cell, so the check cannot be refusing every
      -- file that ends in a quote.
      it "does not refuse a cell that closes at the end of the file" $ do
        Output code sout _ <- runL4 bin ["batch", batchCodeFixture, "--inputs", batchCsvQuoteClosesAtEof]
        code `shouldBe` ExitSuccess
        sout `shouldSatisfy` ("\"result\":\"abc\"" `isInfixOf`)

    it "keeps a line break inside a string literal as it is written" $ do
      -- batch runs the re-printed module; before smucclaw/l4-ide#1028 the newline came back
      -- followed by the body's indentation ("line\\n  next"), status success.
      Output code sout _ <- runL4 bin ["batch", batchLineBreakFixture, "--inputs", batchLineBreakJson]
      code `shouldBe` ExitSuccess
      case filter (not . all (`elem` (" \t\r" :: String))) (lines sout) of
        [broken, tabbed] -> do
          broken `shouldSatisfy` ("\"result\":\"line\\nnext\"" `isInfixOf`)
          tabbed `shouldSatisfy` ("\"result\":\"tab\\there\"" `isInfixOf`)
        rows -> expectationFailure ("expected 2 rows, got " ++ show (length rows) ++ ":\n" ++ sout)

    it "validate-only type-checks MAYBE primitive params" $ do
      -- premium is declared `A MAYBE NUMBER`; a BOOLEAN value must be flagged
      -- as a type mismatch. Before unwrapping MAYBE on the AST this silently
      -- passed as valid.
      Output code sout _ <-
        runL4 bin [ "batch", batchMaybeFixture, "--inputs", batchMaybeBadJson
                  , "--validate-only" ]
      code `shouldSatisfy` (/= ExitSuccess)
      sout `shouldSatisfy` ("\"status\":\"invalid\"" `isInfixOf`)
      sout `shouldSatisfy` ("Type mismatch for field 'premium'" `isInfixOf`)
      sout `shouldSatisfy` ("expected NUMBER" `isInfixOf`)

    -- Regression tests for the generated wrapper's string quoting.
    it "escapes payloads with backslashes, quotes and control chars (no lexer break)" $ do
      -- The payload holds a Windows path, embedded quotes, a newline, a tab,
      -- an apostrophe, braces and a percent sign. This pins the LOUD half of
      -- the escaping only: `echoFixed` ignores its payload, so a quote-only
      -- escaper fails here just because an unescaped `"` ends the wrapper's
      -- string literal early and the wrapper no longer lexes. A backslash, a
      -- tab or a line break does not break the lexing, and is pinned by the
      -- next test. (`l4 batch` runs no shell, so no shell metacharacter is
      -- involved.)
      env <- jsonEnvelope bin ["batch", batchEscapeFixture, "--inputs", batchEscapeInput]
      objField env "status" `shouldBe` Just (String "success")

    -- The silent half. With a quote-only escaper a backslash reaches the lexer
    -- unescaped, which reads it as the start of an escape of its own, so the
    -- rule is handed JSON that is not the JSON that was sent, and the row is
    -- still a success. Measured on plain main: `\u0041` (a backslash, then
    -- u0041) comes back as `A`, `\\n` (two backslashes and an n) as a
    -- backslash and an n, and a Windows path, a tab and a line break as null.
    -- `echoCode` returns its input, so a payload the wrapper changed shows as a
    -- result that is not the one sent.
    it "hands every payload to the rule and back unchanged: backslashes, tabs, line breaks, escape-looking text" $ do
      Output code sout _ <-
        runL4 bin ["batch", batchCodeFixture, "--inputs", batchEscapeRoundtripJson, "--continue-on-error"]
      let rows = [ row | l <- map (filter (/= '\r')) (lines sout)
                       , Right row <- [eitherDecode (BSL8.pack l) :: Either String Value] ]
          sent = [ objField r "input" >>= (`objField` "code") | r <- rows ]
          result r = case objField r "output" of
            Just (Array outs) | (o : _) <- foldr (:) [] outs -> objField o "result"
            _ -> Nothing
      code `shouldBe` ExitSuccess
      map (`objField` "status") rows `shouldBe` replicate 6 (Just (String "success"))
      sent `shouldBe` map (Just . String . T.pack)
        [ "C:\\Users\\x", "back\\slash", "tab\there", "line\nbreak", "\\u0041", "\\\\n" ]
      map result rows `shouldBe` sent

    -- The same, for a CSV file, where the values arrive as cells. Each cell is
    -- `echoCode`'s input and so must be its answer, and each is its own example,
    -- so a failure names the cell. On the hand-rolled escaper the double quote
    -- fails to lex, and the backslash, the trailing backslash, the tab, the line
    -- break and the carriage return come back as null, and the escape-looking
    -- text as a different string, every one under status success; the plain
    -- text, the non-ASCII letter and the apostrophe case are the controls that
    -- pass there.
    describe "hands a CSV cell to the rule and back unchanged" $ do
      let cells :: [(String, String)]
          cells = [ ("plain text", "plain"), ("a double quote", "say \"hi\""), ("a backslash", "C:\\Users\\x")
                  , ("a trailing backslash", "trailing\\"), ("a tab", "tab\there")
                  , ("a line break", "line one\nline two"), ("a carriage return", "cr\rhere")
                  , ("a non-ASCII letter", "caf\233"), ("text that looks like an escape", "\\u0041")
                  , ("two backslashes and an n", "\\\\n"), ("an apostrophe, braces and a percent sign", "it's {braced} 100%") ]
          resultOf row = case objField row "output" of
            Just (Array outs) | (o : _) <- foldr (:) [] outs -> objField o "result"
            _ -> Nothing
      beforeAll
        (do Output code sout _ <-
              runL4 bin ["batch", batchCodeFixture, "--inputs", batchEscapeCellsCsv, "--continue-on-error"]
            pure ( code
                 , [ row | l <- lines sout
                         , Right row <- [eitherDecode (BSL8.fromStrict (TE.encodeUtf8 (T.pack (filter (/= '\r') l)))) :: Either String Value] ] )) do
        it "reads one row per cell, and exits 0" \(code, rows) -> do
          length rows `shouldBe` length cells
          code `shouldBe` ExitSuccess
        forM_ (zip [0 ..] cells) \(i, (name, expected)) ->
          it ("keeps " <> name) \(_, rows) ->
            case drop i rows of
              row : _ ->
                (objField row "status", resultOf row)
                  `shouldBe` (Just (String "success"), Just (String (T.pack expected)))
              [] -> expectationFailure "no row for this cell"

    -- A value is read by the type its input declares. Main's `coerceInputTypes`
    -- (f6ebc282e) did that; #47's `inferCsvCell` types a CSV cell by how it
    -- looks and knows nothing of JSON or YAML, so each of these answered with
    -- status "error" without the declared-type step.
    describe "reads a value by the type its input declares" $ do
      let rowsOf args = do
            Output code sout _ <- runL4 bin (["batch"] <> args <> ["--continue-on-error"])
            pure ( code
                 , sout
                 , [ row | l <- map (filter (/= '\r')) (lines sout)
                         , Right row <- [eitherDecode (BSL8.pack l) :: Either String Value] ] )
          resultOf row = case objField row "output" of
            Just (Array outs) | (o : _) <- foldr (:) [] outs -> objField o "result"
            _ -> Nothing
          statusAndResult row = (objField row "status", resultOf row)
          succeeded r = (Just (String "success"), Just r)

      it "reads text for a NUMBER or BOOLEAN input as a number or a boolean, in JSON" $ do
        (code, sout, rows) <- rowsOf [batchEligFixture, "--inputs", batchDeclaredStringsJson]
        code `shouldBe` ExitSuccess
        map statusAndResult rows `shouldBe` [succeeded (Bool True), succeeded (Bool False)]
        -- the line shows the case as the inputs declare it
        sout `shouldSatisfy` ("\"age\":25" `isInfixOf`)

      it "reads text for a NUMBER or BOOLEAN input as a number or a boolean, in YAML" $ do
        (code, _, rows) <- rowsOf [batchEligFixture, "--inputs", batchDeclaredStringsYaml]
        code `shouldBe` ExitSuccess
        map statusAndResult rows `shouldBe` [succeeded (Bool True), succeeded (Bool False)]

      it "validates a case that sends text for a NUMBER or BOOLEAN input" $ do
        Output code sout _ <-
          runL4 bin ["batch", batchEligFixture, "--inputs", batchDeclaredStringsJson, "--validate-only"]
        code `shouldBe` ExitSuccess
        sout `shouldNotSatisfy` ("\"status\":\"invalid\"" `isInfixOf`)

      it "keeps a CSV cell for a STRING input as the text written" $ do
        -- 123456 and 1.50 used to arrive as numbers and be refused; 018956 and
        -- 1e3 already stayed text
        (code, _, rows) <- rowsOf [batchCodeFixture, "--inputs", batchDeclaredStringCellsCsv]
        code `shouldBe` ExitSuccess
        map statusAndResult rows
          `shouldBe` map (succeeded . String) ["123456", "018956", "1.50", "1e3"]

      -- JSON and YAML carry their own types, so a number sent for a STRING
      -- input is an error.
      it "still refuses a JSON number for a STRING input" $ do
        (code, _, rows) <- rowsOf [batchCodeFixture, "--inputs", batchDeclaredNumberForStringJson]
        code `shouldSatisfy` (/= ExitSuccess)
        map (`objField` "status") rows `shouldBe` [Just (String "error")]

      it "leaves text that is not a number alone, so the error names the value" $ do
        -- `age` is readable and `income` is not. The error is about `lots`.
        (code, _, rows) <- rowsOf [batchEligFixture, "--inputs", batchDeclaredBadNumberJson]
        code `shouldSatisfy` (/= ExitSuccess)
        case rows of
          [row] -> do
            objField row "status" `shouldBe` Just (String "error")
            let diagnostics = show (objField row "diagnostics")
            diagnostics `shouldSatisfy` ("lots" `isInfixOf`)
            diagnostics `shouldNotSatisfy` ("25" `isInfixOf`)
          other -> expectationFailure ("expected 1 row, got " ++ show (length other))

      -- Only a NUMBER or a BOOLEAN reads a CSV cell as anything but its text.
      -- A choice named `True`, or a DATE written without dashes, was typed by
      -- how it looks and then refused: `True` became JSON true ("Could not
      -- decode true as Answer"), and 20261013 a number.
      let declaredTextRows entry csv = rowsOf [batchDeclaredText, "-e", entry, "--inputs", csv]
      it "reads a CSV cell for a choice input as the name written" $ do
        (code, _, rows) <- declaredTextRows "echo answer" batchDeclaredTextAnswers
        code `shouldBe` ExitSuccess
        map statusAndResult rows `shouldBe` map (succeeded . String) ["yes", "no", "dunno"]

      it "reads a CSV cell for a MAYBE choice input as the name written, and a blank one as left out" $ do
        -- the second row is a quoted "", a cell that is blank (T3c)
        (code, _, rows) <- declaredTextRows "echo optional answer" batchDeclaredTextOptional
        code `shouldBe` ExitSuccess
        map statusAndResult rows `shouldBe` map (succeeded . String) ["yes", "none", "dunno"]

      it "reads a CSV cell for a DATE input as text, so a bad date is reported as one" $ do
        (code, _, rows) <- declaredTextRows "echo date" batchDeclaredTextDates
        code `shouldSatisfy` (/= ExitSuccess)
        case rows of
          [good, bad] -> do
            statusAndResult good `shouldBe` succeeded (String "2026-10-13")
            objField bad "status" `shouldBe` Just (String "error")
            show (objField bad "diagnostics") `shouldSatisfy` ("Could not parse date string '20261013'" `isInfixOf`)
          other -> expectationFailure ("expected 2 rows, got " ++ show (length other))

      -- Not a regression test: it passes on a build that types every cell by
      -- its look. It pins the way a synonym is still read as what it stands for.
      it "still reads a CSV cell for a synonym of NUMBER or BOOLEAN as one" $ do
        (code, _, rows) <- declaredTextRows "echo year" batchDeclaredTextSynonyms
        code `shouldBe` ExitSuccess
        map statusAndResult rows `shouldBe` [succeeded (Number 2026)]

      -- A MAYBE input is read by the type it wraps, so "25" is 25 for a MAYBE
      -- NUMBER. Plain main answered it with a decode error (an object holding
      -- the message) under status "success"; nothing tested the new reading.
      it "reads text for a MAYBE NUMBER input as the number it spells, and refuses text that is not one" $ do
        (code, _, rows) <- rowsOf [batchMaybeFixture, "--inputs", batchMaybeTextJson]
        code `shouldSatisfy` (/= ExitSuccess)
        map (`objField` "status") rows `shouldBe` map (Just . String) ["success", "error", "success"]
        case rows of
          [text, notANumber, number] -> do
            resultOf text   `shouldBe` Just (Number 25)
            resultOf number `shouldBe` Just (Number 25)
            show (objField notANumber "diagnostics") `shouldSatisfy` ("abc" `isInfixOf`)
          other -> expectationFailure ("expected 3 rows, got " ++ show (length other))

      -- An input declared through a synonym is the type the synonym stands for
      -- (DECLARE Year IS A NUMBER), and --validate-only has to judge it so:
      -- it used to look at the name `Year` and judge nothing, so text that is
      -- no number, or a number for a flag, was `valid` and then refused when
      -- the case was run. The plain exports in the fixture are the control.
      describe "an input declared through a synonym" $ do
        let run extra entry file = rowsOf ([batchSynonym, "-e", entry, "--inputs", file] <> extra)
            -- one word for how a case went, run or validated
            outcome row = case objField row "status" of
              Just (String st) | st `elem` ["success", "valid"] -> "accepted"
              _                                                  -> "refused" :: String
            shape row = (outcome row, objField row "diagnostics", objField row "errors")

        it "refuses text that is no number, as for a NUMBER, in JSON and in CSV" $ do
          forM_ [batchSynonymYearJson, batchSynonymYearCsv] \file -> do
            (_, _, plain)   <- run [] "plain number" file
            (_, _, through) <- run [] "next year" file
            map shape through `shouldBe` map shape plain
            -- and the first row, the text `abc`, is the one refused, with the
            -- message the plain NUMBER gets
            take 1 (map outcome through) `shouldBe` ["refused"]
            show (map (`objField` "diagnostics") (take 1 through)) `shouldSatisfy` ("Expected JSON number but got: String" `isInfixOf`)

        it "refuses text that is no boolean, and a number, as for a BOOLEAN, in JSON and in CSV" $ do
          forM_ [batchSynonymFlagJson, batchSynonymFlagCsv] \file -> do
            (_, _, plain)   <- run [] "plain flag" file
            (_, _, through) <- run [] "flip flag" file
            map shape through `shouldBe` map shape plain
            take 1 (map outcome through) `shouldBe` ["refused"]

        it "judges a synonym's value under --validate-only as it judges the plain type's" $ do
          forM_ [ ("next year", "plain number", batchSynonymYearJson)
                , ("flip flag", "plain flag", batchSynonymFlagJson) ] \(entry, control, file) -> do
            (_, _, plain)   <- run ["--validate-only"] control file
            (_, _, through) <- run ["--validate-only"] entry file
            map shape through `shouldBe` map shape plain
            -- the mismatch is named, as for the plain type
            show (map (`objField` "errors") through) `shouldSatisfy` ("Type mismatch for field" `isInfixOf`)

        it "validates what it would run: a case is valid exactly when it is accepted" $ do
          forM_ [ ("next year", batchSynonymYearJson), ("flip flag", batchSynonymFlagJson)
                , ("maybe year", batchSynonymYearJson), ("year maybe", batchSynonymYearJson) ]
            \(entry, file) -> do
              (_, _, validated) <- run ["--validate-only"] entry file
              (_, _, ran)       <- run [] entry file
              (entry, map outcome validated) `shouldBe` (entry, map outcome ran)

  -- A step of a trace is printed as source, and a string literal in source is
  -- spelled with escapes: a line break as \n, a tab as \t. #595 made the printer
  -- do that so that `l4 batch` keeps a string that holds a line break; it also
  -- changed every other surface that prints a step: the trace `l4 trace`
  -- reports, and the `exampleCode` of the jl4-service reasoning tree (pinned in
  -- jl4-service-test). Before it, a step broke across lines inside the literal.
  -- The VALUE a trace ends in is not source and keeps its line break. `l4 run`
  -- prints no trace steps on main ("no trace captured"), so it is not pinned.
  -- Ruled 2026-10-12: printed string literals stay escaped on every surface,
  -- and every surface it reaches is listed in the PR body.
  describe "a string literal in a trace step" $ do
    it "is spelled as source in the trace `l4 trace` reports" $ do
      Output code _ serr <- runL4 bin ["trace", evalTraceLineBreakFixture]
      code `shouldBe` ExitSuccess
      let err = map (filter (/= '\r')) (lines serr)
          escapedStep = "IF (x GREATER THAN 0) THEN \"line\\nnext\" ELSE \"tab\\there\""
      err `shouldSatisfy` any (escapedStep `isInfixOf`)
      -- no step ends inside a literal
      err `shouldNotSatisfy` any ("THEN \"line" `isSuffixOf`)

  describe "l4 trace (output path safety)" $ do
    it "never runs a shell for the output path, so metacharacters can't inject" $ do
      -- Render into a directory whose *name* would execute `touch <sentinel>`
      -- if the path were ever handed to a shell. With a direct `proc` call it
      -- is just a literal (if unusual) directory name. The sentinel must not
      -- appear regardless of whether Graphviz's `dot` is installed.
      -- The sentinel is relative, run from a scratch directory: an absolute
      -- Windows path would put a drive colon into the directory name.
      tmp <- getTemporaryDirectory
      let work     = tmp </> "l4-trace-injection"
          sentinel = "l4-trace-injection-sentinel"
          evilDir  = "l4trace$(touch " ++ sentinel ++ ").d"
      removePathForcibly work
      createDirectoryIfMissing True (work </> evilDir)
      fixture <- makeAbsolute evalTraceFixture
      _ <- runL4In (Just work) Nothing bin
        ["trace", fixture, "--format", "png", "--output-dir", evilDir]
      ranShell <- doesFileExist (work </> sentinel)
      removePathForcibly work
      ranShell `shouldBe` False

    it "writes trace output into a directory whose path contains a space" $ do
      -- The `.dot` branch needs no external tools; it exercises the same
      -- outDir path-join the png/svg branches feed to `dot`, proving spaces
      -- survive instead of being word-split.
      tmp <- getTemporaryDirectory
      let outDir = tmp </> "l4 trace out"   -- note the space
      removePathForcibly outDir
      Output code _ _ <- runL4 bin ["trace", evalTraceFixture, "--format", "dot", "--output-dir", outDir]
      code `shouldBe` ExitSuccess
      wrote <- doesFileExist (outDir </> "evaltrace-eval1.dot")
      removePathForcibly outDir
      wrote `shouldBe` True

    it "runs no shell for --output-dir, and renders or fails with a diagnostic" $ do
      -- `;` ends a shell command, so this name, handed to a shell, runs
      -- `touch PWNED` in the working directory. The marker is relative, so
      -- unlike the case above the name has no drive colon and no separator,
      -- and is a legal directory on Windows as well.
      tmp <- getTemporaryDirectory
      let work    = tmp </> "l4-trace-metachar"
          evilDir = "o;touch PWNED;x"
      removePathForcibly work
      createDirectoryIfMissing True work
      fixture <- makeAbsolute evalTraceFixture
      Output code _ serr <- runL4In (Just work) Nothing bin
        ["trace", fixture, "--format", "png", "--output-dir", evilDir]
      ranShell <- doesFileExist (work </> "PWNED")
      rendered <- doesFileExist (work </> evilDir </> "evaltrace-eval1.png")
      removePathForcibly work
      ranShell `shouldBe` False
      case code of
        ExitSuccess   -> rendered `shouldBe` True
        ExitFailure _ -> serr `shouldSatisfy` ("Error: " `isInfixOf`)

    it "hands dot an output dir beginning with '-' as a path, not an option" $ do
      -- dot reads any argument starting with `-` as an option, and has no
      -- `--` to stop that. Given `-out/evaltrace-eval1.dot` it reads
      -- `-o ut/...`, takes the graph from stdin instead, and exits 0 having
      -- written nothing, so `l4 trace` reported an empty SVG as generated.
      -- Only a real `dot` shows this, so without one the test is pending.
      mDot <- findExecutable "dot"
      case mDot of
        Nothing -> pendingWith "Graphviz `dot` is not on PATH"
        Just _ -> do
          tmp <- getTemporaryDirectory
          let work    = tmp </> "l4-trace-dash-path"
              svgFile = work </> "-out" </> "evaltrace-eval1.svg"
          removePathForcibly work
          createDirectoryIfMissing True work
          fixture <- makeAbsolute evalTraceFixture
          Output code _ _ <- runL4In (Just work) Nothing bin
            ["trace", fixture, "--format", "svg", "--output-dir=-out"]
          wrote <- doesFileExist svgFile
          svg <- if wrote
            then T.unpack . TE.decodeUtf8Lenient <$> BS.readFile svgFile
            else pure ""
          removePathForcibly work
          code `shouldBe` ExitSuccess
          svg `shouldSatisfy` ("<svg" `isInfixOf`)

  -- `l4 batch` re-prints the module and evaluates the printed text, so these
  -- check the printer's brackets as much as batch. Each operand nests inside an
  -- AND, and each expected answer is the fixture's own #EVAL under `l4 run`.
  -- With the printer as it was, batch answered `true` to every one of them,
  -- with "status":"success" and no diagnostic.
  describe "l4 batch keeps the grouping the rule wrote" $ do
    let bracket = fixtureDir </> "batch-bracket.l4"
        rows f  = fixtureDir </> ("batch-bracket-" ++ f ++ ".json")
    it "brackets an OR inside an AND" $
      batchAnswer bin bracket (rows "tff") "or under and" `shouldReturn` Bool False
    it "brackets a NOT inside an AND" $
      batchAnswer bin bracket (rows "tff") "not under and" `shouldReturn` Bool False
    it "brackets an IMPLIES inside an AND" $
      batchAnswer bin bracket (rows "fff") "implies under and" `shouldReturn` Bool False
    it "brackets an IF inside an AND" $
      batchAnswer bin bracket (rows "ttf") "if under and" `shouldReturn` Bool False
    it "brackets a function call inside an AND" $
      batchAnswer bin bracket (rows "fff") "call under and" `shouldReturn` Bool False

  -- `l4 batch` re-prints the module and evaluates the printed text, so these
  -- check the printer as much as batch. Each expected value is what `l4 run`
  -- gives on the fixture's own #EVAL. On build 90 the first three returned the
  -- opposite answer with "status":"success", and the division failed to
  -- re-parse (`a DIVIDED b`).
  describe "l4 batch agrees with l4 run" $ do
    let grouping = fixtureDir </> "batch-grouping.l4"
        rows f   = fixtureDir </> ("batch-grouping-" ++ f ++ ".json")
    it "keeps the brackets on an OR inside an AND" $
      batchAnswer bin grouping (rows "tff") "or under and" `shouldReturn` Bool False
    it "keeps the brackets on a NOT inside an OR" $
      batchAnswer bin grouping (rows "ttf") "not under or" `shouldReturn` Bool True
    it "keeps the brackets on an IMPLIES inside an AND" $
      batchAnswer bin grouping (rows "fff") "implies under and" `shouldReturn` Bool False
    it "evaluates an exported division" $
      batchAnswer bin (fixtureDir </> "batch-division.l4") (fixtureDir </> "batch-division.json") "divided"
        `shouldReturn` Number 2

  -- `l4 batch` prints the checked module back and checks it again beside a
  -- generated record with a field for each input. An annotation that names an
  -- input (`%a%`) would then have two candidates and no expected type to choose
  -- between them, and `main`'s checker refuses that ("multiple definitions").
  -- `prettyLayout` writes no annotation back, so the row runs; this pins it.
  describe "l4 batch runs an export whose annotation names its input" $
    it "answers instead of refusing the printed module" $
      batchAnswer bin (fixtureDir </> "batch-nlg-input-slot.l4") (fixtureDir </> "batch-nlg-input-slot.json") "is large"
        `shouldReturn` Bool True

  -- An `@nlg` annotation is wording for the reader of a rule, not part of what
  -- the rule evaluates to. `prettyLayout` prints evaluation results, and it
  -- writes no annotation back; a printer that did would put `[a red colour]`
  -- inside `Shape OF Red [a red colour], 3`.
  describe "l4 run prints a value without its annotations" $ do
    let runOut = do
          Output code sout0 _ <- runL4 bin ["run", fixtureDir </> "annotated-values.l4"]
          code `shouldBe` ExitSuccess
          pure (filter (/= '\r') sout0)
    it "leaves an annotation off a constructor inside a value" $ do
      sout <- runOut
      sout `shouldSatisfy` ("Shape OF Red, 3" `isInfixOf`)
      sout `shouldSatisfy` ("JUST OF Green" `isInfixOf`)
      sout `shouldNotSatisfy` ("a red colour" `isInfixOf`)
      sout `shouldNotSatisfy` ("a green colour" `isInfixOf`)
    it "leaves an annotation off the party and the action of an obligation" $ do
      sout <- runOut
      sout `shouldSatisfy` ("PARTY Alice" `isInfixOf`)
      sout `shouldSatisfy` ("MUST `pay the price`" `isInfixOf`)
      sout `shouldNotSatisfy` ("the payer" `isInfixOf`)
      sout `shouldNotSatisfy` ("paying" `isInfixOf`)

  -- Regression test for smucclaw/l4-ide#906: a diamond import over the
  -- embedded-library fallback used to starve the second sibling of the shared
  -- bottom's environment. `main.l4` imports two embedded siblings
  -- (actus-daycount, actus-schedule) that both IMPORT the embedded `daydate`;
  -- `actus-schedule` uses `Days in month`, defined in `daydate`. Run under the
  -- embedded-only regime (no JL4_LIBRARY_PATH, empty XDG) so the whole closure
  -- is served by the LSP/Shake embedded fallback — exactly the path CI's
  -- JL4_LIBRARY_PATH normally hides. Before the fix `l4 check` printed
  -- "I could not find a definition for the identifier ..." errors for the
  -- starved sibling (and still exited 0, so the assertion on the text below is
  -- what fails). The same starvation stops an ordinary user file that writes
  -- `IMPORT prelude` and `IMPORT daydate` from finding `sum`; that file exits 1
  -- before the fix.
  describe "l4 embedded-library diamond imports (smucclaw/l4-ide#906)" $ do
    it "threads a transitive re-export into both diamond siblings" $ do
      Output code sout serr <- runL4EmbeddedOnly bin ["check", embeddedDiamondEntry]
      let combined = sout ++ "\n" ++ serr
      -- The starvation surfaces as an out-of-scope error on daydate's exports.
      when ("could not find a definition" `isInfixOf` combined) $
        expectationFailure $
          "Diamond sibling was starved of the embedded `daydate` environment:\n"
          ++ "--- stdout ---\n" ++ sout
          ++ "\n--- stderr ---\n" ++ serr
      case code of
        ExitSuccess -> pure ()
        ExitFailure n -> expectationFailure $
          "Expected the embedded-fallback diamond to check clean, but l4 exited "
          ++ show n ++ "\n--- stdout ---\n" ++ sout
          ++ "\n--- stderr ---\n" ++ serr

  -- Regression tests for specs/as-built/import-resolution.md (Option B′ ordering +
  -- Option E shadow warning). All run in the dev regime: JL4_LIBRARY_PATH
  -- unset, XDG_DATA_HOME pointed at a fabricated store. The incident being
  -- guarded against (§3.1 there): a machine-global XDG symlink silently
  -- shadowing the stdlib the binary was built with.
  describe "l4 library resolution shadow (B′)" $ do
    let mkXdgStore name libFileName mkLib = do
          tmp <- getTemporaryDirectory
          let xdgHome = tmp </> name
              store = xdgHome </> "jl4" </> "libraries"
          removePathForcibly xdgHome
          createDirectoryIfMissing True store
          _ <- mkLib (store </> libFileName)
          pure xdgHome
        poison = "this is not L4 at all ("

    it "embedded stdlib outranks a poisoned machine-global XDG copy" $ do
      xdgHome <- mkXdgStore "l4-shadow-xdg-poison" "prelude.l4" \p -> writeFile p poison
      Output code sout serr <- runL4WithXdgHome xdgHome bin ["check", shadowEmbeddedEntry]
      case code of
        ExitSuccess -> pure ()
        ExitFailure n -> expectationFailure $
          "Expected the embedded prelude to outrank the poisoned XDG copy, but l4 exited "
          ++ show n ++ "\n--- stdout ---\n" ++ sout
          ++ "\n--- stderr ---\n" ++ serr
      -- Option E: two differing copies were visible; the warning names them
      -- and the chosen one, at a priority the CLI actually prints. The two rows
      -- are asserted whole, with their markers: that the words "embedded
      -- stdlib" and "XDG data dir" appear somewhere in the output proves
      -- nothing, because the unresolved-import error and the parse error in
      -- the poisoned file name them too. On plain main, which has no warning,
      -- the poisoned file is reported as a parse error and the check still
      -- exits 0.
      serr `shouldSatisfy` ("Multiple differing copies of module `prelude`" `isInfixOf`)
      serr `shouldSatisfy` ("[chosen]   embedded stdlib" `isInfixOf`)
      serr `shouldSatisfy` ("[shadowed] XDG data dir" `isInfixOf`)

    -- The example below makes a symbolic link, and is marked pending where the
    -- account may not make one (Windows without the symlink privilege). This
    -- pins that path: a link made in a folder the account may not write to is
    -- reported, not thrown.
    it "reports a link it may not create, instead of throwing" $ do
      tmp <- getTemporaryDirectory
      let locked = tmp </> "l4-shadow-locked"
          target = tmp </> "l4-shadow-locked-target.l4"
          open' = setOwnerWritable True (setOwnerSearchable True (setOwnerReadable True emptyPermissions))
      removePathForcibly locked
      createDirectoryIfMissing True locked
      writeFile target poison
      setPermissions locked emptyPermissions
      r <- tryLink target (locked </> "prelude.l4") `finally` setPermissions locked open'
      case r of
        Left why -> why `shouldSatisfy` ("cannot create a symbolic link" `isInfixOf`)
        Right () -> pendingWith "this account can make a link in a read-only folder (root, or a platform that ignores the mode)"

    it "dereferences symlinks when naming the shadowed copy" $ do
      tmp <- getTemporaryDirectory
      let target = tmp </> "l4-shadow-poison-target.l4"
      writeFile target poison
      realTarget <- canonicalizePath target
      xdgHome <- mkXdgStore "l4-shadow-xdg-symlink" "prelude.l4" \p -> linkOrPending target p
      Output code _sout serr <- runL4WithXdgHome xdgHome bin ["check", shadowEmbeddedEntry]
      code `shouldBe` ExitSuccess
      -- The warning must print the symlink's real target, so a reader can see
      -- WHICH checkout/file a machine-global entry actually points at.
      serr `shouldSatisfy` (realTarget `isInfixOf`)

    it "a project-local prelude override still outranks the embedded stdlib" $ do
      xdgHome <- mkXdgStore "l4-shadow-xdg-empty" "unused.txt" \_ -> pure ()
      Output code sout serr <- runL4WithXdgHome xdgHome bin ["check", shadowSiblingEntry]
      -- main.l4 uses `shadow marker`, defined only in the fixture's local
      -- prelude.l4 — this checks clean iff the project-scoped copy won.
      case code of
        ExitSuccess -> pure ()
        ExitFailure n -> expectationFailure $
          "Expected the project-local prelude override to win, but l4 exited "
          ++ show n ++ "\n--- stdout ---\n" ++ sout
          ++ "\n--- stderr ---\n" ++ serr

    it "identical copies do not warn (content gate, non-embedded module)" $ do
      -- `shadow-extra` is NOT an embedded module; it exists beside the
      -- importing file AND in the XDG store, byte-identical. Two sources, one
      -- content: the Option E warning must stay silent.
      localCopy <- readFile (fixtureDir </> "library-shadow" </> "xdg-extra" </> "shadow-extra.l4")
      xdgHome <- mkXdgStore "l4-shadow-xdg-identical" "shadow-extra.l4" \p -> writeFile p localCopy
      Output code _sout serr <- runL4WithXdgHome xdgHome bin ["check", shadowExtraEntry]
      code `shouldBe` ExitSuccess
      serr `shouldSatisfy` (not . ("Multiple differing copies" `isInfixOf`))

    it "differing copies of the same non-embedded module do warn" $ do
      xdgHome <- mkXdgStore "l4-shadow-xdg-differing" "shadow-extra.l4" \p ->
        writeFile p "`something else entirely` MEANS TRUE\n"
      Output code _sout serr <- runL4WithXdgHome xdgHome bin ["check", shadowExtraEntry]
      -- The project-scoped copy wins either way; the differing ambient copy
      -- must be called out.
      code `shouldBe` ExitSuccess
      serr `shouldSatisfy` ("Multiple differing copies of module `shadow-extra`" `isInfixOf`)

  -- Precedence has to survive HOW THE ENTRY FILE IS SPELLED, and it has to
  -- reach embedded importers, not just the top-level module. Neither property
  -- was covered: every fixture path above carries a directory component, so
  -- @rootDirectory@ was never "."; and no fixture put a project copy of a module
  -- that an EMBEDDED library imports. Both gaps hid live precedence inversions
  -- on unstable. Plain main shows only the second: the bare-entry cases pass
  -- there too, and the embedded-importer cases are what fail.
  describe "l4 library resolution: entry-path spelling and embedded importers" $ do
    -- `l4 check main.l4`, run from inside the project — the ordinary way a user
    -- invokes the CLI, and the one that makes the resolver's root directory ".".
    let checkFrom dir = do
          absDir <- makeAbsolute dir
          runL4EmbeddedOnlyIn (Just absDir) bin ["check", "main.l4"]

    it "a project-local prelude override wins when the entry file is named bare" $ do
      -- Byte-for-byte the sibling-wins fixture the test above already uses, run
      -- as `l4 check main.l4` instead of `l4 check <dir>/main.l4`. The verdict
      -- must not depend on the spelling: main.l4 uses `shadow marker`, which
      -- only the fixture's own prelude.l4 defines.
      --
      -- Plain main passes this too. It is here because the change makes the
      -- embedded stdlib a candidate URI of its own (`jl4-embedded:`), and a
      -- version of the idea that registered it at a file-shaped key made the
      -- embedded prelude beat the project's when the root directory was ".",
      -- so this exited 1 with "I could not find a definition for the identifier
      -- `shadow marker`".
      Output code sout serr <- checkFrom shadowSiblingDir
      case code of
        ExitSuccess -> pure ()
        ExitFailure n -> expectationFailure $
          "Expected the project-local prelude override to win for a bare entry\
          \ path too, but l4 exited " ++ show n
          ++ "\n--- stdout ---\n" ++ sout
          ++ "\n--- stderr ---\n" ++ serr

    it "the embedded stdlib still wins with a bare entry path when nothing shadows it" $ do
      -- The other direction, so the fix above cannot be "never consult the
      -- embedded stdlib": embedded-wins/main.l4 has no project-local prelude, so
      -- the embedded copy must serve it.
      Output code sout serr <- checkFrom shadowEmbeddedDir
      case code of
        ExitSuccess -> pure ()
        ExitFailure n -> expectationFailure $
          "Expected the embedded prelude to serve a bare entry path, but l4 exited "
          ++ show n ++ "\n--- stdout ---\n" ++ sout
          ++ "\n--- stderr ---\n" ++ serr

    -- The names, not just the import. embedded-wins/main.l4 above only writes
    -- the `IMPORT`, so it cannot tell a prelude that is in scope from one that
    -- is not. With the entry file named bare and nothing on disk to find, plain
    -- main binds none of the prelude's names: `cd project && l4 run total.l4`
    -- answers "I could not find a definition for the identifier `sum`" and
    -- exits 1, while `l4 run project/total.l4` works.
    it "a bare entry path still brings the stdlib's names into scope" $ do
      tmp <- getTemporaryDirectory
      let work = tmp </> "l4-bare-entry-stdlib-names"
      removePathForcibly work
      createDirectoryIfMissing True work
      writeFile (work </> "total.l4") (unlines ["IMPORT prelude", "", "#EVAL sum (LIST 1, 2, 3)"])
      Output code sout serr <- runL4EmbeddedOnlyIn (Just work) bin ["run", "total.l4"]
      removePathForcibly work
      let combined = sout ++ "\n" ++ serr
      when ("could not find a definition" `isInfixOf` combined) $
        expectationFailure ("`sum` was not in scope after IMPORT prelude:\n" ++ combined)
      code `shouldBe` ExitSuccess

    -- One module name, one source, including for importers that are themselves
    -- embedded libraries. embedded-importer/daydate.l4 is a deliberately
    -- narrower override of a module the embedded `actus-schedule` imports and
    -- uses; binding `actus-schedule` to it must surface an arity error against
    -- `actus-schedule` itself. Before the change this checked clean: `main` saw
    -- the project `daydate` while `actus-schedule` quietly kept the embedded one.
    --
    -- An error inside an imported module fails the check, as one in the entry
    -- file does, so the exit code is asserted too. The text is the evidence of
    -- WHICH module it is: the arity error names `actus-schedule`, and the shadow
    -- warning names the chosen project copy.
    --
    -- The positive control is the `embedded-diamond` test above: the same
    -- embedded closure with no project override checks clean.
    let expectEmbeddedImporterSeesOverride label run =
          it label $ do
            Output code _sout serr <- run
            code `shouldBe` ExitFailure 1
            -- The diagnostic must land on the EMBEDDED importer, which is the
            -- whole point: that is the module that changed source.
            serr `shouldSatisfy` ("actus-schedule" `isInfixOf`)
            -- ...and the shadow warning must be telling the truth when it says
            -- the chosen copy is used wherever the module is imported.
            serr `shouldSatisfy` ("Multiple differing copies of module `daydate`" `isInfixOf`)
            serr `shouldSatisfy` ("[chosen]   project root" `isInfixOf`)

    expectEmbeddedImporterSeesOverride
      "an embedded library sees the project-local override too"
      (runL4EmbeddedOnly bin ["check", shadowImporterEntry])

    expectEmbeddedImporterSeesOverride
      "...and also when the entry file is named bare"
      (checkFrom shadowImporterDir)

    -- With the entry file named bare, the project root and the importing
    -- file's directory are the same directory, so the root tier and the
    -- importer-relative tier probe ONE file. The warning listed it twice, once
    -- as [chosen] and once as [shadowed], which reads as a copy shadowing itself.
    it "the shadow warning lists a copy once when two tiers name the same file" $ do
      Output code sout serr <- checkFrom shadowSiblingDir
      case code of
        ExitSuccess -> pure ()
        ExitFailure n -> expectationFailure $
          "Expected the project-local prelude override to win, but l4 exited "
          ++ show n ++ "\n--- stdout ---\n" ++ sout ++ "\n--- stderr ---\n" ++ serr
      serr `shouldSatisfy` ("Multiple differing copies of module `prelude`" `isInfixOf`)
      -- Two copies are visible, the project's prelude.l4 and the embedded
      -- stdlib: two rows, the first chosen and the second shadowed.
      let rows = [ l | l <- lines serr, "  [chosen]" `isPrefixOf` l || "  [shadowed]" `isPrefixOf` l ]
      map (takeWhile (/= ']')) rows `shouldBe` ["  [chosen", "  [shadowed"]
      length (filter ("prelude.l4" `isInfixOf`) rows) `shouldBe` 1

    -- Two rules resolve every IMPORT: the one that collects parser hints
    -- (GetMixfixRegistry) and the one that collects typecheck dependencies
    -- (GetImports). Each used to log "Module not found" at Warning, so one
    -- mistake printed two warnings, and both landed in `--json` diagnostics.
    it "warns once about an unresolved import, not once per rule that resolves it" $ do
      tmp <- getTemporaryDirectory
      let work    = tmp </> "l4-import-missing-warns-once"
          warning = "Module not found: zz no such module"
          occurrences needle hay = length (filter (needle `isPrefixOf`) (tails hay))
      removePathForcibly work
      createDirectoryIfMissing True work
      writeFile (work </> "importer.l4") "IMPORT `zz no such module`\n"
      let runIn args = runL4EmbeddedOnlyIn (Just work) bin args
      Output _ _ serr <- runIn ["check", "importer.l4"]
      occurrences warning serr `shouldBe` 1
      -- `l4 check --json` and `l4 run --json` carry the Warning lines in
      -- `diagnostics`; each must carry this one once.
      Output _ checkJson _ <- runIn ["check", "--json", "importer.l4"]
      occurrences warning checkJson `shouldBe` 1
      Output _ runJson _ <- runIn ["run", "--json", "importer.l4"]
      occurrences warning runJson `shouldBe` 1
      -- Positive control: `l4 ast` never typechecks, so the rule that collects
      -- dependencies never runs and the parser-hint rule is the only one that
      -- tells you. One warning must not become none.
      Output _ _ astErr <- runIn ["ast", "importer.l4"]
      occurrences warning astErr `shouldBe` 1
      removePathForcibly work

  buildVersionSpec bin
  buildIdentitySpec

-- | Run one row through @l4 batch@ and return its result, failing the test
-- unless the row's status is @success@.
batchAnswer :: FilePath -> FilePath -> FilePath -> String -> IO Value
batchAnswer bin file inputs entry = do
  Output code sout serr <- runL4 bin ["batch", file, "-i", inputs, "-e", entry]
  unless (code == ExitSuccess) $
    expectationFailure ("l4 batch exited " ++ show code ++ "\nstdout:\n" ++ sout ++ "\nstderr:\n" ++ serr)
  row <- case lines sout of
    (l : _) -> either (\err -> expectationFailure ("NDJSON parse failed: " ++ err ++ "\n" ++ l) >> error "unreachable")
                      pure (eitherDecode (BSL8.pack l))
    []      -> expectationFailure "l4 batch printed no rows" >> error "unreachable"
  objField row "status" `shouldBe` Just (String "success")
  case objField row "output" of
    Just (Array outs) | (o : _) <- foldr (:) [] outs, Just r <- objField o "result" -> pure r
    other -> expectationFailure ("no result in batch output: " ++ show other) >> error "unreachable"

----------------------------------------------------------------------------
-- The line that names a build
----------------------------------------------------------------------------

-- | Files the build-identity tests need, relative to @jl4/@.
buildIdentityScript, buildIdentityPackageJson :: FilePath
buildIdentityScript      = "../etc/build-identity.sh"
buildIdentityPackageJson = "../ts-apps/vscode/package.json"

-- | No white space at either end, and any run of it inside a single space: how
-- the renderer treats each part, so a value with a line break in it still gives
-- one line.
buildOneLine :: String -> String
buildOneLine = unwords . words

-- | The line this build should print, when the variables it was built with are
-- in the environment of the test run: the release, then the branch (@unknown@
-- if none), the first seven characters of the commit and the date in brackets,
-- with the commit and the date left out when empty. 'Nothing' when there is no
-- release, and the build is a @dev@ build.
--
-- This restates the format of @LSP.L4.BuildInfo.renderBuildInfo@ on purpose, so
-- that the test does not use the code it checks.
buildExpectedFromEnvironment :: IO (Maybe String)
buildExpectedFromEnvironment = do
  release <- buildOneLine . fromMaybe "" <$> lookupEnv "L4_BUILD_RELEASE"
  branch <- buildOneLine . fromMaybe "" <$> lookupEnv "L4_BUILD_BRANCH"
  commit <- buildOneLine . fromMaybe "" <$> lookupEnv "L4_BUILD_COMMIT"
  date <- buildOneLine . fromMaybe "" <$> lookupEnv "L4_BUILD_DATE"
  let details = (if null branch then "unknown" else branch) : filter (not . null) [take 7 commit, date]
  pure $
    if null release
      then Nothing
      else Just (release ++ " (" ++ intercalate ", " details ++ ")")

-- | Find the @jl4-lsp@ binary: @JL4_LSP_BIN@, else the one Cabal built for this
-- test suite (@build-tool-depends@ makes sure it is built).
locateLspBinary :: IO (Maybe FilePath)
locateLspBinary = do
  fromEnv <- lookupEnv "JL4_LSP_BIN"
  case fromEnv of
    Just p -> do
      ok <- doesFileExist p
      if ok then Just <$> makeAbsolute p else pure Nothing
    Nothing -> do
      (code, out, _err) <- readCreateProcessWithExitCode (proc "cabal" ["list-bin", "exe:jl4-lsp"]) ""
      let path = reverse (dropWhile Char.isSpace (reverse (dropWhile Char.isSpace out)))
      ok <- if code == ExitSuccess then doesFileExist path else pure False
      if ok then Just <$> makeAbsolute path else pure Nothing

-- | One @Content-Length@-framed LSP message from a handle, or 'Nothing' at end
-- of input.
readLspMessage :: Handle -> IO (Maybe BS.ByteString)
readLspMessage h = go BS.empty
  where
    go acc
      | "\r\n\r\n" `BS.isSuffixOf` acc = body acc
      | otherwise = do
          c <- BS.hGet h 1
          if BS.null c then pure Nothing else go (acc <> c)
    body header =
      case [ BS8.readInt (BS8.dropWhile Char.isSpace (BS.drop 1 (BS8.dropWhile (/= ':') l)))
           | l <- BS8.lines header, "content-length" `BS.isPrefixOf` BS8.map toLowerAscii l ] of
        Just (n, _) : _ -> Just <$> BS.hGet h n
        _ -> pure Nothing
    toLowerAscii c = if c >= 'A' && c <= 'Z' then toEnum (fromEnum c + 32) else c

-- | Start @jl4-lsp@, send it @initialize@, and give back its answer and
-- everything it wrote to stderr up to being stopped. 'Nothing' for the answer if
-- none came within a minute.
initializeLspServer :: FilePath -> IO (Maybe Value, String)
initializeLspServer lsp = do
  (Just hin, Just hout, Just herr, ph) <-
    createProcess (proc lsp []) {std_in = CreatePipe, std_out = CreatePipe, std_err = CreatePipe}
  mapM_ (`hSetBinaryMode` True) [hin, hout, herr]
  errVar <- newEmptyMVar
  _ <- forkIO (BS.hGetContents herr >>= putMVar errVar)
  let request = BS8.pack "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"processId\":null,\"rootUri\":null,\"capabilities\":{}}}"
  BS.hPut hin (BS8.pack ("Content-Length: " ++ show (BS.length request) ++ "\r\n\r\n") <> request)
  hFlush hin
  answered <- timeout 60000000 (readLspMessage hout)
  terminateProcess ph
  void (waitForProcess ph)
  _ <- try (hClose hin) :: IO (Either IOException ())
  errBytes <- takeMVar errVar
  pure
    ( case answered of
        Just (Just msg) -> Aeson.decode (BSL8.fromStrict msg)
        _ -> Nothing
    , T.unpack (TE.decodeUtf8Lenient errBytes)
    )

-- | The line a binary must print for @--version@: exactly what
-- 'buildExpectedFromEnvironment' says, or @dev@ when the environment names no
-- release. Windows ends a line with carriage return and line feed, so the
-- carriage returns are dropped first.
checkVersionLine :: Maybe String -> String -> Expectation
checkVersionLine expected sout =
  filter (/= '\r') sout `shouldBe` fromMaybe "dev" expected ++ "\n"

-- | Black-box tests for the line that names a build (@LSP.L4.BuildInfo@):
-- @l4 --version@, @jl4-lsp --version@, the language server's @serverInfo@ and
-- its start-up log line.
--
-- What a binary prints is fixed when it is compiled, so these tests cannot set
-- it. They compare it with the variables that are in the environment of the
-- test run. The release workflow (@main-tag.yml@) writes the variables for the
-- build step and the test step alike, so there the test fails if the bake did
-- not take: a release binary that says @dev@, or says the wrong release. Without
-- the variables the binary must say @dev@.
buildVersionSpec :: FilePath -> Spec
buildVersionSpec bin = describe "the line that names a build" $ do
  mLsp <- runIO locateLspBinary
  let withLsp act = maybe (pendingWith "no jl4-lsp binary (set JL4_LSP_BIN, or run under cabal test)") act mLsp

  describe "l4 --version" $ do
    it "prints one line naming the build, and nothing else, and succeeds" $ do
      expected <- buildExpectedFromEnvironment
      Output code sout serr <- runL4 bin ["--version"]
      code `shouldBe` ExitSuccess
      filter (/= '\r') serr `shouldBe` ""
      checkVersionLine expected sout

    it "is listed in l4 --help" $ do
      Output _ sout _ <- runL4 bin ["--help"]
      sout `shouldSatisfy` ("--version" `isInfixOf`)

  describe "jl4-lsp --version" $ do
    it "prints the line l4 --version prints" $ withLsp \lsp -> do
      expected <- buildExpectedFromEnvironment
      Output code sout serr <- runL4 lsp ["--version"]
      code `shouldBe` ExitSuccess
      filter (/= '\r') serr `shouldBe` ""
      checkVersionLine expected sout
      Output _ l4Out _ <- runL4 bin ["--version"]
      sout `shouldBe` l4Out

  describe "the language server" $ do
    it "reports the line as serverInfo, and logs it when it starts" $ withLsp \lsp -> do
      expected <- buildExpectedFromEnvironment
      (answer, stderrText) <- initializeLspServer lsp
      let line = fromMaybe "dev" expected
          serverInfo = answer >>= (`objField` "result") >>= (`objField` "serverInfo")
      fmap (`objField` "name") serverInfo `shouldBe` Just (Just (String "jl4-lsp"))
      fmap (`objField` "version") serverInfo `shouldBe` Just (Just (String (T.pack line)))
      stderrText `shouldSatisfy` (("| Info | jl4-lsp " ++ line) `isInfixOf`)

-- | Tests for @etc/build-identity.sh@, which the release workflow
-- (@main-tag.yml@) runs to write the variables that @LSP.L4.BuildInfo@ bakes
-- into @l4@ and @jl4-lsp@. What the binaries print is tested in
-- 'buildVersionSpec'.
buildIdentitySpec :: Spec
buildIdentitySpec = describe "etc/build-identity.sh" $ do
  let posixOnly act
        | Info.os == "mingw32" = pendingWith "needs a POSIX shell; the release workflow runs it on Windows under Git Bash"
        | otherwise = act
      -- The parent's environment, less the three variables a workflow run sets
      -- (CI has them), plus the ones the case gives.
      runScript set = do
        parent <- getEnvironment
        let inherited = [kv | kv@(k, _) <- parent, k `notElem` ["GITHUB_RUN_NUMBER", "GITHUB_SHA", "GITHUB_REF_NAME"]]
        readCreateProcessWithExitCode (proc "bash" [buildIdentityScript]) {env = Just (inherited ++ set)} ""
      sha = "0123456789abcdef0123456789abcdef01234567"
      datePrefix = "L4_BUILD_DATE=" :: String
      isDate d = length d == 10 && all isDigit (take 4 d) && d !! 4 == '-' && all isDigit (take 2 (drop 5 d))
                   && d !! 7 == '-' && all isDigit (drop 8 d)

  it "prints the release, the first seven characters of the commit, and today, one VAR=value per line" $ posixOnly $ do
    (code, out, _) <- runScript [("GITHUB_RUN_NUMBER", "91"), ("GITHUB_SHA", sha), ("GITHUB_REF_NAME", "main")]
    code `shouldBe` ExitSuccess
    package <- BS.readFile buildIdentityPackageJson
    let version = case Aeson.decodeStrict package >>= (`objField` "version") of
          Just (String v) -> T.unpack v
          _ -> ""
        majorMinor = reverse (drop 1 (dropWhile (/= '.') (reverse version)))
    version `shouldSatisfy` (not . null)
    case lines out of
      [r, b, c, d] -> do
        r `shouldBe` "L4_BUILD_RELEASE=" ++ majorMinor ++ ".91"
        b `shouldBe` "L4_BUILD_BRANCH=main"
        c `shouldBe` "L4_BUILD_COMMIT=0123456"
        d `shouldSatisfy` isPrefixOf datePrefix
        drop (length datePrefix) d `shouldSatisfy` isDate
      other -> expectationFailure ("expected four lines, got " ++ show other)

  it "names the branch the workflow ran on, whatever it is called" $ posixOnly $ do
    (code, out, _) <- runScript [("GITHUB_RUN_NUMBER", "91"), ("GITHUB_SHA", sha), ("GITHUB_REF_NAME", "feature/x")]
    code `shouldBe` ExitSuccess
    lines out `shouldSatisfy` ("L4_BUILD_BRANCH=feature/x" `elem`)

  it "says unknown when the workflow gave no branch, and does not ask Git" $ posixOnly $ do
    (code, out, _) <- runScript [("GITHUB_RUN_NUMBER", "91"), ("GITHUB_SHA", sha)]
    code `shouldBe` ExitSuccess
    lines out `shouldSatisfy` ("L4_BUILD_BRANCH=unknown" `elem`)

  it "refuses to print anything without a run number, so a local run cannot pass for a release" $ posixOnly $ do
    (code, out, err) <- runScript [("GITHUB_SHA", sha)]
    code `shouldSatisfy` (/= ExitSuccess)
    out `shouldBe` ""
    err `shouldSatisfy` ("GITHUB_RUN_NUMBER" `isInfixOf`)

  it "refuses to print anything without a commit" $ posixOnly $ do
    (code, out, err) <- runScript [("GITHUB_RUN_NUMBER", "91")]
    code `shouldSatisfy` (/= ExitSuccess)
    out `shouldBe` ""
    err `shouldSatisfy` ("GITHUB_SHA" `isInfixOf`)
