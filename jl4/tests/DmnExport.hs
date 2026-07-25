-- | The DMN 1.3 exporter (Track D1 of the Lexipedia-superset programme).
--
-- "L4.Viz.GuardedRows" normalises @IF@ \/ @BRANCH@ \/ @CONSIDER@ into first-match
-- rows; "L4.Dmn.Lower" is its second consumer, turning those rows into a decision
-- table, and "L4.Dmn.Emit" writes DMN 1.3 XML.
--
-- These tests pin the three things that are easy to get subtly wrong and hard to
-- notice:
--
--   1. __where @OTHERWISE@ goes.__ Under @U@ it must be the
--      @\<defaultOutputEntry\>@, because a catch-all rule overlaps every other
--      rule and would make the table illegal; under @F@ it must be a final
--      all-@-@ rule.
--   2. __that negated prefixes are not materialised.__ Hit policy @First@ /is/
--      the "and no earlier guard fired" quantifier, so restating it in the cells
--      would be redundant — and the resulting triangular table would be a
--      different, worse artifact.
--   3. __that we never say more than the L4 does.__ A guard that will not reduce
--      to a constant endpoint becomes a boolean column plus a located fidelity
--      note, and a hit policy of @U@ is claimed only when the emitted /cells/
--      can witness it — not merely when the L4 guards were exclusive.
module DmnExport (spec) where

import Base
import qualified Base.Text as Text

import L4.API.VirtualFS (TypeCheckWithDepsResult (..), checkWithImports, emptyVFS)
import L4.Dmn.Emit (emitDrg, escapeXmlAttr, escapeXmlText)
import L4.Dmn.IR
import L4.Dmn.Lower (DmnLowerOptions (..), lowerModule)

import System.FilePath ((</>))
import Test.Hspec
import Test.Hspec.Golden

------------------------------------------------------------------------
-- sources
------------------------------------------------------------------------

-- | The degenerate table: one condition, two answers, a NUMBER on the output
-- side. The ladder consumer refuses this one (it gates on boolean type); the DMN
-- consumer must not, because a numeric table is what DMN is for.
ifThenElseNumber :: Text
ifThenElseNumber =
  "GIVEN c IS A BOOLEAN\n\
  \GIVETH A NUMBER\n\
  \amount MEANS\n\
  \  IF c THEN 100 ELSE 200\n"

-- | Overlapping numeric thresholds, in descending order — the shape every fee
-- schedule and every tapering benefit has.
overlappingThresholds :: Text
overlappingThresholds =
  "GIVEN income IS A NUMBER\n\
  \GIVETH A NUMBER\n\
  \rate MEANS\n\
  \  BRANCH\n\
  \   IF income AT LEAST 200000 THEN 10\n\
  \   IF income AT LEAST 100000 THEN 5\n\
  \   OTHERWISE 0\n"

-- | Distinct nullary constructors against one scrutinee cannot both hold, so the
-- table can honestly claim @U@ — and then @OTHERWISE@ has nowhere to live except
-- the output clause's default.
considerConstructors :: Text
considerConstructors =
  "DECLARE Colour\n\
  \  IS ONE OF\n\
  \    red\n\
  \    green\n\
  \    blue\n\
  \GIVEN c IS A Colour\n\
  \GIVETH A NUMBER\n\
  \score MEANS\n\
  \  CONSIDER c\n\
  \  WHEN red THEN 1\n\
  \  WHEN green THEN 2\n\
  \  OTHERWISE 0\n"

-- | A disjunction of equalities over ONE subject. DMN's own idiom for that is a
-- comma-separated cell, and the correspondence is exact.
orOverOneColumn :: Text
orOverOneColumn =
  "DECLARE Colour\n\
  \  IS ONE OF\n\
  \    red\n\
  \    green\n\
  \    blue\n\
  \GIVEN c IS A Colour\n\
  \GIVETH A NUMBER\n\
  \warmth MEANS\n\
  \  BRANCH\n\
  \   IF (c EQUALS red) OR (c EQUALS green) THEN 1\n\
  \   OTHERWISE 0\n"

-- | The same, over TWO subjects. There is no single column to put the
-- disjunction on, so it falls back to one boolean column.
orOverTwoColumns :: Text
orOverTwoColumns =
  "GIVEN a IS A NUMBER\n\
  \      b IS A NUMBER\n\
  \GIVETH A NUMBER\n\
  \pick MEANS\n\
  \  BRANCH\n\
  \   IF (a EQUALS 1) OR (b EQUALS 2) THEN 1\n\
  \   OTHERWISE 0\n"

