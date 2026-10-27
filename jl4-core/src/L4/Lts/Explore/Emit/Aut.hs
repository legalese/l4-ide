-- | The explored graph in mCRL2's Aldebaran format (@.aut@), the form the
-- bisimulation of REGULATIVE-LOWERING-SPEC.md §6.2 reads: @des (0,T,S)@,
-- then one line per edge, @(from,"label",to)@, state 0 the initial one.
--
-- It is the graph as explored, edge for edge: no @unexplored@ self-loop is
-- added (mCRL2 reads a state with no successor as a deadlock, which is what
-- it is), and the labels are the graph's own, on one line.
--
-- Two things mCRL2's reader does with a label, measured with
-- @ltsinfo@/@ltsconvert@ of mCRL2 202607.0 on 2026-10-26, so that neither
-- happens silently: a double quote inside a label ends it, with no escape
-- (@\"@ is refused: "Expect a comma after the quoted label"), so each one
-- is written as a single quote; and the label @tau@ is the silent action.
-- A file in which either would merge two labels, or make one silent, is
-- refused, by name, rather than written.
module L4.Lts.Explore.Emit.Aut (emitAut) where

import Base
import qualified Base.Map as Map
import qualified Base.Text as Text
import Base.Text (textShow)

import L4.Lts.Explore
import L4.Lts.Explore.Emit.Model (oneLine)

-- | The file for a graph of this many states and these transitions, in
-- order ('gStates' and 'gTransitions'; nothing else of the graph is read).
emitAut :: Int -> [Transition] -> Either Text Text
emitAut states transitions = do
  let labels = nubOrd (map (.tnLabel) transitions)
      spelled = Map.fromList [ (l, spell l) | l <- labels ]
      spell = Text.replace "\"" "'" . oneLine
      collisions = Map.filter ((> 1) . length) (Map.fromListWith (<>) [ (spell l, [l]) | l <- labels ])
  for_ (Map.toList collisions) \ (s, ls) ->
    Left ("the labels " <> Text.intercalate " and " (map (\ l -> "\"" <> l <> "\"") (reverse ls))
          <> " would both be written \"" <> s <> "\" (mCRL2's .aut reader cannot escape a double quote), so the .aut would merge them")
  for_ labels \ l -> when (spell l == "tau") $
    Left ("the label \"" <> l <> "\" would be written tau, which is mCRL2's silent action")
  Right $ Text.unlines $
    ("des (0," <> textShow (length transitions) <> "," <> textShow states <> ")")
    : [ "(" <> textShow t.tnFrom <> ",\"" <> Map.findWithDefault (spell t.tnLabel) t.tnLabel spelled <> "\"," <> textShow t.tnTo <> ")"
      | t <- transitions ]
