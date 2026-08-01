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
  , dmnTypeBase
    -- * The data model
  , ItemDefinition (..)
  , ItemComponent (..)
    -- * FEEL surface syntax
  , renderUnaryTest
  , renderFeelValue
  , renderNumber
  , quoteFeelString
  , feelIdentText
  , feelTypeNameText
  , reservedFeelWords
  , reservedFeelTypeNames
  , uniquifyIn
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
  , ContextEntry (..)
  , InputData (..)
  , Requirement (..)
  , requirementTarget
  , drgDecisions
  , drgInputData
    -- * Fidelity
    -- $fidelity
  , FidelityLoss (..)
  , renderFidelityLoss
  , fidelityLossCode
  , drgNotesAll
  , dmnReport
    -- * Well-formedness (R5)
  , checkDrg
  , cyclicGroups
  ) where

import Base
import qualified Base.Text as Text
import qualified Data.Graph as Graph
import qualified Data.Set as Set
import Data.Char (isAlphaNum, isAscii, isDigit)
import Data.Ratio (denominator, numerator)
import Data.Time.Calendar (Day, showGregorian)

import L4.Interchange.Fidelity
  (FidelityNote (..), FidelityReport, FidelitySeverity (..), addNote, emptyReport)

------------------------------------------------------------------------
-- Cells
------------------------------------------------------------------------

-- | The FEEL built-in types we target. DMN 1.3 spells these unprefixed in a
-- @typeRef@ (the @feel:@ prefix was a DMN 1.1 artifact). 'DmnAny' is the honest
-- answer when L4's inferred type is an inference variable or something FEEL has
-- no analogue for (a list, an open sum, a type declared in another module).
--
-- 'DmnNamed' is a reference to an 'ItemDefinition' this module minted (§4.1,
-- §4.2): a record or an @IS ONE OF@ declared in the module being lowered. It
-- carries __both__ the minted FEEL type name and the builtin the definition is
-- /based on/ — @DmnString@ for an enum (whose values serialise as strings),
-- @DmnAny@ for a record (whose definition is a context, and has no base
-- @typeRef@ at all).
--
-- The base is on the constructor rather than only on the 'ItemDefinition'
-- because a consumer that has no notion of named types still has to say
-- something: "L4.Dmn.Markdown" maps a @typeRef@ into dmnmd's four-type grammar,
-- and without the base an enum column — which was @string@ before item
-- definitions existed and is @string@-backed after — would start reporting a
-- type collapse it does not have.
data DmnType = DmnNumber | DmnString | DmnBoolean | DmnDate | DmnAny
             | DmnNamed !Text !DmnType
  deriving stock (Eq, Show, Generic)

dmnTypeAttr :: DmnType -> Text
dmnTypeAttr = \case
  DmnNumber    -> "number"
  DmnString    -> "string"
  DmnBoolean   -> "boolean"
  DmnDate      -> "date"
  DmnAny       -> "Any"
  DmnNamed t _ -> t

-- | The FEEL builtin a type stands on, for consumers that cannot carry a named
-- type. The identity on every builtin.
dmnTypeBase :: DmnType -> DmnType
dmnTypeBase = \case
  DmnNamed _ base -> base
  t               -> t

------------------------------------------------------------------------
-- The data model
------------------------------------------------------------------------

-- | One field of a record's @itemDefinition@ (DMN §7.3.3: a @tItemDefinition@
-- whose components are themselves @tItemDefinition@s).
--
-- Two names, for the reason 'Decision' has two: 'icmName' is the resolved FEEL
-- name — the same string "L4.Dmn.Lower" emits as the path step of a projection,
-- taken from the same @uniquifyIn@ scope (§5.2 scope 2), so a component and the
-- @r.f@ that reads it cannot disagree — and 'icmLabel' is the verbatim L4 field
-- name.
data ItemComponent = MkItemComponent
  { icmId    :: !Text
  , icmName  :: !Text
  , icmLabel :: !Text
  , icmType  :: !DmnType
  }
  deriving stock (Eq, Show, Generic)