-- | A negated comparison. S-FEEL puts @not(...)@ around a whole cell, so the
-- column stays the comparison's own subject.
negatedComparison :: Text
negatedComparison =
  "GIVEN income IS A NUMBER\n\
  \GIVETH A NUMBER\n\
  \band MEANS\n\
  \  BRANCH\n\
  \   IF NOT (income AT LEAST 100) THEN 1\n\
  \   OTHERWISE 0\n"

-- | A proposition and its negation. Both must land on ONE column, as @true@ and
-- @false@ cells — not on two columns, one of them spelled @not(p)@.
negatedAtom :: Text
negatedAtom =
  "GIVEN p IS A BOOLEAN\n\
  \GIVETH A NUMBER\n\
  \pick MEANS\n\
  \  BRANCH\n\
  \   IF p THEN 1\n\
  \   IF NOT p THEN 2\n\
  \   OTHERWISE 0\n"

-- | Constructors on BOTH sides of the table. FEEL has no sum types, so a
-- constructor is serialised as a string — and it must be quoted on the output
-- side too, or the cell reads as a reference to a variable of that name.
constructorOutput :: Text
constructorOutput =
  "DECLARE Colour\n\
  \  IS ONE OF\n\
  \    red\n\
  \    green\n\
  \    blue\n\
  \GIVEN c IS A Colour\n\
  \GIVETH A Colour\n\
  \complement MEANS\n\
  \  CONSIDER c\n\
  \  WHEN red THEN green\n\
  \  WHEN green THEN red\n\
  \  OTHERWISE blue\n"

-- | A guard that is a function application. It has no constant endpoint, so it
-- becomes its own boolean column — and says so.
undecomposableGuard :: Text
undecomposableGuard =
  "GIVEN n IS A NUMBER\n\
  \GIVETH A BOOLEAN\n\
  \DECIDE `is even` n IF\n\
  \  n MODULO 2 EQUALS 0\n\
  \\n\
  \GIVEN n IS A NUMBER\n\
  \GIVETH A NUMBER\n\
  \bonus MEANS\n\
  \  BRANCH\n\
  \   IF `is even` n THEN 1\n\
  \   OTHERWISE 0\n"

-- | Not a guarded chain at all. DMN's answer for logic that has no table shape is
-- a boxed literal expression; dropping the decision would leave the DRG
-- describing a different rule set than the module does.
notATable :: Text
notATable =
  "ASSUME a IS A BOOLEAN\n\
  \ASSUME b IS A BOOLEAN\n\
  \GIVETH A BOOLEAN\n\
  \DECIDE ok IF\n\
  \  a AND b\n"

-- | The normaliser may DROP a CONSIDER arm whose pattern binds but whose body is
-- inert (literally FALSE). For the ladder that is exact -- a missing disjunct
-- contributes FALSE. For DMN it is not: an unmatched input yields /null/, not
-- @false@. With no OTHERWISE left to become a default output, the table would
-- answer differently from the rule, so no table may be emitted.
elidedArmNoOtherwise :: Text
elidedArmNoOtherwise =
  "DECLARE Purpose\n\
  \  IS ONE OF\n\
  \    education\n\
  \    other HAS description IS A STRING\n\
  \GIVEN p IS A Purpose\n\
  \GIVETH A BOOLEAN\n\
  \DECIDE charitable p IF\n\
  \  CONSIDER p\n\
  \  WHEN education THEN TRUE\n\
  \  WHEN other description THEN FALSE\n"

-- | The same shape WITH an OTHERWISE. Now the elided arm's inputs fall to the
-- default output, which says exactly what the rule says, so the table is fine.
elidedArmWithOtherwise :: Text
elidedArmWithOtherwise =
  "DECLARE Purpose\n\
  \  IS ONE OF\n\
  \    education\n\
  \    other HAS description IS A STRING\n\
  \GIVEN p IS A Purpose\n\
  \GIVETH A BOOLEAN\n\
  \DECIDE charitable p IF\n\
  \  CONSIDER p\n\
  \  WHEN education THEN TRUE\n\
  \  WHEN other description THEN FALSE\n\
  \  OTHERWISE FALSE\n"

