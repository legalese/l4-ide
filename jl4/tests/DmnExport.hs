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
-- __'drgAsCli' is exported__, and only to 'BpmnExport'. The BPMN goldens have
-- to be lowered against the SAME decision graph the DMN goldens are, or the
-- @businessRuleTask@ ids in one set of goldens would be checked against ids
-- from a differently-configured lowering in the other. Sharing the helper is
-- what makes that impossible; re-spelling it there is what would make it
-- inevitable.
module DmnExport (spec, drgAsCli) where

import Base
import qualified Base.Text as Text

import L4.API.VirtualFS (TypeCheckWithDepsResult (..), VFS, checkWithImports, emptyVFS)
import qualified Base.Set as Set
import L4.Annotation (rangeOf)
import L4.Dmn.Emit (emitDrg, escapeXmlAttr, escapeXmlText)
import L4.Dmn.IR
import L4.Dmn.Lower (DmnLowerOptions (..), lowerModule, moduleTitle, resolveMaybePredicates)
import L4.Dmn.Markdown (emitMarkdown, markdownReport)
import L4.EvaluateLazy.Exceptions (UserEvalException (..))
import L4.Interchange.Fidelity
import L4.Syntax (Module, Resolved)
import qualified L4.TypeCheck as TC
import L4.TypeCheck.Types (Severity (..))

import Data.Time.Calendar (fromGregorian)
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

-- | Names of the kind an L4 drafter actually writes, and that FEEL cannot carry
-- verbatim: a space, a hyphen, and both at once. Every engine-facing naming
-- assertion in this file runs over this fixture.
spacedNames :: Text
spacedNames =
  "ASSUME `annual income` IS A NUMBER\n\
  \ASSUME `first-time issuer` IS A BOOLEAN\n\
  \GIVETH A NUMBER\n\
  \`investor limit` MEANS\n\
  \  BRANCH\n\
  \    IF `first-time issuer` THEN 0\n\
  \    IF `annual income` AT LEAST 1000 THEN 1\n\
  \    OTHERWISE 2\n"

-- | Two free terms whose FEEL names collide once the hyphen and the space both
-- become @_@. This is the one collision class the pre-existing @D-SCOPE@ note
-- already covered.
collidingInputs :: Text
collidingInputs =
  "ASSUME `first-time issuer` IS A NUMBER\n\
  \ASSUME `first time issuer` IS A NUMBER\n\
  \GIVETH A NUMBER\n\
  \total MEANS `first-time issuer` PLUS `first time issuer`\n"

-- | An @inputData@ and a @decision@ that collide. Nothing reported this before.
collidingInputAndDecision :: Text
collidingInputAndDecision =
  "ASSUME `net worth` IS A NUMBER\n\
  \ASSUME base IS A NUMBER\n\
  \GIVETH A NUMBER\n\
  \net_worth MEANS base PLUS 1\n\
  \GIVETH A NUMBER\n\
  \total MEANS `net worth` PLUS net_worth\n"

