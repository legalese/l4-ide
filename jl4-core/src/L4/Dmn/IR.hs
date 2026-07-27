-- | A DMN 1.3-shaped intermediate representation.
--
-- This is the target IR for Track D1 of the Lexipedia-superset programme
-- (@specs\/todo\/lexipedia-superset\/SPEC.md@). 'L4.Dmn.Lower' produces it from a
-- typechecked @Module Resolved@ by way of "L4.Viz.GuardedRows"; 'L4.Dmn.Emit'
-- renders it to DMN 1.3 XML. Nothing here knows about XML.
--
-- The shape follows the OMG DMN 1.3 metamodel closely enough that the emitter is
-- a transcription rather than a translation:
--
--   * a 'Drg' is a @\<definitions\>@ — the /decision requirements graph/;
--   * a 'Decision' is a @\<decision\>@, carrying either a 'DecisionTable' or a
--     'LiteralExpression' as its 'DecisionLogic';
--   * a 'DecisionTable' is a @\<decisionTable\>@ with 'InputColumn's, one
--     'OutputColumn' and 'DmnRule's;
--   * every /cell/ on the input side is a 'UnaryTest' (DMN §8.2.5) applied to its
--     column's input expression, and every cell on the output side is a 'FeelExpr'
--     (DMN §8.2.9: "a rule output entry is an expression").
--
-- __The fidelity types are not an afterthought.__ DMN's analysis lineage —
-- completeness and consistency checking since Montalbano (1962), inter-tabular
-- checking since 1998, cross-DRD SMT verification since 2022 — is defined over
-- __S-FEEL__, the /simple/ fragment, with constant outputs. The DMN specification
-- itself (§9.1) says "few if any complete decision models can be defined using
-- S-FEEL" and tells you to use full FEEL instead. So the fragment you can verify
-- is not the fragment you are told to write
-- (@specs\/research\/DMN-STEELMAN.md@ §2.5). Every 'FidelityNote' this exporter
-- emits is one located, named instance of that gap in a real file: /here/ is where
-- your table left the analysable fragment, and /this/ is the capability you gave
-- up by leaving it.
module L4.Dmn.IR
  ( -- * Decision tables
    DecisionTable (..)
  , DmnRule (..)
  , HitPolicy (..)
  , hitPolicyAttr
  , InputColumn (..)
  , OutputColumn (..)
    -- * Cells
  , UnaryTest (..)
  , CmpOp (..)
  , FeelValue (..)
  , FeelExpr (..)
  , FeelFragment (..)
  , DmnType (..)
  , dmnTypeAttr
    -- * FEEL surface syntax
  , renderUnaryTest
  , renderFeelValue
  , renderNumber
  , quoteFeelString
  , feelIdentText
  , oneLine
    -- * Engine flavors
  , DmnFlavor (..)
  , defaultDmnFlavor
  , dmnFlavorName
    -- * The decision requirements graph
  , Drg (..)
  , DrgNode (..)
  , Decision (..)
  , DecisionLogic (..)
  , InputData (..)
  , Requirement (..)
  , requirementTarget
  , drgDecisions
  , drgInputData
    -- * Fidelity
    -- $fidelity
  , FidelityLoss (..)
  , renderFidelityLoss
  , drgNotesAll
  , dmnReport
  ) where

import Base
import qualified Base.Text as Text
import Data.Char (isAlphaNum, isAscii, isDigit)
import Data.Ratio (denominator, numerator)

import L4.Interchange.Fidelity (FidelityNote (..), FidelityReport, addNote, emptyReport)

------------------------------------------------------------------------
-- Cells
------------------------------------------------------------------------

-- | The FEEL built-in types we target. DMN 1.3 spells these unprefixed in a
-- @typeRef@ (the @feel:@ prefix was a DMN 1.1 artifact). 'DmnAny' is the honest
-- answer when L4's inferred type is an inference variable or something FEEL has
-- no analogue for (a record, a list of records, an algebraic data type).
data DmnType = DmnNumber | DmnString | DmnBoolean | DmnDate | DmnAny
  deriving stock (Eq, Show, Generic)