-- | One decision reading another. The reference must become an
-- @informationRequirement@ pointing at the /required/ decision.
decisionChain :: Text
decisionChain =
  "GIVETH A BOOLEAN\n\
  \DECIDE `is holiday` IF\n\
  \  TRUE\n\
  \\n\
  \GIVETH A NUMBER\n\
  \fee MEANS\n\
  \  IF `is holiday` THEN 0 ELSE 10\n"

-- | A decomposable guard whose SUBJECT is a function invocation. The cell is a
-- perfectly ordinary constant endpoint, but the column's input expression is
-- outside S-FEEL, which is where every published DMN analysis result lives.
nonSFeelColumn :: Text
nonSFeelColumn =
  "GIVEN n IS A NUMBER\n\
  \GIVETH A NUMBER\n\
  \double n MEANS n TIMES 2\n\
  \\n\
  \GIVEN n IS A NUMBER\n\
  \GIVETH A NUMBER\n\
  \tier MEANS\n\
  \  BRANCH\n\
  \   IF double n AT LEAST 10 THEN 1\n\
  \   OTHERWISE 0\n"

-- | Tier-2 disjointness with a NON-constant endpoint. L4 knows these two guards
-- are complementary, so @grDisjoint@ is True — but neither guard has a constant
-- endpoint, so both become boolean columns and the two rules then overlap
-- wherever both cells are @true@. Claiming @U@ on that table would be a false
-- statement about the artifact.
disjointButUnwitnessable :: Text
disjointButUnwitnessable =
  "ASSUME limit IS A NUMBER\n\
  \GIVEN income IS A NUMBER\n\
  \GIVETH A NUMBER\n\
  \tier MEANS\n\
  \  BRANCH\n\
  \   IF income LESS THAN limit THEN 1\n\
  \   IF income AT LEAST limit THEN 2\n\
  \   OTHERWISE 0\n"

-- | A range guard: two bounds on one column become one interval cell, which is
-- the idiom DMN's own interval analysis is built around.
rangeGuard :: Text
rangeGuard =
  "GIVEN age IS A NUMBER\n\
  \GIVETH A NUMBER\n\
  \band MEANS\n\
  \  BRANCH\n\
  \   IF age AT LEAST 18 AND age LESS THAN 65 THEN 1\n\
  \   OTHERWISE 0\n"

------------------------------------------------------------------------
-- spec
------------------------------------------------------------------------

