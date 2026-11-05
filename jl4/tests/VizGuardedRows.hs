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

import L4.API.VirtualFS (checkWithImports, emptyVFS, TypeCheckWithDepsResult (..))
import L4.Names (getName)
import L4.Syntax
import qualified L4.Transform as Transform
import qualified L4.Viz.VizExpr as V

import qualified LSP.L4.Viz.Ladder as Ladder

import Language.LSP.Protocol.Types (VersionedTextDocumentIdentifier (..))
import Test.Hspec

------------------------------------------------------------------------
-- sources
------------------------------------------------------------------------

-- | Guards written as negations. The ELSE route, a later row's prefix and the
-- OTHERWISE prefix all negate them again.
ifNotThenElse :: Text
ifNotThenElse =
  "GIVEN a IS A BOOLEAN\n\
  \      b IS A BOOLEAN\n\
  \      c IS A BOOLEAN\n\
  \DECIDE compliant IF\n\
  \  IF NOT a THEN b ELSE c\n"

ifNotFalseElse :: Text
ifNotFalseElse =
  "GIVEN a IS A BOOLEAN\n\
  \      b IS A BOOLEAN\n\
  \DECIDE compliant IF\n\
  \  IF NOT a THEN FALSE ELSE b\n"

branchNegatedGuard :: Text
branchNegatedGuard =
  "GIVEN a IS A BOOLEAN\n\
  \      b IS A BOOLEAN\n\
  \DECIDE compliant IF\n\
  \  BRANCH\n\
  \   IF NOT a THEN TRUE\n\
  \   IF b THEN TRUE\n\
  \   OTHERWISE FALSE\n"

branchNegatedOtherwise :: Text
branchNegatedOtherwise =
  "GIVEN a IS A BOOLEAN\n\
  \      b IS A BOOLEAN\n\
  \DECIDE compliant IF\n\
  \  BRANCH\n\
  \   IF NOT a THEN FALSE\n\
  \   IF NOT b THEN FALSE\n\
  \   OTHERWISE TRUE\n"

notNotAsWritten :: Text
notNotAsWritten =
  "GIVEN a IS A BOOLEAN\n\
  \DECIDE compliant IF\n\
  \  NOT (NOT a)\n"

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

-- | A rule of @k@ clauses that returns a number.
numberRows :: Int -> Text
numberRows k =
  "GIVEN n IS A NUMBER\nGIVETH A NUMBER\n"
    <> Text.unlines [ "DECIDE compliant " <> Text.pack (show i) <> " IS " <> Text.pack (show (i + 1)) | i <- [0 .. k - 1] ]
    <> "DECIDE compliant n IS 0\n"

-- | @k@ rows, each TRUE or FALSE by turns, chained through LETs the drafter wrote.
letRows :: Int -> Text
letRows k =
  "GIVEN n IS A NUMBER\nGIVETH A BOOLEAN\nDECIDE compliant n IS\n"
    <> Text.unlines [ Text.replicate (2 + depth) " " <> "LET r" <> Text.pack (show i) <> " BE IF n EQUALS " <> Text.pack (show i) <> " THEN " <> (if even i then "TRUE" else "FALSE") <> " ELSE " <> (if i == k - 1 then "FALSE" else "r" <> Text.pack (show (i + 1))) <> " IN"
                    | (depth, i) <- zip [0 ..] (reverse [0 .. k - 1]) ]
    <> Text.replicate (2 + k) " " <> "r0\n"

-- | @n@ LETs, each using the one before twice.
letChain :: Int -> Text
letChain n =
  "GIVEN x IS A BOOLEAN\n      y IS A BOOLEAN\nGIVETH A BOOLEAN\nDECIDE compliant IS\n"
    <> "  LET a0 BE x\n  IN\n"
    <> Text.concat
         [ Text.replicate (3 + level) " " <> "LET a" <> Text.pack (show level) <> " BE a" <> Text.pack (show (level - 1)) <> " AND y OR a" <> Text.pack (show (level - 1)) <> "\n"
             <> Text.replicate (3 + level) " " <> "IN\n"
         | level <- [1 .. n - 1] ]
    <> Text.replicate (3 + n) " " <> "a" <> Text.pack (show (n - 1)) <> "\n"

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

