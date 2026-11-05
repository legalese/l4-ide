-- | The explored graph as a one-safe place/transition net in PNML
-- (REGULATIVE-LOWERING-SPEC.md §6.1, the @.pnml@ row), a picture target
-- built last (R-L7): one place per state, one transition per edge, with an
-- arc in from its source state and an arc out to its target, and one token
-- on the outset's place. A firing moves the one token along an edge, so the
-- net's reachable markings are the graph's states, one for one.
--
-- It is the graph as explored, edge for edge, like the @.aut@: a state with
-- no edge is a dead marking. It is not a door to a timed check (§6.1, D-L6):
-- an untimed explicit graph has no clocks to put on arcs.
module L4.Lts.Explore.Emit.Pnml (emitPnml) where

import Base
import qualified Base.Text as Text
import Base.Text (textShow)

import L4.Lts.Explore
import L4.Lts.Explore.Emit.Model (oneLine)
import L4.Print (prettyLayout)

emitPnml :: Text -> [Text] -> Graph -> Text
emitPnml base header g = Text.unlines $
  [ "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" ]
  <> [ "<!-- " <> commentSafe l <> " -->" | l <- header ]
  <> [ "<pnml xmlns=\"http://www.pnml.org/version-2009/grammar/pnml\">"
     , "  <net id=\"" <> base <> "\" type=\"http://www.pnml.org/version-2009/grammar/ptnet\">"
     , "    <name><text>" <> escape (oneLine (g.gStart.stName <> " at " <> prettyLayout g.gStart.stAt)) <> "</text></name>"
     , "    <page id=\"page0\">" ]
  <> concat
     [ [ "      <place id=\"s" <> textShow s.snId <> "\">"
       , "        <name><text>s" <> textShow s.snId <> "</text></name>" ]
       <> [ "        <initialMarking><text>1</text></initialMarking>" | s.snId == 0 ]
       <> [ "      </place>" ]
     | s <- g.gStates ]
  <> concat
     [ [ "      <transition id=\"t" <> textShow k <> "\">"
       , "        <name><text>" <> escape (oneLine t.tnLabel) <> "</text></name>"
       , "      </transition>"
       , "      <arc id=\"t" <> textShow k <> "_in\" source=\"s" <> textShow t.tnFrom <> "\" target=\"t" <> textShow k <> "\"/>"
       , "      <arc id=\"t" <> textShow k <> "_out\" source=\"t" <> textShow k <> "\" target=\"s" <> textShow t.tnTo <> "\"/>" ]
     | (k, t) <- zip [0 :: Int ..] g.gTransitions ]
  <> [ "    </page>"
     , "  </net>"
     , "</pnml>" ]
  where
    escape = Text.concatMap \ case
      '&'  -> "&amp;"
      '<'  -> "&lt;"
      '>'  -> "&gt;"
      '"'  -> "&quot;"
      '\'' -> "&apos;"
      c    -> Text.singleton c
    -- an XML comment may not hold two hyphens together ("---" needs two passes)
    commentSafe = spaced . oneLine
    spaced t = let t' = Text.replace "--" "- -" t in if t' == t then t else spaced t'
