-- | @l4 lint FILE...@ — check that the override phrases a decision's prose
-- carries are honoured by the call graph.
--
-- A decision whose @\@ref@ says "Subject to section 6" must call the decision
-- that encodes section 6, or the encoding answers @TRUE@ where its own opening
-- words do not reach (SUBJECT-TO-NOTWITHSTANDING-SPEC §12.1 and §12.2). This
-- command reads the prose, reads the calls, and reports the mismatches.
--
-- It judges; it never rewrites. Findings are advice, and a lint that failed a
-- build on a heuristic would be switched off, so the exit status is 0 whenever
-- the lint RAN and found things; @--strict@ makes a finding exit 1, for a CI
-- job that has decided to trust it.
--
-- A file the lint could not check (missing, unreadable, an empty directory, a
-- file that does not type-check) is a different matter: nothing was verified,
-- so a run that reaches such a file exits 1 with or without @--strict@, counts
-- it in the summary, and in @--json@ gives it a record of its own, so that an
-- empty array can never stand for a run that checked nothing.
--
-- Each argument is linted on its own and its result is printed as soon as it
-- is known: one bad argument cannot take the others' results with it. A
-- directory argument stands for the @.l4@ files under it.
module L4.Cli.Lint
  ( LintOptions(..)
  , lintOptionsParser
  , lintCmd
  ) where

import Control.Exception (SomeAsyncException, SomeException, displayException, fromException, throwIO, try)
import Control.Monad (unless, when)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy.Char8 as BSL8
import Data.List (sort)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import qualified Data.Text.IO as TIO
import Options.Applicative
import System.Directory (doesDirectoryExist, doesFileExist, listDirectory)
import System.Exit (ExitCode, exitFailure, exitSuccess)
import System.FilePath (takeExtension, (</>))
import System.IO (hFlush, hPutStrLn, stderr, stdout)

import L4.EvaluateLazy (EvalConfig)
import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import Language.LSP.Protocol.Types (normalizedFilePathToUri)

import L4.Cli.Common
import qualified L4.Lint.Override as Override
import L4.Parser.SrcSpan (SrcPos (..), SrcRange (..))

----------------------------------------------------------------------------
-- Options
----------------------------------------------------------------------------

data LintOptions = LintOptions
  { lintFiles  :: [FilePath]
  , lintJson   :: Bool
  , lintAll    :: Bool
  , lintStrict :: Bool
  }

lintOptionsParser :: Parser LintOptions
lintOptionsParser = LintOptions
  <$> some (strArgument (metavar "FILE..." <> help "The .l4 files to lint; a directory stands for the .l4 files under it"))
  <*> switch (long "json" <> help "Emit one JSON array with a record per override mention found and per file that could not be checked, instead of text")
  <*> switch (long "all" <> help "Also list the mentions that raised no finding (wired, target not encoded, open-class, ...)")
  <*> switch (long "strict" <> help "Exit 1 when there is a finding (the default is to report and exit 0); a file that cannot be checked always exits 1")

----------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------

-- | What became of one file.
data Result
  = Checked FilePath [Override.Finding]
  | Unchecked FilePath Text.Text
    -- ^ the file and why nothing was verified

lintCmd :: LintOptions -> IO ()
lintCmd opts = do
  evalConfig <- makeEvalConfig (FixedNowOpt Nothing)
  targets <- concat <$> mapM expandArgument opts.lintFiles
  emitted <- newIORef (0 :: Int)
  results <- mapM (lintTarget evalConfig opts emitted) targets
  when opts.lintJson do
    n <- readIORef emitted
    putStrLn (if n == 0 then "[]" else "]")
  let linted    = [ fs | Checked _ fs <- results ]
      unchecked = length [ () | Unchecked {} <- results ]
      findings  = [ f | fs <- linted, f <- fs, Override.isFinding f.outcome ]
      counts    = Map.fromListWith (+) [ (f.outcome, 1 :: Int) | fs <- linted, f <- fs ]
  unless opts.lintJson (TIO.putStrLn (summaryLine (length results) unchecked counts))
  hFlush stdout
  if unchecked > 0 || (opts.lintStrict && not (null findings))
    then exitFailure
    else exitSuccess

-- | Lint one target and print what is known about it at once. In @--json@ mode
-- the records are streamed as the elements of one array: the @[@ goes out with
-- the first record and the @]@ at the end, so a run killed half way leaves
-- invalid JSON rather than a short valid array.
lintTarget :: EvalConfig -> LintOptions -> IORef Int -> Either (FilePath, Text.Text) FilePath -> IO Result
lintTarget evalConfig opts emitted target = do
  result <- case target of
    Left (fp, why) -> pure (Unchecked fp why)
    Right fp       -> lintFile evalConfig fp
  case result of
    Unchecked fp why -> hPutStrLn stderr ("l4 lint: could not check " <> fp <> ": " <> Text.unpack why)
    Checked {}       -> pure ()
  if opts.lintJson
    then mapM_ record (recordsOf result)
    else case result of
      Checked fp fs -> printFile opts (fp, fs)
      Unchecked {}  -> pure ()
  hFlush stdout
  pure result
 where
  recordsOf = \case
    Checked fp fs    -> [ toJson fp f | f <- fs ]
    Unchecked fp why -> [ uncheckedJson fp why ]
  record v = do
    n <- atomicModifyIORef' emitted (\k -> (k + 1, k))
    putStr (if n == 0 then "[" else ",")
    BSL8.putStrLn (Aeson.encode v)

