-- | The command line of @l4@, as a function of the 'Extensions' added to it.
--
-- Dispatches on a subcommand; if the first positional argument is a bare
-- filepath instead of a known subcommand name, falls through to @l4 run@
-- so legacy invocations like @l4 foo.l4@ (and @jl4-cli foo.l4@ from older
-- scripts) keep working.
--
-- The executable @l4@ is @mainWith noExtensions@ (@jl4/l4/Main.hs@). Another
-- package can build an executable that is @l4@ plus its own commands, export
-- formats and @explore --emit@ targets; see "L4.Cli.Extensions".
module L4.Cli.Main (mainWith) where

import Control.Applicative ((<|>))
import GHC.IO.Encoding (setLocaleEncoding, utf8)
import Options.Applicative
  ( CommandFields
  , Mod
  , Parser
  , ParserInfo
  , command
  , commandGroup
  , customExecParser
  , footer
  , footerDoc
  , fullDesc
  , header
  , helper
  , info
  , metavar
  , progDesc
  , prefs
  , showHelpOnEmpty
  , subparser
  )
import qualified Data.Text as Text
import qualified Options.Applicative as Options
import Options.Applicative.Builder.Internal (mkCommand)
import qualified Options.Applicative.Help.Pretty as Pretty
import System.IO (hSetEncoding, stdin, stdout, stderr)

import LSP.L4.BuildInfo (buildInfoLine)

import L4.Cli.Ast (AstOptions, astCmd, astOptionsParser)
import L4.Cli.Batch (BatchOptions, batchCmd, batchOptionsParser)
import L4.Cli.Blawx (BlawxOptions, blawxCmd, blawxExportOptionsParser, blawxImportOptionsParser)
import L4.Cli.Catala (CatalaOptions, catalaCmd, catalaOptionsParser)
import L4.Cli.Check (CheckOptions, checkCmd, checkOptionsParser)
import L4.Cli.Deploy
  ( DeployOptions
  , DeploymentsOptions
  , UndeployOptions
  , deployCmd
  , deployOptionsParser
  , deploymentsCmd
  , deploymentsOptionsParser
  , redeployCmd
  , redeployOptionsParser
  , undeployCmd
  , undeployOptionsParser
  )
import L4.Cli.Docassemble (DocassembleOptions, docassembleCmd, docassembleOptionsParser)
import L4.Cli.Explore (ExploreCliOptions, exploreCmd, exploreOptionsParser)
import L4.Cli.Export (ExportOptions, exportBpmnOptionsParser, exportCmd, exportDmnMarkdownOptionsParser, exportDmnOptionsParser)
import L4.Cli.Extensions (ExtCommand (..), Extensions (..))
import L4.Cli.Format (FormatOptions, formatCmd, formatOptionsParser)
import L4.Cli.Install (InstallOptions, installCmd, installOptionsParser)
import L4.Cli.Lts (LtsOptions, ltsCmd, ltsOptionsParser)
import L4.Cli.Nlg (NlgOptions, nlgCmd, nlgOptionsParser)
import L4.Cli.OpenFisca (OpenFiscaOptions, openFiscaCmd, openFiscaOptionsParser)
import L4.Cli.Render (RenderOptions, renderCmd, renderOptionsParser)
import L4.Cli.Run (RunOptions, runCmd, runOptionsParser)
import L4.Cli.StateGraph (StateGraphOptions, stateGraphCmd, stateGraphOptionsParser)
import L4.Cli.Trace (TraceOptions, traceCmd, traceOptionsParser)
import L4.Cli.Verify (VerifyOptions, propositionalBound, verifyCmd, verifyOptionsParser)
import L4.Cli.Yscript (YscriptOptions, yscriptCmd, yscriptOptionsParser)

----------------------------------------------------------------------------
-- Top-level command
----------------------------------------------------------------------------

data Command
  = CmdRun        RunOptions
  | CmdCheck      CheckOptions
  | CmdFormat     FormatOptions
  | CmdAst        AstOptions
  | CmdBatch      BatchOptions
  | CmdTrace      TraceOptions
  | CmdStateGraph StateGraphOptions
  | CmdRender     RenderOptions
  | CmdExport     ExportOptions
  | CmdOpenFisca  OpenFiscaOptions
  | CmdBlawx      BlawxOptions
  | CmdCatala     CatalaOptions
  | CmdDocassemble DocassembleOptions
  | CmdNlg        NlgOptions
  | CmdLts        LtsOptions
  | CmdExplore    ExploreCliOptions
  | CmdVerify     VerifyOptions
  | CmdYscript    YscriptOptions
  | CmdDeploy     DeployOptions
  | CmdRedeploy   DeployOptions
  | CmdUndeploy   UndeployOptions
  | CmdDeployments DeploymentsOptions
  | CmdInstall    InstallOptions
  | CmdExtension  (IO ())