dmnTypeAttr :: DmnType -> Text
dmnTypeAttr = \case
  DmnNumber  -> "number"
  DmnString  -> "string"
  DmnBoolean -> "boolean"
  DmnDate    -> "date"
  DmnAny     -> "Any"

-- | A /constant/ FEEL value: the only thing this exporter will ever put on the
-- endpoint of a 'UnaryTest'.
--
-- That restriction is deliberate and is the exporter's central conservatism.
-- S-FEEL's @endpoint@ production also admits a qualified name, so @income@ would
-- be a legal cell on a column whose input expression is @limit@ — but no
-- decision-table analyser can place a variable endpoint on an axis, and a reader
-- cannot tell at a glance whether the cell is a value or a reference. A guard we
-- cannot reduce to a constant endpoint therefore becomes its own boolean column
-- instead (see 'GuardNotDecomposable'), which is always sound.
data FeelValue
  = VNum !Rational
  | VStr !Text
  | VBool !Bool
  deriving stock (Eq, Ord, Show, Generic)

data CmpOp = OpLt | OpLeq | OpGt | OpGeq
  deriving stock (Eq, Ord, Show, Generic)

-- | An input cell (DMN §8.2.5). Applied to its column's input expression.
--
-- Every constructor here is inside S-FEEL's @simple unary tests@ grammar, so the
-- /cells/ this exporter emits never leave the analysable fragment. Only the
-- /input expression/ can, which is why 'InputColumn' is where the fidelity
-- question lives.
data UnaryTest
  = TestAny
    -- ^ @-@: "the input is irrelevant for the containing rule" (§8.2.5). A DMN
    -- rule is therefore a /cube/, not a minterm — which is why @n@ conditions do
    -- not cost @2^n@ rows.
  | TestEq !FeelValue
    -- ^ a bare endpoint, which DMN reads as equality.
  | TestCmp !CmpOp !FeelValue
    -- ^ @>= 100@ and friends.
  | TestRange !Bool !FeelValue !FeelValue !Bool
    -- ^ @[lo..hi]@ — the two 'Bool's are /closed/ flags for the low and high ends.
  | TestOneOf ![UnaryTest]
    -- ^ a comma-separated list, which DMN reads as disjunction. Never empty, and
    -- never nested inside itself. __Its elements must be positive__: S-FEEL's
    -- @simple unary tests@ production allows @not(...)@ only around the whole
    -- cell, so @1, not(2)@ is not legal and must never be constructed.
  | TestNot !UnaryTest
    -- ^ @not(...)@.
  deriving stock (Eq, Show, Generic)

-- | Which FEEL fragment a rendered expression lies in. This is the whole fidelity
-- signal, and it is a property of the /input expression/ (and of output entries),
-- never of a 'UnaryTest'.
data FeelFragment
  = SFeel
    -- ^ Inside S-FEEL (@simple expression = arithmetic expression | simple value |
    -- comparison@, DMN grammar rule 3). Everything DMN can statically analyse
    -- lives here.
  | FullFeel
    -- ^ Valid FEEL, but outside S-FEEL: a function invocation, a boolean
    -- connective, an @if@. Legal, executable, and outside every published
    -- decision-table analysis result.
  | L4Verbatim
    -- ^ We could not render it as FEEL at all, so the text is L4 source. Honest,
    -- and not executable by a DMN engine.
  deriving stock (Eq, Ord, Show, Generic)

-- | A rendered FEEL expression: its text, and our claim about which fragment it
-- is in. Used for input expressions and for output entries.
data FeelExpr = MkFeelExpr
  { feText     :: !Text
  , feFragment :: !FeelFragment
  }
  deriving stock (Eq, Show, Generic)

------------------------------------------------------------------------
-- FEEL surface syntax
------------------------------------------------------------------------