-- | Two decisions that collide. Likewise previously silent.
collidingDecisions :: Text
collidingDecisions =
  "ASSUME base IS A NUMBER\n\
  \GIVETH A NUMBER\n\
  \`net worth` MEANS base PLUS 1\n\
  \GIVETH A NUMBER\n\
  \net_worth MEANS base PLUS 2\n\
  \GIVETH A NUMBER\n\
  \total MEANS `net worth` PLUS net_worth\n"

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
  -- `other` applies `double` to a SECOND, distinct argument, keeping it
  -- tier 2 (Phase 4), and @nonexhaustive keeps it SAFETY-REFUSED (Phase 5):
  -- a clean tier-2 `double` would now emit as a BKM and the call would render
  -- as a FEEL invocation, which is precisely not this test's subject —
  -- verbatim L4 in a <text> position. The refused-tier-2 residue is the
  -- population that still exercises it (§6.2's stated boundary).
  "@nonexhaustive\n\
  \GIVEN n IS A NUMBER\n\
  \GIVETH A NUMBER\n\
  \double n MEANS n TIMES 2\n\
  \\n\
  \GIVETH A NUMBER\n\
  \other MEANS double 99\n\
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
  -- `other` keeps `double` tier 2, @nonexhaustive keeps it refused (Phase 5);
  -- see 'nonSFeelColumn'.
  "@nonexhaustive\n\
  \GIVEN n IS A NUMBER\n\
  \GIVETH A NUMBER\n\
  \double n MEANS n TIMES 2\n\
  \\n\
  \GIVETH A NUMBER\n\
  \other MEANS double 99\n\
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
  -- `other` keeps `double` tier 2, @nonexhaustive keeps it refused (Phase 5);
  -- see 'nonSFeelColumn'.
  "@nonexhaustive\n\
  \GIVEN n IS A NUMBER\n\
  \GIVETH A NUMBER\n\
  \double n MEANS n TIMES 2\n\
  \\n\
  \GIVETH A NUMBER\n\
  \other MEANS double 99\n\
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
  -- `other` keeps `double` tier 2, @nonexhaustive keeps it refused (Phase 5);
  -- see 'nonSFeelColumn'.
  "@nonexhaustive\n\
  \GIVEN n IS A NUMBER\n\
  \GIVETH A NUMBER\n\
  \double n MEANS n TIMES 2\n\
  \\n\
  \GIVETH A NUMBER\n\
  \other MEANS double 99\n\
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
      -- An enum has no FEEL type of its own, so it becomes a NAMED type over
      -- `string` -- the itemDefinition's base -- and the column carries the
      -- domain that used to be nowhere (§3.1, §4.2).
      map (.icType) t.dtInputs `shouldBe` [DmnNamed "Colour" DmnString]
      map (.icValues) t.dtInputs `shouldBe` [Just ["red", "green", "blue"]]

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
      t.dtOutput.ocType `shouldBe` DmnNamed "Colour" DmnString
      -- ...and an ENUM-typed output is the one case §3.2 says the domain is
      -- knowable, so it ships as <outputValues>. A boolean output does not:
      -- there the domain IS the typeRef.
      t.dtOutput.ocValues `shouldBe` Just ["red", "green", "blue"]
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
      map (.icExpr.feText) t.dtInputs `shouldBe` ["offering_amount", "first_time"]
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

        LogicContext _ -> expectationFailure "unexpected boxed context"
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
        LogicContext _ -> expectationFailure "unexpected boxed context"
      d.dcnType `shouldBe` DmnString

    it "fires over DATE, which Table 54 orders too (daydate's `the earlier of`)" $ do
      let d = decisionNamed "the earlier of" (drgOf minIdiomDate)
      case d.dcnLogic of
        LogicLiteral e -> e.feText `shouldBe` "min(start, end)"
        LogicTable _   -> expectationFailure "expected min(start, end), got a decision table"
        LogicContext _ -> expectationFailure "unexpected boxed context"
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
        LogicContext _ -> expectationFailure "unexpected boxed context"
      -- Advisory since the Phase 5 severity re-key (recorded in spec §7):
      -- `a and b` is genuine FEEL an engine evaluates, so what the boxed
      -- literal forfeits is the table analyses, which is Advisory's
      -- definition. The Blocking arm is pinned separately on a body that
      -- stays raw L4 ("fidelity: L4 source in a <text> element is Blocking").
      [(n.code, n.severity) | n <- drg.drgNotes] `shouldBe` [("D-LITERALEXPR", Advisory)]
      emitDrg drg `shouldSatisfy` Text.isInfixOf "<literalExpression"

    -- __Both of these shapes are now refused EARLIER, and by a different code.__
    -- Their `WHEN other description` arm binds the payload of a
    -- payload-carrying `IS ONE OF`, which is R4-a's third reading form, and
    -- §4.2.1-8 requires `D-SUMTYPE` to be decided BEFORE `normaliseGuarded` so
    -- that a FEEL type-system limit is not reported as a table-shape problem.
    -- What used to be reported here -- `RowsElided`, "a DMN table would answer
    -- null where the rule answers FALSE" -- was the correct diagnosis of the
    -- second-nearest cause.
    --
    -- Two consequences worth stating plainly rather than leaving in a diff.
    -- (i) `RowsElided` is now UNREACHABLE for a multi-constructor payload
    -- union, which is the only shape that could produce it: `considerRows`
    -- elides an arm only when the arm binds AND still contributes a
    -- disjointness key, and a `PatVar` catch-all supplies no key (measured: it
    -- gives "is not a guarded chain" instead). (ii) `elidedArmWithOtherwise`
    -- used to emit a table that was CORRECT -- one rule for `education`, the
    -- rest to the default -- and R4-a refuses it anyway. That is the ruling as
    -- written, and it is the one place the corpus-derived claim "R4-a refuses
    -- only what is already refused" does not extend to a synthetic shape.
    it "a payload-binding CONSIDER arm is refused as D-SUMTYPE, not misdiagnosed" $ do
      let drg = drgOf elidedArmNoOtherwise
      case (decisionNamed "charitable" drg).dcnLogic of
        LogicLiteral _ -> pure ()
        LogicTable _   -> expectationFailure "emitted a table that answers null where the rule answers FALSE"
        LogicContext _ -> expectationFailure "unexpected boxed context"
      [(n.code, n.severity) | n <- drg.drgNotes] `shouldBe` [("D-SUMTYPE", Blocking)]
      [n.message | n <- drg.drgNotes]
        `shouldSatisfy` all (Text.isInfixOf "binds `other`'s payload")
      -- and NOT the shape diagnosis it used to get
      [n.message | n <- drg.drgNotes] `shouldSatisfy` all (not . Text.isInfixOf "answer null")

    it "...and adding an OTHERWISE does not rescue it, because the arm still binds" $ do
      let drg = drgOf elidedArmWithOtherwise
      case (decisionNamed "charitable" drg).dcnLogic of
        LogicLiteral _ -> pure ()
        LogicTable _   -> expectationFailure "expected a boxed literal expression (R4-a form 3)"
        LogicContext _ -> expectationFailure "unexpected boxed context"
      [(n.code, n.severity) | n <- drg.drgNotes] `shouldBe` [("D-SUMTYPE", Blocking)]

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
        LogicContext _ -> expectationFailure "unexpected boxed context"
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

    -- The RECORD-CONSTRUCTION subset of AppNamed lowers to a context literal
    -- (Phase 5 build; the arm's own comment in Lower.hs answers the four
    -- reasons the unrestricted lowering was once written and reverted). The
    -- restrictions the two tests after it pin: a construction missing a
    -- stored field stays verbatim, and a FUNCTION applied WITH named
    -- arguments stays verbatim — an enum's payload constructor stays under
    -- D-SUMTYPE (the sumtype block).
    it "RECORD construction lowers to a FEEL context literal in declaration order" $ do
      let t = tableOf "assess" recordConstruction
      map (.drOutput.feFragment) t.dtRules `shouldBe` [FullFeel]
      map (.drOutput.feText) t.dtRules
        `shouldBe` ["{rate: 40, band: \"high\"}"]
      -- no D-NONFEELOUTPUT: the entry is FEEL now. The keys come from the
      -- same field scope the itemDefinition components use, so the write side
      -- and `r.f` cannot disagree.
      map (.code) t.dtNotes `shouldNotContain` ["D-NONFEELOUTPUT"]

    -- No missing-field test, and the absence is a measurement: L4's
    -- typechecker REJECTS a construction that omits a stored field ("you
    -- forgot to supply the following arguments", measured 2026-08-01), so the
    -- arm's completeness guard is unreachable through checked source and
    -- stands as defence-in-depth only.
    it "a FUNCTION applied WITH named arguments stays verbatim, BKM callee or not" $ do
      -- Reason 1 of the reverted lowering, still standing: AppNamed is L4's
      -- general named-argument application, and `f WITH x IS 3, y IS 4` over
      -- `f MEANS x TIMES y` is 12 in L4 and a context under the naive
      -- lowering. ALSO the recorded §6.1 deferral: a named-argument call to
      -- an emitted BKM stays verbatim + Blocking in v1 (the argument names
      -- would need checking against the BKM's parameters).
      let drg = drgOf
            "GIVEN\n\
            \  x IS A NUMBER\n\
            \  y IS A NUMBER\n\
            \GIVETH A NUMBER\n\
            \f x y MEANS x TIMES y\n\
            \GIVETH A NUMBER\n\
            \use MEANS f WITH x IS 3, y IS 4\n\
            \GIVETH A NUMBER\n\
            \use2 MEANS f WITH x IS 5, y IS 6\n"
      -- two distinct argument shapes: `f` IS an emitted BKM...
      map (.bkmName) (drgBkms drg) `shouldBe` ["f"]
      -- ...and the AppNamed call sites still refuse
      (decisionNamed "use" drg).dcnLogic `shouldSatisfy` \case
        LogicLiteral fe -> fe.feFragment == L4Verbatim
        _               -> False

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
      -- The count is computed, not spelled. It read "two" unconditionally
      -- until 2026-07-27, which understated the Reg CF corpus's eight-way
      -- collision on `issuer` as a two-way one.
      map (.message) shared `shouldSatisfy` all (Text.isInfixOf "two different terms")
      -- After §5.2 stage 2 the message may NOT say the elements cannot be told
      -- apart -- they are renamed apart, and every reference reaches the one it
      -- means. What survives is the scope loss, and the note names both the L4
      -- spelling and the FEEL names the reader will see (§5.3.6).
      map (.message) shared `shouldSatisfy` all (Text.isInfixOf "fold to the FEEL name `n`")
      map (.message) shared `shouldSatisfy` all (Text.isInfixOf "`n`, `n_2`")
      map (.message) shared `shouldNotSatisfy` any (Text.isInfixOf "cannot tell apart")

    it "element ids derive from L4 names, so they survive a rebuild" $ do
      let drg = drgOf decisionChain
      map (.dcnId) (drgDecisions drg) `shouldBe` ["decision_is_holiday", "decision_fee"]

    it "a NAMED-ARGUMENT call keeps its edge, because the emitted text names it" $ do
      -- R11 runs both ways. 'survivingRefs' may drop an edge only where the
      -- FOLD removed the name from the emitted text, and an @AppNamed@ is not
      -- folded -- it renders VERBATIM, so the text names `sum of` in full. An
      -- earlier 'survivingRefs' collected references from @App@ heads only,
      -- which silently dropped this edge while the expression still spelled it
      -- out: a DRG describing a different model from its own decisions.
      let drg = drgOf $ Text.unlines
            [ "GIVEN x IS A NUMBER"
            , "      y IS A NUMBER"
            , "GIVETH A NUMBER"
            , "`sum of` x y MEANS x PLUS y"
            , ""
            , "GIVETH A NUMBER"
            , "`the base` MEANS 42"
            , ""
            , "GIVETH A NUMBER"
            , "`total` MEANS `sum of` WITH x IS `the base`"
            , "                            y IS 7"
            ]
          total = decisionNamed "total" drg
      sort (map requirementTarget total.dcnRequirements)
        `shouldSatisfy` elem "decision_sum_of"
      -- `input_x`/`input_y` are also required, because an @AppNamed@'s argument
      -- LABELS resolve to the callee's GIVEN binders and those binders are this
      -- exporter's inputData. That is pre-existing and unchanged -- it is what
      -- the total `toList` collection has always done -- and it is recorded
      -- here rather than asserted away, so a later reader does not read the
      -- edge as something hydration introduced.
      sort (map requirementTarget total.dcnRequirements)
        `shouldBe` ["decision_sum_of", "decision_the_base", "input_x", "input_y"]

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

  -- Every assertion here corresponds to a measured engine failure, not to a
  -- reading of the DMN specification. See
  -- specs/todo/DMN-EXPORT-PROGRAM-MODEL-SPEC.md §13.2, and etc/kie-dmn-check +
  -- etc/camunda-dmn-check, which run the real engines over the golden. Where a
  -- comment below states a DMN clause as well, the clause is marked as a
  -- reading; the engine sentence beside it is the measurement.
  describe "FEEL names an engine can actually resolve" $ do
    it "maps a space and a hyphen to _, and never leaves either in a FEEL name" $ do
      feelIdentText "annual income" `shouldBe` "annual_income"
      feelIdentText "first-time issuer" `shouldBe` "first_time_issuer"
      -- A dot used to pass through, which silently injects a FEEL PATH
      -- expression and shadows a genuine record projection.
      feelIdentText "a.b" `shouldBe` "a_b"
      -- Runs collapse and the ends are trimmed, so the result is never `__`.
      feelIdentText "  a  --  b  " `shouldBe` "a_b"
      feelIdentText "" `shouldBe` "_"
      feelIdentText "---" `shouldBe` "_"
      feelIdentText "2nd tranche" `shouldBe` "_2nd_tranche"

    it "suffixes a folded name that IS a FEEL reserved word (§5.2 stage 1 step 6)" $ do
      feelIdentText "in" `shouldBe` "in_"
      feelIdentText "date" `shouldBe` "date_"
      -- The test is against the WHOLE folded name, never a part: §10.3.1.4
      -- forbids a keyword name START and explicitly permits a keyword name
      -- part, and after folding `annual income` is one name, not two.
      feelIdentText "annual income" `shouldBe` "annual_income"
      feelIdentText "in come" `shouldBe` "in_come"
      -- CASE-SENSITIVE, and this pins the choice rather than inheriting it:
      -- FEEL's literal terminal symbols are lower case, so `IF` is not one of
      -- them and renaming it would rename a name no engine objects to.
      feelIdentText "IF" `shouldBe` "IF"
      -- The suffix is applied LAST, after the leading-digit repair, and is not
      -- re-collapsed.
      feelIdentText "not" `shouldBe` "not_"
      feelIdentText "not!" `shouldBe` "not_"

    it "gives type names their own function, with the same map and the same dot policy" $ do
      -- §5.1-2 and §5.3.6. A `.` in a typeRef QName is DMN's IMPORT PREFIX
      -- separator and this exporter emits no imports, so a dot passed through
      -- would name an import that does not exist.
      feelTypeNameText "Investor Class" `shouldBe` "Investor_Class"
      feelTypeNameText "a.b" `shouldBe` "a_b"
      feelTypeNameText "list" `shouldBe` "list_"

    it "suffixes a type name that collides with a FEEL BUILT-IN type spelling" $ do
      -- The two namespaces diverge here, and only here. FEEL's built-in type
      -- names are not keywords -- a VARIABLE called `number` is fine -- but a
      -- typeRef is resolved against them, so an itemDefinition called `number`
      -- does not shadow the numeric type, it ALIASES onto it: a string enum and
      -- every genuine NUMBER-typed element would share one typeRef, with
      -- nothing in the artifact to say they differ, and therefore nothing a
      -- fidelity note could key off. Renaming is the only repair that leaves
      -- the artifact readable.
      feelTypeNameText "number" `shouldBe` "number_"
      feelTypeNameText "string" `shouldBe` "string_"
      feelTypeNameText "boolean" `shouldBe` "boolean_"
      feelTypeNameText "Any" `shouldBe` "Any_"
      feelTypeNameText "dateTime" `shouldBe` "dateTime_"
      feelTypeNameText "days and time duration" `shouldBe` "days_and_time_duration"
      feelTypeNameText "daysAndTimeDuration" `shouldBe` "daysAndTimeDuration_"
      feelTypeNameText "yearsAndMonthsDuration" `shouldBe` "yearsAndMonthsDuration_"
      -- Case-sensitive, as in the variable namespace: `Any` is DMN's spelling,
      -- `any` is not, and renaming the latter would rename a name no engine
      -- objects to.
      feelTypeNameText "any" `shouldBe` "any"
      -- ...and the VARIABLE namespace is unmoved: a decision or inputData named
      -- `number` needs no suffix, because nothing resolves a variable name
      -- against the type names.
      feelIdentText "number" `shouldBe` "number"
      feelIdentText "Any" `shouldBe` "Any"
      -- ...but the type set is a SUPERSET, so nothing reserved for a variable
      -- silently became legal for a type when the two functions diverged.
      [w | w <- toList reservedFeelWords, w `notElem` toList reservedFeelTypeNames]
        `shouldBe` []

    it "uniquifyIn takes the least FREE suffix, over a stable source order" $ do
      -- §5.2 stage 2. First claimant keeps the base; the nth gets base_<n>.
      uniquifyIn ["a", "a", "b", "a"] `shouldBe` ["a", "a_2", "b", "a_3"]
      -- "least free" rather than "least unused count": a source name that
      -- already spells the suffix must not be handed out twice.
      uniquifyIn ["a", "a_2", "a"] `shouldBe` ["a", "a_2", "a_3"]
      uniquifyIn [] `shouldBe` []

    it "gives a node and its variable the SAME @name (the engines read different ones)" $ do
      -- KIE resolves an inputData by the NODE's @name; Camunda by the
      -- <variable>'s. The emitter used to mangle only the latter, so the same
      -- file was rejected by both, for opposite reasons: KIE fired
      -- VARIABLE_NAME_MISMATCH and then failed to build, Camunda 8 rejected the
      -- whole DRG at parse().
      let xml = emitDrg (drgOf spacedNames)
      xml `shouldSatisfy` Text.isInfixOf
        "<inputData id=\"input_first_time_issuer\" name=\"first_time_issuer\" \
        \label=\"first-time issuer\">"
      xml `shouldSatisfy` Text.isInfixOf
        "<variable id=\"input_first_time_issuer_var\" name=\"first_time_issuer\" \
        \label=\"first-time issuer\" typeRef=\"boolean\"/>"

    it "puts the verbatim L4 name in @label, so mangling costs nothing to read" $ do
      let xml = emitDrg (drgOf spacedNames)
      xml `shouldSatisfy` Text.isInfixOf "label=\"annual income\""
      xml `shouldSatisfy` Text.isInfixOf "label=\"investor limit\""

    it "omits @label when the FEEL name is the L4 name" $
      -- `class`, `score`, `fee`: no mangling happened, so there is nothing to
      -- record, and a label repeating the name would be noise in every diff.
      emitDrg (drgOf considerConstructors) `shouldNotSatisfy` Text.isInfixOf "label=\"score\""

    it "leaves no space in any emitted FEEL text" $ do
      -- The Camunda failure mode is silent, not loud: `annual income` is
      -- tokenised as `annual` `in` `come` -- the membership operator -- and
      -- answers a BOOLEAN. Measured: in a model declaring `annual income` =
      -- 100000, `annual` = 5 and `come` = [1,2,5], Camunda 8.7.6 answers `true`
      -- to both `annual income` and `annual in come`, where KIE answers 100000
      -- and `true` respectively. A name-shaped FEEL text with a space in it is
      -- therefore a wrong NON-NULL answer waiting to happen.
      let xml = emitDrg (drgOf spacedNames)
      xml `shouldNotSatisfy` Text.isInfixOf "annual income<"
      xml `shouldNotSatisfy` Text.isInfixOf "first-time issuer<"
      xml `shouldSatisfy` Text.isInfixOf "<text>annual_income</text>"

    it "gives a single-output table's <output> no @name and no @typeRef" $ do
      -- READING, DMN 8.2.11: an output clause is named only so a MULTI-output
      -- result can be keyed. MEASUREMENT: KIE fires ILLEGAL_USE_OF_NAME and
      -- ILLEGAL_USE_OF_TYPEREF otherwise -- six warnings on the Reg CF exhibit
      -- alone -- and dropping both leaves Camunda 8's answers unchanged.
      let xml = emitDrg (drgOf spacedNames)
      xml `shouldSatisfy` Text.isInfixOf "<output id=\"decision_investor_limit_o1\"/>"
      xml `shouldNotSatisfy` Text.isInfixOf "<output id=\"decision_investor_limit_o1\" name="
      -- ...but the IR still carries both, because dmnmd's header needs them and
      -- a multi-output table will.
      (tableOf "investor limit" spacedNames).dtOutput.ocName `shouldBe` "investor_limit"

    -- §5.2 stage 2 landed, so a collision is now RESOLVED rather than merely
    -- detected: `uniquifyIn` suffixes every claimant after the first, in both
    -- the declaration and every reference to it, and D-RENAME reports the
    -- rename at Lossy. D-FEELNAME keeps its code and its predicate -- §7's
    -- header forbids deleting the tree's only detector of a duplicate
    -- `inputData/@name` until something else reports it -- and therefore now
    -- fires ZERO times. That zero is pinned below, so the day it fires again is
    -- visible rather than inferred.
    describe "two elements, one FEEL name (uniquifyIn, D-RENAME)" $ do
      let feelNameNotes src =
            [n | n <- (dmnReport (drgOf src)).notes, n.code == "D-FEELNAME"]
          renameNotes src =
            [n | n <- (dmnReport (drgOf src)).notes, n.code == "D-RENAME"]

      it "renames inputData x inputData apart, in the declaration AND the references" $ do
        -- Before stage 2, Camunda 8 loaded this file and read one supplied
        -- value twice while KIE rejected it with DUPLICATE_NAME. Now there are
        -- two distinct FEEL names and the sum reads both.
        let drg = drgOf collidingInputs
        map (.idFeelName) (drgInputData drg)
          `shouldBe` ["first_time_issuer", "first_time_issuer_2"]
        emitDrg drg `shouldSatisfy`
          Text.isInfixOf "first_time_issuer + first_time_issuer_2"
        feelNameNotes collidingInputs `shouldBe` []
        let notes = renameNotes collidingInputs
        map (.severity) notes `shouldBe` [Lossy]
        map (.message) notes `shouldSatisfy` all (Text.isInfixOf "`first_time_issuer_2`")
        map (.message) notes `shouldSatisfy` all (Text.isInfixOf "`first time issuer`")

      it "renames inputData x decision apart -- one flat namespace, both kinds" $ do
        -- Measured before the fix: L4 says 7 + 101; Camunda 8 answered 202,
        -- because the reference to the INPUT resolved to the DECISION.
        let drg = drgOf collidingInputAndDecision
        -- free terms in first-use order: `base` is read by the decision that
        -- collides, so it is collected first.
        map (.idFeelName) (drgInputData drg) `shouldBe` ["base", "net_worth"]
        map (.dcnFeelName) (drgDecisions drg) `shouldBe` ["net_worth_2", "total"]
        feelNameNotes collidingInputAndDecision `shouldBe` []
        map (.severity) (renameNotes collidingInputAndDecision) `shouldBe` [Lossy]

      it "renames decision x decision apart" $ do
        let drg = drgOf collidingDecisions
        map (.dcnFeelName) (drgDecisions drg)
          `shouldBe` ["net_worth", "net_worth_2", "total"]
        emitDrg drg `shouldSatisfy` Text.isInfixOf "net_worth + net_worth_2"
        feelNameNotes collidingDecisions `shouldBe` []
        map (.severity) (renameNotes collidingDecisions) `shouldBe` [Lossy]

      it "says nothing when the names are distinct after mangling" $ do
        feelNameNotes spacedNames `shouldBe` []
        feelNameNotes considerConstructors `shouldBe` []
        renameNotes spacedNames `shouldBe` []
        renameNotes considerConstructors `shouldBe` []

    -- §5.3.4's witness, and the reason stage 2's scope list covers projection
    -- paths and not only the DRG: this is the ONE executed corpus collision,
    -- and before stage 2 it emitted `p.foo_bar + p.foo_bar` -- valid FEEL,
    -- computing a wrong number, with no note of any kind. The file's own
    -- comment says the bridge must reject it; the OpenFisca backend does, and
    -- this exporter now renames it apart and says so.
    it "renames two fields of one record apart, and reports it (§5.3.4)" $ do
      src <- Text.readFile (examplesRoot </> "openfisca" </> "not-ok" </> "name-collision.l4")
      let drg = drgNamed "name-collision" src
          xml = emitDrg drg
          notes = dmnReport drg
      xml `shouldSatisfy` Text.isInfixOf "p.foo_bar + p.foo_bar_2"
      xml `shouldNotSatisfy` Text.isInfixOf "p.foo_bar + p.foo_bar<"
      [n.severity | n <- notes.notes, n.code == "D-RENAME"] `shouldBe` [Lossy]
      [n.code | n <- notes.notes] `shouldNotContain` ["D-FEELNAME"]

  -- Phase 3 (§4): the TYPE-level half of the export. What each assertion pins
  -- is either a normative XSD/spec requirement or a ruling with a measurement
  -- behind it, never a preference.
  describe "the data model: itemDefinitions, domains, and the sums FEEL has not got" $ do
    it "puts every itemDefinition BEFORE every drgElement (§4.3)" $ do
      -- tDefinitions is an xsd:sequence, so this is normative, not cosmetic --
      -- and the obvious validator does NOT catch it: libxml2 and dmn-moddle
      -- both accept the misordering that Xerces rejects with
      -- cvc-complex-type.2.4.a.
      --
      -- This assertion is over the EMITTER. That the schema gate itself can go
      -- red is a separate claim, and it needs a file the emitter cannot
      -- produce: see the matched pair in jl4/tests-cli/fixtures/dmn-xsd-order/
      -- and the "XSD sequence-order gate" describe in jl4/tests-cli/Main.hs.
      -- Measured there: Camunda 8.7.6 rejects the misordered file at parse,
      -- while Drools/KIE 8.44 builds and evaluates it correctly and only its
      -- schema legs object.
      let xml = emitDrg (drgOf considerConstructors)
      Text.breakOn "<itemDefinition" xml `shouldSatisfy` (not . Text.null . snd)
      Text.length (fst (Text.breakOn "<itemDefinition" xml))
        `shouldSatisfy` (< Text.length (fst (Text.breakOn "<inputData" xml)))

    it "mints NO itemDefinition for a scalar (§4.3)" $ do
      -- An alias over `number` adds no information and degrades for any
      -- consumer that does not resolve typeRefs.
      let drg = drgOf overlappingThresholds
      drg.drgItemDefs `shouldBe` []
      emitDrg drg `shouldNotSatisfy` Text.isInfixOf "<itemDefinition"

    it "gives an IS ONE OF a string base and its COMPLETE domain, in declaration order" $ do
      -- §7.3.3: allowedValues "specifies the complete range of values that this
      -- ItemDefinition represents". Order is the L4's, because that is the only
      -- ordering the source ever states (and §3.2 makes it the priority order
      -- for the hit policies a later phase may use).
      let drg = drgOf considerConstructors
      map (.idfName) drg.drgItemDefs `shouldBe` ["Colour"]
      map (.idfBase) drg.drgItemDefs `shouldBe` [Just DmnString]
      map (.idfValues) drg.drgItemDefs `shouldBe` [Just ["red", "green", "blue"]]
      map (.idfComponents) drg.drgItemDefs `shouldBe` [[]]
      emitDrg drg `shouldSatisfy`
        Text.isInfixOf "<text>\"red\",\"green\",\"blue\"</text>"

    it "spells a constructor with nameOf, NOT the FEEL fold (§5.3.6)" $ do
      -- A constructor name becomes a FEEL string LITERAL -- the tag value --
      -- never an identifier, so the name fold must not touch it. This is also
      -- what keeps the domain and the cells identical strings.
      let drg = drgOf considerConstructors
          t   = tableOf "score" considerConstructors
      map (.idfValues) drg.drgItemDefs `shouldBe` [Just ["red", "green", "blue"]]
      map (.drInputs) t.dtRules
        `shouldBe` [[TestEq (VStr "red")], [TestEq (VStr "green")]]

    describe "sumtype.l4, the data-model exhibit" $ do
      let sumtypeDrg = do
            src <- Text.readFile (examplesRoot </> "dmn" </> "sumtype.l4")
            pure (drgAsCli "sumtype.l4" src)

      it "maps a record to an itemDefinition with one component per STORED field" $ do
        drg <- sumtypeDrg
        let claim = itemDefNamed "Claim" drg
        claim.idfBase `shouldBe` Nothing
        claim.idfValues `shouldBe` Nothing
        -- `doubled amount` is absent because L4.Desugar turned it into a
        -- top-level DECIDE before type checking, not because we dropped it.
        map (.icmLabel) claim.idfComponents
          `shouldBe` [ "amount", "assessed grade", "supporting notes", "the disposal" ]
        -- nesting -> nesting: a component whose type is another declared type
        -- points at that itemDefinition by name.
        [c.icmType | c <- claim.idfComponents, c.icmLabel == "the disposal"]
          `shouldBe` [DmnNamed "Disposal" DmnString]

      it "gives a component the SAME name a projection path uses (§5.2 scope 2)" $ do
        drg <- sumtypeDrg
        let claim = itemDefNamed "Claim" drg
        map (.icmName) claim.idfComponents
          `shouldSatisfy` elem "supporting_notes"
        emitDrg drg `shouldSatisfy` Text.isInfixOf "c.amount"

      it "points a MAYBE over a DOMAIN-carrying type at a domain-free alias (R8-a, R8-b)" $ do
        drg <- sumtypeDrg
        let xml   = emitDrg drg
            notes = [n | n <- drgNotesAll drg, n.code == "D-MAYBE-NULL"]
            qNotes = [n.message | n <- notes, Text.isInfixOf "`q`" n.message]
        map (.severity) notes `shouldSatisfy` all (== Lossy)
        notes `shouldSatisfy` (not . null)
        -- R8-b suppresses the domain AT the element, because `null` is not a
        -- legal S-FEEL endpoint and a list that omitted it would not be the
        -- COMPLETE range §7.3.3 requires. But §7.3.3 reads the range off
        -- whatever the typeRef RESOLVES to, so R8-a's plain lowering --
        -- typeRef="Grade" -- re-asserted that range one hop on, and nothing
        -- this exporter emits lowers to null. An enforcing engine would then
        -- reject the absent case that is the whole content of the MAYBE: an
        -- ANSWER CHANGE, not a reporting gap, which is why the repair is in
        -- the artifact. `q` points at the alias.
        xml `shouldSatisfy` Text.isInfixOf "name=\"q\" typeRef=\"Grade_optional\""
        xml `shouldNotSatisfy` Text.isInfixOf "name=\"q\" typeRef=\"Grade\""
        -- The alias is a `string` with NO allowedValues, and it does not spell
        -- nullability -- tItemDefinition cannot -- it only keeps R8-b's
        -- suppression from being undone by the hop.
        xml `shouldSatisfy` Text.isInfixOf
          "<itemDefinition id=\"itemdef_grade_optional\" name=\"Grade_optional\" label=\"Grade\">\n\
          \    <typeRef>string</typeRef>\n\
          \  </itemDefinition>"
        -- Minted at most ONCE per module, however many sites point at it:
        -- `Claim`'s `assessed grade` is the second.
        length (Text.breakOnAll "name=\"Grade_optional\"" xml) `shouldBe` 1
        xml `shouldSatisfy` Text.isInfixOf
          "name=\"assessed_grade\" label=\"assessed grade\">\n      <typeRef>Grade_optional</typeRef>"
        -- ...and gated on being pointed at: `Disposal` has a domain too and is
        -- never reached through a MAYBE, so it gets no alias.
        xml `shouldNotSatisfy` Text.isInfixOf "Disposal_optional"
        -- The note names the alias and the type it drops the range of, and
        -- reports what the alias COSTS: at this element an engine no longer
        -- validates the values that ARE present.
        qNotes `shouldSatisfy` all (Text.isInfixOf "`Grade_optional`, a domain-free alias of `Grade`")
        -- The note went wrong twice before, in opposite directions, and this
        -- pins the second one -- the live hazard. It said the suppression "does
        -- not reach through the typeRef", i.e. that a consumer resolving `q`
        -- still finds Grade's complete range. That WAS true of the artifact
        -- that shipped, and is what the alias exists to make false; a note
        -- saying it again would describe an export we no longer emit. (The
        -- first error was the reverse claim that the domain was dropped
        -- outright, which is now true AT THE ALIAS -- so it is deliberately not
        -- pinned here, or a future editor writing the accurate sentence would
        -- trip a test asserting the inaccurate one.)
        qNotes `shouldNotSatisfy` any (Text.isInfixOf "does not reach through the typeRef")
        map (.lost) [n | n <- notes, Text.isInfixOf "`q`" n.message]
          `shouldSatisfy` all (Text.isInfixOf "engine-side validation of the values that ARE present")
        -- The BASE definition is untouched: the alias drops the range, it does
        -- not remove it from the file.
        xml `shouldSatisfy` Text.isInfixOf "<text>\"high\",\"low\"</text>"

      it "leaves a MAYBE over a type with NO domain on R8-a's plain lowering" $ do
        -- The carve-out is scoped to what defeats R8-b. A builtin asserts no
        -- range, so the typeRef hop has nothing to re-assert and an alias would
        -- be the pure ceremony §4.3 refuses.
        drg <- sumtypeDrg
        let xml = emitDrg drg
        xml `shouldSatisfy` Text.isInfixOf
          "name=\"capped_at_ten\" label=\"capped at ten\" typeRef=\"number\""
        xml `shouldNotSatisfy` Text.isInfixOf "number_optional"
        [ n.message | n <- drgNotesAll drg, n.code == "D-MAYBE-NULL"
          , Text.isInfixOf "`capped at ten`" n.message ]
          `shouldSatisfy` all (not . Text.isInfixOf "domain-free alias")

      it "names a THREADED sum component's REAL typeRef, not a hardcoded Any" $ do
        -- The component is emitted `typeRef="Disposal"`, and `Disposal`'s
        -- itemDefinition is a `string` enum listing all three constructors --
        -- so the loss is the tag/payload distinction, not the declared type.
        -- The note used to say typeRef="Any" while the emitter wrote the minted
        -- name: a claim about the artifact that the artifact refuted.
        drg <- sumtypeDrg
        let threaded =
              [ n | n <- drgNotesAll drg, n.code == "D-SUMTYPE"
              , Text.isInfixOf "threads `Claim`" n.message ]
        threaded `shouldSatisfy` (not . null)
        map (.message) threaded `shouldSatisfy` all (Text.isInfixOf "typeRef=\"Disposal\"")
        map (.message) threaded `shouldNotSatisfy` any (Text.isInfixOf "typeRef=\"Any\"")
        map (.lost) threaded `shouldSatisfy` all (Text.isInfixOf "tag/payload distinction")
        emitDrg drg `shouldSatisfy`
          Text.isInfixOf "name=\"the_disposal\" label=\"the disposal\">\n      <typeRef>Disposal</typeRef>"

      it "suffixes an itemDefinition name that collides with a FEEL built-in type" $ do
        -- `DECLARE `number`` and a NUMBER-typed element must not end up sharing
        -- one typeRef: a typeRef resolves against FEEL's built-in type names,
        -- so `name="number"` aliases rather than shadows, and no fidelity note
        -- could report it because nothing in the artifact distinguishes them.
        drg <- sumtypeDrg
        let xml = emitDrg drg
        map (.idfName) drg.drgItemDefs `shouldSatisfy` elem "number_"
        map (.idfName) drg.drgItemDefs `shouldNotSatisfy` elem "number"
        xml `shouldSatisfy` Text.isInfixOf "name=\"k\" typeRef=\"number_\""
        -- ...while a genuine NUMBER keeps the built-in spelling.
        xml `shouldSatisfy` Text.isInfixOf "name=\"n\" typeRef=\"number\""
        -- The L4 spelling survives verbatim on @label, so the rename is visible
        -- rather than lossy.
        xml `shouldSatisfy`
          Text.isInfixOf "<itemDefinition id=\"itemdef_number\" name=\"number_\" label=\"number\">"

      it "never spells NOTHING as a FEEL value (R8-f, and the defect it fixes)" $ do
        drg <- sumtypeDrg
        let xml = emitDrg drg
        -- The shipped defect: `isConstantRef` accepted the BUILTIN NOTHING,
        -- because the typechecker stamps it `Constructor` exactly as it stamps
        -- a user one, so it lowered to the S-FEEL string constant "NOTHING" --
        -- silently wrong, and worse than a loud failure because the paired JUST
        -- arm WAS reported.
        xml `shouldNotSatisfy` Text.isInfixOf "\"NOTHING\""
        -- Nor as a bare FEEL identifier, which is what excluding it from
        -- `isConstantRef` alone would have produced.
        --
        -- The assertion above is UNCHANGED by R8-d′ and must stay: R8-f is
        -- about the STRING CONSTANT, and `NOTHING` still has no spelling as
        -- one. What changed underneath it is the rendering -- `NOTHING` is now
        -- FEEL's `null`, a literal, not a name and not a string.
        xml `shouldNotSatisfy` Text.isInfixOf ">NOTHING<"

      it "tabulates a MAYBE-valued decision with a null default output (R8-d′)" $ do
        -- Was: "refuses the builtin open sums at the value level (R8-d)".
        -- R8-d is OVERTURNED for the value channel as of 2026-07-31, on its own
        -- stated terms, so `capped at ten` is now a real decision TABLE whose
        -- absent case is the defaultOutputEntry.
        drg <- sumtypeDrg
        case (decisionNamed "capped at ten" drg).dcnLogic of
          LogicTable t -> do
            t.dtHitPolicy `shouldBe` HitUnique
            map cellTexts t.dtRules `shouldBe` [["<= 10"]]
            -- The absent case. MEASURED on both engines before this lowering
            -- was written (jl4/tests-cli/fixtures/dmn-null-probe): a table
            -- whose defaultOutputEntry is `null` answers null past its rows on
            -- KIE 8.44 and zeebe-dmn 8.7.6 alike.
            fmap (.feText) t.dtOutput.ocDefault `shouldBe` Just "null"
          LogicLiteral e -> expectationFailure ("expected a table, got " <> show e.feText)
          LogicContext _ -> expectationFailure "unexpected boxed context"
        -- D-SUMTYPE is GONE; D-MAYBE-NULL stays, because the variable's typeRef
        -- is still `number` and the absent/undefined conflation is still real.
        [(n.code, n.severity) | n <- drgNotesAll drg, n.element == "decision_capped_at_ten"]
          `shouldSatisfy` notElem ("D-SUMTYPE", Blocking)
        [(n.code, n.severity) | n <- drgNotesAll drg, n.element == "decision_capped_at_ten"]
          `shouldSatisfy` elem ("D-MAYBE-NULL", Lossy)

      it "renders an absence test as a comparison against null, not verbatim (R8-d′)" $ do
        drg <- sumtypeDrg
        -- The LONGHAND spelling: a CONSIDER over a MAYBE, rendered by
        -- renderFeelIn's own case rather than by a source rewrite.
        case (decisionNamed "grade is settled, spelled longhand" drg).dcnLogic of
          LogicLiteral e -> do
            e.feText `shouldBe` "if p != null then true else false"
            e.feFragment `shouldBe` FullFeel
          LogicTable _ -> expectationFailure "expected a boxed literal expression"
          LogicContext _ -> expectationFailure "unexpected boxed context"
        -- The IDIOMATIC spelling, through the combinator table. Both must
        -- render, because both appear in real L4 and recognising only one
        -- would make the house style the worse artifact.
        case (decisionNamed "grade is settled" drg).dcnLogic of
          LogicLiteral e -> do
            e.feText `shouldBe` "q != null"
            e.feFragment `shouldBe` FullFeel
          LogicTable _ -> expectationFailure "expected a boxed literal expression"

          LogicContext _ -> expectationFailure "unexpected boxed context"
      it "refuses a NESTED MAYBE, because null does not nest (R8-c)" $ do
        drg <- sumtypeDrg
        -- Phase 4 adds D-INERT: `deep m MEANS TRUE` forces no reference and
        -- no input, which is rule 4's ruled predicate doing its job on a
        -- fixture that happens to be a constant stub.
        [(n.code, n.severity) | n <- drgNotesAll drg, n.element == "decision_deep"]
          `shouldBe` [("D-SUMTYPE", Blocking), ("D-INERT", Advisory)]
        [n.message | n <- drgNotesAll drg, n.element == "decision_deep", n.code == "D-SUMTYPE"]
          `shouldSatisfy` all (Text.isInfixOf "does not nest")

      it "keeps the nullary-only CONSIDER's table and reports the DOMAIN, not a refusal" $ do
        -- §10's Phase 3 obligation. The table is exact -- measured in KIE 8.44,
        -- §4.2.1-2 -- and what is lost is that the payload constructor has no
        -- cell, which the itemDefinition's allowedValues makes visible to a gap
        -- analyser as a gap rather than as silence.
        drg <- sumtypeDrg
        case (decisionNamed "is a sale" drg).dcnLogic of
          LogicTable t -> do
            t.dtHitPolicy `shouldBe` HitUnique
            map (.icValues) t.dtInputs `shouldBe` [Just ["sell", "lease", "assign"]]
          LogicLiteral e -> expectationFailure ("expected a table, got " <> show e.feText)
          LogicContext _ -> expectationFailure "unexpected boxed context"
        [(n.code, n.severity) | n <- drgNotesAll drg, n.element == "decision_is_a_sale"]
          `shouldBe` [("D-SUMTYPE", Lossy)]
        [n.message | n <- drgNotesAll drg, n.element == "decision_is_a_sale"]
          `shouldSatisfy` all (Text.isInfixOf "no cell is emitted for `lease`")

      it "refuses a payload PROJECTION and only Lossy-reports a record that threads one" $ do
        drg <- sumtypeDrg
        -- Phase 4 adds D-PARTIAL: the payload projection is ALSO L11's
        -- refusal — a selector over a multi-constructor union raises
        -- NonExhaustivePatterns at run time — so DMN-SAFE and the data-model
        -- analysis state the same hazard from two sides, deliberately.
        [(n.code, n.severity) | n <- drgNotesAll drg, n.element == "decision_stated_term"]
          `shouldBe` [("D-SUMTYPE", Blocking), ("D-PARTIAL", Blocking)]
        -- Threading is NOT reading: R4-a keeps this one, and only says the
        -- component's type could not be carried.
        -- (it is also a plain projection rather than a chain, so it carries the
        -- ordinary D-LITERALEXPR as well — Advisory since the Phase 5
        -- severity re-key: the projection renders as FEEL; the point here is
        -- the SEVERITY of the sum-type note, which is Lossy and not Blocking)
        [(n.code, n.severity) | n <- drgNotesAll drg, n.element == "decision_claim_amount"]
          `shouldBe` [("D-LITERALEXPR", Advisory), ("D-SUMTYPE", Lossy)]

      it "reports a LIST OF component, which needs an itemDefinition of its own" $ do
        drg <- sumtypeDrg
        [n.message | n <- drgNotesAll drg, n.code == "D-ITEMDEF"]
          `shouldSatisfy` any (Text.isInfixOf "supporting notes")
        [n.severity | n <- drgNotesAll drg, n.code == "D-ITEMDEF"]
          `shouldSatisfy` all (== Lossy)

    -- R8-e and R8-c, pinned as REFUSALS in their own right.
    --
    -- These were written BEFORE the R8-d′ narrowing that made JUST/NOTHING
    -- lower to FEEL null, and were watched go green on the unmodified tree
    -- first, because narrowing a refusal you have not pinned is exactly how a
    -- refusal disappears without anyone noticing. EITHER in particular had ZERO
    -- coverage in this file and zero corpus exposure before this change: the
    -- only thing standing between it and a silent value lowering was a
    -- disjunct in a list comprehension.
    describe "what still refuses after MAYBE lowers to null (R8-c, R8-e)" $ do
      let eitherSrc name body =
            Text.unlines
              [ "GIVEN e IS AN EITHER NUMBER STRING"
              , "GIVETH A BOOLEAN"
              , "`" <> name <> "` e MEANS"
              , body
              ]

      it "refuses a decision that CONSTRUCTS an EITHER (R8-e)" $ do
        let drg = drgOf $ Text.unlines
              [ "GIVEN n IS A NUMBER"
              , "GIVETH AN EITHER NUMBER STRING"
              , "`tagged` n MEANS"
              , "  IF n AT MOST 10 THEN LEFT n ELSE RIGHT \"big\""
              ]
        [(n.code, n.severity) | n <- drgNotesAll drg, n.element == "decision_tagged"]
          `shouldSatisfy` elem ("D-SUMTYPE", Blocking)
        -- LEFT/RIGHT keep the R8-f treatment JUST/NOTHING lose: verbatim, so
        -- the constructor name never reaches an engine as a FEEL string or as
        -- a bare identifier.
        emitDrg drg `shouldNotSatisfy` Text.isInfixOf "\"LEFT\""
        emitDrg drg `shouldNotSatisfy` Text.isInfixOf "\"RIGHT\""

      it "refuses a CONSIDER over an EITHER (R8-e)" $ do
        let drg = drgOf $ eitherSrc "reads"
              "  CONSIDER e\n  WHEN LEFT n  THEN TRUE\n  WHEN RIGHT s THEN FALSE"
        [(n.code, n.severity) | n <- drgNotesAll drg, n.element == "decision_reads"]
          `shouldSatisfy` elem ("D-SUMTYPE", Blocking)

      it "refuses an EITHER at a decision BOUNDARY, even unread (R8-e)" $ do
        -- `e` is threaded and never matched, so neither the constructor clause
        -- nor the CONSIDER clause fires. Only the boundary clause does, and
        -- this is the test that pins it.
        let drg = drgOf $ eitherSrc "threads" "  TRUE"
        [(n.code, n.severity) | n <- drgNotesAll drg, n.element == "decision_threads"]
          `shouldSatisfy` elem ("D-SUMTYPE", Blocking)
        [n.message | n <- drgNotesAll drg, n.element == "decision_threads"]
          `shouldSatisfy` any (Text.isInfixOf "no EITHER")

      it "refuses a NESTED MAYBE used as a CONSIDER SCRUTINEE (R8-c)" $ do
        -- The disjunct that is easiest to drop. `classifyType` sets tfMaybe
        -- TRUE as well as tfNestedMaybe on a nested MAYBE, so a scrutinee
        -- clause narrowed to `tfEither` alone would let this through and
        -- lower `JUST NOTHING` and `NOTHING` to one FEEL null -- an ANSWER
        -- CHANGE, not a rendering one. `deep` in sumtype.l4 does NOT cover
        -- this: its body is `TRUE` and it only reaches the boundary clause.
        let drg = drgOf $ Text.unlines
              [ "GIVEN m IS A MAYBE (MAYBE NUMBER)"
              , "GIVETH A BOOLEAN"
              , "`nested scrutinee` m MEANS"
              , "  CONSIDER m"
              , "  WHEN JUST inner THEN TRUE"
              , "  WHEN NOTHING    THEN FALSE"
              ]
        [(n.code, n.severity) | n <- drgNotesAll drg, n.element == "decision_nested_scrutinee"]
          `shouldSatisfy` elem ("D-SUMTYPE", Blocking)
        -- ★ The NOTE is not the refusal. `literalFallback` renders the body and
        -- reports Blocking BESIDE it, so a note alone leaves open the one
        -- outcome R8-c exists to prevent: `if m != null then true else false`
        -- COMPILES, and answers `false` for `JUST NOTHING` where L4 answers
        -- `true`. Pinning the rendering is what makes the refusal a refusal --
        -- and before this assertion existed, the artifact shipped exactly that
        -- executable wrong answer while this test stayed green.
        case (decisionNamed "nested scrutinee" drg).dcnLogic of
          LogicLiteral e -> do
            e.feFragment `shouldBe` L4Verbatim
            e.feText `shouldNotSatisfy` Text.isInfixOf "!= null"
          LogicTable _   -> expectationFailure "expected a boxed literal expression"
          LogicContext _ -> expectationFailure "unexpected boxed context"

      it "refuses JUST and NOTHING at a NESTED MAYBE type (R8-c)" $ do
        -- The other two arms of the same guard. `JUST NOTHING` and `NOTHING`
        -- would both render `null`, so a decision returning the first would
        -- become indistinguishable from one returning the second.
        let drg = drgOf $ Text.unlines
              [ "GIVEN n IS A NUMBER"
              , "GIVETH A MAYBE (MAYBE NUMBER)"
              , "`wrapped` n MEANS"
              , "  IF n AT MOST 10 THEN JUST (JUST n) ELSE JUST NOTHING"
              ]
        emitDrg drg `shouldNotSatisfy` Text.isInfixOf "<text>null</text>"
        [(n.code, n.severity) | n <- drgNotesAll drg, n.element == "decision_wrapped"]
          `shouldSatisfy` elem ("D-SUMTYPE", Blocking)

      it "does not recognise a LOCALLY defined isJust as the prelude's (R8-d′)" $ do
        -- The combinator table is keyed on a resolved 'Unique', but the Unique
        -- is FOUND by a name lookup, so the name alone cannot be what licenses
        -- the `x != null` rendering: a module that defines its own
        -- `isJust :: MAYBE a -> BOOLEAN` and does not import the prelude has
        -- exactly one shaped candidate, and the shape check cannot see the
        -- body. 'resolveMaybePredicates' therefore also requires the definition
        -- to come from a DIFFERENT module. Without that, this body -- which
        -- means the opposite of what its name says -- rendered `q != null`,
        -- with no fidelity note at all because a recognised combinator is
        -- clean FEEL.
        let drg = drgOf $ Text.unlines
              [ "GIVEN x IS A MAYBE NUMBER"
              , "GIVETH A BOOLEAN"
              , "`isJust` x MEANS FALSE"
              , ""
              , "GIVEN y IS A MAYBE NUMBER"
              , "GIVETH A BOOLEAN"
              , "`isNothing` y MEANS TRUE"
              , ""
              , "GIVEN q IS A MAYBE NUMBER"
              , "GIVETH A BOOLEAN"
              , "`asks` q MEANS isJust q"
              ]
        case (decisionNamed "asks" drg).dcnLogic of
          LogicLiteral e -> e.feText `shouldNotSatisfy` Text.isInfixOf "!= null"
          LogicTable _   -> expectationFailure "expected a boxed literal expression"
          LogicContext _ -> expectationFailure "unexpected boxed context"

  -- §4.4. Hydration ships four goldens and, until this block, no NAMED test.
  -- A golden pins everything at once, which is also why it pins nothing in
  -- particular: a hydrator that moved for the wrong reason reads as "the
  -- hydrator moved" and gets blessed. Each of these was written against a
  -- defect the goldens did not catch.
  describe "hydration (§4.4)" $ do
    let hydratedEntries name drg = case (decisionNamed name drg).dcnLogic of
          LogicContext es -> map (.ceName) es
          _               -> []

    it "keeps INDEPENDENT computed fields in declaration order" $ do
      -- The first implementation sorted with 'Data.Graph.stronglyConnComp',
      -- which does put dependencies first but says nothing about independent
      -- vertices -- and duly emitted Reg CF's `greater of …` and `lesser of …`
      -- in the opposite order from the DECLARE, while the comment beside it
      -- and the spec both asserted declaration order was preserved.
      let drg = drgOf $ Text.unlines
            [ "DECLARE P HAS"
            , "    `x` IS A NUMBER"
            , "    `y` IS A NUMBER"
            , "    `first`  IS A NUMBER MEANS `x` PLUS 1"
            , "    `second` IS A NUMBER MEANS `y` PLUS 1"
            , ""
            , "GIVEN p IS A P"
            , "GIVETH A NUMBER"
            , "`reads` p MEANS p's `first` PLUS p's `second`"
            ]
      hydratedEntries "p" drg `shouldBe` ["x", "y", "first", "second"]

    it "emits a dependent field AFTER the sibling it reads" $ do
      -- A boxed context's entries see only EARLIER siblings, so getting this
      -- wrong is silent: the reference resolves to nothing and FEEL answers
      -- null. Declared deliberately in the wrong order.
      let drg = drgOf $ Text.unlines
            [ "DECLARE P HAS"
            , "    `x` IS A NUMBER"
            , "    `y` IS A NUMBER"
            , "    `doubled` IS A NUMBER MEANS `total` TIMES 2"
            , "    `total`   IS A NUMBER MEANS `x` PLUS `y`"
            , ""
            , "GIVEN p IS A P"
            , "GIVETH A NUMBER"
            , "`reads` p MEANS p's `doubled`"
            ]
      hydratedEntries "p" drg `shouldBe` ["x", "y", "total", "doubled"]

    it "keeps a STORED and a COMPUTED field apart when both fold to one name" $ do
      -- §5.3.4's executed collision, at the seam hydration added. `total income`
      -- and `total_income` both fold to `total_income` at stage 1, so unless the
      -- computed selectors join the record's OWN `uniquifyIn` call they get
      -- separate path steps that happen to be the same string: valid FEEL
      -- computing a wrong number, with no note. Because one map then serves both
      -- the context entry names and the downstream path steps, they agree by
      -- construction rather than by two functions remembering to.
      let drg = drgOf $ Text.unlines
            [ "DECLARE P HAS"
            , "    `total income` IS A NUMBER"
            , "    `total_income` IS A NUMBER MEANS `total income` TIMES 2"
            , ""
            , "GIVEN p IS A P"
            , "GIVETH A NUMBER"
            , "`reads` p MEANS p's `total_income`"
            ]
          entries = hydratedEntries "p" drg
      entries `shouldSatisfy` ((== 2) . length)
      nubOrd entries `shouldBe` entries
      -- and the downstream read names the SECOND one, not the stored one
      case (decisionNamed "reads" drg).dcnLogic of
        LogicLiteral e -> e.feText `shouldBe` ("p_hydrated." <> last entries)
        _              -> expectationFailure "expected a boxed literal expression"

    it "requires every DECISION a computed field's body names" $ do
      -- 'Desugar.rewriteFieldRefs' rewrites only the record's OWN field names,
      -- so a MEANS body may reference any module-level decision and the
      -- context entry renders it by name. A hydrator whose only edge was its
      -- source instance left that name unbound: KIE 8.44 reports "Required
      -- dependency not found" and SKIPs (measured, dmn-null-probe/null-absent),
      -- zeebe-dmn reads null and multiplies by it.
      let drg = drgOf $ Text.unlines
            [ "GIVETH A NUMBER"
            , "`vat rate` MEANS 7"
            , ""
            , "DECLARE R HAS"
            , "    `a` IS A NUMBER"
            , "    `b` IS A NUMBER MEANS `a` TIMES `vat rate`"
            , ""
            , "GIVEN r IS A R"
            , "GIVETH A NUMBER"
            , "`out` r MEANS r's `b`"
            ]
      sort (map requirementTarget (decisionNamed "r" drg).dcnRequirements)
        `shouldBe` ["decision_vat_rate", "input_r"]

    it "reports a computed field body it cannot render as FEEL, Blocking" $ do
      -- Every OTHER rendering path in the lowerer asks `feFragment ==
      -- L4Verbatim` before emitting; the hydrator is built outside the
      -- per-decide note machinery, so for a while it did not. A computed field
      -- whose body is a CONSIDER over a payload-carrying sum shipped raw L4
      -- source inside a <literalExpression> with a CLEAN fidelity report.
      let drg = drgOf $ Text.unlines
            [ "DECLARE D IS ONE OF"
            , "    sale"
            , "    lease HAS `term` IS A NUMBER"
            , ""
            , "DECLARE R HAS"
            , "    `a` IS A NUMBER"
            , "    `d` IS A D"
            , "    `b` IS A NUMBER MEANS CONSIDER `d`"
            , "                          WHEN lease t THEN t"
            , "                          WHEN sale    THEN `a`"
            , ""
            , "GIVEN r IS A R"
            , "GIVETH A NUMBER"
            , "`out` r MEANS r's `b`"
            ]
      [(n.code, n.severity) | n <- drgNotesAll drg, n.element == "hydration_r"]
        `shouldSatisfy` elem ("D-NONFEELOUTPUT", Blocking)

    it "rewires a computed read to the hydrator and drops the direct edge (R11)" $ do
      let drg = drgOf $ Text.unlines
            [ "DECLARE P HAS"
            , "    `x` IS A NUMBER"
            , "    `twice` IS A NUMBER MEANS `x` TIMES 2"
            , ""
            , "GIVEN p IS A P"
            , "GIVETH A NUMBER"
            , "`reads` p MEANS p's `twice`"
            ]
      -- The emitted FEEL no longer names `p`, so the graph must not claim it
      -- does; and it DOES name the hydrator, so the graph must say so.
      map requirementTarget (decisionNamed "reads" drg).dcnRequirements
        `shouldBe` ["hydration_p"]
      -- `p` is still an inputData: the hydrator requires it.
      map (.idId) (drgInputData drg) `shouldBe` ["input_p"]
      -- And no bogus inputData was minted for the computed selector itself.
      map (.idId) (drgInputData drg) `shouldNotSatisfy` elem "input_twice"

    it "leaves a computed read through a NON-NULLARY receiver verbatim (D12)" $ do
      -- No hydrator names a record-valued EXPRESSION, so this cannot fold. It
      -- must refuse GRACEFULLY -- the existing verbatim path and its existing
      -- diagnosis -- and mint no new code. regcf-wizard.l4 carries the live
      -- instance and is deliberately left carrying it.
      let drg = drgOf $ Text.unlines
            [ "DECLARE P HAS"
            , "    `x` IS A NUMBER"
            , "    `twice` IS A NUMBER MEANS `x` TIMES 2"
            , ""
            , "GIVEN n IS A NUMBER"
            , "GIVETH A P"
            , "`make` n MEANS P WITH `x` IS n"
            , ""
            , "GIVEN n IS A NUMBER"
            , "GIVETH A NUMBER"
            , "`reads` n MEANS (`make` n)'s `twice`"
            ]
      case (decisionNamed "reads" drg).dcnLogic of
        LogicLiteral e -> e.feFragment `shouldBe` L4Verbatim
        _              -> expectationFailure "expected a boxed literal expression"
      [n.code | n <- drgNotesAll drg, n.element == "decision_reads"]
        `shouldSatisfy` all (`elem` ["D-LITERALEXPR", "D-NONFEELOUTPUT", "D-SUMTYPE"])

    it "does not fold the SELECT idiom inside a hydrator -- a stated boundary" $ do
      -- A KNOWN divergence, pinned so the golden cannot move unexplained.
      -- `IF a AT LEAST b THEN a ELSE b` folds to `max(a, b)` everywhere else,
      -- including through a SOURCE-written projection (`max(p.x, p.y)`), but
      -- not inside a hydrator: 'Desugar.rewriteFieldRefs' builds the sibling
      -- read as `Proj emptyAnno (Var emptyAnno _self) n`, and a node with no
      -- source range carries no inferred type, so 'feelOrderable' cannot
      -- answer and 'selectIdiomIn' declines. Both forms are FullFeel and both
      -- evaluate (33/33 on KIE 8.44 and zeebe-dmn 8.7.6), so the cost is
      -- legibility, not fidelity -- which is why this is recorded rather than
      -- repaired in L4.Desugar, whose output every computed-field module and
      -- the exactprint goldens depend on.
      let drg = drgOf $ Text.unlines
            [ "DECLARE P HAS"
            , "    `x` IS A NUMBER"
            , "    `y` IS A NUMBER"
            , "    `bigger` IS A NUMBER MEANS IF `x` AT LEAST `y` THEN `x` ELSE `y`"
            , ""
            , "GIVEN p IS A P"
            , "GIVETH A NUMBER"
            , "`reads` p MEANS p's `bigger`"
            ]
      case (decisionNamed "p" drg).dcnLogic of
        LogicContext es ->
          [e.ceExpr.feText | e <- es, e.ceName == "bigger"]
            `shouldBe` ["(if x >= y then x else y)"]
        _ -> expectationFailure "expected a boxed context"

  describe "engine flavors (R7)" $ do
    it "defaults to camunda" $ do
      defaultDmnFlavor `shouldBe` FlavorCamunda
      (drgOf spacedNames).drgFlavor `shouldBe` FlavorCamunda

    it "names the flavor in the fidelity report, not just the notation" $ do
      -- The report is generated from the same Drg the document is. One that said
      -- only "DMN 1.3 (XML)" would be describing a file the reader cannot
      -- identify, which is the failure class this exporter exists to close.
      (dmnReport (drgFlavored FlavorCamunda "T" spacedNames)).target
        `shouldBe` "DMN 1.3 (XML), camunda flavor"
      (dmnReport (drgFlavored FlavorKie "T" spacedNames)).target
        `shouldBe` "DMN 1.3 (XML), kie flavor"

    it "the flavors DIVERGE on exactly the §-invocation, and nowhere else" $ do
      -- This test used to be the Phase 5 tripwire ("EXPECTED TO FAIL AT
      -- PHASE 5: the two flavors are still byte-identical"), and it fired on
      -- 2026-08-01. Flipped as its own comment instructed: split the goldens
      -- (svc.kie.dmn beside svc.dmn), keep the test, and assert the seam in
      -- BOTH directions.
      --
      -- Direction 1 — the POSITIVE divergence, on the one subject that
      -- genuinely diverges (the §-invocation exhibit): the kie bytes carry a
      -- requiredKnowledge pointing at a decisionService and the rendered
      -- invocation; the camunda bytes carry neither, because that edge is
      -- fatal to Camunda 8's parse() (§13.4).
      svcSrc <- Text.readFile (examplesRoot </> "dmn" </> "svc.l4")
      let kie     = emitDrg (drgFlavored FlavorKie "S" svcSrc)
          camunda = emitDrg (drgFlavored FlavorCamunda "S" svcSrc)
      kie `shouldSatisfy`
        Text.isInfixOf "<requiredKnowledge href=\"#service_special_assessment\"/>"
      kie `shouldSatisfy` Text.isInfixOf "special_assessment(p: 150, q: 5)"
      camunda `shouldNotSatisfy` Text.isInfixOf "requiredKnowledge href=\"#service_"
      camunda `shouldNotSatisfy` Text.isInfixOf "special_assessment(p:"
      -- ...and the camunda side says WHY, at Blocking, rather than shipping
      -- the gap silently (§13.5's D-FLAVOR-NOSERVICE).
      let camNotes = (dmnReport (drgFlavored FlavorCamunda "S" svcSrc)).notes
      [n.severity | n <- camNotes, n.code == "D-FLAVOR-NOSERVICE", n.severity == Blocking]
        `shouldBe` [Blocking]
      -- Direction 2 — everything WITHOUT a §-invocation stays byte-identical
      -- (measured 2026-08-01 over every golden subject), so a future change
      -- that makes the flavors drift anywhere else is announced here.
      emitDrg (drgFlavored FlavorCamunda "T" spacedNames)
        `shouldBe` emitDrg (drgFlavored FlavorKie "T" spacedNames)
      emitDrg (drgFlavored FlavorCamunda "Regulation Crowdfunding" considerConstructors)
        `shouldBe` emitDrg (drgFlavored FlavorKie "Regulation Crowdfunding" considerConstructors)
      bkmSrc <- Text.readFile (examplesRoot </> "dmn" </> "bkm.l4")
      emitDrg (drgFlavored FlavorCamunda "B" bkmSrc)
        `shouldBe` emitDrg (drgFlavored FlavorKie "B" bkmSrc)

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

    it "omits a table whose OTHERWISE dmnmd cannot say, and says so (R8-d′)" $ do
      -- ★ 'expressible' checked the rules and not the <defaultOutputEntry>, so
      -- when R8-d′ made a MAYBE-valued decision tabulate with a FEEL `null`
      -- catch-all, 'defaultRows' fell back to `fromMaybe "-"` and printed
      -- `| 2 | - | - |`. In dmnmd `-` is the INPUT column's "any" token, so a
      -- reader read the catch-all as "output unspecified" rather than as "no
      -- value" -- and the only note beside it was D-MD-NODEFAULT, whose
      -- message is about the U-to-F demotion and whose own spec row says "the
      -- answers are preserved". A loud omission is the correct trade against a
      -- quiet misstatement, and it is the standard 'mdConstant' already sets
      -- for a date.
      let drg = drgOf $ Text.unlines
            [ "GIVEN n IS A NUMBER"
            , "GIVETH A MAYBE NUMBER"
            , "`capped` n MEANS"
            , "  IF n AT MOST 10 THEN JUST n ELSE NOTHING"
            ]
      -- the DMN table itself is unaffected: this is a markdown-carrier loss
      case (decisionNamed "capped" drg).dcnLogic of
        LogicTable t -> fmap (.feText) t.dtOutput.ocDefault `shouldBe` Just "null"
        _            -> expectationFailure "expected a decision table"
      let md = emitMarkdown drg
      md `shouldNotSatisfy` Text.isInfixOf "capped (out)"
      md `shouldNotSatisfy` Text.isInfixOf "| - | - |"
      let notes = [n | n <- (markdownReport drg).notes, n.element == "decision_capped"]
      [(n.code, n.severity) | n <- notes] `shouldSatisfy` elem ("D-MD-CELLSYNTAX", Blocking)
      map (.message) notes `shouldSatisfy` any (Text.isInfixOf "OTHERWISE is `null`")
      -- and the DMN report keeps calling `null` a LITERAL, which is what the
      -- D-COMPUTEDOUTPUT message used to contradict in the same file
      [n.message | n <- (dmnReport drg).notes, n.code == "D-COMPUTEDOUTPUT"]
        `shouldSatisfy` any (Text.isInfixOf "null LITERAL")
      -- and D-MD-NODEFAULT must NOT also fire: the table is not there to have
      -- had its hit policy demoted.
      map (.code) notes `shouldNotSatisfy` elem "D-MD-NODEFAULT"

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

  -- The corpus assertion §5.2 stage 2 owes: on the real Reg CF corpus, whose
  -- nine collision groups (`issuer` x 9, `investor` x 9, ...) are what made
  -- D-FEELNAME worth building, the code must now fire ZERO times, because every
  -- one of those groups is renamed apart instead. The golden fidelity report
  -- shows the same thing; this says it as an invariant rather than as a diff.
  it "fires D-FEELNAME zero times on the Reg CF corpus, by construction" $ do
    src <- Text.readFile (examplesRoot </> "legal" </> "regcf" </> "regcf.l4")
    let notes = (dmnReport (drgAsCli "regcf.l4" src)).notes
    [n | n <- notes, n.code == "D-FEELNAME"] `shouldBe` []
    [n | n <- notes, n.code == "D-RENAME"] `shouldSatisfy` (not . null)

  ----------------------------------------------------------------------
  -- Law time (spec §15): binding, interval tables, the D-RULEDATE family
  ----------------------------------------------------------------------
  describe "law time" $ do
    let gstDrg = do
          src <- Text.readFile (examplesRoot </> "dmn" </> "gst-rate.l4")
          pure (drgAsCli "gst-rate.l4" src)
        corpusDrg = do
          src <- Text.readFile (examplesRoot </> "legal" </> "regcf" </> "regcf.l4")
          pure (drgAsCli "regcf.l4" src)
        notOkDrg n = do
          src <- Text.readFile (examplesRoot </> "dmn" </> "not-ok" </> n)
          pure (drgAsCli n src)

    -- D1. Before this, `RULES_EFFECTIVE_DATE` occurred in the shipped corpus
    -- golden exactly once and was bound by NOTHING -- a free FEEL name no
    -- engine can resolve, with no note anywhere saying so.
    it "binds the rule date as one date-typed inputData (D1)" $ do
      drg <- gstDrg
      let ins = [i | NodeInputData i <- drg.drgNodes, i.idFeelName == "RULES_EFFECTIVE_DATE"]
      map (.idType) ins `shouldBe` [DmnDate]
      map (.idName) ins `shouldBe` ["RULES EFFECTIVE DATE"]
      map (.idId) ins `shouldBe` ["input_rules_effective_date"]

    -- Edges are computed at IR level over `freeRefs`, never by scanning the
    -- emitted FEEL: the corpus's COVID-window decision reads law time twice and
    -- its emitted text used to contain no `RULES_EFFECTIVE_DATE` token at all.
    it "gives every decision that mentions the rule date a requiredInput edge (D1)" $ do
      drg <- gstDrg
      let mentions d = case d.dcnLogic of
            LogicLiteral e -> Text.isInfixOf "RULES_EFFECTIVE_DATE" e.feText
            LogicTable t ->
              any (Text.isInfixOf "RULES_EFFECTIVE_DATE" . (.feText) . (.icExpr)) t.dtInputs
            LogicContext _ -> False
      [ d.dcnName
        | d <- drgDecisions drg
        , mentions d
        , RequiredInput "input_rules_effective_date" `notElem` d.dcnRequirements
        ] `shouldBe` []

    -- §15.5's invariant, asserted over EVERY golden subject rather than left to
    -- the goldens: no emitted model may reference law time without either the
    -- bound input plus its Advisory, or the Lossy population finding (R12
    -- re-severed D-RULEDATE-UNBOUND Blocking → Lossy, spec §15.12).
    it "never references law time without a binding or a Lossy note (§15.5)" $
      forM_ goldenSubjects \(srcPath, stem, _) -> do
        src <- Text.readFile (examplesRoot </> srcPath)
        let drg   = drgAsCli srcPath src
            xml   = emitDrg drg
            notes = (dmnReport drg).notes
            bound = not (null [i | NodeInputData i <- drg.drgNodes
                                 , i.idFeelName == "RULES_EFFECTIVE_DATE"])
            ruleDate = [n | n <- notes, n.code == "D-RULEDATE"]
            unbound  = [n | n <- notes, n.code == "D-RULEDATE-UNBOUND"]
        when (Text.isInfixOf "RULES_EFFECTIVE_DATE" xml) $
          unless ((bound && length ruleDate == 1) || not (null unbound)) $
            expectationFailure
              (stem <> " references law time with neither a bound input + one \
                        \D-RULEDATE Advisory nor a D-RULEDATE-UNBOUND Lossy")

    -- D2, the PREDICATE idiom. The cells are asserted VERBATIM because the
    -- closed-low/open-high convention is the whole content of the lowering.
    it "lowers the predicate idiom to a UNIQUE date-interval table (D2)" $ do
      drg <- gstDrg
      case (decisionNamed "GST rate percent" drg).dcnLogic of
        LogicLiteral e -> expectationFailure ("expected a table, got " <> show e.feText)
        LogicTable t -> do
          t.dtHitPolicy `shouldBe` HitUnique
          map (.icType) t.dtInputs `shouldBe` [DmnDate]
          map (.feText) (map (.icExpr) t.dtInputs) `shouldBe` ["RULES_EFFECTIVE_DATE"]
          map (renderUnaryTest . headTest) t.dtRules `shouldBe`
            [ ">= date(\"2024-01-01\")"
            , "[date(\"2023-01-01\")..date(\"2024-01-01\"))"
            , "[date(\"1994-04-01\")..date(\"2023-01-01\"))"
            , "< date(\"1994-04-01\")"
            ]
          -- R9: the OTHERWISE is a floor ROW, so §3.3.1's SHALL forbids a
          -- defaultOutputEntry on what is now a complete table.
          t.dtOutput.ocDefault `shouldBe` Nothing
          t.dtAnnotations `shouldBe` ["regime"]
          map (length . (.drAnnotations)) t.dtRules `shouldBe` [1, 1, 1, 1]

        LogicContext _ -> expectationFailure "unexpected boxed context"
    -- The inline idiom's right-hand side may be a NAMED regime constant or a
    -- bare `Date d m y`, and the exhibit writes one of each: the inline form is
    -- the predicate form with the helper elided, so it must fold the same way
    -- and reach the same one-hop resolver. An earlier version called the bare
    -- literal fold here, which refused every inline chain written against a
    -- named constant while the refusal MESSAGE said such constants are folded.
    it "lowers the inline idiom the same way, named constant or literal (D2)" $ do
      drg <- gstDrg
      case (decisionNamed "tourist refund minimum spend" drg).dcnLogic of
        LogicLiteral e -> expectationFailure ("expected a table, got " <> show e.feText)
        LogicTable t -> do
          t.dtHitPolicy `shouldBe` HitUnique
          map (.icType) t.dtInputs `shouldBe` [DmnDate]
          map (renderUnaryTest . headTest) t.dtRules `shouldBe`
            [ ">= date(\"2024-01-01\")"
            , "[date(\"1994-04-01\")..date(\"2024-01-01\"))"
            , "< date(\"1994-04-01\")"
            ]
          t.dtOutput.ocDefault `shouldBe` Nothing
          -- ...and the constant the arm NAMED reaches the annotation column,
          -- while the arm written as a literal has nothing but its day.
          concat (take 1 (map (.drAnnotations) t.dtRules))
            `shouldSatisfy` any (Text.isInfixOf "the 2024 rate change")
          concat (take 1 (drop 1 (map (.drAnnotations) t.dtRules)))
            `shouldBe` ["from 1994-04-01"]

        LogicContext _ -> expectationFailure "unexpected boxed context"
    -- The refusals. Both must ALSO still ship the sound fallback, so the
    -- artifact is not silently missing a decision.
    it "refuses a mis-ordered dated BRANCH, loudly (R10)" $ do
      drg <- notOkDrg "dated-chain-misordered.l4"
      let ns = [n | n <- (dmnReport drg).notes, n.code == "D-DATEDCHAIN"]
      map (.severity) ns `shouldBe` [Blocking]
      map (.message) ns `shouldSatisfy` all (Text.isInfixOf "1994-04-01")
      map (.message) ns `shouldSatisfy` all (Text.isInfixOf "2023-01-01")
      map (.message) ns `shouldSatisfy` all (Text.isInfixOf "not strictly earlier")
      case (decisionNamed "GST rate percent" drg).dcnLogic of
        LogicTable t   -> length t.dtInputs `shouldSatisfy` (> 1)
        LogicLiteral _ -> expectationFailure "the sound fallback table was not emitted"

        LogicContext _ -> expectationFailure "unexpected boxed context"
    -- §15.4's leniency ruling, end to end: `Date 32 1 2024` ROLLS in L4, and
    -- the exporter refuses to fold it rather than putting a day nobody wrote
    -- into an interval endpoint.
    it "refuses an unfoldable (rolling) arm date, naming it (§15.4)" $ do
      drg <- notOkDrg "dated-chain-rolling-date.l4"
      let ns = [n | n <- (dmnReport drg).notes, n.code == "D-DATEDCHAIN"]
      map (.severity) ns `shouldBe` [Blocking]
      map (.message) ns `shouldSatisfy` all (Text.isInfixOf "not a foldable date constant")
      map (.message) ns `shouldSatisfy` all (Text.isInfixOf "the rolled change")
      case (decisionNamed "GST rate percent" drg).dcnLogic of
        LogicTable t   -> length t.dtInputs `shouldSatisfy` (> 1)
        LogicLiteral _ -> expectationFailure "the sound fallback table was not emitted"

        LogicContext _ -> expectationFailure "unexpected boxed context"
    it "refuses duplicate dates by the same predicate (R10)" $ do
      drg <- notOkDrg "dated-chain-duplicate-date.l4"
      let ns = [n | n <- (dmnReport drg).notes, n.code == "D-DATEDCHAIN"]
      map (.severity) ns `shouldBe` [Blocking]
      map (.message) ns `shouldSatisfy` all (Text.isInfixOf "not strictly earlier")

    -- The ALL-OR-NOTHING arm, which nothing else reaches. This is NOT the same
    -- code path as the corpus's `financial statements required` below: that
    -- chain matches ZERO rows and is therefore `NotDated` (existing path,
    -- existing findings, no note), whereas a chain that matches SOME rows and
    -- not others is a Blocking refusal -- because mixing a law-time arm with an
    -- ordinary one is exactly how a temporal bug hides.
    it "refuses a chain that mixes rule-date arms with an ordinary one (R10)" $ do
      drg <- notOkDrg "dated-chain-mixed.l4"
      let ns = [n | n <- (dmnReport drg).notes, n.code == "D-DATEDCHAIN"]
      map (.severity) ns `shouldBe` [Blocking]
      map (.message) ns `shouldSatisfy` all (Text.isInfixOf "no single date axis")
      -- The ordinal is an index into the CHAIN's rows, so it names the same arm
      -- here as it would in an ordering refusal on the same file.
      map (.message) ns `shouldSatisfy` all (Text.isInfixOf "arm 2 of the chain")
      map (.message) ns `shouldSatisfy` all (Text.isInfixOf "transitional relief")
      case (decisionNamed "GST rate percent" drg).dcnLogic of
        LogicTable t   -> length t.dtInputs `shouldSatisfy` (> 1)
        LogicLiteral _ -> expectationFailure "the sound fallback table was not emitted"

        LogicContext _ -> expectationFailure "unexpected boxed context"
    -- `rowsToDmnWith'` refuses a deontic body BEFORE it builds anything, and
    -- the dated path does not go through `rowsToDmnWith'`. Without the matching
    -- refusal in `datedChain`, a law-time-guarded obligation -- the shape
    -- temporal rule-versioning most invites -- would become a UNIQUE table of
    -- verbatim L4 obligations, and the reader would be told "the output entry
    -- is L4 source, not FEEL" instead of "DMN cannot hold an obligation".
    it "keeps a law-time-guarded OBLIGATION off the dated path (R10)" $ do
      drg <- notOkDrg "dated-chain-regulative.l4"
      let notes = (dmnReport drg).notes
      [n | n <- notes, n.code == "D-DATEDCHAIN"] `shouldBe` []
      case (decisionNamed "filing duty" drg).dcnLogic of
        LogicTable _ ->
          expectationFailure "a deontic body was tabulated; RegulativeBody stopped applying"
        LogicLiteral _ ->
          [n.message | n <- notes, n.code == "D-LITERALEXPR"]
            `shouldSatisfy` any (Text.isInfixOf "deontic (regulative) body")

        LogicContext _ -> expectationFailure "unexpected boxed context"
    -- The nested-chain test counts the OTHERWISE as an arm body. Without that,
    -- `flattenGuarded`'s `expandOtherwise` never runs on a dated chain and the
    -- whole inner chain collapses into ONE floor-row output entry -- silently,
    -- because `datedTable` passes no capped bodies so no D-FLATTENCAP can fire.
    -- Two rules and UNIQUE would be the WRONG artifact here; three and FIRST is
    -- what the source says.
    it "declines a chain whose OTHERWISE is itself a chain (R10)" $ do
      drg <- notOkDrg "dated-chain-nested-otherwise.l4"
      [n | n <- (dmnReport drg).notes, n.code == "D-DATEDCHAIN"] `shouldBe` []
      case (decisionNamed "GST rate percent" drg).dcnLogic of
        LogicTable t -> do
          t.dtHitPolicy `shouldBe` HitFirst
          length t.dtRules `shouldSatisfy` (> 2)
        LogicLiteral _ -> expectationFailure "expected the ordinary flattened table"

        LogicContext _ -> expectationFailure "unexpected boxed context"
    -- The corpus's named witnesses that reference law time and are NOT dated
    -- chains. §15.8 says they must not move. NB this decision matches zero
    -- rule-date arms, so it is `NotDated` rather than a refusal -- the mixed
    -- (partial-match) arm is covered by the not-ok fixture above.
    it "leaves a chain with no rule-date guard on the ordinary path (§15.8)" $ do
      -- Phase 5: `financial statements required` is tier 2 and now emits as a
      -- BKM — but §15.8's claim is about its LOGIC, which is unchanged: the
      -- same multi-column ordinary FIRST table, now the encapsulatedLogic.
      drg <- corpusDrg
      case (bkmNamed "financial statements required" drg).bkmLogic of
        LogicTable t -> do
          t.dtHitPolicy `shouldBe` HitFirst
          length t.dtInputs `shouldSatisfy` (> 1)
        LogicLiteral _ -> expectationFailure "expected the ordinary table"

        LogicContext _ -> expectationFailure "unexpected boxed context"
    -- R12 (§15.12): a rule-date-rebinding decide is DROPPED at population
    -- time, so the note is a population note (Lossy) about a decision the
    -- artifact does not contain — one per rebinding decide, 15 on the corpus.
    it "drops every EVAL UNDER RULES EFFECTIVE AT decision, Lossy-noted (§15.12)" $ do
      drg <- corpusDrg
      let ns = [n | n <- (dmnReport drg).notes, n.code == "D-RULEDATE-UNBOUND"]
      length ns `shouldBe` 15
      map (.severity) ns `shouldSatisfy` all (== Lossy)
      map (.message) ns `shouldSatisfy` all (Text.isInfixOf "not emitted")
      -- ...and none of the named decisions is in the DRG. Population notes
      -- name the decide by its L4 name (there is no element id to name).
      let emittedNames = Set.fromList [d.dcnName | d <- drgDecisions drg]
      [n.element | n <- ns, Set.member n.element emittedNames] `shouldBe` []
      -- the ~20 assert-only scenario fixtures are NOT rebind-dropped: the gate
      -- is the structural rebind property, never test-ness (the R12 tripwire).
      emittedNames `shouldSatisfy` Set.member "the base case qualifies"

    -- The §15.12 non-emission invariant, over every golden subject: no decide
    -- carrying D-RULEDATE-UNBOUND appears in the emitted decision population.
    -- (This replaces the retired two-message scoping test: with nothing
    -- emitted, there is no emitted logic for the claim to be scoped to.)
    it "never emits a decision that carries D-RULEDATE-UNBOUND (§15.12)" $
      forM_ goldenSubjects \(srcPath, stem, _) -> do
        src <- Text.readFile (examplesRoot </> srcPath)
        let drg   = drgAsCli srcPath src
            ns    = [n | n <- (dmnReport drg).notes, n.code == "D-RULEDATE-UNBOUND"]
            names = Set.fromList [d.dcnName | d <- drgDecisions drg]
        forM_ ns \n ->
          when (Set.member n.element names) $
            expectationFailure
              (stem <> ": D-RULEDATE-UNBOUND on " <> Text.unpack n.element
                 <> " but the decision was emitted anyway")

    describe "the ruledate-rebind fixture (§15.12)" $ do
      let rebindDrg = do
            src <- Text.readFile (examplesRoot </> "dmn" </> "not-ok" </> "ruledate-rebind.l4")
            pure (drgAsCli "ruledate-rebind.l4" src)

      it "drops the rebinding decides — plain AND WHERE-wrapped — with one Lossy note each" $ do
        drg <- rebindDrg
        let names = [d.dcnName | d <- drgDecisions drg]
        names `shouldNotSatisfy` elem "the fee under the 2016 rules"
        -- raw-body traversal parity: the old detection ran over the peeled
        -- body; the population predicate must see through WHERE too
        names `shouldNotSatisfy` elem "the fee under the 2019 rules, doubled"
        let ns = [n | n <- (dmnReport drg).notes, n.code == "D-RULEDATE-UNBOUND"]
        map (.severity) ns `shouldSatisfy` all (== Lossy)
        length ns `shouldBe` 3

      it "keeps the CALLER, whose dropped callee surfaces as an inputData" $ do
        drg <- rebindDrg
        let caller = decisionNamed "twice the 2016 fee" drg
            inputs = [i | NodeInputData i <- drg.drgNodes]
        [i.idId | i <- inputs, i.idName == "the fee under the 2016 rules"]
          `shouldBe` ["input_the_fee_under_the_2016_rules"]
        caller.dcnRequirements
          `shouldSatisfy` elem (RequiredInput "input_the_fee_under_the_2016_rules")
        -- no dangling edge: every requirement resolves to an emitted element
        let decisionIds = Set.fromList [d.dcnId | d <- drgDecisions drg]
            inputIds    = Set.fromList [i.idId | i <- inputs]
        forM_ [d | d <- drgDecisions drg] \d ->
          forM_ d.dcnRequirements \case
            RequiredDecision t -> Set.member t decisionIds `shouldBe` True
            RequiredInput t    -> Set.member t inputIds `shouldBe` True

      it "gives a fixture-shaped rebind ONLY the rebind drop, even unverified (§15.12)" $ do
        -- `the fixture-shaped rebind` satisfies FIXTURE(a)-(c) module-locally.
        -- With no importer view, the fixture filter would KEEP it with a
        -- report-only D-FIXTURE advisory — but the rebind gate is structural
        -- and unconditional, so it is dropped as a rebind, with no D-FIXTURE
        -- beside the drop and no second drop reason.
        src <- Text.readFile (examplesRoot </> "dmn" </> "not-ok" </> "ruledate-rebind.l4")
        let drg = drgGeneral emptyVFS (\o -> o { dloExternalRefNames = Nothing })
                    defaultDmnFlavor (const "Test") src
            notes = (dmnReport drg).notes
        [d.dcnName | d <- drgDecisions drg] `shouldNotSatisfy` elem "the fixture-shaped rebind"
        [n.code | n <- notes, n.element == "the fixture-shaped rebind"]
          `shouldBe` ["D-RULEDATE-UNBOUND"]

      it "still drops on --include-tests: the gate is structural, not test-ness" $ do
        src <- Text.readFile (examplesRoot </> "dmn" </> "not-ok" </> "ruledate-rebind.l4")
        let drg = drgAdjusted (\o -> o { dloIncludeTests = True }) src
        [d.dcnName | d <- drgDecisions drg] `shouldNotSatisfy` elem "the fee under the 2016 rules"
        [n.code | n <- (dmnReport drg).notes, n.element == "the fee under the 2016 rules"]
          `shouldBe` ["D-RULEDATE-UNBOUND"]

    describe "D-SVCEMPTY (the un-emitted decisionService, §15.12's companion)" $ do
      let svcEmptyDrg = do
            src <- Text.readFile (examplesRoot </> "dmn" </> "not-ok" </> "svc-empty-ruledate.l4")
            pure (drgAsCli "svc-empty-ruledate.l4" src)

      it "emits NO decisionService and one Advisory per un-emitted §, two message forms" $ do
        drg <- svcEmptyDrg
        [s | NodeService s <- drg.drgNodes] `shouldBe` []
        let ns = [n | n <- (dmnReport drg).notes, n.code == "D-SVCEMPTY"]
        map (.severity) ns `shouldSatisfy` all (== Advisory)
        -- arm (i): the § whose whole membership was rebind-dropped
        [n | n <- ns, n.element == "pinned_scenarios"] `shouldSatisfy` \arm ->
          length arm == 1
            && all (Text.isInfixOf "rule-date-rebinding" . (.message)) arm
        -- arm (ii): the kept-but-shapeless § (the previously silent D5 skip)
        [n | n <- ns, n.element == "fees"] `shouldSatisfy` \arm ->
          length arm == 1 && all (Text.isInfixOf "6.3.10" . (.message)) arm
        length ns `shouldBe` 2

      it "never lets D-FLAVOR-NOSERVICE name a service the artifact does not contain" $ do
        drg <- svcEmptyDrg
        [n | n <- (dmnReport drg).notes, n.code == "D-FLAVOR-NOSERVICE"] `shouldBe` []

      -- The 2026-08-02 widening, pinned on the corpus because the corpus is
      -- where both halves were measured false: arm (i) was rebind-only, which
      -- left the all-fixture `Group 6 — advertising (Rule 204)` exactly as
      -- silent as the silence the note exists to end; and arm (ii)'s
      -- unconditional lost-line claimed "its member decisions are all
      -- emitted" of three §s whose members the SAME report records as
      -- dropped (15 rebinds in the rule-version §, 4 fixtures in `Fixtures`,
      -- 1 uncalled regulative in §6).
      it "names the corpus's all-fixture § (Group 6) via arm (i)" $ do
        drg <- corpusDrg
        let ns = [n | n <- (dmnReport drg).notes, n.code == "D-SVCEMPTY"]
        [n | n <- ns, Text.isInfixOf "Group 6" n.message] `shouldSatisfy` \arm ->
          length arm == 1
            && all (Text.isInfixOf "test fixtures (D-FIXTURE" . (.message)) arm
            && all (Text.isInfixOf "no emitted member decisions" . (.message)) arm

      it "claims 'all emitted' ONLY of §s with no dropped members (the mixed lost-line)" $ do
        drg <- corpusDrg
        let ns = [n | n <- (dmnReport drg).notes, n.code == "D-SVCEMPTY"]
            claimsAll n = Text.isInfixOf "all emitted" n.lost
        -- the pure arm-(ii) §s keep the strong claim …
        sort [n.element | n <- ns, claimsAll n]
          `shouldBe` [ "Group_4_disclosure_Rule_201_t_boundaries_at_124_000_618_000_1_235_000"
                     , "Periods_every_deadline_bound_once"
                     , "Thresholds_every_dollar_figure_bound_once_dated_per_regime"
                     , "_2_Offering_limit_Rule_100_a_1"
                     ]
        -- … and every mixed § says instead how many decides were dropped,
        -- naming the note code that carries each member's own loss
        let mixed = [n | n <- ns, Text.isInfixOf "separately dropped" n.lost]
        sort [n.element | n <- mixed]
          `shouldBe` [ "Fixtures"
                     , "The_rule_version_axis_the_same_question_under_four_regimes"
                     , "_6_Advertising_restrictions_Rule_204"
                     ]
        [n.lost | n <- mixed, n.element == "Fixtures"]
          `shouldSatisfy` all (Text.isInfixOf "D-FIXTURE")
        [ n.lost
          | n <- mixed
          , n.element == "The_rule_version_axis_the_same_question_under_four_regimes"
          ] `shouldSatisfy` all (Text.isInfixOf "D-RULEDATE-UNBOUND")
        [n.lost | n <- mixed, n.element == "_6_Advertising_restrictions_Rule_204"]
          `shouldSatisfy` all (Text.isInfixOf "D-REGULATIVE")

    it "carries the @ref citation into the annotation column (§15.9)" $ do
      drg <- corpusDrg
      case (decisionNamed "offering maximum in a 12-month period" drg).dcnLogic of
        LogicTable t ->
          concatMap (.drAnnotations) t.dtRules `shouldSatisfy`
            any (Text.isInfixOf "86 FR 3496")
        LogicLiteral _ -> expectationFailure "expected the dated table"

        LogicContext _ -> expectationFailure "unexpected boxed context"
    ----------------------------------------------------------------------
    -- units under the above
    ----------------------------------------------------------------------
    it "renders a FEEL date literal and a half-open date interval" $ do
      renderFeelValue (VDate (fromGregorian 2024 1 1)) `shouldBe` "date(\"2024-01-01\")"
      renderUnaryTest
        (TestRange True (VDate (fromGregorian 1994 4 1)) (VDate (fromGregorian 2024 1 1)) False)
        `shouldBe` "[date(\"1994-04-01\")..date(\"2024-01-01\"))"

    -- dmnmd has no date datatype at all, so a date cell must be REFUSED rather
    -- than emitted and then misread by dmnmd's numeric parser.
    it "gives dmnmd no form for a date cell" $ do
      drg <- gstDrg
      let md = emitMarkdown drg
      md `shouldSatisfy` (not . Text.isInfixOf "date(")
      [ n.code
        | n <- (markdownReport drg).notes
        , n.code == "D-MD-CELLSYNTAX"
        ] `shouldSatisfy` (not . null)

  ----------------------------------------------------------------------
  -- The deontic verdict lowering (R13, spec §16)
  ----------------------------------------------------------------------
  describe "the deontic verdict lowering (R13, §16)" $ do
    let corpusDrg = do
          src <- Text.readFile (examplesRoot </> "legal" </> "regcf" </> "regcf.l4")
          pure (drgAsCli "regcf.l4" src)
        verdictDrg = do
          src <- Text.readFile (examplesRoot </> "dmn" </> "deontic-verdict.l4")
          pure (drgAsCli "deontic-verdict.l4" src)

    it "lowers the corpus reporting spine to a FIRST verdict table over its guards" $ do
      drg <- corpusDrg
      let dec = decisionNamed "ongoing reporting obligation" drg
      dec.dcnType `shouldBe` DmnString
      case dec.dcnLogic of
        LogicTable t -> do
          t.dtHitPolicy `shouldBe` HitFirst
          map (.feText) (map (.drOutput) t.dtRules)
            `shouldBe` [ "\"file a Form C-TR termination of reporting\""
                       , "\"fulfilled\""
                       , "\"file a Form C-AR annual report and continue\""
                       ]
          t.dtOutput.ocType `shouldBe` DmnString
          t.dtOutput.ocValues
            `shouldBe` Just [ "file a Form C-TR termination of reporting"
                            , "fulfilled"
                            , "file a Form C-AR annual report and continue"
                            ]
        _ -> expectationFailure "expected the verdict decision table"
      -- R13 × R11: the requirements are the GUARDS' survivors, nothing else —
      -- in particular no self-edge (the HENCE call does not survive) and no
      -- edge on the un-lifted callee's discarded argument.
      dec.dcnRequirements
        `shouldBe` [ RequiredDecision "decision_ongoing_reporting_obligation_may_terminate"
                   , RequiredInput "input_annual_cycles"
                   ]

    it "makes the corpus D-CYCLE disappear by construction, and empties Blocking" $ do
      drg <- corpusDrg
      let notes = (dmnReport drg).notes
      [n | n <- notes, n.code == "D-CYCLE"] `shouldBe` []
      -- the R0 headline: nothing in the corpus report is Blocking any more
      [(n.code, n.element) | n <- notes, n.severity == Blocking] `shouldBe` []
      [n.severity | n <- notes, n.code == "D-VERDICT"] `shouldBe` [Lossy]
      [n | n <- notes, n.code == "D-LITERALEXPR"
         , n.element == "decision_ongoing_reporting_obligation"] `shouldBe` []
      -- D-PARTIAL stays — it describes the L4 source — in its verdict-aware
      -- form, which must not claim raw-L4 call sites the artifact lost
      let partials = [n | n <- notes, n.code == "D-PARTIAL"]
      map (.element) partials `shouldBe` ["decision_ongoing_reporting_obligation"]
      map (.message) partials `shouldSatisfy`
        all (Text.isInfixOf "verdict decision table")
      map (.message) partials `shouldSatisfy`
        all (not . Text.isInfixOf "remain raw L4")

    it "pins every verdictOf spelling on the off-corpus exhibit" $ do
      drg <- verdictDrg
      let dec = decisionNamed "reporting duty" drg
      case dec.dcnLogic of
        LogicTable t -> do
          t.dtHitPolicy `shouldBe` HitFirst
          map (.feText) (map (.drOutput) t.dtRules)
            `shouldBe` [ "\"file the termination report\""
                       , "\"fulfilled\""
                       , "\"may publish a notice\""
                       , "\"must not advertise the offering\""
                       , "\"file the annual report and continue\""
                       ]
        _ -> expectationFailure "expected the verdict decision table"
      -- the HENCE self-call never becomes a self-edge
      dec.dcnRequirements `shouldNotSatisfy`
        elem (RequiredDecision "decision_reporting_duty")
      [n | n <- (dmnReport drg).notes, n.code == "D-CYCLE"] `shouldBe` []

    it "keeps the v1 scope: a RAND arm still refuses RegulativeBody" $ do
      drg <- verdictDrg
      case (decisionNamed "joint duty" drg).dcnLogic of
        LogicTable _ -> expectationFailure "a RAND arm was verdict-tabulated"
        _            -> pure ()
      [ n | n <- (dmnReport drg).notes
          , n.code == "D-LITERALEXPR"
          , n.element == "decision_joint_duty"
          , n.severity == Blocking
          , Text.isInfixOf "deontic (regulative) body" n.message
        ] `shouldSatisfy` ((== 1) . length)

    it "keeps the v1 scope: a bare deontic body is still NotAGuardedChain" $ do
      drg <- verdictDrg
      case (decisionNamed "bare duty" drg).dcnLogic of
        LogicTable _ -> expectationFailure "a bare deontic body was verdict-tabulated"
        _            -> pure ()
      [ n | n <- (dmnReport drg).notes
          , n.code == "D-LITERALEXPR"
          , n.element == "decision_bare_duty"
          , n.severity == Blocking
          , Text.isInfixOf "not a guarded chain" n.message
        ] `shouldSatisfy` ((== 1) . length)

  describe "Phase 4: un-lifting, DMN-SAFE, and the population filter" $ do
    let notesOf code drg = [n | n <- (dmnReport drg).notes, n.code == code]
        firstNote = \case
          (n : _) -> n
          []      -> error "expected at least one note"
        inputsNamed nm drg = [i | NodeInputData i <- drg.drgNodes, i.idName == nm]
        decisionNames drg = map (.dcnName) (drgDecisions drg)

    describe "tier 1: the un-lift (§2.1)" $ do
      -- fixture 1+4: two decisions sharing a GIVEN name, called by a third
      -- with identical argument expressions -> ONE inputData, bare FEEL call
      -- sites, requiredDecision edges, one D-PARAM-AS-INPUT.
      let tier1Merge =
            "DECLARE P HAS v IS A NUMBER\n\
            \GIVEN p IS A P\n\
            \GIVETH A NUMBER\n\
            \f1 p MEANS p's v PLUS 1\n\
            \GIVEN p IS A P\n\
            \GIVETH A NUMBER\n\
            \f2 p MEANS p's v TIMES 2\n\
            \GIVEN p IS A P\n\
            \GIVETH A NUMBER\n\
            \both p MEANS f1 p PLUS f2 p\n"

      it "merges same-named, same-typed parameters into one inputData" $ do
        let drg = drgOf tier1Merge
        length (inputsNamed "p" drg) `shouldBe` 1

      it "renders a saturated call to an un-lifted decision as its bare FEEL name" $ do
        let d = decisionNamed "both" (drgOf tier1Merge)
        case d.dcnLogic of
          LogicLiteral fe -> do
            fe.feText `shouldBe` "f1 + f2"
            fe.feFragment `shouldBe` SFeel
          _ -> expectationFailure "expected a boxed literal"

      it "keeps the requiredDecision edges classifyRef already emits" $ do
        let d = decisionNamed "both" (drgOf tier1Merge)
        d.dcnRequirements `shouldSatisfy`
          (\rs -> RequiredDecision "decision_f1" `elem` rs
               && RequiredDecision "decision_f2" `elem` rs)

      it "notes the loss once per merged group (D-PARAM-AS-INPUT, OPEN-3)" $ do
        let ns = notesOf "D-PARAM-AS-INPUT" (drgOf tier1Merge)
        map (.severity) ns `shouldBe` [Advisory]
        (firstNote ns).message `shouldSatisfy` Text.isInfixOf "`p`"

      -- the SINGLETON un-lift: no merge, but the call-site argument is
      -- discarded all the same — `a MEANS net 100` renders as the bare name
      -- `net` and the literal 100 vanishes, so gating D-PARAM-AS-INPUT on
      -- merged groups turned a Blocking verbatim call into a silently wrong
      -- number. One decision, one parameter, two identical applied sites.
      let singletonUnlift =
            "GIVEN amount IS A NUMBER\n\
            \GIVETH A NUMBER\n\
            \net amount MEANS amount TIMES 0.9\n\
            \GIVETH A NUMBER\n\
            \a MEANS net 100\n\
            \GIVETH A NUMBER\n\
            \b MEANS net 100\n"

      it "notes the discarded argument on a singleton un-lift (no merge required)" $ do
        let drg = drgOf singletonUnlift
            ns  = notesOf "D-PARAM-AS-INPUT" drg
        map (.severity) ns `shouldBe` [Advisory]
        (firstNote ns).message `shouldSatisfy` Text.isInfixOf "`amount`"
        (firstNote ns).message `shouldSatisfy` Text.isInfixOf "discarded"
        -- the un-lift itself still happens; the note is the record of its cost
        (decisionNamed "a" drg).dcnLogic `shouldSatisfy` \case
          LogicLiteral fe -> fe.feText == "net" && fe.feFragment == SFeel
          _               -> False

      it "stays silent on a vacuous singleton (zero applied call sites discard nothing)" $ do
        let drg = drgOf
              "GIVEN q IS A NUMBER\n\
              \GIVETH A NUMBER\n\
              \solo2 q MEANS q PLUS 1\n\
              \#EVAL solo2 5\n"
        notesOf "D-PARAM-AS-INPUT" drg `shouldBe` []

      -- fixture 2: ZERO non-directive call sites (27% of the measured
      -- population, §2.4.3) still un-lift, vacuously; the #EVAL is not a call
      -- site, and — being the directive's applied head — it also keeps the
      -- decision out of the fixture bucket (§2.5.7(c), fixture 20's negative).
      it "un-lifts a decision whose only reference is a directive (vacuous tier 1)" $ do
        let drg = drgOf
              "GIVEN q IS A NUMBER\n\
              \GIVETH A NUMBER\n\
              \solo q MEANS q PLUS 1\n\
              \#EVAL solo 5\n"
        length (inputsNamed "q" drg) `shouldBe` 1
        decisionNames drg `shouldBe` ["solo"]
        notesOf "D-FIXTURE" drg `shouldBe` []
        notesOf "D-BKM" drg `shouldBe` []

      -- fixture 3: directive polarity, both ways in one file. Two #ASSERTs
      -- apply `dbl` to two DIFFERENT argument expressions; one decision body
      -- applies it to one. Directives are excluded from tiering (§2.1 as
      -- amended by R6) so `dbl` is tier 1 — while the same directives are the
      -- fixture criterion's evidence, dropping `sample` (§2.5.7(b),(c)).
      it "excludes directives from tiering while the fixture verdict reads them as evidence" $ do
        let drg = drgOf
              "GIVEN n IS A NUMBER\n\
              \GIVETH A NUMBER\n\
              \dbl n MEANS n TIMES 2\n\
              \GIVETH A NUMBER\n\
              \use MEANS dbl 7\n\
              \GIVETH A NUMBER\n\
              \sample MEANS 42\n\
              \#ASSERT dbl 1 EQUALS 2\n\
              \#ASSERT dbl 2 EQUALS 4\n\
              \#ASSERT dbl sample EQUALS 84\n"
        -- tier 1: no BKM classification, and the body call renders bare
        notesOf "D-BKM" drg `shouldBe` []
        (decisionNamed "use" drg).dcnLogic `shouldSatisfy` \case
          LogicLiteral fe -> fe.feText == "dbl"
          _               -> False
        -- the same directives are FIXTURE evidence: `sample` is referenced
        -- only from their argument positions, so it is dropped and named
        decisionNames drg `shouldNotSatisfy` elem "sample"
        map (.element) (notesOf "D-FIXTURE" drg) `shouldBe` ["sample"]

    describe "tier 2: the real λ (§2.1)" $ do
      -- fixture 5. This WAS the Phase 5 tripwire ("when BKM emission lands,
      -- this test goes red — rewrite it against the BKM"), and it fired on
      -- 2026-08-01. Rewritten as instructed: the same source now pins the
      -- emission itself.
      let tier2Lambda =
            "GIVEN pot IS A NUMBER\n\
            \GIVETH A NUMBER\n\
            \half pot MEANS pot TIMES 0.5\n\
            \GIVETH A NUMBER\n\
            \a MEANS half 100\n\
            \GIVETH A NUMBER\n\
            \b MEANS half 200\n"

      it "emits two distinct argument shapes as a BKM (D-BKM), invoked by name" $ do
        let drg = drgOf tier2Lambda
            ns  = notesOf "D-BKM" drg
        map (.severity) ns `shouldBe` [Advisory]
        (firstNote ns).message `shouldSatisfy` Text.isInfixOf "`a`"
        (firstNote ns).message `shouldSatisfy` Text.isInfixOf "`b`"
        (firstNote ns).message `shouldSatisfy` Text.isInfixOf "emitted as a businessKnowledgeModel"
        -- the callee is a BKM whose logic is the old body, parameterised
        let bkm = bkmNamed "half" drg
        map (.fpName) bkm.bkmParams `shouldBe` ["pot"]
        -- the call sites render as FEEL named-argument invocations (probe A2),
        -- each caller carrying its own knowledgeRequirement edge (probe C3:
        -- required by KIE, silently nulled by Camunda without it)
        (decisionNamed "a" drg).dcnLogic `shouldSatisfy` \case
          LogicLiteral fe -> fe.feText == "half(pot: 100)" && fe.feFragment == FullFeel
          _               -> False
        (decisionNamed "a" drg).dcnKnowledgeReqs `shouldBe` [RequiredBkm "bkm_half"]
        (decisionNamed "b" drg).dcnKnowledgeReqs `shouldBe` [RequiredBkm "bkm_half"]
        -- `pot` is a formalParameter now, bound per call: NO inputData, no
        -- merge question at all
        length (inputsNamed "pot" drg) `shouldBe` 0
        notesOf "D-PARAM-AS-INPUT" drg `shouldBe` []
        -- and the emitted bytes carry the invariant the default flavor never
        -- checks (probe C4): element name == variable name
        emitDrg drg `shouldSatisfy`
          Text.isInfixOf "<businessKnowledgeModel id=\"bkm_half\" name=\"half\">"

    describe "D-PARTIAL: the DMN-SAFE side-condition (§2.4)" $ do
      -- fixtures 6+8, one adjacent pair: the SAME division is accepted when
      -- its guard travels in the same decision (one FEEL if) and refused when
      -- the guard lives in a different decision — which is exactly the
      -- configuration un-lifting would create.
      it "L3, strict: a split-off division is refused, and partiality is contagious" $ do
        let drg = drgOf
              "GIVEN\n\
              \  pot IS A NUMBER\n\
              \  n   IS A NUMBER\n\
              \GIVETH A NUMBER\n\
              \share pot n MEANS pot DIVIDED BY n\n\
              \GIVEN c IS A NUMBER\n\
              \GIVETH A BOOLEAN\n\
              \above c MEANS share c 4 GREATER THAN 10\n"
            ns = notesOf "D-PARTIAL" drg
        -- `share` itself: L3, Blocking (its one call site is strict)
        [n | n <- ns, n.element == "decision_share"]
          `shouldSatisfy` \case
            [n] -> n.severity == Blocking && Text.isInfixOf "L3" n.message
            _   -> False
        -- contagion: `above` calls a ¬DMN-SAFE decision and is itself refused
        [n | n <- ns, n.element == "decision_above"]
          `shouldSatisfy` \case
            [n] -> Text.isInfixOf "TOTAL" n.message
            _   -> False
        -- and the refusal wording (§2.4.4): not certified, never a remedy
        (firstNote ns).message `shouldSatisfy` Text.isInfixOf "could not be certified total"
        forM_ ns \n -> n.message `shouldNotSatisfy` Text.isInfixOf "@nonexhaustive"

      it "accepts the same division when the guard sits in the same decision" $ do
        let drg = drgOf
              "GIVEN\n\
              \  n IS A NUMBER\n\
              \  d IS A NUMBER\n\
              \GIVETH A NUMBER\n\
              \safediv n d MEANS IF d EQUALS 0 THEN 0 ELSE n DIVIDED BY d\n"
        notesOf "D-PARTIAL" drg `shouldBe` []
        length (inputsNamed "d" drg) `shouldBe` 1

      -- The §14.7 probe: a partial multi-clause pattern-matching group.
      -- Before OPEN-6 this exported clean (two Advisory notes, no D-PARTIAL,
      -- passed --fail-on blocking, answered null for Blue); the checker's
      -- clause-matrix warning now reaches L1 through the Decide-level channel
      -- (siClauseMatrixRanges). The DMN half of §14.7's regression pair — the
      -- l4-check half is ok/pattern-matching-partial-matrix.l4's golden.
      it "L1, clause matrix: a partial multi-clause group is refused (§14.7)" $ do
        let src =
              "DECLARE Colour IS ONE OF Red, Green, Blue\n\
              \GIVEN c IS A Colour\n\
              \GIVETH A NUMBER\n\
              \DECIDE `two clause partial` Red   IS 1\n\
              \DECIDE `two clause partial` Green IS 2\n"
            drg = drgOf src
        [n | n <- notesOf "D-PARTIAL" drg, n.element == "decision_two_clause_partial"]
          `shouldSatisfy` \case
            [n] ->
              n.severity == Blocking            -- a DRG root: no guard can fence the null
                && Text.isInfixOf "L1" n.message
                && Text.isInfixOf "multi-clause" n.message
            _ -> False
        -- Phase 4 classifies and reports; it does not change node kind: the
        -- two-rule table is still emitted.
        length (tableOf "two clause partial" src).dtRules `shouldBe` 2

      it "L1, clause matrix: the total three-clause variant is certified" $ do
        let drg = drgOf
              "DECLARE Colour IS ONE OF Red, Green, Blue\n\
              \GIVEN c IS A Colour\n\
              \GIVETH A NUMBER\n\
              \DECIDE `all three` Red   IS 1\n\
              \DECIDE `all three` Green IS 2\n\
              \DECIDE `all three` Blue  IS 3\n"
        notesOf "D-PARTIAL" drg `shouldBe` []

      -- fixture 7: the same partial decision consumed ONLY from a lazy
      -- position (an IF arm) is Lossy, not Blocking — the consumer's guard
      -- can fence the null.
      it "downgrades to Lossy when every consumer is lazy" $ do
        let drg = drgOf
              "GIVEN\n\
              \  pot IS A NUMBER\n\
              \  n   IS A NUMBER\n\
              \GIVETH A NUMBER\n\
              \share2 pot n MEANS pot DIVIDED BY n\n\
              \GIVEN c IS A NUMBER\n\
              \GIVETH A NUMBER\n\
              \guarded c MEANS IF c EQUALS 0 THEN 0 ELSE share2 100 c\n"
        [n | n <- notesOf "D-PARTIAL" drg, n.element == "decision_share2"]
          `shouldSatisfy` \case
            [n] -> n.severity == Lossy && Text.isInfixOf "lazy position" n.message
            _   -> False

      -- fixture 9: L11's accepting AND rejecting branches. No corpus
      -- exercises this (0 Proj sites over a multi-constructor enum across
      -- all 62 files), so both sides are synthetic — deliberately. `l4 check`
      -- says "Check succeeded" on the rejecting shape; the exporter must
      -- still refuse, because the selector application raises
      -- NonExhaustivePatterns at run time with no CONSIDER in sight.
      it "L11: refuses a projection over a multi-constructor enum missing the field" $ do
        let drg = drgOf
              "DECLARE Shape IS ONE OF\n\
              \    Circle HAS radius IS A NUMBER\n\
              \    Square HAS side   IS A NUMBER\n\
              \GIVEN s IS A Shape\n\
              \GIVETH A NUMBER\n\
              \`the radius` s MEANS s's radius\n"
        [n | n <- notesOf "D-PARTIAL" drg, Text.isInfixOf "L11" n.message]
          `shouldSatisfy` (not . null)

      -- The "every constructor declares the field" acceptance is DEFENSIVE:
      -- probing shows the checker rejects that shape as an ambiguous selector
      -- (two same-typed `size` definitions), so today the reachable accepting
      -- branch is the single-payload-constructor enum. Should the checker
      -- learn to disambiguate, the exporter's all-constructors test is
      -- already right.
      it "L11: accepts the projection on a single-payload-constructor enum" $ do
        let drg = drgOf
              "DECLARE Wrapped IS ONE OF\n\
              \    W HAS val IS A NUMBER\n\
              \GIVEN s IS A Wrapped\n\
              \GIVETH A NUMBER\n\
              \`the val` s MEANS s's val\n"
        notesOf "D-PARTIAL" drg `shouldBe` []

      -- fixture 10: L12. The WHERE-locals' mutual cycle typechecks (probed)
      -- and BlackholeForces at run time; the exporter refuses. This is also a
      -- robustness fix for the exporter itself, since Lower INLINES
      -- WHERE-locals.
      it "L12: refuses a WHERE-local dependency cycle" $ do
        let drg = drgOf
              "GIVEN n IS A NUMBER\n\
              \GIVETH A NUMBER\n\
              \loopy n MEANS y PLUS n\n\
              \  WHERE\n\
              \    y MEANS z PLUS 1\n\
              \    z MEANS y PLUS 1\n"
        [n | n <- notesOf "D-PARTIAL" drg, Text.isInfixOf "L12" n.message]
          `shouldSatisfy` (not . null)

      -- fixture 11: L7 at the TRANSITIVE granularity — the head type is a
      -- record; the function hides in a component, where runBinOpEquals's
      -- componentwise recursion finds it at run time.
      it "L7: refuses EQUALS at a record type with a function-typed field" $ do
        let drg = drgOf
              "DECLARE Policy HAS\n\
              \  name   IS A STRING\n\
              \  payout IS A FUNCTION FROM NUMBER TO NUMBER\n\
              \GIVEN\n\
              \  a IS A Policy\n\
              \  b IS A Policy\n\
              \GIVETH A BOOLEAN\n\
              \same a b MEANS a EQUALS b\n"
        [n | n <- notesOf "D-PARTIAL" drg, Text.isInfixOf "L7" n.message]
          `shouldSatisfy` (not . null)

      -- fixture 12, both sides — the structural TERMINATES check is
      -- untested against the corpora on both sides, so both live here.
      it "TERMINATES: accepts structural recursion through FOLLOWED BY" $ do
        let drg = drgOf
              "IMPORT prelude\n\
              \GIVEN xs IS A LIST OF NUMBER\n\
              \GIVETH A NUMBER\n\
              \total xs MEANS\n\
              \  CONSIDER xs\n\
              \  WHEN EMPTY THEN 0\n\
              \  WHEN x FOLLOWED BY rest THEN x PLUS total rest\n"
        notesOf "D-PARTIAL" drg `shouldBe` []

      it "TERMINATES: rejects NUMBER-measure recursion (a don't-know, not a proof)" $ do
        let drg = drgOf
              "GIVEN n IS A NUMBER\n\
              \GIVETH A NUMBER\n\
              \countdown n MEANS IF n EQUALS 0 THEN 0 ELSE countdown (n MINUS 1)\n"
        [n | n <- notesOf "D-PARTIAL" drg, Text.isInfixOf "TERMINATES" n.message]
          `shouldSatisfy` (not . null)

      -- TOTAL's contagion must not depend on declaration order. Forward
      -- references are legal L4 (`l4 check` accepts a caller defined before
      -- its callee), so a source-order fold silently certified any caller
      -- defined before its ¬DMN-SAFE callee — byte-identical logic, one
      -- D-PARTIAL in one order and two in the other. Both orders, one test.
      it "TOTAL: refuses a caller whichever side of its ¬DMN-SAFE callee it is defined on" $ do
        let calleeLast =
              "GIVEN x IS A NUMBER\n\
              \GIVETH A NUMBER\n\
              \caller x MEANS callee x\n\
              \GIVEN y IS A NUMBER\n\
              \GIVETH A NUMBER\n\
              \callee y MEANS 100 DIVIDED BY y\n"
            calleeFirst =
              "GIVEN y IS A NUMBER\n\
              \GIVETH A NUMBER\n\
              \callee y MEANS 100 DIVIDED BY y\n\
              \GIVEN x IS A NUMBER\n\
              \GIVETH A NUMBER\n\
              \caller x MEANS callee x\n"
        forM_ [calleeLast, calleeFirst] \src -> do
          let ns = notesOf "D-PARTIAL" (drgOf src)
          map (.element) ns `shouldMatchList` ["decision_caller", "decision_callee"]
          [n | n <- ns, n.element == "decision_caller"]
            `shouldSatisfy` \case
              [n] -> Text.isInfixOf "TOTAL" n.message
                       && Text.isInfixOf "`callee`" n.message
              _   -> False

      -- Mutual recursion: a two-cycle escapes 'selfRecursionIssues' (which
      -- only sees calls whose head is the decide's own Unique) and no fold
      -- order can see it — only the condensation can. Un-lifting the pair
      -- would emit mutually requiring <decision> elements (a DMN 1.3 §6.3.2
      -- acyclicity violation) with bare-FEEL-name call sites, silently.
      it "TERMINATES: rejects mutual recursion on every cycle member, and does not un-lift it" $ do
        let drg = drgOf
              "GIVEN n IS A NUMBER\n\
              \GIVETH A NUMBER\n\
              \ping n MEANS IF n LESS THAN 1 THEN 100 DIVIDED BY n ELSE pong (n MINUS 1)\n\
              \GIVEN n IS A NUMBER\n\
              \GIVETH A NUMBER\n\
              \pong n MEANS ping (n MINUS 1)\n"
            ns = notesOf "D-PARTIAL" drg
        map (.element) ns `shouldMatchList` ["decision_ping", "decision_pong"]
        forM_ ns \n -> do
          n.message `shouldSatisfy` Text.isInfixOf "TERMINATES"
          n.message `shouldSatisfy` Text.isInfixOf "mutually recursive"
          n.message `shouldSatisfy` Text.isInfixOf "could not be certified"
        -- the refusal keeps the call sites verbatim: no bare-name un-lift
        (decisionNamed "pong" drg).dcnLogic `shouldSatisfy` \case
          LogicLiteral fe -> fe.feFragment == L4Verbatim
          _               -> False

      -- fixture 13's wording assertion rides on the L3 test above.

    describe "the type-conflict refusal (D-PARAMTYPE, OPEN-4)" $ do
      -- fixture 14+17: the GCO-first-version.l4:157,164 shape — one GIVEN
      -- name at two declared types on two @export-style uncalled roots.
      -- Merging measured `null [SUCCEEDED]` with zero runtime messages on
      -- both engines, so the refusal is Blocking and D-SCOPE must still fire
      -- (the hazard of two same-folded names is real precisely because the
      -- merge did NOT happen).
      let conflictTwo =
            "DECLARE Art3 HAS x IS A NUMBER\n\
            \DECLARE Art7 HAS y IS A NUMBER\n\
            \GIVEN s IS AN Art3\n\
            \GIVETH A NUMBER\n\
            \art3 s MEANS s's x\n\
            \GIVEN s IS AN Art7\n\
            \GIVETH A NUMBER\n\
            \art7 s MEANS s's y\n"

      it "refuses the merge on a declared-type conflict, at Blocking, naming everyone" $ do
        let drg = drgOf conflictTwo
            ns  = notesOf "D-PARAMTYPE" drg
        map (.severity) ns `shouldBe` [Blocking]
        length (inputsNamed "s" drg) `shouldBe` 2
        (firstNote ns).message `shouldSatisfy` Text.isInfixOf "`Art3`"
        (firstNote ns).message `shouldSatisfy` Text.isInfixOf "`Art7`"
        (firstNote ns).message `shouldSatisfy` Text.isInfixOf "`art3`"
        (firstNote ns).message `shouldSatisfy` Text.isInfixOf "`art7`"
        -- D-SCOPE does not go quiet where the hazard is real (fixture 17)
        notesOf "D-SCOPE" drg `shouldSatisfy` (not . null)

      -- fixture 15: same name, same type -> merged, and NEITHER code fires.
      it "merges silently when the declared types agree" $ do
        let drg = drgOf
              "DECLARE Art3 HAS x IS A NUMBER\n\
              \GIVEN s IS AN Art3\n\
              \GIVETH A NUMBER\n\
              \art3a s MEANS s's x\n\
              \GIVEN s IS AN Art3\n\
              \GIVETH A NUMBER\n\
              \art3b s MEANS s's x PLUS 1\n"
        length (inputsNamed "s" drg) `shouldBe` 1
        notesOf "D-PARAMTYPE" drg `shouldBe` []
        notesOf "D-SCOPE" drg `shouldBe` []

      -- fixture 16: the anti-regression on the last-wins defect — A, B, A
      -- must name ALL THREE claimants and BOTH types, not "the last one
      -- wins". (The old freeTermTypes map was Unique-keyed and could not
      -- collide; a name-keyed merge built with Map.fromList would silently
      -- keep one claimant, which is the §7 defect this pins.)
      it "names all three claimants and both types on an A, B, A conflict" $ do
        let drg = drgOf
              "DECLARE A1 HAS x IS A NUMBER\n\
              \DECLARE B1 HAS y IS A NUMBER\n\
              \GIVEN s IS AN A1\n\
              \GIVETH A NUMBER\n\
              \first s MEANS s's x\n\
              \GIVEN s IS A B1\n\
              \GIVETH A NUMBER\n\
              \second s MEANS s's y\n\
              \GIVEN s IS AN A1\n\
              \GIVETH A NUMBER\n\
              \third s MEANS s's x PLUS 1\n"
            ns = notesOf "D-PARAMTYPE" drg
        length ns `shouldBe` 1
        forM_ ["`first`", "`second`", "`third`", "`A1`", "`B1`"] \frag ->
          (firstNote ns).message `shouldSatisfy` Text.isInfixOf frag
        length (inputsNamed "s" drg) `shouldBe` 3

      -- The untyped hole: an omitted GIVEN type is not a spelling, it is the
      -- ABSENCE of evidence. Comparing the sentinel "<untyped>" made two
      -- same-named untyped GIVENs of different INFERRED types (a NUMBER
      -- comparison in one decision, a BOOLEAN conjunction in the other)
      -- compare equal, merge into one typeRef=Any element, and silence both
      -- D-PARAMTYPE and D-SCOPE — `q` then read a NUMBER as its BOOLEAN and
      -- answered null/SUCCEEDED with zero notes on both engines.
      it "refuses to merge same-named UNTYPED parameters: no declared type certifies no agreement" $ do
        let drg = drgOf
              "GIVEN x\n\
              \GIVETH A BOOLEAN\n\
              \p1 x MEANS x GREATER THAN 10\n\
              \GIVEN x\n\
              \GIVETH A BOOLEAN\n\
              \q1 x MEANS x AND TRUE\n"
            ns = notesOf "D-PARAMTYPE" drg
        map (.severity) ns `shouldBe` [Blocking]
        (firstNote ns).message `shouldSatisfy` Text.isInfixOf "no declared type"
        (firstNote ns).message `shouldSatisfy` Text.isInfixOf "REFUSED"
        length (inputsNamed "x" drg) `shouldBe` 2
        -- and D-SCOPE keeps naming the two same-folded elements
        notesOf "D-SCOPE" drg `shouldSatisfy` (not . null)

      it "refuses a typed/untyped mix for the same reason" $ do
        let drg = drgOf
              "DECLARE A2 HAS v IS A NUMBER\n\
              \GIVEN s IS AN A2\n\
              \GIVETH A NUMBER\n\
              \typed s MEANS s's v\n\
              \GIVEN s\n\
              \GIVETH A BOOLEAN\n\
              \untyped s MEANS s AND TRUE\n"
            ns = notesOf "D-PARAMTYPE" drg
        map (.severity) ns `shouldBe` [Blocking]
        (firstNote ns).message `shouldSatisfy` Text.isInfixOf "`A2`"
        (firstNote ns).message `shouldSatisfy` Text.isInfixOf "no declared type"
        length (inputsNamed "s" drg) `shouldBe` 2

    describe "the population filter (§2.5.6, §2.5.7)" $ do
      -- fixture 18: FIXTURE positive, and --include-tests restores it.
      let fixtureSrc =
            "DECLARE R HAS v IS A NUMBER\n\
            \GIVEN r IS A R\n\
            \GIVETH A NUMBER\n\
            \rule r MEANS r's v\n\
            \GIVETH A R\n\
            \sample MEANS R OF 42\n\
            \#ASSERT rule sample EQUALS 42\n"

      it "drops a directive-argument-only decision as a fixture, with a note" $ do
        let drg = drgOf fixtureSrc
        decisionNames drg `shouldNotSatisfy` elem "sample"
        map (.element) (notesOf "D-FIXTURE" drg) `shouldBe` ["sample"]

      it "emits it anyway under --include-tests, with no note" $ do
        let drg = drgAdjusted (\o -> o { dloIncludeTests = True }) fixtureSrc
        decisionNames drg `shouldSatisfy` elem "sample"
        notesOf "D-FIXTURE" drg `shouldBe` []

      -- fixture 19: FIXTURE(b)'s negative — a decision referenced by NOTHING
      -- is kept (it is the inert-prose-carrier case, not a fixture; without
      -- (b) the rule would delete every unreferenced genuine root too).
      it "keeps a wholly unreferenced decision, flagging inert prose (D-INERT)" $ do
        let drg = drgOf
              "GIVETH A BOOLEAN\n\
              \`definition x` MEANS \"statutory text\" AND TRUE\n"
        decisionNames drg `shouldBe` ["definition x"]
        map (.severity) (notesOf "D-INERT" drg) `shouldBe` [Advisory]

      -- fixture 22's negative control: a body that reads one input is NOT
      -- inert — the predicate is "forces no reference and no input", which a
      -- Lit-shaped detector would pass trivially and this test would miss.
      it "does not flag a body that reads an input" $ do
        let drg = drgOf
              "GIVEN flag IS A BOOLEAN\n\
              \GIVETH A BOOLEAN\n\
              \live flag MEANS flag\n"
        notesOf "D-INERT" drg `shouldBe` []

      -- fixture 21: FIXTURE(d), the conjunct that stops the rule deleting a
      -- statute. `statute` satisfies (a)+(b)+(c) module-locally — exactly the
      -- `relevant date` shape — and the three importer views give the three
      -- ruled outcomes.
      let statuteSrc =
            "GIVEN n IS A NUMBER\n\
            \GIVETH A NUMBER\n\
            \wrap n MEANS n TIMES 2\n\
            \GIVEN n IS A NUMBER\n\
            \GIVETH A NUMBER\n\
            \statute n MEANS n PLUS 1\n\
            \#EVAL wrap (statute 1)\n"

      it "drops the statute-shaped decision only when the importer view clears it" $ do
        let drg = drgOf statuteSrc   -- harness default: Just Set.empty
        decisionNames drg `shouldNotSatisfy` elem "statute"

      it "keeps it when an importing module references it (conjunct (d))" $ do
        let drg = drgAdjusted
              (\o -> o { dloExternalRefNames = Just (Set.singleton "statute") })
              statuteSrc
        decisionNames drg `shouldSatisfy` elem "statute"
        notesOf "D-FIXTURE" drg `shouldBe` []

      it "fails safe when no importer view is available: kept, report-only advisory" $ do
        let drg = drgAdjusted
              (\o -> o { dloExternalRefNames = Nothing })
              statuteSrc
        decisionNames drg `shouldSatisfy` elem "statute"
        [n | n <- notesOf "D-FIXTURE" drg, Text.isInfixOf "NOT checked" n.message]
          `shouldSatisfy` (not . null)

      -- fixture 23: D-REGULATIVE, both directions. An uncalled regulative
      -- body routes to BPMN; a module-CALLED one stays in the DRG, still
      -- emitting raw L4 — rule 3 must not be read as closing §2.4.2's gap.
      let dutySrc =
            "DECLARE Actor IS ONE OF Buyer, Seller\n\
            \DECLARE Act IS ONE OF Pay, Deliver\n\
            \GIVETH A DEONTIC Actor Act\n\
            \`payment duty` MEANS\n\
            \  PARTY Buyer\n\
            \  MUST Pay\n\
            \  WITHIN 30\n\
            \  HENCE FULFILLED\n"

      it "drops an uncalled regulative body (D-REGULATIVE, Lossy)" $ do
        let drg = drgOf dutySrc
        decisionNames drg `shouldNotSatisfy` elem "payment duty"
        map (.severity) (notesOf "D-REGULATIVE" drg) `shouldBe` [Lossy]

      it "keeps a module-called regulative body, with no D-REGULATIVE" $ do
        let drg = drgOf
              (dutySrc
                 <> "GIVETH A DEONTIC Actor Act\n\
                    \another MEANS `payment duty`\n")
        decisionNames drg `shouldSatisfy` elem "payment duty"
        notesOf "D-REGULATIVE" drg `shouldBe` []

      -- fixture 24: closure orientation — fixture-side, computed BEFORE rule
      -- 3, which is the 46%-vs-74.6% distinction (§2.5.6).
      it "drops a helper called only from fixtures; keeps one also called live" $ do
        let helperSrc =
              "GIVEN n IS A NUMBER\n\
              \GIVETH A NUMBER\n\
              \helper n MEANS n PLUS 1\n\
              \GIVEN r IS A NUMBER\n\
              \GIVETH A NUMBER\n\
              \builder r MEANS helper r\n\
              \GIVEN n IS A NUMBER\n\
              \GIVETH A NUMBER\n\
              \mainrule n MEANS n TIMES 2\n\
              \#EVAL mainrule (builder 1)\n"
        decisionNames (drgOf helperSrc) `shouldNotSatisfy` elem "helper"
        -- Phase 5: kept-and-live `helper` has two distinct argument shapes, so
        -- it is now KEPT AS A BKM — the filter question (fixture-only vs live)
        -- is unchanged; the node kind it is kept as moved.
        let live = drgOf (helperSrc <> "GIVETH A NUMBER\nliveuse MEANS helper 5\n")
        map (.bkmName) (drgBkms live) `shouldSatisfy` elem "helper"

    -- §7.7: the 9th-constructor tripwire. 'UserEvalException' has exactly 8
    -- constructors, and every one is either foreclosed by a DMN-SAFE clause
    -- or deliberately NOT foreclosed. A ninth constructor makes the case
    -- below incomplete — under -Wall -Werror the WARNING is the alarm — and
    -- the count assertion is the belt to those braces. When it fires: add the
    -- constructor to the coverage map AND to L4.Dmn.Analysis, or record why
    -- it needs no clause.
    describe "the DMN-SAFE / UserEvalException coverage map (§2.4.1)" $ do
      it "accounts for every UserEvalException constructor" $ do
        let coveredBy :: UserEvalException -> Text
            coveredBy = \case
              NonExhaustivePatterns _     -> "L1, L2, L11"   -- L1+L2 alone do NOT cover it
              EqualityOnUnsupportedType _ _ -> "L7, transitively stated"
              DivisionByZero _            -> "L3"
              NotAnInteger _ _            -> "L4"
              UserError _                 -> "L4, L6, L8, L9, L10; JSON via PURE"
              BlackholeForced _           -> "L12"
              StackOverflow               -> "TERMINATES (a resource bound, not a clause)"
              Stuck _                     -> "deliberately NOT foreclosed: the ASSUME input channel"
            constructorCount = 8 :: Int
        -- the case above is TOTAL; -Werror's incomplete-pattern warning fires
        -- on a ninth constructor before this assertion ever runs
        coveredBy StackOverflow `shouldSatisfy` (not . Text.null)
        constructorCount `shouldBe` 8

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

  -- §13.6 at Phase 5: the kie flavor's split goldens, for the (measured)
  -- divergent subjects only. The default flavor keeps the unsuffixed names;
  -- never a diff-golden — each file is reproducible byte-for-byte by one
  -- `l4 export --flavor=kie` invocation and feedable to the KIE harness.
  describe "golden (kie flavor)" $ forM_ kieGoldenSubjects \(srcPath, stem, label) -> do
    it (label <> ", as DMN 1.3 XML (kie)") $
      goldenKieOf examplesRoot srcPath (stem <> ".kie.dmn") emitDrg
    it (label <> "'s fidelity report (kie)") $
      goldenKieOf examplesRoot srcPath (stem <> ".kie.fidelity.txt")
        (renderReport . dmnReport)

  -- R5 (§6.4): checkDrg + D-CYCLE over the informationRequirement graph, and
  -- the §6.4.4-2 self-edge un-suppression. Every expectation below was
  -- MEASURED on 2026-08-01 against this tree (the fixtures' own headers say
  -- their stated expectations were transcribed without a build and must be
  -- measured, not copied — this block is that measurement).
  describe "checkDrg / D-CYCLE (R5, §6.4)" $ do
    it "counts a one-member SCC only when it has a self-edge (§6.4.4-3)" $ do
      -- Both obvious defaults are wrong: literal "one per SCC" notes every
      -- acyclic node; "size >= 2" silently undoes the self-edge fix.
      let groups :: [(Text, Text, [Text])] -> [[Text]]
          groups = cyclicGroups
      groups [("a", "a", ["a"])] `shouldBe` [["a"]]
      groups [("a", "a", []), ("b", "b", ["a"])] `shouldBe` []

    let cycleNotesOf drg = [n | n <- drgNotesAll drg, n.code == "D-CYCLE"]
        notOkDrg fp = do
          src <- Text.readFile (examplesRoot </> "dmn" </> "not-ok" </> fp)
          pure (drgAsCli fp src)

    it "p1 (forward reference): genuinely acyclic, no D-CYCLE" $ do
      drg <- notOkDrg "cycle-p1-forward.l4"
      cycleNotesOf drg `shouldBe` []

    it "p2 (mutual recursion, nullary): one Blocking note naming both members by name AND id" $ do
      drg <- notOkDrg "cycle-p2-mutual-nullary.l4"
      case cycleNotesOf drg of
        [n] -> do
          n.severity `shouldBe` Blocking
          n.range `shouldBe` Nothing
          for_ [ "`the left total`", "decision_the_left_total"
               , "`the right total`", "decision_the_right_total" ] \needle ->
            n.message `shouldSatisfy` Text.isInfixOf needle
        ns -> expectationFailure ("expected exactly one D-CYCLE, got " <> show (length ns))

    it "p2 (mutual recursion, parameterised): D-CYCLE now, and stays the §6.3.9 arm's corpus for Phase 5" $ do
      -- MEASURED: the combined report carries one D-CYCLE (the requirement
      -- graph records the cycle) AND two Lossy D-PARTIAL ("mutually recursive
      -- with", every call site lazy) from Phase 4's SCC-ordered TOTAL pass —
      -- so neither decide is certified total, neither can become a BKM, and
      -- the knowledgeRequirement graph never carries this cycle. D-RECURSIVE
      -- (§6.3.9) therefore has no reachable L4 source shape today; it is
      -- exercised at the IR level instead (see the D-RECURSIVE block below).
      drg <- notOkDrg "cycle-p2-mutual-parameterised.l4"
      length (cycleNotesOf drg) `shouldBe` 1
      [n.severity | n <- drgNotesAll drg, n.code == "D-PARTIAL"]
        `shouldBe` [Lossy, Lossy]

    it "p3 (self-recursion): a one-member SCC said as 'requires itself' — REPORTED in the IR, ERASED from the XML" $ do
      -- Before §6.4.4-2 this exported with NO self-edge and advisory-only
      -- fidelity: freeRefs bound the decide's own name and classifyRef
      -- filtered target /= did, so the case §6.3.7 names FIRST was erased
      -- before any graph saw it.
      --
      -- §6.4.4-4a (ruled 2026-08-02) splits those two halves apart, and this
      -- test is where the split is pinned: the IR keeps the self-edge, so the
      -- Blocking note still fires and still names the decision; the XML does
      -- not, because DMN §7.3.1 forbids it and etc/validate-dmn.mjs rejects the
      -- file. Erasing the edge must never erase the finding — if the first
      -- assertion below ever goes quiet, the fix has become a cover-up.
      drg <- notOkDrg "cycle-p3-self.l4"
      case cycleNotesOf drg of
        [n] -> do
          n.message `shouldSatisfy` Text.isInfixOf "requires itself"
          n.message `shouldSatisfy` Text.isInfixOf "`countdown` (decision_countdown)"
        ns -> expectationFailure ("expected exactly one D-CYCLE, got " <> show (length ns))
      emitDrg drg `shouldNotSatisfy`
        Text.isInfixOf "<requiredDecision href=\"#decision_countdown\"/>"

    it "p2 (mutual recursion, nullary): a MULTI-node cycle keeps every edge — the §6.4.4-4a erasure is self-edges only" $ do
      -- The negative control for the test above. Dropping one edge of a 2-cycle
      -- would have to choose which member's meaning to change; §6.4.4-4 emits
      -- it as it is and reports it, and that is unchanged by the 2026-08-02
      -- ruling. If this ever goes red, the self-edge filter has widened.
      drg <- notOkDrg "cycle-p2-mutual-nullary.l4"
      let xml = emitDrg drg
      for_ [ "<requiredDecision href=\"#decision_the_left_total\"/>"
           , "<requiredDecision href=\"#decision_the_right_total\"/>" ] \needle ->
        xml `shouldSatisfy` Text.isInfixOf needle

    it "p4 (cycle through a WHERE-local, two decisions): D-CYCLE" $ do
      drg <- notOkDrg "cycle-p4-where-local.l4"
      length (cycleNotesOf drg) `shouldBe` 1

    it "p4-self (WHERE-local recursing on itself): NO cycle finding, by concession §6.4.5" $ do
      -- The only cycle is INSIDE one node; no SCC over the DRG can see it.
      -- This fixture is the concession's witness: it is caught today by
      -- D-PARTIAL (TERMINATES) and D-LITERALEXPR, which is luck, not a graph
      -- check. If a cycle finding ever appears here, the graph grew nodes it
      -- did not have — reread §6.4.5 before touching this test.
      drg <- notOkDrg "cycle-p4-where-local-self.l4"
      cycleNotesOf drg `shouldBe` []
      [n.code | n <- drgNotesAll drg, n.code `elem` ["D-PARTIAL", "D-LITERALEXPR"]]
        `shouldSatisfy` (not . null)

    it "p5 (cycle through a record computed field): the §6.4.5 obligation, re-measured — the hydrator closes it" $ do
      -- §6.4.2's table (measured pre-Phase-3) said "no — one direction only,
      -- Proj filtered". RE-MEASURED 2026-08-01 as §6.4.5 instructed: Phase
      -- 3.6's hydration rewiring (R11) turned the missing edge into a present
      -- one — the computed read folds onto the hydrator, the reading decision
      -- requires the hydrator, and the hydrator requires its source decision —
      -- so the cycle IS now in the DRG, with the hydrator as a member.
      drg <- notOkDrg "cycle-p5-computed-field.l4"
      case cycleNotesOf drg of
        [n] -> do
          n.message `shouldSatisfy` Text.isInfixOf "decision_the_assessed_total"
          n.message `shouldSatisfy` Text.isInfixOf "hydration_the_case_file"
        ns -> expectationFailure ("expected exactly one D-CYCLE, got " <> show (length ns))

    it "p6 (section-qualified mutual recursion): D-CYCLE, no longer advisory-only" $ do
      drg <- notOkDrg "cycle-p6-section-qualified.l4"
      length (cycleNotesOf drg) `shouldBe` 1

    it "p7 (nullary MEANS cycle): D-CYCLE" $ do
      drg <- notOkDrg "cycle-p7-means.l4"
      length (cycleNotesOf drg) `shouldBe` 1

    it "p8 (cycle through a guard): D-CYCLE, no longer '(nothing lost)'" $ do
      drg <- notOkDrg "cycle-p8-guard.l4"
      length (cycleNotesOf drg) `shouldBe` 1

    it "p9 (3-cycle among nullary decisions): one note, three members" $ do
      drg <- notOkDrg "cycle-p9-triangle.l4"
      case cycleNotesOf drg of
        [n] -> for_ ["`stage one`", "`stage two`", "`stage three`"] \needle ->
          n.message `shouldSatisfy` Text.isInfixOf needle
        ns -> expectationFailure ("expected exactly one D-CYCLE, got " <> show (length ns))

  -- §6.3.9 / §6.3-1: D-RECURSIVE, the SAME SCC routine over the SECOND graph
  -- (the knowledgeRequirement edges), and D-KNOWLEDGEREQ, the completeness
  -- assertion §13.3's consequence 2 makes mandatory (Camunda has no backstop:
  -- a missing edge is a silent null on the default flavor).
  --
  -- Exercised at the IR level, and the reason is itself a measurement: no L4
  -- source can currently reach a cyclic knowledgeRequirement graph, because a
  -- recursive or mutually recursive decide is never certified total (Phase
  -- 4's SCC-ordered TERMINATES pass), and §6.2's boundary keeps uncertified
  -- tier-2 decides OUT of the emitted-BKM set — cycle-p2-mutual-parameterised
  -- and cycle-p3 pin exactly that above (D-PARTIAL + D-CYCLE, no BKM). If a
  -- future totality certificate learns to bless a recursive decide, these
  -- tests are the contract its emission must meet.
  describe "checkDrg / D-RECURSIVE + D-KNOWLEDGEREQ (§6.3.9, §6.2)" $ do
    let testDrg ns = MkDrg
          { drgId = "definitions_t", drgName = "t"
          , drgNamespace = "ns", drgFlavor = FlavorCamunda
          , drgItemDefs = [], drgNodes = ns, drgNotes = []
          }
        lit frag t = LogicLiteral (MkFeelExpr t frag)
        bkmNode nm krs body = NodeBkm MkBkm
          { bkmId = "bkm_" <> nm, bkmName = nm, bkmFeelName = nm
          , bkmType = DmnNumber, bkmParams = [], bkmLogic = body
          , bkmKnowledgeReqs = krs
          }
        decNode nm krs body = NodeDecision MkDecision
          { dcnId = "decision_" <> nm, dcnName = nm, dcnFeelName = nm
          , dcnDecide = Nothing
          , dcnType = DmnNumber, dcnLogic = body
          , dcnRequirements = [], dcnKnowledgeReqs = krs
          }
        codesOf drg = [(n.code, n.element) | n <- checkDrg drg]

    it "a BKM that requires ITSELF — the case §6.3.9 names first — is a one-member SCC" $ do
      let drg = testDrg
            [bkmNode "f" [RequiredBkm "bkm_f"] (lit FullFeel "f(p: 1)")]
      case [n | n <- checkDrg drg, n.code == "D-RECURSIVE"] of
        [n] -> do
          n.severity `shouldBe` Blocking
          n.message `shouldSatisfy` Text.isInfixOf "requires itself"
          n.message `shouldSatisfy` Text.isInfixOf "`f` (bkm_f)"
        ns  -> expectationFailure ("expected one D-RECURSIVE, got " <> show (length ns))

    it "two BKMs requiring each other: one note, both members, decisions not implicated" $ do
      let drg = testDrg
            [ bkmNode "f" [RequiredBkm "bkm_g"] (lit FullFeel "g(p: 1)")
            , bkmNode "g" [RequiredBkm "bkm_f"] (lit FullFeel "f(p: 1)")
            , decNode "use" [RequiredBkm "bkm_f"] (lit FullFeel "f(p: 2)")
            ]
      case [n | n <- checkDrg drg, n.code == "D-RECURSIVE"] of
        [n] -> do
          n.message `shouldSatisfy` Text.isInfixOf "`f` (bkm_f)"
          n.message `shouldSatisfy` Text.isInfixOf "`g` (bkm_g)"
          n.message `shouldNotSatisfy` Text.isInfixOf "use"
        ns  -> expectationFailure ("expected one D-RECURSIVE, got " <> show (length ns))

    it "an acyclic decision→BKM→BKM chain (probe C1's shape) raises nothing" $ do
      let drg = testDrg
            [ bkmNode "inner" [] (lit SFeel "v * 10")
            , bkmNode "outer" [RequiredBkm "bkm_inner"] (lit FullFeel "inner(v: v)")
            , decNode "use" [RequiredBkm "bkm_outer"] (lit FullFeel "outer(v: n)")
            ]
      checkDrg drg `shouldBe` []

    it "a rendered invocation with NO edge on its owner is D-KNOWLEDGEREQ (probe C3's silent null)" $ do
      let drg = testDrg
            [ bkmNode "f" [] (lit SFeel "p + 1")
            , decNode "use" [] (lit FullFeel "f(p: 2)")
            ]
      codesOf drg `shouldBe` [("D-KNOWLEDGEREQ", "decision_use")]

    it "the completeness scan is token-bounded and skips verbatim texts" $ do
      let drg = testDrg
            [ bkmNode "f" [] (lit SFeel "p + 1")
            -- `affine(2)` CONTAINS "f" twice, neither at a token boundary
            -- with an open paren; the verbatim body spells a call-shaped
            -- `f (x)` but raw L4 is not FEEL and is skipped.
            , decNode "clean"    [] (lit FullFeel "affine(2)")
            , decNode "verbatim" [] (lit L4Verbatim "f (x) PLUS 1")
            ]
      checkDrg drg `shouldBe` []

    it "a `name(` inside a FEEL string literal is prose, not an invocation" $ do
      -- The false-positive shape found by review: the exporter generates
      -- string literals too (an L4 STRING constant renders as one), and this
      -- exact model runs green on BOTH engine harnesses — KIE 8.44.0.Final
      -- 0 errors 0 warnings, Camunda 8.7.6 parsed — so a Blocking note here
      -- fails `--fail-on blocking` on a fully valid artifact.
      let drg = testDrg
            [ bkmNode "half" [] (lit SFeel "p + 1")
            , decNode "note" [] (lit FullFeel "\"please call half(now) about this\"")
            ]
      checkDrg drg `shouldBe` []

    it "blanking a string literal (escapes included) does not blind the scan beside it" $ do
      -- One text, three lessons: the quoted decoy is skipped, the \" escape
      -- does not end the literal early, and the REAL invocation after the
      -- closing quote is still caught.
      let drg = testDrg
            [ bkmNode "f" [] (lit SFeel "p + 1")
            , decNode "use" [] (lit FullFeel "\"f(decoy) \\\" still inside\" + f(p: 2)")
            ]
      codesOf drg `shouldBe` [("D-KNOWLEDGEREQ", "decision_use")]

    it "the edge must be on the INVOKING node, not somewhere in the file (C2/C3's lesson)" $ do
      let drg = testDrg
            [ bkmNode "inner" [] (lit SFeel "v * 10")
            , bkmNode "outer" [] (lit FullFeel "inner(v: v)")
            -- the top-level caller carries BOTH edges — the flat shape
            -- bkm-chain-flat measured FAILING on both engines
            , decNode "use" [RequiredBkm "bkm_outer", RequiredBkm "bkm_inner"]
                (lit FullFeel "outer(v: n)")
            ]
      codesOf drg `shouldBe` [("D-KNOWLEDGEREQ", "bkm_outer")]

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
-- Four subjects, and the difference between them is the whole point:
--
-- * @dmn\/reg-cf.l4@ is the SHAPE exhibit — five decisions chosen so the
--   goldens show every outcome the exporter has, written module-level-scalar
--   (@ASSUME@) style because that is the program model DMN itself has. Its
--   figures are illustrative and its own header says so.
-- * @dmn\/gst-rate.l4@ is the DATED-REGIME exhibit — the smallest module that
--   exercises law time end to end (spec §15): two rule-date chains, one in the
--   PREDICATE idiom and one INLINE — and the inline one writes an arm against a
--   NAMED regime constant and an arm against a bare @Date d m y@, because those
--   are the two things an inline right-hand side may be and they reach different
--   code. Both lower to a single-column @UNIQUE@ table over
--   @RULES_EFFECTIVE_DATE@ with half-open date intervals, plus one downstream
--   arithmetic decision so a date is shown driving a number driving a number.
--   It is the only subject with an engine leg whose cases FEED DATES.
-- * @legal\/regcf\/regcf.l4@ is the REAL corpus — 1,241 lines and 102
--   decisions since the rule-version axis landed — written
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
  , ( "dmn" </> "gst-rate.l4"
    , "gst-rate"
    , "the dated-regime exhibit"
    )
  , ( "legal" </> "regcf" </> "regcf.l4"
    , "regcf-corpus"
    , "the Reg CF corpus"
    )
  , ( "dmn" </> "sumtype.l4"
    , "sumtype"
    , "the data-model exhibit"
    )
  , ( "dmn" </> "hydration.l4"
    , "hydration"
    , "the hydration exhibit"
    )
    -- The Phase 4 exhibit: one module holding, deliberately, one of each —
    -- a tier-1 merge (`basic monthly benefit`/`benefit cap`/`capped benefit`
    -- share one `claimant` inputData and call by bare FEEL name), a tier-2 λ
    -- (`scaled amount`, D-BKM), a type conflict (`s` at Article3Case vs
    -- Article7Case, D-PARAMTYPE, merge refused), a dropped test fixture
    -- (`sample claimant`, D-FIXTURE), an inert prose carrier
    -- (`definition — benefit`, D-INERT), an uncalled regulative body
    -- (`payment duty`, D-REGULATIVE), and a SINGLETON un-lift (`net payout`,
    -- whose discarded literal argument D-PARAM-AS-INPUT must name even
    -- though no merge happened).
  , ( "dmn" </> "unlift.l4"
    , "unlift"
    , "the Phase 4 un-lifting exhibit"
    )
    -- The Phase 5 exhibits. `bkm` holds one of each emission shape (multi-
    -- parameter BKM, BKM→BKM chain, BKM inside a hydrator, λ-lifted closure)
    -- and is flavor-IDENTICAL by measurement; `svc` isolates the ONE
    -- construct that splits the flavors (§-invocation, §13.5) and is the
    -- only subject with a `.kie.` golden pair — see the kie-flavor golden
    -- block below and each file's own header.
  , ( "dmn" </> "bkm.l4"
    , "bkm"
    , "the Phase 5 BKM exhibit"
    )
  , ( "dmn" </> "svc.l4"
    , "svc"
    , "the §-invocation exhibit"
    )
    -- The R13 exhibit (spec §16): the deontic verdict lowering, off-corpus —
    -- one chain exercising every `verdictOf` spelling, plus the two negative
    -- controls that pin the v1 scope (RAND arm; bare deontic body).
  , ( "dmn" </> "deontic-verdict.l4"
    , "deontic-verdict"
    , "the deontic-verdict exhibit"
    )
  ]

-- | The `.kie.` golden pairs (§13.6): ONLY the subjects whose bytes actually
-- diverge by flavor. Measured 2026-08-01 over every golden subject: reg-cf,
-- gst-rate, regcf-corpus, sumtype, hydration, unlift and bkm are all
-- byte-IDENTICAL at both flavors (nothing in them invokes a §; BKM emission
-- is flavor-ungated), so they keep unsuffixed goldens only, and the
-- flavor-divergence test asserts that identity stays true. `svc` diverges by
-- construction and gets the split pair.
kieGoldenSubjects :: [(FilePath, FilePath, String)]
kieGoldenSubjects =
  [ ( "dmn" </> "svc.l4"
    , "svc"
    , "the §-invocation exhibit"
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

-- | 'goldenOf' at the KIE flavor: what `l4 export --to=dmn --flavor=kie FILE`
-- writes, with the same model-name precedence.
goldenKieOf :: FilePath -> FilePath -> FilePath -> (Drg -> Text) -> IO (Golden Text)
goldenKieOf examplesRoot srcPath name render = do
  src <- Text.readFile (examplesRoot </> srcPath)
  let drg = drgFlavoredWith FlavorKie
              (\m -> fromMaybe (Text.pack (takeBaseName srcPath)) (moduleTitle m))
              src
  pure (mkGolden examplesRoot name (render drg))

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

  LogicContext _ -> False
------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------

drgOf :: Text -> Drg
drgOf = drgNamed "Test"

-- | Lower a source at the default flavor, INSISTING that L4 accepted it first.
drgNamed :: Text -> Text -> Drg
drgNamed = drgFlavored defaultDmnFlavor

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
--
-- __There is exactly one of these__, taking the flavor and the model-naming
-- function as parameters; everything else in this file is a partial
-- application of it. The flavor helper was briefly a second copy without the
-- @tcdErrors@ guard, which put the hole above straight back — and put it
-- precisely under the byte-identity tripwire, where a fixture that stopped
-- typechecking would degrade /both/ sides equally, keep the equality true, and
-- let the one test whose job is to announce Phase 5 go green on garbage.
drgFlavoredWith :: DmnFlavor -> (Module Resolved -> Text) -> Text -> Drg
drgFlavoredWith = drgGeneral emptyVFS id

-- | The one general helper 'drgFlavoredWith' promises to be, extended for
-- Phase 4 with a VFS (so a two-module fixture can exercise @FIXTURE(d)@) and
-- an options adjuster (so a fixture can flip @--include-tests@ or supply an
-- importer view). The Phase 4 defaults mirror the CLI:
--
--   * 'dloMissingMatchRanges' is extracted from the SAME check result the
--     module came from, by the same pattern @jl4\/app\/L4\/Cli\/Export.hs@
--     uses, so the two cannot drift on what "the checker warned" means;
--   * 'dloExternalRefNames' is @Just Set.empty@ — a VFS fixture's universe is
--     closed, so "no importers" is a FACT here, where the CLI has to scan for
--     it. A fixture that wants the fail-safe path passes
--     @Nothing@ through the adjuster.
drgGeneral
  :: VFS
  -> (DmnLowerOptions -> DmnLowerOptions)
  -> DmnFlavor
  -> (Module Resolved -> Text)
  -> Text
  -> Drg
drgGeneral vfs adjust flavor mkName src = case checkWithImports vfs src of
  Left errs -> error ("source failed to parse: " <> show errs)
  Right tc
    | errs@(_ : _) <- filter ((== SError) . TC.severity) tc.tcdErrors ->
        error
          ( "source failed to typecheck: "
              <> Text.unpack (Text.unlines (concatMap TC.prettyCheckErrorWithContext errs))
          )
    | otherwise ->
        lowerModule
          ( adjust
              MkDmnLowerOptions
                { dloModelName    = mkName tc.tcdModule
                , dloSubstitution = tc.tcdSubstitution
                , dloFlavor       = flavor
                -- Resolved from the SAME check result, by the SAME function the
                -- CLI uses (jl4/app/L4/Cli/Export.hs). If these two ever stopped
                -- agreeing, a golden would move without any source moving.
                , dloMaybePredicates =
                    resolveMaybePredicates tc.tcdModule tc.tcdEnvironment tc.tcdEntityInfo
                , dloIncludeTests = False
                , dloMissingMatchRanges =
                    [ r
                    | e@(TC.MkCheckErrorWithContext (TC.CheckWarning (TC.PatternMatchesMissing _)) _) <-
                        tc.tcdErrors
                    , Just r <- [rangeOf e]
                    ]
                -- L1's Decide-level channel (clause matrices), extracted by
                -- the same comprehension as the CLI (jl4/app/L4/Cli/Export.hs)
                , dloClauseMatrixRanges =
                    [ r
                    | e@(TC.MkCheckErrorWithContext (TC.CheckWarning (TC.PatternClausesMissing {})) _) <-
                        tc.tcdErrors
                    , Just r <- [rangeOf e]
                    ]
                , dloExternalRefNames = Just Set.empty
                }
          )
          tc.tcdModule

-- | Phase 4 fixtures: the default lowering with an options adjuster.
drgAdjusted :: (DmnLowerOptions -> DmnLowerOptions) -> Text -> Drg
drgAdjusted adjust = drgGeneral emptyVFS adjust defaultDmnFlavor (const "Test")

-- | As 'drgFlavoredWith', with a fixed model name.
drgFlavored :: DmnFlavor -> Text -> Text -> Drg
drgFlavored flavor name = drgFlavoredWith flavor (const name)

-- | As 'drgNamed', at the default flavor, with the model name computed from the
-- checked module.
drgWith :: (Module Resolved -> Text) -> Text -> Drg
drgWith = drgFlavoredWith defaultDmnFlavor

itemDefNamed :: Text -> Drg -> ItemDefinition
itemDefNamed nm drg = case [i | i <- drg.drgItemDefs, i.idfName == nm] of
  (i : _) -> i
  []      -> error ("no itemDefinition named " <> show nm)

-- | A rule's first (and, on a rule-date interval table, only) input cell.
headTest :: DmnRule -> UnaryTest
headTest r = case r.drInputs of
  (t : _) -> t
  []      -> error ("rule " <> show r.drId <> " has no input cell")

decisionNamed :: Text -> Drg -> Decision
decisionNamed nm drg = case [d | d <- drgDecisions drg, d.dcnName == nm] of
  (d : _) -> d
  []      -> error ("no decision named " <> show nm)

bkmNamed :: Text -> Drg -> Bkm
bkmNamed nm drg = case [b | b <- drgBkms drg, b.bkmName == nm] of
  (b : _) -> b
  []      -> error ("no businessKnowledgeModel named " <> show nm)

tableOf :: Text -> Text -> DecisionTable
tableOf nm src = case (decisionNamed nm (drgOf src)).dcnLogic of
  LogicTable t   -> t
  LogicLiteral e -> error ("expected a decision table for " <> show nm <> ", got: " <> show e.feText)

  LogicContext _ -> error "expected a decision table, got a boxed context"
-- | The decision must stay a table: the select-idiom peephole must not fire.
mustNotBeSelect :: Text -> Text -> Expectation
mustNotBeSelect nm src = do
  let drg = drgOf src
  case (decisionNamed nm drg).dcnLogic of
    LogicTable _   -> pure ()
    LogicLiteral e -> expectationFailure ("select idiom fired on " <> show nm <> ": " <> show e.feText)
    LogicContext _ -> expectationFailure "unexpected boxed context"
  emitDrg drg `shouldSatisfy` (\x -> not (Text.isInfixOf "max(" x) && not (Text.isInfixOf "min(" x))

cellTexts :: DmnRule -> [Text]
cellTexts r = map renderUnaryTest r.drInputs