-- | A rule the drafter wrote with a LET (the later cases named), not clauses.
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

-- | A clause group whose first clause's result is a LET the drafter wrote.
clauseGroupLetResult :: Text
clauseGroupLetResult =
  colourDecl <>
  "GIVEN c IS A Colour\n\
  \      b IS A BOOLEAN\n\
  \GIVETH A BOOLEAN\n\
  \DECIDE compliant Red b IS LET both BE b AND b IN both\n\
  \DECIDE compliant c b IS FALSE\n"

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

-- | A table of two columns whose rows share the first column and differ in the
-- second. The desugarer tests the colour again in every later clause.
clauseTable :: Text
clauseTable =
  colourDecl <>
  "GIVEN c IS A Colour\n\
  \      b IS A BOOLEAN\n\
  \GIVETH A BOOLEAN\n\
  \DECIDE compliant Red TRUE IS TRUE\n\
  \DECIDE compliant Red FALSE IS FALSE\n\
  \DECIDE compliant Green b IS b\n\
  \DECIDE compliant Blue b IS NOT b\n"

clauseTableByHand :: Text
clauseTableByHand =
  colourDecl <>
  "GIVEN c IS A Colour\n\
  \      b IS A BOOLEAN\n\
  \GIVETH A BOOLEAN\n\
  \DECIDE compliant c b IS\n\
  \  CONSIDER c\n\
  \    WHEN Red THEN\n\
  \      CONSIDER b\n\
  \        WHEN TRUE THEN TRUE\n\
  \        WHEN FALSE THEN FALSE\n\
  \    WHEN Green THEN b\n\
  \    WHEN Blue THEN NOT b\n"

-- | A table of @k@ rows over an enum of @k@ values and a BOOLEAN: each value
-- with TRUE is TRUE, and anything else FALSE.
enumTable :: Int -> Text
enumTable k =
  "DECLARE Big IS ONE OF " <> Text.intercalate ", " [ "V" <> Text.pack (show i) | i <- [0 .. k - 1] ] <> "\n"
    <> "GIVEN c IS A Big\n      b IS A BOOLEAN\nGIVETH A BOOLEAN\n"
    <> Text.unlines [ "DECIDE compliant V" <> Text.pack (show i) <> " TRUE IS TRUE" | i <- [0 .. k - 1] ]
    <> "DECIDE compliant c b IS FALSE\n"

enumTableByHand :: Int -> Text
enumTableByHand k =
  "DECLARE Big IS ONE OF " <> Text.intercalate ", " [ "V" <> Text.pack (show i) | i <- [0 .. k - 1] ] <> "\n"
    <> "GIVEN c IS A Big\n      b IS A BOOLEAN\nGIVETH A BOOLEAN\nDECIDE compliant c b IS\n  CONSIDER c\n"
    <> Text.unlines [ "    WHEN V" <> Text.pack (show i) <> " THEN\n      CONSIDER b\n        WHEN TRUE THEN TRUE\n        OTHERWISE FALSE" | i <- [0 .. k - 1] ]
    <> "    OTHERWISE FALSE\n"

-- | 'enumTable' with each enum value written @EXACTLY Vi@, two rows per value.
exactlyTable :: Int -> Text
exactlyTable k =
  "DECLARE Big IS ONE OF " <> Text.intercalate ", " [ "V" <> Text.pack (show i) | i <- [0 .. k - 1] ] <> "\n"
    <> "GIVEN c IS A Big\n      b IS A BOOLEAN\nGIVETH A BOOLEAN\n"
    <> Text.unlines (concat [ [ "DECIDE compliant (EXACTLY V" <> Text.pack (show i) <> ") TRUE IS " <> (if even i then "TRUE" else "FALSE")
                              , "DECIDE compliant (EXACTLY V" <> Text.pack (show i) <> ") FALSE IS " <> (if even i then "FALSE" else "TRUE") ]
                            | i <- [0 .. k - 1] ])
    <> "DECIDE compliant c b IS FALSE\n"