-- | A cell, as DMN's @\<text\>@ content. Every form here is S-FEEL @simple unary
-- tests@ (DMN grammar rules 13–17).
renderUnaryTest :: UnaryTest -> Text
renderUnaryTest = \case
  TestAny        -> "-"
  TestEq v       -> renderFeelValue v
  TestCmp op v   -> cmpText op <> " " <> renderFeelValue v
  TestOneOf ts   -> Text.intercalate ", " (map renderUnaryTest ts)
  TestNot t      -> "not(" <> renderUnaryTest t <> ")"
  TestRange lc lo hi hc ->
    (if lc then "[" else "(") <> renderFeelValue lo
      <> ".." <> renderFeelValue hi <> (if hc then "]" else ")")
 where
  cmpText = \case
    OpLt  -> "<"
    OpLeq -> "<="
    OpGt  -> ">"
    OpGeq -> ">="

renderFeelValue :: FeelValue -> Text
renderFeelValue = \case
  VNum r  -> renderNumber r
  VStr t  -> quoteFeelString t
  VBool b -> if b then "true" else "false"

-- | A FEEL string literal. FEEL strings are double-quoted with Java-style
-- escapes (DMN grammar rule 62).
quoteFeelString :: Text -> Text
quoteFeelString t = "\"" <> Text.concatMap esc t <> "\""
 where
  esc = \case
    '\\' -> "\\\\"
    '"'  -> "\\\""
    '\n' -> "\\n"
    '\r' -> "\\r"
    '\t' -> "\\t"
    c    -> Text.singleton c

-- | Render a rational as a clean FEEL numeric literal. Integers print bare;
-- fractions that terminate in base 10 print as decimals; anything else prints as
-- an exact division, so no precision is silently lost. (FEEL numbers are
-- @decimal@ with 34 digits of precision, so an inexact literal would be a silent
-- semantic change.)
--
-- __Caveat.__ The @(n \/ d)@ form is an arithmetic /expression/, which S-FEEL
-- allows in an output entry but not as a unary-test /endpoint/. It cannot arise
-- from an endpoint today, because every 'VNum' this exporter builds comes from a
-- decimal 'NumericLit' and therefore terminates. Anyone constructing a
-- 'FeelValue' by hand should keep that invariant.
renderNumber :: Rational -> Text
renderNumber r
  | d == 1    = sign <> tshow (abs n)
  | otherwise = case terminating (abs n) d of
      Just t  -> sign <> t
      Nothing -> "(" <> tshow n <> " / " <> tshow d <> ")"
 where
  n    = numerator r
  d    = denominator r
  sign = if n < 0 then "-" else ""

  terminating num den =
    let places = countFactors 2 den `max` countFactors 5 den
    in if stripFactors 5 (stripFactors 2 den) == 1
         then Just (format places (num * (10 ^ places) `div` den))
         else Nothing

  countFactors p x = go (0 :: Integer) x
    where go acc y | y `mod` p == 0 && y /= 0 = go (acc + 1) (y `div` p)
                   | otherwise                = acc
  stripFactors p x | x `mod` p == 0 && x /= 0 = stripFactors p (x `div` p)
                   | otherwise                = x
  format places scaled
    | places == 0 = tshow scaled
    | otherwise =
        let s             = Text.justifyRight (fromIntegral places + 1) '0' (tshow scaled)
            (whole, frac) = Text.splitAt (Text.length s - fromIntegral places) s
        in whole <> "." <> frac

  tshow :: Show a => a -> Text
  tshow = Text.pack . show