spec :: FilePath -> Spec
spec examplesRoot = describe "DMN 1.3 export (Track D1)" $ do
  describe "hit policy and where OTHERWISE goes" $ do
    it "IF/THEN/ELSE over NUMBER is one rule under U, with the ELSE as the default output" $ do
      let t = tableOf "amount" ifThenElseNumber
      t.dtHitPolicy `shouldBe` HitUnique
      length t.dtRules `shouldBe` 1
      fmap (.feText) t.dtOutput.ocDefault `shouldBe` Just "200"
      t.dtOutput.ocType `shouldBe` DmnNumber
      -- the condition is one boolean column, tested for `true`
      map (.icExpr.feText) t.dtInputs `shouldBe` ["c"]
      map (.drInputs) t.dtRules `shouldBe` [[TestEq (VBool True)]]

    it "a CONSIDER over distinct constructors is U with a defaultOutputEntry, not a catch-all rule" $ do
      let t = tableOf "score" considerConstructors
      t.dtHitPolicy `shouldBe` HitUnique
      length t.dtRules `shouldBe` 2                     -- red and green; OTHERWISE is not a rule
      fmap (.feText) t.dtOutput.ocDefault `shouldBe` Just "0"
      map (.icExpr.feText) t.dtInputs `shouldBe` ["c"]
      map (.drInputs) t.dtRules
        `shouldBe` [[TestEq (VStr "red")], [TestEq (VStr "green")]]
      -- an enum has no FEEL type, but every cell in the column is a string
      map (.icType) t.dtInputs `shouldBe` [DmnString]

  describe "columns, cells, and what is NOT in them" $ do
    it "overlapping thresholds decompose to one column of unary tests under F" $ do
      let t = tableOf "rate" overlappingThresholds
      t.dtHitPolicy `shouldBe` HitFirst
      map (.icExpr.feText) t.dtInputs `shouldBe` ["income"]
      map (.icType) t.dtInputs `shouldBe` [DmnNumber]
      -- three rules: two guarded, then OTHERWISE as an all-`-` catch-all, which
      -- is exactly what First means.
      map (.drInputs) t.dtRules
        `shouldBe` [ [TestCmp OpGeq (VNum 200000)]
                   , [TestCmp OpGeq (VNum 100000)]
                   , [TestAny]
                   ]
      map (.drOutput.feText) t.dtRules `shouldBe` ["10", "5", "0"]

    it "and does NOT materialise the negated prefixes that the ladder has to" $ do
      let t = tableOf "rate" overlappingThresholds
      -- Row 2 fires iff its own guard holds AND row 1's did not. The ladder must
      -- write that `NOT (income >= 200000)` out; hit policy First already says
      -- it, so no cell may mention 200000 except row 1's own.
      concatMap cellTexts (drop 1 t.dtRules) `shouldSatisfy` all (not . Text.isInfixOf "200000")
      -- and no `not(...)` was invented anywhere
      concatMap cellTexts t.dtRules `shouldSatisfy` all (not . Text.isInfixOf "not(")

    it "a disjunction over one subject becomes one comma-separated cell" $ do
      let t = tableOf "warmth" orOverOneColumn
      map (.icExpr.feText) t.dtInputs `shouldBe` ["c"]
      map cellTexts t.dtRules `shouldBe` [["\"red\", \"green\""]]
      map (.drInputs) t.dtRules
        `shouldBe` [[TestOneOf [TestEq (VStr "red"), TestEq (VStr "green")]]]

    it "but a disjunction over TWO subjects falls back to one boolean column" $ do
      let t = tableOf "pick" orOverTwoColumns
      map (.icExpr.feText) t.dtInputs `shouldBe` ["a = 1 or b = 2"]
      map (.drInputs) t.dtRules `shouldBe` [[TestEq (VBool True)]]
      map (.fnReason) t.dtNotes `shouldContain` [GuardNotDecomposable]

    it "a constructor is quoted on the OUTPUT side as well as the input side" $ do
      let t = tableOf "complement" constructorOutput
      map (.drOutput.feText) t.dtRules `shouldBe` ["\"green\"", "\"red\""]
      fmap (.feText) t.dtOutput.ocDefault `shouldBe` Just "\"blue\""
      t.dtOutput.ocType `shouldBe` DmnString
      -- and a quoted constant is not a "computed output"
      map (.fnReason) t.dtNotes `shouldNotContain` [ComputedOutput]

    it "a negated comparison keeps its subject's column and wraps the cell" $ do
      let t = tableOf "band" negatedComparison
      map (.icExpr.feText) t.dtInputs `shouldBe` ["income"]
      map cellTexts t.dtRules `shouldBe` [["not(>= 100)"]]

    it "a proposition and its negation share one column, as true and false" $ do
      let t = tableOf "pick" negatedAtom
      map (.icExpr.feText) t.dtInputs `shouldBe` ["p"]
      map (.drInputs) t.dtRules `shouldBe` [[TestEq (VBool True)], [TestEq (VBool False)]]
      t.dtHitPolicy `shouldBe` HitUnique
      fmap (.feText) t.dtOutput.ocDefault `shouldBe` Just "0"

    it "two bounds on one column become one interval cell" $ do
      let t = tableOf "band" rangeGuard
      map (.icExpr.feText) t.dtInputs `shouldBe` ["age"]
      -- one row, so the chain is vacuously disjoint: U, and OTHERWISE is the
      -- default output rather than a catch-all rule.
      t.dtHitPolicy `shouldBe` HitUnique
      map cellTexts t.dtRules `shouldBe` [["[18..65)"]]
      fmap (.feText) t.dtOutput.ocDefault `shouldBe` Just "0"

  describe "fidelity: never say more than the L4 does" $ do
    it "an undecomposable guard becomes a boolean column AND is named in the report" $ do
      let t = tableOf "bonus" undecomposableGuard
      map (.icExpr.feText) t.dtInputs `shouldBe` ["is even(n)"]
      map (.drInputs) t.dtRules `shouldBe` [[TestEq (VBool True)]]
      let notes = [n | n <- t.dtNotes, n.fnReason == GuardNotDecomposable]
      map (.fnFragment) notes `shouldBe` ["`is even` OF n"]
      -- the note is located, and it names what was given up
      map (.fnRange) notes `shouldSatisfy` all isJust
      concatMap (capabilitiesLost . (.fnReason)) notes `shouldContain` [OverlapDetection]

    it "a column whose input expression leaves S-FEEL is named and located" $ do
      let t = tableOf "tier" nonSFeelColumn
      -- the cell is a fine constant endpoint; it is the COLUMN that left the
      -- analysable fragment, because S-FEEL has no function invocation.
      map (.icExpr.feText) t.dtInputs `shouldBe` ["double(n)"]
      map (.icExpr.feFragment) t.dtInputs `shouldBe` [FullFeel]
      map (.drInputs) t.dtRules `shouldBe` [[TestCmp OpGeq (VNum 10)]]
      let notes = [n | n <- t.dtNotes, n.fnReason == InputExpressionNotSFeel]
      map (.fnFragment) notes `shouldBe` ["double OF n"]
      map (.fnRange) notes `shouldSatisfy` all isJust

    it "a decision that does not normalise becomes a literalExpression, with a note" $ do
      let drg = drgOf notATable
          d   = decisionNamed "ok" drg
      case d.dcnLogic of
        LogicLiteral e -> e.feText `shouldBe` "a and b"
        LogicTable _   -> expectationFailure "expected a literal expression, got a decision table"
      [n.fnReason | n <- drg.drgNotes, n.fnDecision == "ok"]
        `shouldBe` [NotADecisionTable NotAGuardedChain]
      emitDrg drg `shouldSatisfy` Text.isInfixOf "<literalExpression"

    it "an elided CONSIDER arm with no OTHERWISE refuses to become a table" $ do
      -- DMN answers null where the rule answers FALSE, so there must be no table
      let drg = drgOf elidedArmNoOtherwise
      case (decisionNamed "charitable" drg).dcnLogic of
        LogicLiteral _ -> pure ()
        LogicTable _   -> expectationFailure "emitted a table that answers null where the rule answers FALSE"
      [n.fnReason | n <- drg.drgNotes] `shouldBe` [NotADecisionTable RowsElided]

    it "...but with an OTHERWISE the default output plugs the hole" $ do
      let t = tableOf "charitable" elidedArmWithOtherwise
      map (.drInputs) t.dtRules `shouldBe` [[TestEq (VStr "education")]]
      fmap (.feText) t.dtOutput.ocDefault `shouldBe` Just "false"

    it "U is claimed only when the CELLS witness it, not merely because the guards are exclusive" $ do
      let t = tableOf "tier" disjointButUnwitnessable
      -- L4 knows `< limit` and `>= limit` are complementary...
      t.dtHitPolicy `shouldBe` HitFirst
      -- ...and the report says why the table cannot show it
      map (.fnReason) t.dtNotes `shouldContain` [HitPolicyDowngraded]

    it "an order-dependent table says so, in DMN's own terms" $ do
      let t = tableOf "rate" overlappingThresholds
      map (.fnReason) t.dtNotes `shouldContain` [OrderDependentTable]
      capabilitiesLost OrderDependentTable `shouldBe` [ManualValidation]

    it "a clean numeric table has no fidelity losses at all" $
      (tableOf "amount" ifThenElseNumber).dtNotes `shouldBe` []

  describe "the DRG" $ do
    it "a reference to another DECIDE is one informationRequirement, pointing at it" $ do
      let drg = drgOf decisionChain
          fee = decisionNamed "fee" drg
          hol = decisionNamed "is holiday" drg
      fee.dcnRequirements `shouldBe` [RequiredDecision hol.dcnId]
      hol.dcnRequirements `shouldBe` []
      let xml = emitDrg drg
      Text.count "<informationRequirement" xml `shouldBe` 1
      xml `shouldSatisfy` Text.isInfixOf ("<requiredDecision href=\"#" <> hol.dcnId <> "\"/>")

    it "GIVEN and ASSUMEd terms become inputData, and decisions require them" $ do
      let drg = drgOf disjointButUnwitnessable
          ins = drgInputData drg
      sort (map (.idName) ins) `shouldBe` ["income", "limit"]
      map (.idType) (sortOn (.idName) ins) `shouldBe` [DmnNumber, DmnNumber]
      map requirementTarget (decisionNamed "tier" drg).dcnRequirements
        `shouldBe` sort (map (.idId) ins)

    it "two DIFFERENT terms spelling one FEEL name are flagged: DMN inputData has no scope" $ do
      -- `is even` and `bonus` each take their own GIVEN n. L4 scopes those to
      -- their own decisions; DMN's inputData is global, so the emitted model has
      -- two elements a FEEL expression cannot tell apart.
      let drg = drgOf undecomposableGuard
      map (.idId) (drgInputData drg) `shouldBe` ["input_n", "input_n_2"]
      [n.fnFragment | n <- drg.drgNotes, n.fnReason == InputDataNameShared] `shouldBe` ["n"]

    it "element ids derive from L4 names, so they survive a rebuild" $ do
      let drg = drgOf decisionChain
      map (.dcnId) (drgDecisions drg) `shouldBe` ["decision_is_holiday", "decision_fee"]

  describe "emission" $ do
    it "is byte-identical across two independent lowerings of the same source" $ do
      let a = emitDrg (drgOf considerConstructors)
          b = emitDrg (drgOf considerConstructors)
      a `shouldBe` b

    it "escapes XML text and attributes" $ do
      escapeXmlText "a & b < c > \"d\"" `shouldBe` "a &amp; b &lt; c &gt; \"d\""
      escapeXmlAttr "a \"b\" <c>\nd" `shouldBe` "a &quot;b&quot; &lt;c&gt;&#xA;d"
      -- a control character XML 1.0 cannot carry at all becomes visible, not silent
      escapeXmlText "a\x01\&b" `shouldBe` "a\xfffd\&b"

    it "emits a well-formed DMN 1.3 envelope" $ do
      let xml = emitDrg (drgOf considerConstructors)
      xml `shouldSatisfy` Text.isPrefixOf "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<definitions"
      xml `shouldSatisfy` Text.isInfixOf "xmlns=\"https://www.omg.org/spec/DMN/20191111/MODEL/\""
      xml `shouldSatisfy` Text.isInfixOf "hitPolicy=\"UNIQUE\""

  describe "golden" $ do
    it "the Reg CF exhibit, as DMN 1.3 XML" $ goldenDmn examplesRoot
    it "the Reg CF exhibit's fidelity report" $ goldenFidelity examplesRoot

