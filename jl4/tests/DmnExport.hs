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
import L4.Dmn.Lower (DmnLowerOptions (..), lowerModule, moduleTitle)
import L4.Dmn.Markdown (emitMarkdown, markdownReport)
import L4.Interchange.Fidelity
import L4.Syntax (Module, Resolved)
import qualified L4.TypeCheck as TC
import L4.TypeCheck.Types (Severity (..))

import System.FilePath ((</>), takeBaseName)
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

-- | A decomposable guard whose SUBJECT is a FEEL BUILTIN invocation. The cell is
-- a perfectly ordinary constant endpoint, and the column is genuinely
-- executable — but @modulo(n, 2)@ is outside S-FEEL, which is where every
-- published DMN analysis result lives. This is the Advisory case.
fullFeelColumn :: Text
fullFeelColumn =
  "GIVEN n IS A NUMBER\n\
  \GIVETH A NUMBER\n\
  \tier MEANS\n\
  \  BRANCH\n\
  \   IF n MODULO 2 AT LEAST 1 THEN 1\n\
  \   OTHERWISE 0\n"

-- | The Blocking case, and the same shape a reader would mistake for the one
-- above: the subject is an L4 function call. FEEL resolves an invocation against
-- its builtins or a BKM, and this backend emits neither — an L4 @DECIDE@ becomes
-- a 0-ary DMN variable — so @double(n)@ names nothing and KIE says
-- @Unknown variable 'double'@. The text is therefore L4 source, not FEEL.
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

-- | The same defect on the OUTPUT side of a rule that fires. KIE compiles the
-- entry, fails, and the decision evaluates to null with status FAILED.
verbatimOutput :: Text
verbatimOutput =
  "GIVEN n IS A NUMBER\n\
  \GIVETH A NUMBER\n\
  \double n MEANS n TIMES 2\n\
  \\n\
  \GIVEN c IS A BOOLEAN\n\
  \GIVETH A NUMBER\n\
  \amount MEANS\n\
  \  BRANCH\n\
  \   IF c THEN double 5\n\
  \   OTHERWISE 0\n"

-- | The same defect in the @\<defaultOutputEntry\>@ — the position 18 of the 28
-- corpus instances occupy, and the only one that fails SILENTLY: KIE returns
-- null with status SUCCEEDED and no evaluation-time message.
verbatimDefault :: Text
verbatimDefault =
  "GIVEN n IS A NUMBER\n\
  \GIVETH A NUMBER\n\
  \double n MEANS n TIMES 2\n\
  \\n\
  \GIVEN c IS A BOOLEAN\n\
  \GIVETH A NUMBER\n\
  \amount MEANS\n\
  \  BRANCH\n\
  \   IF c THEN 1\n\
  \   OTHERWISE double 5\n"

-- | A select idiom (so: a boxed literal expression, deliberately without a
-- D-LITERALEXPR note) one of whose operands cannot be rendered. Corpus instance:
-- @max(cash out, conversion amount(liq))@ in @safe-post-new.l4@.
verbatimSelect :: Text
verbatimSelect =
  "GIVEN n IS A NUMBER\n\
  \GIVETH A NUMBER\n\
  \double n MEANS n TIMES 2\n\
  \\n\
  \ASSUME cash IS A NUMBER\n\
  \GIVETH A NUMBER\n\
  \greater MEANS\n\
  \  IF cash AT LEAST double 5 THEN cash ELSE double 5\n"

-- | Quoted statute text carried along for isomorphism. A string literal in
-- direct boolean-operand position becomes an 'Inert' node whose value is its
-- context's identity element. 794 of these appear in the Charities corpus alone,
-- and before they were rendered every guard containing one was poisoned into L4
-- source.
inertScaffolding :: Text
inertScaffolding =
  "GIVEN c IS A BOOLEAN\n\
  \      d IS A BOOLEAN\n\
  \GIVETH A NUMBER\n\
  \amount MEANS\n\
  \  BRANCH\n\
  \   IF c OR \"subject to paragraph 3\" THEN 1\n\
  \   IF d AND \"and for the avoidance of doubt\" THEN 2\n\
  \   OTHERWISE 0\n"

-- | Record construction. FEEL's context literal is the exact counterpart, and it
-- is the one structured value FEEL has.
recordConstruction :: Text
recordConstruction =
  "DECLARE Assessment\n\
  \  HAS rate IS A NUMBER\n\
  \      band IS A STRING\n\
  \\n\
  \GIVEN c IS A BOOLEAN\n\
  \GIVETH AN Assessment\n\
  \assess MEANS\n\
  \  IF c\n\
  \  THEN Assessment WITH rate IS 40, band IS \"high\"\n\
  \  ELSE Assessment WITH rate IS 0, band IS \"low\"\n"

-- | The other half of the pair: projection was always rendered @r.f@, so
-- construction had to use the same field names or the two would not meet.
recordProjection :: Text
recordProjection =
  "DECLARE Assessment\n\
  \  HAS rate IS A NUMBER\n\
  \      band IS A STRING\n\
  \\n\
  \GIVEN a IS AN Assessment\n\
  \GIVETH A NUMBER\n\
  \level MEANS\n\
  \  BRANCH\n\
  \   IF a's rate AT LEAST 10 THEN 1\n\
  \   OTHERWISE 0\n"

-- | A percentage. Division is inside S-FEEL, so this costs no fidelity at all.
percentBody :: Text
percentBody =
  "GIVEN base IS A NUMBER\n\
  \      c IS A BOOLEAN\n\
  \GIVETH A NUMBER\n\
  \charge MEANS\n\
  \  IF c THEN (10 %) TIMES base ELSE 0\n"

-- | A cons. FEEL has no cons operator but does have @concatenate@ (DMN 1.1).
consBody :: Text
consBody =
  "GIVEN rest IS A LIST OF NUMBER\n\
  \      c IS A BOOLEAN\n\
  \GIVETH A LIST OF NUMBER\n\
  \queue MEANS\n\
  \  IF c THEN 1 FOLLOWED BY rest ELSE rest\n"

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

