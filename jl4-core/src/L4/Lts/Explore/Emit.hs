-- | @l4 explore --emit@ (REGULATIVE-LOWERING-SPEC.md §6.1, work package
-- WP3): the explored graph, written for the tools that check what the
-- in-process checker cannot (liveness under fairness, §5.3) and for the
-- tools that draw it. Every emitter reads the graph, through
-- "L4.Lts.Explore.Emit.Model"; none interprets L4.
--
-- The files, in the order §6.1 builds them (ruled R-L7):
--
-- 1. @<base>.aut@, mCRL2's Aldebaran format, the form the bisimulation
--    against the probes' hand models reads (§6.2): "L4.Lts.Explore.Emit.Aut";
-- 2. @<base>.tla@ with @<base>.cfg@ and one @<base>.<property>.cfg@ per
--    property, for TLC, and @<base>.smv@, for NuSMV, built together because
--    no liveness verdict is quoted until the two agree (§6.3):
--    "L4.Lts.Explore.Emit.Tla", "L4.Lts.Explore.Emit.Smv";
-- 3. @<base>.dot@, GraphViz, which is 'graphDot' of WP1;
-- 4. @<base>.pnml@, a one-safe net, last, as a picture target:
--    "L4.Lts.Explore.Emit.Pnml".
module L4.Lts.Explore.Emit
  ( EmitInput (..)
  , fairMatches
  , emitBase
  , emitFiles
  ) where

import Base
import qualified Base.Text as Text

import L4.Lts.Explore (Graph (..), graphDot)
import L4.Lts.Explore.Emit.Aut (emitAut)
import L4.Lts.Explore.Emit.Model
import L4.Lts.Explore.Emit.Pnml (emitPnml)
import L4.Lts.Explore.Emit.Smv (emitSmv)
import L4.Lts.Explore.Emit.Tla (TlaFiles (..), emitTla)

-- | The base name of the files for one contract of a file: the file's stem
-- as an identifier (a TLA+ module is named for its file, and may not hold a
-- hyphen), with the contract's number after it when the file has several.
emitBase :: Text -> Int -> Int -> Text
emitBase stem total k
  | total > 1 = identifier stem <> "_" <> Text.pack (show k)
  | otherwise = identifier stem

-- | Every file, by name, in the order of §6.1; 'Left' for a file that
-- cannot be written faithfully, with why (the others are still given).
emitFiles :: EmitInput -> [Either Text (Text, Text)]
emitFiles ei =
  [ (\ t -> (base <> ".aut", t)) <$> first ((base <> ".aut: ") <>) (emitAut (length ei.eiGraph.gStates) ei.eiGraph.gTransitions)
  , Right (base <> ".tla", tla.tfModule)
  , Right (base <> ".cfg", tla.tfConfig) ]
  <> [ Right (base <> "." <> name <> ".cfg", cfg) | (name, cfg) <- tla.tfProperties ]
  <> [ Right (base <> ".smv", emitSmv model)
     , Right (base <> ".dot", graphDot ei.eiGraph)
     , Right (base <> ".pnml", emitPnml base model.mdHeader ei.eiGraph) ]
  where
    base = ei.eiBase
    model = buildModel ei
    tla = emitTla model
