-- | @l4 export dmn|dmn-md|bpmn FILE@ — write an L4 module out in a foreign
-- interchange notation, together with an account of what that notation could
-- not carry.
--
-- Two notations, three formats, each its own @l4 export@ subcommand
-- (CLI-SURFACE-SPEC C1; this was @l4 export --to=…@ until 2026-09-24):
--
--   * @l4 export dmn@    — DMN 1.3 XML   ('L4.Dmn.Lower' → 'L4.Dmn.Emit')
--   * @l4 export dmn-md@ — dmnmd markdown, the same IR through a second
--                          emitter ('L4.Dmn.Markdown'), with its own,
--                          different loss list
--   * @l4 export bpmn@   — BPMN 2.0 XML  ('L4.StateGraph' → 'L4.Bpmn.Lower' →
--                          'L4.Bpmn.Emit')
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
--     __stderr__. @l4 export bpmn f.l4 --fidelity-report > f.bpmn@ must
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
  , exportDmnOptionsParser
  , exportDmnMarkdownOptionsParser
  , exportBpmnOptionsParser
  , exportCmd
  ) where

import Base
import qualified Base.Map as Map
import qualified Base.Text as Text
import Control.Exception (SomeException, try)
import qualified Base.Set as Set
import qualified Data.ByteString as ByteString
import qualified Data.Text.Encoding as Text (decodeUtf8')
import Options.Applicative
import System.Directory (canonicalizePath, doesDirectoryExist, listDirectory)
import System.Environment (lookupEnv)
import System.Exit (exitFailure, exitSuccess)
import System.FilePath (replaceExtension, takeBaseName, takeDirectory, takeExtension, takeFileName, (</>))

import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import Language.LSP.Protocol.Types (normalizedFilePathToUri, uriToFilePath)

import qualified L4.API.EmbeddedLibraries as EmbeddedLibraries
import L4.Bpmn.Emit (renderBpmn)
import L4.Bpmn.IR (BpmnExport (..), BpmnOptions (..), DeadlineUnitPolicy (..))
import L4.Bpmn.Lower (stateGraphToBpmn)
import L4.Bpmn.Wiring (wiringFromDrg)
import L4.Dmn.Emit (emitDrg)
import L4.Dmn.IR (Drg (..), DmnFlavor (..), DropReason (..), defaultDmnFlavor, dmnReport, drgDecisions)
import L4.Dmn.Lower
  ( DmnLowerOptions (..), ImportedModule (..), checkerClauseMatrixRanges
  , checkerMissingMatchRanges, embeddedLibraryModule, lowerModule, moduleTitle, resolveMaybePredicates )
import L4.Dmn.Markdown (emitMarkdown, markdownReport)
import L4.Interchange.Fidelity
  (FidelityNote (..), FidelityReport (..), FidelitySeverity (..), renderReport)
import L4.StateGraph (StateGraph (..), extractStateGraphs)
import L4.Syntax

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
    -- different loss list. Its own @l4 export dmn-md@ format rather than a
    -- flag on @dmn@, because it is a target, not a formatting option.
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

-- | One parser per format, each offering only the flags that format reads.
--
-- These were one parser behind @--to=dmn|dmn-md|bpmn@ until 2026-09-24, and
-- five of its flags belonged to a proper subset of the targets. A runtime
-- check refused each one given to the wrong target, because silently ignoring
-- a flag the caller took the trouble to type is a small lie of the same family
-- the fidelity report exists to stop. With a subcommand per format that
-- refusal is optparse's own @Invalid option@, and @--help@ lists only what
-- applies (CLI-SURFACE-SPEC C1).
--
-- __@--flavor@ is on @l4 export dmn@ only.__ It was briefly admitted on dmn-md
-- too, on the theory that "the flavor lives in the @Drg@, which both emitters
-- read". Review checked, and the markdown side reads it nowhere:
-- @emitMarkdown@ mentions no field of it, and @markdownReport@ hard-codes the
-- target string @"dmnmd"@ rather than naming the flavor the way 'dmnReport'
-- does. So @--flavor=kie@ on dmn-md produced a byte-identical document /and/ a
-- byte-identical fidelity report — the silent ignore described above. Nor does
-- that self-heal at Phase 5: the one divergence is whether a
-- @\<decisionService\>@ may be invocable, and dmnmd is a table format with no
-- graph at all (it already says so, via @D-MD-NODRG@).
exportDmnOptionsParser :: Parser ExportOptions
exportDmnOptionsParser = ExportOptions
  <$> fileArgument
  <*> pure TargetDmn
  <*> outputOption
  <*> fidelityReportSwitch
  <*> pure Nothing
  <*> modelNameOption
  <*> flavorOption
  <*> pure Nothing
  <*> failOnOption
  <*> includeTestsSwitch

exportDmnMarkdownOptionsParser :: Parser ExportOptions
exportDmnMarkdownOptionsParser = ExportOptions
  <$> fileArgument
  <*> pure TargetDmnMarkdown
  <*> outputOption
  <*> fidelityReportSwitch
  <*> pure Nothing
  <*> modelNameOption
  <*> pure Nothing
  <*> pure Nothing
  <*> failOnOption
  <*> includeTestsSwitch

exportBpmnOptionsParser :: Parser ExportOptions
exportBpmnOptionsParser = ExportOptions
  <$> fileArgument
  <*> pure TargetBpmn
  <*> outputOption
  <*> fidelityReportSwitch
  <*> ruleOption
  <*> pure Nothing
  <*> pure Nothing
  <*> deadlineUnitOption
  <*> failOnOption
  <*> pure False

fileArgument :: Parser FilePath
fileArgument = strArgument (metavar "FILE" <> help "Path to the .l4 file to export")

outputOption :: Parser (Maybe FilePath)
outputOption = optional
  ( strOption
      ( long "output"
     <> short 'o'
     <> metavar "FILE"
     <> help "Write the exported document to FILE instead of stdout"
      )
  )

fidelityReportSwitch :: Parser Bool
fidelityReportSwitch = switch
  ( long "fidelity-report"
 <> help
      "Also emit the full fidelity report: to FILE.fidelity.txt beside --output, \
      \or to stderr when the document goes to stdout. A one-line tally is printed \
      \either way."
  )

ruleOption :: Parser (Maybe Text)
ruleOption = optional
  ( strOption
      ( long "rule"
     <> metavar "NAME"
     <> help "Which regulative rule to export (required when the file has more than one)"
      )
  )

modelNameOption :: Parser (Maybe Text)
modelNameOption = optional
  ( strOption
      ( long "model-name"
     <> metavar "NAME"
     <> help "The <definitions> name and namespace seed (default: the module's outermost section heading, else the file's base name)"
      )
  )

flavorOption :: Parser (Maybe DmnFlavor)
flavorOption = optional
  ( option dmnFlavorReader
      ( long "flavor"
     <> metavar "ENGINE"
     <> showDefaultWith (const "camunda")
     <> help
          "Which engine to shape the document for. camunda (the default, \
          \= Camunda 8) | kie (= Drools). The two differ on exactly one thing: whether a \
          \<decisionService> may be the target of a <knowledgeRequirement>. Camunda 8 \
          \rejects the whole file at parse() if it is, so that shape is kie-only."
      )
  )

deadlineUnitOption :: Parser (Maybe DeadlineUnitPolicy)
deadlineUnitOption = optional
  ( option deadlineUnitReader
      ( long "deadline-unit"
     <> metavar "POLICY"
     <> showDefaultWith (const "days")
     <> help
          "How to read a unitless WITHIN. days (the default) = P<n>D plus a \
          \P-DEADLINE-UNIT note; refuse = no timer and a P-DEADLINE note."
      )
  )

-- | Shared by @export dmn@, @export dmn-md@ and @export bpmn@, so its help
-- must be true of all three. "Most realistic exports" was measured on each,
-- over the 1,049 @.l4@ files under @jl4/@ and @doc/@, exported one by one with
-- @--fidelity-report@ (2026-11-26, on this branch's build): of the files each
-- one writes, a Blocking note is in 441 of 764 for @dmn@, 764 of 764 for
-- @dmn-md@, and 49 of 49 for @bpmn@, which writes only a file with exactly
-- one regulative rule unless @--rule@ names one.
failOnOption :: Parser FidelityGate
failOnOption = option fidelityGateReader
  ( long "fail-on"
 <> metavar "SEVERITY"
 <> value GateNever
 <> showDefaultWith (const "none")
 <> help
      "Exit non-zero when the fidelity report holds a note this severe or worse: \
      \none|blocking|lossy|advisory. Default none, because Blocking usually describes \
      \the target notation's limits rather than a defect in your file, and fires on \
      \most realistic exports."
  )

includeTestsSwitch :: Parser Bool
includeTestsSwitch = switch
  ( long "include-tests"
 <> help
      "Also emit decisions the population filter classifies as test \
      \scaffolding (referenced only from directive argument positions, with no \
      \callers). Default off: a fixture emitted as a <decision> misdescribes the \
      \rule set."
  )

----------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------

exportCmd :: ExportOptions -> IO ()
exportCmd opts = do
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
      -- exactly what its author needs to see; `l4 render` and `l4 export openfisca`
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
  goSec (MkSection _ _ _ _ ds) = concatMap goDecl ds
  goDecl = \case
    Decide _ (MkDecide _ _ (MkAppForm _ n _ _) _) ->
      [unqualifiedNameToText (getOriginal n)]
    Section _ s -> goSec s
    _ -> []

----------------------------------------------------------------------------
-- The decision side
----------------------------------------------------------------------------

-- | Lower the module to a decision graph, exactly as @l4 export dmn@ would.
--
-- Named and shared because __both__ targets need it: the DMN emitters obviously,
-- and @l4 export bpmn@ because PROCESS-TRACK.md §8.3's @businessRuleTask@ has to name
-- the decision ids the DMN backend actually emitted. Re-deriving those on the
-- process side is the failure this factoring exists to prevent — see
-- "L4.Bpmn.Wiring".
--
-- It does not decide whether the result is worth emitting: a module with no
-- decisions is an error for @l4 export dmn@ and a non-event for @l4 export bpmn@, so that
-- judgement stays with the callers.
dmnDrgFor :: ExportOptions -> Rules.TypeCheckResult -> IO Drg
dmnDrgFor opts tcRes = do
  -- Which loaded modules are the standard library, for the lowering's
  -- provenance tests (`sum`, `all`, `YMD`, `isJust` and the rest).
  library <- dmnLibraryModule (Rules.transitiveDependencies tcRes)
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
                resolveMaybePredicates library tcRes.module' tcRes.environment tcRes.entityInfo
            , dloIncludeTests = opts.exportIncludeTests
            -- DMN-SAFE's L1: the checker's own exhaustiveness warnings, from
            -- the same check result the module came from (the golden harness
            -- extracts them with the same function, so the two cannot drift).
            , dloMissingMatchRanges = checkerMissingMatchRanges tcRes.infos
            -- L1's Decide-level channel: the clause-matrix warnings for
            -- multi-clause pattern-matching groups.
            , dloClauseMatrixRanges = checkerClauseMatrixRanges tcRes.infos
            , dloExternalRefNames = externalRefs
            -- #1102: every module this one imports, transitively and once
            -- each (the same walk `l4 export catala` takes), so a closed
            -- imported constant can be carried into the model as a decision,
            -- and certified with the checker's facts about its own module.
            -- 'imChecks' is 'Rules.evaluable': the module type-checks, and so
            -- does every module it imports, directly or not, so a module with
            -- no error of its own that imports one with errors is refused too.
            -- `l4 check` asks that of the module's result and also refuses on
            -- any other blocking diagnostic in its closure ("LSP.L4.BlockingErrors");
            -- the two kinds probed (a type mismatch, check/implicit-crosses-import)
            -- fail 'Rules.evaluable' too, but the two are not shown to agree
            -- in every case.
            , dloImportedModules =
                [ MkImportedModule
                    { imModule             = dep.module'
                    , imSubstitution       = dep.substitution
                    , imMissingMatchRanges = checkerMissingMatchRanges dep.infos
                    , imClauseMatrixRanges = checkerClauseMatrixRanges dep.infos
                    , imChecks             = Rules.evaluable dep
                    }
                | dep <- Rules.transitiveDependencies tcRes
                ]
            , dloLibraryModule = library
            }
          tcRes.module'
  pure drg

-- | The standard-library file a loaded module is, for 'dloLibraryModule': the
-- copy compiled into this binary, or a file in the @$JL4_LIBRARY_PATH@
-- directory, which outranks every other place the resolver looks (CLAUDE.md
-- §5), __whose text is the compiled-in copy of the same name__ (line endings
-- aside), and every module it imports is one of these too. Nothing else is the
-- library, whatever it is called: a @prelude.l4@ beside the exported file
-- outranks the compiled-in copy when that variable is unset, and is the
-- author's own module. Nor is a library found in the per-user store or the
-- editor bundle, which the resolver reaches only when @$JL4_LIBRARY_PATH@
-- names a directory without it. Each of these fails closed: its calls are
-- refused (Blocking) rather than lowered as the library's.
--
-- Why the text, and not the directory alone: the lowering writes the
-- library's calls as the FEEL the compiled-in copy's bodies mean
-- (@sum(concatenate([0], xs))@ for @sum@), so a directory whose @prelude.l4@
-- defines @sum@ differently was exported as the built-in @sum@ while @l4 run@
-- evaluated its own: @sum xs PLUS count xs@ over a @prelude.l4@ defining them
-- as 42 and 7 answered 5 on both engines against L4's 49, with Advisory notes
-- only (found by the review of this branch, 2026-11-26). Comparing the text
-- with the copy this binary carries is the one check that cannot be fooled by
-- a body, and it costs a library file that differs from the binary's copy in
-- any character, a comment included, the lowering of the calls into it and
-- into every library file that imports it: a binary built from other
-- @jl4-core/libraries@ than the ones its @$JL4_LIBRARY_PATH@ names gets a
-- Blocking note on each such call, where it used to lower them. Requiring the
-- text and not the meaning is decided by Claude 2026-11-26, pending Meng's
-- review.
--
-- Line endings are not compared: @\r\n@ is read as @\n@ on both sides. A
-- Windows checkout can write the libraries with CRLF, while the copy compiled
-- in was read in text mode, so a byte comparison would refuse the very tree
-- the binary was built from (found by the review of this branch, 2026-11-26;
-- the release workflow runs @l4-cli-test@ on Windows).
--
-- The compiled-in copy is trusted without looking at what its own imports
-- resolve to. That differs from the rule above, and on purpose: of the
-- libraries whose calls are lowered by name, the prelude imports nothing, and
-- @daydate@ imports @date-compat@ but calls nothing in it, so an author's
-- @date-compat.l4@, which the embedded @daydate@ does resolve when it sits in
-- the project root, cannot change what @Date@ or @YMD@ mean (measured
-- 2026-11-26: with one defining @DATE@ as 1 January 1999 beside the file,
-- @l4 run@ and the export both give 2 January 2024 for @Date 2 1 2024@ and
-- @YMD 2024 1 2@). A library lowered by name that called into its imports
-- would need the rule above extended to it. Leaving it so is decided by
-- Claude 2026-11-26, pending Meng's review.
--
-- Paths are compared canonically (symbolic links and @..@ resolved) because
-- the variable may be spelled relative or through a link.
dmnLibraryModule :: [Rules.TypeCheckResult] -> IO (NormalizedUri -> Maybe Text)
dmnLibraryModule deps = do
  mLibDir <- traverse canonical =<< lookupEnv "JL4_LIBRARY_PATH"
  sameText <- case mLibDir of
    Nothing -> pure []
    Just libDir -> fmap catMaybes $ for deps \dep -> do
      let u = Rules.moduleUriOf dep
      case uriToFilePath (fromNormalizedUri u) of
        Nothing -> pure Nothing
        Just p -> do
          dir <- canonical (takeDirectory p)
          same <- isCompiledInCopy p
          pure (if dir == libDir && same then Just (u, Text.pack (takeFileName p)) else Nothing)
  let byText = Map.fromList sameText
      library u = embeddedLibraryModule u <|> Map.lookup u byText
      -- `daydate.l4` imports `date-compat.l4`: a file whose own text is the
      -- compiled-in copy's is the library only when what it imports is too.
      trusted = Map.fromList
        [ (u, f)
        | dep <- deps
        , let u = Rules.moduleUriOf dep
        , Just f <- [Map.lookup u byText]
        , all (isJust . library . Rules.moduleUriOf) (Rules.transitiveDependencies dep)
        ]
  pure \u -> embeddedLibraryModule u <|> Map.lookup u trusted
 where
  canonical p = either (\(_ :: SomeException) -> p) id <$> try (canonicalizePath p)
  lf = Text.replace "\r\n" "\n"
  isCompiledInCopy p = do
    r <- try (ByteString.readFile p)
    pure case (r, EmbeddedLibraries.lookupEmbeddedLibrary (Text.pack (takeBaseName p))) of
      (Right bytes, Just src) -> either (const False) (\t -> lf t == lf src) (Text.decodeUtf8' bytes)
      (Left (_ :: SomeException), _) -> False
      (_, Nothing) -> False

exportDmn :: ExportOptions -> Rules.TypeCheckResult -> IO FidelityReport
exportDmn opts tcRes = do
  drg <- dmnDrgFor opts tcRes
  when (null (drgDecisions drg)) do
    hPutStr stderr (Text.unpack (noDecisionsMessage drg))
    exitFailure
  case opts.exportTarget of
    TargetDmnMarkdown -> do
      emitArtifact opts (emitMarkdown drg)
      pure (markdownReport drg)
    _ -> do
      emitArtifact opts (emitDrg drg)
      pure (dmnReport drg)

-- | Why the model has no decisions, in the reader's words.
--
-- A module with no @DECIDE@ or @MEANS@ at all gets the old one-line refusal.
-- But the model can also be empty because the population filter (spec §2.5.6)
-- left out every decision the module has, and saying "no DECIDE or MEANS" to
-- that module is false (smucclaw/l4-ide#1104). So the refusal names what was
-- left out and why, grouped by reason, and points at @--include-tests@ only
-- for the reason it cures: a regulative rule or a rule-date rebind stays out
-- with the flag set too.
--
-- Read from 'drgOmitted', never from the notes: one form of @D-FIXTURE@
-- reports a decision that was KEPT. A rule the checker took for a computed
-- field (smucclaw/l4-ide#1038) is not a population drop and comes from
-- 'drgTakenForFields'; before it was listed, a module whose only rule was
-- such a one was told it had no DECIDE or MEANS, and one that also had
-- scaffolding was given a list without it.
--
-- The wording is decided by Claude 2026-11-25, pending Meng's review; the
-- #1038 line is decided by Claude 2026-11-26, pending Meng's review.
noDecisionsMessage :: Drg -> Text
noDecisionsMessage drg
  | null drg.drgOmitted && null drg.drgTakenForFields =
      "No decisions found in module — nothing to export as DMN \
      \(a DMN decision comes from a DECIDE / MEANS definition; a module of bare \
      \DECLAREs and IMPORTs has none)\n"
  | otherwise =
      Text.unlines $
        "No decisions to export: every decision in this module was left out of the DMN model."
          : concat
              [ reasonLine scaffolding
                  "as test scaffolding, because each is used only by directives such as \
                  \#EVAL and #ASSERT, or by other test scaffolding"
                  " Pass --include-tests to export them."
              , reasonLine regulative
                  "as regulative rules (MUST, MAY, SHANT) that no decision calls"
                  " DMN describes decisions, not obligations: export these with \
                  \`l4 export bpmn` instead."
              , reasonLine rebinding
                  "because each evaluates under its own rule date (EVAL UNDER RULES \
                  \EFFECTIVE AT), and a DMN model has one rule-date input and no way to \
                  \rebind it"
                  ""
              , reasonLine drg.drgTakenForFields
                  "because each has the name of a computed field of a record (a field \
                  \with a MEANS in a DECLARE), and the checker takes each for that field \
                  \(smucclaw/l4-ide#1038, not yet fixed)"
                  " Rename them to export them."
              ]
 where
  scaffolding = [n | (n, r) <- drg.drgOmitted, r `elem` [DroppedFixture, DroppedFixtureHelper]]
  regulative  = [n | (n, DroppedRegulative) <- drg.drgOmitted]
  rebinding   = [n | (n, DroppedRuleDateRebind) <- drg.drgOmitted]
  reasonLine names why after
    | null names = []
    | otherwise =
        [ "  - " <> Text.intercalate ", " ["`" <> n <> "`" | n <- names]
            <> ": left out " <> why <> "." <> after
        ]

----------------------------------------------------------------------------
-- The process side
----------------------------------------------------------------------------

exportBpmn :: ExportOptions -> Rules.TypeCheckResult -> IO FidelityReport
exportBpmn opts tcRes = do
  sg <- selectGraph opts.exportRule (extractStateGraphs tcRes.module')
  -- The same lowering @l4 export dmn@ would perform, run for its NAMES rather than
  -- its XML: a gateway is wired only to a decision this graph actually contains
  -- (PROCESS-TRACK.md §8.3). Unconditional — a module with no decisions yields
  -- an empty table, which wires nothing and reports nothing, which is right.
  drg <- dmnDrgFor opts tcRes
  let policy = fromMaybe AssumeDays opts.exportDeadlineUnit
      bx =
        stateGraphToBpmn
          (BpmnOptions {optDeadlineUnit = policy, optWiring = Just (wiringFromDrg drg)})
          sg
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