-- | The shape the corpus's best decision tables actually have: a WHERE-wrapped
-- chain of ELSE-IFs testing successively higher thresholds, returning a STRING.
-- Two things must happen or it degrades to one opaque rule: the WHERE has to be
-- peeled (normaliseGuarded cannot see through it) and the nest has to be
-- flattened into siblings.
whereWrappedTiers :: Text
whereWrappedTiers =
  "ASSUME `offering amount` IS A NUMBER\n\
  \ASSUME `first time` IS A BOOLEAN\n\
  \GIVETH A STRING\n\
  \`financial statements required` MEANS\n\
  \  IF   `aggregate` AT MOST 100000\n\
  \  THEN \"certified\"\n\
  \  ELSE IF   `aggregate` AT MOST 500000\n\
  \       THEN \"reviewed\"\n\
  \       ELSE IF   `relief applies`\n\
  \            THEN \"reviewed\"\n\
  \            ELSE \"audited\"\n\
  \  WHERE\n\
  \  `aggregate` MEANS `offering amount`\n\
  \  `relief applies` MEANS `first time` AND `aggregate` AT MOST 300000\n"

-- | A CONSIDER over three nullary constructors returning NUMBER. The corpus's
-- cleanest table, and the one that must come out as U.
assuranceLevel :: Text
assuranceLevel =
  "DECLARE Assurance\n\
  \  IS ONE OF\n\
  \    low\n\
  \    moderate\n\
  \    high\n\
  \ASSUME level IS A Assurance\n\
  \GIVETH A NUMBER\n\
  \`assurance level` MEANS\n\
  \  CONSIDER level\n\
  \  WHEN low THEN 1\n\
  \  WHEN moderate THEN 2\n\
  \  WHEN high THEN 3\n\
  \  OTHERWISE 0\n"

-- | @IF a AT LEAST b THEN a ELSE b@ is `max`, not a decision over two cases.
maxIdiom :: Text
maxIdiom =
  "ASSUME a IS A NUMBER\n\
  \ASSUME b IS A NUMBER\n\
  \GIVETH A NUMBER\n\
  \`the greater` MEANS\n\
  \  IF a AT LEAST b THEN a ELSE b\n"

-- | The same SHAPE over STRING. L4's comparisons are overloaded — @__GEQ__@ has
-- variants over NUMBER, STRING and BOOLEAN — so the syntactic match says nothing
-- about the operand type, and this is a well-typed L4 program over any of them.
-- STRING is a type FEEL orders (DMN 1.3 §10.3.2.13, Table 54, has a @string@ row
-- defining lexicographic @\<@), so it is a "comparable item" for @min@\/@max@
-- (§10.3.4.4, Table 75) and the fold is in-domain. It has to be: the un-folded
-- fallthrough would be @(if s >= t then s else t)@, whose @\>=@ is legal by that
-- same Table 54 row. Declining @max@ while emitting @\>=@ would not be
-- conservative, only inconsistent.
stringSelect :: Text
stringSelect =
  "ASSUME s IS A STRING\n\
  \ASSUME t IS A STRING\n\
  \GIVETH A STRING\n\
  \`the later name` MEANS\n\
  \  IF s AT LEAST t THEN s ELSE t\n"

-- | ...and over BOOLEAN, which is the one type with no defence: Table 54 has
-- rows for number, string, date, time, date-and-time and the two durations, and
-- __none for boolean__, under a sentence that says the ordering operators "are
-- defined only for the datatypes listed in Table 54". So @max(true, false)@ is
-- outside the builtin's domain (§10.3.4: an out-of-domain parameter gives
-- @null@) — and, the point the first version of this fix missed, so is the
-- @p >= q@ it would fall through to. Neither spelling is FEEL, so the fallthrough
-- is not a safe harbour: the comparison itself must go out verbatim, under a
-- Blocking note. (KIE answers @true@ for @max(true, false)@ anyway, because its
-- domain is Java's @Comparable@ — exactly the engine-specific luck an exporter
-- must not depend on.)
booleanSelect :: Text
booleanSelect =
  "ASSUME p IS A BOOLEAN\n\
  \ASSUME q IS A BOOLEAN\n\
  \GIVETH A BOOLEAN\n\
  \`the stronger claim` MEANS\n\
  \  IF p AT LEAST q THEN p ELSE q\n"

-- | The select in a position 'renderFeelIn' renders as an EXPRESSION rather than
-- decomposing into rows: the subject of a guard. STRING is orderable, so the
-- peephole fires here exactly as it does for NUMBER.
stringSelectAsSubject :: Text
stringSelectAsSubject =
  "ASSUME s IS A STRING\n\
  \ASSUME t IS A STRING\n\
  \GIVETH A NUMBER\n\
  \`tier` MEANS\n\
  \  BRANCH\n\
  \   IF (IF s AT LEAST t THEN s ELSE t) EQUALS \"zulu\" THEN 1\n\
  \   OTHERWISE 0\n"

-- | The numeric twin of 'stringSelectAsSubject', in the same position.
numberSelectAsSubject :: Text
numberSelectAsSubject =
  "ASSUME a IS A NUMBER\n\
  \ASSUME b IS A NUMBER\n\
  \GIVETH A NUMBER\n\
  \`tier` MEANS\n\
  \  BRANCH\n\
  \   IF (IF a AT LEAST b THEN a ELSE b) EQUALS 100 THEN 1\n\
  \   OTHERWISE 0\n"

-- | The BOOLEAN twin, in the same position. Here the gate declines, and the
-- un-folded @if@ carries a boolean @\>=@ — so what must appear is L4 source and
-- a Blocking note, not @(if p >= q then p else q)@ tagged S-FEEL.
booleanSelectAsSubject :: Text
booleanSelectAsSubject =
  "ASSUME p IS A BOOLEAN\n\
  \ASSUME q IS A BOOLEAN\n\
  \GIVETH A NUMBER\n\
  \`tier` MEANS\n\
  \  BRANCH\n\
  \   IF (IF p AT LEAST q THEN p ELSE q) THEN 1\n\
  \   OTHERWISE 0\n"

-- | A select as a ROW BODY — the position @childOf@ governs, and the only one
-- where the peephole's /structural/ job shows. This one cannot fold (BOOLEAN),
-- which is precisely why it is the test: 'L4.Dmn.Lower.flattenGuarded' must
-- still refuse to splice it, or the table gains two rules the source never
-- stated and drops from @U@ to @F@.
booleanSelectAsBody :: Text
booleanSelectAsBody =
  "ASSUME p IS A BOOLEAN\n\
  \ASSUME q IS A BOOLEAN\n\
  \ASSUME late IS A BOOLEAN\n\
  \GIVETH A BOOLEAN\n\
  \`claim` MEANS\n\
  \  BRANCH\n\
  \   IF late THEN IF p AT LEAST q THEN p ELSE q\n\
  \   OTHERWISE p\n"