commandParser :: Extensions -> Parser Command
commandParser exts =
      -- The export formats are read only by `l4 export`; forcing them here
      -- makes a name clash among them stop every invocation, as one among the
      -- commands does.
      exportFormats `seq` checkedSubparser "command" subcommandSet
  -- Backward-compat fallthrough: `l4 foo.l4 [--flags]` = `l4 run foo.l4 [--flags]`.
  -- Must come after `subparser` so a well-typed subcommand name wins.
  <|> (CmdRun <$> runOptionsParser)
  where
    subcommandSet =
         command "run"
           (info (helper <*> (CmdRun <$> runOptionsParser))
             (progDesc "Typecheck and evaluate an L4 file (prints diagnostics + #EVAL results)"))
      <> command "check"
           (info (helper <*> (CmdCheck <$> checkOptionsParser))
             (progDesc "Typecheck an L4 file only (fast path; no evaluation)"))
      <> command "format"
           (info (helper <*> (CmdFormat <$> formatOptionsParser))
             (progDesc "Reformat an L4 file and print to stdout"))
      <> command "ast"
           (info (helper <*> (CmdAst <$> astOptionsParser))
             (progDesc "Dump the parsed AST of an L4 file"))
      <> command "batch"
           (info (helper <*> (CmdBatch <$> batchOptionsParser))
             -- "NDJSON" here is the OUTPUT default (--output-format); the input
             -- side reads json|yaml|csv and has no ndjson reader. The summary
             -- used to say just "NDJSON streaming", which read as if
             -- `--input-format ndjson` were available (smucclaw/l4-ide#932).
             (progDesc "Evaluate an @export function against many input rows (json|yaml|csv in, NDJSON streaming out)"))
      <> command "trace"
           (info (helper <*> (CmdTrace <$> traceOptionsParser))
             (progDesc "Render #EVALTRACE evaluation traces as GraphViz (dot|png|svg)"))
      <> command "state-graph"
           (info (helper <*> (CmdStateGraph <$> stateGraphOptionsParser))
             (progDesc "Extract regulative-rule state transition graphs as GraphViz DOT"))
      <> command "render"
           (info (helper <*> (CmdRender <$> renderOptionsParser))
             (progDesc "Render an L4 file to a formatted document (html|text|json|plan)"))
      <> command "nlg"
           (info (helper <*> (CmdNlg <$> nlgOptionsParser))
             (progDesc "Linearize a module's directives to natural-language prose (the .nlg golden payload)"))
      <> command "lts"
           (info (helper <*> (CmdLts <$> ltsOptionsParser))
             (progDesc "List, for every #TRACE, what is owed now, what would discharge it, what would breach it, and the next deadline"))
      <> command "explore"
           (info (helper <*> (CmdExplore <$> exploreOptionsParser exts.extEmitTargets))
             ( progDesc "Every position a contract can reach, as an explicit labelled transition system, ending in a coverage line"
             <> footer "Exit status: 0 complete, and every property named holds; 1 the file or an option failed, or an emitted file could not be written; 2 an act was refused (a variable whose type has no finite set of values) or a candidate could not be tried; 3 the depth or state bound stopped it; 4 a property is violated; 5 a property's verdict is unknown (every liveness property: run the emitted model). No sample is ever tried in a refused act's place."
             ))
      -- Every subcommand carries `helper` (measured 2026-10-30: `l4 <cmd> --help`
      -- exits 0 for all nineteen), so `explore` and `verify` can deliver their
      -- honesty about their own limits through `footer`. A caveat nobody can
      -- reach is not a caveat.
      <> command "verify"
           (info (helper <*> (CmdVerify <$> verifyOptionsParser))
             (progDesc "Look for unsatisfiable rules, dead branches, vacuous guards and unreachable outcomes in the boolean decision skeleton"
               <> footerDoc (Just (verbatim propositionalBound))))
      <> command "export"
           (info (helper <*> exportFormats)
             (progDesc "Write an L4 module out in another notation: an interchange document, a runnable program, or an interview. Run `l4 export --help` for the formats, `l4 export FORMAT --help` for each one's options"))
      <> command "import"
           (info (helper <*> importFormats)
             (progDesc "Read another notation into L4 source. Run `l4 import --help` for the formats"))
      <> command "deploy"
           (info (helper <*> (CmdDeploy <$> deployOptionsParser))
             (progDesc "Deploy an L4 file and its imports as a new deployment (Legalese Cloud, or --server)"))
      <> command "redeploy"
           (info (helper <*> (CmdRedeploy <$> redeployOptionsParser))
             (progDesc "Update an existing deployment; refuses breaking changes unless --force"))
      <> command "undeploy"
           (info (helper <*> (CmdUndeploy <$> undeployOptionsParser))
             (progDesc "Delete a deployment"))
      <> command "deployments"
           (info (helper <*> (CmdDeployments <$> deploymentsOptionsParser))
             (progDesc "List deployments"))
      <> command "install"
           (info (helper <*> (CmdInstall <$> installOptionsParser))
             (progDesc "Install a companion tool: `l4 install legalese` (the Legalese Cloud CLI)"))
      -- Added by an extension, after the built-in ones (empty in the community build).
      <> foldMap extensionCommand exts.extCommands

    -- One subcommand per foreign notation (CLI-SURFACE-SPEC C1). Each was a
    -- top-level verb, or a `--to` value on `l4 export`, until 2026-09-24.
    -- Adding a backend adds one entry here, and `l4 export --help` is the
    -- catalogue of every notation L4 can write.
    exportFormats =
      checkedSubparser "export format"
        (  metavar "FORMAT"
        <> commandGroup "Formats:"
        <> command "dmn"
             (info (helper <*> (CmdExport <$> exportDmnOptionsParser))
               (progDesc "DMN 1.3 XML decision model, with a fidelity report"))
        <> command "dmn-md"
             (info (helper <*> (CmdExport <$> exportDmnMarkdownOptionsParser))
               (progDesc "dmnmd markdown decision tables, with a fidelity report"))
        <> command "bpmn"
             (info (helper <*> (CmdExport <$> exportBpmnOptionsParser))
               (progDesc "BPMN 2.0 XML process for one regulative rule, with a fidelity report"))
        <> command "openfisca"
             (info (helper <*> (CmdOpenFisca <$> openFiscaOptionsParser))
               (progDesc "A runnable OpenFisca Python module of the decision-rule subset"))
        <> command "blawx"
             (info (helper <*> (CmdBlawx <$> blawxExportOptionsParser))
               (progDesc "A Blawx project (.blawx YAML + s(CASP) dump) of the decision-rule subset"))
        <> command "catala"
             (info (helper <*> (CmdCatala <$> catalaOptionsParser))
               (progDesc "A literate Catala module of the constitutive subset"))
        <> command "docassemble"
             (info (helper <*> (CmdDocassemble <$> docassembleOptionsParser))
               (progDesc "A docassemble interview (YAML) of the decision-rule subset, with a fidelity report"))
        <> command "yscript"
             (info (helper <*> (CmdYscript <$> yscriptOptionsParser))
               (progDesc "AustLII DataLex yscript for the pure-propositional-logic subset (one-way, no fidelity report)"))
        <> foldMap extensionCommand exts.extExports
        )

    importFormats =
      subparser
        (  metavar "FORMAT"
        <> commandGroup "Formats:"
        <> command "blawx"
             (info (helper <*> (CmdBlawx <$> blawxImportOptionsParser))
               (progDesc "Lift a .blawx project to L4 source"))
        )

-- | A footer that keeps the line breaks it was written with.
--
-- @footer@ takes a String and runs it through optparse-applicative's
-- @paragraph@, which is @fillSep . words@: every newline becomes a space and
-- the whole thing reflows into one wall of prose. For a caveat with five
-- separately-quotable paragraphs that is a real loss — the text report and the
-- @--help@ footer are the same string and must read the same way, because the
-- run receipt points a reader at @--help@ for the full statement.
verbatim :: String -> Pretty.Doc
verbatim = Pretty.vsep . fmap Pretty.pretty . lines

-- | An extension's subcommand, as a built-in one is declared.
extensionCommand :: ExtCommand -> Mod CommandFields Command
extensionCommand c = command c.ecName (CmdExtension <$> c.ecInfo)

-- | 'subparser', except that a name given twice is an error. With optparse-
-- applicative's own rule, the first of two commands of one name wins and the
-- other is unreachable without a word, which is how an extension would lose
-- to a built-in. The error is raised when the parser is first read, which
-- 'commandParser' does for both lists on every invocation. @what@ names the
-- kind of thing, for the message.
checkedSubparser :: String -> Mod CommandFields a -> Parser a
checkedSubparser what m = case [ n | n <- names, length (filter (== n) names) > 1 ] of
  [] -> subparser m
  n : _ -> errorWithoutStackTrace
    ("two " <> what <> "s are named `" <> n <> "`: a name added by an extension cannot be one that a built-in or another extension already has")
  where
    names = map fst (snd (mkCommand m))

commandInfo :: Extensions -> ParserInfo Command
commandInfo exts = info (helper <*> versionOption <*> commandParser exts)
  ( fullDesc
  <> header "l4 — the L4 computational-law CLI"
  <> progDesc "Typecheck, evaluate, format, visualize and deploy .l4 files, and export them to (or import them from) other notations. Run `l4 <command> --help` for per-command options."
  <> footer "Part of the L4 tool family from Legalese.com"
  )

-- | @l4 --version@: one line naming the build, @dev@ for a local build
-- ("LSP.L4.BuildInfo"). It is an option of @l4@ itself and not a subcommand,
-- because @l4 version@ already means the file called @version@ (the
-- fall-through to @l4 run@ above).
versionOption :: Parser (a -> a)
versionOption =
  Options.infoOption (Text.unpack buildInfoLine)
    (Options.long "version" <> Options.help "Print the version of this build and exit")

-- | Run the command line: the built-in commands, and the 'Extensions' added to them.
mainWith :: Extensions -> IO ()
mainWith exts = do
  -- Force UTF-8 everywhere. On Windows, GHC's default locale encoding is
  -- whatever the user codepage happens to be (CP1252 / CP437 / CP850 …),
  -- which means two independent disasters:
  --
  --   1. `Text.readFile` in LSP.Core.Shake decodes `.l4` source as the
  --      system codepage, so `§` (bytes 0xC2 0xA7) comes back as "┬º"
  --      and the parser bails with `unexpected '┬'`.
  --   2. `putStrLn`-family writes to stdout/stderr run their Text through
  --      the same codepage, so echoing a `§` back as part of a diagnostic
  --      crashes with `hPutChar: cannot encode character '\167'`.
  --
  -- `setLocaleEncoding` fixes (1) by making *new* handles UTF-8 by
  -- default. The three explicit `hSetEncoding` calls fix (2) by
  -- overriding the standard handles, which were already opened by the
  -- runtime before `main` started and so inherited the original locale.
  setLocaleEncoding utf8
  hSetEncoding stdin  utf8
  hSetEncoding stdout utf8
  hSetEncoding stderr utf8

  cmd <- customExecParser (prefs showHelpOnEmpty) (commandInfo exts)
  case cmd of
    CmdRun        opts -> runCmd        opts
    CmdCheck      opts -> checkCmd      opts
    CmdFormat     opts -> formatCmd     opts
    CmdAst        opts -> astCmd        opts
    CmdBatch      opts -> batchCmd      opts
    CmdTrace      opts -> traceCmd      opts
    CmdStateGraph opts -> stateGraphCmd opts
    CmdRender     opts -> renderCmd     opts
    CmdExport     opts -> exportCmd     opts
    CmdOpenFisca  opts -> openFiscaCmd  opts
    CmdBlawx      opts -> blawxCmd      opts
    CmdCatala     opts -> catalaCmd     opts
    CmdDocassemble opts -> docassembleCmd opts
    CmdNlg        opts -> nlgCmd        opts
    CmdLts        opts -> ltsCmd        opts
    CmdExplore    opts -> exploreCmd    exts.extEmitTargets opts
    CmdVerify     opts -> verifyCmd     opts
    CmdYscript    opts -> yscriptCmd    opts
    CmdDeploy     opts -> deployCmd     opts
    CmdRedeploy   opts -> redeployCmd   opts
    CmdUndeploy   opts -> undeployCmd   opts
    CmdDeployments opts -> deploymentsCmd opts
    CmdInstall    opts -> installCmd    opts
    CmdExtension  act  -> act

-- Silence unused-imports warning when we only import Options for types
-- indirectly via re-exports.
_unusedOptions :: Options.Parser ()
_unusedOptions = pure ()
