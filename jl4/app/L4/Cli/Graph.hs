-- | @l4 graph FILE@ — render the global dependency graph of an L4 module and
-- its import closure ('L4.DependencyGraph') as GraphViz DOT or Mermaid.
--
-- One node per named definition, one edge @A -> B@ per \"evaluating A may
-- require evaluating B\" — the \"is defined in terms of\" relation, never
-- control flow. @--root@ slices the graph at a definition (forward: what it is
-- defined in terms of; @--reverse@: who is defined in terms of it), and
-- @--depth@ cuts the slice a fixed number of edges out.
--
-- Exit codes, chosen deliberately where the precedents split (@l4 state-graph@
-- exits 1 when it finds no regulative rules; @l4 verify@ exits 0 when clean):
-- @l4 graph@ exits 0 and emits the rendering even for a degenerate graph — an
-- empty diagram is an answer about the module, not a failure of the command.
-- Typecheck failure exits 1, as does a @--root@ that names no definition.
module L4.Cli.Graph
  ( GraphOptions(..)
  , graphOptionsParser
  , graphCmd
  ) where

import Base
import qualified Base.Text as Text
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Options.Applicative
import System.Exit (exitFailure, exitSuccess)

import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import Language.LSP.Protocol.Types (normalizedFilePathToUri)

import L4.DependencyGraph
import L4.DependencyGraph.Render
import L4.Syntax (Module (..), Resolved, Unique)

import L4.Cli.Common

----------------------------------------------------------------------------
-- Options
----------------------------------------------------------------------------

data GraphFormat = GfDot | GfMermaid
  deriving (Eq, Show)

data GraphOptions = GraphOptions
  { graphFile    :: FilePath
  , graphFormat  :: GraphFormat
  , graphOutput  :: Maybe FilePath
  , graphRoots   :: [Text]
  , graphReverse :: Bool
  , graphDepth   :: Maybe Int
  }

-- @json@ is deliberately not accepted here: it is reserved for the interactive
-- rendering's topology payload (CALL-GRAPH-MATERIALITY-SPEC.md, D5).
graphFormatReader :: ReadM GraphFormat
graphFormatReader = eitherReader \input ->
  case Text.toLower (Text.pack input) of
    "dot"     -> Right GfDot
    "mermaid" -> Right GfMermaid
    "mmd"     -> Right GfMermaid
    other     -> Left $ "Invalid format: " <> Text.unpack other <> " (expected dot|mermaid)"

graphOptionsParser :: Parser GraphOptions
graphOptionsParser = GraphOptions
  <$> strArgument (metavar "FILE" <> help "Path to the .l4 file to graph")
  <*> option graphFormatReader
        ( long "format"
       <> metavar "FMT"
       <> value GfDot
       <> showDefaultWith (const "dot")
       <> help "Output format: dot|mermaid"
        )
  <*> optional
        ( strOption
            ( long "output"
           <> short 'o'
           <> metavar "FILE"
           <> help "Write to FILE instead of stdout"
            )
        )
  <*> many
        ( fmap Text.pack $ strOption
            ( long "root"
           <> metavar "NAME"
           <> help "Slice at this definition (repeatable; default: draw the whole graph)"
            )
        )
  <*> switch
        ( long "reverse"
       <> help "Slice against the arrows: who is defined in terms of the roots (needs --root)"
        )
  <*> optional
        ( option auto
            ( long "depth"
           <> metavar "N"
           <> help "Cut the slice N edges out from the roots; 0 = the roots alone (needs --root)"
            )
        )

----------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------

graphCmd :: GraphOptions -> IO ()
graphCmd opts = do
  -- The graph is static, so there is no --fixed-now: the clock never enters.
  evalConfig <- makeEvalConfig (FixedNowOpt Nothing)
  (errs, mTc) <- runOneshot evalConfig opts.graphFile \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    Shake.use Rules.SuccessfulTypeCheck uri

  case mTc of
    Just tc | tc.success -> do
      putDiagnostics errs
      let g = buildDepGraph tc.entityInfo tc.module' (dedupModules (transitiveDeps tc))
      mSlice <- sliceFor opts g
      let renderOpts = defaultDepGraphRenderOptions { slice = mSlice }
      emit opts case opts.graphFormat of
        GfDot     -> depGraphToDot renderOpts g
        GfMermaid -> depGraphToMermaid renderOpts g
      exitSuccess
    _ -> do
      putDiagnostics errs
      hPutStrLn stderr "Type checking failed - cannot build dependency graph"
      exitFailure

-- | Resolve @--root@\/@--reverse@\/@--depth@ into a renderer slice ('Nothing'
-- draws everything). A root matches every definition spelled with that
-- (unqualified) name; a root matching nothing is an error, not an empty
-- diagram — as are @--reverse@\/@--depth@ with no root to measure from, which
-- would otherwise silently draw the whole graph.
sliceFor :: GraphOptions -> DepGraph -> IO (Maybe (Set Unique))
sliceFor opts g
  | null opts.graphRoots = do
      when (opts.graphReverse || isJust opts.graphDepth) do
        hPutStrLn stderr "--reverse and --depth need at least one --root"
        exitFailure
      pure Nothing
  | otherwise = do
      roots <- for opts.graphRoots \nm ->
        case [u | (u, i) <- Map.toList g.nodes, i.name == nm] of
          [] -> do
            hPutStrLn stderr ("--root " <> Text.unpack nm <> ": no definition of that name")
            exitFailure
          us -> pure us
      let es = if opts.graphReverse then reverseEdges g else g.edges
      pure (Just (closureUpTo opts.graphDepth es (Set.fromList (concat roots))))

emit :: GraphOptions -> Text -> IO ()
emit opts t = case opts.graphOutput of
  Just f  -> Text.writeFile f t
  Nothing -> Text.putStr t

-- Copied from L4.Cli.Render (its transitiveDeps/dedupModules pair) rather
-- than shared through Common, to keep Render untouched in this change.
transitiveDeps :: Rules.TypeCheckResult -> [Module Resolved]
transitiveDeps tc = go tc.dependencies
 where
  go = concatMap (\d -> d.module' : go d.dependencies)

dedupModules :: [Module Resolved] -> [Module Resolved]
dedupModules = List.nubBy (\a b -> muri a == muri b)
 where
  muri (MkModule _ u _) = u