-- | The same idiom over DATE — the shape @daydate.l4@'s @the earlier of@ and
-- @the later of@ have, and the reason this test imports that library rather than
-- writing the comparison bare. L4's comparison BUILTINS are @NUMBER@, @STRING@
-- and @BOOLEAN@ only, so a bare @start AT MOST end@ over DATE is not a DATE
-- comparison at all: it is an ambiguous overload, which the typechecker rejects
-- with "There are multiple definitions for the identifier @__LEQ__@". Asserting
-- on that would pin the exporter's treatment of a module L4 refuses.
-- @daydate.l4@ supplies real @DATE@ variants of @__LEQ__@ \/ @__GEQ__@ \/
-- @__LT__@ \/ @__GT__@, and DMN Table 54 has a @date@ row, so this one both
-- typechecks and folds.
minIdiomDate :: Text
minIdiomDate =
  "IMPORT daydate\n\
  \ASSUME `start` IS A DATE\n\
  \ASSUME `end` IS A DATE\n\
  \GIVETH A DATE\n\
  \`the earlier of` MEANS\n\
  \  IF `start` AT MOST `end` THEN `start` ELSE `end`\n"

-- | Corpus near-miss 1 (safe-post-new.l4:188): the ELSE arm IS an operand, but
-- the THEN arm is that operand PLUS a term. Must not fire.
nearMissPlusTerm :: Text
nearMissPlusTerm =
  "ASSUME pool IS A NUMBER\n\
  \ASSUME promised IS A NUMBER\n\
  \ASSUME increase IS A NUMBER\n\
  \GIVETH A NUMBER\n\
  \`new pool` MEANS\n\
  \  IF promised GREATER THAN pool THEN pool PLUS increase ELSE pool\n"

-- | Corpus near-miss 2 (math.l4:43, if-example.l4:20): `abs`, four times over.
-- Arms are `n` and `0 - n`; operands are `n` and `0`. Must not fire.
nearMissAbs :: Text
nearMissAbs =
  "ASSUME n IS A NUMBER\n\
  \GIVETH A NUMBER\n\
  \magnitude MEANS\n\
  \  IF n LESS THAN 0 THEN 0 MINUS n ELSE n\n"

-- | Corpus near-miss 3 (excel-date.l4:80): an off-by-one, not a max.
nearMissOffByOne :: Text
nearMissOffByOne =
  "ASSUME n IS A NUMBER\n\
  \GIVETH A NUMBER\n\
  \adjusted MEANS\n\
  \  IF n GREATER THAN 60 THEN n MINUS 1 ELSE n\n"

-- | A lifted max with a LITERAL operand: the Reg CF $2,500 investment floor in
-- miniature. Lifting is right (the statute says "the greater of"), but the floor
-- stops being a row anyone can point at, and the report must say so.
liftedFloor :: Text
liftedFloor =
  "ASSUME income IS A NUMBER\n\
  \GIVETH A NUMBER\n\
  \`investment limit` MEANS\n\
  \  BRANCH\n\
  \   IF income AT LEAST 1000 THEN IF 2500 AT LEAST income THEN 2500 ELSE income\n\
  \   OTHERWISE 0\n"

