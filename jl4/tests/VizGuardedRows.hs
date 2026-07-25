-- | A guarded chain over boolean bodies is ladder structure, not a leaf
-- (specs/todo/lexipedia-superset/GUARDED-ROWS.md).
--
-- @IF-THEN-ELSE@, @BRANCH@ and @CONSIDER@ used to fall through 'translateExpr' to
-- 'leafFromExpr', which labels ONE box with 'prettyLayout' of the whole expression.
-- The R1 corpus spike measured what that costs: 17 of the 22 widest diagrams in the
-- corpus were single leaves, the worst 4372px wide holding 247 characters of raw L4,
-- with its newlines collapsed to spaces by SVG @\<text\>@. A whole decision table
-- rendered as an unreadable ribbon.
--
-- But a first-match guarded chain over BOOLEAN bodies has an exact And/Or reading:
-- row @i@ fires iff @gᵢ@ holds and no earlier guard did. These tests pin both halves
-- of that claim — the expansion where it applies, and the bail-out where it does not,
-- because a wrong expansion is worse than no expansion: it would be a diagram that
-- reads fluently and states a different rule.
module VizGuardedRows (spec) where

import Base

import L4.API.VirtualFS (checkWithImports, emptyVFS, TypeCheckWithDepsResult (..))
import L4.Names (getName)
import L4.Syntax
import qualified L4.Viz.VizExpr as V

import qualified LSP.L4.Viz.Ladder as Ladder

import Language.LSP.Protocol.Types (VersionedTextDocumentIdentifier (..))
import Test.Hspec

------------------------------------------------------------------------
-- sources
------------------------------------------------------------------------

-- | The degenerate chain everyone writes by accident. Renders today as a box
-- containing the string @"IF c THEN TRUE ELSE FALSE"@.
ifTrueFalse :: Text
ifTrueFalse =
  "GIVEN c IS A BOOLEAN\n\
  \DECIDE compliant IF\n\
  \  IF c THEN TRUE ELSE FALSE\n"

ifFalseTrue :: Text
ifFalseTrue =
  "GIVEN c IS A BOOLEAN\n\
  \DECIDE compliant IF\n\
  \  IF c THEN FALSE ELSE TRUE\n"

-- | Overlapping guards: row 2 must restate that row 1 did not fire, or the picture
-- says something the source does not.
branchOverlapping :: Text
branchOverlapping =
  "GIVEN a IS A BOOLEAN\n\
  \      b IS A BOOLEAN\n\
  \DECIDE compliant IF\n\
  \  BRANCH\n\
  \   IF a THEN TRUE\n\
  \   IF b THEN TRUE\n\
  \   OTHERWISE FALSE\n"

-- | A @FALSE@ body means that row can never conduct, so the disjunct is deleted
-- outright — @b@ survives only under a negation, in the @OTHERWISE@ prefix.
branchFalseBody :: Text
branchFalseBody =
  "GIVEN a IS A BOOLEAN\n\
  \      b IS A BOOLEAN\n\
  \DECIDE compliant IF\n\
  \  BRANCH\n\
  \   IF a THEN TRUE\n\
  \   IF b THEN FALSE\n\
  \   OTHERWISE TRUE\n"

-- | Distinct nullary constructors against one scrutinee cannot both hold, so the
-- negated prefixes drop out entirely and the chain flattens.
considerCtors :: Text
considerCtors =
  "DECLARE Colour\n\
  \  IS ONE OF\n\
  \    red\n\
  \    green\n\
  \    blue\n\
  \GIVEN c IS A Colour\n\
  \DECIDE compliant IF\n\
  \  CONSIDER c\n\
  \  WHEN red THEN TRUE\n\
  \  WHEN green THEN FALSE\n\
  \  WHEN blue THEN TRUE\n"

-- | A pattern that BINDS. The body may reference the bound name, so the branch is
-- not a closed boolean expression and must NOT be booleanised.
considerBinding :: Text
considerBinding =
  "DECLARE Colour\n\
  \  IS ONE OF\n\
  \    red\n\
  \    green\n\
  \GIVEN c IS A Colour\n\
  \DECIDE compliant IF\n\
  \  CONSIDER c\n\
  \  WHEN anything THEN TRUE\n"

-- | Tier-2 disjointness: @\<@ and @AT LEAST@ on the same operands are complementary,
-- so neither row needs a prefix. This is the shape of a real threshold rule.
complementGuards :: Text
complementGuards =
  "GIVEN income IS A NUMBER\n\
  \DECIDE compliant IF\n\
  \  BRANCH\n\
  \   IF income LESS THAN 107000 THEN TRUE\n\
  \   IF income AT LEAST 107000 THEN TRUE\n\
  \   OTHERWISE FALSE\n"

-- | The same shape WITHOUT the complement, as the control: unrelated guards must
-- keep their prefixes. If this one loses its 'V.Not' the tier-2 check is too eager.
unrelatedGuards :: Text
unrelatedGuards =
  "GIVEN income IS A NUMBER\n\
  \      worth IS A NUMBER\n\
  \DECIDE compliant IF\n\
  \  BRANCH\n\
  \   IF income LESS THAN 107000 THEN TRUE\n\
  \   IF worth AT LEAST 200000 THEN TRUE\n\
  \   OTHERWISE FALSE\n"

