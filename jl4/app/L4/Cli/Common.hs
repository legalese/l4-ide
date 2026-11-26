{-# LANGUAGE NamedFieldPuns #-}

-- | Shared helpers for the l4 CLI subcommands.
--
-- Everything here is neutral to a specific command so individual
-- @L4.Cli.*@ modules stay narrow and readable.
module L4.Cli.Common
  ( -- * Shared options
    FixedNowOpt(..)
  , fixedNowParser
  , parseFixedNowText
  , EvalLimits(..)
  , evalLimitsParser
  , evalLimitsParserNoting
  , withEvalLimits
  , guardRunStop
  , langTagReader
  , langOption

    -- * Evaluation config
  , makeEvalConfig
  , makeRunEvalConfig
  , makeTracePolicyForEval
  , makeTracePolicyForRun
  , makeTracePolicyForTrace

    -- * Running the LSP pipeline
  , runOneshot
  , runOneshotWithDiagnostics
  , runOneshotVerbose
  , hasBlockingError
  , transitiveDeps
  , dedupModules

    -- * Rendering
  , TraceTextMode(..)
  , traceTextModeReader
  , renderTraceTextMode
  , renderEvalOutput
  , renderEvalValue
  , indentBlockText

    -- * GraphViz format
  , GraphVizFormat(..)
  , graphVizFormatReader
  , graphVizFormatExt
  , graphVizFormatToTraceFormat

    -- * Diagnostics output
  , putDiagnostics
  , diagnosticsToJson
  ) where

import Base.Text (Text)
import qualified Base.Text as Text
import qualified Data.Aeson as Aeson
import Data.Maybe (catMaybes)
import Data.IORef (readIORef)
import Data.Time (UTCTime)
import Options.Applicative (ReadM, eitherReader, long, metavar, help, option, optional)
import qualified Options.Applicative as Options
import System.IO (hPutStrLn, stderr)
import Control.Exception (throwIO, try)
import System.Exit (ExitCode, exitFailure)
import Control.Applicative ((<|>))

import LSP.Core.Types.Diagnostics (FileDiagnostic(..))
import LSP.L4.BlockingErrors (hasBlockingError)
import LSP.L4.Oneshot (oneshotL4Action)
import qualified LSP.L4.Oneshot as Oneshot
import LSP.Logger
  ( Priority(..)
  , Recorder
  , WithPriority(..)
  , cfilter
  , makeKeyedRefRecorder
  , pretty
  )
import Language.LSP.Protocol.Types (NormalizedFilePath)
import Development.IDE.Graph (Action)

import L4.Lexer (LangTag(..), isLangTagChar)
import qualified LSP.L4.Rules as Rules
import L4.Syntax (Module (..), Resolved)
import qualified Data.List as List
import L4.EvaluateLazy
  ( EvalConfig(..)
  , EvalDirectiveResult(..)
  , EvalDirectiveValue(..)
  , AssertionOutcome(..)
  , ReductionOutcome(..)
  , parseFixedNow
  , prettyAssertionOutcome
  , prettyReductionOutcome
  , prettyLedger
  , readFixedNowEnv
  , resolveEvalConfig
  , EvalLimits(..)
  , applyEvalLimits
  , withRunStop
  )
import L4.EvaluateLazy.Exceptions (EvalException (..), UserEvalException (..), maximumClosureApplications, maximumOpenObligations, maximumTracedClosureApplications, prettyEvalException)
import qualified L4.EvaluateLazy.GraphViz2 as GraphViz2
import L4.Parser.SrcSpan (prettySrcRange, prettySrcRangeM)
import L4.Print (prettyLayout)
import qualified L4.TracePolicy as TracePolicy
import L4.TracePolicy
  ( TraceDestination(..)
  , TraceLevel(..)
  , TraceOptions(..)
  , TracePolicy(..)
  )

----------------------------------------------------------------------------
-- Shared options
----------------------------------------------------------------------------

newtype FixedNowOpt = FixedNowOpt { unFixedNow :: Maybe UTCTime }

parseFixedNowText :: String -> Either String UTCTime
parseFixedNowText s =
  maybe
    (Left "Unable to parse --fixed-now; expected ISO8601 UTC like 2025-01-31T15:45:30Z")
    Right
    (parseFixedNow (Text.pack s))

fixedNowReader :: ReadM UTCTime
fixedNowReader = eitherReader parseFixedNowText

fixedNowParser :: Options.Parser FixedNowOpt
fixedNowParser = fmap FixedNowOpt $ optional $
  option fixedNowReader
    ( long "fixed-now"
    <> metavar "ISO8601"
    <> help "Pin evaluation clock (e.g. 2025-01-31T15:45:30Z) so NOW/TODAY stay deterministic"
    )

-- | The limits on evaluation that every @l4@ command that evaluates takes
-- (smucclaw/l4-ide#1075: ruling L2 of the Recursion Limits bench for @l4
-- run@ and @l4 batch@, Meng's ruling of 2026-11-21 for @l4 trace@, @l4 lts@, @l4 explore@,
-- @l4 coverage@, @l4 prove@ and @l4 verify@). The REPL takes the same
-- flags from its own copy of this parser (@jl4-repl/app/Main.hs@), which is
-- kept in step with this one.
--
-- The two counts are on by default ('L4.EvaluateLazy.withCountedBudgets'):
-- they count what the machine does, so they stop the same program at the
-- same place on every machine, and an evaluation that goes over one is an
-- error on that one alone; the others still answer. A flag changes either
-- one, and @none@ turns it off.
--
-- Time and memory are off unless asked for, named as jl4-service names its
-- own, and neither is deterministic. An evaluation that goes over one stops
-- the run: it is an error naming the limit, and nothing after it is
-- evaluated.
evalLimitsParser :: Options.Parser EvalLimits
evalLimitsParser = evalLimitsParserNoting ""

-- | 'evalLimitsParser', with a sentence added to @--max-steps@'s help, for a
-- command with another flag that a reader could take for it (@l4 lts
-- --steps@, the step log).
evalLimitsParserNoting :: String -> Options.Parser EvalLimits
evalLimitsParserNoting stepsNote = EvalLimits
  <$> optional (option countReader
        ( long "max-open"
        <> metavar "N|none"
        <> help ("Stop any one evaluation (an #EVAL, #ASSERT or #TRACE, or one input or trace the command tries) that has more than N obligations open at once, or joins more than N failures into one breach, as an error on that one (default "
                 <> show maximumOpenObligations <> "; none: no limit)")
        ))
  <*> optional (option countReader
        ( long "max-steps"
        <> metavar "N|none"
        <> help ("Stop any one evaluation that takes more than N steps, counting each function applied and each contract handed the events, as an error on that one" <> stepsNote <> " (default "
                 <> show maximumClosureApplications <> ", and " <> show maximumTracedClosureApplications <> " for one that collects a trace, such as an #EVALTRACE, which keeps a record of every step; this sets both, and none removes both)")
        ))
  <*> optional (option positiveIntReader
        ( long "eval-timeout"
        <> metavar "SECONDS"
        <> help "Stop the run when any one evaluation runs longer than SECONDS of wall-clock time; nothing after it is evaluated"
        ))
  <*> optional (option positiveIntReader
        ( long "max-eval-memory-mb"
        <> metavar "MB"
        <> help "Stop the run when any one evaluation allocates more than MB megabytes (every byte allocated, not only what is kept); nothing after it is evaluated"
        ))
  where
    positiveIntReader = eitherReader \ input -> case reads input of
      [(n, "")] | n > (0 :: Int) -> Right n
      _ -> Left ("expected a whole number above 0, got " <> show input)
    countReader = eitherReader \ case
      "none" -> Right Nothing
      input -> case reads input of
        [(n, "")] | n > (0 :: Int) -> Right (Just n)
        _ -> Left ("expected a whole number above 0, or none, got " <> show input)

-- | The limits one invocation of an @l4@ command evaluates under: the
-- counted budgets at their defaults, then whatever the flags say, and one
-- run stop for the whole invocation ('withRunStop').
withEvalLimits :: EvalLimits -> EvalConfig -> IO EvalConfig
withEvalLimits lims cfg = withRunStop (applyEvalLimits lims cfg)

-- | Do a command's work under its configuration's run stop, and when a time
-- or memory limit stopped the run, say so on the error output, naming the
-- limit and where (L2, which Meng extended to every command that evaluates
-- on 2026-11-21), and fail, whatever the work's own exit. A command that
-- evaluates many inputs or traces reports each one after the stop as not
-- evaluated; this is what says why, and makes sure the command does not
-- exit 0 on an answer that was cut short (decided by Claude 2026-11-21,
-- pending Meng's review: L2 extension, choice 2).
guardRunStop :: Text -> EvalConfig -> IO a -> IO a
guardRunStop command cfg work = do
  outcome <- try @ExitCode work
  stopped <- maybe (pure Nothing) readIORef cfg.runStop
  case stopped of
    Just (b, at) -> do
      hPutStrLn stderr $ Text.unpack $
        command <> ": " <> prettySrcRangeM at <> ": "
          <> Text.unwords (prettyEvalException (UserEvalException (OverBudget b)))
      exitFailure
    Nothing -> either throwIO pure outcome

-- | Read a @--lang@ value into a 'LangTag'.
--
-- __Validated, because the value reaches markup.__ @l4 render --format html@
-- puts it in @\<html lang="…"\>@ and the AKN writer puts it in an FRBR URI, so
-- an unreadable value is an unreadable document rather than a rendering that
-- merely falls back. The module-side spelling of the same thing has always been
-- validated — the lexer restricts @\@lang@ to 'isLangTagChar' — and this closes
-- the asymmetry the flag had against it.
--
-- Two normalisations, both silent because both are BCP 47 saying the same tag:
--
--   * __surrounding whitespace is trimmed__. @--lang 'he '@ used to label the
--     document @he @ and then lose @dir="rtl"@, because the direction lookup
--     compared @"he "@ against the table and missed — a Hebrew document laid out
--     left to right, exit 0, no diagnostic. A trailing space out of a shell
--     variable or a spreadsheet column is how that arrives.
--   * __the primary subtag is lowercased__, which is its conventional form
--     (@he-IL@, not @HE-IL@). Nothing else is re-cased: canonicalising the
--     script and region too would be inventing a tag the user did not type.
--     This also makes @--lang HE@ SELECT the @\@nlg:he@ renderings, which it did
--     not before — rendering selection compares tags exactly.
--
-- Rejected: empty or all-whitespace, anything outside @[A-Za-z0-9-]@, and any tag
-- whose @-@-separated subtags are not each one to eight characters — which covers
-- a leading, trailing or doubled hyphen (@-he@, @he-@, @he--IL@) and an
-- over-long subtag, because BCP 47 spells every subtag @1*8alphanum@.
--
-- __That is a shape check, not a grammar.__ It does not know which subtags are
-- registered, nor that a script sits before a region; @xx-Qrst@ passes. The line
-- is drawn at "could this be a language tag at all", because the point is to keep
-- an unreadable value out of an attribute, not to validate against the IANA
-- registry — which would mean vendoring it.
langTagReader :: ReadM LangTag
langTagReader = eitherReader \input ->
  let tag             = Text.strip (Text.pack input)
      subtags         = Text.splitOn "-" tag
      (primary, rest) = Text.break (== '-') tag
      bad why = Left $ "Invalid --lang value " <> show input <> ": " <> why
                     <> " (expected a BCP 47 language tag, e.g. he, he-IL, az-Arab)"
  in if Text.null tag
       then bad "empty"
     else if not (Text.all isLangTagChar tag)
       then bad "only letters, digits and '-' are allowed"
     else if any (\ st -> Text.null st || Text.length st > 8) subtags
       then bad "each '-'-separated subtag must be 1 to 8 characters"
     else Right (MkLangTag (Text.toLower primary <> rest))

-- | The @--lang@ option itself, so that every verb that takes one takes the
-- same one. @help@ differs between verbs only in what it calls the output.
langOption :: String -> Options.Parser (Maybe LangTag)
langOption what = optional $
  option langTagReader
    ( long "lang"
   <> metavar "SUBTAG"
   <> help ("Render using the @nlg:SUBTAG annotations, e.g. --lang he. A "
         <> what <> " with no rendering in that language falls back to its "
         <> "default one, so a partial translation still produces a whole document.")
    )

----------------------------------------------------------------------------
-- Evaluation config
----------------------------------------------------------------------------

-- | Build an `EvalConfig` honoring either the `--fixed-now` flag or the
-- `L4_NOW` environment variable. Use this for the verbs that never print a
-- trace (`check`, `batch`, the exporters); `l4 run` uses 'makeRunEvalConfig'.
makeEvalConfig :: FixedNowOpt -> IO EvalConfig
makeEvalConfig (FixedNowOpt mClock) = do
  envFixed <- readFixedNowEnv
  resolveEvalConfig (mClock <|> envFixed) makeTracePolicyForEval

-- | The `EvalConfig` for `l4 run`. Same clock handling as 'makeEvalConfig';
-- the trace policy follows the @--trace@ mode, see 'makeTracePolicyForRun'.
makeRunEvalConfig :: TraceTextMode -> FixedNowOpt -> IO EvalConfig
makeRunEvalConfig traceMode (FixedNowOpt mClock) = do
  envFixed <- readFixedNowEnv
  resolveEvalConfig (mClock <|> envFixed) (makeTracePolicyForRun traceMode)

-- | No trace for anything: the policy of every verb that prints only results.
makeTracePolicyForEval :: TracePolicy
makeTracePolicyForEval =
  TracePolicy
    { evalDirectiveTrace = NoTrace
    , evaltraceDirectiveTrace = NoTrace
    }

-- | Trace policy used by `l4 run`. Collecting a trace costs time and memory, so
-- it is collected for @#EVALTRACE@ directives only, and only when @--trace@ is
-- @full@. A plain @#EVAL@ (or @#ASSERT@) never collects one, whatever the mode,
-- and keeps its "no trace captured" line.
--
-- The policy is global, not per module. 'LSP.L4.Rules' evaluates every module
-- in the import closure with the one 'EvalConfig', and @l4 run@ prints only the
-- entry module's results, so an @#EVALTRACE@ inside an IMPORTed module is
-- collected and then discarded: its cost is paid and its trace shown nowhere.
-- (Measured on a 100000-step @#EVALTRACE@ in a library: 0.57 s and 205 MB
-- before this policy, 2.59 s and 1.4 GB after.) A policy that depends on the
-- module is the real fix; it is not built.
makeTracePolicyForRun :: TraceTextMode -> TracePolicy
makeTracePolicyForRun = \case
  TraceTextNone -> makeTracePolicyForEval
  TraceTextFull -> TracePolicy.withTextTrace GraphViz2.defaultGraphVizOptions

-- | Trace policy used by `l4 trace`. `#EVAL` stays silent so the user can
-- still author `#EVAL` directives without being drowned in trace output;
-- `#EVALTRACE` directives do emit.
makeTracePolicyForTrace :: GraphVizFormat -> Maybe FilePath -> TracePolicy
makeTracePolicyForTrace fmt outputDir =
  let gvOpts = GraphViz2.GraphVizOptions
        { GraphViz2.includeValues = True
        , GraphViz2.showUnevaluated = True
        , GraphViz2.simplifyTrivial = False
        , GraphViz2.maxDepth = Nothing
        , GraphViz2.collapseFunctionLookups = False
        , GraphViz2.collapseSimplePaths = False
        , GraphViz2.deduplicateBindings = True
        }
      dest = case outputDir of
        Nothing -> Stdout
        Just dir -> FilesOnly dir
      traceFmt = graphVizFormatToTraceFormat fmt
  in TracePolicy
       { evalDirectiveTrace = NoTrace
       , evaltraceDirectiveTrace = CollectTrace (TraceOptions traceFmt dest gvOpts)
       }

----------------------------------------------------------------------------
-- Running the LSP pipeline
----------------------------------------------------------------------------

-- | Run a one-shot Shake action against `fp` and collect both the inner
-- action's result *and* any Warning/Error priority diagnostic lines the
-- LSP rules emitted. Info/Debug chatter (e.g. import-resolution progress)
-- is filtered out so CLI output stays clean — callers that want verbose
-- progress can use 'runOneshotVerbose' with their own recorder.
runOneshot
  :: EvalConfig
  -> FilePath
  -> (NormalizedFilePath -> Action b)
  -> IO ([Text], b)
runOneshot evalConfig fp act = do
  -- Debug-priority messages (very verbose Shake internals) are dropped, and
  -- Info/Warning/Error kept: real parse/type diagnostics come through at Info
  -- priority via the LSP publishDiagnostics hook, so we can't just filter by
  -- priority alone.  We scrub progress chatter out of the rendered Text list
  -- below with `isProgressChatter`.
  (getLog, filteredRec) <- makeCliRecorder
  res <- oneshotL4Action filteredRec evalConfig fp act
  rawErrs <- getLog
  -- Post-filter: drop lines matching known progress-chatter prefixes.
  pure (filter (not . isProgressChatter) rawErrs, res)

-- | Like 'runOneshot', but additionally returns the structured diagnostics
-- published to the Shake store during the run, across every file in the import
-- closure and not just the entry file.
--
-- The rendered @[Text]@ is still returned for display; the @[FileDiagnostic]@
-- is what a caller consults for a verdict that knows severity. An import cycle
-- is the case that needs it: a module on a ring has no typecheck, so a file that
-- imports one is checked without it, and its own result can look successful.
runOneshotWithDiagnostics
  :: EvalConfig
  -> FilePath
  -> (NormalizedFilePath -> Action b)
  -> IO ([Text], [FileDiagnostic], b)
runOneshotWithDiagnostics evalConfig fp act = do
  (getLog, filteredRec) <- makeCliRecorder
  (diags, res) <- Oneshot.oneshotL4ActionWithDiags filteredRec evalConfig fp act
  rawErrs <- getLog
  pure (filter (not . isProgressChatter) rawErrs, diags, res)

-- | The recorder a command collects the pipeline's log with, as text, without
-- its Debug-priority messages.
--
-- With no editor to publish to, the pipeline logs every diagnostic of a file
-- each time that file's diagnostics change ('Shake.LogDiagsDiffButNoLspEnv'),
-- so a command that printed the log printed each diagnostic once for every
-- later change to its file's diagnostics: @l4 run@ printed a type checker's
-- warning three times and an error of the export check twice, and @l4 check@
-- a type checker's warning twice (review of #779, 2026-11-21). Each list
-- holds all of the file's diagnostics, so only the last one of each file is
-- kept, where it falls in the log ('Oneshot.latestDiagnostics'); it is printed as it
-- was.
makeCliRecorder :: IO (IO [Text], Recorder (WithPriority Oneshot.Log))
makeCliRecorder = do
  (getLog, refRecorder) <- makeKeyedRefRecorder Oneshot.diagnosticsOf pretty
  let keep wp = wp.priority /= Debug
  pure (Oneshot.latestDiagnostics <$> getLog, cfilter keep refRecorder)

-- 'hasBlockingError' (re-exported) is the rule for whether a diagnostics set
-- should make a CLI command exit non-zero. It lives in jl4-lsp so that the
-- editor's Deploy buttons refuse exactly what @l4 check@ and @l4 deploy@ do.
-- It leaves out the evaluator's diagnostics (source @\"eval\"@), so that it
-- speaks only about structural diagnostics and stays usable by commands that
-- never evaluate (notably @l4 check@).
--
-- That exclusion is NOT the whole exit-code contract for @l4 run@. Ruled by
-- Meng 2026-08-01: a @#EVAL@ that CRASHES during evaluation must be loud — it
-- exits non-zero; ruled 2026-09-29: so must an @#ASSERT@ that evaluates to
-- false. @l4 run@ therefore applies its own check on the directive results
-- ('L4.Cli.Run.evalDirectiveFailsRun') in addition to calling this predicate.
--
-- If silencing is ever wanted, add a @-q@ \/ @--quiet-eval@ option to @l4 run@
-- that restores exit 0 for a crashed directive — rather than flipping the
-- default back.

-- | Returns True for rendered log lines that represent internal
-- bookkeeping (import resolution, VFS lookups, Shake db progress) rather
-- than user-facing diagnostics.
--
-- The rendered format puts priority + content inline, e.g.
-- @"Info | [Import Resolution] Found on filesystem: ..."@, so we look
-- past the @"Priority | "@ prefix.
--
-- Import-resolution lines at Warning/Error priority are NOT chatter: they
-- carry the library-shadow warning (multiple differing copies of a module
-- visible; see specs/as-built/import-resolution.md) and module-not-found notices,
-- which a CLI user must see.
isProgressChatter :: Text -> Bool
isProgressChatter txt =
  let (mPriority, body) = splitPriorityPrefix txt
      starts p = p `Text.isPrefixOf` body
      warningOrWorse = mPriority `elem` [Just "Warning", Just "Error"]
  in  (starts "[Import Resolution]" && not warningOrWorse)
   || starts "[VFS"
   || starts "Ide: Shake"
   || starts "Shake:"
   || starts "Finishing writing Shake database"
   || starts "Opening Shake database"
   || Text.null (Text.strip body)

-- | Split a rendered log line into its priority column (if present) and body.
splitPriorityPrefix :: Text -> (Maybe Text, Text)
splitPriorityPrefix txt =
  case Text.breakOn " | " txt of
    (prio, rest) | not (Text.null rest) -> (Just (Text.strip prio), Text.stripStart (Text.drop 3 rest))
    _                                   -> (Nothing, txt)

-- | Like 'runOneshot', but routes LSP diagnostics through a caller-supplied
-- recorder (e.g. one backed by stderr) and returns only the action's result.
-- Used by @l4 trace@ / @l4 state-graph@ where the caller wants interleaved
-- progress visible.
runOneshotVerbose
  :: Recorder (WithPriority Oneshot.Log)
  -> EvalConfig
  -> FilePath
  -> (NormalizedFilePath -> Action b)
  -> IO b
runOneshotVerbose recorder evalConfig fp act =
  oneshotL4Action recorder evalConfig fp act

----------------------------------------------------------------------------
-- Trace text rendering
----------------------------------------------------------------------------

data TraceTextMode
  = TraceTextNone
  | TraceTextFull
  deriving (Eq, Show)

renderTraceTextMode :: TraceTextMode -> String
renderTraceTextMode = \case
  TraceTextNone -> "none"
  TraceTextFull -> "full"

traceTextModeReader :: ReadM TraceTextMode
traceTextModeReader = eitherReader \input ->
  case Text.toLower (Text.pack input) of
    "none" -> Right TraceTextNone
    "off" -> Right TraceTextNone
    "full" -> Right TraceTextFull
    "text" -> Right TraceTextFull
    "ascii" -> Right TraceTextFull
    other -> Left $ "Invalid trace MODE: " <> Text.unpack other <> " (expected none|full)"

renderEvalOutput :: TraceTextMode -> Int -> EvalDirectiveResult -> Text
renderEvalOutput traceMode idx MkEvalDirectiveResult{range = mRange, result, trace = mTrace, ledger = led, notes = ns} =
  Text.intercalate "\n\n" $ catMaybes
    [ Just headerLine
    , Just ("Result:\n" <> indentBlockText (renderEvalValue result))
    , notesSection
    , ledgerSection
    , traceSection
    ]
  where
    -- what the run reported without failing (an early act, R-X6; an empty
    -- window): dropped when there is nothing, like the ledger
    notesSection = case ns of
      [] -> Nothing
      _  -> Just ("Notes:\n" <> indentBlockText (Text.intercalate "\n" ns))
    headerLine =
      let idxText = Text.pack (show idx)
          rangeText = maybe "" (\rng -> " @ " <> prettySrcRange rng) mRange
      in "Evaluation[" <> idxText <> "]" <> rangeText
    -- STATE-AS-LEDGER M2: surface the ledger this directive produced (the
    -- RECORD/COMMIT/ATTEST writes). 'prettyLedger' returns empty for a directive
    -- that wrote nothing, so we drop the section in that case.
    ledgerSection =
      let body = prettyLedger led
      in if Text.null body then Nothing else Just (Text.dropWhile (== '\n') body)
    traceSection = case traceMode of
      TraceTextNone -> Nothing
      TraceTextFull ->
        let traceBody = case (mTrace, result) of
              (Just t, _) -> prettyLayout t
              -- refused because an earlier directive stopped the run: it
              -- was not evaluated, so there is nothing to trace
              (Nothing, Reduction (ReducedErrored (UserEvalException (NotEvaluated _ _)))) -> "(not evaluated)"
              (Nothing, Assertion (Errored (UserEvalException (NotEvaluated _ _)))) -> "(not evaluated)"
              (Nothing, _) -> "(no trace captured; add #EVALTRACE to the directive)"
        in Just ("Trace:\n" <> indentBlockText traceBody)

renderEvalValue :: EvalDirectiveValue -> Text
renderEvalValue = \case
  Assertion a -> prettyAssertionOutcome a
  Reduction r -> prettyReductionOutcome r

indentBlockText :: Text -> Text
indentBlockText txt =
  let ls = case Text.lines txt of
             [] -> [""]
             xs -> xs
  in Text.unlines (map ("  " <>) ls)

----------------------------------------------------------------------------
-- GraphViz format
----------------------------------------------------------------------------

data GraphVizFormat
  = DotFormat
  | PngFormat
  | SvgFormat
  deriving (Eq, Show)

graphVizFormatExt :: GraphVizFormat -> String
graphVizFormatExt = \case
  DotFormat -> "dot"
  PngFormat -> "png"
  SvgFormat -> "svg"

graphVizFormatReader :: ReadM GraphVizFormat
graphVizFormatReader = eitherReader \input ->
  case Text.toLower (Text.pack input) of
    "dot" -> Right DotFormat
    "png" -> Right PngFormat
    "svg" -> Right SvgFormat
    other -> Left $ "Invalid format: " <> Text.unpack other <> " (expected dot|png|svg)"

graphVizFormatToTraceFormat :: GraphVizFormat -> TracePolicy.TraceFormat
graphVizFormatToTraceFormat = \case
  DotFormat -> TracePolicy.DotFormat
  PngFormat -> TracePolicy.PngFormat
  SvgFormat -> TracePolicy.SvgFormat

----------------------------------------------------------------------------
-- Diagnostic dump helpers
----------------------------------------------------------------------------

-- | Write collected diagnostic lines to stderr, one per line.
putDiagnostics :: [Text] -> IO ()
putDiagnostics = mapM_ (hPutStrLn stderr . Text.unpack)

-- | Convert a list of rendered diagnostic lines to a JSON array of strings.
-- A richer structured-diagnostics shape is a future upgrade; for now the
-- JSON envelope quotes the already-prettified LSP log text.
diagnosticsToJson :: [Text] -> Aeson.Value
diagnosticsToJson = Aeson.toJSON

-- | Every module the checked one reaches through @IMPORT@, transitively, once
-- each, in the order a depth-first walk of the imports first meets it
-- ('Rules.transitiveDependencies'). This used to recurse into each
-- dependency's own list, which is already transitive, so it listed a module
-- once per import path and took time exponential in the depth of the imports
-- (smucclaw\/l4-ide#1008). 'dedupModules' is now a no-op on it.
transitiveDeps :: Rules.TypeCheckResult -> [Module Resolved]
transitiveDeps tc = map (.module') (Rules.transitiveDependencies tc)

dedupModules :: [Module Resolved] -> [Module Resolved]
dedupModules = List.nubBy (\a b -> muri a == muri b)
 where
  muri (MkModule _ u _) = u
