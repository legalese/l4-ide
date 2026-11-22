-- | The explored graph as a TLA+ module and TLC configurations
-- (REGULATIVE-LOWERING-SPEC.md §6.1, the @.tla + .cfg@ row; §4.6 for the
-- step encoding and the fairness).
--
-- == The module
--
-- @VARIABLES s, lastAct, beat@; @Init@ is the outset, state 0. Each action is
-- one label of the graph, the disjunction of its edges, and every edge is a
-- real step: it sets @lastAct@ to the action's name and flips @beat@, so a
-- self-loop changes @vars@ and is a step TLC sees, not a stutter (§4.6:
-- emitted as @UNCHANGED vars@ it would be invisible to fairness). @Next@ is
-- the disjunction of the actions, @Spec@ is
-- @Init /\ [][Next]_vars /\ WF_vars(Next)@, and @FairSpec@ adds weak
-- fairness on each fair action ("L4.Lts.Explore.Emit.Model"), on its moving
-- edges only (@WF_vars(A /\ s' # s)@) when some of its edges are
-- self-loops. Each boolean decision is an operator, the set of states the
-- evaluator labelled it TRUE in.
--
-- @WF_vars(Next)@ is in @Spec@ because the graph has no implicit stutter
-- (§4.6): every state has an edge, so some edge is always taken, which is
-- what NuSMV assumes of every path. Without it TLC lets the whole system
-- stutter forever, and the two disagree on the same graph: measured
-- 2026-10-26 on D1 with no fair action, TLC reported "eventually Alice has
-- bought or stopped" violated and NuSMV true (spec §1 finding 6, the
-- tools' disagreement, reproduced on emitted models). It makes no act
-- happen, since pausing forever satisfies it (§1 finding 11), so it is not
-- the fairness that P5 and P6 need; @FairSpec@ is.
--
-- @lastAct@ holds the action's identifier, not its label: SANY's lexer
-- rejects a backtick inside a string (measured with TLC 2.19, 2026-10-26:
-- @"a `b` c"@ is a lexical error), and every act of an L4 contract that
-- names its constructor in backticks has one. The label is in the comment
-- above each action.
--
-- == The configurations
--
-- TLC stops at the first property it finds violated, so one configuration
-- can give one verdict. @<base>.cfg@ is the model alone: TLC explores it,
-- checks that no state deadlocks, and checks no property. Each property has
-- its own @<base>.<name>.cfg@:
--
-- * __always__ @p@: @INVARIANT@ under @Spec@; it holds when TLC finds no error.
-- * __reachable__ @p@: TLC has no reachability check, so the configuration
--   asks for the @INVARIANT@ @~p@, and the property HOLDS when TLC reports
--   that invariant violated (the trace it prints is the witness). Said in
--   the configuration, since the reading is inverted.
-- * __stays__ @p@: @PROPERTY [](p => []p)@ under @Spec@.
-- * __eventually__ @p@ (@[]q => <>p@ with a premise): @PROPERTY@ under
--   @FairSpec@.
--
-- Safety is checked under @Spec@, without the per-action fairness, because
-- weak fairness on @Next@ or on sub-actions of it is machine-closed: it
-- rules out no finite prefix, so it cannot change a safety verdict.
module L4.Lts.Explore.Emit.Tla
  ( TlaFiles (..)
  , emitTla
  ) where

import Base
import qualified Base.Text as Text
import Base.Text (textShow)

import L4.Lts.Explore.Check (PropertyKind (..))
import L4.Lts.Explore.Emit.Model

data TlaFiles = MkTlaFiles
  { tfModule     :: !Text
    -- ^ @<base>.tla@
  , tfConfig     :: !Text
    -- ^ @<base>.cfg@, the model alone
  , tfProperties :: ![(Text, Text)]
    -- ^ @(<name>, text)@: one configuration per property, written as
    -- @<base>.<name>.cfg@
  }

emitTla :: Model -> TlaFiles
emitTla m = MkTlaFiles
  { tfModule = Text.unlines moduleLines
  , tfConfig = Text.unlines $
      [ "\\* " <> m.mdBase <> ".cfg: the model alone. TLC explores it and checks that no state deadlocks; it checks no property."
      , "\\* TLC stops at the first property it finds violated, so each property has its own configuration:" ]
      <> [ "\\*   " <> cfgName p <> "  " <> p.ppText | p <- m.mdProps ]
      <> (if null m.mdProps then ["\\*   (no property was named to l4 explore)"] else [])
      <> [ "SPECIFICATION FairSpec" ]
  , tfProperties = [ (p.ppIdent, propertyCfg p) | p <- m.mdProps ]
  }
  where
    cfgName p = m.mdBase <> "." <> p.ppIdent <> ".cfg"
    moduleLines =
      [ "---- MODULE " <> m.mdBase <> " ----" ]
      <> map comment m.mdHeader
      <> [ comment "" ]
      <> map comment (actionTable m)
      <> [ comment "" ]
      <> map comment (fairnessLines m)
      <> map comment [ "Not emitted: " <> p <> ": " <> why | (p, why) <- m.mdNotEmitted ]
      <> [ ""
         , "EXTENDS Naturals"
         , ""
         , "VARIABLES s, lastAct, beat"
         , "vars == <<s, lastAct, beat>>"
         , ""
         , "Init == s = 0 /\\ lastAct = \"outset\" /\\ beat = 0"
         , "" ]
      <> concatMap actionLines m.mdActions
      <> [ "Next ==" ]
      <> [ "  \\/ " <> a.eaIdent | a <- m.mdActions ]
      <> [ ""
         , comment "The graph has no implicit stutter: every state has an edge, a pause or a terminal state a self-loop that"
         , comment "is a real step. WF_vars(Next) says so to TLC, as NuSMV assumes it of every path; it makes no act happen,"
         , comment "since pausing forever satisfies it, which is why FairSpec adds weak fairness per labelled action."
         , "Spec == Init /\\ [][Next]_vars /\\ WF_vars(Next)"
         , ""
         , comment "Weak fairness per labelled action; the list, and why each other action has none, is in the header."
         , "FairSpec == Spec" <> Text.concat [ " /\\ " <> fairness a | a <- m.mdActions, a.eaFairness == Fair ]
         , "" ]
      <> (if null m.mdPredicates then [] else
           comment "Each boolean decision: the states the evaluator labelled it TRUE in." : concatMap predicateLines m.mdPredicates <> [""])
      <> (if null m.mdProps then [] else comment "The properties; each has its own configuration." : concatMap propLines m.mdProps <> [""])
      <> [ "====" ]
    actionLines a =
      [ comment a.eaLabel
      , a.eaIdent <> " ==" ]
      <> case a.eaEdges of
           [] -> [ "  /\\ FALSE" ]
           [(i, j)] -> [ "  /\\ s = " <> textShow i <> " /\\ s' = " <> textShow j ]
           e : es -> ("  /\\ \\/ " <> edge e) : [ "     \\/ " <> edge e' | e' <- es ]
      <> [ "  /\\ lastAct' = \"" <> a.eaIdent <> "\""
         , "  /\\ beat' = 1 - beat"
         , "" ]
    edge (i, j) = "(s = " <> textShow i <> " /\\ s' = " <> textShow j <> ")"
    fairness a
      | any (uncurry (==)) a.eaEdges = "WF_vars(" <> a.eaIdent <> " /\\ s' # s)"
      | otherwise = "WF_vars(" <> a.eaIdent <> ")"
    predicateLines p =
      [ comment ("`" <> p.pdDecision <> "`")
      , p.pdIdent <> " == s \\in {" <> Text.intercalate ", " (map textShow p.pdTrue) <> "}" ]
    propLines p =
      [ comment (p.ppText <> case p.ppKind of
                   Reachable -> ": as the invariant that it is never TRUE, which TLC reports violated when the property holds"
                   _ -> "")
      , p.ppIdent <> " == " <> formula p ]
    formula p = case p.ppKind of
      Always -> p.ppPred
      Reachable -> "~ " <> p.ppPred
      Stays -> "[](" <> p.ppPred <> " => [] " <> p.ppPred <> ")"
      Eventually -> case p.ppPremise of
        Nothing -> "<> " <> p.ppPred
        Just q -> "([] " <> q <> ") => (<> " <> p.ppPred <> ")"
    propertyCfg p = Text.unlines
      [ "\\* " <> p.ppText <> ", on " <> m.mdBase <> ".tla:"
      , "\\*   java -cp tla2tools.jar tlc2.TLC -config " <> cfgName p <> " " <> m.mdBase <> ".tla"
      , "\\* " <> reading p
      , "SPECIFICATION " <> (if p.ppKind == Eventually then "FairSpec" else "Spec")
      , (if p.ppKind `elem` [Always, Reachable] then "INVARIANT " else "PROPERTY ") <> p.ppIdent ]
    reading p = case p.ppKind of
      Reachable -> "The property HOLDS when TLC reports the invariant " <> p.ppIdent <> " violated (its trace is the witness), and is violated when TLC finds no error."
      Eventually -> "Under weak fairness per labelled action (FairSpec). The property holds when TLC finds no error, and is violated when TLC reports it violated (its trace is the lasso)."
      _ -> "Under Spec, whose one fairness condition cannot change a safety verdict. The property holds when TLC finds no error, and is violated when TLC reports it violated."
    comment t = if Text.null t then "\\*" else "\\* " <> t