-- | A DATE-typed column. DMN has a `date` type; dmnmd does not.
dateColumn :: Text
dateColumn =
  "ASSUME `filed on` IS A DATE\n\
  \ASSUME `deadline` IS A DATE\n\
  \ASSUME late IS A BOOLEAN\n\
  \GIVETH A DATE\n\
  \`effective date` MEANS\n\
  \  BRANCH\n\
  \   IF late THEN `deadline`\n\
  \   OTHERWISE `filed on`\n"

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
      map (.code) t.dtNotes `shouldContain` ["D-UNDECOMPOSABLE"]

    it "a constructor is quoted on the OUTPUT side as well as the input side" $ do
      let t = tableOf "complement" constructorOutput
      map (.drOutput.feText) t.dtRules `shouldBe` ["\"green\"", "\"red\""]
      fmap (.feText) t.dtOutput.ocDefault `shouldBe` Just "\"blue\""
      t.dtOutput.ocType `shouldBe` DmnString
      -- and a quoted constant is not a "computed output"
      map (.code) t.dtNotes `shouldNotContain` ["D-COMPUTEDOUTPUT"]

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

  describe "the shapes the real corpus has" $ do
    it "a WHERE-wrapped 4-tier chain flattens to four rules with the local inlined" $ do
      let t = tableOf "financial statements required" whereWrappedTiers
      t.dtHitPolicy `shouldBe` HitFirst
      length t.dtRules `shouldBe` 4
      -- `aggregate` is gone; what is left is what it stood for
      -- and the inlined local's own conjuncts get decomposed too, so the third
      -- tier shares the `offering amount` column rather than hiding inside an
      -- opaque boolean one
      map (.icExpr.feText) t.dtInputs `shouldBe` ["offering amount", "first time"]
      map cellTexts t.dtRules
        `shouldBe` [ ["<= 100000", "-"]
                   , ["<= 500000", "-"]
                   , ["<= 300000", "true"]
                   , ["-", "-"]
                   ]
      map (.drOutput.feText) t.dtRules
        `shouldBe` ["\"certified\"", "\"reviewed\"", "\"reviewed\"", "\"audited\""]
      t.dtOutput.ocType `shouldBe` DmnString
      map (.code) t.dtNotes `shouldContain` ["D-INLINEDLOCAL"]
      [n.message | n <- t.dtNotes, n.code == "D-INLINEDLOCAL"]
        `shouldSatisfy` all (Text.isInfixOf "`aggregate`")

    it "a CONSIDER over three constructors returning NUMBER is a clean U table" $ do
      let t = tableOf "assurance level" assuranceLevel
      t.dtHitPolicy `shouldBe` HitUnique
      length t.dtRules `shouldBe` 3
      t.dtOutput.ocType `shouldBe` DmnNumber
      fmap (.feText) t.dtOutput.ocDefault `shouldBe` Just "0"
      map cellTexts t.dtRules `shouldBe` [["\"low\""], ["\"moderate\""], ["\"high\""]]
      -- constant outputs and a single-hit policy: this one is INSIDE the
      -- fragment DMN can analyse, and has nothing to report.
      t.dtNotes `shouldBe` []

  describe "the select idiom: max/min wearing a conditional's clothes" $ do
    it "IF a >= b THEN a ELSE b is max(a, b), not a one-case table" $ do
      let d = decisionNamed "the greater" (drgOf maxIdiom)
      case d.dcnLogic of
        LogicLiteral e -> e.feText `shouldBe` "max(a, b)"
        LogicTable _   -> expectationFailure "expected max(a, b), got a decision table"

    -- The SHAPE is not the whole idiom: L4's `<` / `<=` / `>` / `>=` are
    -- overloaded over NUMBER, STRING and BOOLEAN (and daydate.l4 adds DATE), so
    -- `IF s AT LEAST t THEN s ELSE t` is a well-typed program over any of them
    -- and the syntax says nothing about which. What decides the fold is whether
    -- FEEL can ORDER the operands: min/max take "comparable items" (DMN 1.3
    -- §10.3.4.4 Table 75) and §10.3.2.13 fixes what is comparable -- "the other
    -- comparison operators are defined only for the datatypes listed in
    -- Table 54", whose rows are number, string, date, date-and-time, time and
    -- the two durations. So NUMBER, STRING and DATE fold; BOOLEAN does not.
    --
    -- The line has to fall there and not one type earlier, because the
    -- fallthrough for a declined fold is `(if s >= t then s else t)` -- and that
    -- `>=` is legal in exactly the same rows of exactly the same table. Refusing
    -- `min` over dates while emitting `<=` over dates would not be conservative,
    -- just inconsistent.
    it "fires over STRING, which Table 54 orders lexicographically" $ do
      let d = decisionNamed "the later name" (drgOf stringSelect)
      case d.dcnLogic of
        LogicLiteral e -> e.feText `shouldBe` "max(s, t)"
        LogicTable _   -> expectationFailure "expected max(s, t), got a decision table"
      d.dcnType `shouldBe` DmnString

    it "fires over DATE, which Table 54 orders too (daydate's `the earlier of`)" $ do
      let d = decisionNamed "the earlier of" (drgOf minIdiomDate)
      case d.dcnLogic of
        LogicLiteral e -> e.feText `shouldBe` "min(start, end)"
        LogicTable _   -> expectationFailure "expected min(start, end), got a decision table"
      d.dcnType `shouldBe` DmnDate

    -- BOOLEAN is the one type L4 orders and FEEL does not, and the un-folded
    -- `if` is NOT a safe harbour for it: `p >= q` is outside FEEL by the same
    -- clause as `max(p, q)`. So declining the fold is only half the job -- the
    -- comparison has to leave as L4 source, under a Blocking note, rather than
    -- as an S-FEEL claim that an engine will evaluate it.
    it "does not fire over BOOLEAN, which FEEL has no ordering for at all" $ do
      mustNotBeSelect "the stronger claim" booleanSelect
      let t = tableOf "the stronger claim" booleanSelect
      map (.icExpr.feText) t.dtInputs `shouldBe` ["p AT LEAST q"]
      map (.icExpr.feFragment) t.dtInputs `shouldBe` [L4Verbatim]
      map (.code) t.dtNotes `shouldContain` ["D-NONFEELINPUT"]
      [n.severity | n <- t.dtNotes, n.code == "D-NONFEELINPUT"] `shouldBe` [Blocking]
      -- and in particular NOT the transliteration that reads as executable FEEL
      -- (escaped or not: `>` leaves the emitter as `&gt;` in a <text> element)
      emitDrg (drgOf booleanSelect)
        `shouldSatisfy` (\x -> not (Text.isInfixOf "p &gt;= q" x) && not (Text.isInfixOf "p >= q" x))

    it "a STRING select in expression position folds, like its NUMBER twin" $ do
      let t = tableOf "tier" stringSelectAsSubject
      map (.icExpr.feText) t.dtInputs `shouldBe` ["max(s, t)"]
      map (.drInputs) t.dtRules `shouldBe` [[TestEq (VStr "zulu")]]

    it "...as does the NUMBER twin in the same position" $ do
      let t = tableOf "tier" numberSelectAsSubject
      map (.icExpr.feText) t.dtInputs `shouldBe` ["max(a, b)"]
      map (.drInputs) t.dtRules `shouldBe` [[TestEq (VNum 100)]]

    it "...while the BOOLEAN twin becomes a verbatim column, reported Blocking" $ do
      let t = tableOf "tier" booleanSelectAsSubject
      map (.icExpr.feText) t.dtInputs `shouldBe` ["IF (p AT LEAST q) THEN p ELSE q"]
      map (.icExpr.feFragment) t.dtInputs `shouldBe` [L4Verbatim]
      map (.code) t.dtNotes `shouldContain` ["D-NONFEELINPUT"]

    -- The peephole has a second, purely structural job: keeping a select OUT of
    -- the row splicer. That job does not depend on the fold firing, so the test
    -- for it uses the operand type that cannot fold. Expanding this body turns
    -- one rule into three -- the comparison becomes a second column, `late AND
    -- p >= q` and `late` become separate rules, and the OTHERWISE becomes an
    -- all-`-` row -- which forces First: two case distinctions the source never
    -- draws, plus DMN 8.2.10 order dependence, in exchange for nothing.
    it "a select as a ROW BODY is never spliced into rows, even when it cannot fold" $ do
      let t = tableOf "claim" booleanSelectAsBody
      t.dtHitPolicy `shouldBe` HitUnique
      length t.dtRules `shouldBe` 1
      map (.icExpr.feText) t.dtInputs `shouldBe` ["late"]
      map (.code) t.dtNotes `shouldSatisfy` notElem "D-ORDERDEPENDENT"

    it "does not fire when an arm is an operand PLUS a term" $
      mustNotBeSelect "new pool" nearMissPlusTerm

    it "does not fire on abs" $
      mustNotBeSelect "magnitude" nearMissAbs

    it "does not fire on an off-by-one" $
      mustNotBeSelect "adjusted" nearMissOffByOne

    it "a lifted max is NOT flattened into extra rows, and the threshold is reported" $ do
      let t = tableOf "investment limit" liftedFloor
      -- ONE rule, not three: the max is a value, so it stays in the output
      -- expression instead of becoming a floor row and a cap row.
      length t.dtRules `shouldBe` 1
      map (.drOutput.feText) t.dtRules `shouldBe` ["max(2500, income)"]
      fmap (.feText) t.dtOutput.ocDefault `shouldBe` Just "0"
      let notes = [n | n <- t.dtNotes, n.code == "D-LIFTEDTHRESHOLD"]
      map (.severity) notes `shouldBe` [Advisory]
      map (.message) notes `shouldSatisfy` all (Text.isInfixOf "2500")
      -- and the computed output is itself reported, per DMN-STEELMAN 2.5
      map (.code) t.dtNotes `shouldContain` ["D-COMPUTEDOUTPUT"]

  describe "fidelity: never say more than the L4 does" $ do
    it "an undecomposable guard becomes a boolean column AND is named in the report" $ do
      let t = tableOf "bonus" undecomposableGuard
      map (.icExpr.feText) t.dtInputs `shouldBe` ["`is even` OF n"]
      map (.drInputs) t.dtRules `shouldBe` [[TestEq (VBool True)]]
      let notes = [n | n <- t.dtNotes, n.code == "D-UNDECOMPOSABLE"]
      map (.message) notes `shouldSatisfy` all (Text.isInfixOf "`is even` OF n")
      -- the note is located, names what was given up, and is honest about severity:
      -- DMN CAN express this, so it is advisory, not blocking.
      map (.range) notes `shouldSatisfy` all isJust
      map (.severity) notes `shouldBe` [Advisory]
      map (.lost) notes `shouldSatisfy` all (not . Text.null)

    it "a column whose input expression leaves S-FEEL is named and located" $ do
      let t = tableOf "tier" fullFeelColumn
      -- the cell is a fine constant endpoint; it is the COLUMN that left the
      -- analysable fragment, because S-FEEL has no function invocation. `modulo`
      -- is a FEEL BUILTIN, so this is genuinely executable -- merely unanalysable.
      map (.icExpr.feText) t.dtInputs `shouldBe` ["modulo(n, 2)"]
      map (.icExpr.feFragment) t.dtInputs `shouldBe` [FullFeel]
      map (.drInputs) t.dtRules `shouldBe` [[TestCmp OpGeq (VNum 1)]]
      let notes = [n | n <- t.dtNotes, n.code == "D-NONFEEL"]
      map (.message) notes `shouldSatisfy` all (Text.isInfixOf "modulo(n, 2)")
      map (.range) notes `shouldSatisfy` all isJust
      map (.severity) notes `shouldBe` [Advisory]

    it "a decision that does not normalise becomes a literalExpression, with a note" $ do
      let drg = drgOf notATable
          d   = decisionNamed "ok" drg
      case d.dcnLogic of
        LogicLiteral e -> e.feText `shouldBe` "a and b"
        LogicTable _   -> expectationFailure "expected a literal expression, got a decision table"
      [(n.code, n.severity) | n <- drg.drgNotes] `shouldBe` [("D-LITERALEXPR", Blocking)]
      emitDrg drg `shouldSatisfy` Text.isInfixOf "<literalExpression"

    it "an elided CONSIDER arm with no OTHERWISE refuses to become a table" $ do
      -- DMN answers null where the rule answers FALSE, so there must be no table
      let drg = drgOf elidedArmNoOtherwise
      case (decisionNamed "charitable" drg).dcnLogic of
        LogicLiteral _ -> pure ()
        LogicTable _   -> expectationFailure "emitted a table that answers null where the rule answers FALSE"
      [n.code | n <- drg.drgNotes] `shouldBe` ["D-LITERALEXPR"]
      [n.message | n <- drg.drgNotes] `shouldSatisfy` all (Text.isInfixOf "answer null")

    it "...but with an OTHERWISE the default output plugs the hole" $ do
      let t = tableOf "charitable" elidedArmWithOtherwise
      map (.drInputs) t.dtRules `shouldBe` [[TestEq (VStr "education")]]
      fmap (.feText) t.dtOutput.ocDefault `shouldBe` Just "false"

    it "U is claimed only when the CELLS witness it, not merely because the guards are exclusive" $ do
      let t = tableOf "tier" disjointButUnwitnessable
      -- L4 knows `< limit` and `>= limit` are complementary...
      t.dtHitPolicy `shouldBe` HitFirst
      -- ...and the report says why the table cannot show it
      map (.code) t.dtNotes `shouldContain` ["D-HITPOLICY"]

    it "an order-dependent table says so, in DMN's own terms" $ do
      let t = tableOf "rate" overlappingThresholds
      map (.code) t.dtNotes `shouldContain` ["D-ORDERDEPENDENT"]
      [n.message | n <- t.dtNotes, n.code == "D-ORDERDEPENDENT"]
        `shouldSatisfy` all (Text.isInfixOf "hard to validate manually")

    it "a clean numeric table has no fidelity losses at all" $
      (tableOf "amount" ifThenElseNumber).dtNotes `shouldBe` []

  -- The line between "outside the analysable fragment" (Advisory) and "outside
  -- FEEL" (Blocking). Everything in this block was previously reported Advisory
  -- or not at all, and every one of these shapes was VERIFIED to fail on
  -- Drools/KIE 8.44.0.Final -- loudly for an input expression or a firing rule,
  -- SILENTLY (null, status SUCCEEDED) for a defaultOutputEntry.
  describe "fidelity: L4 source in a <text> element is Blocking, not Advisory" $ do
    it "an L4-source INPUT expression is Blocking, and does not merely say `outside S-FEEL`" $ do
      let t = tableOf "tier" nonSFeelColumn
      -- an L4 call is not a FEEL invocation: DMN decisions are 0-ary, so there
      -- is nothing named `double` for an engine to resolve.
      map (.icExpr.feText) t.dtInputs `shouldBe` ["double OF n"]
      map (.icExpr.feFragment) t.dtInputs `shouldBe` [L4Verbatim]
      let blocking = [n | n <- t.dtNotes, n.code == "D-NONFEELINPUT"]
      map (.severity) blocking `shouldBe` [Blocking]
      map (.message) blocking `shouldSatisfy` all (Text.isInfixOf "L4 source, not FEEL")
      map (.range) blocking `shouldSatisfy` all isJust
      -- mutually exclusive with the Advisory note about the same column
      map (.code) t.dtNotes `shouldNotContain` ["D-NONFEEL"]

    it "...even when the column was a fallback, which used to suppress the report" $ do
      -- `fallbackKeys` silences D-NONFEEL for a fallback column, on the ground
      -- that D-UNDECOMPOSABLE already covered it. D-UNDECOMPOSABLE is Advisory
      -- and talks about endpoints, so that suppression must not extend here.
      let t = tableOf "bonus" undecomposableGuard
      map (.icExpr.feFragment) t.dtInputs `shouldBe` [L4Verbatim]
      map (.code) t.dtNotes `shouldContain` ["D-UNDECOMPOSABLE"]
      [n.severity | n <- t.dtNotes, n.code == "D-NONFEELINPUT"] `shouldBe` [Blocking]

    it "an L4-source OUTPUT entry is Blocking, not a `computed output` advisory" $ do
      let t = tableOf "amount" verbatimOutput
      map (.drOutput.feText) t.dtRules `shouldBe` ["double OF 5"]
      map (.drOutput.feFragment) t.dtRules `shouldBe` [L4Verbatim]
      let blocking = [n | n <- t.dtNotes, n.code == "D-NONFEELOUTPUT"]
      map (.severity) blocking `shouldBe` [Blocking]
      map (.message) blocking `shouldSatisfy` all (Text.isInfixOf "L4 source, not FEEL")
      -- the whole point: this used to be swallowed by an Advisory note whose
      -- message ("an expression, not a constant") describes a milder problem.
      map (.code) t.dtNotes `shouldNotContain` ["D-COMPUTEDOUTPUT"]

    it "a verbatim defaultOutputEntry -- the silent case -- is reported too" $ do
      -- 18 of the 28 corpus instances sat in exactly this position, where KIE
      -- returns null with status SUCCEEDED and emits no evaluation-time message.
      let t = tableOf "amount" verbatimDefault
      fmap (.feFragment) t.dtOutput.ocDefault `shouldBe` Just L4Verbatim
      [n.severity | n <- t.dtNotes, n.code == "D-NONFEELOUTPUT"] `shouldBe` [Blocking]
      [n.lost | n <- t.dtNotes, n.code == "D-NONFEELOUTPUT"]
        `shouldSatisfy` all (Text.isInfixOf "SILENTLY")

    it "a valid-FEEL computed output stays Advisory: the split is a boundary, not a demotion" $ do
      let t = tableOf "investment limit" liftedFloor
      map (.drOutput.feFragment) t.dtRules `shouldBe` [FullFeel]
      map (.code) t.dtNotes `shouldContain` ["D-COMPUTEDOUTPUT"]
      map (.code) t.dtNotes `shouldNotContain` ["D-NONFEELOUTPUT"]

    it "a boxed max/min over an unrenderable operand no longer ships with ZERO notes" $ do
      -- The select-idiom branch deliberately emits no D-LITERALEXPR, so this
      -- shape used to carry no fidelity note at all.
      let drg = drgOf verbatimSelect
      case (decisionNamed "greater" drg).dcnLogic of
        LogicLiteral e -> e.feFragment `shouldBe` L4Verbatim
        LogicTable _   -> expectationFailure "expected a boxed literal expression"
      [(n.code, n.severity) | n <- drg.drgNotes] `shouldContain` [("D-NONFEELOUTPUT", Blocking)]

    it "dmnmd will not print an L4 phrase as a column header, even when it spells like a name" $ do
      -- `double OF n` satisfies dmnmd's varname grammar (letters and spaces) by
      -- accident. The fragment, not the spelling, is what decides.
      let drg = drgOf nonSFeelColumn
      emitMarkdown drg `shouldNotSatisfy` Text.isInfixOf "double"
      let notes = [n | n <- (markdownReport drg).notes, n.code == "D-MD-NONIDENTCOLUMN"]
      map (.severity) notes `shouldBe` [Blocking]
      map (.message) notes `shouldSatisfy` all (Text.isInfixOf "L4 source, not FEEL")

  -- Four constructs that DMN can express exactly and that this backend simply
  -- did not render, so they fell to the verbatim fallback and poisoned every
  -- expression containing them. Each rendering is the evaluator's own
  -- definition, and each was executed against KIE 8.44.0.Final.
  describe "lowerings that remove the need for a fallback" $ do
    it "Inert scaffolding is its context's identity element, which is S-FEEL" $ do
      let t = tableOf "amount" inertScaffolding
      -- OR context -> false (the OR identity); AND context -> true, except that
      -- a top-level Inert conjunct is dropped from the table entirely, so the
      -- second column is just `d`.
      map (.icExpr.feText) t.dtInputs `shouldBe` ["c or false", "d"]
      map (.icExpr.feFragment) t.dtInputs `shouldBe` [FullFeel, SFeel]
      -- and nothing is Blocking: the statute text survives in the rule's
      -- <description>, which carries the guard's full source.
      map (.severity) t.dtNotes `shouldNotContain` [Blocking]

    -- NOT a lowering, and deliberately so. A `{f: v, …}` context literal for
    -- record construction was written and reverted: `AppNamed` is L4's general
    -- named-argument APPLICATION, so `f WITH x IS 3, y IS 4` (with `f MEANS x
    -- TIMES y`) is 12 in L4 and `{x: 3, y: 4}` under that lowering — which KIE
    -- compiles without complaint. It also drops the constructor tag (`Paid WITH
    -- amount IS 40` and `Owed WITH amount IS 40` collapse to one FEEL value that
    -- L4 says are unequal), never checks field names against FEEL's reserved
    -- words (`{for: 1}` fails to compile while the decision still reports
    -- SUCCEEDED), and omits computed fields that `Proj` still reads.
    --
    -- Each of those is a silently wrong answer reported Advisory, which is worse
    -- than the honest Blocking below. This test is the regression guard.
    it "record construction stays verbatim and is Blocking, not a context literal" $ do
      let t = tableOf "assess" recordConstruction
      map (.drOutput.feFragment) t.dtRules `shouldBe` [L4Verbatim]
      map (.drOutput.feText) t.dtRules
        `shouldSatisfy` all (Text.isInfixOf "Assessment WITH")
      map (.code) t.dtNotes `shouldContain` ["D-NONFEELOUTPUT"]
      [n | n <- t.dtNotes, n.code == "D-NONFEELOUTPUT"]
        `shouldSatisfy` all ((== Blocking) . (.severity))

    it "a projection off a record-typed parameter round-trips through the field names" $ do
      let t = tableOf "level" recordProjection
      map (.icExpr.feText) t.dtInputs `shouldBe` ["a.rate"]
      map (.icExpr.feFragment) t.dtInputs `shouldBe` [SFeel]

    it "PERCENT is division by 100, and stays inside S-FEEL" $ do
      let t = tableOf "charge" percentBody
      map (.drOutput.feText) t.dtRules `shouldBe` ["10 / 100 * base"]
      map (.drOutput.feFragment) t.dtRules `shouldBe` [SFeel]

    it "FOLLOWED BY is FEEL's concatenate over a one-element list" $ do
      let t = tableOf "queue" consBody
      map (.drOutput.feText) t.dtRules `shouldBe` ["concatenate([1], rest)"]
      map (.drOutput.feFragment) t.dtRules `shouldBe` [FullFeel]

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
      let shared = [n | n <- drg.drgNotes, n.code == "D-SCOPE"]
      map (.severity) shared `shouldBe` [Lossy]
      map (.message) shared `shouldSatisfy` all (Text.isInfixOf "both named `n`")
      -- The count is computed, not spelled. It read "two" unconditionally
      -- until 2026-07-27, which understated the Reg CF corpus's eight-way
      -- collision on `issuer` as a two-way one.
      map (.message) shared `shouldSatisfy` all (Text.isInfixOf "two different terms")

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

  describe "dmnmd markdown (the second emitter over the same IR)" $ do
    it "renders a table as a pipe table, with the hit policy as the first header cell" $ do
      let md = emitMarkdown (drgOf considerConstructors)
      md `shouldSatisfy` Text.isInfixOf "| F | c : String | score (out) : Number |"
      md `shouldSatisfy` Text.isInfixOf "| 1 | red | 1 |"
      md `shouldSatisfy` Text.isInfixOf "| 2 | green | 2 |"
      -- the OTHERWISE became the catch-all row the U-to-F downgrade bought
      md `shouldSatisfy` Text.isInfixOf "| 3 | - | 0 |"

    it "downgrades U to F because dmnmd has no defaultOutputEntry, and says so" $ do
      let drg = drgOf considerConstructors
      (decisionNamed "score" drg).dcnLogic `shouldSatisfy` isUniqueTable
      emitMarkdown drg `shouldSatisfy` Text.isInfixOf "| F |"
      let notes = [n | n <- (markdownReport drg).notes, n.code == "D-MD-NODEFAULT"]
      map (.severity) notes `shouldBe` [Lossy]
      map (.message) notes `shouldSatisfy` all (Text.isInfixOf "U down to F")

    it "renders a multi-value cell comma-separated, and a comparison literally" $ do
      emitMarkdown (drgOf orOverOneColumn) `shouldSatisfy` Text.isInfixOf "| 1 | red, green | 1 |"
      emitMarkdown (drgOf overlappingThresholds) `shouldSatisfy` Text.isInfixOf "| 1 | >= 200000 | 10 |"

    it "ends with exactly one newline, because dmnmd misdiagnoses a missing one" $ do
      -- An unterminated final row backtracks the whole table and reports the
      -- error at its HEADER row, eight lines from the fault.
      let md = emitMarkdown (drgOf considerConstructors)
      Text.isSuffixOf "|\n" md `shouldBe` True
      Text.isSuffixOf "|\n\n" md `shouldBe` False

    it "writes (out) with no interior space, which the post-label parser requires" $
      emitMarkdown (drgOf considerConstructors) `shouldSatisfy` Text.isInfixOf "(out) :"

    it "omits a table whose column is an EXPRESSION, since a header is a variable name" $ do
      let drg = drgOf nonSFeelColumn
      emitMarkdown drg `shouldNotSatisfy` Text.isInfixOf "double"
      [n.code | n <- (markdownReport drg).notes] `shouldContain` ["D-MD-NONIDENTCOLUMN"]

    it "omits a decision with no table shape, and names it" $ do
      let drg = drgOf notATable
          notes = [n | n <- (markdownReport drg).notes, n.code == "D-MD-NOLITERAL"]
      map (.severity) notes `shouldBe` [Blocking]
      map (.message) notes `shouldSatisfy` all (Text.isInfixOf "no boxed-expression form")

    it "reports that the DRG itself has no markdown form" $ do
      let notes = [n | n <- (markdownReport (drgOf decisionChain)).notes, n.code == "D-MD-NODRG"]
      map (.severity) notes `shouldBe` [Blocking]

    it "reports the type collapse for a DATE column, which dmnmd has no type for" $ do
      -- an enum column does NOT collapse here: it was already a string on both
      -- sides, because FEEL has no sum types either. A date is a real loss --
      -- DMN has `date`, dmnmd has only String/Number/Boolean/List.
      let notes = [n | n <- (markdownReport (drgOf dateColumn)).notes, n.code == "D-MD-TYPE"]
      map (.severity) notes `shouldSatisfy` all (== Lossy)
      notes `shouldSatisfy` (not . null)

    it "is byte-identical across two independent lowerings" $
      emitMarkdown (drgOf considerConstructors) `shouldBe` emitMarkdown (drgOf considerConstructors)

    it "renders a number the same way the XML emitter does" $ do
      -- the DRY point: one renderNumber, so `9` cannot be `9.0` in one and `9`
      -- in the other
      let drg = drgOf overlappingThresholds
      emitMarkdown drg `shouldSatisfy` Text.isInfixOf "200000"
      emitDrg drg `shouldSatisfy` Text.isInfixOf "&gt;= 200000"

  describe "golden" $ forM_ goldenSubjects \(srcPath, stem, label) -> do
    it (label <> ", as DMN 1.3 XML") $
      goldenOf examplesRoot srcPath (stem <> ".dmn") emitDrg
    it (label <> "'s fidelity report") $
      goldenOf examplesRoot srcPath (stem <> ".fidelity.txt")
        (renderReport . dmnReport)
    it (label <> ", as dmnmd markdown") $
      goldenOf examplesRoot srcPath (stem <> ".dmn.md") emitMarkdown
    it (label <> "'s markdown fidelity report") $
      goldenOf examplesRoot srcPath (stem <> ".md.fidelity.txt")
        (renderReport . markdownReport)

