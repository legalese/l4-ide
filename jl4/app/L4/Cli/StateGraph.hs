-- | @l4 state-graph FILE@ — extract the state transition graph of every
-- regulative rule in an L4 file as GraphViz DOT.
--
-- @REGULATIVE ... PARTY ... MUST/MAY/SHANT ...@ blocks define obligation
-- lifecycles: fulfilled, breached, dismissed. This command emits a DOT
-- diagram of those transitions so designers can visually check the flow.
--
-- Output goes to stdout; redirect with @>@. Exits 1 on typecheck failure.
--
-- With @--dominators@ the DOT is replaced by a plain-text answer per rule:
-- for each terminal state, the acts every path from the start must pass
-- through on the way to it ('L4.StateGraph.Dominators'). @--all-states@
-- widens that to every state of the graph.
module L4.Cli.StateGraph
  ( StateGraphOptions(..)
  , stateGraphOptionsParser
  , stateGraphCmd
  ) where

import Base (for_)
import qualified Base.Text as Text
import qualified Data.Text.IO as TIO
import Options.Applicative
import System.Exit (exitFailure, exitSuccess)
import System.IO (hPutStrLn, stderr)

import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import qualified L4.StateGraph as StateGraph
import qualified L4.StateGraph.Dominators as Dominators
import Language.LSP.Protocol.Types (normalizedFilePathToUri)

import L4.Cli.Common

----------------------------------------------------------------------------
-- Options
----------------------------------------------------------------------------

data StateGraphOptions = StateGraphOptions
  { stateGraphFile :: FilePath
  , stateGraphDominators :: Bool
    -- ^ Print, instead of DOT, the acts every path to each terminal state
    -- must traverse.
  , stateGraphAllStates :: Bool
    -- ^ With @--dominators@: answer for every state, not only the terminals.
  }

stateGraphOptionsParser :: Parser StateGraphOptions
stateGraphOptionsParser = StateGraphOptions
  <$> strArgument (metavar "FILE" <> help "Path to the .l4 file with regulative rules")
  <*> switch
        ( long "dominators"
       <> help "Instead of DOT, list the acts every path to FULFILLED and to BREACH must pass through" )
  <*> switch
        ( long "all-states"
       <> help "With --dominators: answer for every state of the graph, not only the terminal ones" )

----------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------

stateGraphCmd :: StateGraphOptions -> IO ()
stateGraphCmd opts = do
  evalConfig <- makeEvalConfig (FixedNowOpt Nothing)
  (errs, mTc) <- runOneshot evalConfig opts.stateGraphFile \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    Shake.use Rules.SuccessfulTypeCheck uri

  case mTc of
    Just tcRes | tcRes.success -> do
      let graphs = StateGraph.extractStateGraphs tcRes.module'
      case graphs of
        [] -> do
          hPutStrLn stderr "No regulative rules found in module"
          exitFailure
        _ -> do
          let sgOpts = StateGraph.defaultStateGraphOptions
          for_ graphs $ \sg ->
            if opts.stateGraphDominators
              then TIO.putStr (Text.unlines (Dominators.renderGraphDominators opts.stateGraphAllStates sg))
              else TIO.putStrLn (StateGraph.stateGraphToDot sgOpts sg)
          exitSuccess
    _ -> do
      putDiagnostics errs
      hPutStrLn stderr "Type checking failed — cannot extract state graph"
      exitFailure