-- | The files an argument stands for: itself if it is a file, the @.l4@ files
-- under it (sorted, dot-directories skipped) if it is a directory, and
-- otherwise a reason it cannot be linted.
expandArgument :: FilePath -> IO [Either (FilePath, Text.Text) FilePath]
expandArgument fp = do
  isFile <- doesFileExist fp
  isDir  <- doesDirectoryExist fp
  if isFile then pure [Right fp]
  else if isDir then do
    fs <- l4FilesUnder fp
    pure (if null fs then [Left (fp, "no .l4 files under this directory")] else map Right fs)
  else pure [Left (fp, "no such file or directory")]

l4FilesUnder :: FilePath -> IO [FilePath]
l4FilesUnder dir = do
  names <- sort <$> listDirectory dir
  concat <$> mapM visit [ n | n <- names, take 1 n /= "." ]
 where
  visit n = do
    let p = dir </> n
    isDir <- doesDirectoryExist p
    if isDir then l4FilesUnder p
    else pure [ p | takeExtension p == ".l4" ]

lintFile :: EvalConfig -> FilePath -> IO Result
lintFile evalConfig fp = do
  r <- try (runOneshot evalConfig fp \ nfp -> do
         let uri = normalizedFilePathToUri nfp
         _ <- Shake.addVirtualFileFromFS nfp
         Shake.use Rules.SuccessfulTypeCheck uri)
  case r of
    Right (_, Just tc) | tc.success -> pure (Checked fp (Override.lintModule tc.module'))
    Right (errs, _) -> do
      putDiagnostics errs
      pure (Unchecked fp "does not type-check")
    Left (e :: SomeException)
      | Just (_ :: SomeAsyncException) <- fromException e -> throwIO e
      | Just (_ :: ExitCode) <- fromException e -> throwIO e
      | otherwise -> pure (Unchecked fp (Text.pack (takeWhile (/= '\n') (displayException e))))

----------------------------------------------------------------------------
-- Rendering
----------------------------------------------------------------------------

printFile :: LintOptions -> (FilePath, [Override.Finding]) -> IO ()
printFile opts (fp, fs) =
  mapM_ (TIO.putStrLn . renderFinding fp) (filter keep fs)
 where
  keep f = opts.lintAll || Override.isFinding f.outcome

lineOf :: Override.Finding -> Text.Text
lineOf f = case f.at of
  Just r  -> Text.pack (show r.start.line)
  Nothing -> "?"

renderFinding :: FilePath -> Override.Finding -> Text.Text
renderFinding fp f = Text.unlines (headLine : detail)
 where
  headLine = Text.pack fp <> ":" <> lineOf f <> ": " <> Override.outcomeText f.outcome <> ": `" <> f.decision <> "`"
  said = "\"" <> Override.phraseText f.phrase <> " " <> f.written <> "\""
         <> maybe "" (", i.e. " <>) (relativeAs f.written f.resolved)
  readIn = "read in " <> Text.intercalate ", " (map Override.sourceText f.sources)
  detail = case f.outcome of
    Override.MissingConjunct ->
      [ "    says " <> said <> " (" <> readIn <> ")"
      , "    but its body reaches none of: " <> names f.candidates
      ]
    Override.OverrideUnwired ->
      [ "    says " <> said <> " (" <> readIn <> ")"
      , "    but no call joins it to any of: " <> names f.candidates
      ]
    _ ->
      [ "    " <> said <> " (" <> readIn <> ")"
      ]
  -- a section can have a dozen decisions; the first few are enough to find it
  names ns =
    Text.intercalate ", " [ "`" <> n <> "`" | n <- take 4 ns ]
      <> (if length ns > 4 then " and " <> Text.pack (show (length ns - 4)) <> " more" else "")
  -- "subsection (8)" names no provision until it is read against the
  -- decision's own section; say which one it was read as.
  relativeAs w mr = case mr of
    Just r | " (" `Text.isInfixOf` w -> Just r
    _ -> Nothing

summaryLine :: Int -> Int -> Map.Map Override.Outcome Int -> Text.Text
summaryLine nFiles nUnchecked counts =
  "l4 lint: " <> Text.pack (show nFiles) <> " file" <> (if nFiles == 1 then "" else "s")
    <> (if nUnchecked > 0 then ", " <> Text.pack (show nUnchecked) <> " could not be checked" else "")
    <> "; findings: " <> tally (filter Override.isFinding keys)
    <> "; set aside: " <> tally (filter (not . Override.isFinding) keys)
 where
  keys = Map.keys counts
  tally ks
    | null ks = "none"
    | otherwise = Text.intercalate ", " [ Text.pack (show (Map.findWithDefault 0 k counts)) <> " " <> Override.outcomeText k | k <- ks ]

toJson :: FilePath -> Override.Finding -> Aeson.Value
toJson fp f = Aeson.object
  [ "file"       Aeson..= fp
  , "status"     Aeson..= ("checked" :: Text.Text)
  , "line"       Aeson..= fmap (\ r -> r.start.line) f.at
  , "decision"   Aeson..= f.decision
  , "phrase"     Aeson..= Override.phraseText f.phrase
  , "target"     Aeson..= f.written
  , "resolved"   Aeson..= f.resolved
  , "readIn"     Aeson..= map Override.sourceText f.sources
  , "outcome"    Aeson..= Override.outcomeText f.outcome
  , "finding"    Aeson..= Override.isFinding f.outcome
  , "candidates" Aeson..= f.candidates
  ]

uncheckedJson :: FilePath -> Text.Text -> Aeson.Value
uncheckedJson fp why = Aeson.object
  [ "file"   Aeson..= fp
  , "status" Aeson..= ("unchecked" :: Text.Text)
  , "reason" Aeson..= why
  ]
