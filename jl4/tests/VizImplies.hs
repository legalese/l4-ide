-- | The SEAM survives the pipeline (ladder DESIGN §25a).
--
-- @IMPLIES@ is the join between a rule's scope and its requirement, and the ladder
-- has to draw it as one. The standing hazard is 'L4.Transform.simplify', whose whole
-- job is to reach CNF and whose first act is therefore to rewrite @P IMPLIES Q@ into
-- @NOT P OR Q@ — truth-functionally perfect, and shape-destroying. It throws away the
-- scope/requirement split (the first two questions anyone asks of a rule), and it
-- leaves the picture unable to distinguish the two cases a reader most needs
-- distinguished: a case the rule never reached (N/A) and a case that complies. Both
-- satisfy @NOT P OR Q@.
--
-- These tests pin the fix at the only place it can be pinned — the wire IR that comes
-- out of the visualiser — because a silent regression here is invisible: the diagram
-- would still be CORRECT, just no longer FAITHFUL, which is the exact failure mode
-- @logic-not-flowcharts.md@ convicts flowcharts of.
module VizImplies (spec) where

import Base

import L4.API.VirtualFS (checkWithImports, emptyVFS, TypeCheckWithDepsResult (..))
import L4.Names (getName)
import L4.Syntax
import qualified L4.Viz.VizExpr as V

import qualified LSP.L4.Viz.Ladder as Ladder

import Language.LSP.Protocol.Types (VersionedTextDocumentIdentifier (..))
import Test.Hspec

-- | A rule with the shape of a real one: a scope, a requirement, and a seam.
-- Both sides are compound, so we can also check that each side is still simplified
-- INSIDE its panel (simplification is a readability win there — it is only across the
-- seam that it destroys something).
impliesSrc :: Text
impliesSrc =
  "GIVEN upper IS A BOOLEAN\n\
  \      side IS A BOOLEAN\n\
  \      glazed IS A BOOLEAN\n\
  \      shut IS A BOOLEAN\n\
  \DECIDE compliant IF\n\
  \  (upper AND side) IMPLIES (glazed AND shut)\n"

-- | The same rule with the symbolic spelling.
arrowSrc :: Text
arrowSrc =
  "GIVEN upper IS A BOOLEAN\n\
  \      glazed IS A BOOLEAN\n\
  \DECIDE compliant IF\n\
  \  upper => glazed\n"

-- | An implication NESTED inside a conjunction. The two-sink form is top-level only
-- (v1) — a buried implication has nowhere to hang its lamps — so this one is expected
-- to fall back to the classical reading. What it must NOT do is what the old code did:
-- fall through to 'leafFromExpr' and swallow the whole implication into one opaque box.
nestedSrc :: Text
nestedSrc =
  "GIVEN a IS A BOOLEAN\n\
  \      b IS A BOOLEAN\n\
  \      c IS A BOOLEAN\n\
  \DECIDE compliant IF\n\
  \  c AND (a IMPLIES b)\n"