------------------------------------------------------------------------
-- golden
------------------------------------------------------------------------

-- | @(source, golden stem, spec label)@.
--
-- There is deliberately no model-name column. The model's name comes from the
-- module's own outermost @§@ heading, else from the file's base name — the
-- same precedence @l4 export --to=dmn@ applies — so these goldens are what a
-- bare CLI invocation writes, with no flag and no string retyped here. It used
-- to be a hand-typed column, and the result was that the Reg CF corpus's model
-- had three names at once: @SEC Regulation Crowdfunding — 17 CFR Part 227@ in
-- the corpus, @Regulation Crowdfunding (17 CFR Part 227)@ in this table, and
-- @regcf@ from the CLI.
--
-- Two subjects, and the difference between them is the whole point:
--
-- * @dmn\/reg-cf.l4@ is the SHAPE exhibit — five decisions chosen so the
--   goldens show every outcome the exporter has, written module-level-scalar
--   (@ASSUME@) style because that is the program model DMN itself has. Its
--   figures are illustrative and its own header says so.
-- * @legal\/regcf\/regcf.l4@ is the REAL 981-line corpus, 73 decisions, written
--   in the house @GIVEN@ + record style. It is here to be honest about what
--   that costs: a DMN decision is a 0-ary variable, so every cross-decision
--   call @f x@ leaves the FEEL fragment, and every @GIVEN@ binder becomes a
--   global @inputData@ — nine of which are called @issuer@. The XML is
--   well-formed and a real engine will load it; almost none of it will
--   evaluate. That is a fact about the DMN program model, and it belongs in a
--   golden rather than in a paragraph nobody can regression-test.
goldenSubjects :: [(FilePath, FilePath, String)]
goldenSubjects =
  [ ( "dmn" </> "reg-cf.l4"
    , "reg-cf"
    , "the Reg CF shape exhibit"
    )
  , ( "legal" </> "regcf" </> "regcf.l4"
    , "regcf-corpus"
    , "the Reg CF corpus"
    )
  ]