-- | A @\<itemDefinition\>@: the type-level half of the export (§4.1, §4.2).
--
-- Three shapes, and DMN spells them all with the same element:
--
--   * a __record__ — @idfBase = Nothing@, @idfValues = Nothing@, one
--     'ItemComponent' per /stored/ field. FEEL contexts are records, so this is
--     the tightest correspondence in the exercise.
--   * an __@IS ONE OF@__ — @idfBase = Just DmnString@ (its values serialise as
--     strings, since FEEL has no sum types) and @idfValues@ listing every
--     constructor in declaration order, which is what §7.3.3 calls "the
--     complete range of values that this ItemDefinition represents".
--   * a __domain-free alias__ of one of those — @idfBase = Just DmnString@ and
--     @idfValues = Nothing@ — which is what a @MAYBE τ@ site points at when τ
--     has a domain (§11-R8-a's carve-out). It spells no nullability, because
--     @tItemDefinition@ cannot; it exists so that R8-b's suppression of the
--     range /at the element/ is not undone by the @typeRef@ hop, since §7.3.3
--     reads the range off whatever the @typeRef@ resolves to. "L4.Dmn.Lower"
--     mints one per domain-carrying type at most, and only where an element
--     actually points at it.
--
-- __Scalars get none__ (§4.3): an alias over @number@ adds no information and
-- degrades for any consumer that does not resolve @typeRef@s. A @MAYBE NUMBER@
-- gets no optional alias either, and for the same reason — a builtin asserts no
-- range, so there is none to keep the hop from re-asserting.
data ItemDefinition = MkItemDefinition
  { idfId         :: !Text
  , idfName       :: !Text            -- ^ 'feelTypeNameText' + 'uniquifyIn'
  , idfLabel      :: !Text            -- ^ the verbatim L4 type name
  , idfBase       :: !(Maybe DmnType) -- ^ the @\<typeRef\>@ CHILD element, if any
  , idfValues     :: !(Maybe [Text])  -- ^ @\<allowedValues\>@, in declaration order
  , idfComponents :: ![ItemComponent]
  }
  deriving stock (Eq, Show, Generic)

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
-- __'VDate' is appended last on purpose.__ The derived 'Ord' is consulted by
-- nothing that cares about the cross-constructor order, but appending keeps the
-- relative order of the three that existed before, so no @Set FeelValue@
-- anywhere reorders.
data FeelValue
  = VNum !Rational
  | VStr !Text
  | VBool !Bool
  | VDate !Day
    -- ^ a FEEL @date@. Rendered @date("YYYY-MM-DD")@, which DMN 1.3 grammar rule
    -- 21 calls a @date time literal@ and rule 33 admits as a @simple literal@ —
    -- so it is a legal S-FEEL unary-test ENDPOINT, which is the whole reason a
    -- chain of rule-date guards can become an analysable interval table.
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
  -- DMN 1.3 grammar rule 21: a `date time literal` is ("date"|"time"|...) "("
  -- string ")". Rule 33 makes it a `simple literal`, hence a legal endpoint.
  -- MEASURED on both engines via jl4/tests-cli/fixtures/dmn-date-probe.
  VDate d -> "date(\"" <> Text.pack (showGregorian d) <> "\")"

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
-- This is the whole of stage 1 of §5.2's policy __except step 1 (NFC
-- normalisation)__, which is deferred with its reason recorded in §5.3.3: under
-- fold, NFC is defence-in-depth rather than load-bearing, @jl4-core.cabal@ has
-- no normalisation dependency, and the library must survive the @arch(wasm32)@
-- branch. Step 6, the reserved-word suffix, is applied here ('reservedFeelWords').
--
-- Stage 1 is deliberately __non-injective__: two distinct L4 names can still
-- fold onto one FEEL name. What makes the composite injective within a scope is
-- stage 2, 'uniquifyIn', which needs a whole-DRG traversal rather than a
-- per-name function and therefore lives at the call site in "L4.Dmn.Lower". The
-- emitter pairs every mangled @\@name@ with a verbatim @\@label@ so a reader can
-- always see which L4 name a node came from.
feelIdentText :: Text -> Text
feelIdentText = suffixReserved . foldFeelName