spec :: Spec
spec = describe "IMPLIES is a seam, not sugar (ladder DESIGN §25a)" $ do
  -- The regression that matters. `simplify` is ON in the LSP's default viz path, and
  -- it is precisely the thing that used to eat the connective.
  it "survives simplify=True: the ladder still sees an Implies, not NOT P OR Q" $
    case vizBody True impliesSrc of
      V.Implies _ scope requirement _ -> do
        -- the SPLIT is the point: scope on one side of the seam, requirement on the
        -- other, each still simplified in its own right
        atomsOf scope `shouldBe` ["upper", "side"]
        atomsOf requirement `shouldBe` ["glazed", "shut"]
      other ->
        expectationFailure $
          "simplify ate the seam; the ladder got: " <> show other

  it "survives simplify=False too" $
    case vizBody False impliesSrc of
      V.Implies _ _ _ seam -> seam `shouldBe` "IMPLIES"
      other -> expectationFailure $ "expected an Implies, got: " <> show other

  -- §25e, as far as it can actually go. `=>` is normalised to IMPLIES, and NOT because
  -- we chose to: the typechecker desugars every binop into a function application and
  -- rebuilds the annotation as bare holes, so the operator token is destroyed before
  -- the visualiser ever runs (the node is resugared back to an Implies afterwards, but
  -- token-less). See 'Ladder.seamLabel'. This test pins the behaviour so the erasure is
  -- a known, deliberate fact rather than a surprise — and so it fails loudly if someone
  -- later teaches the desugarer to preserve concrete syntax, which is the fix.
  it "the symbolic spelling => is normalised to IMPLIES (the token is erased upstream)" $
    case vizBody True arrowSrc of
      V.Implies _ _ _ seam -> seam `shouldBe` "IMPLIES"
      other -> expectationFailure $ "expected an Implies, got: " <> show other

  -- The negative half of the claim: the seam is NOT smuggled in everywhere. A nested
  -- implication is read classically, on purpose, and says so by its shape.
  it "a NESTED implication falls back to the classical reading, not to an opaque box" $
    case vizBody False nestedSrc of
      V.And _ args -> do
        length (filter isOr args) `shouldBe` 1
        -- three real atoms survive; nothing was swallowed into a single leaf
        sort (concatMap atomsOf args) `shouldBe` ["a", "b", "c"]
      other -> expectationFailure $ "expected an And, got: " <> show other

  -- The seam is not a barrier to the atom walk. If it were, every TYPICALLY inside a
  -- scope or requirement would silently vanish from the question-ordering priors —
  -- a failure that produces no error, just a quietly worse wizard.
  it "atoms on BOTH sides of the seam are reachable to the prior walk" $
    let body = vizBody True typicallySrc
     in V.boolPriorsFromBody body `shouldSatisfy` ((== 2) . length)

-- | Boolean TYPICALLYs on either side of the seam.
typicallySrc :: Text
typicallySrc =
  "GIVEN upper IS A BOOLEAN TYPICALLY TRUE\n\
  \      glazed IS A BOOLEAN TYPICALLY FALSE\n\
  \DECIDE compliant IF\n\
  \  upper IMPLIES glazed\n"

------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------

-- | Typecheck a source, visualise its @compliant@ DECIDE, and hand back the wire body.
vizBody :: Bool -> Text -> V.IRExpr
vizBody simplify src =
  case checkWithImports emptyVFS src of
    Left errs -> error ("source failed to typecheck: " <> show errs)
    Right tc ->
      let verDoc = VersionedTextDocumentIdentifier (fromNormalizedUri tc.tcdUri) 0
          cfg = Ladder.mkVizConfig verDoc tc.tcdModule tc.tcdSubstitution simplify
       in case Ladder.doVisualize (findDecide "compliant" tc.tcdModule) cfg of
            Right (info, _) -> info.funDecl.body
            Left e -> error ("doVisualize failed: " <> show e)

findDecide :: Text -> Module Resolved -> Decide Resolved
findDecide nm m =
  case foldTopLevelDecides (\d -> [d | matches d]) m of
    (d : _) -> d
    [] -> error ("findDecide: no top-level DECIDE named " <> show nm)
  where
    matches (MkDecide _ _ af _) = nameToText (getName af) == nm

-- | The atom labels under a node, in source order.
atomsOf :: V.IRExpr -> [Text]
atomsOf = \case
  V.UBoolVar _ nm _ _ _ _ -> [nm.label]
  V.And _ es -> concatMap atomsOf es
  V.Or _ es -> concatMap atomsOf es
  V.Not _ e -> atomsOf e
  V.Implies _ p q _ -> atomsOf p <> atomsOf q
  V.App _ _ es _ -> concatMap atomsOf es
  _ -> []

isOr :: V.IRExpr -> Bool
isOr = \case
  V.Or{} -> True
  _ -> False
