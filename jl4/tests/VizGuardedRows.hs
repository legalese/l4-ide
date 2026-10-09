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
import qualified Base.Text as Text
import qualified Data.List as List

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

-- | A binding row whose body is @FALSE@ contributes nothing to the disjunction, so it
-- can be dropped rather than forcing the whole chain back to a leaf. This is the shape
-- of the two widest single-leaf diagrams in the corpus (both @the purpose is
-- charitable@, 3494px and 3212px), whose only offending row is an @other …@ catch-all
-- that draws nothing.
considerInertBinder :: Text
considerInertBinder =
  "DECLARE Purpose\n\
  \  IS ONE OF\n\
  \    education\n\
  \    health\n\
  \    other HAS description IS A STRING\n\
  \GIVEN p IS A Purpose\n\
  \DECIDE compliant IF\n\
  \  CONSIDER p\n\
  \  WHEN education THEN TRUE\n\
  \  WHEN health THEN TRUE\n\
  \  WHEN other description THEN FALSE\n\
  \  OTHERWISE FALSE\n"

-- | The control. The same binding row with a body that DOES draw something cannot be
-- dropped — its guard is unexpressible, so the whole chain must stay a leaf.
considerLiveBinder :: Text
considerLiveBinder =
  "DECLARE Purpose\n\
  \  IS ONE OF\n\
  \    education\n\
  \    other HAS description IS A STRING\n\
  \GIVEN p IS A Purpose\n\
  \DECIDE compliant IF\n\
  \  CONSIDER p\n\
  \  WHEN education THEN TRUE\n\
  \  WHEN other description THEN TRUE\n\
  \  OTHERWISE FALSE\n"

-- | Two @EXACTLY@ patterns over two NUMBER parameters. @lo@ and @hi@ can hold the same
-- value, so these guards are NOT mutually exclusive and the negated prefix must survive.
exactlyVariables :: Text
exactlyVariables =
  "GIVEN x IS A NUMBER\n\
  \      lo IS A NUMBER\n\
  \      hi IS A NUMBER\n\
  \DECIDE compliant IF\n\
  \  CONSIDER x\n\
  \  WHEN EXACTLY lo THEN FALSE\n\
  \  WHEN EXACTLY hi THEN TRUE\n\
  \  OTHERWISE FALSE\n"

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

-- | A numeric rule of @k@ clauses, each TRUE or FALSE by turns, then a fall-through.
rowsGroup :: Int -> Text
rowsGroup k =
  "GIVEN n IS A NUMBER\nGIVETH A BOOLEAN\n"
    <> Text.unlines [ "DECIDE compliant " <> Text.pack (show i) <> " IS " <> (if even i then "TRUE" else "FALSE") | i <- [0 .. k - 1] ]
    <> "DECIDE compliant n IS FALSE\n"

-- | The same rows as a CONSIDER written by hand.
considerRows :: Int -> Text
considerRows k =
  "GIVEN n IS A NUMBER\nGIVETH A BOOLEAN\nDECIDE compliant n IS\n  CONSIDER n\n"
    <> Text.unlines [ "    WHEN " <> Text.pack (show i) <> " THEN " <> (if even i then "TRUE" else "FALSE") | i <- [0 .. k - 1] ]
    <> "    OTHERWISE FALSE\n"

colourDecl :: Text
colourDecl = "DECLARE Colour IS ONE OF Red, Green, Blue\n"