-- | An L4 name as a FEEL name.
--
-- Every place a name is /referenced/ (an input expression, an output entry) and
-- every place one is /declared/ (an @inputData@ or @decision@ node and its
-- @\<variable\>@) goes through this same function, so the two always agree.
--
-- __Spaces and dots do not survive__, and that is a correctness fix rather than
-- a portability preference (@specs\/todo\/DMN-EXPORT-PROGRAM-MODEL-SPEC.md@
-- §5.2, §13.2). FEEL names may contain spaces (grammar rule 30) and KIE, feelin
-- and @dmn-eval-js@ all honour that — but Camunda's @feel-scala@ does not, and
-- it fails in the /silent/ direction: @annual income@ is tokenised as
-- @annual@ @in@ @come@, i.e. as the membership operator, and answers a
-- __boolean__ rather than the number. That is measured, not inferred: in a
-- model declaring @annual income = 100000@, @annual = 5@ and @come = [1,2,5]@,
-- Camunda 8.7.6 answers @true@ to both @annual income@ and @annual in come@,
-- while KIE 8.44 answers @100000@ and @true@ respectively (§13.2). Note the
-- value: @true@, not @null@ — a wrong /non-null/ answer, which is why the
-- engine harnesses under @etc\/@ compare against expected values and not merely
-- against null. (The boolean is whatever the membership test yields, so it is
-- the /type/ of the answer that is the tell, not the constant @false@ an
-- earlier draft of this comment named.) A dot is worse still, because it
-- injects a FEEL path expression that silently shadows a genuine record
-- projection.
--
-- This is stage 1 of §5.2's policy, minus three parts that belong to Phase 2
-- and are deliberately __not__ done here: NFC normalisation, the reserved-word
-- suffix, and @uniquifyIn@ (which is what makes the mapping injective within a
-- scope, and which needs a whole-DRG traversal rather than a per-name
-- function). Until then two L4 names can still collapse onto one FEEL name. The
-- emitter pairs every mangled @\@name@ with a verbatim @\@label@ so a reader can
-- always see which L4 name a node came from, and 'L4.Dmn.Lower' raises a
-- @D-FEELNAME@ note, at 'Blocking', when a collision actually happens — because
-- on Camunda 8 a collision is a silently wrong answer rather than a rejection.
feelIdentText :: Text -> Text
feelIdentText t
  | Text.null squashed           = "_"
  | isDigit (Text.head squashed) = "_" <> squashed
  | otherwise                    = squashed
 where
  -- Every non-ASCII-alphanumeric becomes '_', INCLUDING whitespace, so a run of
  -- whitespace becomes a run of '_' and is then collapsed by `squashed` along
  -- with every other run. Two L4 names an engine would read as one therefore
  -- cannot come out of here looking distinct. (An earlier draft pre-collapsed
  -- whitespace with `Text.unwords . Text.words`; that was a no-op for every
  -- input, since `squashed` already does the collapsing and the trimming, and
  -- it read as a load-bearing step. Removed rather than left to mislead.)
  underscored = Text.map keep t
  -- Collapse runs of '_' and strip them from both ends, in one pass.
  squashed = Text.intercalate "_" (filter (not . Text.null) (Text.splitOn "_" underscored))
  keep c
    | isAscii c && isAlphaNum c = c
    | otherwise                 = '_'

------------------------------------------------------------------------
-- Decision tables
------------------------------------------------------------------------

-- | The two hit policies this exporter emits.
--
-- The choice is forced by "L4.Viz.GuardedRows"' @grDisjoint@ and by what survives
-- the decomposition into columns:
--
--   * 'HitUnique' (@U@) when no two rules can both match. DMN calls @U@ and @A@
--     and @P@ order-/free/ (§8.2.10), so the table reads as a truth table.
--   * 'HitFirst' (@F@) otherwise. @F@ is order-/semantic/: the first matching rule
--     wins, which is exactly L4's first-match @BRANCH@. DMN's own warning applies
--     and we repeat it in the fidelity report: "the table is hard to validate
--     manually and therefore has to be used with care."
--
-- Note what is /not/ here: @C@ (Collect). L4's guarded chains are single-hit by
-- construction, and Collect tables are outside every published analysis result
-- anyway (Semantic DMN restricts itself to single-hit policies; KIE skips gap and
-- overlap analysis for COLLECT).
data HitPolicy = HitUnique | HitFirst
  deriving stock (Eq, Show, Generic)

hitPolicyAttr :: HitPolicy -> Text
hitPolicyAttr = \case
  HitUnique -> "UNIQUE"
  HitFirst  -> "FIRST"

-- | One column of a decision table. The @label@ is what a human reads; the
-- @expr@ is the FEEL that is evaluated once for the whole table and then tested
-- by each rule's cell.
--
-- That "once for the whole table" is why an effectful guard bails out entirely
-- rather than becoming a column: see 'EffectfulGuard'.
data InputColumn = MkInputColumn
  { icId    :: !Text
  , icLabel :: !Text     -- ^ the L4 source text of the column's subject
  , icExpr  :: !FeelExpr
  , icType  :: !DmnType
  }
  deriving stock (Eq, Show, Generic)