exactlyTableByHand :: Int -> Text
exactlyTableByHand k =
  "DECLARE Big IS ONE OF " <> Text.intercalate ", " [ "V" <> Text.pack (show i) | i <- [0 .. k - 1] ] <> "\n"
    <> "GIVEN c IS A Big\n      b IS A BOOLEAN\nGIVETH A BOOLEAN\nDECIDE compliant c b IS\n  CONSIDER c\n"
    <> Text.unlines [ "    WHEN EXACTLY V" <> Text.pack (show i) <> " THEN\n      CONSIDER b\n        WHEN TRUE THEN " <> (if even i then "TRUE" else "FALSE") <> "\n        WHEN FALSE THEN " <> (if even i then "FALSE" else "TRUE") <> "\n        OTHERWISE FALSE"
                    | i <- [0 .. k - 1] ]
    <> "    OTHERWISE FALSE\n"

-- | A last clause whose pattern is a new name, not the input's own.
clauseNewName :: Text
clauseNewName =
  colourDecl <>
  "GIVEN c IS A Colour\n\
  \      a IS A BOOLEAN\n\
  \      b IS A BOOLEAN\n\
  \GIVETH A BOOLEAN\n\
  \DECIDE compliant Red a b IS a\n\
  \DECIDE compliant Green a b IS b\n\
  \DECIDE compliant other a b IS a AND b\n"

clauseNewNameByHand :: Text
clauseNewNameByHand =
  colourDecl <>
  "GIVEN c IS A Colour\n\
  \      a IS A BOOLEAN\n\
  \      b IS A BOOLEAN\n\
  \GIVETH A BOOLEAN\n\
  \DECIDE compliant c a b IS\n\
  \  CONSIDER c\n\
  \    WHEN Red THEN a\n\
  \    WHEN Green THEN b\n\
  \    OTHERWISE a AND b\n"

