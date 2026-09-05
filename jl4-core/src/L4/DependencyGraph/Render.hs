-- | Renderers for the global dependency graph ('L4.DependencyGraph'): DOT via
-- the @graphviz@ library (following the "L4.StateGraph" template) and Mermaid
-- as hand-rolled 'Text' — the repo's first Haskell Mermaid emitter; its label
-- discipline comes from @ts-shared\/ladder-core\/src\/mermaid.ts@.
--
-- Both renderers draw one vocabulary:
--
-- * node shape and fill by 'DepKind' (hues shared with "L4.StateGraph" for
--   family resemblance);
--
-- * nodes unreachable from the entry points drawn dashed and grey —
--   surplusage, the drafting smell — except when the graph has no entry
--   points at all, in which case the analysis is vacuous rather than damning
--   and nothing is marked;
--
-- * members of cyclic SCCs bordered red (circular definitions);
--
-- * a node's @\@desc@ text as its DOT tooltip (Mermaid has no tooltip short
--   of a @click@ directive, so it is DOT-only);
--
-- * edges bare: an edge reads \"is defined in terms of\", never control flow,
--   so it carries no label that could suggest sequencing.
--
-- Surplusage and cycles are judged on the /whole/ graph even under a 'slice':
-- a slice is a view of the graph, not a smaller graph with its own analyses.
--
-- Mermaid's double-quoted labels have no escape sequence, so labels are
-- folded, never escaped — see 'mermaidLit'. The first line of Mermaid output
-- is frozen as 'mermaidHeader' (@flowchart TD@); tests and downstream tooling
-- may rely on it.
module L4.DependencyGraph.Render
  ( -- * Options
    DepGraphRenderOptions (..)
  , defaultDepGraphRenderOptions
    -- * Renderers
  , depGraphToDot
  , depGraphToMermaid
  , mermaidHeader
  ) where

import Base
import qualified Base.Text as Text
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text.Lazy as Text.Lazy
import Data.Word (Word8)
import Numeric (showHex)

import qualified Data.Graph.Inductive.Graph as FGL
import qualified Data.Graph.Inductive.PatriciaTree as FGL
import qualified Data.GraphViz as GV
import qualified Data.GraphViz.Attributes.Complete as GV

import L4.DependencyGraph
import L4.Syntax (Unique)

data DepGraphRenderOptions = MkDepGraphRenderOptions
  { slice :: !(Maybe (Set Unique))
    -- ^ draw only these nodes, and only the edges between them ('Nothing'
    -- draws everything); produce one with 'closure', 'closureUpTo' or
    -- 'reverseEdges'
  }
  deriving stock (Eq, Show)

defaultDepGraphRenderOptions :: DepGraphRenderOptions
defaultDepGraphRenderOptions = MkDepGraphRenderOptions {slice = Nothing}

-- ----------------------------------------------------------------------------
-- The shared view both renderers draw
-- ----------------------------------------------------------------------------

data GraphView = MkGraphView
  { nodes :: ![(Unique, DepNodeInfo)]
  , edges :: ![(Unique, Unique)]
  , surplus :: !(Set Unique)
  , cyclic :: !(Set Unique)
  }

graphView :: DepGraphRenderOptions -> DepGraph -> GraphView
graphView opts g =
  MkGraphView
    { nodes = [n | n@(u, _) <- Map.toList g.nodes, visible u]
    , edges =
        [ (a, b)
        | (a, bs) <- Map.toList g.edges
        , visible a
        , b <- Set.toList bs
        , visible b
        ]
    , surplus =
        if null g.entryPoints
          then Set.empty
          else unreachableFrom g RootsEntryPoints
    , cyclic = Set.fromList (concat (cyclicSccs g))
    }
 where
  visible u = maybe True (Set.member u) opts.slice

-- ----------------------------------------------------------------------------
-- DOT
-- ----------------------------------------------------------------------------

depGraphToDot :: DepGraphRenderOptions -> DepGraph -> Text
depGraphToDot opts g =
  Text.Lazy.toStrict (GV.printDotGraph (GV.graphToDot params fgl))
 where
  v = graphView opts g
  idx = Map.fromList (zip (map fst v.nodes) [0 :: Int ..])
  fgl :: FGL.Gr (Unique, DepNodeInfo) ()
  fgl =
    FGL.mkGraph
      (zip [0 ..] v.nodes)
      [(idx Map.! a, idx Map.! b, ()) | (a, b) <- v.edges]
  params =
    GV.nonClusteredParams
      { GV.globalAttributes =
          [ GV.GraphAttrs [GV.RankDir GV.FromTop, GV.FontName "Helvetica", GV.FontSize 14]
          , GV.NodeAttrs [GV.FontName "Helvetica", GV.FontSize 11]
          ]
      , GV.fmtNode = \(_, (u, i)) -> dotNodeAttrs v u i
      , GV.fmtEdge = const []
      }

