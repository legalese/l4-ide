{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE LambdaCase #-}
-- | GraphViz DOT rendering of a 'StateGraph'.
--
-- This is the drawing half of what used to be one module. It was split from
-- "L4.StateGraph" on 2026-09-16 for a reason of dependency, not of taste:
-- the picture wants to mark the acts every path to a terminal must traverse
-- ('showDominators'), that question is answered by "L4.StateGraph.Dominators",
-- and that module is a query over the IR which must not import the thing that
-- draws it. So the IR and its extraction stay in "L4.StateGraph", the query
-- imports them, and the renderer imports both.
--
-- Nothing in the default rendering changed with the move: with
-- 'defaultStateGraphOptions' the DOT is byte-identical to what
-- "L4.StateGraph" emitted before, measured over every corpus file
-- @l4 state-graph@ accepts (see LTS-VISUALISER.md §1.1c, the annotation's
-- LANDED block).
module L4.StateGraph.Dot
  ( -- * Options
    StateGraphOptions(..)
  , defaultStateGraphOptions
    -- * Rendering
  , stateGraphToDot
  ) where

import Base
import qualified Base.Map as Map
import qualified Base.Text as Text
import qualified Data.Text.Lazy as Text.Lazy

import L4.StateGraph
import L4.StateGraph.Dominators (Dominance (..), dominators, namesAnAct, targetName)
import L4.Syntax (DeonticModal (..))

-- GraphViz imports
import qualified Data.GraphViz as GV
import qualified Data.GraphViz.Attributes.Complete as GV
import Data.Graph.Inductive.Graph (Node, LNode, LEdge)
import qualified Data.Graph.Inductive.Graph as FGL
import qualified Data.Graph.Inductive.PatriciaTree as FGL

--------------------------------------------------------------------------------
-- Options
--------------------------------------------------------------------------------

-- | Options for state graph rendering
data StateGraphOptions = StateGraphOptions
  { showDeadlines   :: Bool   -- ^ Include temporal constraints on edges
  , showGuards      :: Bool   -- ^ Include PROVIDED conditions
  , compactLabels   :: Bool   -- ^ Use shorter labels
  , showModal       :: Bool   -- ^ Show deontic modal in labels
  , showDominators  :: Bool
    -- ^ Mark the edges every path to a terminal state must traverse — the
    -- answer @l4 state-graph --dominators@ prints as a list, drawn onto the
    -- picture instead: such an edge is bold, and its caption gains a line
    -- naming the terminal (@on every path to FULFILLED@). An edge on every
    -- path to both terminals says so on one line. Off by default, and with
    -- it off nothing here consults the dominators at all, so the default
    -- drawing is exactly what it was before the option existed.
  } deriving (Eq, Show)

-- | Default options with all information shown
defaultStateGraphOptions :: StateGraphOptions
defaultStateGraphOptions = StateGraphOptions
  { showDeadlines = True
  , showGuards    = True
  , compactLabels = False
  , showModal     = True
  , showDominators = False
  }

--------------------------------------------------------------------------------
-- GraphViz DOT Generation
--------------------------------------------------------------------------------

-- | Node attributes for FGL graph
data NodeAttrs = NodeAttrs
  { naLabel     :: Text
  , naFillColor :: Text
  , naShape     :: Text
  , naStyle     :: Text
  } deriving (Eq, Show)

-- | Edge attributes for FGL graph
data EdgeAttrs = EdgeAttrs
  { eaLabel :: Text
  , eaColor :: Text
  , eaStyle :: Text
  , eaBold  :: Bool   -- ^ drawn heavy: on every path to a terminal ('showDominators')
  } deriving (Eq, Show)

type ContractGraph = FGL.Gr NodeAttrs EdgeAttrs

-- | Convert a StateGraph to GraphViz DOT format
stateGraphToDot :: StateGraphOptions -> StateGraph -> Text
stateGraphToDot opts sg =
  let graph = buildFGLGraph opts sg
      dotGraph = graphToDot opts sg graph
  in Text.Lazy.toStrict $ GV.printDotGraph dotGraph

-- | Build an FGL graph from a StateGraph
buildFGLGraph :: StateGraphOptions -> StateGraph -> ContractGraph
buildFGLGraph opts sg@StateGraph{..} =
  let fanOf sid = maybe Linear (.stateFan) (find (\s -> s.stateId == sid) sgStates)
      emphasis = if opts.showDominators then dominatorEmphasis sg else Map.empty
      nodes = map (stateToNode opts) sgStates
      edges = [ transitionToEdge opts (fanOf t.transFrom) (Map.lookup i emphasis) t
              | (i, t) <- zip [0 ..] sgTransitions ]
  in FGL.mkGraph nodes edges

-- | For each transition (by its index into 'sgTransitions') on every path to
-- a terminal state, the terminals it is on every path to, named as
-- @--dominators@ names them. Absent for an edge that dominates nothing, and
-- absent for an edge the list would not name either: a bare @RAND@ \/ @ROR@
-- branch edge is on every path to whatever lies below it, but a party does
-- not /do/ a branch edge, so 'renderTransition' leaves it out of the list —
-- and the same predicate ('namesAnAct') leaves it unmarked here, so that the
-- picture is the list drawn and nothing more. Until 2026-09-16 the first
-- branch edge of every sequenced @RAND@ was drawn heavy with the caption
-- \"on every path to FULFILLED\" while its siblings were not, an artefact of
-- the sequential view that the list never showed.
--
-- Matched by value: 'dominators' answers in transitions, not indices, so two
-- byte-identical edges would both be marked if either were. The one shape
-- that drew such a pair — @z RAND z@, two blank branch edges from the
-- junction to one memoised @z@, until 2026-09-16 — now draws two @z@
-- states, and a branch edge is filtered out above regardless; should
-- another pair arise, the two are indistinguishable to a reader anyway.
dominatorEmphasis :: StateGraph -> Map Int [Text]
dominatorEmphasis sg =
  Map.fromListWith (flip (<>))
    [ (i, [targetName s])
    | s <- sg.sgStates
    , s.stateType `elem` [TerminalFulfilled, TerminalBreach]
    , Dominated ts <- [dominators sg s.stateId]
    , (i, t) <- zip [0 ..] sg.sgTransitions
    , t `elem` ts
    , namesAnAct sg t
    ]

-- | Convert a ContractState to an FGL node
stateToNode :: StateGraphOptions -> ContractState -> LNode NodeAttrs
stateToNode _ ContractState{..} =
  let (fillColor, shape, style) = case (stateFan, stateType) of
        -- Junctions are drawn as diamonds and say outright which kind they
        -- are; the fan-out is the whole point of the node.
        (AllOf, _)                    -> (allOfColor, "diamond", "filled")
        (OneOf, _)                    -> (oneOfColor, "diamond", "filled")
        (Linear, InitialState)        -> ("#e8f4fd", "ellipse", "filled")
        (Linear, IntermediateState)   -> ("#ffffff", "ellipse", "filled")
        (Linear, TerminalFulfilled)   -> ("#d4edda", "doublecircle", "filled")
        (Linear, TerminalBreach)      -> ("#f8d7da", "doublecircle", "filled")
      attrs = NodeAttrs
        { naLabel     = stateName <> fanSuffix stateFan
        , naFillColor = fillColor
        , naShape     = shape
        , naStyle     = style
        }
  in (stateId, attrs)

-- | Fill colour for an @RAND@ junction (violet).
allOfColor :: Text
allOfColor = "#e6dcf5"

-- | Fill colour for an @ROR@ junction (amber).
oneOfColor :: Text
oneOfColor = "#fde8cc"

-- | The junction kind, spelled out on the node label so no reader has to
-- infer it from the shape alone.
fanSuffix :: FanKind -> Text
fanSuffix = \case
  Linear -> ""
  AllOf  -> "\nALL OF"
  OneOf  -> "\nONE OF"

-- | Convert a Transition to an FGL edge. The 'FanKind' is that of the
-- transition's source state: edges leaving a junction are branch selections,
-- not obligations, and are drawn to match the junction. The terminals, when
-- given, are those the edge is on every path to; the caption says so and
-- the edge is drawn heavy.
transitionToEdge :: StateGraphOptions -> FanKind -> Maybe [Text] -> Transition -> LEdge EdgeAttrs
transitionToEdge opts fromFan mDominates Transition{..} =
  let label = formatTransitionLabel opts transLabel
      (color, style) = case (transType, fromFan) of
        (DefaultTransition, AllOf) -> (allOfEdgeColor, "solid")  -- Violet: every branch
        (DefaultTransition, OneOf) -> (oneOfEdgeColor, "dotted") -- Amber: one branch
        (HenceTransition, _)       -> ("#28a745", "solid")       -- Green for success
        (LestTransition, _)        -> ("#dc3545", "dashed")      -- Red dashed for failure
        (DefaultTransition, _)     -> ("#6c757d", "solid")       -- Gray for neutral
      -- A junction's branch edge has no caption of its own, so the note is
      -- the whole label rather than a second line under nothing.
      dominatesNote = case mDominates of
        Nothing -> ""
        Just ts -> (if Text.null label then "" else "\n")
                   <> "on every path to " <> Text.intercalate " and to " ts
      attrs = EdgeAttrs
        { eaLabel = label <> dominatesNote
        , eaColor = color
        , eaStyle = style
        , eaBold  = isJust mDominates
        }
  in (transFrom, transTo, attrs)

-- | Edge colour out of an @RAND@ junction.
allOfEdgeColor :: Text
allOfEdgeColor = "#6f42c1"

-- | Edge colour out of an @ROR@ junction.
oneOfEdgeColor :: Text
oneOfEdgeColor = "#e8850c"

-- | Format a transition label for display
formatTransitionLabel :: StateGraphOptions -> TransitionLabel -> Text
formatTransitionLabel opts TransitionLabel{..} =
  let -- The modal is a qualifier on a party's action — "Alice MUST pay" — so it
      -- is drawn only where there is a party to qualify. A LEST edge carries the
      -- modal for consumers that hold only that edge, but its caption is not a
      -- restatement of the rule; it names what became of it. "SHANT violation"
      -- would read as a second and contradictory copy of the obligation.
      modalPart
        | not opts.showModal = Nothing
        | isNothing labelParty = Nothing
        | otherwise = fmap formatModal labelModal
      parts = catMaybes
        [ labelParty
        , modalPart
        , Just labelAction
        , if opts.showDeadlines then fmap (\d -> "[" <> d <> "]") labelDeadline else Nothing
        , if opts.showGuards then fmap (\g -> "IF " <> g) labelGuard else Nothing
        ]
      -- The join line, as the source spells it, on a line of its own under the
      -- obligation — the one place the picture says whether the continuation
      -- fires once or once per member.
      joinPart = do
        q <- labelQuantifier
        j <- q.quantJoin
        let kind = case j.joinKind of
              Barrier th -> "ONCE " <> th
              Fork       -> "UPON EACH"
            dl | opts.showDeadlines = maybe "" (" WITHIN " <>) j.joinDeadline
               | otherwise          = ""
        pure (kind <> dl)
  in Text.intercalate " " parts <> maybe "" ("\n" <>) joinPart

-- | Format a deontic modal for display
formatModal :: DeonticModal -> Text
formatModal = \case
  DMust    -> "MUST"
  DMay     -> "MAY"
  DMustNot -> "SHANT"
  DDo      -> "DO"

-- | Convert FGL graph to GraphViz DotGraph
graphToDot :: StateGraphOptions -> StateGraph -> ContractGraph -> GV.DotGraph Node
graphToDot _opts StateGraph{..} graph =
  GV.graphToDot params graph
  where
    params = GV.nonClusteredParams
      { GV.globalAttributes =
          [ GV.GraphAttrs
              [ GV.RankDir GV.FromTop
              , GV.Label (GV.StrLabel (Text.Lazy.fromStrict sgName))
              , GV.LabelLoc GV.VTop
              , GV.FontName "Helvetica"
              , GV.FontSize 14
              ]
          , GV.NodeAttrs
              [ GV.FontName "Helvetica"
              , GV.FontSize 11
              ]
          , GV.EdgeAttrs
              [ GV.FontName "Helvetica"
              , GV.FontSize 10
              ]
          ]
      , GV.fmtNode = \(_, attrs) ->
          [ GV.toLabel attrs.naLabel
          , GV.FillColor [GV.toWC (GV.X11Color GV.White)]
          , GV.style (parseStyle attrs.naStyle)
          , GV.Shape (parseShape attrs.naShape)
          , GV.FillColor [GV.toWC (parseColor attrs.naFillColor)]
          ]
      , GV.fmtEdge = \(_, _, attrs) ->
          [ GV.toLabel attrs.eaLabel
          , GV.Color [GV.toWC (parseColor attrs.eaColor)]
          , GV.style (parseEdgeStyle attrs.eaStyle)
          ]
          -- Appended, not merged into the style: a dashed edge stays dashed
          -- and only gets heavier, and an unmarked edge's attribute list is
          -- exactly what it was, so the default output cannot drift.
          <> [ GV.PenWidth 3 | attrs.eaBold ]
      }

-- | Parse a style string
parseStyle :: Text -> GV.Style
parseStyle "filled" = GV.filled
parseStyle _        = GV.filled

-- | Parse an edge style string
parseEdgeStyle :: Text -> GV.Style
parseEdgeStyle "dashed" = GV.dashed
parseEdgeStyle "dotted" = GV.dotted
parseEdgeStyle _        = GV.solid

-- | Parse a shape string
parseShape :: Text -> GV.Shape
parseShape "doublecircle" = GV.DoubleCircle
parseShape "box"          = GV.BoxShape
parseShape "diamond"      = GV.DiamondShape
parseShape _              = GV.Ellipse

-- | Parse a hex color to GraphViz color
parseColor :: Text -> GV.Color
parseColor hex = case Text.unpack hex of
  ('#':r1:r2:g1:g2:b1:b2:[]) ->
    let r = read ("0x" ++ [r1, r2]) :: Int
        g = read ("0x" ++ [g1, g2]) :: Int
        b = read ("0x" ++ [b1, b2]) :: Int
    in GV.RGB (fromIntegral r) (fromIntegral g) (fromIntegral b)
  _ -> GV.X11Color GV.Gray
