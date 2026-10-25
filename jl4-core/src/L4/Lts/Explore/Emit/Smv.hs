-- | The explored graph as a NuSMV model (REGULATIVE-LOWERING-SPEC.md §6.1,
-- the @.smv@ row: @VAR s@, @TRANS@, @DEFINE@ labels, @SPEC@/@LTLSPEC@,
-- @JUSTICE@).
--
-- @s@ is the state and @act@ the action of the step that reached it (the
-- @lastAct@ of the TLA+ module): the step's label is what weak fairness of
-- an action needs that @s@ does not give. It is a state variable, not an
-- @IVAR@, so that each fairness constraint is a predicate on states and
-- reads plainly on a path (NuSMV 2.7.0 does parse an @IVAR@ in a @JUSTICE@,
-- measured 2026-10-26; what it then means was not measured, so it is not
-- relied on). NuSMV has no stuttering, so every edge,
-- self-loops included, is a step of @TRANS@ and needs no @beat@. Weak
-- fairness of an action @A@, enabled in the states @E@, is
-- @JUSTICE !(s in E) | act = A@: infinitely often it is not enabled or was
-- just taken, which on an infinite path is exactly weak fairness. A fair
-- action that is a self-loop in some states records another value on those
-- (@<A>_still@), so that pausing on it never counts as taking it.
--
-- The properties, each with its @NAME@ (NuSMV prints the formula, not the
-- name, on its verdict line, and each formula names its own predicate):
--
-- * __always__ @p@: @INVARSPEC p@, which is decided by reachability, so no
--   fairness constraint and no state without a successor can change it, and
--   @SPEC AG p@, which must agree with it;
-- * __reachable__ @p@: @SPEC EF p@, and @INVARSPEC !p@, which must come out
--   FALSE when @EF p@ is TRUE (its counterexample is the witness);
-- * __stays__ @p@: @LTLSPEC G (p -> G p)@;
-- * __eventually__ @p@: @LTLSPEC F p@, and @(G q) -> F p@ with a premise.
--
-- CTL and LTL range over infinite paths, and over fair ones when there is a
-- @JUSTICE@. Every state has a successor here ('mdUnexplored' gets a
-- self-loop), and weak fairness on actions is machine-closed, so every
-- reachable state lies on a fair path and neither restriction drops one.
module L4.Lts.Explore.Emit.Smv (emitSmv) where

import Base
import qualified Base.Text as Text
import Base.Text (textShow)

import L4.Lts.Explore.Check (PropertyKind (..))
import L4.Lts.Explore.Emit.Model

emitSmv :: Model -> Text
emitSmv m = Text.unlines $
  map comment m.mdHeader
  <> [ comment "" ]
  <> map comment (actionTable m)
  <> [ comment "" ]
  <> map comment (fairnessLines m)
  <> map comment [ "Not emitted: " <> p <> ": " <> why | (p, why) <- m.mdNotEmitted ]
  <> [ ""
     , "MODULE main"
     , "VAR"
     , "  s : 0.." <> textShow (max 0 (m.mdStates - 1)) <> ";"
     , "  act : {" <> Text.intercalate ", " ("outset" : concatMap values m.mdActions) <> "};"
     , "INIT"
     , "  s = 0 & act = outset"
     , "TRANS" ]
  <> zipWith (\ k e -> (if k == (0 :: Int) then "     " else "   | ") <> e) [0 ..] transitions
  <> (if null m.mdPredicates then [] else
       "DEFINE" : concat [ [ "  " <> comment ("`" <> p.pdDecision <> "`: the states the evaluator labelled it TRUE in")
                           , "  " <> p.pdIdent <> " := " <> setOf p.pdTrue <> ";" ] | p <- m.mdPredicates ])
  <> [ "" ]
  <> (case [ a | a <- m.mdActions, a.eaFairness == Fair ] of
        [] -> [ comment "No JUSTICE: no action is fair (see the header)." ]
        fair -> comment "Weak fairness per labelled action: infinitely often, not enabled or just taken."
                : [ "JUSTICE !(" <> setOf (enabledIn a) <> ") | act = " <> a.eaIdent <> ";" | a <- fair ])
  <> concatMap propLines m.mdProps
  where
    values a = a.eaIdent : maybeToList a.eaStill
    transitions =
      [ "(s = " <> textShow i <> " & next(s) = " <> textShow j <> " & next(act) = " <> valueOf a (i, j) <> ")"
      | a <- m.mdActions, (i, j) <- a.eaEdges ]
    valueOf a (i, j) = case a.eaStill of
      Just still | i == j -> still
      _ -> a.eaIdent
    -- where a fair action is enabled: the sources of its moving edges
    enabledIn a = nubOrd [ i | (i, j) <- a.eaEdges, i /= j ]
    setOf = \ case
      [] -> "FALSE"
      is -> "s in {" <> Text.intercalate ", " (map textShow is) <> "}"
    propLines p =
      [ "", comment (p.ppText <> note p) ]
      <> case p.ppKind of
           Always ->
             [ "INVARSPEC NAME " <> p.ppIdent <> " := " <> p.ppPred <> ";"
             , "SPEC NAME " <> p.ppIdent <> "_ctl := AG " <> p.ppPred <> ";" ]
           Reachable ->
             [ "SPEC NAME " <> p.ppIdent <> "_ctl := EF " <> p.ppPred <> ";"
             , "INVARSPEC NAME " <> p.ppIdent <> " := !" <> p.ppPred <> ";" ]
           Stays ->
             [ "LTLSPEC NAME " <> p.ppIdent <> " := G (" <> p.ppPred <> " -> G " <> p.ppPred <> ");" ]
           Eventually ->
             [ "LTLSPEC NAME " <> p.ppIdent <> " := " <> case p.ppPremise of
                 Nothing -> "F " <> p.ppPred <> ";"
                 Just q -> "(G " <> q <> ") -> F " <> p.ppPred <> ";" ]
    note p = case p.ppKind of
      Always -> ": the invariant and the CTL form must agree"
      Reachable -> ": holds when EF is TRUE; the invariant that it is never TRUE must then be FALSE, and its trace is the witness"
      Stays -> ""
      Eventually -> ": under the JUSTICE constraints above"
    comment t = if Text.null t then "--" else "-- " <> t
