-- | @l4 lint FILE...@ — check that the override phrases a decision's prose
-- carries are honoured by the call graph.
--
-- A decision whose @\@ref@ says "Subject to section 6" must call the decision
-- that encodes section 6, or the encoding answers @TRUE@ where its own opening
-- words do not reach (SUBJECT-TO-NOTWITHSTANDING-SPEC §12.1 and §12.2). This
-- command reads the prose, reads the calls, and reports the mismatches.
--
-- It judges; it never rewrites. Exit status 0 means the lint RAN, not that it
-- found nothing: findings are advice, and a lint that failed a build on a
-- heuristic would be switched off. @--strict@ makes a finding exit 1, for a CI
-- job that has decided to trust it. A file that does not type-check cannot be
-- linted and exits 1 either way.
module L4.Cli.Lint
  ( LintOptions(..)
  , lintOptionsParser
  , lintCmd
  ) where

import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy.Char8 as BSL8
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.Text.IO as TIO
import Options.Applicative
import System.Exit (exitFailure, exitSuccess)
import System.IO (hPutStrLn, stderr)

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
  <$> some (strArgument (metavar "FILE..." <> help "The .l4 files to lint"))
  <*> switch (long "json" <> help "Emit one JSON array of every override mention found, instead of text")
  <*> switch (long "all" <> help "Also list the mentions that raised no finding (wired, target not encoded, open-class, ...)")
  <*> switch (long "strict" <> help "Exit 1 when there is a finding (the default is to report and exit 0)")

----------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------

lintCmd :: LintOptions -> IO ()
lintCmd opts = do
  evalConfig <- makeEvalConfig (FixedNowOpt Nothing)
  let lintOne fp = do
        (errs, mTc) <- runOneshot evalConfig fp \ nfp -> do
          let uri = normalizedFilePathToUri nfp
          _ <- Shake.addVirtualFileFromFS nfp
          Shake.use Rules.SuccessfulTypeCheck uri
        case mTc of
          Just tc | tc.success -> pure (Right (fp, Override.lintModule tc.module'))
          _ -> do
            putDiagnostics errs
            pure (Left fp)
  results <- mapM lintOne opts.lintFiles
  let linted   = [ (fp, fs) | Right (fp, fs) <- results ]
      failed   = [ fp | Left fp <- results ]
      findings = [ (fp, f) | (fp, fs) <- linted, f <- fs, Override.isFinding f.outcome ]
      counts   = Map.fromListWith (+) [ (f.outcome, 1 :: Int) | (_, fs) <- linted, f <- fs ]
  if opts.lintJson
    then BSL8.putStrLn (Aeson.encode [ toJson fp f | (fp, fs) <- linted, f <- fs ])
    else do
      mapM_ (printFile opts) linted
      TIO.putStrLn (summaryLine (length linted) counts)
  mapM_ (\ fp -> hPutStrLn stderr ("l4 lint: could not check " <> fp <> "; it was not linted")) failed
  if not (null failed) || (opts.lintStrict && not (null findings))
    then exitFailure
    else exitSuccess

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

summaryLine :: Int -> Map.Map Override.Outcome Int -> Text.Text
summaryLine nFiles counts =
  "l4 lint: " <> Text.pack (show nFiles) <> " file" <> (if nFiles == 1 then "" else "s")
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