-- | One golden: read the source, lower it the way the CLI would, render it
-- with @render@, and compare against @expected\/\<name\>@. Goldens all live
-- under @examples\/dmn\/expected@ even when the source does not, so
-- @etc\/validate-dmn.mjs@ with no arguments still finds every emitted model.
goldenOf :: FilePath -> FilePath -> FilePath -> (Drg -> Text) -> IO (Golden Text)
goldenOf examplesRoot srcPath name render = do
  src <- Text.readFile (examplesRoot </> srcPath)
  pure (mkGolden examplesRoot name (render (drgAsCli srcPath src)))

-- | Lower exactly as @l4 export --to=dmn FILE@ does with no @--model-name@:
-- the module's outermost @§@ heading if it has one, else the file's base name.
-- Keeping this in step with 'L4.Cli.Export.exportDmn' is what makes every DMN
-- golden reproducible from the command line.
drgAsCli :: FilePath -> Text -> Drg
drgAsCli srcPath src =
  drgWith (\m -> fromMaybe (Text.pack (takeBaseName srcPath)) (moduleTitle m)) src

mkGolden :: FilePath -> FilePath -> Text -> Golden Text
mkGolden examplesRoot name output =
  Golden
    { output
    , encodePretty = Text.unpack
    , writeToFile = Text.writeFile
    , readFromFile = Text.readFile
    , goldenFile = examplesRoot </> "dmn" </> "expected" </> name
    , actualFile = Just (examplesRoot </> "dmn" </> "expected" </> (name <> ".actual"))
    , failFirstTime = True
    }