-- | An L4 __type__ name as a FEEL type name — the name an @itemDefinition@
-- carries and a @typeRef@ refers to (§5.1-2, §5.3.6).
--
-- It is 'feelIdentText'\'s character map plus the same reserved-word suffix, and
-- it is a __separate function__ because it names a separate thing and lives in a
-- separate 'uniquifyIn' scope: DMN keeps the itemDefinition-name namespace apart
-- from the variable namespace, so a type and a variable may share a name without
-- either being renamed.
--
-- __Dot policy (ruled, §5.3.6).__ A @.@ in a type name folds to @_@, identically
-- to 'feelIdentText'. DMN reserves @.@ in a @typeRef@ QName for the /import
-- prefix/, and this exporter emits no @\<import\>@ — so a dot passed through
-- would manufacture a reference to an import that does not exist.
--
-- __The two functions have already diverged__, and this is where: a type name
-- is checked against 'reservedFeelTypeNames', which is 'reservedFeelWords' plus
-- FEEL's __built-in type spellings__. A variable may be called @number@; a
-- @typeRef@ may not, because @typeRef=\"number\"@ already means FEEL's numeric
-- type. See 'reservedFeelTypeNames' for the collision this prevents.
feelTypeNameText :: Text -> Text
feelTypeNameText = suffixReservedIn reservedFeelTypeNames . foldFeelName

-- | §5.2 stage 1 step 6. FEEL's literal terminal symbols, as DMN 1.3 grammar
-- rules 28-30 and §10.3.1.4 spell them: __lower case__.
--
-- Matching is therefore case-sensitive, and that is the ruling rather than an
-- accident: §10.3.1.4 forbids a name /start/ that is a literal terminal symbol,
-- and @IF@ is not one — FEEL's keyword is @if@. Folding case would rename names
-- no engine objects to. (A name /part/ may be a keyword in any case, which is
-- why the test is against the whole folded name and not against a part: after
-- folding, @annual income@ is @annual_income@, not @in@.)
reservedFeelWords :: Set Text
reservedFeelWords = Set.fromList
  [ "true", "false", "null", "and", "or", "not", "if", "then", "else", "for", "in", "return"
  , "some", "every", "satisfies", "instance", "of", "between", "function", "external"
  , "date", "time", "duration", "list", "context"
  ]