-- | The single output column — a restriction of __this exporter__, not of L4.
--
-- An L4 decision may perfectly well return several values, by returning a
-- record: @GIVETH A Assessment@ with branches building @Assessment WITH …@, or
-- (as the Charities corpus actually does) @GIVETH A MAYBE Part6Penalty@ with
-- branches returning @JUST \<named constant\>@. DMN likewise permits several
-- @\<output\>@ clauses per table, and 'BUILD-SPEC-dmnmd-to-l4.md' §1.4 already
-- handles the inverse direction by synthesising a record.
--
-- What is missing is the forward lowering: a record-valued decision currently
-- collapses to one @Any@-typed column whose entry is L4 source text rather than
-- FEEL. See @specs\/todo\/DMN-EXPORT-PROGRAM-MODEL-SPEC.md@.
--
-- @ocDefault@ is the @\<defaultOutputEntry\>@, which DMN supports precisely for
-- the single-hit order-free policies. It is where @OTHERWISE@ goes under 'HitUnique';
-- under 'HitFirst' @OTHERWISE@ becomes a final all-@-@ rule instead.
data OutputColumn = MkOutputColumn
  { ocId      :: !Text
  , ocName    :: !Text
  , ocType    :: !DmnType
  , ocDefault :: !(Maybe FeelExpr)
  }
  deriving stock (Eq, Show, Generic)

-- | One rule: a cell per input column (in column order), and one output entry.
data DmnRule = MkDmnRule
  { drId          :: !Text
  , drInputs      :: ![UnaryTest]   -- ^ same length and order as 'dtInputs'
  , drOutput      :: !FeelExpr
  , drDescription :: !(Maybe Text)  -- ^ the L4 source text of the row's guard
  }
  deriving stock (Eq, Show, Generic)

data DecisionTable = MkDecisionTable
  { dtId        :: !Text
  , dtName      :: !Text
  , dtHitPolicy :: !HitPolicy
  , dtInputs    :: ![InputColumn]
  , dtOutput    :: !OutputColumn
  , dtRules     :: ![DmnRule]
  , dtNotes     :: ![FidelityNote]
    -- ^ non-fatal fidelity losses incurred while building /this/ table. A fatal
    -- one is a 'FidelityLoss' and means there is no table at all.
  }
  deriving stock (Eq, Show, Generic)

------------------------------------------------------------------------
-- Engine flavors
------------------------------------------------------------------------

-- | Which DMN engine the emitted document is aimed at.
--
-- __One bit, and it is narrower than "which engine do you use".__ The three
-- axes R7 nominated were measured against Drools\/KIE 8.44.0.Final, Camunda
-- 7.23\/7.24 and Camunda 8.7.6, and two of them turned out not to diverge at all
-- (@specs\/todo\/DMN-EXPORT-PROGRAM-MODEL-SPEC.md@ §13):
--
--   * __naming__ (§13.2) — one policy is right everywhere. The apparent split
--     was two of our own bugs, fixed in 'feelIdentText' and "L4.Dmn.Emit".
--   * __business knowledge models__ (§13.3) — KIE and Camunda 8 both execute
--     them in every probed form. Only Camunda 7 is silently BKM-less, and
--     Camunda 7 is end-of-life and not a target.
--   * __decision services__ (§13.4) — the one real divergence, and not "does
--     the engine support them": a bare @\<decisionService\>@ is inert-but-safe
--     everywhere. What Camunda 8 cannot take is a @\<knowledgeRequirement\>@
--     whose @requiredKnowledge@ points at one, which makes its @parse()@ throw
--     @ClassCastException@ and reject the __whole file__ before any decision
--     runs. KIE runs that shape correctly, and it is the shape an invocable @§@
--     needs.
--
-- So the bit exists to answer exactly one question: may a @decisionService@ be
-- the target of a @knowledgeRequirement@? 'FlavorKie' says yes, 'FlavorCamunda'
-- says no and routes such call sites elsewhere.
--
-- __Nothing observable turns on it yet.__ Neither construct is emitted today
-- (that is Phase 5), so the two flavors are byte-identical, and
-- @jl4\/tests\/DmnExport.hs@ pins that identity as a test which is /expected/ to
-- fail the day Phase 5 lands. A knob with no effect is a trap; a test that
-- announces the day it acquires one is the cheapest defence.
data DmnFlavor
  = FlavorCamunda
    -- ^ Camunda 8 (@io.camunda:zeebe-dmn@ → dmn-scala + feel-engine), the
    -- default. Chosen because @specs\/todo\/lexipedia-superset\/SPEC.md@ K4
    -- commits the BPMN side to Camunda Modeler import — a DMN file a Camunda
    -- user cannot open breaks the pairing — and because the failure modes are
    -- unequal: this flavor on KIE is degraded but sound, the other on Camunda
    -- loads nothing at all.
  | FlavorKie
    -- ^ Drools\/KIE. Not Camunda 7: that is an unrelated implementation which
    -- cannot execute a BKM at all, and it is end-of-life.
  deriving stock (Eq, Show, Generic)

