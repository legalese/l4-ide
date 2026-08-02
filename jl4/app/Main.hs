-- | Entry point for the @l4@ CLI.
--
-- Dispatches on a subcommand; if the first positional argument is a bare
-- filepath instead of a known subcommand name, falls through to @l4 run@
-- so legacy invocations like @l4 foo.l4@ (and @jl4-cli foo.l4@ from older
-- scripts) keep working.
module Main where

import Control.Applicative ((<|>))
import GHC.IO.Encoding (setLocaleEncoding, utf8)
import Options.Applicative
  ( Parser
  , ParserInfo
  , command
  , customExecParser
  , footer
  , fullDesc
  , header
  , helper
  , info
  , progDesc
  , prefs
  , showHelpOnEmpty
  , subparser
  )
import qualified Options.Applicative as Options
import System.IO (hSetEncoding, stdin, stdout, stderr)

import L4.Cli.Ast (AstOptions, astCmd, astOptionsParser)
import L4.Cli.Batch (BatchOptions, batchCmd, batchOptionsParser)
import L4.Cli.Check (CheckOptions, checkCmd, checkOptionsParser)
import L4.Cli.Export (ExportOptions, exportCmd, exportOptionsParser)
import L4.Cli.Format (FormatOptions, formatCmd, formatOptionsParser)
import L4.Cli.Nlg (NlgOptions, nlgCmd, nlgOptionsParser)
import L4.Cli.OpenFisca (OpenFiscaOptions, openFiscaCmd, openFiscaOptionsParser)
import L4.Cli.Render (RenderOptions, renderCmd, renderOptionsParser)
import L4.Cli.Run (RunOptions, runCmd, runOptionsParser)
import L4.Cli.StateGraph (StateGraphOptions, stateGraphCmd, stateGraphOptionsParser)
import L4.Cli.Trace (TraceOptions, traceCmd, traceOptionsParser)
import L4.Cli.Verify (VerifyOptions, propositionalBound, verifyCmd, verifyOptionsParser)

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
  | CmdNlg        NlgOptions
  | CmdVerify     VerifyOptions

commandParser :: Parser Command
commandParser =
      subparser subcommandSet
  -- Backward-compat fallthrough: `l4 foo.l4 [--flags]` = `l4 run foo.l4 [--flags]`.
  -- Must come after `subparser` so a well-typed subcommand name wins.
  <|> (CmdRun <$> runOptionsParser)
  where
    subcommandSet =
         command "run"
           (info (CmdRun <$> runOptionsParser)
             (progDesc "Typecheck and evaluate an L4 file (prints diagnostics + #EVAL results)"))
      <> command "check"
           (info (CmdCheck <$> checkOptionsParser)
             (progDesc "Typecheck an L4 file only (fast path; no evaluation)"))
      <> command "format"
           (info (CmdFormat <$> formatOptionsParser)
             (progDesc "Reformat an L4 file and print to stdout"))
      <> command "ast"
           (info (CmdAst <$> astOptionsParser)
             (progDesc "Dump the parsed AST of an L4 file"))
      <> command "batch"
           (info (CmdBatch <$> batchOptionsParser)
             (progDesc "Evaluate an @export function against many input rows (NDJSON streaming)"))
      <> command "trace"
           (info (CmdTrace <$> traceOptionsParser)
             (progDesc "Render #EVALTRACE evaluation traces as GraphViz (dot|png|svg)"))
      <> command "state-graph"
           (info (CmdStateGraph <$> stateGraphOptionsParser)
             (progDesc "Extract regulative-rule state transition graphs as GraphViz DOT"))
      <> command "render"
           (info (CmdRender <$> renderOptionsParser)
             (progDesc "Render an L4 file to a formatted document (html|text|json|plan)"))
      <> command "export"
           (info (CmdExport <$> exportOptionsParser)
             (progDesc "Export an L4 file to a foreign interchange notation (dmn|dmn-md|bpmn) with a fidelity report"))
      <> command "openfisca"
           (info (CmdOpenFisca <$> openFiscaOptionsParser)
             (progDesc "Compile the decision-rule subset of an L4 file to a runnable OpenFisca Python module"))
      <> command "nlg"
           (info (helper <*> (CmdNlg <$> nlgOptionsParser))
             (progDesc "Linearize a module's directives to natural-language prose (the .nlg golden payload)"))
      -- `helper` here, and not on the older subcommands, is deliberate rather
      -- than inconsistent-by-accident: `l4 <cmd> --help` answers
      -- `Invalid option '--help'` for every subcommand that predates these two,
      -- and this command's honesty about its own limits is delivered through
      -- `footer`. A caveat nobody can reach is not a caveat. Extending `helper`
      -- to the rest is a good idea and a separate change: the orchestrator's
      -- p0-preflight pins CLI enumerations, and moving nine help surfaces at
      -- once is not something to do inside a footing PR.
      <> command "verify"
           (info (helper <*> (CmdVerify <$> verifyOptionsParser))
             (progDesc "Look for unsatisfiable rules, dead branches, vacuous guards and unreachable outcomes in the boolean decision skeleton"
               <> footer propositionalBound))

commandInfo :: ParserInfo Command
commandInfo = info (helper <*> commandParser)
  ( fullDesc
  <> header "l4 — the L4 computational-law CLI"
  <> progDesc "Typecheck, evaluate, format, and visualize .l4 files. Run `l4 <command> --help` for per-command options."
  <> footer "Part of the L4 tool family from Legalese.com"
  )

main :: IO ()
main = do
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

  cmd <- customExecParser (prefs showHelpOnEmpty) commandInfo
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
    CmdNlg        opts -> nlgCmd        opts
    CmdVerify     opts -> verifyCmd     opts

-- Silence unused-imports warning when we only import Options for types
-- indirectly via re-exports.
_unusedOptions :: Options.Parser ()
_unusedOptions = pure ()