-- | 'reservedFeelWords' __plus FEEL's built-in type spellings__, which is the
-- set a /type/ name is checked against ('feelTypeNameText').
--
-- The two sets differ because the two namespaces differ. FEEL's built-in types
-- are not keywords — nothing stops a /variable/ called @number@ — but a
-- @typeRef@ is resolved against the built-in type names first, so an
-- @itemDefinition name=\"number\"@ does not shadow the built-in: it __aliases__
-- onto it. Both an L4 @DECLARE \`number\` IS ONE OF alpha\/beta@ and a genuine
-- @NUMBER@-typed element then emit @typeRef=\"number\"@, and a reader who
-- resolves the numeric element's type lands on a @string@ enum. Nothing in the
-- artifact says the two are different types, so nothing in the fidelity report
-- could report it either — which is why the repair is a rename rather than a
-- note. @number@ becomes @number_@ and the two stay distinct.
--
-- The spellings are DMN 1.3 §10.3.1.2's, i.e. the ones that are legal in a
-- @typeRef@ attribute, so the two-word types appear in their camel-case form
-- (@dateTime@, @daysAndTimeDuration@, @yearsAndMonthsDuration@) and not as the
-- prose forms — @date and time@ folds to @date_and_time@, which no engine
-- resolves. @Any@ is capitalised, and matching stays case-sensitive, so a type
-- called @any@ is left alone.
reservedFeelTypeNames :: Set Text
reservedFeelTypeNames = reservedFeelWords <> Set.fromList
  [ "number", "string", "boolean", "Any"
  , "dateTime", "daysAndTimeDuration", "yearsAndMonthsDuration"
  ]

-- | Append a single @_@ to a folded name that is a reserved word. The result is
-- deliberately __not__ re-run through the run-collapser: collapsing would undo
-- the suffix on a name that already ends in @_@, which after folding cannot
-- happen anyway (step 4 strips trailing @_@), and re-running would make the
-- function's fixed point depend on the order of two steps that must not be
-- reordered.
suffixReserved :: Text -> Text
suffixReserved = suffixReservedIn reservedFeelWords

-- | 'suffixReserved', against a namespace's own reserved set.
suffixReservedIn :: Set Text -> Text -> Text
suffixReservedIn reserved t
  | Set.member t reserved = t <> "_"
  | otherwise             = t

-- | §5.2 stage 1 steps 2-5: the character map, the run collapse, the empty and
-- leading-digit repairs. Shared by 'feelIdentText' and 'feelTypeNameText' so the
-- two cannot drift apart on the part R3 ruled.
foldFeelName :: Text -> Text
foldFeelName t
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

-- | §5.2 stage 2. Make a list of folded names injective, in place, over a stable
-- source-order traversal: the first claimant keeps the base, and the @n@th gets
-- @base_\<n\>@ for the least free @n \>= 2@.
--
-- \"Least __free__\" rather than \"least unused count\" is what keeps the result
-- injective when a suffixed name collides with a name the source already spells:
-- @[\"a\", \"a_2\", \"a\"]@ gives @[\"a\", \"a_2\", \"a_3\"]@, not a second
-- @a_2@.
--
-- __A port, not a design__: 'L4.Dmn.Lower.assignIds' has been exactly this
-- stepper for XML ids since before §5.2 was written, and is now expressed in
-- terms of it so the two cannot drift.
--
-- The caller supplies the scope. §5.2 names four, and they are separate
-- namespaces in DMN: the DRG variable namespace (all @inputData@ and all
-- @decision@ variables together), each itemDefinition's @itemComponent@ list
-- (and, until itemDefinitions exist, the record-field projection paths
-- "L4.Dmn.Lower" emits), @decisionService@ names, and BKM @formalParameter@
-- names.
uniquifyIn :: [Text] -> [Text]
uniquifyIn names = reverse (snd (foldl' step (Set.empty, []) names))
 where
  step (used, acc) nm =
    let this = if Set.member nm used then firstFree (2 :: Int) else nm
        firstFree n
          | Set.member cand used = firstFree (n + 1)
          | otherwise            = cand
         where
          cand = nm <> "_" <> Text.pack (show n)
    in (Set.insert this used, this : acc)

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
--
-- @icValues@ is @\<inputValues\>@ — the column's /expected/ values, which DMN
-- §8.2.4 makes the thing completeness is assessed against: "a decision table
-- will be considered complete if its rules cover all combinations of expected
-- input values for all input expressions". It is a __different scope__ from the
-- itemDefinition's @allowedValues@ (the type's domain), and §8.2.4's own
-- "regardless of how the expected input values are modeled" is what makes
-- carrying both belt-and-braces rather than redundant. Emitted only when the
-- column's L4 type has a known finite domain, i.e. an @IS ONE OF@.
data InputColumn = MkInputColumn
  { icId     :: !Text
  , icLabel  :: !Text     -- ^ the L4 source text of the column's subject
  , icExpr   :: !FeelExpr
  , icType   :: !DmnType
  , icValues :: !(Maybe [Text])
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
--
-- @ocValues@ is @\<outputValues\>@, and it is emitted for an __enum-typed__
-- output only. Not for a boolean: §8.2.4 assesses completeness "regardless of
-- how the expected input values are modeled", so restating @true,false@ adds no
-- information, while §8.2.7 ("output entries SHOULD be … a subset of the output
-- values") would then be violated by every computed boolean output entry. An
-- enum is the case where the domain is genuinely unrecoverable from
-- @typeRef="string"@, which is §3.1's complaint.
data OutputColumn = MkOutputColumn
  { ocId      :: !Text
  , ocName    :: !Text
  , ocType    :: !DmnType
  , ocValues  :: !(Maybe [Text])
  , ocDefault :: !(Maybe FeelExpr)
  }
  deriving stock (Eq, Show, Generic)

-- | One rule: a cell per input column (in column order), and one output entry.
data DmnRule = MkDmnRule
  { drId          :: !Text
  , drInputs      :: ![UnaryTest]   -- ^ same length and order as 'dtInputs'
  , drOutput      :: !FeelExpr
  , drDescription :: !(Maybe Text)  -- ^ the L4 source text of the row's guard
  , drAnnotations :: ![Text]
    -- ^ same length and order as the table's 'dtAnnotations'. Empty on every
    -- table that declares no annotation column.
  }
  deriving stock (Eq, Show, Generic)

data DecisionTable = MkDecisionTable
  { dtId        :: !Text
  , dtName      :: !Text
  , dtHitPolicy :: !HitPolicy
  , dtInputs    :: ![InputColumn]
  , dtOutput    :: !OutputColumn
  , dtRules     :: ![DmnRule]
  , dtAnnotations :: ![Text]
    -- ^ annotation column NAMES (DMN 8.2.12's @tRuleAnnotationClause@, which has
    -- a @\@name@ and no content). @[]@ on every table but a rule-date interval
    -- table, which carries one column named @regime@.
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

-- | One @\<contextEntry\>@ of a 'LogicContext'.
--
-- __Every entry is NAMED.__ A context entry with no @\<variable\>@ is DMN's
-- /final result entry/, and a context that has one evaluates to that entry
-- alone. A hydrator's value IS the record, so it emits none and the context
-- itself is the decision's value. Measured on KIE 8.44.0.Final and zeebe-dmn
-- 8.7.6 (@jl4\/tests-cli\/fixtures\/dmn-hydration-probe@).
data ContextEntry = MkContextEntry
  { ceId    :: !Text
  , ceName  :: !Text
    -- ^ the FEEL entry name, and also the path step a downstream reader uses.
    -- It comes from the SAME @neFields@ map the 'ItemComponent' name does, so
    -- the two agree by construction rather than by an emitter remembering.
  , ceLabel :: !Text   -- ^ the verbatim L4 field name
  , ceType  :: !DmnType
  , ceExpr  :: !FeelExpr
  }
  deriving stock (Eq, Show, Generic)

-- | What a decision's logic is. DMN calls all three of these /boxed expressions/.
--
-- 'LogicLiteral' is not a failure mode to be ashamed of: a decision whose body is
-- not a guarded chain (an arithmetic formula, a plain conjunction, a deontic rule)
-- has no decision-table shape, and DMN's answer for that is a
-- @\<literalExpression\>@. Silently dropping such a decision would leave the DRG
-- describing a different rule set than the module does.
--
-- 'LogicContext' is a __hydrator__ (§4.4): a record instance re-emitted as a
-- boxed context whose stored components are copied from the source and whose
-- COMPUTED components are calculated from the entries declared before them. It
-- is not a fallback at all — it is the only shape in which a derived field can
-- reach a DMN engine, since FEEL has no notion of a derived component and an L4
-- call is not a FEEL invocation.
data DecisionLogic
  = LogicTable !DecisionTable
  | LogicLiteral !FeelExpr
  | LogicContext ![ContextEntry]
  deriving stock (Eq, Show, Generic)

-- | A @\<decision\>@.
--
-- __Two names, and the split is load-bearing.__ 'dcnName' is the verbatim L4
-- name and becomes @\@label@; 'dcnFeelName' is the resolved FEEL name — folded
-- ('feelIdentText') and then made unique within the DRG's variable namespace
-- ('uniquifyIn') — and becomes both the element's @\@name@ and its
-- @\<variable\>@'s (§5.3.5's invariant, which is now true by construction rather
-- than by an emitter remembering to re-fold). Resolution is a property of the
-- whole graph, so it cannot be recomputed from the string at emission time.
data Decision = MkDecision
  { dcnId           :: !Text
  , dcnName         :: !Text
  , dcnFeelName     :: !Text
  , dcnType         :: !DmnType
  , dcnLogic        :: !DecisionLogic
  , dcnRequirements :: ![Requirement]  -- ^ sorted by target id, for determinism
  }
  deriving stock (Eq, Show, Generic)

-- | A free term: a @GIVEN@ parameter, an @ASSUME@d term, or any other name the
-- module does not itself decide.
--
-- 'idName' and 'idFeelName' split for the same reason 'dcnName' and
-- 'dcnFeelName' do, and share one 'uniquifyIn' scope with them: DMN's variable
-- namespace is flat and holds both kinds of node at once.
data InputData = MkInputData
  { idId       :: !Text
  , idName     :: !Text
  , idFeelName :: !Text
  , idType     :: !DmnType
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
  , drgItemDefs  :: ![ItemDefinition]
    -- ^ one per module-local record and @IS ONE OF@, in source order, referenced
    -- or not. Reachability-gating would make the artifact depend on which
    -- decisions happened to survive lowering — a moving target — and an
    -- unreferenced itemDefinition is inert. They are the __first children__ of
    -- @\<definitions\>@ (§4.3).
    --
    -- The __domain-free aliases__ follow them, and those /are/ gated on being
    -- pointed at: an alias exists only to be some @MAYBE@ site's @typeRef@, so
    -- unlike a base definition one with no referrer says nothing.
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
  | SumTypeRead !Text
    -- ^ the decision /reads/ a sum type FEEL cannot represent (§4.2.1's R4-a,
    -- and R8-c\/d\/e for the builtin @MAYBE@ \/ @EITHER@). The 'Text' is the
    -- clause naming what it read. Reported as @D-SUMTYPE@ rather than
    -- @D-LITERALEXPR@ — see 'fidelityLossCode' — and decided /before/
    -- normalisation, so a payload-binding @CONSIDER@ is not misdiagnosed as
    -- "is not a guarded chain" (§4.2.1-8).
  deriving stock (Eq, Show, Generic)

-- | Which fidelity code reports this loss.
--
-- Every loss ends in the same place — a boxed literal expression — but not
-- every loss is the same /diagnosis/, and §4.2.1-8 makes the distinction
-- normative: a decision refused because FEEL has no sum type must not be told
-- it "is not a guarded chain", which describes a table-shape problem it does
-- not have.
fidelityLossCode :: FidelityLoss -> Text
fidelityLossCode = \case
  SumTypeRead _ -> "D-SUMTYPE"
  _             -> "D-LITERALEXPR"

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
  SumTypeRead what -> what

-- | Every note in a 'Drg': the module-level ones, then 'checkDrg'\'s
-- well-formedness findings, then each table\'s own, in decision order. The
-- ordering is fixed (§6.4.4-1) so that adding a well-formedness check does not
-- churn every golden that carries module notes.
drgNotesAll :: Drg -> [FidelityNote]
drgNotesAll drg =
  drg.drgNotes
    <> checkDrg drg
    <> [ note
       | NodeDecision d <- drg.drgNodes
       , LogicTable t <- [d.dcnLogic]
       , note <- t.dtNotes
       ]

------------------------------------------------------------------------
-- Well-formedness (R5, §6.4)
------------------------------------------------------------------------

-- | The cyclic strongly connected components of a keyed edge list, in the
-- traversal order 'Graph.stronglyConnComp' gives (reverse topological, which is
-- deterministic in the input order).
--
-- __One detector, three graphs__ (§6.4.4): DMN 1.3 states the same acyclicity
-- @SHALL@ three times — §6.3.7 for a Decision\'s @informationRequirement@
-- subgraph, §6.3.9 for a BusinessKnowledgeModel\'s @knowledgeRequirement@
-- subgraph, §6.3.10 for a DecisionService\'s. 'checkDrg' runs this routine over
-- the first two; "L4.Dmn.Lower"\'s §2.3.2 service splitter runs it over the
-- third, mid-lowering — which is why it is exported rather than inlined.
--
-- The §6.4.4-3 side condition — @|SCC| ≥ 2@, __or__ @|SCC| = 1@ with a
-- self-edge — is exactly 'Graph.CyclicSCC': a vertex with a self-loop is
-- cyclic, a vertex merely on no cycle is 'Graph.AcyclicSCC'. Both obvious
-- defaults are wrong (literal "one per SCC" notes every acyclic node; "size
-- ≥ 2" silently undoes the §6.4.4-2 self-edge un-suppression).
cyclicGroups :: Ord k => [(n, k, [k])] -> [[n]]
cyclicGroups nodes = [ns | Graph.CyclicSCC ns <- Graph.stronglyConnComp nodes]

-- | Well-formedness of the finished IR (§6.4.4-1): a plain function over 'Drg',
-- folded into 'drgNotesAll', and __also callable from "L4.Dmn.Lower"
-- mid-lowering__ (§6.4.4-6, the §2.3.2 splitter fixpoint).
--
-- One note per offending SCC, @range = Nothing@ (a cycle is not at a point;
-- same ruling as BPMN\'s @P-CYCLE@), naming every member by __name and id__ —
-- names alone are ambiguous under §5.2\'s uniquifier, which can emit two
-- decisions both labelled @shared@.
checkDrg :: Drg -> [FidelityNote]
checkDrg drg = cycleNotes
 where
  decisions = drgDecisions drg

  -- §6.3.7: the informationRequirement graph. Only decision→decision edges can
  -- close a cycle (an inputData has no requirements), so the graph is over
  -- decisions with their RequiredDecision edges.
  cycleNotes =
    [ MkFidelityNote
        { code     = "D-CYCLE"
        , severity = Blocking
        , element  = headId ds
        , range    = Nothing
        , message  = cycleMessage "informationRequirement" "decision" (memberList ds)
        , lost     =
            "loadability: DMN 1.3 §6.3.7 requires a Decision's requirement subgraph to \
            \be acyclic. KIE 8.44 reports `Cyclic dependency detected` and skips the \
            \node; Camunda 8 rejects the whole file at parse"
        }
    | ds <- cyclicGroups
        [ (d, d.dcnId, [t | RequiredDecision t <- d.dcnRequirements])
        | d <- decisions
        ]
    , let memberList xs = [(x.dcnName, x.dcnId) | x <- xs]
    , let headId xs = case xs of (x : _) -> x.dcnId; [] -> ""
    ]

-- | The prose shared by the cycle findings: one member reads "requires itself",
-- several read as a cycle listing every member by name and id.
cycleMessage :: Text -> Text -> [(Text, Text)] -> Text
cycleMessage graphName kind members = case members of
  [(nm, eid)] ->
    kind <> " `" <> nm <> "` (" <> eid <> ") requires itself: its "
      <> graphName <> " subgraph has a self-edge"
  _ ->
    tshowLen (length members) <> " " <> kind <> "s form a cycle in the "
      <> graphName <> " graph: "
      <> Text.intercalate ", " ["`" <> nm <> "` (" <> eid <> ")" | (nm, eid) <- members]
 where
  tshowLen = Text.pack . show

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
