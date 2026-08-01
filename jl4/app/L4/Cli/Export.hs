-- | @l4 export --to=dmn|bpmn FILE@ — write an L4 module out in a foreign
-- interchange notation, together with an account of what that notation could
-- not carry.
--
-- Two targets, three artifacts:
--
--   * @--to=dmn@    — DMN 1.3 XML   ('L4.Dmn.Lower' → 'L4.Dmn.Emit')
--   * @--to=dmn-md@ — dmnmd markdown, the same IR through a second emitter
--                     ('L4.Dmn.Markdown'), with its own, different loss list
--   * @--to=bpmn@   — BPMN 2.0 XML  ('L4.StateGraph' → 'L4.Bpmn.Lower' →
--                     'L4.Bpmn.Emit')
--
-- The decision side reads the whole module; the process side reads one
-- regulative rule, because a BPMN document holds one process and
-- 'L4.Bpmn.Emit.renderBpmn' writes its own XML prolog — concatenating two of
-- them is not a well-formed document. Hence @--rule NAME@.
--
-- == Where the fidelity report goes, and why
--
-- The goldens under @jl4\/examples\/{bpmn,dmn}\/expected@ are pairs — @X.bpmn@
-- beside @X.fidelity.txt@ — never one file with the report bolted onto the
-- front. That is the shape this command reproduces:
--
--   * with @--output FILE@, @--fidelity-report@ writes a sibling
--     @FILE@-with-@.fidelity.txt@-extension and says so on stderr;
--   * without @--output@ the artifact owns stdout, so the report goes to
--     __stderr__. @l4 export --to=bpmn f.l4 --fidelity-report > f.bpmn@ must
--     still produce an importable file.
--
-- == The report is never optional, but it is also not an error
--
-- Even without @--fidelity-report@, a one-line tally goes to stderr whenever
-- anything was lost. Shipping output that quietly drops what the source said is
-- the defect both exporters were fixed for, and a flag you have to know about
-- is not a fix.
--
-- What this deliberately does __not__ do is exit non-zero on a @Blocking@ note.
-- @Blocking@ in "L4.Interchange.Fidelity" means /the target notation cannot
-- express this at all, so a fallback was emitted/ — a statement about DMN and
-- BPMN, not about this file. It is the ordinary case, not the exceptional one:
-- every one of the four shipped exhibits has @Blocking@ notes (@F1@ fires for
-- every task in every BPMN export, because MUST\/MAY\/SHANT all draw as a task;
-- @D-LITERALEXPR@ fires for any decision that is a formula rather than a
-- table). A gate on @Blocking@ would therefore fail 100% of exports, including
-- the three files the BPMN README tells you to open in Camunda Modeler, and a
-- check that always fires teaches nobody anything.
--
-- The exit code is instead opt-in and graduated: @--fail-on=blocking|lossy|
-- advisory@ for a pipeline that wants a gate, @none@ (the default) otherwise.
-- Genuine failures — the file does not typecheck, the rule does not exist,
-- there is nothing of that kind in the module to export — exit non-zero
-- regardless.
module L4.Cli.Export
  ( ExportOptions (..)
  , ExportTarget (..)
  , FidelityGate (..)
  , exportOptionsParser
  , exportCmd
  ) where

import Base
import qualified Base.Text as Text
import Control.Exception (SomeException, try)
import qualified Base.Set as Set
import Options.Applicative
import System.Directory (doesDirectoryExist, listDirectory)
import System.Exit (exitFailure, exitSuccess)
import System.FilePath (replaceExtension, takeBaseName, takeDirectory, takeExtension, (</>))

import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import Language.LSP.Protocol.Types (normalizedFilePathToUri)

import L4.Bpmn.Emit (renderBpmn)
import L4.Bpmn.IR (BpmnExport (..), BpmnOptions (..), DeadlineUnitPolicy (..))
import L4.Bpmn.Lower (stateGraphToBpmn)
import L4.Dmn.Emit (emitDrg)
import L4.Dmn.IR (DmnFlavor (..), defaultDmnFlavor, dmnReport, drgDecisions)
import L4.Dmn.Lower (DmnLowerOptions (..), lowerModule, moduleTitle, resolveMaybePredicates)
import L4.Dmn.Markdown (emitMarkdown, markdownReport)
import L4.Annotation (rangeOf)
import L4.Interchange.Fidelity
  (FidelityNote (..), FidelityReport (..), FidelitySeverity (..), renderReport)