-- | @k@ rows each with a long numeric body, so that written out the rule passes
-- 'Transform.letInliningNodeBudget' though its ladder would be small.
longRows :: Int -> Int -> Text
longRows k width =
  "GIVEN n IS A NUMBER\nGIVETH A BOOLEAN\n"
    <> Text.unlines [ "DECIDE compliant " <> Text.pack (show i) <> " IS n" <> Text.concat (replicate width " + 1") <> " GREATER THAN 0" | i <- [0 .. k - 1] ]
    <> "DECIDE compliant n IS FALSE\n"

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

  -- A guard written NOT x fails where x holds. The negation the expansion adds
  -- cancels the guard's own, so no route reads NOT (NOT x) (L4.Viz.VizExpr.negateIR).
  describe "a negated guard is not negated twice" $ do
    it "IF NOT a THEN b ELSE c: the ELSE route reads a" $ do
      shapeOf (vizBody False ifNotThenElse)
        `shouldBe` "(or (and (not atom a) atom b) (and atom a atom c))"
      hasDoubleNot (vizBody True ifNotThenElse) `shouldBe` False

    it "IF NOT a THEN FALSE ELSE b draws a and b, with no NOT" $
      shapeOf (vizBody False ifNotFalseElse) `shouldBe` "(and atom a atom b)"

    it "a later BRANCH row's prefix reads a where row 1's guard is NOT a" $ do
      let body = vizBody False branchNegatedGuard
      hasDoubleNot body `shouldBe` False
      countNots body `shouldBe` 1   -- row 1's guard, as written; row 2's prefix is a

    it "the OTHERWISE prefix cancels too" $
      hasDoubleNot (vizBody False branchNegatedOtherwise) `shouldBe` False

    -- The guard and its cancelled twin are one proposition, so they must keep one
    -- identity, or a binding on one would not move the other.
    it "the cancelled guard keeps the guard's identity" $ do
      let ids = [u | (u, "a") <- identitiesOf (vizBody False ifNotThenElse)]
      length ids `shouldBe` 2
      length (nub ids) `shouldBe` 1

    it "a NOT NOT the author wrote is drawn as written" $
      countNots (vizBody False notNotAsWritten) `shouldBe` 2

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

    -- Only the LETs the desugarer generated are read through. A LET the
    -- drafter wrote is drawn as it was before clauses were read through: one
    -- leaf, whatever it holds.
    it "leaves a LET the drafter wrote as written: one atom" $
      countLeaves (vizBody False clauseGroupByLet) `shouldBe` 1

    -- A clause whose result is a LET: the group around it is still read through,
    -- and the LET inside the clause is the drafter's, so it stays one leaf.
    it "reads a clause group through whose clause result is a LET the drafter wrote" $
      case vizResult False clauseGroupLetResult of
        Right body -> do
          atomsOf body `shouldSatisfy` ("c EQUALS Red" `elem`)
          countLeaves body `shouldSatisfy` (> 1)
        Left e -> expectationFailure (show e)

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
        Left e -> Ladder.prettyPrintVizError e `shouldSatisfy` Text.isInfixOf "more than 300 boxes"
        Right _ -> expectationFailure "a clause group over the budget was drawn"

    it "says a large clause group returning a number is not boolean, not that it is too large" $
      vizResult False (numberRows 600) `shouldBe` Left Ladder.InvalidDecideMustHaveBoolRetType

    -- Rows chained through LETs the drafter wrote are not read through, of
    -- any length: the LET is the one atom it was.
    it "draws a chain of LETs the drafter wrote as written, one atom, of any size" $
      for_ [20, 600] \k ->
        case vizResult False (letRows k) of
          Right body -> countLeaves body `shouldBe` 1
          Left e -> expectationFailure (show e)

    -- A chain of LETs that each use the one before twice doubles for each LET
    -- when written out, and the ladder is its conjunctive normal form, which
    -- grows faster still (six LETs did not finish). It is never read through.
    it "draws a chain of doubling LETs the drafter wrote as written, one atom" $
      for_ [3, 5, 7, 13] \n ->
        countLeaves (vizBody True (letChain n)) `shouldBe` 1

    it "does not hold a CONSIDER the drafter wrote to the clause-group budget" $
      vizResult False (considerRows 600) `shouldSatisfy` either (const False) (const True)

    -- The desugarer tests an earlier column again in every later clause. Each
    -- generated test is read with what the branches around it already decided,
    -- so the table is the CONSIDER a drafter writes for it, not a copy of every
    -- later clause under every earlier case (29 leaves against 6, before).
    it "is the same ladder as its hand-written CONSIDER: a table of two columns" $ do
      let clauses = vizBody False clauseTable
      shapeOf clauses `shouldBe` shapeOf (vizBody False clauseTableByHand)
      countLeaves clauses `shouldBe` 6

    it "draws a table of an enum by a BOOLEAN in a size linear in its rows" $
      for_ [2, 6, 24] \k -> do
        let clauses = vizBody False (enumTable k)
        shapeOf clauses `shouldBe` shapeOf (vizBody False (enumTableByHand k))
        countLeaves clauses `shouldBe` 2 * k

    -- EXACTLY an enum value names one value, as the value itself does. It was
    -- not known as one, so nothing in a table written with it was pruned, and
    -- eight values by a BOOLEAN were refused as too long to draw.
    it "reads EXACTLY an enum value as that value, and draws the table as its hand-written CONSIDER" $
      case vizResult False (exactlyTable 8) of
        Left e -> expectationFailure ("an EXACTLY table was refused: " <> show e)
        Right clauses -> shapeOf clauses `shouldBe` shapeOf (vizBody False (exactlyTableByHand 8))

    it "reads a clause whose pattern is a new name as the OTHERWISE" $
      shapeOf (vizBody False clauseNewName) `shouldBe` shapeOf (vizBody False clauseNewNameByHand)

    -- Written out, these clauses pass the bound on the work of reading them
    -- through, though their ladder would be small; the refusal says which.
    it "refuses clauses too long to write out, saying that and not that the ladder is too large" $
      case vizResult False (longRows 60 200) of
        Left e -> do
          e `shouldBe` Ladder.ClauseGroupTooLong Transform.letInliningNodeBudget
          Ladder.prettyPrintVizError e `shouldSatisfy` Text.isInfixOf "too long to draw"
        Right _ -> expectationFailure "clauses past the bound on reading them through were drawn"

    it "names nothing the desugarer made up" $
      for_ [clauseGroup, clauseGroupTwoInputs, clauseGroupOfOne, clauseGroupNoGiveth] \src ->
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

-- | Is there a NOT directly over a NOT anywhere in the body?
hasDoubleNot :: V.IRExpr -> Bool
hasDoubleNot = \case
  V.Not _ (V.Not _ _) -> True
  e -> any hasDoubleNot (children e)

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