defaultDmnFlavor :: DmnFlavor
defaultDmnFlavor = FlavorCamunda

-- | The spelling the CLI accepts and the fidelity report prints.
dmnFlavorName :: DmnFlavor -> Text
dmnFlavorName = \case
  FlavorCamunda -> "camunda"
  FlavorKie     -> "kie"

------------------------------------------------------------------------
-- The decision requirements graph
------------------------------------------------------------------------

-- | An information requirement: DMN §6.2.2.1 allows these "from Input Data
-- elements to Decisions, and from Decisions to other Decisions".
data Requirement
  = RequiredDecision !Text  -- ^ the target 'dcnId'
  | RequiredInput !Text     -- ^ the target 'idId'
  deriving stock (Eq, Ord, Show, Generic)

requirementTarget :: Requirement -> Text
requirementTarget = \case
  RequiredDecision t -> t
  RequiredInput t    -> t

-- | What a decision's logic is. DMN calls both of these /boxed expressions/.
--
-- 'LogicLiteral' is not a failure mode to be ashamed of: a decision whose body is
-- not a guarded chain (an arithmetic formula, a plain conjunction, a deontic rule)
-- has no decision-table shape, and DMN's answer for that is a
-- @\<literalExpression\>@. Silently dropping such a decision would leave the DRG
-- describing a different rule set than the module does.
data DecisionLogic
  = LogicTable !DecisionTable
  | LogicLiteral !FeelExpr
  deriving stock (Eq, Show, Generic)

data Decision = MkDecision
  { dcnId           :: !Text
  , dcnName         :: !Text
  , dcnType         :: !DmnType
  , dcnLogic        :: !DecisionLogic
  , dcnRequirements :: ![Requirement]  -- ^ sorted by target id, for determinism
  }
  deriving stock (Eq, Show, Generic)

-- | A free term: a @GIVEN@ parameter, an @ASSUME@d term, or any other name the
-- module does not itself decide.
data InputData = MkInputData
  { idId   :: !Text
  , idName :: !Text
  , idType :: !DmnType
  }
  deriving stock (Eq, Show, Generic)

data DrgNode
  = NodeDecision !Decision
  | NodeInputData !InputData
  deriving stock (Eq, Show, Generic)

data Drg = MkDrg
  { drgId        :: !Text
  , drgName      :: !Text
  , drgNamespace :: !Text
  , drgFlavor    :: !DmnFlavor
    -- ^ which engine this graph was lowered /for/. It lives on the IR rather
    -- than on the emitter's argument list so that 'L4.Dmn.Emit.emitDrg',
    -- 'L4.Dmn.Markdown.emitMarkdown', 'dmnReport' and
    -- 'L4.Dmn.Markdown.markdownReport' all stay one-argument functions over one
    -- IR, and so that the fidelity report can name the artifact it describes.
  , drgNodes     :: ![DrgNode]
  , drgNotes     :: ![FidelityNote]  -- ^ module-level notes; per-table ones live on the table
  }
  deriving stock (Eq, Show, Generic)

drgDecisions :: Drg -> [Decision]
drgDecisions drg = [d | NodeDecision d <- drg.drgNodes]

drgInputData :: Drg -> [InputData]
drgInputData drg = [i | NodeInputData i <- drg.drgNodes]