import L4.StateGraph (StateGraph (..), extractStateGraphs)
import L4.Syntax
import qualified L4.TypeCheck as TC

import L4.Cli.Common

----------------------------------------------------------------------------
-- Options
----------------------------------------------------------------------------

-- | Which interchange notation to write.
data ExportTarget
  = TargetDmn
    -- ^ DMN 1.3 XML
  | TargetDmnMarkdown
    -- ^ dmnmd markdown: the same 'L4.Dmn.IR.Drg', a second emitter, a
    -- different loss list. Kept on the same @--to@ axis rather than behind a
    -- separate flag because it is a target, not a formatting option.
  | TargetBpmn
    -- ^ BPMN 2.0 XML
  deriving stock (Eq, Show)

-- | How severe a fidelity note has to be before the command exits non-zero.
data FidelityGate
  = GateNever
  | GateBlocking
  | GateLossy
  | GateAdvisory
  deriving stock (Eq, Show)

data ExportOptions = ExportOptions
  { exportFile         :: FilePath
  , exportTarget       :: ExportTarget
  , exportOutput       :: Maybe FilePath
  , exportFidelity     :: Bool
  , exportRule         :: Maybe Text
  , exportModelName    :: Maybe Text
  , exportFlavor       :: Maybe DmnFlavor
  , exportDeadlineUnit :: Maybe DeadlineUnitPolicy
  , exportFailOn       :: FidelityGate
  , exportIncludeTests :: Bool
  }

exportTargetReader :: ReadM ExportTarget
exportTargetReader = eitherReader \input ->
  case Text.toLower (Text.pack input) of
    "dmn"      -> Right TargetDmn
    "dmn-md"   -> Right TargetDmnMarkdown
    "dmnmd"    -> Right TargetDmnMarkdown
    "bpmn"     -> Right TargetBpmn
    other      -> Left $
      "Invalid export target: " <> Text.unpack other
        <> " (expected dmn|dmn-md|bpmn)"

-- | @drools@ is accepted as a synonym for @kie@ because that is what the engine
-- is called in half its own documentation; @camunda@ means Camunda 8, which is
-- an unrelated implementation to Camunda 7 and the only one of the two that can
-- execute a BKM (see 'DmnFlavor').
dmnFlavorReader :: ReadM DmnFlavor
dmnFlavorReader = eitherReader \input ->
  case Text.toLower (Text.pack input) of
    "camunda" -> Right FlavorCamunda
    "kie"     -> Right FlavorKie
    "drools"  -> Right FlavorKie
    other     -> Left $
      "Invalid --flavor: " <> Text.unpack other <> " (expected camunda|kie)"

deadlineUnitReader :: ReadM DeadlineUnitPolicy
deadlineUnitReader = eitherReader \input ->
  case Text.toLower (Text.pack input) of
    "days"   -> Right AssumeDays
    "day"    -> Right AssumeDays
    "refuse" -> Right RefuseToGuess
    other    -> Left $
      "Invalid --deadline-unit: " <> Text.unpack other <> " (expected days|refuse)"

fidelityGateReader :: ReadM FidelityGate
fidelityGateReader = eitherReader \input ->
  case Text.toLower (Text.pack input) of
    "none"     -> Right GateNever
    "never"    -> Right GateNever
    "blocking" -> Right GateBlocking
    "lossy"    -> Right GateLossy
    "advisory" -> Right GateAdvisory
    "any"      -> Right GateAdvisory
    other      -> Left $
      "Invalid --fail-on: " <> Text.unpack other
        <> " (expected none|blocking|lossy|advisory)"