-- | A numeric chain. Two independent things stop it, and it is worth being precise
-- about which does the work HERE: the surrounding @EQUALS@ is itself unhandled, so it
-- becomes the leaf and the walk never descends to the @BRANCH@ at all. The boolean
-- gate is belt-and-braces behind that.
--
-- The gate cannot be falsified from L4 source, and that is a property of the design
-- rather than a gap in the test: every call site of @go@ is a boolean position (the
-- DECIDE body, which 'translateDecide' has already checked; the operands of
-- AND\/OR\/NOT; both sides of an @IMPLIES@; and @App@ arguments, only once they are
-- known boolean). A non-boolean chain therefore cannot reach the expansion by any
-- route. The gate exists so that this stays true if someone later adds a call site.
branchNumeric :: Text
branchNumeric =
  "GIVEN a IS A BOOLEAN\n\
  \      b IS A BOOLEAN\n\
  \DECIDE compliant IF\n\
  \  (BRANCH\n\
  \    IF a THEN 1\n\
  \    IF b THEN 2\n\
  \    OTHERWISE 3) EQUALS 2\n"

------------------------------------------------------------------------
-- spec
------------------------------------------------------------------------

spec :: Spec
spec = describe "guarded chains are ladder structure, not leaves (GUARDED-ROWS)" $ do
  -- The whole chain collapses to the guard itself. Note simplify=False: this is our
  -- expansion doing the work, not 'L4.Transform.simplify' getting there first.
  it "IF c THEN TRUE ELSE FALSE collapses to the single atom c" $ do
    let body = vizBody False ifTrueFalse
    atomsOf body `shouldBe` ["c"]
    countNots body `shouldBe` 0
    countOrs body `shouldBe` 0

  it "IF c THEN FALSE ELSE TRUE collapses to NOT c" $ do
    let body = vizBody False ifFalseTrue
    atomsOf body `shouldBe` ["c"]
    countNots body `shouldBe` 1

  -- The load-bearing case: first-match order becomes negated prefixes.
  it "overlapping BRANCH guards: row 2 carries NOT of row 1's guard" $ do
    let body = vizBody False branchOverlapping
    case body of
      V.Or _ ds -> do
        length ds `shouldBe` 2        -- the FALSE fallback is deleted
        -- a appears twice: once as its own row, once negated in row 2's prefix
        sort (atomsOf body) `shouldBe` ["a", "a", "b"]
        countNots body `shouldBe` 1
      other -> expectationFailure ("expected an Or, got: " <> show other)

  it "a FALSE body deletes its whole disjunct" $ do
    let body = vizBody False branchFalseBody
    case body of
      V.Or _ ds -> do
        length ds `shouldBe` 2        -- row a, and the OTHERWISE
        -- b survives ONLY under a negation; it never conducts on its own
        countNots body `shouldBe` 2   -- NOT a and NOT b, both in the fallback
        sort (atomsOf body) `shouldBe` ["a", "a", "b"]
      other -> expectationFailure ("expected an Or, got: " <> show other)

  -- Disjointness earned from the pattern match itself.
  it "CONSIDER over distinct constructors flattens: no negated prefixes" $ do
    let body = vizBody False considerCtors
    case body of
      V.Or _ ds -> do
        length ds `shouldBe` 2        -- red and blue; green is FALSE, deleted
        countNots body `shouldBe` 0
      other -> expectationFailure ("expected an Or, got: " <> show other)

  -- The bail-outs. Each must land on the pre-existing single-leaf behaviour.
  it "a BINDING pattern is left alone as one leaf" $
    countLeaves (vizBody False considerBinding) `shouldBe` 1

  it "a numeric BRANCH is left alone" $
    countLeaves (vizBody False branchNumeric) `shouldBe` 1

  -- Tier 2, and its control. These two must disagree, or the check is doing nothing.
  it "complementary threshold guards need no prefix" $ do
    let body = vizBody False complementGuards
    countNots body `shouldBe` 0
    countOrs body `shouldBe` 1

  it "but unrelated guards keep theirs" $ do
    let body = vizBody False unrelatedGuards
    countNots body `shouldBe` 1

  -- simplify is ON in the LSP's default path and runs BEFORE this expansion, on the
  -- raw L4 expression. Pin that it does not eat the chain on the way past.
  it "survives simplify=True" $
    atomsOf (vizBody True ifTrueFalse) `shouldBe` ["c"]

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

countNots :: V.IRExpr -> Int
countNots = countWhere $ \case
  V.Not{} -> True
  _ -> False

countOrs :: V.IRExpr -> Int
countOrs = countWhere $ \case
  V.Or{} -> True
  _ -> False

countLeaves :: V.IRExpr -> Int
countLeaves = countWhere $ \case
  V.UBoolVar{} -> True
  _ -> False

countWhere :: (V.IRExpr -> Bool) -> V.IRExpr -> Int
countWhere p e = here + concatMapSub
  where
    here = if p e then 1 else 0
    concatMapSub = sum (map (countWhere p) (children e))

children :: V.IRExpr -> [V.IRExpr]
children = \case
  V.And _ es -> es
  V.Or _ es -> es
  V.Not _ x -> [x]
  V.Implies _ x y _ -> [x, y]
  V.App _ _ es _ -> es
  _ -> []
