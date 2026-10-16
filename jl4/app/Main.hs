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
import qualified Data.Text as Text
import qualified Options.Applicative as Options
import System.IO (hSetEncoding, stdin, stdout, stderr)

import LSP.L4.BuildInfo (buildInfoLine)

import L4.Cli.Ast (AstOptions, astCmd, astOptionsParser)
import L4.Cli.Batch (BatchOptions, batchCmd, batchOptionsParser)
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
import L4.Cli.Format (FormatOptions, formatCmd, formatOptionsParser)
import L4.Cli.Install (InstallOptions, installCmd, installOptionsParser)
import L4.Cli.Render (RenderOptions, renderCmd, renderOptionsParser)
import L4.Cli.Run (RunOptions, runCmd, runOptionsParser)
import L4.Cli.StateGraph (StateGraphOptions, stateGraphCmd, stateGraphOptionsParser)
import L4.Cli.Trace (TraceOptions, traceCmd, traceOptionsParser)

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
  | CmdDeploy     DeployOptions
  | CmdRedeploy   DeployOptions
  | CmdUndeploy   UndeployOptions
  | CmdDeployments DeploymentsOptions
  | CmdInstall    InstallOptions

commandParser :: Parser Command
commandParser =
      subparser subcommandSet
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
             -- "NDJSON" here is the OUTPUT default (--format); the input side
             -- reads json|yaml|csv and has no ndjson reader. The summary used to
             -- say just "NDJSON streaming", which read as if
             -- `--input-format ndjson` were available.
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

commandInfo :: ParserInfo Command
commandInfo = info (helper <*> versionOption <*> commandParser)
  ( fullDesc
  <> header "l4 — the L4 computational-law CLI"
  <> progDesc "Typecheck, evaluate, format, visualize, and deploy .l4 files. Run `l4 <command> --help` for per-command options."
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
    CmdDeploy     opts -> deployCmd     opts
    CmdRedeploy   opts -> redeployCmd   opts
    CmdUndeploy   opts -> undeployCmd   opts
    CmdDeployments opts -> deploymentsCmd opts
    CmdInstall    opts -> installCmd    opts

-- Silence unused-imports warning when we only import Options for types
-- indirectly via re-exports.
_unusedOptions :: Options.Parser ()
_unusedOptions = pure ()