exportOptionsParser :: Parser ExportOptions
exportOptionsParser = ExportOptions
  <$> strArgument (metavar "FILE" <> help "Path to the .l4 file to export")
  <*> option exportTargetReader
        ( long "to"
       <> metavar "TARGET"
       <> help "Interchange notation: dmn (DMN 1.3 XML) | dmn-md (dmnmd markdown) | bpmn (BPMN 2.0 XML)"
        )
  <*> optional
        ( strOption
            ( long "output"
           <> short 'o'
           <> metavar "FILE"
           <> help "Write the exported document to FILE instead of stdout"
            )
        )
  <*> switch
        ( long "fidelity-report"
       <> help
            "Also emit the full fidelity report: to FILE.fidelity.txt beside --output, \
            \or to stderr when the document goes to stdout. A one-line tally is printed \
            \either way."
        )
  <*> optional
        ( strOption
            ( long "rule"
           <> metavar "NAME"
           <> help "BPMN only: which regulative rule to export (required when the file has more than one)"
            )
        )
  <*> optional
        ( strOption
            ( long "model-name"
           <> metavar "NAME"
           <> help "DMN only: the <definitions> name and namespace seed (default: the module's outermost section heading, else the file's base name)"
            )
        )
  <*> optional
        ( option dmnFlavorReader
            ( long "flavor"
           <> metavar "ENGINE"
           <> showDefaultWith (const "camunda")
           <> help
                "DMN only: which engine to shape the document for. camunda (the default, \
                \= Camunda 8) | kie (= Drools). The two differ on exactly one thing: whether a \
                \<decisionService> may be the target of a <knowledgeRequirement>. Camunda 8 \
                \rejects the whole file at parse() if it is, so that shape is kie-only."
            )
        )
  <*> optional
        ( option deadlineUnitReader
            ( long "deadline-unit"
           <> metavar "POLICY"
           <> showDefaultWith (const "days")
           <> help
                "BPMN only: how to read a unitless WITHIN. days (the default) = P<n>D plus a \
                \P-DEADLINE-UNIT note; refuse = no timer and a P-DEADLINE note."
            )
        )
  <*> option fidelityGateReader
        ( long "fail-on"
       <> metavar "SEVERITY"
       <> value GateNever
       <> showDefaultWith (const "none")
       <> help
            "Exit non-zero when the fidelity report holds a note this severe or worse: \
            \none|blocking|lossy|advisory. Default none, because Blocking describes the \
            \target notation's limits and fires on every realistic export."
        )
  <*> switch
        ( long "include-tests"
       <> help
            "DMN only: also emit decisions the population filter classifies as test \
            \scaffolding (referenced only from directive argument positions, with no \
            \callers). Default off: a fixture emitted as a <decision> misdescribes the \
            \rule set."
        )

----------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------

exportCmd :: ExportOptions -> IO ()
exportCmd opts = do
  checkTargetFlags opts
  evalConfig <- makeEvalConfig (FixedNowOpt Nothing)
  (errs, mTc) <- runOneshot evalConfig opts.exportFile \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    Shake.use Rules.SuccessfulTypeCheck uri

  case mTc of
    Just tcRes | tcRes.success -> do
      -- Unlike `l4 state-graph`, surface non-fatal diagnostics even on the
      -- happy path. An export is an artifact handed to someone else, so a
      -- library-shadow warning that changed which prelude was compiled is
      -- exactly what its author needs to see; `l4 render` and `l4 openfisca`
      -- print them for the same reason.
      putDiagnostics errs
      report <- case opts.exportTarget of
        TargetBpmn        -> exportBpmn opts tcRes
        TargetDmn         -> exportDmn opts tcRes
        TargetDmnMarkdown -> exportDmn opts tcRes
      tripped <- reportFidelity opts report
      if tripped then exitFailure else exitSuccess
    _ -> do
      putDiagnostics errs
      hPutStrLn stderr "Type checking failed — cannot export"
      exitFailure