------------------------------------------------------------------------
-- Fidelity
------------------------------------------------------------------------

-- $fidelity
--
-- Per-note accumulation uses the /shared/ 'L4.Interchange.Fidelity.FidelityNote',
-- not a DMN-local record: the DMN and BPMN backends have one @--fidelity-report@
-- output shape between them, so the CLI does not have to reconcile two
-- near-identical types. (Duplicating that knowledge would be the exact bug this
-- programme is a critique of.)
--
-- DMN\'s note codes are all prefixed @D-@ so they cannot collide with BPMN\'s
-- @F1@–@F5@ in a combined report. They are documented at their construction
-- sites in "L4.Dmn.Lower" and "L4.Dmn.Markdown".
--
-- 'FidelityLoss' is the separate, /fatal/ question: not "what did this table
-- give up" but "is there a table at all".

-- | Why a guarded chain could not become a decision table at all. The caller\'s
-- recourse is a @\<literalExpression\>@, never silence.
data FidelityLoss
  = NotAGuardedChain
    -- ^ the body is not @IF@ \/ @BRANCH@ \/ @CONSIDER@, so there are no rows.
  | NoRules
    -- ^ a chain with no rows at all (e.g. a @CONSIDER@ whose only arm binds).
  | EffectfulGuard
    -- ^ a guard performs I\/O. A DMN input expression is evaluated /once for the
    -- whole table/, whereas @BRANCH@ short-circuits, so tabulating would change
    -- how often the effect runs.
  | RegulativeBody
    -- ^ a row\'s body is a deontic rule. DMN "has no notion of time" (Callewaert &
    -- Vennekens, TPLP 2024) and cannot hold an obligation as a state.
  | RowsElided
    -- ^ the normaliser dropped a @CONSIDER@ arm as inert and there is no
    -- @OTHERWISE@ to cover the inputs it used to catch. That is sound for the
    -- ladder, where a missing disjunct is FALSE; it is /not/ sound for DMN,
    -- where an unmatched input yields __null__.
  | UninlinableLocal
    -- ^ a @WHERE@ \/ @LET@ local could not be inlined (it takes parameters, or its
    -- body performs I\/O), so the chain cannot be flattened into a closed table.
  deriving stock (Eq, Show, Generic)

renderFidelityLoss :: FidelityLoss -> Text
renderFidelityLoss = \case
  NotAGuardedChain -> "not a guarded chain (IF / BRANCH / CONSIDER), so it has no rows"
  NoRules          -> "a guarded chain with no expressible rows"
  EffectfulGuard   -> "a guard performs I/O; a DMN input expression is evaluated once per table, not per rule"
  RegulativeBody   -> "a deontic (regulative) body: DMN has no notion of time or obligation"
  RowsElided       ->
    "an inert CONSIDER arm was elided with no OTHERWISE to cover it; \
    \a DMN table would answer null where the rule answers FALSE"
  UninlinableLocal ->
    "a WHERE/LET local could not be inlined (parameterised, or effectful)"

-- | Every note in a 'Drg': the module-level ones, then each table\'s own, in
-- decision order.
drgNotesAll :: Drg -> [FidelityNote]
drgNotesAll drg =
  drg.drgNotes
    <> [ note
       | NodeDecision d <- drg.drgNodes
       , LogicTable t <- [d.dcnLogic]
       , note <- t.dtNotes
       ]

-- | The XML backend\'s report.
--
-- The target names the /flavor/, not just the notation, because the report is
-- generated from the same 'Drg' the document is: a report that did not say which
-- engine the artifact beside it was shaped for would be describing a file the
-- reader cannot identify.
dmnReport :: Drg -> FidelityReport
dmnReport drg =
  foldl' (flip addNote) (emptyReport target) (drgNotesAll drg)
 where
  target = "DMN 1.3 (XML), " <> dmnFlavorName drg.drgFlavor <> " flavor"

-- | Collapse newlines and runs of whitespace. A DMN cell is a one-liner, and an
-- SVG @\<text\>@ collapses newlines to spaces anyway — better to do it where it
-- can be seen than to let a renderer do it silently.
oneLine :: Text -> Text
oneLine = Text.unwords . Text.words