------------------------------------------------------------------------
-- golden
------------------------------------------------------------------------

-- | A realistic multi-decision module, in the shape of the regulation the
-- Lexipedia page describes: a boolean eligibility test, a computed measure, and
-- an investor limit that returns a NUMBER. Goldens live beside the source, the
-- way the OpenFisca ones do.
goldenDmn :: FilePath -> IO (Golden Text)
goldenDmn examplesRoot = do
  src <- Text.readFile (examplesRoot </> "dmn" </> "reg-cf.l4")
  let output = emitDrg (drgNamed "Regulation Crowdfunding" src)
  pure
    Golden
      { output
      , encodePretty = Text.unpack
      , writeToFile = Text.writeFile
      , readFromFile = Text.readFile
      , goldenFile = examplesRoot </> "dmn" </> "expected" </> "reg-cf.dmn"
      , actualFile = Just (examplesRoot </> "dmn" </> "expected" </> "reg-cf.dmn.actual")
      , failFirstTime = True
      }

-- | The other half of the deliverable, and the more interesting one: every place
-- the emitted model left the fragment DMN can analyse, named and located.
goldenFidelity :: FilePath -> IO (Golden Text)
goldenFidelity examplesRoot = do
  src <- Text.readFile (examplesRoot </> "dmn" </> "reg-cf.l4")
  let output = renderFidelityReport (drgNotesAll (drgNamed "Regulation Crowdfunding" src))
  pure
    Golden
      { output
      , encodePretty = Text.unpack
      , writeToFile = Text.writeFile
      , readFromFile = Text.readFile
      , goldenFile = examplesRoot </> "dmn" </> "expected" </> "reg-cf.fidelity.txt"
      , actualFile = Just (examplesRoot </> "dmn" </> "expected" </> "reg-cf.fidelity.actual")
      , failFirstTime = True
      }

------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------

drgOf :: Text -> Drg
drgOf = drgNamed "Test"

drgNamed :: Text -> Text -> Drg
drgNamed name src = case checkWithImports emptyVFS src of
  Left errs -> error ("source failed to typecheck: " <> show errs)
  Right tc ->
    lowerModule
      MkDmnLowerOptions {dloModelName = name, dloSubstitution = tc.tcdSubstitution}
      tc.tcdModule

decisionNamed :: Text -> Drg -> Decision
decisionNamed nm drg = case [d | d <- drgDecisions drg, d.dcnName == nm] of
  (d : _) -> d
  []      -> error ("no decision named " <> show nm)

tableOf :: Text -> Text -> DecisionTable
tableOf nm src = case (decisionNamed nm (drgOf src)).dcnLogic of
  LogicTable t   -> t
  LogicLiteral e -> error ("expected a decision table for " <> show nm <> ", got: " <> show e.feText)

cellTexts :: DmnRule -> [Text]
cellTexts r = map renderUnaryTest r.drInputs