dotNodeAttrs :: GraphView -> Unique -> DepNodeInfo -> [GV.Attribute]
dotNodeAttrs v u i =
  concat
    [ [GV.toLabel i.name, GV.Shape (kindShape i.kind)]
    , [GV.Tooltip (Text.Lazy.fromStrict d) | Just d <- [i.desc]]
    , if Set.member u v.surplus
        then
          [ GV.styles [GV.dashed, GV.filled]
          , GV.FillColor [GV.toWC (gvColor surplusFillRgb)]
          , GV.FontColor (gvColor surplusInkRgb)
          ]
        else
          [ GV.style GV.filled
          , GV.FillColor [GV.toWC (gvColor (kindRgb i.kind))]
          ]
    , if Set.member u v.cyclic
        then [GV.Color [GV.toWC (gvColor cyclicRgb)], GV.PenWidth 2]
        else []
    ]

kindShape :: DepKind -> GV.Shape
kindShape = \case
  DepFunction -> GV.BoxShape
  DepComputedField -> GV.BoxShape
  DepSelector -> GV.Ellipse
  DepConstructor -> GV.Hexagon
  DepAssume -> GV.Parallelogram

-- ----------------------------------------------------------------------------
-- Mermaid
-- ----------------------------------------------------------------------------

-- | The frozen first line of every Mermaid rendering.
mermaidHeader :: Text
mermaidHeader = "flowchart TD"

depGraphToMermaid :: DepGraphRenderOptions -> DepGraph -> Text
depGraphToMermaid opts g =
  Text.unlines $
    concat
      [ [mermaidHeader, "  %% an edge reads: source is defined in terms of target"]
      , map nodeLine v.nodes
      , map edgeLine v.edges
      , classLine "surplusage" (visIds v.surplus)
      , classLine "cyclic" (visIds v.cyclic)
      , [kindDef k | k <- nubOrd [i.kind | (_, i) <- v.nodes]]
      , [surplusageDef | not (null (visIds v.surplus))]
      , [cyclicDef | not (null (visIds v.cyclic))]
      ]
 where
  v = graphView opts g
  idx = Map.fromList (zip (map fst v.nodes) [0 :: Int ..])
  nid u = "n" <> Text.pack (show (idx Map.! u))
  nodeLine (u, i) =
    "  " <> nid u <> "[\"" <> mermaidLit i.name <> "\"]:::" <> kindClass i.kind
  edgeLine (a, b) = "  " <> nid a <> " --> " <> nid b
  visIds us = [nid u | u <- Set.toList us, Map.member u idx]
  classLine cls = \case
    [] -> []
    ids -> ["  class " <> Text.intercalate "," ids <> " " <> cls]
  kindDef k = "  classDef " <> kindClass k <> " fill:" <> hexColor (kindRgb k)
  surplusageDef =
    "  classDef surplusage fill:" <> hexColor surplusFillRgb
      <> ",color:" <> hexColor surplusInkRgb
      <> ",stroke-dasharray:5 5"
  cyclicDef =
    "  classDef cyclic stroke:" <> hexColor cyclicRgb <> ",stroke-width:2px"

kindClass :: DepKind -> Text
kindClass = \case
  DepFunction -> "depFunction"
  DepComputedField -> "depComputedField"
  DepSelector -> "depSelector"
  DepConstructor -> "depConstructor"
  DepAssume -> "depAssume"

-- | Mermaid double-quoted labels have no escape sequence, so problem
-- characters are folded away rather than escaped (the @lit@ discipline of
-- @ts-shared\/ladder-core\/src\/mermaid.ts@): @\"@ becomes a typographic
-- close-quote, backticks vanish, newlines become spaces.
mermaidLit :: Text -> Text
mermaidLit = Text.strip . Text.concatMap foldChar
 where
  foldChar = \case
    '"' -> "\x201d"
    '`' -> ""
    '\n' -> " "
    '\r' -> ""
    c -> Text.singleton c

-- ----------------------------------------------------------------------------
-- Palette
-- ----------------------------------------------------------------------------

-- One palette feeding two encodings ('gvColor' for DOT, 'hexColor' for
-- Mermaid), so the two renderings cannot drift apart.

kindRgb :: DepKind -> (Word8, Word8, Word8)
kindRgb = \case
  DepFunction -> (0xe8, 0xf4, 0xfd) -- light blue: a rule
  DepComputedField -> (0xe6, 0xdc, 0xf5) -- violet: a derived attribute
  DepSelector -> (0xff, 0xff, 0xff) -- white: a stored datum
  DepConstructor -> (0xfd, 0xe8, 0xcc) -- amber: schema
  DepAssume -> (0xd4, 0xed, 0xda) -- green: an exogenous input

surplusFillRgb, surplusInkRgb, cyclicRgb :: (Word8, Word8, Word8)
surplusFillRgb = (0xee, 0xee, 0xee)
surplusInkRgb = (0x6c, 0x75, 0x7d)
cyclicRgb = (0xdc, 0x35, 0x45)

gvColor :: (Word8, Word8, Word8) -> GV.Color
gvColor (r, grn, b) = GV.RGB r grn b

hexColor :: (Word8, Word8, Word8) -> Text
hexColor (r, grn, b) = "#" <> hex2 r <> hex2 grn <> hex2 b
 where
  hex2 w =
    let s = showHex w ""
    in Text.pack (replicate (2 - length s) '0' <> s)
