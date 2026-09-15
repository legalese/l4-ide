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
-- widens that to every state of the graph. @--dominators --dot@ keeps the
-- DOT and draws the same answer onto it: the acts on every path to
-- @FULFILLED@ or to @BREACH@ are bold and captioned
-- ('L4.StateGraph.Dot.showDominators').
module L4.Cli.StateGraph
  ( StateGraphOptions(..)
  , stateGraphOptionsParser
  , stateGraphCmd
  ) where

import Base (for_, when)
import qualified Base.Text as Text
import qualified Data.Text.IO as TIO
import Options.Applicative
import System.Exit (exitFailure, exitSuccess)
import System.IO (hPutStrLn, stderr)

import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import qualified L4.StateGraph as StateGraph
import qualified L4.StateGraph.Dominators as Dominators
import qualified L4.StateGraph.Dot as Dot
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
  , stateGraphDot :: Bool
    -- ^ With @--dominators@: keep the DOT, and mark the answer on it.
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
  <*> switch
        ( long "dot"
       <> help "With --dominators: keep the DOT drawing, with the acts on every path to FULFILLED or BREACH drawn bold and captioned" )

----------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------

stateGraphCmd :: StateGraphOptions -> IO ()
stateGraphCmd opts = do
  -- @--all-states@ only means something to the dominators listing. Accepting
  -- it alone would print the DOT as if the flag had been read, and exit 0.
  when (opts.stateGraphAllStates && not opts.stateGraphDominators) do
    hPutStrLn stderr "l4 state-graph: --all-states requires --dominators"
    exitFailure
  -- Likewise @--dot@ alone: the default output IS DOT, so accepting the flag
  -- would print the unmarked drawing as if it were the marked one.
  when (opts.stateGraphDot && not opts.stateGraphDominators) do
    hPutStrLn stderr "l4 state-graph: --dot requires --dominators"
    exitFailure
  -- And the two modifiers together: a drawing marks only the two terminals,
  -- and the per-state answer has no place on it.
  when (opts.stateGraphDot && opts.stateGraphAllStates) do
    hPutStrLn stderr "l4 state-graph: --dot and --all-states cannot be combined"
    exitFailure
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
          let sgOpts = Dot.defaultStateGraphOptions
                { Dot.showDominators = opts.stateGraphDominators && opts.stateGraphDot }
          for_ graphs $ \sg ->
            if opts.stateGraphDominators && not opts.stateGraphDot
              then TIO.putStr (Text.unlines (Dominators.renderGraphDominators opts.stateGraphAllStates sg))
              else TIO.putStrLn (Dot.stateGraphToDot sgOpts sg)
          exitSuccess
    _ -> do
      putDiagnostics errs
      hPutStrLn stderr "Type checking failed — cannot extract state graph"
      exitFailure
