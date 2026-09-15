{-# LANGUAGE OverloadedStrings #-}
-- | Dominators over a 'StateGraph': the acts every path to a state must
-- traverse.
--
-- This is the query the bounded-deontics paper calls @dom_s(J)@ and leaves
-- unimplemented (@paper\/bounded-deontics\/draft\/bd-sections-5-6.tex@,
-- Definition @def:dom@): an act @K@ dominates a goal @J@ from state @s@ iff
-- every path from @s@ that reaches @J@ contains a @K@-labelled transition.
-- Read off the extracted graph, that is the derived @MUST@ — /you must do
-- exactly those acts without which the goal is not reachable/ — and it
-- prints as a list. It needs no picture, which is why
-- @specs\/todo\/lexipedia-superset\/LTS-VISUALISER.md@ §1.1c unbundles it
-- from the rest of P2 (§7.2, row P2f).
--
-- == The algorithm
--
-- Dominance is the classical data-flow problem
--
-- > Dom(entry) = {entry}
-- > Dom(n)     = {n} ∪ ⋂ { Dom(p) | p a predecessor of n }
--
-- whose solution is the /greatest/ fixpoint, reached by starting every
-- reachable node at \"all nodes\" and iterating until nothing changes. That
-- is the formulation Cooper, Harvey & Kennedy start from in /A Simple, Fast
-- Dominance Algorithm/ (Rice CS TR-06-33870 — the report's own stamp; the
-- Rice repository catalogues the same file as TR06-38870,
-- <https://hdl.handle.net/1911/96345>), §2; their contribution is an
-- engineering of it — an immediate-dominator tree walked in reverse
-- postorder — that runs faster in practice than Lengauer & Tarjan (1979),
-- which the spec names. All three compute the same relation, by definition:
-- the dominator set of a node is unique, and any algorithm that computes it
-- computes exactly it. The graphs here are a few dozen nodes, so
-- 'dominators' solves the equations directly on sets and leaves the tree
-- encoding alone.
--
-- Two adaptations turn node dominance into the answer the spec asks for.
--
-- 1. __Acts are edges, not nodes.__ Every transition is subdivided into a
--    node of its own (@u → e → v@), so that \"every path passes through edge
--    @e@\" is the same statement as \"@e@ dominates @v@\" in the subdivided
--    graph. 'dominators' then reports only the edge nodes.
--
-- 2. __Neither @RAND@ nor @ROR@ has its join in the IR.__ A junction fans
--    out to its branches and each branch ends on the /shared/ sinks; nothing
--    waits for the siblings (LTS-VISUALISER §8, ruling R2). The evaluator's
--    join is in @L4.EvaluateLazy.Machine@, frames @RBinOp1@ \/ @RBinOp2@:
--    an @RAND@ is fulfilled only when /every/ branch is, and breached as
--    soon as /one/ is; an @ROR@ is fulfilled as soon as /one/ branch is,
--    and breached only when /every/ alternative has been lost. Read
--    literally, the drawn graph gets the \"one\" halves right and the
--    \"every\" halves wrong: a path through one @RAND@ branch reaches
--    @Fulfilled@, and a path through one @ROR@ branch reaches @Breach@, so
--    neither branch would dominate. 'fulfilmentView' and 'breachView'
--    supply the missing join, each for the one query that needs it: the
--    fulfilment view rewrites each @AllOf@ so its branches run in sequence
--    — branch 1's arrivals at @Fulfilled@ are re-pointed at branch 2's
--    entry, and so on, with only the last branch keeping its edge to the
--    sink — and the breach view does the same to each @ROR@-derived
--    @OneOf@ with arrivals at @Breach@. Dominance is insensitive to the
--    order acts occur in, so the set of edges every path to the sink
--    traverses in the sequential view is exactly the set every /run/ of the
--    concurrent contract traverses. An @IF@-derived @OneOf@ (its branch
--    edges carry a 'labelBranch') is genuinely exclusive — the facts pick
--    one arm and the others never run — and is left alone by both views.
--    An intermediate state lies inside one branch, so for it the literal
--    graph is already right. That premise is the extractor's to keep: a
--    named rule reached from two branches of one @RAND@ \/ @ROR@ is drawn
--    once per branch (@L4.StateGraph.extractFan@, since 2026-09-16), so no
--    state below a sequenced junction is shared between its branches. The
--    states a branch /can/ share are its ancestors, reached by a back-edge,
--    and a back-edge never arrives at a sink, so it is never redirected.
--
-- == What the answer means, and what it does not
--
-- It is a statement about the /drawn/ graph, and inherits its blind spots
-- (LTS-VISUALISER §1.1b): a @PROVIDED@ guard that can never be true still
-- draws its edge, two applications of one action pattern are one edge, and
-- deadlines are text. So \"every path passes through @K@\" is sound —
-- there is no drawn route around @K@ — while \"nothing dominates\" means
-- only that the graph shows more than one route, not that each is live.
-- One gap runs the other way: a bare single-party @PARTY … MAY@ whose
-- @HENCE@ leads on to another obligation can lapse straight to
-- @FULFILLED@, and the graph does not draw that route (see the note on
-- @DMay@ in 'extractDeonton'), so an act listed for @FULFILLED@ below such
-- a permission can in fact be bypassed. A quantified @EVERY … MAY@ under
-- either join line does draw its lapse, as a @LEST@ edge to @FULFILLED@,
-- so the answer below it is right ("nothing in particular").
--
-- Two narrowings of the paper's definition are deliberate: the question is
-- asked from the start state only (the paper's @dom_s(J)@ ranges over every
-- @s@), and it is asked per edge, not per action label — an act that appears
-- on two edges, say the same @sign@ in both arms of an @IF@, is two edges
-- here and dominates nothing, where the paper would count the label.
module L4.StateGraph.Dominators
  ( -- * The answer
    Dominance(..)
  , dominators
  , terminalDominators
  , allDominators
    -- * The views that supply @RAND@'s and @ROR@'s joins
  , fulfilmentView
  , breachView
    -- * Rendering for a reader
  , renderDominance
  , renderGraphDominators
  , renderTransition
  , namesAnAct
  , targetName
  ) where

import Base
import qualified Base.Map as Map
import qualified Base.Set as Set
import qualified Base.Text as Text

import L4.StateGraph
import L4.Syntax (DeonticModal(..))

--------------------------------------------------------------------------------
-- The answer
--------------------------------------------------------------------------------

-- | What every path from the entry state to a target must traverse.
data Dominance
  = Unreachable
    -- ^ No path from the entry state reaches the target, so the question
    -- has no answer. Also the verdict on a state id the graph does not have.
  | Dominated [Transition]
    -- ^ Every path to the target traverses each of these, listed in the
    -- graph's own transition order. Empty for the entry state itself, and
    -- for any target the graph offers more than one route to.
  deriving (Eq, Show)

-- | The transitions every path from the entry state to the target traverses.
--
-- A @TerminalFulfilled@ target is answered over 'fulfilmentView', a
-- @TerminalBreach@ target over 'breachView', and every other target over
-- the graph as given. See the module header for why.
dominators :: StateGraph -> StateId -> Dominance
dominators sg target
  | not (any (\s -> s.stateId == target) sg.sgStates) = Unreachable
  | otherwise =
      let edges | isFulfilledState sg target = joinEdges ForFulfilled sg
                | isBreachState sg target    = joinEdges ForBreach sg
                | otherwise                  = zip [0 ..] sg.sgTransitions
          doms = solveDominators (NState sg.sgInitialState) (subdivide edges)
      in case Map.lookup (NState target) doms of
           Nothing -> Unreachable
           Just ds ->
             let byIx = Map.fromList [(i, t) | (i, t) <- zip [0 :: Int ..] sg.sgTransitions]
                 ixs  = sort [i | NEdge i <- Set.toList ds]
             in Dominated (mapMaybe (`Map.lookup` byIx) ixs)

-- | 'dominators' for every terminal state — the @Fulfilled@ and @Breach@
-- sinks — in state order.
terminalDominators :: StateGraph -> [(ContractState, Dominance)]
terminalDominators sg =
  [ (s, dominators sg s.stateId)
  | s <- sg.sgStates
  , s.stateType `elem` [TerminalFulfilled, TerminalBreach]
  ]

-- | 'dominators' for every state, in state order.
allDominators :: StateGraph -> [(ContractState, Dominance)]
allDominators sg = [ (s, dominators sg s.stateId) | s <- sg.sgStates ]

isFulfilledState :: StateGraph -> StateId -> Bool
isFulfilledState sg sid =
  any (\s -> s.stateId == sid && s.stateType == TerminalFulfilled) sg.sgStates

isBreachState :: StateGraph -> StateId -> Bool
isBreachState sg sid =
  any (\s -> s.stateId == sid && s.stateType == TerminalBreach) sg.sgStates

fanOf :: StateGraph -> StateId -> FanKind
fanOf sg sid = maybe Linear (.stateFan) (find (\s -> s.stateId == sid) sg.sgStates)

--------------------------------------------------------------------------------
-- The dominator computation
--------------------------------------------------------------------------------

-- | A node of the subdivided graph: a state, or a transition (by its index
-- into 'sgTransitions') standing between its two states.
data Node = NState StateId | NEdge Int
  deriving (Eq, Ord, Show)

-- | Successor map of the subdivided graph: @u → e → v@ for each edge.
subdivide :: [(Int, Transition)] -> Map Node [Node]
subdivide edges = Map.fromListWith (<>) $
  concat [ [ (NState t.transFrom, [NEdge i]), (NEdge i, [NState t.transTo]) ]
         | (i, t) <- edges ]

-- | Solve the dominance equations by iteration to their greatest fixpoint,
-- over the nodes reachable from the entry. Unreachable nodes are absent
-- from the result: they have no dominators because they have no paths.
solveDominators :: Ord n => n -> Map n [n] -> Map n (Set n)
solveDominators entry succs =
  let reachable = reach Set.empty [entry]
      reach seen [] = seen
      reach seen (n : rest)
        | n `Set.member` seen = reach seen rest
        | otherwise = reach (Set.insert n seen) (fromMaybe [] (Map.lookup n succs) <> rest)
      preds = Map.fromListWith (<>)
        [ (v, [u]) | (u, vs) <- Map.toList succs, u `Set.member` reachable
                   , v <- vs, v `Set.member` reachable ]
      start = Map.fromSet (\n -> if n == entry then Set.singleton entry else reachable) reachable
      step doms = Map.mapWithKey (update doms) doms
      update doms n old
        | n == entry = old
        | otherwise =
            case fromMaybe [] (Map.lookup n preds) of
              []       -> old
              (p : ps) -> Set.insert n (foldl' (\acc q -> Set.intersection acc (doms Map.! q)) (doms Map.! p) ps)
      fixpoint doms = let doms' = step doms in if doms' == doms then doms else fixpoint doms'
  in fixpoint start

--------------------------------------------------------------------------------
-- The fulfilment and breach views
--------------------------------------------------------------------------------

-- | Which sink a sequential view is built for. The two are duals: to reach
-- @Fulfilled@ every @RAND@ branch must fulfil, and to reach @Breach@ every
-- @ROR@ alternative must be lost (@L4.EvaluateLazy.Machine@, @RBinOp2@: a
-- compound is breached when both operands are, \"for RAND because all
-- components must be fulfilled, for ROR because every alternative has been
-- definitively lost\").
data Sink = ForFulfilled | ForBreach
  deriving (Eq, Show)

-- | The graph with every @AllOf@ junction's branches run in sequence, so a
-- path to @Fulfilled@ has to complete all of them. This is the join the IR
-- does not carry (R2), supplied for the fulfilment query only; see the
-- module header. States are unchanged; transitions keep their labels and
-- may change target, and a junction's second and later branch edges are
-- dropped because the redirected arrivals replace them.
fulfilmentView :: StateGraph -> StateGraph
fulfilmentView sg = sg { sgTransitions = map snd (joinEdges ForFulfilled sg) }

-- | The dual of 'fulfilmentView': the graph with every @ROR@ junction's
-- branches run in sequence, so a path to @Breach@ has to lose all of them.
-- An @IF@-derived @OneOf@ is left alone — its arms are exclusive, and one
-- arm failing does breach the whole.
breachView :: StateGraph -> StateGraph
breachView sg = sg { sgTransitions = map snd (joinEdges ForBreach sg) }

-- | The sequential view for a sink, keeping each surviving transition's
-- index into the original 'sgTransitions' so the answer can name the
-- original edge.
joinEdges :: Sink -> StateGraph -> [(Int, Transition)]
joinEdges sink sg =
  let indexed = zip [0 :: Int ..] sg.sgTransitions
      outsOf s = [ e | e@(_, t) <- indexed, t.transFrom == s ]
      isBoundary s = isFulfilledState sg s || isBreachState sg s || s == sg.sgInitialState
      (isSink, sinkType) = case sink of
        ForFulfilled -> (isFulfilledState sg, TerminalFulfilled)
        ForBreach    -> (isBreachState sg, TerminalBreach)
      -- The junctions whose branches this view runs in sequence: every
      -- @AllOf@ for fulfilment; for breach every @OneOf@ that came from
      -- @ROR@, which is the one whose branch edges carry no 'labelBranch'
      -- ('fanLabel' sets it on @IF@ arms only, the trailing @ELSE@ included).
      -- Spelled out per constructor, with no wildcard, so that a fourth
      -- 'FanKind' has to say here what its join is.
      sequential n es = case fanOf sg n of
        AllOf  -> sink == ForFulfilled
        OneOf  -> sink == ForBreach && all (\(_, t) -> isNothing t.transLabel.labelBranch) es
        Linear -> False
      -- The walk's state: nodes seen, edge indices dropped, and where each
      -- redirected edge now points.
      (_, (_, dropped, redirected)) =
        runState (walkNode theSink sg.sgInitialState) (Set.empty, Set.empty, Map.empty)
      -- The exit of the whole contract: the sink if there is one. A graph
      -- with no sink has nothing to redirect towards, and no redirect ever
      -- fires (every candidate edge targets the sink), so the placeholder
      -- is never used.
      theSink = maybe (-1) (.stateId) (find (\s -> s.stateType == sinkType) sg.sgStates)

      -- Walk the region below a node with the exit its arrivals at the
      -- sink should be re-pointed at.
      walkNode exit n = do
        (seen, _, _) <- get
        unless (n `Set.member` seen) do
          modify (\(sn, dr, rd) -> (Set.insert n sn, dr, rd))
          let es = outsOf n
          if not (null es) && sequential n es
            then
              -- Branch k exits into branch k+1's entry — or, when that
              -- branch is the bare sink with no entry of its own, into
              -- whatever branch k+1 exits into. The last branch exits where
              -- the junction does.
              let exits = branchExits exit (map snd es)
              in forM_ (zip3 [0 :: Int ..] es exits) \(k, e, ex) ->
                   if k == 0 then walkEdge ex e
                   else do
                     modify (\(sn, dr, rd) -> (sn, Set.insert (fst e) dr, rd))
                     let v = (snd e).transTo
                     unless (isBoundary v) (walkNode ex v)
            else forM_ es (walkEdge exit)

      walkEdge exit (i, t)
        | isSink t.transTo =
            when (t.transTo /= exit) $ modify (\(sn, dr, rd) -> (sn, dr, Map.insert i exit rd))
        | isBoundary t.transTo = pure ()
        | otherwise = walkNode exit t.transTo

      branchExits exit = \case
        []           -> []
        [_]          -> [exit]
        (_ : rest@(next : _)) ->
          case branchExits exit rest of
            []              -> []
            rs@(nextEx : _) ->
              (if isSink next.transTo then nextEx else next.transTo) : rs

      retarget (i, t) = case Map.lookup i redirected of
        Just v  -> (i, t { transTo = v })
        Nothing -> (i, t)
  in [ retarget e | e@(i, _) <- indexed, not (i `Set.member` dropped) ]

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

-- | The name a reader knows a target by: the two sinks in capitals, as the
-- source spells them, and any other state by its label in quotes.
targetName :: ContractState -> Text
targetName s = case s.stateType of
  TerminalFulfilled -> "FULFILLED"
  TerminalBreach    -> "BREACH"
  -- A state is named after its obligation, whose party is source text and
  -- so may be back-quoted; the quotes are dropped here as they are for an
  -- act in 'renderTransition'.
  _                 -> "\"" <> Text.filter (/= '`') s.stateName <> "\""

-- | One answer, phrased for a reader, as lines.
renderDominance :: StateGraph -> ContractState -> Dominance -> [Text]
renderDominance sg s dom
  | s.stateId == sg.sgInitialState =
      [ targetName s <> " is the start state: nothing has to happen to be there." ]
  | otherwise = case dom of
      Unreachable ->
        [ "No path reaches " <> targetName s <> " from the start state." ]
      Dominated ts ->
        case mapMaybe (renderTransition sg) ts of
          [] -> [ "Every path to " <> targetName s <> " passes through: nothing in particular"
                  <> " (there is more than one route)." ]
          acts -> ("Every path to " <> targetName s <> " passes through:")
                  : [ "  - " <> a | a <- acts ]

-- | Every terminal state's answer for one graph, headed by the rule's name.
-- A graph with no terminal state at all — a rule whose arms are other named
-- rules, which extraction draws as dead-end states — says so rather than
-- printing a bare heading.
renderGraphDominators :: Bool -> StateGraph -> [Text]
renderGraphDominators everyState sg =
  sg.sgName : case (if everyState then allDominators else terminalDominators) sg of
    []      -> [ "  (this graph has no FULFILLED or BREACH state to reach)" ]
    answers -> [ "  " <> line | (s, d) <- answers, line <- renderDominance sg s d ]

-- | Whether the list would name this transition at all: the one predicate
-- the printed answer ('renderDominance') and the DOT annotation
-- (@L4.StateGraph.Dot.dominatorEmphasis@) share, so that an edge is marked
-- on the picture exactly when it is a line of the list.
namesAnAct :: StateGraph -> Transition -> Bool
namesAnAct sg = isJust . renderTransition sg

-- | A transition as a reader would name it, or 'Nothing' for one that names
-- no act — a bare @RAND@ \/ @ROR@ branch edge, which a party does not do.
--
-- Three shapes:
--
-- * an obligation: @PARTY B pays (MUST, WITHIN 3)@;
-- * a @LEST@ arm, which carries no party of its own, named by the obligation
--   it belongs to and by what takes it — the deadline passing, the
--   prohibited act, or the permission lapsing ('lestArm');
-- * an @IF@ arm: @the arm IF price EQUALS 20@.
renderTransition :: StateGraph -> Transition -> Maybe Text
renderTransition sg t = case t.transLabel.labelParty of
  -- The HENCE edge of a prohibition is taken by the deadline passing with
  -- the act NOT done (see the note on 'extractDeonton'): its label restates
  -- the rule, and read as an act on a path it would say the opposite.
  Just party
    | t.transType == HenceTransition, t.transLabel.labelModal == Just DMustNot
                -> Just (obligation party (l { labelAction = "refraining from " <> l.labelAction }))
    | otherwise -> Just (obligation party l)
  Nothing -> case t.transType of
    LestTransition -> Just (lestArm t)
    _ -> ("the arm IF " <>) <$> l.labelGuard
 where
  l = t.transLabel
  obligation party lbl =
    let modal    = maybe [] (\m -> [modalText m]) lbl.labelModal
        deadline = maybe [] (\d -> ["WITHIN " <> d]) lbl.labelDeadline
        guarded  = maybe [] (\g -> ["PROVIDED " <> g]) lbl.labelGuard
        joined   = maybe [] (\q -> maybe [] (\j -> [joinText j]) q.quantJoin) lbl.labelQuantifier
        details  = modal <> deadline <> guarded <> joined
        -- The party arrives as source text, so a multi-word name is
        -- back-quoted; the action arrives bare. Drop the quotes: this is a
        -- sentence for a reader, not a rule to re-parse.
        unquoted = Text.filter (/= '`') party
        subject  = if Text.isPrefixOf "EVERY " party then unquoted else "PARTY " <> unquoted
    in subject <> " " <> lbl.labelAction
         <> (if null details then "" else " (" <> Text.intercalate ", " details <> ")")

  -- The obligation whose LEST arm this is: the HENCE edge leaving the same
  -- state, which restates it. A LEST edge with no such sibling (a hand-built
  -- graph) falls back to the state's own name.
  lestArm lt =
    let owner = case find (\o -> o.transFrom == lt.transFrom && o.transType == HenceTransition
                                 && isJust o.transLabel.labelParty) sg.sgTransitions of
          Just o  -> maybe "" (\p -> obligation p o.transLabel) o.transLabel.labelParty
          Nothing -> "\"" <> stateNameOf lt.transFrom <> "\""
    in if lt.transLabel.labelAction == noTriggerWording
         then "the LEST arm of " <> owner <> ", which nothing can take (no WITHIN)"
         else case lt.transLabel.labelModal of
           Just DMustNot -> "the prohibited act being done: " <> owner
           Just DMay     -> "the permission lapsing: " <> owner
           _             -> "the deadline passing on " <> owner

  stateNameOf sid = maybe (Text.textShow sid) (.stateName) (find (\s -> s.stateId == sid) sg.sgStates)

  joinText j =
    let kind = case j.joinKind of
          Barrier th -> "ONCE " <> th
          Fork       -> "UPON EACH"
    in kind <> maybe "" (" WITHIN " <>) j.joinDeadline

modalText :: DeonticModal -> Text
modalText = \case
  DMust    -> "MUST"
  DMay     -> "MAY"
  DMustNot -> "SHANT"
  DDo      -> "DO"
