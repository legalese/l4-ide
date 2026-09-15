{-# LANGUAGE OverloadedStrings #-}
-- | The CodeLens entry point to the state graph, shared by both producers.
--
-- The ladder's "Show decision graph" lens is produced twice — once by the
-- language server (addressed by source position) and once by the wasm shim
-- (addressed by name), see @specs/todo/lexipedia-superset/LTS-VISUALISER.md@
-- §4.8 — and the two producers share nothing but the visualiser they call.
-- This module is the part of the state-graph lens that /can/ be shared: which
-- top-level @DECIDE@s earn a lens, how a lens target is found again from
-- either address, and the JSON payload a click returns.
--
-- The gate is the same speculative-success gate the ladder uses: a @DECIDE@
-- earns a lens exactly when 'extractStateGraphs' produced a graph for it. That
-- is decided by 'L4.StateGraph.findRegulativeExpr' on the body, so a boolean
-- rule never earns one — and, measured (R13, §8 of the spec), a regulative
-- rule never earns the ladder's, because 'L4.Viz.Ladder.translateDecide'
-- refuses any body that is not @BOOLEAN@. The two lenses never stack.
module L4.StateGraph.Lens
  ( -- * Which rules earn a lens
    StateGraphTarget(..)
  , stateGraphTargets
    -- * Finding the target again from a click
  , stateGraphAtPos
  , stateGraphByName
    -- * The payload
  , stateGraphResponse
  , stateGraphResponseText
  ) where

import Base
import qualified Data.Aeson as Aeson
import Data.Aeson ((.=))
import qualified Data.Map.Strict as Map
import qualified Data.Text.Lazy as LazyText
import qualified Data.Text.Lazy.Encoding as LazyText

import L4.Annotation (rangeOfNode)
import L4.Parser.SrcSpan (SrcPos, SrcRange(..))
import L4.Print (prettyLayout)
import L4.StateGraph
  ( StateGraph(..)
  , defaultStateGraphOptions
  , extractStateGraphs
  , stateGraphToDot
  )
import L4.Syntax
  ( AppForm(..)
  , Decide(..)
  , Module
  , Resolved
  , Unique
  , foldTopLevelDecides
  , getActual
  , getUnique
  )

-- | A top-level @DECIDE@ that has a state graph, with the two addresses a
-- lens click can come back under.
data StateGraphTarget = MkStateGraphTarget
  { targetDecide :: Decide Resolved
  , targetGraph  :: StateGraph
  , targetName   :: Text
    -- ^ The name as the wasm lens spells it: 'prettyLayout' of the defining
    -- occurrence, backticks included, exactly as
    -- 'L4.Viz.Ladder.findAllVisualizableDecides' spells @vdName@. Matching by
    -- this and not by 'sgName' keeps the name-addressed round trip
    -- self-consistent.
  , targetStart  :: SrcPos
    -- ^ Where the lens is anchored: the start of the @DECIDE@ node, the
    -- same anchor the ladder's lens uses.
  }

-- | Every top-level @DECIDE@ in the module that has a state graph, in source
-- order. A @DECIDE@ without a source range is skipped: nothing could anchor
-- a lens above it.
stateGraphTargets :: Module Resolved -> [StateGraphTarget]
stateGraphTargets mod' =
  foldTopLevelDecides target mod'
  where
    graphsByDecide :: Map Unique StateGraph
    graphsByDecide = Map.fromList
      [ (u, sg) | sg <- extractStateGraphs mod', Just u <- [sg.sgDecide] ]

    target :: Decide Resolved -> [StateGraphTarget]
    target d@(MkDecide _ _ (MkAppForm _ name _ _) _) =
      case (Map.lookup (getUnique name) graphsByDecide, rangeOfNode d) of
        (Just sg, Just rng) ->
          [ MkStateGraphTarget
              { targetDecide = d
              , targetGraph  = sg
              , targetName   = prettyLayout (getActual name)
              , targetStart  = rng.start
              }
          ]
        _ -> []

-- | The target whose @DECIDE@ starts at exactly this position — the LSP
-- lens's address.
stateGraphAtPos :: Module Resolved -> SrcPos -> Maybe StateGraphTarget
stateGraphAtPos mod' pos =
  listToMaybe [ t | t <- stateGraphTargets mod', t.targetStart == pos ]

-- | The target with exactly this name — the wasm lens's address.
stateGraphByName :: Module Resolved -> Text -> Maybe StateGraphTarget
stateGraphByName mod' name =
  listToMaybe [ t | t <- stateGraphTargets mod', t.targetName == name ]

-- | What a click returns, on both paths:
--
-- @
-- { "name": "the tenancy", "dot": "digraph { ... }" }
-- @
--
-- @dot@ is 'stateGraphToDot' with 'defaultStateGraphOptions' — deadlines,
-- guards and modals all shown. The host decides what to do with it.
stateGraphResponse :: StateGraph -> Aeson.Value
stateGraphResponse sg = Aeson.object
  [ "name" .= sg.sgName
  , "dot"  .= stateGraphToDot defaultStateGraphOptions sg
  ]

-- | 'stateGraphResponse', encoded — for the FFI edge, which speaks 'Text'.
stateGraphResponseText :: StateGraph -> Text
stateGraphResponseText = LazyText.toStrict . LazyText.decodeUtf8 . Aeson.encode . stateGraphResponse