isUniqueTable :: DecisionLogic -> Bool
isUniqueTable = \case
  LogicTable t  -> t.dtHitPolicy == HitUnique
  LogicLiteral _ -> False

------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------

drgOf :: Text -> Drg
drgOf = drgNamed "Test"

-- | Lower a source, INSISTING that L4 accepted it first.
--
-- @checkWithImports@ returns 'Left' only for a parse or import-resolution
-- failure; a module that parses but does not typecheck comes back 'Right' with
-- the diagnostics in @tcdErrors@ and @tcdSuccess = False@. Reading only the
-- 'Left' meant a source could be asserted on while L4 was rejecting it — and
-- one was: the DATE select in this file used to be written without
-- @IMPORT daydate@, which makes @start AT MOST end@ an ambiguous overload
-- ("multiple definitions for the identifier @__LEQ__@"), so the test that
-- claimed to pin DATE behaviour was pinning the exporter's treatment of a failed
-- overload resolution. Warnings and infos are left alone; only errors are fatal.
drgNamed :: Text -> Text -> Drg
drgNamed name = drgWith (const name)

-- | As 'drgNamed', with the model name computed from the checked module.
drgWith :: (Module Resolved -> Text) -> Text -> Drg
drgWith mkName src = case checkWithImports emptyVFS src of
  Left errs -> error ("source failed to parse: " <> show errs)
  Right tc
    | errs@(_ : _) <- filter ((== SError) . TC.severity) tc.tcdErrors ->
        error
          ( "source failed to typecheck: "
              <> Text.unpack (Text.unlines (concatMap TC.prettyCheckErrorWithContext errs))
          )
    | otherwise ->
        lowerModule
          MkDmnLowerOptions
            { dloModelName = mkName tc.tcdModule
            , dloSubstitution = tc.tcdSubstitution
            }
          tc.tcdModule

decisionNamed :: Text -> Drg -> Decision
decisionNamed nm drg = case [d | d <- drgDecisions drg, d.dcnName == nm] of
  (d : _) -> d
  []      -> error ("no decision named " <> show nm)

tableOf :: Text -> Text -> DecisionTable
tableOf nm src = case (decisionNamed nm (drgOf src)).dcnLogic of
  LogicTable t   -> t
  LogicLiteral e -> error ("expected a decision table for " <> show nm <> ", got: " <> show e.feText)

-- | The decision must stay a table: the select-idiom peephole must not fire.
mustNotBeSelect :: Text -> Text -> Expectation
mustNotBeSelect nm src = do
  let drg = drgOf src
  case (decisionNamed nm drg).dcnLogic of
    LogicTable _   -> pure ()
    LogicLiteral e -> expectationFailure ("select idiom fired on " <> show nm <> ": " <> show e.feText)
  emitDrg drg `shouldSatisfy` (\x -> not (Text.isInfixOf "max(" x) && not (Text.isInfixOf "min(" x))

cellTexts :: DmnRule -> [Text]
cellTexts r = map renderUnaryTest r.drInputs