-- | A BOOLEAN rule as several DECIDE clauses (the desugarer's LET plus CONSIDER).
clauseGroup :: Text
clauseGroup =
  colourDecl <>
  "GIVEN c IS A Colour\n\
  \GIVETH A BOOLEAN\n\
  \DECIDE compliant Red IS TRUE\n\
  \DECIDE compliant Green IS FALSE\n\
  \DECIDE compliant Blue IS FALSE\n"

-- | The same rule, as the nested CONSIDER a drafter would write.
clauseGroupByHand :: Text
clauseGroupByHand =
  colourDecl <>
  "GIVEN c IS A Colour\n\
  \GIVETH A BOOLEAN\n\
  \DECIDE compliant c IS\n\
  \  CONSIDER c\n\
  \    WHEN Red THEN TRUE\n\
  \    WHEN Green THEN FALSE\n\
  \    WHEN Blue THEN FALSE\n"

-- | The rule with Blue TRUE, by hand and with the later clauses named in a LET.
clauseGroupByHandTrue :: Text
clauseGroupByHandTrue =
  colourDecl <>
  "GIVEN c IS A Colour\n\
  \GIVETH A BOOLEAN\n\
  \DECIDE compliant c IS\n\
  \  CONSIDER c\n\
  \    WHEN Red THEN TRUE\n\
  \    WHEN Green THEN FALSE\n\
  \    WHEN Blue THEN TRUE\n"


clauseGroupByLet :: Text
clauseGroupByLet =
  colourDecl <>
  "GIVEN c IS A Colour\n\
  \GIVETH A BOOLEAN\n\
  \DECIDE compliant c IS\n\
  \  LET rest BE CONSIDER c\n\
  \                WHEN Green THEN FALSE\n\
  \                WHEN Blue THEN TRUE\n\
  \  IN CONSIDER c\n\
  \       WHEN Red THEN TRUE\n\
  \       OTHERWISE rest\n"

clauseGroupTwoInputs :: Text
clauseGroupTwoInputs =
  "GIVEN n IS A NUMBER\n\
  \      b IS A BOOLEAN\n\
  \GIVETH A BOOLEAN\n\
  \DECIDE compliant 0 b IS FALSE\n\
  \DECIDE compliant n b IS b AND n GREATER THAN 5\n"

clauseGroupTwoInputsByHand :: Text
clauseGroupTwoInputsByHand =
  "GIVEN n IS A NUMBER\n\
  \      b IS A BOOLEAN\n\
  \GIVETH A BOOLEAN\n\
  \DECIDE compliant n b IS\n\
  \  CONSIDER n\n\
  \    WHEN 0 THEN FALSE\n\
  \    OTHERWISE b AND n GREATER THAN 5\n"

-- | The same as ONE clause: just the desugarer's CONSIDER.
clauseGroupOfOne :: Text
clauseGroupOfOne =
  "GIVEN m IS A MAYBE BOOLEAN\n\
  \GIVETH A BOOLEAN\n\
  \DECIDE compliant (JUST b) IS b\n"

clauseGroupOfOneByHand :: Text
clauseGroupOfOneByHand =
  "GIVEN m IS A MAYBE BOOLEAN\n\
  \GIVETH A BOOLEAN\n\
  \DECIDE compliant m IS\n\
  \  CONSIDER m\n\
  \    WHEN JUST b THEN b\n"

-- | No GIVETH: the result type is inferred, not declared.
clauseGroupNoGiveth :: Text
clauseGroupNoGiveth =
  colourDecl <>
  "GIVEN c IS A Colour\n\
  \DECIDE compliant Red IS TRUE\n\
  \DECIDE compliant Green IS FALSE\n\
  \DECIDE compliant Blue IS FALSE\n"

clauseGroupNoGivethByHand :: Text
clauseGroupNoGivethByHand =
  colourDecl <>
  "GIVEN c IS A Colour\n\
  \DECIDE compliant c IS\n\
  \  CONSIDER c\n\
  \    WHEN Red THEN TRUE\n\
  \    WHEN Green THEN FALSE\n\
  \    WHEN Blue THEN FALSE\n"

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

  -- A binding row that draws nothing is dropped; one that draws something is not.
  it "a binding row with a FALSE body is dropped, and the rest expands" $ do
    let body = vizBody False considerInertBinder
    case body of
      V.Or _ ds -> do
        length ds `shouldBe` 2        -- education and health
        countNots body `shouldBe` 0
      other -> expectationFailure ("expected an Or, got: " <> show other)

  it "but a binding row with a live body keeps the whole chain a leaf" $
    countLeaves (vizBody False considerLiveBinder) `shouldBe` 1

  -- Found by adversarial review. `Var` is a pattern synonym for `App ann n []`, so a
  -- naive "nullary application means nullary constructor" test also matches every
  -- GIVEN parameter. Two EXACTLY patterns over two NUMBER parameters are NOT mutually
  -- exclusive -- lo and hi can be equal -- so the negated prefix must survive. Without
  -- this, the diagram answers TRUE where the rule answers FALSE whenever lo == hi.
  it "EXACTLY over two variables is NOT disjoint: the prefix survives" $ do
    let body = vizBody False exactlyVariables
    countNots body `shouldSatisfy` (>= 1)

  -- Also found by adversarial review. leafFromExpr mints a FRESH Unique per call for a
  -- compound expression, and submitNewBinding binds exactly one Unique with no
  -- fan-out. If the positive occurrence of a guard and its negated twin were
  -- translated separately they would be two unrelated atoms, and the user could set
  -- one TRUE and the other FALSE -- a diagram asserting P and NOT P at once.
  it "a duplicated compound guard is ONE atom, not two" $ do
    let body = vizBody False unrelatedGuards
        ids = identitiesOf body
        threshold = [u | (u, l) <- ids, "107000" `Text.isInfixOf` l]
    -- it appears twice (row 1, and row 2's negated prefix) ...
    length threshold `shouldSatisfy` (>= 2)
    -- ... under exactly one identity
    length (nub threshold) `shouldBe` 1

  -- simplify is ON in the LSP's default path and runs BEFORE this expansion, on the
  -- raw L4 expression. Pin that it does not eat the chain on the way past.
  it "survives simplify=True" $
    atomsOf (vizBody True ifTrueFalse) `shouldBe` ["c"]

  -- A BOOLEAN rule written as DECIDE clauses is compiled to a CONSIDER (and a
  -- LET for the clauses not yet tried) that have no source range. The checker
  -- used to record a result type only on a node that has one, so the rule was
  -- refused as "not a boolean"; and the LET, once accepted, was drawn as one
  -- leaf naming a binding the drafter never wrote. The rule is the same rule
  -- as the nested CONSIDER it stands for, and is drawn as that.
  describe "a BOOLEAN rule written as DECIDE clauses" $ do
    it "is the same ladder as its hand-written CONSIDER: several clauses" $ do
      let clauses = vizBody False clauseGroup
      shapeOf clauses `shouldBe` shapeOf (vizBody False clauseGroupByHand)
      -- an opaque atom is a leaf too, so say what the shape is
      atomsOf clauses `shouldBe` ["c EQUALS Red"]

    -- A LET the drafter wrote is read through, so it is no longer one opaque
    -- leaf; its nesting is the drafter's own, so the shape is not compared.
    it "reads a LET through: the same questions as the CONSIDER it names" $ do
      let viaLet = vizBody False clauseGroupByLet
          byHand = vizBody False clauseGroupByHandTrue
      List.sort (List.nub (atomsOf viaLet)) `shouldBe` List.sort (List.nub (atomsOf byHand))
      countLeaves viaLet `shouldSatisfy` (> 1)

    it "is the same ladder as its hand-written CONSIDER: two inputs" $ do
      let clauses = vizBody False clauseGroupTwoInputs
      shapeOf clauses `shouldBe` shapeOf (vizBody False clauseGroupTwoInputsByHand)
      length (atomsOf clauses) `shouldSatisfy` (> 1)

    it "is the same ladder as its hand-written CONSIDER: one clause" $
      shapeOf (vizBody False clauseGroupOfOne) `shouldBe` shapeOf (vizBody False clauseGroupOfOneByHand)

    it "is the same ladder as its hand-written CONSIDER: no GIVETH" $
      shapeOf (vizBody False clauseGroupNoGiveth) `shouldBe` shapeOf (vizBody False clauseGroupNoGivethByHand)

    -- The ladder of a rule written as clauses can be far larger than the clauses,
    -- and its plan far larger still, so there is a limit ('Transform.clauseGroupLadderBudget').
    -- A group of rows that are each TRUE or FALSE draws one node per TRUE row,
    -- plus one: 598 rows draw 300 nodes, the most allowed, and 600 draw 301.
    it "draws a clause group of exactly the budget's size" $
      vizResult False (rowsGroup 598) `shouldSatisfy` either (const False) (const True)

    it "refuses a clause group one node over the budget, naming why" $
      case vizResult False (rowsGroup 600) of
        Left e -> Ladder.prettyPrintVizError e `shouldSatisfy` Text.isInfixOf "more than 300 decision points"
        Right _ -> expectationFailure "a clause group over the budget was drawn"

    it "does not hold a CONSIDER the drafter wrote to the clause-group budget" $
      vizResult False (considerRows 600) `shouldSatisfy` either (const False) (const True)

    it "names nothing the desugarer made up" $
      for_ [clauseGroup, clauseGroupByLet, clauseGroupTwoInputs, clauseGroupOfOne, clauseGroupNoGiveth] \src ->
        for_ (atomsOf (vizBody False src)) \label ->
          for_ ["the result of", "input 1", "__pm_", "LET"] \g ->
            (g, g `Text.isInfixOf` label) `shouldBe` (g, False)

------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------

-- | Typecheck a source, visualise its @compliant@ DECIDE, and hand back the wire body.
vizBody :: Bool -> Text -> V.IRExpr
vizBody simplify src =
  case vizResult simplify src of
    Right body -> body
    Left e -> error ("doVisualize failed: " <> show e)

-- | The same, with the visualizer's refusal kept.
vizResult :: Bool -> Text -> Either Ladder.VizError V.IRExpr
vizResult simplify src =
  case checkWithImports emptyVFS src of
    Left errs -> error ("source failed to typecheck: " <> show errs)
    Right tc ->
      let verDoc = VersionedTextDocumentIdentifier (fromNormalizedUri tc.tcdUri) 0
          cfg = Ladder.mkVizConfig verDoc tc.tcdModule tc.tcdSubstitution simplify
       in (\(info, _) -> info.funDecl.body) <$> Ladder.doVisualize (findDecide "compliant" tc.tcdModule) cfg

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
  V.UBoolVar _ nm _ _ _ _ _ -> [nm.label]
  V.And _ es -> concatMap atomsOf es
  V.Or _ es -> concatMap atomsOf es
  V.Not _ e -> atomsOf e
  V.Implies _ p q _ -> atomsOf p <> atomsOf q
  V.App _ _ es _ _ -> concatMap atomsOf es
  _ -> []

-- | The shape of a ladder body: its connectives and its atoms' labels, without
-- the numbers the visualizer gave its nodes.
shapeOf :: V.IRExpr -> String
shapeOf = \case
  V.UBoolVar _ nm _ _ _ _ _ -> "atom " <> Text.unpack nm.label
  V.And _ es -> "(and " <> unwords (map shapeOf es) <> ")"
  V.Or _ es -> "(or " <> unwords (map shapeOf es) <> ")"
  V.Not _ e -> "(not " <> shapeOf e <> ")"
  V.Implies _ p q _ -> "(implies " <> shapeOf p <> " " <> shapeOf q <> ")"
  V.App _ nm es _ _ -> "(app " <> Text.unpack nm.label <> " " <> unwords (map shapeOf es) <> ")"
  other -> show (length (children other)) <> "-other"

-- | Every atom occurrence, as (unique, label). Two occurrences of the SAME proposition
-- must share a unique, or a binding on one will not move the other.
identitiesOf :: V.IRExpr -> [(Int, Text)]
identitiesOf e = here <> concatMap identitiesOf (children e)
  where
    here = case e of
      V.UBoolVar _ nm _ _ _ _ _ -> [(nm.unique, nm.label)]
      V.App _ nm _ _ _ -> [(nm.unique, nm.label)]
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
  V.App _ _ es _ _ -> es
  _ -> []