-- | @FIXTURE(d)@'s importer view (OPEN-5, option 1): glob @*.l4@ beside the
-- exported file, textually detect @IMPORT <basename>@ — bare OR backticked —
-- and report which of this module's decide names occur anywhere in an
-- importing sibling's text.
--
-- The backticked spelling is load-bearing, not a nicety: a hyphenated module
-- name can ONLY be imported backticked (@IMPORT `housing-act-common`@ is how
-- the whole housing-act\/charities\/reg-cf corpus spells it), so a scan that
-- only matched the bare form saw NO importer for any hyphenated basename,
-- returned @Just Set.empty@ (\"verified clear\") instead of the fail-safe
-- 'Nothing', and dropped externally-called fixture-shaped decisions — the
-- \"delete a statute\" case §2.5.7 names, on the whole measured population.
--
-- Deliberately textual and conservative in the KEEP direction: a name
-- occurring in a comment still counts as an external reference and the
-- decision is kept — a false keep costs one extra element, a false drop
-- deletes a statute (§2.5.7's @`relevant date`@ is called from three sibling
-- files). What this scan cannot see: importers outside the file's own
-- directory. 'Nothing' (scan failed) makes the population filter fail safe.
siblingExternalRefs :: FilePath -> Module Resolved -> IO (Maybe (Set Text))
siblingExternalRefs fp modul = do
  let dir = takeDirectory fp
  ok <- doesDirectoryExist dir
  if not ok
    then pure Nothing
    else do
      efs <- try (listDirectory dir) :: IO (Either SomeException [FilePath])
      case efs of
        Left _ -> pure Nothing
        Right fs -> do
          let siblings =
                [ dir </> f
                | f <- fs
                , takeExtension f == ".l4"
                , takeBaseName f /= takeBaseName fp
                ]
              baseName = Text.pack (takeBaseName fp)
          texts <- for siblings \f -> do
            et <- try (Text.readFile f) :: IO (Either SomeException Text)
            pure (either (const "") id et)
          let importSpellings =
                [ "IMPORT " <> baseName
                , "IMPORT `" <> baseName <> "`"
                ]
              importerTexts =
                [ t
                | t <- texts
                , any (`Text.isInfixOf` t) importSpellings
                ]
          pure . Just $ Set.fromList
            [ n
            | n <- moduleDecideNames modul
            , any (n `Text.isInfixOf`) importerTexts
            ]

moduleDecideNames :: Module Resolved -> [Text]
moduleDecideNames (MkModule _ _ sec) = goSec sec
 where
  goSec (MkSection _ _ _ ds) = concatMap goDecl ds
  goDecl = \case
    Decide _ (MkDecide _ _ (MkAppForm _ n _ _) _) ->
      [unqualifiedNameToText (getOriginal n)]
    Section _ s -> goSec s
    _ -> []

-- | Four of the flags belong to some proper subset of the three targets.
-- Silently ignoring one the caller took the trouble to type is a small lie of
-- the same family the fidelity report exists to stop, so say so and stop.
--
-- __@--flavor@ is legal on @--to=dmn@ only.__ It was briefly admitted on
-- @--to=dmn-md@ too, on the theory that "the flavor lives in the @Drg@, which
-- both emitters read". Review checked, and the markdown side reads it nowhere:
-- @emitMarkdown@ mentions no field of it, and @markdownReport@ hard-codes the
-- target string @"dmnmd"@ rather than naming the flavor the way 'dmnReport'
-- does. So @--flavor=kie --to=dmn-md@ produced a byte-identical document /and/
-- a byte-identical fidelity report — the exact silent ignore the paragraph
-- above refuses. Nor does that self-heal at Phase 5: the one divergence is
-- whether a @\<decisionService\>@ may be invocable, and dmnmd is a table format
-- with no graph at all (it already says so, via @D-MD-NODRG@).
checkTargetFlags :: ExportOptions -> IO ()
checkTargetFlags opts = case misplaced of
  [] -> pure ()
  fs -> do
    for_ fs \(f, owner) ->
      hPutStrLn stderr $
        f <> ": no meaning for --to=" <> targetFlagName opts.exportTarget
          <> "; it belongs to " <> owner
    exitFailure
 where
  -- flag, was it given, where it IS legal, and how to say that
  candidates =
    [ ("--model-name",    isJust opts.exportModelName,    [TargetDmn, TargetDmnMarkdown], "--to=dmn / --to=dmn-md")
    , ("--flavor",        isJust opts.exportFlavor,       [TargetDmn],                    "--to=dmn")
    , ("--rule",          isJust opts.exportRule,         [TargetBpmn],                   "--to=bpmn")
    , ("--deadline-unit", isJust opts.exportDeadlineUnit, [TargetBpmn],                   "--to=bpmn")
    , ("--include-tests", opts.exportIncludeTests,        [TargetDmn, TargetDmnMarkdown], "--to=dmn / --to=dmn-md")
    ]
  misplaced =
    [ (f, owner)
    | (f, given, legalOn, owner) <- candidates
    , given
    , opts.exportTarget `notElem` legalOn
    ]

targetFlagName :: ExportTarget -> String
targetFlagName = \case
  TargetDmn         -> "dmn"
  TargetDmnMarkdown -> "dmn-md"
  TargetBpmn        -> "bpmn"

----------------------------------------------------------------------------
-- The decision side
----------------------------------------------------------------------------

exportDmn :: ExportOptions -> Rules.TypeCheckResult -> IO FidelityReport
exportDmn opts tcRes = do
  -- FIXTURE(d)'s importer view (§2.5.7, OPEN-5): a sibling-directory scan.
  -- Textual and conservative-keep: an occurrence of a decide's name anywhere
  -- in an importing sibling counts as an external reference, so over-matching
  -- KEEPS a decision (safe); only a name that appears in no importer can be
  -- dropped. When the scan cannot run, 'Nothing' makes the filter fail safe.
  externalRefs <- siblingExternalRefs opts.exportFile tcRes.module'
  -- Precedence: what the caller asked for, else the module's own outermost @§@
  -- heading, else the file's base name. The middle step is what lets a corpus
  -- name its own model once, in the corpus, instead of having the title
  -- retyped into every caller.
  let modelName =
        fromMaybe
          (fromMaybe
             (Text.pack (takeBaseName opts.exportFile))
             (moduleTitle tcRes.module'))
          opts.exportModelName
      drg =
        lowerModule
          MkDmnLowerOptions
            { dloModelName    = modelName
            , dloSubstitution = tcRes.substitution
            , dloFlavor       = fromMaybe defaultDmnFlavor opts.exportFlavor
            -- R8-d′'s combinator table. Resolved HERE, from the same check
            -- result the module came from, so `isJust`/`isNothing` are matched
            -- by Unique rather than by name. 'resolveMaybePredicates' lives in
            -- L4.Dmn.Lower beside its only consumer, so this call site and the
            -- golden harness's cannot drift apart on how recognition is done.
            , dloMaybePredicates =
                resolveMaybePredicates tcRes.module' tcRes.environment tcRes.entityInfo
            , dloIncludeTests = opts.exportIncludeTests
            -- DMN-SAFE's L1: the checker's own exhaustiveness warnings, from
            -- the same check result the module came from (the golden harness
            -- extracts them identically, so the two cannot drift).
            , dloMissingMatchRanges =
                [ r
                | e@(TC.MkCheckErrorWithContext (TC.CheckWarning (TC.PatternMatchesMissing _)) _) <- tcRes.infos
                , Just r <- [rangeOf e]
                ]
            -- L1's Decide-level channel: the clause-matrix warnings for
            -- multi-clause pattern-matching groups, extracted by the same
            -- comprehension as above (the golden harness matches this
            -- exactly, so the two cannot drift).
            , dloClauseMatrixRanges =
                [ r
                | e@(TC.MkCheckErrorWithContext (TC.CheckWarning (TC.PatternClausesMissing {})) _) <- tcRes.infos
                , Just r <- [rangeOf e]
                ]
            , dloExternalRefNames = externalRefs
            }
          tcRes.module'
  when (null (drgDecisions drg)) do
    hPutStrLn stderr
      "No decisions found in module — nothing to export as DMN \
      \(a DMN decision comes from a DECIDE / MEANS definition; a module of bare \
      \DECLAREs and IMPORTs has none)"
    exitFailure
  case opts.exportTarget of
    TargetDmnMarkdown -> do
      emitArtifact opts (emitMarkdown drg)
      pure (markdownReport drg)
    _ -> do
      emitArtifact opts (emitDrg drg)
      pure (dmnReport drg)

----------------------------------------------------------------------------
-- The process side
----------------------------------------------------------------------------

exportBpmn :: ExportOptions -> Rules.TypeCheckResult -> IO FidelityReport
exportBpmn opts tcRes = do
  sg <- selectGraph opts.exportRule (extractStateGraphs tcRes.module')
  let policy = fromMaybe AssumeDays opts.exportDeadlineUnit
      bx = stateGraphToBpmn (BpmnOptions {optDeadlineUnit = policy}) sg
  emitArtifact opts (renderBpmn bx)
  pure bx.bxFidelity

-- | Pick the one regulative rule to draw.
--
-- A BPMN file is one @\<definitions\>@ holding one process, and 'renderBpmn'
-- writes its own XML prolog, so \"export them all to stdout\" — which is what
-- @l4 state-graph@ does with DOT — would produce a document no tool can read.
-- Refusing and naming the alternatives is the honest answer.
selectGraph :: Maybe Text -> [StateGraph] -> IO StateGraph
selectGraph mWanted graphs = case (mWanted, graphs) of
  (_, []) -> die
    "No regulative rules found in module — nothing to export as BPMN"
  (Nothing, [g]) -> pure g
  (Nothing, _) -> die $
    "This module has "
      <> Text.pack (show (length graphs))
      <> " regulative rules, and a BPMN document holds exactly one process. \
         \Pass --rule NAME, where NAME is one of: "
      <> names
  (Just wanted, _) -> case [g | g <- graphs, g.sgName == wanted] of
    (g : _) -> pure g
    []      -> die $
      "No regulative rule named `" <> wanted <> "` in this module. Available: " <> names
 where
  names = Text.intercalate ", " ["`" <> g.sgName <> "`" | g <- graphs]
  die msg = do
    hPutStrLn stderr (Text.unpack msg)
    exitFailure

----------------------------------------------------------------------------
-- Output
----------------------------------------------------------------------------

emitArtifact :: ExportOptions -> Text -> IO ()
emitArtifact opts t = case opts.exportOutput of
  Just f  -> Text.writeFile f t
  Nothing -> Text.putStr t

-- | Where @--fidelity-report@ writes when the document went to a file.
--
-- @offering.bpmn@ → @offering.fidelity.txt@, matching the golden pairs under
-- @jl4\/examples\/bpmn\/expected@. (@reg-cf.dmn.md@ becomes
-- @reg-cf.dmn.fidelity.txt@ rather than the suite's @reg-cf.md.fidelity.txt@;
-- one rule for every target beats reproducing a test harness's naming.)
fidelitySibling :: FilePath -> FilePath
fidelitySibling f = replaceExtension f ".fidelity.txt"

----------------------------------------------------------------------------
-- Fidelity
----------------------------------------------------------------------------

-- | Tally, report, gate. Returns 'True' when @--fail-on@ says this export
-- should exit non-zero.
reportFidelity :: ExportOptions -> FidelityReport -> IO Bool
reportFidelity opts report = do
  let ns = report.notes
      countOf s = length [() | n <- ns, n.severity == s]
      tally = Text.intercalate ", "
        [ Text.pack (show c) <> " " <> label
        | (c, label) <-
            [ (countOf Blocking, "blocking")
            , (countOf Lossy,    "lossy")
            , (countOf Advisory, "advisory")
            ]
        , c > 0
        ]
      blockingCodes = nubOrd [n.code | n <- ns, n.severity == Blocking]

  -- (1) The tally is unconditional: an export never silently drops what the
  --     source said, whether or not the caller knew to ask.
  unless (null ns) do
    hPutStrLn stderr . Text.unpack $
      "l4 export: " <> report.target
        <> " could not carry everything this module says — " <> tally
    unless (null blockingCodes) $
      hPutStrLn stderr . Text.unpack $
        "l4 export:   blocking (the notation has no form for it; a fallback was emitted): "
          <> Text.intercalate ", " blockingCodes
    unless opts.exportFidelity $
      hPutStrLn stderr
        "l4 export:   re-run with --fidelity-report for the located list"

  -- (2) The full report, when asked for, as its own artifact.
  when opts.exportFidelity do
    let rendered = renderReport report
    case opts.exportOutput of
      Just f -> do
        let sidecar = fidelitySibling f
        Text.writeFile sidecar rendered
        hPutStrLn stderr ("l4 export: fidelity report written to " <> sidecar)
      Nothing -> Text.hPutStr stderr rendered

  pure (tripsGate opts.exportFailOn ns)

-- | 'FidelitySeverity' derives 'Ord' in declaration order, so @Blocking <
-- Lossy < Advisory@: \"at least this severe\" is @<=@ the threshold.
tripsGate :: FidelityGate -> [FidelityNote] -> Bool
tripsGate gate ns = case threshold of
  Nothing -> False
  Just t  -> any (\n -> n.severity <= t) ns
 where
  threshold = case gate of
    GateNever    -> Nothing
    GateBlocking -> Just Blocking
    GateLossy    -> Just Lossy
    GateAdvisory -> Just Advisory
