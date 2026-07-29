-- | Lower a typechecked L4 module to the DMN 1.3 'Drg' IR.
--
-- The decision side of the Lexipedia-superset spine
-- (@specs\/todo\/lexipedia-superset\/SPEC.md@ §3): "L4.Viz.GuardedRows" normalises
-- @IF@ \/ @BRANCH@ \/ @CONSIDER@ into first-match rows, and this module is its
-- /second/ consumer — the first being the ladder. The correspondence is close to
-- definitional (GUARDED-ROWS.md §7):
--
-- > grRows in source order   ->  rules, in rule order
-- > grDisjoint = False       ->  hit policy First   (order-dependent, DMN 8.2.10)
-- > grDisjoint = True        ->  hit policy Unique
-- > grOtherwise              ->  the default output / catch-all rule
-- > a guard                  ->  an input entry
-- > a body                   ->  an output entry (an EXPRESSION, DMN 8.2.9)
--
-- Three things that table leaves implicit, and that this module has to get right:
--
-- [Where @OTHERWISE@ goes] A catch-all rule with all-@-@ input entries overlaps
--   /every/ other rule, so it is illegal under @U@. Under 'HitUnique',
--   @grOtherwise@ therefore becomes the @\<defaultOutputEntry\>@ on the output
--   clause, which DMN 1.3 supports precisely for the single-hit policies; only
--   under 'HitFirst' does it become a final all-@-@ rule.
--
-- [Negated prefixes are not materialised] Row @i@ of a @BRANCH@ fires iff its own
--   guard holds /and no earlier guard did/. The ladder consumer has to write those
--   @⋀_{j\<i} ¬gⱼ@ prefixes out, because an And\/Or tree has no other way to say
--   "first match wins". A DMN table does: hit policy @First@ /is/ that
--   quantifier. Restating the prefixes would be redundant and would turn a
--   readable table into a triangular mess, so each rule carries only its own
--   guard. This is a genuine advantage the table has over the ladder expansion.
--
-- [Non-boolean bodies are in scope] The ladder consumer gates on boolean type;
--   this one must not. A @NUMBER@-returning @BRANCH@ — a fee schedule, an
--   investor limit — is precisely what a decision table is /for/.
--
-- __The boundary this exporter reports on.__ Everything DMN can statically
-- check — completeness and consistency since Montalbano (1962), inter-tabular
-- checking since 1998, cross-DRD SMT verification since 2022 — is defined over
-- __S-FEEL input entries, constant output entries, and a single-hit policy__.
-- The DMN specification's own §9.1 then says "few if any complete decision
-- models can be defined using S-FEEL" and encourages "the full FEEL
-- specification rather than the S-FEEL subset". So the fragment you can verify
-- is not the fragment you are told to write
-- (@specs\/research\/DMN-STEELMAN.md@ §2.5, which also records what must /not/
-- be claimed: nobody has proved FEEL analysis undecidable). This exporter's job
-- is to say, per file, exactly where the emitted model crossed that line.
--
-- Of the three conditions, the third is met for free: the only hit policies here
-- are @U@ and @F@, both single-hit. @Collect@ is excluded from every published
-- result (Semantic DMN: "S-FEEL does not provide list-handling constructs …
-- hence only single-hit policies combine well with S-FEEL within a DRG"), and
-- L4's guarded chains are single-hit by construction anyway.
--
-- __The conservatism, stated once.__ A guard conjunct becomes a column plus a
-- unary test only when the test reduces to a /constant/ endpoint. Anything else
-- becomes its own boolean column whose input expression is the conjunct's own
-- text and whose cell is @true@, plus a 'FidelityNote'. That is always sound;
-- guessing is not. The exporter must never emit a table that says something the
-- L4 does not.
--
-- __One divergence this does not detect, recorded rather than hidden.__ @BRANCH@
-- short-circuits: a later guard is never evaluated once an earlier one has
-- fired. A DMN table does not — its /input expressions/ are evaluated once for
-- the whole table and then tested rule by rule. For __total, pure__ guards the
-- two agree exactly, which is what makes the mapping sound, and effectful guards
-- bail out ('EffectfulGuard'). But a __partial__ guard is a third case: in
--
-- > BRANCH
-- >   IF x EQUALS 0        THEN 0
-- >   IF 100 / x AT LEAST 5 THEN 1
-- >   OTHERWISE 2
--
-- L4 never divides by zero and DMN always does. Partiality is not decidable
-- here, so no note is emitted; a guard that can fail on inputs an earlier rule
-- would have caught is a real, undetected fidelity loss.
module L4.Dmn.Lower
  ( -- * The interface the spec fixes
    rowsToDmn
    -- * Richer entry points
  , rowsToDmnWith
  , TableCtx (..)
  , defaultTableCtx
  , lowerModule
  , moduleTitle
  , DmnLowerOptions (..)
  , defaultDmnLowerOptions
    -- * Reusable pieces
  , renderFeel
  , renderFeelIn
  , NameEnv (..)
  , emptyNameEnv
  , sanitiseId
  , selectShape
  , selectIdiom
  , selectIdiomIn
  , TypeOracle (..)
  , noTypeOracle
  , TypeEnv (..)
  , emptyTypeEnv
  , TypeFlags (..)
  , noTypeFlags
  , classifyType
  , peelLocals
  , flattenGuarded
  ) where

import Base
import qualified Base.Text as Text
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Char (isAlphaNum, isAscii, isDigit)
import Optics

import L4.Annotation (Anno_ (..), emptyAnno, getAnno)
import L4.Desugar (carameliseExpr)
import L4.Parser.SrcSpan (SrcRange)
import L4.Print (prettyLayout)
import L4.Syntax
import qualified L4.TypeCheck as TC
import L4.Viz.GuardedRows (GuardedRows (..), hasEffectfulNode, normaliseGuarded)
import L4.Interchange.Fidelity

import L4.Dmn.IR

------------------------------------------------------------------------
-- Contexts
------------------------------------------------------------------------

-- | The resolved FEEL names of everything a reference can name (§5.2 stage 2).
--
-- Stage 1 ('feelIdentText') is a per-name fold and is deliberately
-- non-injective; stage 2 ('uniquifyIn') makes it injective /within a scope/ and
-- is therefore a property of the whole module, not of a string. So a reference
-- cannot be rendered by folding the name it mentions — it has to look the name
-- up. That is what this environment is for, and it is what makes a rename reach
-- __references__ and not only declarations.
--
-- Two scopes, because DMN has two namespaces here (§5.2 scopes 1 and 2):
--
--   * 'neVars' — the DRG's flat variable namespace: every @inputData@ variable
--     and every @decision@ variable together, since they share one evaluation
--     scope.
--   * 'neFields' — record-field projection paths, keyed by the selector's own
--     'Unique'. A selector is unique to its declaring type, so one flat map
--     covers every record at once, and the map is per-declaration internally:
--     two records may each have a field that folds to @foo_bar@ without either
--     being renamed.
data NameEnv = MkNameEnv
  { neVars   :: !(Map Unique Text)
  , neFields :: !(Map Unique Text)
  }

-- | Knows no names, so every reference falls back to the stage-1 fold. Right for
-- 'renderFeel', which holds an expression and nothing else; wrong inside a
-- module, where 'lowerModule' always supplies the resolved environment.
emptyNameEnv :: NameEnv
emptyNameEnv = MkNameEnv { neVars = Map.empty, neFields = Map.empty }

-- | What a single table needs to know beyond its rows.
data TableCtx = MkTableCtx
  { tcName         :: !Text        -- ^ the decision's name; also the table's
  , tcFeelName     :: !Text
    -- ^ the decision's __resolved__ FEEL name (§5.2 stage 2). The output
    -- clause's @ocName@ is this, not a re-fold of 'tcName': the markdown carrier
    -- keys its column off it, and a name that disagreed with the decision's
    -- @\<variable\>@ would name a variable that does not exist.
  , tcNames        :: !NameEnv     -- ^ resolved FEEL names for every reference
  , tcIdPrefix     :: !Text        -- ^ every id in the table derives from this
  , tcOutputType   :: !DmnType     -- ^ from @GIVETH@, when the source declared one
  , tcConstructors :: !(Set Unique)
    -- ^ nullary constructors visible in the module. A @CONSIDER@ arm becomes an
    -- equality against a constant only if we can tell a constructor from a
    -- variable; see 'isConstantRef' for why guessing here is unsound.
  , tcConstants    :: !(Set Unique)
    -- ^ nullary decisions whose body is a literal, i.e. named thresholds. Used
    -- only to decide whether a lifted @max@\/@min@ deserves a
    -- @D-LIFTEDTHRESHOLD@ note; it never changes the lowering.
  , tcTypes        :: !TypeEnv
    -- ^ what the module's own @DECLARE@s say: which types have an
    -- @itemDefinition@ and what it is called, which have a finite domain, and
    -- which are payload-carrying unions. One environment answers the @typeRef@
    -- question and the @inputValues@ question at once, which is why they are
    -- not two lookups (§3, §4.2).
  , tcOutputValues :: !(Maybe [Text])
    -- ^ the @GIVETH@ type's domain, when it has one. Becomes
    -- @\<outputValues\>@; see 'OutputColumn'.
  , tcSubst        :: !TC.Substitution
  , tcUri          :: !NormalizedUri
  }

-- | Enough to satisfy 'rowsToDmn' standing alone. Knows no constructors, so a
-- @CONSIDER@ lowered through it degrades to boolean columns — which is why the
-- module-level path builds a real 'TableCtx'.
defaultTableCtx :: TableCtx
defaultTableCtx = MkTableCtx
  { tcName         = "decision"
  , tcFeelName     = "decision"
  , tcNames        = emptyNameEnv
  , tcIdPrefix     = "decision"
  , tcOutputType   = DmnAny
  , tcConstructors = Set.empty
  , tcConstants    = Set.empty
  , tcTypes        = emptyTypeEnv
  , tcOutputValues = Nothing
  , tcSubst        = Map.empty
  , tcUri          = toNormalizedUri (Uri "")
  }

-- | The typechecker's answer to "what type is this expression?", bundled — the
-- three arguments 'annTypeOf' already takes.
--
-- 'TableCtx' carries all three already, but 'renderFeelIn' has to ask the same
-- question without being inside a table: FEEL orders only the datatypes DMN 1.3
-- Table 54 lists, so both the select-idiom gate ('selectIdiomIn') and the
-- rendering of @\<@ \/ @\<=@ \/ @\>@ \/ @\>=@ itself need the operand's type.
-- Bundling is what lets a caller that holds only an expression ('renderFeel')
-- and a caller that holds a whole table ('mkColumn') ask through the same
-- predicate.
--
-- Deliberately NOT threaded into 'flattenGuarded': its @childOf@ guard is
-- structural, not type-directed. See 'selectShape'.
data TypeOracle = MkTypeOracle
  { toTypes :: !TypeEnv
  , toSubst :: !TC.Substitution
  , toUri   :: !NormalizedUri
  }

-- | An oracle that knows only what each node's own annotation already says.
--
-- Weaker, and the two directions differ. An operand still annotated with an
-- inference variable resolves to 'DmnAny' rather than to whatever the final
-- substitution would have given, so 'selectIdiomIn' declines to fold — a lost
-- peephole, nothing more. But 'DmnAny' also fails 'isBooleanOperand', so a
-- comparison whose operand type is unknown still renders as @a \>= b@; that is
-- right for every type FEEL orders and wrong only for a BOOLEAN comparison the
-- oracle could not see was one.
--
-- In practice it sees: a resolved comparison's operands carry the winning
-- overload's ground type in their own annotation (see 'feelOrderable'), which is
-- exactly what this oracle reads. Every lowering path inside a module goes
-- through 'oracleOf' and its substitution anyway; this one exists for
-- 'renderFeel', which has an expression and nothing else.
noTypeOracle :: TypeOracle
noTypeOracle = MkTypeOracle
  { toTypes = emptyTypeEnv
  , toSubst = Map.empty
  , toUri   = toNormalizedUri (Uri "")
  }

oracleOf :: TableCtx -> TypeOracle
oracleOf ctx = MkTypeOracle
  { toTypes = ctx.tcTypes
  , toSubst = ctx.tcSubst
  , toUri   = ctx.tcUri
  }

data DmnLowerOptions = MkDmnLowerOptions
  { dloModelName    :: !Text
    -- ^ the @\<definitions\>@ name, and the seed of its namespace. Taken as a
    -- parameter rather than read off the module's URI so that goldens do not
    -- depend on where the file lives.
  , dloSubstitution :: !TC.Substitution
    -- ^ the typechecker's final substitution, used to resolve inference
    -- variables into @typeRef@s. 'Map.empty' is fine; every unresolved type
    -- simply becomes @Any@.
  , dloFlavor       :: !DmnFlavor
    -- ^ which engine the document is aimed at. It is a __lowering__ option and
    -- not a post-hoc XML rewrite for three reasons, in order of force
    -- (@specs\/todo\/DMN-EXPORT-PROGRAM-MODEL-SPEC.md@ §13.5): the FEEL /text/ of
    -- a call site differs and cannot be recovered from a @\<text\>@ node after
    -- the fact; the fidelity report is generated from this same IR, so a rewrite
    -- would ship a report describing a different artifact — the "valid per the
    -- validator, wrong in the engine" failure this whole exercise exists to
    -- close, one layer up; and Camunda 8 fails at @parse()@ whole-file, so "emit
    -- the rich form and strip later" has no safe intermediate.
  }

defaultDmnLowerOptions :: DmnLowerOptions
defaultDmnLowerOptions = MkDmnLowerOptions
  { dloModelName    = "L4"
  , dloSubstitution = Map.empty
  , dloFlavor       = defaultDmnFlavor
  }

------------------------------------------------------------------------
-- rowsToDmn
------------------------------------------------------------------------

-- | The interface GUARDED-ROWS.md §7 fixes.
rowsToDmn :: GuardedRows -> Either FidelityLoss DecisionTable
rowsToDmn = rowsToDmnWith defaultTableCtx

-- | 'rowsToDmn', told who it is working for.
rowsToDmnWith :: TableCtx -> GuardedRows -> Either FidelityLoss DecisionTable
rowsToDmnWith ctx = rowsToDmnWith' ctx [] []

-- | 'rowsToDmnWith', plus the two things only the module-level caller knows:
-- which @WHERE@\/@LET@ locals it inlined, and which nested bodies it declined to
-- flatten. Both are reported, not silently absorbed.
rowsToDmnWith'
  :: TableCtx -> [Text] -> [Expr Resolved] -> GuardedRows -> Either FidelityLoss DecisionTable
rowsToDmnWith' ctx inlined cappedBodies rows = do
  -- A DMN input expression is evaluated ONCE for the whole table and then tested
  -- by every rule, whereas BRANCH short-circuits. Tabulating an effectful guard
  -- would therefore change how often the effect runs. (GUARDED-ROWS.md §6.)
  when (any (hasEffectfulNode . fst) rows.grRows) (Left EffectfulGuard)
  -- A deontic body is a transition system, not a value. DMN "has no notion of
  -- time" and cannot hold an obligation as a state.
  when (any isRegulative (map fst rows.grRows <> bodies)) (Left RegulativeBody)
  when (null rows.grRows) (Left NoRules)
  pure table
 where
  bodies = map snd rows.grRows <> maybeToList rows.grOtherwise

  decomposed  = map (decomposeGuard ctx . fst) rows.grRows
  columnCells = orderedColumns decomposed
  columnKeys  = map (.cellKey) columnCells
  columns     = zipWith (mkColumn ctx) [1 :: Int ..] columnCells

  -- Note what does NOT happen here: a row whose body is FALSE is kept. The
  -- ladder consumer deletes such rows because a FALSE disjunct cannot conduct;
  -- a DMN output entry of `false` is an ordinary answer, and deleting the rule
  -- would silently reroute those inputs to the default.
  ruleCells =
    [ [ maybe TestAny (.cellTest) (findCell key row) | key <- columnKeys ]
    | row <- decomposed
    ]
  findCell key row = listToMaybe [c | c <- row, c.cellKey == key]

  policy = if rows.grDisjoint && rulesPairwiseDisjoint ruleCells then HitUnique else HitFirst

  rowRules = zipWith3 mkRule [1 :: Int ..] ruleCells rows.grRows
  mkRule i cells (guardE, body) = MkDmnRule
    { drId          = ctx.tcIdPrefix <> "_r" <> tshow i
    , drInputs      = cells
    -- NB the empty constructor set is this call site's existing behaviour (a
    -- rule output has never quoted constructors, unlike `defaultOut` below);
    -- only the oracle is new here.
    , drOutput      = renderFeelIn ctx.tcNames Set.empty (oracleOf ctx) body
    , drDescription = Just (oneLine (prettyLayout guardE))
    }

  -- Under First the catch-all is a final rule with all-`-` inputs, which is
  -- exactly what First means. Under Unique it cannot be a rule at all (it would
  -- overlap everything), so it goes on the output clause instead.
  catchAll = case (policy, rows.grOtherwise) of
    (HitFirst, Just b0) ->
      [ MkDmnRule
          { drId          = ctx.tcIdPrefix <> "_r" <> tshow (length rowRules + 1)
          , drInputs      = map (const TestAny) columnKeys
          , drOutput      = renderFeelIn ctx.tcNames ctx.tcConstructors (oracleOf ctx) b0
          , drDescription = Just "OTHERWISE"
          }
      ]
    _ -> []

  allRules   = rowRules <> catchAll
  defaultOut = renderFeelIn ctx.tcNames ctx.tcConstructors (oracleOf ctx) <$> rows.grOtherwise

  -- A column's declared type is whatever L4 inferred for its subject; when that
  -- is opaque to FEEL (an enum, a record, an inference variable) but every cell
  -- in the column is the same kind of constant, say so instead. That is how a
  -- CONSIDER over constructors becomes a `string` column rather than an `Any` one.
  typedColumns = zipWith retype [0 ..] columns
  retype i col
    | col.icType /= DmnAny = col
    | otherwise            = col { icType = typeFromCells [row !! i | row <- ruleCells] }

  outColumn = MkOutputColumn
    { ocId      = ctx.tcIdPrefix <> "_o1"
    , ocName    = ctx.tcFeelName
    , ocType    = resolveOutputType ctx (map (.drOutput) allRules <> maybeToList defaultOut)
      -- Only when the DECLARED type is what won: a type recovered from the
      -- cells says what this table happens to mention, which is exactly the
      -- domain we must not assert (§3.2).
    , ocValues  = if ctx.tcOutputType /= DmnAny then ctx.tcOutputValues else Nothing
    , ocDefault = if policy == HitUnique then defaultOut else Nothing
    }

  table = MkDecisionTable
    { dtId        = ctx.tcIdPrefix <> "_table"
    , dtName      = ctx.tcName
    , dtHitPolicy = policy
    , dtInputs    = typedColumns
    , dtOutput    = outColumn
    , dtRules     = allRules
    , dtNotes     = tableNotes ctx decomposed columnCells typedColumns policy rows inlined cappedBodies
    }

------------------------------------------------------------------------
-- Guard decomposition
------------------------------------------------------------------------

-- | One decomposed conjunct: the column it constrains, and how.
data Cell = MkCell
  { cellKey      :: !(Expr Resolved)  -- ^ 'clearAnno'd subject, for column identity
  , cellSubject  :: !(Expr Resolved)  -- ^ the subject as written, for rendering
  , cellTest     :: !UnaryTest
  , cellFallback :: !Bool             -- ^ did we have to demote it to a boolean column?
  , cellNote     :: !Bool             -- ^ ...and is that worth reporting?
  }

-- | Split a guard into conjuncts and classify each one.
--
-- Two conjuncts of one row landing on the same column is a real possibility
-- (@income AT LEAST 100 AND income LESS THAN 200@) and a DMN cell is a
-- /disjunctive/ list, so they cannot simply both be written there. Where they
-- form an interval we merge them into one; otherwise the later one is demoted to
-- its own boolean column, which is verbose but says the same thing.
decomposeGuard :: TableCtx -> Expr Resolved -> [Cell]
decomposeGuard ctx = foldl' add [] . filter (not . isInert) . conjuncts
 where
  add acc conj =
    let cell = classify ctx conj
    in case break (\c -> c.cellKey == cell.cellKey) acc of
      (_, [])             -> acc <> [cell]
      (before, c : after) -> case mergeTests c.cellTest cell.cellTest of
        Just merged -> before <> [c { cellTest = merged }] <> after
        Nothing     -> acc <> [fallbackCell conj]

  -- An Inert node is grammatical scaffolding that evaluates to its context's
  -- identity; in a conjunction that is TRUE, so it constrains nothing. The words
  -- are not lost: the rule's description carries the guard's full source text.
  isInert = \case
    Inert {} -> True
    _        -> False

conjuncts :: Expr Resolved -> [Expr Resolved]
conjuncts = \case
  And _ a b -> conjuncts a <> conjuncts b
  e         -> [e]

disjuncts :: Expr Resolved -> [Expr Resolved]
disjuncts = \case
  Or _ a b -> disjuncts a <> disjuncts b
  e        -> [e]

classify :: TableCtx -> Expr Resolved -> Cell
classify ctx e = case e of
  Not _ inner -> case tryDecompose ctx inner of
    Just (subj, t) -> mkCell subj (TestNot t) False False
    -- A negated conjunct we cannot decompose is still boolean, so it becomes a
    -- `false` cell on its operand's column rather than a `true` cell on a column
    -- spelled `not(...)`. Same meaning, one fewer column, and it lines up with
    -- any positive occurrence of the same proposition elsewhere in the table.
    Nothing -> mkCell inner (TestEq (VBool False)) True (isCompound inner)
  _ -> case tryDecompose ctx e of
    Just (subj, t) -> mkCell subj t False False
    Nothing        -> fallbackCell e
 where
  mkCell subj t fb note = MkCell
    { cellKey      = clearAnno subj
    , cellSubject  = subj
    , cellTest     = t
    , cellFallback = fb
    , cellNote     = note
    }

-- | The always-correct answer: the conjunct becomes its own boolean column with
-- a @true@ cell. Reported only when the conjunct is compound — a bare boolean
-- term is an idiomatic DMN column and loses nothing.
fallbackCell :: Expr Resolved -> Cell
fallbackCell e = MkCell
  { cellKey      = clearAnno e
  , cellSubject  = e
  , cellTest     = TestEq (VBool True)
  , cellFallback = True
  , cellNote     = isCompound e
  }

isCompound :: Expr Resolved -> Bool
isCompound = \case
  App _ _ [] -> False
  Proj {}    -> False
  Lit {}     -> False
  _          -> True

-- | @Just (subject, test)@ when the conjunct is a comparison or equality against
-- a constant, or a disjunction of such over one subject.
tryDecompose :: TableCtx -> Expr Resolved -> Maybe (Expr Resolved, UnaryTest)
tryDecompose ctx = \case
  Lt     _ a b -> comparison OpLt  OpGt  a b
  Leq    _ a b -> comparison OpLeq OpGeq a b
  Gt     _ a b -> comparison OpGt  OpLt  a b
  Geq    _ a b -> comparison OpGeq OpLeq a b
  Equals _ a b -> equalityOn a b
  -- A comma-separated cell is DMN's own idiom for disjunction over one column,
  -- and it is exact: `red, blue` on column `c` means `c = red or c = blue`.
  e@Or {} -> case traverse (tryDecompose ctx) (disjuncts e) of
    Just parts@((subj, _) : _ : _)
      | all (\(s, _) -> clearAnno s == clearAnno subj) parts
      -- S-FEEL puts @not(...)@ at the TOP of a cell only: the grammar is
      -- @simple unary tests = simple POSITIVE unary tests | "not" "(" simple
      -- positive unary tests ")" | "-"@, so @1, not(2)@ is not a legal cell. A
      -- disjunct that needs a negation therefore does not get merged.
      , all (isPositiveTest . snd) parts
      -> Just (subj, TestOneOf (concatMap (flattenOneOf . snd) parts))
    _ -> Nothing
  _ -> Nothing
 where
  flattenOneOf = \case
    TestOneOf ts -> ts
    t            -> [t]

  -- A boolean endpoint is refused for the same reason 'renderFeelIn' sends a
  -- boolean @\>=@ out verbatim: DMN 1.3 §10.3.2.13 defines the ordering
  -- operators "only for the datatypes listed in Table 54", which has no boolean
  -- row, so a cell reading @\>= true@ is outside FEEL. Refusing here sends the
  -- conjunct to 'fallbackCell', where the whole comparison becomes the column
  -- subject and is reported Blocking rather than silently emitted as S-FEEL.
  comparison op mirrored a b = case (constantOf ctx a, constantOf ctx b) of
    (Nothing, Just v) | not (isBoolValue v) -> Just (a, TestCmp op v)
    (Just v, Nothing) | not (isBoolValue v) -> Just (b, TestCmp mirrored v)
    _                                       -> Nothing

  isBoolValue = \case
    VBool _ -> True
    _       -> False

  equalityOn a b = case (constantOf ctx a, constantOf ctx b) of
    (Nothing, Just v) -> Just (a, TestEq v)
    (Just v, Nothing) -> Just (b, TestEq v)
    _                 -> Nothing

-- | Is this test legal as one element of a comma-separated cell? (S-FEEL calls
-- these @simple positive unary tests@.)
isPositiveTest :: UnaryTest -> Bool
isPositiveTest = \case
  TestNot _    -> False
  TestAny      -> False
  TestOneOf ts -> all isPositiveTest ts
  TestEq _     -> True
  TestCmp _ _  -> True
  TestRange {} -> True

-- | The constant an expression denotes, if any.
constantOf :: TableCtx -> Expr Resolved -> Maybe FeelValue
constantOf ctx = \case
  Lit _ (NumericLit _ r) -> Just (VNum r)
  Lit _ (StringLit _ t)  -> Just (VStr t)
  App _ r []             -> constantRef ctx r
  _                      -> Nothing

constantRef :: TableCtx -> Resolved -> Maybe FeelValue
constantRef ctx = constantRefIn ctx.tcConstructors

constantRefIn :: Set Unique -> Resolved -> Maybe FeelValue
constantRefIn ctors r
  | u == TC.trueUnique    = Just (VBool True)
  | u == TC.falseUnique   = Just (VBool False)
  | isBuiltinSumCon r     = Nothing
  | isConstantRef ctors r = Just (VStr (nameOf r))
  | otherwise             = Nothing
 where
  u = getUnique r

-- | A constructor of one of L4\'s __builtin open sums__: @NOTHING@, @JUST@,
-- @LEFT@, @RIGHT@.
--
-- The typechecker stamps these with the @Constructor@ 'TermKind'
-- ("L4.TypeCheck.Environment"), exactly as it stamps a user-declared one, so
-- 'isConstructorKind' accepted them and 'constantRefIn' turned @NOTHING@ into
-- the S-FEEL __string constant__ @\"NOTHING\"@. Measured on the Charities and
-- Reg CF corpora: six decisions of the shape @IF p THEN JUST c ELSE NOTHING@
-- shipped with a @Blocking@ note on the @JUST@ arm and a silently wrong
-- @\"NOTHING\"@ on the other — strictly worse than a loud failure, because a
-- reader who checks the report sees one arm reported and concludes the other is
-- fine (R8-f).
--
-- __Excluding them from 'constantRefIn' is not sufficient on its own__, and the
-- second half is in 'renderFeelIn': without it a bare @NOTHING@ would fall
-- through to 'feelIdentIn' and render as a bare FEEL /identifier/ tagged
-- 'SFeel' — an unresolvable name carrying this module\'s strongest
-- executability claim, which is worse still. So a reference to one of these
-- renders __verbatim__, which is honest, and the decision that mentions it is
-- routed to a boxed literal expression with @D-SUMTYPE@ before any cell is
-- asked for (R8-d).
isBuiltinSumCon :: Resolved -> Bool
isBuiltinSumCon r = Set.member (getUnique r) builtinSumCons

builtinSumCons :: Set Unique
builtinSumCons =
  Set.fromList [TC.nothingUnique, TC.justUnique, TC.leftUnique, TC.rightUnique]

-- | Is this nullary reference a data constructor?
--
-- The question matters because 'L4.Syntax.Var' is a pattern synonym for
-- @App ann n []@, so "a nullary application is a nullary constructor" also
-- matches every @GIVEN@ parameter, every local binding and every zero-argument
-- @DECIDE@. Treating @WHEN EXACTLY lo@ as a constant would put the /name/ @lo@
-- in a cell as though it were a value — and, worse, would let the disjointness
-- check declare two such rows exclusive when @lo == hi@. (Same trap
-- GUARDED-ROWS.md §5a records for the ladder.)
--
-- Two independent witnesses, either of which suffices; neither guesses:
-- membership of the module's own declared constructors, and the @Constructor@
-- 'TermKind' the typechecker stamps on a resolved constructor name.
isConstantRef :: Set Unique -> Resolved -> Bool
isConstantRef ctors r = Set.member (getUnique r) ctors || isConstructorKind r

isConstructorKind :: Resolved -> Bool
isConstructorKind r = case getActual r of
  MkName cAnn _ -> case cAnn.extra.resolvedInfo of
    Just (TypeInfo _ (Just Constructor)) -> True
    _                                    -> False

-- | The name of a binding, as DMN should spell it.
--
-- L4 gives a constructor or a stored record selector declared inside a @§@ a
-- section-qualified /spelling/ as well as its bare one (see
-- @specs\/todo\/SECTION-RANKING-SPEC.md@ and @addQualifiedAliases@ in
-- "L4.TypeCheck"). 'rawNameToText' renders that qualification by joining the
-- section path with @.@ — which is right for L4, where @.@ separates scopes,
-- and wrong for FEEL, where @.@ is path traversal into a value.
--
-- Flattening the qualified spelling into FEEL therefore produced text that
-- /parses/ as a path and cannot resolve: the corpus at
-- @jl4\/examples\/legal\/regcf\/regcf.l4@ emitted, among 22 such decisions,
--
-- > investor._3. Investor investment limits _ Rule 100_a__2_.annual income
--
-- — four path steps, of which two are a section heading with its punctuation
-- mangled by 'feelIdentText'. Because that renders as structured FEEL it never
-- reached the verbatim fallback, so no @D-NONFEELINPUT@ fired and the model
-- was silently unevaluable rather than loudly so. The same flattening put a
-- section heading in front of every enum value in the one clean decision table
-- the corpus produced.
--
-- FEEL has no notion of L4 sections, so the qualification cannot be carried,
-- and dropping it is the only honest rendering. Where dropping it makes two
-- bindings collide, @D-SCOPE@ already says so — that note is the reason this
-- is a documented loss rather than a silent one.
nameOf :: Resolved -> Text
nameOf = unqualifiedNameToText . getOriginal

------------------------------------------------------------------------
-- Columns
------------------------------------------------------------------------

-- | Column identity is the subject expression modulo annotations; column /order/
-- is first appearance, scanning rows in rule order and conjuncts left to right.
-- Both are properties of the source, so both are deterministic.
--
-- The FIRST cell to reach a column is kept, not just its key: 'clearAnno' erases
-- the inferred type and the source range along with the positions, so a column
-- built from the key alone could be neither typed nor located.
orderedColumns :: [[Cell]] -> [Cell]
orderedColumns rows = go Set.empty [c | row <- rows, c <- row]
 where
  go _ [] = []
  go seen (c : cs)
    | Set.member c.cellKey seen = go seen cs
    | otherwise                 = c : go (Set.insert c.cellKey seen) cs

-- | The column, and — from the same walk of the subject's type — its domain
-- (§3.1). One classification answers both, which is what keeps a column's
-- @typeRef@ and its @\<inputValues\>@ from being derived by two rules that can
-- disagree.
mkColumn :: TableCtx -> Int -> Cell -> InputColumn
mkColumn ctx i c = MkInputColumn
  { icId     = ctx.tcIdPrefix <> "_i" <> tshow i
  , icLabel  = oneLine (prettyLayout c.cellSubject)
  , icExpr   = renderFeelIn ctx.tcNames ctx.tcConstructors (oracleOf ctx) c.cellSubject
  , icType   = ty
  , icValues = dom
  }
 where
  (ty, dom, _) = oracleClassify (oracleOf ctx) c.cellSubject

-- | When L4's own type is opaque to FEEL, fall back to what the cells say.
typeFromCells :: [UnaryTest] -> DmnType
typeFromCells tests = case nub (concatMap kinds tests) of
  [t] -> t
  _   -> DmnAny
 where
  kinds = \case
    TestAny             -> []
    TestEq v            -> [kindOf v]
    TestCmp _ v         -> [kindOf v]
    TestNot t           -> kinds t
    TestOneOf ts        -> concatMap kinds ts
    TestRange _ lo hi _ -> [kindOf lo, kindOf hi]
  kindOf = \case
    VNum _  -> DmnNumber
    VStr _  -> DmnString
    VBool _ -> DmnBoolean

-- | @GIVETH@ wins; failing that, agreement among the output entries' own
-- literals. Deliberately syntactic, because this only runs when the declared
-- type said nothing and the annotation gave back an inference variable.
resolveOutputType :: TableCtx -> [FeelExpr] -> DmnType
resolveOutputType ctx outs
  | ctx.tcOutputType /= DmnAny = ctx.tcOutputType
  | otherwise = case nub (mapMaybe literalKind outs) of
      [t] | length (mapMaybe literalKind outs) == length outs -> t
      _ -> DmnAny
 where
  literalKind fe
    | fe.feFragment /= SFeel              = Nothing
    | fe.feText `elem` ["true", "false"]  = Just DmnBoolean
    | Text.isPrefixOf "\"" fe.feText      = Just DmnString
    | isNumericText fe.feText             = Just DmnNumber
    | otherwise                           = Nothing

isNumericText :: Text -> Bool
isNumericText t =
  not (Text.null t) && Text.all (\c -> isDigit c || c == '.' || c == '-') t

------------------------------------------------------------------------
-- Unary-test algebra
------------------------------------------------------------------------

-- | Two bounds on one column, as one interval. Only for numbers, and only when
-- the interval is non-empty; anything else returns 'Nothing' and the caller
-- falls back to a separate column.
mergeTests :: UnaryTest -> UnaryTest -> Maybe UnaryTest
mergeTests a b = case (a, b) of
  (TestCmp OpGeq lo, TestCmp OpLeq hi) -> range True lo hi True
  (TestCmp OpGeq lo, TestCmp OpLt  hi) -> range True lo hi False
  (TestCmp OpGt  lo, TestCmp OpLeq hi) -> range False lo hi True
  (TestCmp OpGt  lo, TestCmp OpLt  hi) -> range False lo hi False
  (TestCmp OpLeq _, TestCmp OpGeq _)   -> mergeTests b a
  (TestCmp OpLt  _, TestCmp OpGeq _)   -> mergeTests b a
  (TestCmp OpLeq _, TestCmp OpGt  _)   -> mergeTests b a
  (TestCmp OpLt  _, TestCmp OpGt  _)   -> mergeTests b a
  _                                    -> Nothing
 where
  range lc lo hi hc = case (lo, hi) of
    (VNum x, VNum y) | x <= y -> Just (TestRange lc lo hi hc)
    _                         -> Nothing

-- | Can no input satisfy both cells? Sound but incomplete: a 'False' costs only
-- a hit-policy downgrade, never correctness.
testsDisjoint :: UnaryTest -> UnaryTest -> Bool
testsDisjoint a b = case (a, b) of
  (TestAny, _)                   -> False
  (_, TestAny)                   -> False
  (TestOneOf ts, u)              -> all (`testsDisjoint` u) ts
  (u, TestOneOf ts)              -> all (testsDisjoint u) ts
  (TestNot x, y)                 -> x == y
  (x, TestNot y)                 -> x == y
  (TestEq x, TestEq y)           -> x /= y
  (TestEq x, TestCmp op v)       -> refutes x op v
  (TestCmp op v, TestEq x)       -> refutes x op v
  (TestEq x, r@TestRange {})     -> not (inRange x r)
  (r@TestRange {}, TestEq x)     -> not (inRange x r)
  (TestCmp o1 v1, TestCmp o2 v2) -> cmpDisjoint o1 v1 o2 v2
  (TestCmp o v, r@TestRange {})  -> any (uncurry (cmpDisjoint o v)) (rangeBounds r)
  (r@TestRange {}, TestCmp o v)  -> any (uncurry (cmpDisjoint o v)) (rangeBounds r)
  (r1@TestRange {}, r2@TestRange {}) ->
    or [ cmpDisjoint o1 v1 o2 v2 | (o1, v1) <- rangeBounds r1, (o2, v2) <- rangeBounds r2 ]
 where
  refutes x op v = fromMaybe False (not <$> satisfies x op v)

rangeBounds :: UnaryTest -> [(CmpOp, FeelValue)]
rangeBounds = \case
  TestRange lc lo hi hc -> [(if lc then OpGeq else OpGt, lo), (if hc then OpLeq else OpLt, hi)]
  _                     -> []

inRange :: FeelValue -> UnaryTest -> Bool
inRange x r = and [fromMaybe True (satisfies x op v) | (op, v) <- rangeBounds r]

-- | Does @x@ satisfy @x op v@? 'Nothing' when the two are not comparable
-- numbers, in which case every caller degrades to "assume it might".
satisfies :: FeelValue -> CmpOp -> FeelValue -> Maybe Bool
satisfies x op v = do
  p <- numberOf x
  q <- numberOf v
  pure $ case op of
    OpLt  -> p < q
    OpLeq -> p <= q
    OpGt  -> p > q
    OpGeq -> p >= q

numberOf :: FeelValue -> Maybe Rational
numberOf = \case
  VNum r -> Just r
  _      -> Nothing

-- | Is @x op1 v1 AND x op2 v2@ unsatisfiable?
cmpDisjoint :: CmpOp -> FeelValue -> CmpOp -> FeelValue -> Bool
cmpDisjoint o1 v1 o2 v2 = fromMaybe False $ do
  p <- numberOf v1
  q <- numberOf v2
  pure $ case (o1, o2) of
    (OpLt,  OpGeq) -> p <= q
    (OpLt,  OpGt)  -> p <= q
    (OpLeq, OpGt)  -> p <= q
    (OpLeq, OpGeq) -> p < q
    (OpGeq, OpLt)  -> q <= p
    (OpGt,  OpLt)  -> q <= p
    (OpGt,  OpLeq) -> q <= p
    (OpGeq, OpLeq) -> q < p
    _              -> False

-- | Can the emitted table itself witness that no two rules both fire?
--
-- @grDisjoint@ is a claim about the L4 /guards/; hit policy @U@ is a claim about
-- the emitted /cells/, and the decomposition can lose the connection between
-- them. @income LESS THAN limit@ versus @income AT LEAST limit@ are exclusive in
-- L4, but neither has a constant endpoint, so both become boolean columns and the
-- two rules then overlap syntactically wherever both hold. Emitting @U@ on that
-- table would be a false claim about the artifact, so we check the cells and
-- downgrade to @F@ — always sound, since @F@ reproduces first-match order.
rulesPairwiseDisjoint :: [[UnaryTest]] -> Bool
rulesPairwiseDisjoint rules =
  and [or (zipWith testsDisjoint r1 r2) | (r1 : rest) <- tails rules, r2 <- rest]

------------------------------------------------------------------------
-- L4 -> FEEL
------------------------------------------------------------------------

-- | Render an L4 expression as FEEL, and say honestly which fragment the result
-- lies in.
--
-- 'SFeel' is the claim that matters: DMN's completeness, consistency and overlap
-- checking are all defined over S-FEEL (@simple expression = arithmetic
-- expression | simple value | comparison@, grammar rule 3). Boolean connectives,
-- function invocation and @if@ are ordinary FEEL but outside that grammar, so
-- they are 'FullFeel'; anything we cannot render at all is 'L4Verbatim' and the
-- text is L4.
--
-- If any sub-expression is 'L4Verbatim' the whole node is re-rendered with
-- 'prettyLayout' rather than spliced, so the text never mixes the two languages.
renderFeel :: Expr Resolved -> FeelExpr
renderFeel = renderFeelIn emptyNameEnv Set.empty noTypeOracle

-- | 'renderFeel', told which nullary references are data constructors, and given
-- a 'TypeOracle'.
--
-- The constructor set matters on the OUTPUT side and is easy to get wrong: a
-- constructor is a /value/, and FEEL has no sum types, so it must be quoted.
-- Rendered as a bare name it would read as a reference to a variable of that
-- name — and it would disagree with the input side, where 'constantOf' has
-- already quoted the same constructor into a @\"red\"@ cell.
--
-- The oracle answers the one question FEEL's grammar cannot: which of L4's
-- comparisons DMN actually orders. It decides whether the select idiom may fold
-- ('selectIdiomIn'), and whether a bare @\<@ \/ @\<=@ \/ @\>@ \/ @\>=@ is FEEL
-- at all (see 'ordering' below). Both fall out of DMN 1.3 Table 54, so both ask
-- the same predicate family and cannot drift apart.
renderFeelIn :: NameEnv -> Set Unique -> TypeOracle -> Expr Resolved -> FeelExpr
renderFeelIn names ctors oracle top = let (_, txt, frag) = go top in MkFeelExpr (oneLine txt) frag
 where
  -- (precedence, text, fragment)
  go :: Expr Resolved -> (Int, Text, FeelFragment)
  go e = case e of
    Lit _ (NumericLit _ r) -> (atomPrec, renderNumber r, SFeel)
    Lit _ (StringLit _ s)  -> (atomPrec, quoteFeelString s, SFeel)
    -- A builtin sum constructor is NOT a FEEL name and NOT a FEEL string; see
    -- 'isBuiltinSumCon'. Verbatim is the only honest rendering, and it makes the
    -- whole enclosing expression verbatim too, which is what stops `NOTHING`
    -- from being spliced into an otherwise FEEL-looking cell.
    App _ r [] | isBuiltinSumCon r -> verbatim e
               | otherwise         -> (atomPrec, nullaryText r, SFeel)
    -- A projection path is FEEL's `qualified name`, and its steps live in the
    -- FIELD namespace (§5.2 scope 2), not the DRG's variable namespace. That is
    -- where the one executed corpus collision lands (§5.3.4): two distinct
    -- fields folding to one path step is valid FEEL computing a wrong number.
    Proj _ x n             -> unary e SFeel (\t -> t <> "." <> feelFieldIn names n) x
    Plus      _ a b -> binary e 6 SFeel "+"  a b
    Minus     _ a b -> binary e 6 SFeel "-"  a b
    Times     _ a b -> binary e 7 SFeel "*"  a b
    DividedBy _ a b -> binary e 7 SFeel "/"  a b
    Lt        _ a b -> ordering e "<"  a b
    Leq       _ a b -> ordering e "<=" a b
    Gt        _ a b -> ordering e ">"  a b
    Geq       _ a b -> ordering e ">=" a b
    -- Equality, unlike ordering, is total in FEEL: Table 52 requires only that
    -- both sides be "of the same kind/datatype", and Table 53 gives boolean its
    -- own row ("e1 and e2 must both be true or both be false").
    Equals    _ a b -> binary e 5 SFeel "="  a b
    -- Inert text is grammatical scaffolding -- a quoted fragment of the statute
    -- carried along for isomorphism -- whose VALUE is its context's identity
    -- element. That is the evaluator's own definition
    -- ("L4.EvaluateLazy.Machine": @InertCtxAnd -> ValBool True@,
    -- @InertCtxOr -> ValBool False@, @InertCtxNone -> ValBool True@), and the
    -- ladder reads it the same way. A boolean literal is S-FEEL, so this costs
    -- nothing. The words are not lost: a guard's full source text is already the
    -- rule's @\<description\>@. Before this case, 794 statute quotations in the
    -- Charities corpus alone poisoned their enclosing guards into L4 source.
    Inert _ _ ictx -> (atomPrec, inertText ictx, SFeel)
    -- @n %@ is @n / 100@ ("L4.EvaluateLazy.Machine":
    -- @UnaryPercent -> ValNumber (val / 100)@), and division is inside S-FEEL's
    -- `arithmetic expression`, so the fragment claim is unchanged. Written at
    -- division's own precedence rather than wrapped in parentheses, because
    -- S-FEEL's grammar has no parenthesised-expression production (rules 2, 3,
    -- 16-21): @(10 %) TIMES base@ becomes @10 / 100 * base@, which is how the
    -- Reg CF exhibit already spells the same quantity.
    Percent _ x ->
      let (p, t, f) = go x
      in if f == L4Verbatim
           then verbatim e
           else (7, parenIf (p < 7) t <> " / 100", max SFeel f)
    -- Legal FEEL, outside S-FEEL's `simple expression`.
    And    _ a b -> binary e 3 FullFeel "and" a b
    Or     _ a b -> binary e 2 FullFeel "or"  a b
    Modulo _ a b -> call e "modulo" [a, b]
    Not    _ a   -> call e "not" [a]
    -- FEEL has no implication operator; material implication is the reading L4
    -- gives a constitutive IMPLIES, and it is what the ladder's seam draws.
    Implies _ a b -> pair e FullFeel (\ta tb -> "(not(" <> ta <> ") or " <> tb <> ")") a b
    List _ xs -> nary e FullFeel (\ts -> "[" <> Text.intercalate ", " ts <> "]") xs
    -- FEEL has no cons operator, but it has `concatenate` (DMN 1.1 §10.3.4), and
    -- a one-element list literal is how you spell the head.
    Cons _ x xs -> pair e FullFeel (\tx txs -> "concatenate([" <> tx <> "], " <> txs <> ")") x xs
    -- @AppNamed@ deliberately has NO case here: it falls to 'verbatim' below and
    -- is therefore reported @D-NONFEELOUTPUT@ \/ Blocking.
    --
    -- It is tempting to render it as a FEEL context literal @{f: v, …}@, since
    -- 'Proj' above renders the read side as @r.f@. That lowering was written and
    -- REVERTED, because it is wrong four ways, each verified by running both
    -- evaluators:
    --
    --   1. @AppNamed@ is L4\'s general NAMED-ARGUMENT APPLICATION, not record
    --      construction. 'inferAppNamed' types it against any @Fun@, and the
    --      evaluator reduces it to @App@. With @f MEANS x TIMES y@,
    --      @f WITH x IS 3, y IS 4@ is @12@ in L4 and @{x: 3, y: 4}@ under that
    --      lowering — which KIE compiles happily and returns as a context.
    --   2. It drops the constructor tag, so @Paid WITH amount IS 40@ and
    --      @Owed WITH amount IS 40@ both become @{amount: 40}@. L4 says those are
    --      unequal; a DMN engine says they are equal.
    --   3. Field names are not checked against FEEL\'s reserved words, so a field
    --      called @for@ or @in@ emits @{for: 1}@, which KIE fails to compile while
    --      still reporting the decision SUCCEEDED with an empty result.
    --   4. Computed fields (@HAS f IS A T MEANS …@) are not supplied as arguments,
    --      so they are absent from the context while 'Proj' still reads @r.f@ —
    --      null in DMN, a value in L4.
    --
    -- Each of those turns an honest Blocking note into a silently wrong answer
    -- reported Advisory, which is strictly worse than not lowering at all. A
    -- correct version must check the head is a constructor, quote the tag,
    -- validate keys, and supply computed fields; until then, verbatim is honest.
    -- A conditional whose arms ARE its comparison's operands is not a decision;
    -- it is `max` / `min`. Lower it to FEEL's own function rather than to an
    -- `if`, the way a compiler backend recognises a select pattern instead of
    -- emitting a branch.
    IfThenElse _ c t f
      | Just (fn, a, b) <- selectIdiomIn oracle e -> call e fn [a, b]
      | otherwise ->
          triple e FullFeel (\tc tt tf -> "(if " <> tc <> " then " <> tt <> " else " <> tf <> ")") c t f
    -- A call to an L4 function is NOT a FEEL function invocation, and this used
    -- to be rendered @f(args)@ and labelled 'FullFeel' -- a claim of
    -- executability the exporter cannot honour. FEEL resolves an invocation
    -- against its own builtins or against a BKM in the same DRG, and this
    -- exporter emits neither: an L4 @DECIDE@ becomes a 0-ary DMN decision
    -- variable (Vandevelde et al.: "the 'variables' of standard DMN correspond
    -- to constants"), so @f(x)@ names nothing an engine can resolve. Drools/KIE
    -- 8.44 answers @Unknown variable 'JUST'@ for @JUST(40)@ -- which the shipped
    -- Charities corpus emitted four times -- and the whole decision evaluates to
    -- null. So it is verbatim, and the report says Blocking. The FEEL builtins
    -- this backend DOES emit (@not@, @modulo@, @max@, @min@, @concatenate@) are
    -- constructed here by name and never routed through this case.
    App _ _ (_ : _) -> verbatim e
    _ -> verbatim e
   where
    atomPrec = 9 :: Int

    inertText = \case
      InertCtxAnd  -> "true"
      InertCtxOr   -> "false"
      InertCtxNone -> "true"

    unary whole frag build x =
      let (p, t, f) = go x
      in if f == L4Verbatim
           then verbatim whole
           else (atomPrec, build (parenIf (p < atomPrec) t), max frag f)

    -- FEEL's ORDERING operators are partial in a way its equality is not.
    -- DMN 1.3 §10.3.2.13: "The other comparison operators are defined only for
    -- the datatypes listed in Table 54", and Table 54 has rows for number,
    -- string, date, date-and-time, time and the two durations — and __none for
    -- boolean__. L4 does order booleans (@__LEQ__@ has a
    -- @BOOLEAN AND BOOLEAN TO BOOLEAN@ variant, "L4.TypeCheck.Environment"), so
    -- @IF p AT LEAST q@ is a well-typed L4 program whose obvious transliteration
    -- @p >= q@ is outside FEEL's language, not merely outside S-FEEL.
    --
    -- Emitting it tagged 'SFeel' would be the strongest executability claim this
    -- module can make about a fragment DMN does not define. So it goes out
    -- verbatim, which is what this module already does for every other
    -- "renders fine, evaluates to nothing" case (see the @App@ note above), and
    -- verbatim is what raises @D-NONFEELINPUT@ \/ @D-NONFEELOUTPUT@ Blocking.
    ordering whole op a b
      | any (isBooleanOperand oracle) [a, b] = verbatim whole
      | otherwise                            = binary whole 5 SFeel op a b

    binary whole prec frag op a b =
      let (pa, ta, fa) = go a
          (pb, tb, fb) = go b
      in if fa == L4Verbatim || fb == L4Verbatim
           then verbatim whole
           else ( prec
                , parenIf (pa < prec) ta <> " " <> op <> " " <> parenIf (pb <= prec) tb
                , maximum [frag, fa, fb]
                )

    pair whole frag build a b =
      let (_, ta, fa) = go a
          (_, tb, fb) = go b
      in if fa == L4Verbatim || fb == L4Verbatim
           then verbatim whole
           else (atomPrec, build ta tb, maximum [frag, fa, fb])

    triple whole frag build a b c =
      let (_, ta, fa) = go a
          (_, tb, fb) = go b
          (_, tc, fc) = go c
      in if L4Verbatim `elem` [fa, fb, fc]
           then verbatim whole
           else (atomPrec, build ta tb tc, maximum [frag, fa, fb, fc])

    nary whole frag build xs =
      let parts = map go xs
      in if any (\(_, _, f) -> f == L4Verbatim) parts
           then verbatim whole
           else (atomPrec, build [t | (_, t, _) <- parts], maximum (frag : [f | (_, _, f) <- parts]))

    call whole fn args =
      nary whole FullFeel (\ts -> fn <> "(" <> Text.intercalate ", " ts <> ")") args

    verbatim whole = (atomPrec, prettyLayout whole, L4Verbatim)

    parenIf True t  = "(" <> t <> ")"
    parenIf False t = t

  nullaryText r = case constantRefIn ctors r of
    Just v  -> renderFeelValue v
    Nothing -> feelIdentIn names r

-- | An L4 name as the FEEL name that refers to it.
--
-- The declaring side (an @inputData@\'s or a @decision@\'s @\<variable\>@)
-- carries its resolved name on the IR, and this is the same map, so the two
-- always agree — including after a collision rename, which is the case a
-- per-name fold cannot get right (§5.2 stage 2).
--
-- The fallback is the bare fold, for a reference the environment does not know:
-- 'renderFeel' standing alone, and a reference to something outside the DRG's
-- namespace. It is stage 1's answer, which is what the exporter emitted for
-- everything before stage 2 landed.
feelIdentIn :: NameEnv -> Resolved -> Text
feelIdentIn env r =
  Map.findWithDefault (feelIdentText (nameOf r)) (getUnique r) env.neVars

-- | A record field, as the FEEL path step that reads it. Its own namespace.
feelFieldIn :: NameEnv -> Resolved -> Text
feelFieldIn env r =
  Map.findWithDefault (feelIdentText (nameOf r)) (getUnique r) env.neFields

------------------------------------------------------------------------
-- The select idiom: max / min wearing a conditional's clothes
------------------------------------------------------------------------

-- | @IF a AT LEAST b THEN a ELSE b@ is not a decision over two cases. It is
-- @max a b@, and the L4 prelude literally defines @max@ that way.
--
-- A corpus survey found 17 instances across 12 files, ten of which sit under a
-- declaration or comment that /names/ the operation in English — "The lesser
-- of", "the earlier of", "greater of annual income or net worth" — while
-- spelling the conditional out longhand. So authors know it is @min@; they just
-- do not write @min@.
--
-- Recognising it is the peephole a compiler backend runs (LLVM's
-- @matchSelectPattern@ folding a branch into @SPF_SMAX@\/@SMIN@), and recognising
-- the SHAPE also matters structurally, whether or not the fold fires: without
-- 'selectShape', 'flattenGuarded' would expand the conditional into extra table
-- rows, manufacturing cases the regulation does not have. 17 CFR
-- 227.100(a)(2)(i) says "__The greater of__ $2,500, or 5 percent of …" — the
-- statute states an operator, so @max@ is the isomorphic rendering and the
-- expansion would be a derivation the statute never makes.
--
-- __Strictness does not matter here__, which is why @>=@ and @>@ map to the same
-- thing: the arms are the operands, so on a tie both branches return equal
-- values.
--
-- The match is exact and syntactic — arms must be the comparison's own operands
-- modulo annotations. That is what keeps it off the corpus\'s near misses:
-- @IF pool > promised THEN pool + increase ELSE pool@ (an arm is an operand
-- /plus a term/), @IF n < 0 THEN 0 - n ELSE n@ (@abs@, four times in the
-- corpus), and @IF n > k THEN n - 1 ELSE n@ (an off-by-one).
--
-- __The shape is not the whole test.__ L4\'s @\<@ \/ @\<=@ \/ @\>@ \/ @\>=@ are
-- overloaded — "L4.TypeCheck.Environment" gives each a @NUMBER@, a @STRING@ and
-- a @BOOLEAN@ variant, and @daydate.l4@ adds a @DATE@ one — so
-- @IF s AT LEAST t THEN s ELSE t@ is a well-typed L4 program over any of the
-- four, and the syntax says nothing about which. FEEL\'s @min@\/@max@ take a
-- "non-empty list of __comparable__ items" (DMN 1.3 §10.3.4.4 Table 75), and
-- what FEEL can compare is fixed by §10.3.2.13: "The other comparison operators
-- are defined only for the datatypes listed in Table 54", whose rows are number,
-- string, date, date-and-time, time and the two durations. __Boolean is absent__,
-- so @max(true, false)@ is outside the builtin\'s domain and §10.3.4 makes an
-- out-of-domain parameter yield @null@. (Drools\/KIE 8.44 answers @true@ anyway,
-- because it delegates to Java\'s @Comparable@ — engine-specific luck an exporter
-- must not bank on.)
--
-- So the gate is __FEEL-orderable operands__ ('feelOrderable'), which of the
-- types this backend models means @NUMBER@, @STRING@ and @DATE@. That line is
-- forced rather than chosen: the un-folded fallthrough is
-- @(if s >= t then s else t)@, whose @\>=@ is legal in exactly the same rows of
-- exactly the same table. Refusing to emit @min@ over dates while emitting @\<=@
-- over dates would not be conservative, just inconsistent. Boolean fails the
-- gate for a reason that applies to both spellings at once, and 'renderFeelIn'
-- accordingly sends a boolean @\>=@ out verbatim rather than pretending it is
-- S-FEEL.
--
-- An operand the oracle cannot type at all ('DmnAny' — no annotation, an
-- unresolved inference variable, a synthesised node) also fails the gate: not
-- because @if@ is safer, but because we cannot say it is orderable. Missing type
-- information costs a peephole, never correctness.
--
-- 'selectIdiom' asks the weakest oracle there is ('noTypeOracle'): it reads each
-- operand\'s own annotation and nothing else. Callers holding a 'TableCtx' should
-- use 'selectIdiomIn' with 'oracleOf', which can additionally resolve an operand
-- whose annotation is still an inference variable.
selectIdiom :: Expr Resolved -> Maybe (Text, Expr Resolved, Expr Resolved)
selectIdiom = selectIdiomIn noTypeOracle

-- | 'selectIdiom', told how to type an operand.
selectIdiomIn :: TypeOracle -> Expr Resolved -> Maybe (Text, Expr Resolved, Expr Resolved)
selectIdiomIn oracle e = do
  found@(_, a, b) <- selectShape e
  guard (feelOrderable oracle a && feelOrderable oracle b)
  pure found

-- | The select /shape/, with no view on the operands\' type: @IF@ whose arms are
-- its own comparison\'s operands.
--
-- Separate from 'selectIdiomIn' because the two questions have different
-- consumers and must not be conflated:
--
--   * __may we fold?__ is 'selectIdiomIn', and it is about what FEEL can
--     evaluate.
--   * __may we expand?__ is this one, and it is about ISOMORPHISM. @childOf@ in
--     'flattenGuarded' asks it to keep a select out of the row splicer, because
--     splicing @IF a >= b THEN a ELSE b@ into two rules manufactures a case
--     distinction the source does not make and drags the whole table from @U@ to
--     @F@ (DMN 8.2.10 order dependence) for a body that is one operator. That
--     harm does not go away when the operands are strings, and it is not caused
--     by the fold — so gating expansion on the fold's type test would have made
--     the artifact worse for exactly the operands the fold declines.
selectShape :: Expr Resolved -> Maybe (Text, Expr Resolved, Expr Resolved)
selectShape = \case
  IfThenElse _ c t f -> do
    (thenIsA, a, b) <- comparisonOf c
    let same x y = clearAnno x == clearAnno y
    if      same t a && same f b then Just (if thenIsA then "max" else "min", a, b)
    else if same t b && same f a then Just (if thenIsA then "min" else "max", a, b)
    else Nothing
  _ -> Nothing
 where
  -- 'thenIsA' is True when taking the THEN arm as `a` means "the bigger one".
  comparisonOf = \case
    Geq _ a b -> Just (True, a, b)
    Gt  _ a b -> Just (True, a, b)
    Leq _ a b -> Just (False, a, b)
    Lt  _ a b -> Just (False, a, b)
    _         -> Nothing

-- | Is this operand of a comparison of a type FEEL can ORDER (DMN 1.3 Table 54)?
--
-- The overload the typechecker committed to is /not/ readable here: it desugars
-- @a AT LEAST b@ into an application of one of @__GEQ__@\'s variants, but
-- 'carameliseExpr' — which "L4.Dmn.Lower" runs to make a comparison look like a
-- comparison again — matches on the head\'s NAME TEXT and drops the 'Resolved',
-- which is the only carrier of the chosen 'Unique'. Every variant, including
-- @daydate.l4@\'s user-level @DATE@ ones, caramelises to the identical 'Geq'
-- node.
--
-- What survives is better placed anyway. @matchFunTy@ checks each argument
-- against the chosen candidate\'s own declared parameter type, and @checkExpr@
-- stamps that expected type onto the node
-- ("L4.TypeCheck": @setAnnResolvedType t Nothing re@). Since the comparison
-- builtins are @fun_ [ty, ty] boolean@ for a ground @ty@, a resolved
-- comparison\'s operand carries the winning overload\'s concrete
-- @NUMBER@\/@STRING@\/@BOOLEAN@\/@DATE@ — in an annotation caramelisation
-- rebuilds in place and 'substLocals' splices intact. That is exactly the fact
-- the discarded 'Unique' would have given.
feelOrderable :: TypeOracle -> Expr Resolved -> Bool
feelOrderable oracle e = builtinOperandType oracle e `elem` [DmnNumber, DmnString, DmnDate]

-- | Is this operand a @BOOLEAN@ — the one type L4 orders and FEEL does not?
isBooleanOperand :: TypeOracle -> Expr Resolved -> Bool
isBooleanOperand oracle e = builtinOperandType oracle e == DmnBoolean

-- | The operand\'s type as a FEEL /builtin/, with the enum collapse deliberately
-- switched off.
--
-- 'oracleClassify' maps an @IS ONE OF@ to a named itemDefinition over @string@, which
-- is right for a typeRef — an enum\'s values serialise as strings — but wrong as
-- a licence to ORDER them. @max("red", "green")@ compares constructor
-- SPELLINGS, and the L4 declaration order those constructors were written in is
-- the only ordering the source ever suggested. Passing the empty environment
-- makes 'classifyType' fall through to 'builtinType', so an enum answers
-- 'DmnAny' here and fails both gates.
builtinOperandType :: TypeOracle -> Expr Resolved -> DmnType
builtinOperandType o = annTypeOf emptyTypeEnv o.toSubst o.toUri

isSelectIdiomIn :: TypeOracle -> Expr Resolved -> Bool
isSelectIdiomIn oracle = isJust . selectIdiomIn oracle

isSelectShape :: Expr Resolved -> Bool
isSelectShape = isJust . selectShape

-- | Lifted @max@\/@min@ whose operands include a literal or a named constant.
--
-- Lifting is right (see 'selectIdiom'), but it has a real cost that the report
-- must not swallow: the Reg CF $2,500 investment floor becomes part of
-- @max(2500, …)@ instead of being a row a compliance reader can point at. Two
-- symmetric computed quantities (@max(annual income, net worth)@) are
-- arithmetic and get no note; a named or literal threshold as one operand is
-- policy, and does.
liftedThresholds :: TableCtx -> Expr Resolved -> [(Text, Expr Resolved)]
liftedThresholds ctx top =
  [ (fn, sub)
  | sub <- toListOf (cosmosOf (gplate @(Expr Resolved))) top
  , Just (fn, a, b) <- [selectIdiomIn (oracleOf ctx) sub]
  , any isThreshold [a, b]
  ]
 where
  isThreshold = \case
    Lit _ _    -> True
    App _ r [] -> Set.member (getUnique r) ctx.tcConstants
    _          -> False

------------------------------------------------------------------------
-- WHERE / LET
------------------------------------------------------------------------

-- | Peel @WHERE@ and @LET@ wrappers off a decision body, substituting every
-- local into the expression that used it.
--
-- 'normaliseGuarded' matches only @IfThenElse@ \/ @MultiWayIf@ \/ @Consider@, so
-- a @WHERE@-wrapped chain is invisible to it — and the corpus\'s best decision
-- tables are all @WHERE@-wrapped. Peeling is therefore not a nicety.
--
-- __Inlining, not hoisting.__ A @WHERE@-local could in principle become its own
-- DRG decision, but DMN\'s decisions are globally named where L4\'s locals are
-- lexically scoped, so hoisting invites collisions between two decisions that
-- each happen to define @aggregate@. The DRG still gets a real dependency chain
-- from the module\'s top-level @MEANS@ declarations.
--
-- Bails (rather than producing a table with dangling names) when a local takes
-- parameters, is an @ASSUME@, performs I\/O, or is recursive.
peelLocals :: Expr Resolved -> Either FidelityLoss (Expr Resolved, [Text])
peelLocals = collect Map.empty []
 where
  collect env names = \case
    Where _ body ds -> absorb env names body ds
    LetIn _ ds body -> absorb env names body ds
    e               -> Right (substLocals env e, reverse names)

  absorb env names body ds = do
    bindings <- traverse binding ds
    env' <- resolveEnv (env <> Map.fromList [(u, b) | (u, _, b) <- bindings])
    collect env' (reverse [nm | (_, nm, _) <- bindings] <> names) body

  binding = \case
    LocalDecide _ (MkDecide _ _ (MkAppForm _ n [] _) b)
      | not (hasEffectfulNode b) -> Right (getUnique n, nameOf n, b)
    _ -> Left UninlinableLocal

  -- Later locals may reference earlier ones (and, in a WHERE, vice versa), so
  -- substitute the environment into itself until it stops changing. Bounded by
  -- the number of bindings; anything still self-referential after that is
  -- recursive, which has no closed form.
  resolveEnv raw =
    let step m = Map.map (substLocals m) m
        fixed  = iterate step raw !! Map.size raw
    in if any (mentions (Map.keysSet raw)) (Map.elems fixed)
         then Left UninlinableLocal
         else Right fixed

  mentions keys e =
    or [Set.member (getUnique r) keys | App _ r [] <- toListOf (cosmosOf (gplate @(Expr Resolved))) e]

-- | Replace every nullary reference to a bound local with its body.
substLocals :: Map Unique (Expr Resolved) -> Expr Resolved -> Expr Resolved
substLocals env
  | Map.null env = id
  | otherwise    = go
 where
  go e = case e of
    App _ r [] | Just b <- Map.lookup (getUnique r) env -> b
    _ -> over (gplate @(Expr Resolved)) go e

------------------------------------------------------------------------
-- Flattening nested chains
------------------------------------------------------------------------

-- | How deep to splice nested chains, and how many rules to tolerate.
--
-- @IF a THEN x ELSE IF b THEN y ELSE IF c THEN z ELSE w@ normalises to ONE row
-- plus an @OTHERWISE@ that is itself a chain. Lowered naively that is a
-- one-rule table whose default output is a nested conditional — the opaque
-- ribbon this programme exists to remove, relocated into DMN. So splice:
--
-- > row (g, b) where b normalises to [(h1,c1) … (hm,cm)] + otherwise c0
-- >   =>  (g and h1, c1) … (g and hm, cm), (g, c0)
--
-- The final @(g, c0)@ is correct under @First@, and the parent\'s negated prefix
-- stays implicit for the same reason no other prefix is materialised.
--
-- The caps are not paranoia: nesting multiplies, and an unbounded splice on a
-- deeply nested rule is a table-size explosion.
maxFlattenDepth, maxFlattenRows :: Int
maxFlattenDepth = 4
maxFlattenRows  = 64

-- | Splice nested chains into more rows. Returns the flattened chain and the
-- bodies left unflattened by a cap.
--
-- Deliberately type-blind: @childOf@ below asks 'selectShape', not
-- 'selectIdiomIn'. Whether the select may be FOLDED is a question about FEEL\'s
-- domain; whether it may be EXPANDED is a question about isomorphism, and the
-- answer to the second is no for every operand type.
flattenGuarded :: GuardedRows -> (GuardedRows, [Expr Resolved])
flattenGuarded rs0
  | length flat.grRows > maxFlattenRows = (rs0, [b | (_, b) <- rs0.grRows, isJust (childOf b)])
  | otherwise                           = (flat, capped)
 where
  (flat, capped) = go maxFlattenDepth rs0

  go depth rs =
    let expanded = map (expandRow depth) rs.grRows
        (othRows, othFinal, othDisj, othCapped) = expandOtherwise depth rs.grOtherwise
        rows = concatMap (\(r, _, _) -> r) expanded <> othRows
        -- Disjointness composes: the flattened family is exclusive iff the
        -- parent family was AND every child family is AND no child contributed
        -- a bare catch-all row (which its siblings' guards all imply).
        disjoint = rs.grDisjoint && and [d | (_, d, _) <- expanded] && othDisj
    in ( MkGuardedRows
           { grRows      = rows
           , grOtherwise = othFinal
           , grDisjoint  = disjoint
           }
       , concatMap (\(_, _, c) -> c) expanded <> othCapped
       )

  expandRow depth (g, b) = case childOf b of
    Nothing  -> ([(g, b)], True, [])
    Just sub
      | depth <= 0 -> ([(g, b)], True, [b])
      | otherwise ->
          let (child, ccapped) = go (depth - 1) sub
          in ( [(conj g h, c) | (h, c) <- child.grRows]
                 <> [(g, c0) | Just c0 <- [child.grOtherwise]]
             , child.grDisjoint && isNothing child.grOtherwise
             , ccapped
             )

  expandOtherwise _ Nothing = ([], Nothing, True, [])
  expandOtherwise depth (Just b0) = case childOf b0 of
    Just sub | depth > 0 ->
      let (child, ccapped) = go (depth - 1) sub
      -- Splicing the OTHERWISE's rows AFTER the parent's is exactly First; but
      -- the parent's guards and these need not exclude one another, so once any
      -- parent row exists the family is no longer provably disjoint.
      in (child.grRows, child.grOtherwise, False, ccapped)
    _ -> ([], Just b0, True, [])

  conj = And emptyAnno

  -- Reuse the normaliser's own answer rather than re-deriving its bail
  -- conditions, and refuse the two cases this module adds on top of them.
  childOf b
    | isSelectShape b    = Nothing
    | hasEffectfulNode b = Nothing
    | otherwise = case normaliseGuarded b of
        Just sub
          | not (rowsElided b sub)
          , not (any (hasEffectfulNode . fst) sub.grRows) -> Just sub
        _ -> Nothing

------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------

-- | What the module's own @DECLARE@s say about a type.
--
-- Phase 3 replaced a bare @Set Unique@ of "enums" with this, because the old
-- set answered one question ("does this collapse to @string@?") and lost two
-- others in the same step: /which/ itemDefinition the type is, and what its
-- domain is. §3 and §4.2 want both, and one walk of the type now produces both.
data TypeEnv = MkTypeEnv
  { teNamed   :: !(Map Unique Text)
    -- ^ type 'Unique' -> the minted @itemDefinition@'s FEEL name. Module-local
    -- declarations only: 'topDecls' does not descend into imports, so a type
    -- declared elsewhere has no definition to point at and stays @Any@.
  , teDomains :: !(Map Unique [Text])
    -- ^ type 'Unique' -> its constructor names, in __declaration order__ and in
    -- the __'nameOf' spelling__. Not 'feelIdentText': a constructor name becomes
    -- a FEEL /string literal/ (the tag value), never an identifier, so the name
    -- fold must not touch it (§5.3.6) — and this is precisely the string the
    -- cells already carry, so a domain and a cell cannot disagree.
  , tePayload :: !(Set Unique)
    -- ^ types that are payload-carrying @IS ONE OF@s: more than one
    -- constructor, at least one of which declares fields. R4-a's subject.
  , teOptional :: !(Map Unique Text)
    -- ^ type 'Unique' -> the FEEL name of its __domain-free alias__, for the
    -- types that have a domain at all (R8-a's carve-out, §11-R8-a).
    --
    -- A @MAYBE τ@ site points here instead of at 'teNamed' when τ is one of
    -- them, because pointing at τ's own definition would defeat R8-b one
    -- @typeRef@ hop away: R8-b suppresses @allowedValues@ /at the element/,
    -- §7.3.3 makes @allowedValues@ the __complete__ range of the definition
    -- reached through the @typeRef@, and nothing this exporter emits lowers to
    -- @null@ — so an enforcing engine would reject the absent case that is the
    -- whole content of the @MAYBE@. That is an answer change, not a reporting
    -- gap, which is why it is repaired in the artifact rather than in prose.
    --
    -- Empty for a τ with no domain: a record, a builtin and a @LIST OF@ assert
    -- no range to begin with, so R8-a's plain lowering is already correct for
    -- them and an alias would be the pure ceremony §4.3 refuses.
  , teUri     :: !NormalizedUri
    -- ^ the module being lowered, so "declared in another module" is decidable.
  }

emptyTypeEnv :: TypeEnv
emptyTypeEnv = MkTypeEnv
  { teNamed    = Map.empty
  , teDomains  = Map.empty
  , tePayload  = Set.empty
  , teOptional = Map.empty
  , teUri      = toNormalizedUri (Uri "")
  }

-- | What a classification found on the way that the @typeRef@ alone cannot say.
--
-- These are the R8 flags plus the two @D-ITEMDEF@ reasons. They exist because
-- the answer "this element is typed @number@" is true and incomplete when the
-- L4 said @MAYBE NUMBER@: the loss is real, it is not visible in the artifact,
-- and the only place it can be reported from is the walk that erased it.
data TypeFlags = MkTypeFlags
  { tfMaybe         :: !Bool  -- ^ a @MAYBE τ@ was lowered to τ's own typeRef (R8-a)
  , tfOptionalAlias :: !(Maybe (Text, Text))
    -- ^ ...and τ had a finite domain, so the element points at a __domain-free
    -- alias__ instead: @Just (the alias's name, τ's own name)@.
    --
    -- This is R8-a's carve-out, and it exists because the plain lowering was
    -- __defeated one @typeRef@ hop away__. R8-b suppresses @allowedValues@ \/
    -- @inputValues@ /at the element/; §7.3.3 then makes the @allowedValues@ of
    -- whatever the @typeRef@ resolves to the __complete__ range of the element
    -- — so pointing a @MAYBE@ site at τ's own definition re-asserts, one hop
    -- on, exactly the range R8-b just refused to write, and it is a range with
    -- no absent case in it. Nothing this exporter emits lowers to @null@, so
    -- under an enforcing engine the absent case that is the whole content of
    -- the @MAYBE@ is rejected: an answer change.
    --
    -- Nothing but a 'DmnNamed' with a domain can reach this field, because
    -- 'classifyType' returns a domain only from the branch that mints a name.
    -- A record, a builtin and a @LIST OF@ keep R8-a's plain lowering and leave
    -- this 'Nothing' — they assert no range, so there is nothing to defeat.
  , tfNestedMaybe   :: !Bool  -- ^ @MAYBE (MAYBE τ)@: refused, because @null@ does not nest (R8-c)
  , tfEither        :: !Bool  -- ^ @EITHER a b@: refused (R8-e)
  , tfList          :: !Bool  -- ^ @LIST OF τ@: @isCollection@ needs an itemDefinition of its own
  , tfForeign       :: !Bool  -- ^ a type declared in another module, so no itemDefinition exists
  }
  deriving stock (Eq, Show, Generic)

noTypeFlags :: TypeFlags
noTypeFlags = MkTypeFlags
  { tfMaybe = False, tfOptionalAlias = Nothing, tfNestedMaybe = False, tfEither = False
  , tfList = False, tfForeign = False
  }

oracleType :: TypeOracle -> Expr Resolved -> DmnType
oracleType o e = let (t, _, _) = oracleClassify o e in t

-- | The classifier, asked about an expression's inferred type.
oracleClassify :: TypeOracle -> Expr Resolved -> (DmnType, Maybe [Text], TypeFlags)
oracleClassify o e = case annTypeSource o e of
  Just ty -> classifyType o.toTypes ty
  Nothing -> (DmnAny, Nothing, noTypeFlags)

-- | An expression's inferred type, with the final substitution applied.
annTypeSource :: TypeOracle -> Expr Resolved -> Maybe (Type' Resolved)
annTypeSource o e = case (getAnno e).extra.resolvedInfo of
  Just (TypeInfo ty _) -> Just (TC.applyFinalSubstitution o.toSubst o.toUri ty)
  _                    -> Nothing

-- | Kept separate from 'oracleClassify' on purpose: 'TableCtx' has strict fields, so a
-- caller computing @tcOutputType@ from an expression's annotation cannot go
-- through the context it is in the middle of building.
annTypeOf :: TypeEnv -> TC.Substitution -> NormalizedUri -> Expr Resolved -> DmnType
annTypeOf env subst uri =
  oracleType MkTypeOracle { toTypes = env, toSubst = subst, toUri = uri }

-- | FEEL's type system is numbers, strings, booleans, dates, lists and contexts
-- — no algebraic data types. What it /does/ have is the __context__, which is a
-- record, and DMN's @itemDefinition@ is how you name one. So a module-local
-- @DECLARE@ maps across (§4.1, §4.2) and everything else is honestly @Any@.
--
-- Returns the @typeRef@, the type's __domain__ if it has a finite one, and the
-- 'TypeFlags' the walk found. One walk rather than three, because §3's column
-- domains and §4.2's @allowedValues@ are the same question asked at two scopes,
-- and answering them separately is how they drift.
--
-- The rules, in the order they are tested:
--
--   * @NUMBER@ \/ @STRING@ \/ @BOOLEAN@ \/ @DATE@ — a builtin @typeRef@, and
--     __no itemDefinition__ (§4.3: an alias over @number@ adds no information
--     and degrades for a consumer that does not resolve typeRefs).
--   * a module-local __record__ — @DmnNamed@, no domain.
--   * a module-local __@IS ONE OF@__ — @DmnNamed@ over @string@, domain =
--     __every__ constructor, including payload-carrying ones. Listing them all
--     is what makes the missing constructor visible to a gap analyser as a gap
--     (§4.2.1-9); listing only the nullary ones would assert a domain the type
--     does not have.
--   * @MAYBE τ@ — __τ's own typeRef__, and __no domain at this element__ (R8-a,
--     R8-b): @tItemDefinition@ has no nullability flag, so the @MAYBE@ is
--     recorded in the fidelity report rather than spelled in the artifact; and
--     §7.3.3 makes @allowedValues@ the /complete/ range, which a list that
--     cannot include @null@ would not be.
--   * @MAYBE τ@ __where τ carries a domain__ — a __domain-free alias__ of τ
--     ('teOptional'), because there the plain lowering is not merely lossy but
--     wrong: §7.3.3 reads the range off whatever the @typeRef@ resolves to, so
--     pointing at τ's own definition re-asserts one hop on the complete range
--     R8-b just suppressed, and that range has no absent case. The alias is
--     __not__ a way to spell nullability — @tItemDefinition@ still cannot — it
--     is what keeps R8-b's suppression from being undone by the hop.
--     'tfOptionalAlias' records both names so @D-MAYBE-NULL@ can report what
--     the alias costs: no engine-side validation of the values that /are/
--     present at this site.
--   * @MAYBE (MAYBE τ)@ — @Any@ and refused (R8-c). @null@ does not nest, so
--     @JUST NOTHING@ and @NOTHING@ would become one FEEL value and FEEL @=@
--     would answer @true@ where L4 answers @false@. That is an answer change.
--   * @EITHER a b@ — @Any@ and refused (R8-e).
--   * @LIST OF τ@ — @Any@. @isCollection@ is an attribute of
--     @tItemDefinition@, so a list needs a definition of its own; @D-ITEMDEF@.
--   * a type declared in __another module__ — @Any@, because 'topDecls' is
--     module-local and there is nothing to point a @typeRef@ at; @D-ITEMDEF@.
classifyType :: TypeEnv -> Type' Resolved -> (DmnType, Maybe [Text], TypeFlags)
classifyType env = go False
 where
  go inMaybe = \case
    TyApp _ n args -> case args of
      [inner] | getUnique n == TC.maybeUnique ->
        if inMaybe
          then (DmnAny, Nothing, noTypeFlags { tfMaybe = True, tfNestedMaybe = True })
          else
            -- R8-a, and R8-a's carve-out. τ's own typeRef is the answer unless
            -- τ carries a domain, in which case pointing at it would re-assert
            -- through the hop the complete range R8-b just suppressed. Those
            -- sites get the domain-free alias instead; everything else is
            -- unchanged.
            let (t, dom, f) = go True inner
                aliased = do
                  _ <- dom
                  u <- typeHeadUnique inner
                  a <- Map.lookup u env.teOptional
                  pure (a, dmnTypeAttr t)
            in case aliased of
                 Just (a, base) ->
                   ( DmnNamed a (dmnTypeBase t)
                   , Nothing
                   , f { tfMaybe = True, tfOptionalAlias = Just (a, base) }
                   )
                 Nothing -> (t, Nothing, f { tfMaybe = True })
      [] -> named (getUnique n)
      _ : _
        | getUnique n == TC.eitherUnique -> (DmnAny, Nothing, noTypeFlags { tfEither = True })
        | getUnique n == TC.listUnique   -> (DmnAny, Nothing, noTypeFlags { tfList = True })
        | otherwise                      -> (DmnAny, Nothing, noTypeFlags)
    _ -> (DmnAny, Nothing, noTypeFlags)

  named u
    | Just nm <- Map.lookup u env.teNamed =
        ( DmnNamed nm (if Map.member u env.teDomains then DmnString else DmnAny)
        , Map.lookup u env.teDomains
        , noTypeFlags
        )
    | builtinType u /= DmnAny = (builtinType u, Nothing, noTypeFlags)
    | otherwise               = (DmnAny, Nothing, noTypeFlags { tfForeign = foreign_ u })

  -- An inference variable's Unique belongs to no module and must not be
  -- reported as an unresolvable import; only a name the checker actually
  -- resolved somewhere else is.
  foreign_ u = u.moduleUri /= env.teUri && env.teUri /= toNormalizedUri (Uri "")

-- | One module-local @DECLARE@ that earns an @itemDefinition@ (§4.1, §4.2).
--
-- Not exported: it is the shape of an analysis "L4.Dmn.Lower" runs once over
-- the module's declarations, and every consumer downstream sees the
-- 'ItemDefinition' it produces instead.
data ItemDecl = MkItemDecl
  { itdUnique   :: !Unique
  , itdName     :: !Text                            -- ^ the verbatim L4 type name
  , itdCtors    :: ![Text]                          -- ^ @IS ONE OF@: constructors in declaration order
  , itdFields   :: ![(Resolved, Type' Resolved)]    -- ^ record: STORED fields in declaration order
  , itdComputed :: ![Text]                          -- ^ record: computed fields, which are skipped
  , itdPayload  :: !Bool                            -- ^ a multi-constructor union with a payload arm
  }

-- | The head type constructor of a type, seen through a @MAYBE@.
typeHeadUnique :: Type' Resolved -> Maybe Unique
typeHeadUnique = \case
  TyApp _ n [inner] | getUnique n == TC.maybeUnique -> typeHeadUnique inner
  TyApp _ n []                                      -> Just (getUnique n)
  _                                                 -> Nothing

builtinType :: Unique -> DmnType
builtinType u
  | u == TC.numberUnique  = DmnNumber
  | u == TC.stringUnique  = DmnString
  | u == TC.booleanUnique = DmnBoolean
  | u == TC.dateUnique    = DmnDate
  | otherwise             = DmnAny

------------------------------------------------------------------------
-- Notes
------------------------------------------------------------------------

-- | The note codes this backend emits. All prefixed @D-@ so they cannot collide
-- with the process-side backend's in a combined report.
--
-- Severity follows the shared vocabulary: 'Blocking' means DMN cannot express
-- the thing at all and we emitted a fallback; 'Lossy' means something the L4
-- said is gone; 'Advisory' means the emission is faithful but a /target-side/
-- capability is forfeited. Most of these are Advisory, and that is the point —
-- the losses are properties of DMN, not defects in the export.
--
-- The codes, and the line between the two severities that matters most here:
--
-- [@D-NONFEELINPUT@ (Blocking)] an input expression is L4 source, not FEEL
--   ('L4Verbatim'). No engine can evaluate the table.
-- [@D-NONFEELOUTPUT@ (Blocking)] an output entry is L4 source, not FEEL.
-- [@D-LITERALEXPR@ (Blocking)] the decision has no table shape and became a
--   boxed literal expression.
-- [@D-SCOPE@ (Lossy)] two differently-scoped L4 terms collide on one DMN
--   @inputData@ name.
-- [@D-NONFEEL@ (Advisory)] the input expression is /valid/ FEEL but outside
--   S-FEEL.
-- [@D-COMPUTEDOUTPUT@ (Advisory)] the output entry is /valid/ FEEL but an
--   expression rather than a constant.
-- [@D-UNDECOMPOSABLE@, @D-HITPOLICY@, @D-ORDERDEPENDENT@, @D-INLINEDLOCAL@,
--  @D-FLATTENCAP@, @D-LIFTEDTHRESHOLD@ (Advisory)] faithful emissions that
--   forfeit a DMN-side capability.
--
-- __The @NONFEEL@\/valid-FEEL split is a soundness boundary, not a gradation.__
-- Before it existed, an 'L4Verbatim' cell — DMN that no engine can execute —
-- was reported by @D-COMPUTEDOUTPUT@, whose message ("an expression, not a
-- constant") describes a much milder problem, and on the input side it could be
-- suppressed entirely. A reader who acts on an Advisory note ships a model that
-- fails at run time, and 18 of the 28 corpus instances failed /silently/ (a
-- verbatim @defaultOutputEntry@ evaluates to @null@ with status @SUCCEEDED@ on
-- Drools\/KIE 8.44). Each 'L4Verbatim' cell therefore raises exactly one
-- Blocking note and never also the Advisory one: the pairs
-- @D-NONFEELINPUT@\/@D-NONFEEL@ and @D-NONFEELOUTPUT@\/@D-COMPUTEDOUTPUT@ are
-- mutually exclusive by construction.
dmnNote :: Text -> FidelitySeverity -> Text -> Maybe SrcRange -> Text -> Text -> FidelityNote
dmnNote c sev el rng msg lostWhat =
  MkFidelityNote
    { code     = c
    , severity = sev
    , element  = el
    , range    = rng
    , message  = msg
    , lost     = lostWhat
    }

-- | The one Blocking note for an output position whose text is L4, not FEEL.
--
-- Shared by the decision-table path and the boxed-literal select-idiom path,
-- because the failure is the same in both and a reader must not have to know
-- which shape the exporter chose.
nonFeelOutput :: Text -> Maybe SrcRange -> FeelExpr -> FidelityNote
nonFeelOutput el rng fe =
  dmnNote "D-NONFEELOUTPUT" Blocking el rng
    ("the output entry `" <> fe.feText
       <> "` is L4 source, not FEEL: this backend has no FEEL rendering for it, so the text \
          \was emitted verbatim and NO DMN engine can evaluate it")
    "execution: an engine fails to compile the entry -- loudly when the rule fires, but \
    \SILENTLY (a null result, reported as success) when it is the defaultOutputEntry"

-- | @D-MAYBE-NULL@ (R8-a, R8-b): a @MAYBE τ@ was lowered to τ's own @typeRef@.
--
-- __Explicit and mandatory, not silent__, because of what the encoding costs.
-- The type-level half of R8 is sound: §2.4's refusal is about L4's /error/
-- channel, and @NOTHING@ is a value of a total function, not a raise — §2.4.1
-- says so itself when it accepts @TO NUMBER@ \/ @TO DATE@ as "genuinely total"
-- precisely /because/ they return a @MAYBE@. What the encoding does lose is a
-- distinction the target cannot make: FEEL has one @null@, and it spells both
-- "the rule says there is none" and "the engine could not compute it". L4 keeps
-- those apart; the artifact cannot, and no reader or analyser can recover which
-- was meant. That is a fidelity loss rather than a soundness one — hence
-- 'Lossy' — and it is exactly what a fidelity report is for.
--
-- The second sentence fires only when τ is a __named__ type with a finite
-- domain, and it reports an alias rather than a loss of domain. R8-b suppresses
-- @allowedValues@ \/ @inputValues@ /at this element/, and the reason stands:
-- §7.3.3 makes @allowedValues@ the __complete__ range of values the type
-- represents, DMN 1.3's grammar rules 13-17 make an S-FEEL endpoint a @simple
-- value@, and @null@ (rule 34, a /literal/) is not one — so a list written here
-- would exclude a value the type admits. The suppression would not survive the
-- @typeRef@ hop, though, because §7.3.3 reads the range off the definition the
-- @typeRef@ resolves to: pointing at τ's own would re-assert the very range
-- just suppressed. So the element points at a __domain-free alias__ of τ
-- instead (R8-a's carve-out).
--
-- __What that costs, and what it does not.__ It does not spell nullability;
-- @tItemDefinition@ has no flag for it and the alias invents none, which is why
-- the note fires here at all. What it forfeits is the /other/ half of the
-- domain's job: at this site an engine no longer validates the values that
-- __are__ present, so a string outside τ's constructors passes where at a
-- non-@MAYBE@ site it would be rejected. That is a checking loss on the present
-- case, deliberately taken to keep the absent case admissible — and naming both
-- the alias and τ is what lets a reader see the trade in the artifact.
maybeNullNote :: Text -> Maybe SrcRange -> Text -> Text -> Maybe (Text, Text) -> FidelityNote
maybeNullNote el rng what tyText optionalAlias =
  dmnNote "D-MAYBE-NULL" Lossy el rng
    ( what <> " is declared `" <> tyText
        <> "`, and DMN has no nullability marker -- tItemDefinition has no such flag -- so the \
           \emitted typeRef is the payload type's own. FEEL has one `null` and it means both \
           \\"there is no value\" and \"the value could not be computed\", so NOTHING and an \
           \undefined result can no longer be told apart in the artifact"
        <> case optionalAlias of
             Just (alias, base) ->
               ". No allowedValues or inputValues is emitted AT THIS ELEMENT, because DMN 7.3.3 \
               \makes allowedValues the COMPLETE range of values a type represents and `null` is \
               \not a legal S-FEEL endpoint -- and because that range is read through the typeRef, \
               \this element points at `" <> alias <> "`, a domain-free alias of `" <> base
               <> "`, rather than at `" <> base <> "` itself. Pointing at `" <> base
               <> "` would re-assert its complete range one hop on, and that range has no absent \
                  \case in it, so an enforcing engine would reject the very NOTHING this type \
                  \exists to allow"
             Nothing -> ""
    )
    ("the distinction between an absent value and an undefined one"
       <> case optionalAlias of
            Just (_, base) ->
              ", and -- at THIS element only -- engine-side validation of the values that ARE \
              \present: `" <> base <> "`'s domain is deliberately not asserted here, so a value \
              \outside it is no longer rejected at this site"
            Nothing -> "")

tableNotes
  :: TableCtx
  -> [[Cell]]
  -> [Cell]
  -> [InputColumn]
  -> HitPolicy
  -> GuardedRows
  -> [Text]              -- ^ names of inlined WHERE/LET locals
  -> [Expr Resolved]     -- ^ bodies left unflattened by the cap
  -> [FidelityNote]
tableNotes ctx decomposed columnCells columns policy rows inlined cappedBodies =
  dedupeNotes $
    fallbackNotes <> nonFeelInputNotes <> sfeelNotes <> policyNotes
      <> nonFeelOutputNotes <> outputNotes
      <> inlineNotes <> capNotes <> thresholdNotes <> columnMaybeNotes
 where
  here = ctx.tcIdPrefix

  -- R8-a's column site. The output clause has no site of its own: this emitter
  -- deliberately emits no @typeRef@ on a @\<output\>@ (measured: KIE says
  -- ILLEGAL_USE_OF_TYPEREF), so a MAYBE-typed decision is reported once, at its
  -- own @\<variable\>@, in "lowerModule".
  columnMaybeNotes =
    [ maybeNullNote here (bestRange c.cellSubject)
        ("the column `" <> oneLine (prettyLayout c.cellSubject) <> "`")
        (oneLine (prettyLayout sty)) fl.tfOptionalAlias
    | c <- columnCells
    , Just sty <- [annTypeSource (oracleOf ctx) c.cellSubject]
    , let (_, _, fl) = classifyType ctx.tcTypes sty
    , fl.tfMaybe
    ]

  fallbackNotes =
    [ dmnNote "D-UNDECOMPOSABLE" Advisory here (bestRange c.cellSubject)
        ("the guard `" <> oneLine (prettyLayout c.cellSubject)
           <> "` has no constant endpoint, so it became its own boolean column rather than \
              \an input expression tested by a unary test")
        "interval gap and overlap analysis over this condition"
    | row <- decomposed, c <- row, c.cellNote
    ]

  -- A column born of a fallback already has a note; do not say it twice.
  fallbackKeys = Set.fromList [c.cellKey | row <- decomposed, c <- row, c.cellFallback]

  -- The input-side half of the soundness boundary, and the reason it is NOT
  -- filtered by 'fallbackKeys' the way 'sfeelNotes' is. That suppression is
  -- right for D-NONFEEL, which reports a lost DMN capability the fallback note
  -- has already reported in other words. It is wrong here: D-UNDECOMPOSABLE says
  -- "no constant endpoint, so it became a boolean column", which is true of
  -- perfectly executable columns and says nothing about executability. Three
  -- verified corpus shapes reached the shipped DMN through that gap — one with
  -- only D-UNDECOMPOSABLE, and two (a `Proj` of a verbatim object; a select
  -- idiom over an unrenderable operand) with no note at all.
  nonFeelInputNotes =
    [ dmnNote "D-NONFEELINPUT" Blocking here (bestRange c.cellSubject)
        ("the input expression `" <> col.icExpr.feText
           <> "` is L4 source, not FEEL: this backend has no FEEL rendering for it, so the \
              \text was emitted verbatim and NO DMN engine can evaluate this column")
        "execution: the table is well-formed DMN but the engine fails to compile the column, \
        \and every rule that tests it is silently treated as non-matching"
    | (col, c) <- zip columns columnCells
    , col.icExpr.feFragment == L4Verbatim
    ]

  sfeelNotes =
    [ dmnNote "D-NONFEEL" Advisory here (bestRange c.cellSubject)
        ("the input expression `" <> col.icExpr.feText
           <> "` is outside S-FEEL (which admits only arithmetic, simple values and comparisons)")
        "completeness, consistency and overlap checking, all of which DMN's analysis is defined over S-FEEL only"
    | (col, c) <- zip columns columnCells
    , col.icExpr.feFragment == FullFeel
    , not (Set.member c.cellKey fallbackKeys)
    ]

  -- Located at the first guard: these are properties of the whole table, and
  -- that is the nearest thing it has to a position.
  tableRange = listToMaybe (mapMaybe (bestRange . fst) rows.grRows)

  policyNotes =
    [ dmnNote "D-HITPOLICY" Advisory here tableRange
        "the L4 guards are provably exclusive, but the emitted columns cannot witness it, \
        \so the hit policy is First rather than Unique"
        "the reader's and the tool's ability to see that the rules cannot conflict"
    | rows.grDisjoint, policy == HitFirst
    ]
      <> [ dmnNote "D-ORDERDEPENDENT" Advisory here tableRange
             "hit policy First is order-dependent: DMN 8.2.10 says of such tables that \
             \\"the table is hard to validate manually and therefore has to be used with care\""
             "order-free reading; a rule cannot be checked without the rules above it"
         | policy == HitFirst
         , length rows.grRows + length (maybeToList rows.grOtherwise) > 1
         ]

  -- The whole point of the S-FEEL pincer, made concrete. DMN 8.2.9 says "a rule
  -- output entry is an expression", so this is legal and we emit it faithfully.
  -- But both Calvanese formalisations define an output entry as mapping to an
  -- OBJECT, so a computed-output table is outside the analysable fragment BY
  -- CONSTRUCTION -- and our flagship exhibit, a MIN/MAX of computed quantities,
  -- is exactly such a table. Saying nothing here would let a reader assume the
  -- DMN tooling can check a table it cannot.
  outputNotes =
    [ dmnNote "D-COMPUTEDOUTPUT" Advisory here (bestRange body)
        ("the output entry `" <> fe.feText
           <> "` is an expression, not a constant; DMN 8.2.9 permits that, but every published \
              \decision-table analysis defines an output entry as a constant")
        "gap and overlap analysis of this table: DMN renders it, DMN's checkers do not check it"
    | body <- outputBodies
    , let fe = renderFeelIn ctx.tcNames ctx.tcConstructors (oracleOf ctx) body
      -- MUTUALLY EXCLUSIVE with D-NONFEELOUTPUT. An L4Verbatim entry satisfies
      -- `not . isConstantText` too, and used to be reported by this Advisory
      -- note alone -- a note about ANALYSABILITY standing in for a failure of
      -- EXECUTABILITY. That is the defect this split fixes.
    , fe.feFragment /= L4Verbatim
    , not (isConstantText fe)
    ]

  -- The output-side half of the soundness boundary. DMN 8.2.9 does say "a rule
  -- output entry is an expression", so an expression here is legal -- but only
  -- if it is a FEEL expression. This text is not.
  nonFeelOutputNotes =
    [ nonFeelOutput here (bestRange body) fe
    | body <- outputBodies
    , let fe = renderFeelIn ctx.tcNames ctx.tcConstructors (oracleOf ctx) body
    , fe.feFragment == L4Verbatim
    ]

  outputBodies = map snd rows.grRows <> maybeToList rows.grOtherwise

  inlineNotes =
    [ dmnNote "D-INLINEDLOCAL" Advisory here tableRange
        ("the WHERE/LET local(s) " <> Text.intercalate ", " (map tick inlined)
           <> " were inlined into the cells that used them; DMN has no lexically scoped \
              \intermediate value")
        "the name the drafter gave the intermediate quantity"
    | not (null inlined)
    ]

  capNotes =
    [ dmnNote "D-FLATTENCAP" Advisory here (bestRange b)
        ("a nested guarded chain was left as an output expression rather than spliced into \
         \more rules, because flattening hit the depth or row cap")
        "the rows the nested chain would have contributed"
    | b <- cappedBodies
    ]

  thresholdNotes =
    [ dmnNote "D-LIFTEDTHRESHOLD" Advisory here (bestRange sub)
        ("`" <> oneLine (prettyLayout sub) <> "` was lifted to " <> fn
           <> "(...): the threshold is now inside an output expression rather than a row of the table")
        "a compliance reader's ability to point at the threshold as a rule"
    | body <- outputBodies
    , (fn, sub) <- liftedThresholds ctx body
    ]

  tick t = "`" <> t <> "`"

  isConstantText fe =
    fe.feFragment == SFeel
      && ( fe.feText `elem` ["true", "false"]
             || Text.isPrefixOf "\"" fe.feText
             || isNumericText fe.feText
         )

dedupeNotes :: [FidelityNote] -> [FidelityNote]
dedupeNotes = go Set.empty
 where
  go _ [] = []
  go seen (n : ns)
    | Set.member k seen = go seen ns
    | otherwise         = n : go (Set.insert k seen) ns
   where
    k = (n.code, n.message)

-- | The first source range anywhere under an expression. Guards synthesised by
-- 'normaliseGuarded' (a @CONSIDER@ arm becomes @scrutinee EQUALS ctor@) carry an
-- empty annotation at the root, but their scrutinee still knows where it came
-- from, so a note is still locatable.
bestRange :: Expr Resolved -> Maybe SrcRange
bestRange e =
  listToMaybe
    (mapMaybe (\x -> (getAnno x).range) (toListOf (cosmosOf (gplate @(Expr Resolved))) e))

------------------------------------------------------------------------
-- The module
------------------------------------------------------------------------

-- | Every top-level @DECIDE@ becomes a @\<decision\>@; every free term becomes an
-- @\<inputData\>@; references between decisions become
-- @\<informationRequirement\>@s.
lowerModule :: DmnLowerOptions -> Module Resolved -> Drg
lowerModule opts modul@(MkModule _ uri _) =
  MkDrg
    { drgId        = "definitions_" <> modelId
    , drgName      = opts.dloModelName
    , drgNamespace = "https://legalese.com/l4/dmn/" <> modelId
    , drgFlavor    = opts.dloFlavor
    , drgItemDefs  = itemDefs
    , drgNodes     = nodes
    , drgNotes     = sharedInputNotes <> renameNotes <> feelNameCollisionNotes
                       <> itemDefNotes <> componentMaybeNotes <> inputMaybeNotes
                       <> concatMap snd lowered
    }
 where
  modelId = sanitiseId opts.dloModelName

  -- Named rather than inlined into 'drgNodes' because the itemDefinition list
  -- reads the emitted types back off it, to decide which domain-free aliases
  -- are pointed at. Nothing flows the other way, so there is no knot.
  nodes = map NodeInputData inputNodes <> map (NodeDecision . fst) lowered

  decls   = topDecls modul
  decides = [d | Decide _ d <- decls]
  assumes = [a | Assume _ a <- decls]

  constructors = Set.fromList
    [ getUnique n | Declare _ (MkDeclare _ _ _ td) <- decls, n <- constructorNames td ]

  constructorNames = \case
    EnumDecl _ cds    -> [n | MkConDecl _ n _ <- cds]
    RecordDecl _ mn _ -> maybeToList mn
    SynonymDecl _ _   -> []

  -- Field selectors are references in the AST but are not terms; a record
  -- projection must not conjure an inputData element for the field name.
  selectors = Set.fromList
    [ getUnique n | Declare _ (MkDeclare _ _ _ td) <- decls, n <- selectorNames td ]

  selectorNames = \case
    EnumDecl _ cds    -> [n | MkConDecl _ _ fs <- cds, MkTypedName _ n _ _ _ <- fs]
    RecordDecl _ _ fs -> [n | MkTypedName _ n _ _ _ <- fs]
    SynonymDecl _ _   -> []

  -- §5.2 SCOPE 2: the record-field namespace. One 'uniquifyIn' PER DECLARED
  -- TYPE, in field source order, because that is the namespace DMN has -- an
  -- itemDefinition's itemComponent list, and until itemDefinitions exist
  -- (Phase 3) the projection paths this module emits. Two different records may
  -- each own a field that folds to `foo_bar` without either being renamed; two
  -- fields of ONE record may not, and that case is the corpus's one executed
  -- collision, which used to emit `p.foo_bar + p.foo_bar` -- valid FEEL,
  -- computing a wrong number, with no note (§5.3.4).
  fieldScopes :: [(Text, [(Resolved, Text, Text)])]
  fieldScopes =
    [ (nameOf tn, zip3 ns (map (feelIdentText . nameOf) ns) (uniquifyIn foldedNs))
    | Declare _ (MkDeclare _ _ (MkAppForm _ tn _ _) td) <- decls
    , let ns     = selectorNames td
    , let foldedNs = map (feelIdentText . nameOf) ns
    , not (null ns)
    ]

  fieldNames :: Map Unique Text
  fieldNames = Map.fromList
    [ (getUnique n, resolved) | (_, fs) <- fieldScopes, (n, _, resolved) <- fs ]

  ------------------------------------------------------------------------
  -- The data model (§4, Phase 3)
  ------------------------------------------------------------------------

  -- Every module-local DECLARE that has an itemDefinition, in source order.
  --
  -- __Referenced or not.__ Reachability-gating would make the artifact depend
  -- on which decisions happened to survive lowering -- a moving target that
  -- would change the type-level output of the export every time a body did --
  -- and an unreferenced itemDefinition is inert.
  itemDecls :: [ItemDecl]
  itemDecls =
    [ MkItemDecl
        { itdUnique   = getUnique tn
        , itdName     = nameOf tn
        -- Constructor spellings come from 'nameOf', NOT 'feelIdentText': a
        -- constructor name becomes a FEEL string LITERAL (the tag value), never
        -- an identifier, so the name fold must not touch it (§5.3.6). It is
        -- also the exact string the cells already carry, so the domain and the
        -- cells cannot disagree.
        , itdCtors    = ctors
        -- STORED fields only. The 5th field of 'MkTypedName' is `Just expr` for
        -- a COMPUTED field (a `MEANS` clause), which is derived rather than
        -- supplied; emitting it as an itemComponent would misstate the model's
        -- input contract, so it is skipped and reported D-ITEMDEF.
        --
        -- __The filter is unexercised on this tree, and the reason is worth
        -- knowing rather than discovering.__ "L4.Desugar" rewrites a computed
        -- field into a synthetic top-level @DECIDE@ __before type checking__,
        -- so the @Declare@ this module sees never carries one: on
        -- @jl4\/examples\/dmn\/sumtype.l4@, whose @Claim@ declares
        -- @`doubled amount` IS A NUMBER MEANS …@, the emitted itemDefinition
        -- has the other components and the field is a @\<decision\>@ of its own
        -- reading a @_self@ @inputData@ typed @Claim@. So the information is
        -- relocated, not dropped, and the D-ITEMDEF arm below has zero
        -- exercise. It is kept for the same reason @D-FEELNAME@ is (§7): the
        -- day the desugaring stops running before this pass, an input contract
        -- that silently gained a derived field is not a failure anyone would
        -- see.
        , itdFields   = [(fn, fty) | MkTypedName _ fn fty _ Nothing <- flds]
        , itdComputed = [nameOf fn | MkTypedName _ fn _ _ (Just _) <- flds]
        , itdPayload  = payload
        }
    | Declare _ (MkDeclare _ _ (MkAppForm _ tn _ _) td) <- decls
    , Just (ctors, flds, payload) <- [itemShapeOf td]
    ]

  -- @Just (constructor names, stored+computed fields, is a payload union)@, or
  -- 'Nothing' for a declaration that gets no itemDefinition.
  itemShapeOf = \case
    RecordDecl _ _ rfs -> Just ([], rfs, False)
    -- §4.2.1-7 leaves the SINGLE payload constructor unruled, and there are
    -- zero in the corpora, so the choice is free and stating it stops a guess:
    -- it is a record, and the itemDefinition is named after the TYPE, which is
    -- what §4.1 already does for `DECLARE T HAS`.
    EnumDecl _ [MkConDecl _ _ cfs] | not (null cfs) -> Just ([], cfs, False)
    EnumDecl _ cds ->
      Just
        ( [nameOf cn | MkConDecl _ cn _ <- cds]
        , []
        , length cds > 1 && any (\(MkConDecl _ _ cfs) -> not (null cfs)) cds
        )
    SynonymDecl _ _ -> Nothing

  itemDefIds   = assignIds "itemdef_" (map (.itdName) itemDecls)

  -- The types that assert a range, and therefore the ones a @MAYBE@ site needs
  -- a domain-free alias of (R8-a's carve-out).
  domainDecls = [d | d <- itemDecls, not (null d.itdCtors)]

  -- ONE 'uniquifyIn' scope (§5.2, A3), and it is the itemDefinition-name
  -- namespace only: DMN keeps that apart from the DRG's variable namespace, so
  -- a type and a variable may share a name without either being renamed.
  --
  -- __The aliases are minted in the same scope as the base names__, and after
  -- them, so a hand-written @DECLARE Grade_optional@ keeps its own name and the
  -- alias takes the suffix rather than the other way round. That is why this is
  -- one 'uniquifyIn' over a concatenation and not two: two scopes could hand
  -- the same string to a type and to an alias, and the alias would then silently
  -- acquire the domain it exists to drop.
  (itemDefNames, optionalNames) =
    splitAt (length itemDecls) $ uniquifyIn $
      map (feelTypeNameText . (.itdName)) itemDecls
        <> [feelTypeNameText d.itdName <> "_optional" | d <- domainDecls]

  optionalNameOf :: Map Unique Text
  optionalNameOf = Map.fromList (zip (map (.itdUnique) domainDecls) optionalNames)

  typeEnv :: TypeEnv
  typeEnv = MkTypeEnv
    { teNamed    = Map.fromList (zip (map (.itdUnique) itemDecls) itemDefNames)
    , teDomains  = Map.fromList
        [(d.itdUnique, d.itdCtors) | d <- itemDecls, not (null d.itdCtors)]
    , tePayload  = Set.fromList [d.itdUnique | d <- itemDecls, d.itdPayload]
    , teOptional = optionalNameOf
    , teUri      = uri
    }

  -- The base definitions, then the aliases any element actually points at.
  --
  -- __Alias minting is reachability-gated and the base definitions are not__,
  -- and the asymmetry is the point. A base definition is minted per @DECLARE@
  -- because an unreferenced one is inert and gating it would make the type
  -- half of the artifact move whenever a decision body did. An alias is not
  -- inert in the same way: it exists only to be the target of a @MAYBE@ site,
  -- so one with no referrer is noise in an artifact whose whole claim is that
  -- every line in it means something. The gate is the emitted 'DmnType's, not
  -- the L4, so what is minted and what is pointed at cannot disagree.
  itemDefs :: [ItemDefinition]
  itemDefs = baseItemDefs <> aliasItemDefs

  aliasItemDefs :: [ItemDefinition]
  aliasItemDefs =
    [ MkItemDefinition
        { idfId         = iid <> "_optional"
        , idfName       = anm
        -- The L4 type name, verbatim, exactly as the base definition carries
        -- it: the alias IS `Grade`, minus the range. A reader who wants to
        -- know which values it holds reads the label and finds the base.
        , idfLabel      = d.itdName
        , idfBase       = Just DmnString
        -- The whole content of the alias. R8-b's suppression is what this
        -- Nothing spells, and it is spelled HERE so that the typeRef hop
        -- cannot undo it.
        , idfValues     = Nothing
        , idfComponents = []
        }
    | (d, iid) <- zip itemDecls itemDefIds
    , Just anm <- [Map.lookup d.itdUnique optionalNameOf]
    , Set.member anm referencedTypeNames
    ]

  -- Every minted type name some element's typeRef actually resolves to.
  referencedTypeNames :: Set Text
  referencedTypeNames = Set.fromList
    [ nm
    | DmnNamed nm _ <-
        concatMap nodeTypeRefs nodes
          <> [c.icmType | b <- baseItemDefs, c <- b.idfComponents]
    ]

  nodeTypeRefs :: DrgNode -> [DmnType]
  nodeTypeRefs = \case
    NodeInputData i -> [i.idType]
    NodeDecision  d -> d.dcnType : case d.dcnLogic of
      LogicTable t   -> map (.icType) t.dtInputs
      LogicLiteral _ -> []

  baseItemDefs :: [ItemDefinition]
  baseItemDefs =
    [ MkItemDefinition
        { idfId         = iid
        , idfName       = fnm
        , idfLabel      = d.itdName
        -- An enum's values serialise as strings, so its definition is a string
        -- with a domain; a record's definition IS the component list and has no
        -- base typeRef at all.
        , idfBase       = if null d.itdCtors then Nothing else Just DmnString
        , idfValues     = if null d.itdCtors then Nothing else Just d.itdCtors
        , idfComponents = zipWith (itemComponent iid) [1 :: Int ..] d.itdFields
        }
    | (d, iid, fnm) <- zip3 itemDecls itemDefIds itemDefNames
    ]

  -- The component's name comes from the SAME map a projection path reads
  -- ('fieldNames', §5.2 scope 2), so `r.f` and the component it names are one
  -- string by construction rather than by two functions agreeing.
  itemComponent iid i (fn, fty) = MkItemComponent
    { icmId    = iid <> "_c" <> tshow i
    , icmName  = Map.findWithDefault (feelIdentText (nameOf fn)) (getUnique fn) fieldNames
    , icmLabel = nameOf fn
    , icmType  = let (t, _, _) = classifyType typeEnv fty in t
    }

  -- D-ITEMDEF: one code, three reasons, so the report stays readable.
  itemDefNotes =
    [ dmnNote "D-ITEMDEF" Lossy iid Nothing
        ("`" <> d.itdName <> "`'s field `" <> f
           <> "` is COMPUTED (it is declared with a MEANS clause), so it is not part of the \
              \model's input contract and no <itemComponent> was emitted for it; DMN has no \
              \notion of a derived component")
        "the derived field: a reader of the itemDefinition cannot see that the type has it"
    | (d, iid) <- zip itemDecls itemDefIds
    , f <- d.itdComputed
    ]
      <> [ dmnNote "D-ITEMDEF" Lossy (iid <> "_c" <> tshow i) Nothing
             ("`" <> d.itdName <> "`'s component `" <> nameOf fn <> "` is typed `"
                <> oneLine (prettyLayout fty) <> "`, " <> reason
                <> ", so it is emitted as typeRef=\"Any\"")
             "the component's declared type; nothing downstream can tell what it holds"
         | (d, iid) <- zip itemDecls itemDefIds
         , (i, (fn, fty)) <- zip [1 :: Int ..] d.itdFields
         , let (_, _, fl) = classifyType typeEnv fty
         , Just reason <- [itemDefReason fl]
         ]

  -- @Nothing@ when the component's type needed no explanation.
  itemDefReason fl
    | fl.tfList =
        Just "and a collection needs an itemDefinition of its OWN -- isCollection is an \
             \attribute of tItemDefinition, not of a typeRef -- which this phase does not mint"
    | fl.tfForeign =
        Just "and it is declared in ANOTHER MODULE: this exporter lowers one module at a time, \
             \so there is no itemDefinition in this file to point a typeRef at"
    | otherwise = Nothing

  -- R8-a at the itemComponent site.
  componentMaybeNotes =
    [ maybeNullNote (iid <> "_c" <> tshow i) Nothing
        ("`" <> d.itdName <> "`'s component `" <> nameOf fn <> "`")
        (oneLine (prettyLayout fty)) fl.tfOptionalAlias
    | (d, iid) <- zip itemDecls itemDefIds
    , (i, (fn, fty)) <- zip [1 :: Int ..] d.itdFields
    , let (_, _, fl) = classifyType typeEnv fty
    , fl.tfMaybe
    ]

  -- Which module-local records THREAD a payload-carrying sum type: R4-a's
  -- second `Lossy` arm, reported at the decision that passes the record around.
  --
  -- The third component is the typeRef the itemComponent is ACTUALLY emitted
  -- with, taken from the same 'classifyType' call 'itemComponent' uses rather
  -- than from a constant in the message. It used to be spelled "Any" in the
  -- note's prose while the artifact emitted the minted name, which is the kind
  -- of claim only the artifact can settle -- so the note now reads it off the
  -- same computation the emitter does.
  sumFieldRecords :: Map Unique [(Text, Text, Text)]
  sumFieldRecords = Map.fromList
    [ (d.itdUnique, threaded)
    | d <- itemDecls
    , let threaded =
            [ ( nameOf fn
              , Map.findWithDefault "" hu itemDeclNames
              , let (t, _, _) = classifyType typeEnv fty in dmnTypeAttr t
              )
            | (fn, fty) <- d.itdFields
            , Just hu <- [typeHeadUnique fty]
            , Set.member hu typeEnv.tePayload
            ]
    , not (null threaded)
    ]

  itemDeclNames = Map.fromList [(d.itdUnique, d.itdName) | d <- itemDecls]

  -- The constructors and selectors of a payload-carrying union, each mapped to
  -- the L4 name of the type that owns it. R4-a's first three reading forms are
  -- membership tests against this.
  payloadOwner :: Map Unique Text
  payloadOwner = Map.fromList
    [ (u, nameOf tn)
    | Declare _ (MkDeclare _ _ (MkAppForm _ tn _ _) (EnumDecl _ cds)) <- decls
    , length cds > 1
    , MkConDecl _ cn cfs <- cds
    , not (null cfs)
    , u <- getUnique cn : [getUnique fn | MkTypedName _ fn _ _ _ <- cfs]
    ]

  decideIds      = assignIds "decision_" (map decideName decides)

  -- A nullary decision whose body is a literal is a NAMED THRESHOLD -- the thing
  -- that makes a lifted max/min worth a D-LIFTEDTHRESHOLD note.
  namedConstants = Set.fromList
    [ getUnique n
    | MkDecide _ _ (MkAppForm _ n [] _) b <- decides
    , Lit _ _ <- [carameliseExpr b]
    ]
  decideByUnique = Map.fromList (zip (map (getUnique . decideResolved) decides) decideIds)

  -- Free terms, collected across every decision first so that ids and types are
  -- assigned once, in a source-determined order.
  freeTerms :: [(Unique, Text)]
  freeTerms = nubOrdOn fst (concatMap decideFreeTerms decides)

  decideFreeTerms d =
    [ (getUnique r, nameOf r)
    | r <- freeRefs d
    , let u = getUnique r
    , u.moduleUri == uri
    , not (Map.member u decideByUnique)
    , not (Set.member u constructors)
    , not (Set.member u selectors)
    ]

  inputIds      = assignIds "input_" (map snd freeTerms)
  inputByUnique = Map.fromList (zip (map fst freeTerms) inputIds)

  inputNodes =
    [ MkInputData
        { idId       = iid
        , idName     = nm
        , idFeelName = feel
        , idType     = Map.findWithDefault DmnAny u freeTermTypes
        }
    | ((u, nm), iid, feel) <- zip3 freeTerms inputIds inputFeelNames
    ]

  -- §5.2 SCOPE 1: the DRG's FEEL variable namespace -- every inputData variable
  -- and every decision variable TOGETHER, since they share one evaluation scope
  -- ("the 'variables' of standard DMN correspond to constants"). The traversal
  -- order is inputData then decision, which is the order 'drgNodes' is
  -- assembled in above, so the resolution is a function of source order alone.
  --
  -- Two further scopes §5.2 names have no emitter yet and therefore no entry
  -- here: `decisionService` names (§2.3) and BKM `formalParameter` names (§6.2),
  -- both Phase 5. Each is its own 'uniquifyIn' scope -- neither shares this one
  -- -- so extending this is adding a scope, not widening it.
  varFolded = map (feelIdentText . snd) freeTerms <> map (feelIdentText . decideName) decides
  varResolved = uniquifyIn varFolded
  (inputFeelNames, decideFeelNames) = splitAt (length freeTerms) varResolved

  nameEnv = MkNameEnv
    { neVars   = Map.fromList
        ( zip (map fst freeTerms) inputFeelNames
            <> zip (map (getUnique . decideResolved) decides) decideFeelNames
        )
    , neFields = fieldNames
    }

  -- A GIVEN's declared type is the best evidence about a free term; an ASSUME's
  -- is the other source. Anything else stays Any.
  freeTermSrc :: Map Unique (Type' Resolved)
  freeTermSrc = Map.fromList
    ( [ (getUnique n, ty)
      | MkDecide _ (MkTypeSig _ (MkGivenSig _ gs) _) _ _ <- decides
      , MkOptionallyTypedName _ n (Just ty) _ <- gs
      ]
        <> [ (getUnique n, ty)
           | MkAssume _ _ (MkAppForm _ n _ _) (Just ty) _ <- assumes
           ]
    )

  freeTermTypes = Map.map (\ty -> let (t, _, _) = classifyType typeEnv ty in t) freeTermSrc

  -- R8-a at the inputData site.
  inputMaybeNotes =
    [ maybeNullNote iid Nothing ("the input `" <> nm <> "`")
        (oneLine (prettyLayout ty)) fl.tfOptionalAlias
    | ((u, nm), iid) <- zip freeTerms inputIds
    , Just ty <- [Map.lookup u freeTermSrc]
    , let (_, _, fl) = classifyType typeEnv ty
    , fl.tfMaybe
    ]

  -- TWO DIFFERENT free terms that spell the same FEEL name. L4 scopes a GIVEN
  -- to its own decision, so `n` in one rule and `n` in another are unrelated;
  -- DMN's variables are 0-ary functions with no scope at all ("the 'variables'
  -- of standard DMN correspond to constants", Vandevelde et al. on cDMN), so the
  -- emitted model has two inputData elements a FEEL expression cannot tell
  -- apart. Note that the same term used by two decisions is NOT this, and does
  -- not warn.
  -- The counts are computed, not spelled. They used to read "two ... two"
  -- unconditionally under a guard of @length us > 1@, which understated the
  -- Reg CF corpus's eight-way collision on `issuer` as a two-way one.
  --
  -- __The message changed when @uniquifyIn@ landed, and it had to.__ It used to
  -- end "...so the emitted model has eight elements a FEEL expression cannot
  -- tell apart". After §5.2 stage 2 that sentence is FALSE: the elements are
  -- renamed apart, and every reference reaches the one it means. The loss that
  -- SURVIVES is the one this note was always about and never said plainly --
  -- L4 scoped N parameters locally, one per decision, and DMN has N globals, so
  -- a caller must now supply eight values where the L4 has one name used eight
  -- times. The note also names both the L4 spellings and the resolved FEEL
  -- names, per §5.3.6: under the fold the folded name is precisely what a
  -- reader cannot invert.
  --
  -- The PREDICATE is unchanged, deliberately. §7's header warns that it is the
  -- tree's only detector of duplicate `inputData/@name` (TP=185/FP=0/FN=0), and
  -- the type-conflict repurpose it proposes is Phase 4 work that must ADD a
  -- code rather than take this one over.
  sharedInputNotes =
    [ dmnNote "D-SCOPE" Lossy ("input_" <> sanitiseId nm) Nothing
        (englishCount (length us) <> " different terms fold to the FEEL name `"
           <> nm <> "` (L4: " <> Text.intercalate ", " (map tick l4spellings)
           <> "; used in " <> Text.intercalate ", " users
           <> "); they are emitted as the distinct globals "
           <> Text.intercalate ", " (map tick feelSpellings)
           <> ", because DMN's inputData is global and has no scope at all")
        "L4's lexical scoping of GIVEN parameters: a caller must now supply one value per \
        \element where the L4 has one locally-scoped name"
    | (nm, us) <- Map.toAscList sharedNames
    , length us > 1
    , let users = nubOrd [decideName d | d <- decides, any ((`elem` us) . fst) (decideFreeTerms d)]
    , let l4spellings = nubOrd [tnm | (u, tnm) <- freeTerms, u `elem` us]
    , let feelSpellings =
            [ feel | (feel, (u, _)) <- zip inputFeelNames freeTerms, u `elem` us ]
    ]

  sharedNames = Map.fromListWith (flip (<>))
    [ (feelIdentText tnm, [u]) | (u, tnm) <- freeTerms ]

  tick t = "`" <> t <> "`"

  -- D-RENAME, §5.2 stage 2's own note: the COLLISION arm only.
  --
  -- One note per element whose FEEL name had to be suffixed, naming the L4 name,
  -- the resolved FEEL name and the other claimants on the base. `Lossy` rather
  -- than `Blocking` is exactly what §5.3.4-3 makes conditional on stage 2: the
  -- names are now made distinct and `@label` preserves the source, so nothing is
  -- silently wrong -- what is lost is the resemblance between the FEEL text and
  -- the L4 name.
  --
  -- __The benign-mangle arm (`Advisory`) is deliberately NOT built here.__ §7's
  -- header defers the two-severities-on-one-code shape to a re-ruling against
  -- FIDELITY-SEVERITY-AXIS-SPEC.md §5, and the arm would emit ~169 Advisory
  -- notes on one corpus module while `@label` already carries the source name.
  renameNotes =
    [ dmnNote "D-RENAME" Lossy eid Nothing
        ("`" <> l4name <> "` is emitted as the FEEL name `" <> resolved
           <> "`, not `" <> foldedName <> "`: " <> englishCount (length claimants)
           <> " " <> kindPlural <> " in this module fold to `" <> foldedName
           <> "` (" <> Text.intercalate ", " (map tick claimants)
           <> "), and the first claimant in source order keeps the base name")
        "the resemblance between the emitted FEEL name and the L4 name it came from; \
        \the L4 name survives in @label"
    | (eid, kindPlural, l4name, foldedName, resolved, claimants) <- renameCandidates
    , resolved /= foldedName
    ]

  renameCandidates =
    [ (iid, "elements of the DRG's flat variable namespace", nm, feelIdentText nm, feel
      , [ other | (other, ofolded) <- varClaimants, ofolded == feelIdentText nm ])
    | ((_, nm), iid, feel) <- zip3 freeTerms inputIds inputFeelNames
    ]
      <> [ (did, "elements of the DRG's flat variable namespace", nm, feelIdentText nm, feel
           , [ other | (other, ofolded) <- varClaimants, ofolded == feelIdentText nm ])
         | (d, did, feel) <- zip3 decides decideIds decideFeelNames
         , let nm = decideName d
         ]
      <> [ ("itemdef_" <> sanitiseId tyName, "fields of one declared type", nameOf n, fldFolded, resolved
           , [ nameOf other | (other, _, _) <- fs ])
         | (tyName, fs) <- fieldScopes
         , (n, fldFolded, resolved) <- fs
         ]

  varClaimants =
    [ (nm, feelIdentText nm) | (_, nm) <- freeTerms ]
      <> [ (nm, feelIdentText nm) | d <- decides, let nm = decideName d ]

  -- TWO DIFFERENT DRG ELEMENTS THAT SPELL THE SAME FEEL NAME -- the whole
  -- namespace, not just the inputData half of it.
  --
  -- 'sharedInputNotes' above covers exactly one of the three ways this happens
  -- (inputData x inputData) because it is computed from 'freeTerms'. The other
  -- two -- inputData x decision, and decision x decision -- had no note at all,
  -- and they are the worse pair. Measured, on the two engines this exporter
  -- targets, with three two-element modules (base = 100, `net worth` = 7):
  --
  --   inputData x inputData   L4 says 10 + 200. KIE: validator 2x ERROR
  --                           [DUPLICATE_NAME], BUILD CLEAN, answers 20 --
  --                           both inputs read the one supplied value.
  --                           Camunda 8: parses clean, 0 errors, answers 20.
  --   inputData x decision    L4 says 7 + 101 = 108. KIE: validator 2x ERROR,
  --                           build clean, the decision is NOT_EVALUATED and
  --                           the answer is 14 -- the INPUT won. Camunda 8:
  --                           silent, and answers 202 -- the DECISION won.
  --   decision  x decision    L4 says 101 + 102 = 203. KIE: validator 2x ERROR,
  --                           one decision NOT_EVALUATED, answers 202.
  --                           Camunda 8: silent, answers 204.
  --
  -- Note what that table does NOT say. KIE does not /reject/ any of these: the
  -- DUPLICATE_NAME errors come from the validator leg, the KieBuilder leg is
  -- clean, and the model deploys and answers. So neither engine refuses the
  -- file, neither returns what L4 said, and the two do not even agree with each
  -- other on which element wins. Camunda -- the default flavor -- is the one
  -- that says nothing at all.
  --
  -- Blocking rather than Lossy for that reason: nothing was approximated, an
  -- answer was changed, and it survived every other check we have (the file is
  -- schema-valid, dmn-moddle-clean, and reports every decision as evaluated).
  --
  -- The fix that makes the collision go away rather than merely loud is §5.2's
  -- stage-2 @uniquifyIn@, and it has now landed: the names below are the
  -- RESOLVED ones, so this predicate fires __zero times by construction__ and
  -- D-RENAME reports the rename instead.
  --
  -- The code and its predicate are kept anyway, and §7's header says why: it
  -- must not be deleted until something else reports a duplicate
  -- `inputData/@name`, which DMN 1.3 §7.3.4 makes a violation of a normative
  -- SHALL. A test pins the count at zero, so the day it fires again is visible
  -- rather than inferred.
  declaredFeelNames :: [(Text, (Text, Text, Text))]
  declaredFeelNames =
    [ (n.idFeelName, ("inputData", n.idName, n.idId)) | n <- inputNodes ]
      <> [ (feel, ("decision", decideName d, did))
         | (d, did, feel) <- zip3 decides decideIds decideFeelNames
         ]

  feelNameCollisionNotes =
    [ dmnNote "D-FEELNAME" Blocking eid Nothing
        ("`" <> fname <> "` is the FEEL name of " <> Text.pack (show (length grp))
           <> " elements this module keeps apart ("
           <> Text.intercalate ", " [kind <> " `" <> l4name <> "`" | (kind, l4name, _) <- grp]
           <> "); DMN's variable namespace is flat, so no FEEL reference can pick one of them. \
              \Neither engine refuses the file: KIE's validator says DUPLICATE_NAME but still \
              \builds and answers, and Camunda 8 says nothing at all. Both answer with whichever \
              \element they resolved first, and they do not agree on which that is")
        "the distinction between them; every reference to either now reaches one of them"
    | (fname, grp@((_, _, eid) : _ : _)) <- Map.toAscList feelNameGroups
    ]

  feelNameGroups = Map.fromListWith (flip (<>)) [(f, [x]) | (f, x) <- declaredFeelNames]

  lowered = zipWith3 lowerOne decides decideIds decideFeelNames

  lowerOne d did feelName = (decision, notes)
   where
    MkDecide _ (MkTypeSig _ (MkGivenSig _ givens) mGiveth) _ rawBody = d
    -- The typechecker desugars every binary operator into a function
    -- application; 'carameliseExpr' undoes that, which is what makes a
    -- comparison recognisable as a comparison. The ladder does the same.
    caramelised = carameliseExpr rawBody

    -- WHERE/LET first: 'normaliseGuarded' cannot see through a wrapper, and the
    -- corpus's best tables are all WHERE-wrapped.
    peeled = peelLocals caramelised
    (body, inlined) = either (const (caramelised, [])) id peeled

    -- The oracle, built WITHOUT going through 'tctx'. 'TableCtx' has strict
    -- fields, so asking `oracleOf tctx` while computing `tcOutputType` would
    -- force the record that is being built.
    oracle0 = MkTypeOracle
      { toTypes = typeEnv, toSubst = opts.dloSubstitution, toUri = uri }

    givethSrc = case mGiveth of
      Just (MkGivethSig _ ty) -> Just ty
      Nothing                 -> annTypeSource oracle0 body

    (declaredType, declaredDomain, declaredFlags) =
      maybe (DmnAny, Nothing, noTypeFlags) (classifyType typeEnv) givethSrc

    -- Every type the decision states at its own boundary: the GIVEN parameters
    -- that carry a declared type, and the GIVETH.
    boundaryTypes =
      [ty | MkOptionallyTypedName _ _ (Just ty) _ <- givens] <> maybeToList givethSrc

    tctx = MkTableCtx
      { tcName         = decideName d
      , tcFeelName     = feelName
      , tcNames        = nameEnv
      , tcIdPrefix     = did
      , tcOutputType   = declaredType
      , tcConstructors = constructors
      , tcConstants    = namedConstants
      , tcTypes        = typeEnv
      , tcOutputValues = declaredDomain
      , tcSubst        = opts.dloSubstitution
      , tcUri          = uri
      }

    subExprs = toListOf (cosmosOf (gplate @(Expr Resolved))) body

    -- R4-a's three reading forms, plus R8-c/d/e. Each is a SENTENCE COMPLETING
    -- "`<decision>` is ...", so 'literalFallback' can render them all one way.
    --
    -- __Decided before 'normaliseGuarded' and before the select-idiom branch__
    -- (§4.2.1-8): a payload-binding CONSIDER fails inside "L4.Viz.GuardedRows"
    -- for a reason of its own, and would otherwise be reported "is not a guarded
    -- chain" -- a table-shape diagnosis for a FEEL type-system limit.
    sumTypeReasons :: [Text]
    sumTypeReasons =
      [ "a reader of `" <> owner
          <> "`, a payload-carrying sum type FEEL has no way to represent (it projects the \
             \payload field `" <> nameOf n <> "`)"
      | Proj _ _ n <- subExprs
      , Just owner <- [Map.lookup (getUnique n) payloadOwner]
      ]
        <> [ "a constructor of `" <> owner
               <> "`, a payload-carrying sum type FEEL has no way to represent (it applies `"
               <> nameOf r <> "` to arguments)"
           | (r, applied) <- appHeads
           , applied
           , Just owner <- [Map.lookup (getUnique r) payloadOwner]
           ]
        <> [ "a reader of `" <> owner
               <> "`, a payload-carrying sum type FEEL has no way to represent (a CONSIDER arm \
                  \binds `" <> nameOf cn <> "`'s payload)"
           | Consider _ _ brs <- subExprs
           , MkBranch _ (When _ (PatApp _ cn ps)) _ <- brs
           , not (null ps)
           , Just owner <- [Map.lookup (getUnique cn) payloadOwner]
           ]
        -- R8-d: value emission for the BUILTIN open sums is refused in this
        -- change. A `CONSIDER`-on-`MAYBE` table would need `null` as an INPUT
        -- CELL, and DMN 1.3's grammar rule 34 makes `null` a literal while rule
        -- 33's `simple literal` is numeric | string | boolean | date-time only,
        -- so it is not a legal S-FEEL endpoint at all. Leaving S-FEEL on the
        -- cell side would forfeit §3.1's whole thesis on precisely the tables
        -- the encoding was supposed to buy.
        <> [ "a decision that constructs or matches L4's builtin open sums (it mentions `"
               <> nameOf r <> "`), and FEEL has no way to spell a tagged value"
           | r <- toList d
           , isBuiltinSumCon r
           ]
        <> [ "a CONSIDER over `" <> oneLine (prettyLayout sty)
               <> "`, whose arms would need `null` as an input cell -- which S-FEEL's endpoint \
                  \grammar does not admit"
           | Consider _ scrut _ <- subExprs
           , Just sty <- [annTypeSource oracle0 scrut]
           , let (_, _, fl) = classifyType typeEnv sty
           , fl.tfMaybe || fl.tfEither
           ]
        -- R8-c and R8-e at the boundary. Nested MAYBE is refused because `null`
        -- does not nest: `JUST NOTHING` and `NOTHING` would become one FEEL
        -- value, and FEEL `=` would answer true where L4 answers false. That is
        -- an ANSWER CHANGE, which is §2.4's own severity line.
        <> [ "typed `" <> oneLine (prettyLayout bty)
               <> "` at its own boundary: FEEL's `null` does not nest and FEEL has no EITHER, so \
                  \the type has no faithful image"
           | bty <- boundaryTypes
           , let (_, _, fl) = classifyType typeEnv bty
           , fl.tfNestedMaybe || fl.tfEither
           ]

    appHeads =
      [(r, not (null as)) | App _ r as <- subExprs]
        <> [(r, not (null as)) | AppNamed _ r as _ <- subExprs]

    -- R4-a's `Lossy` arms. Emitted only when the decision is NOT refused, so a
    -- reader is not told two different things about one decision.
    sumTypeLossyNotes
      | not (null sumTypeReasons) = []
      | otherwise = nullaryOnlyNotes <> threadedRecordNotes

    nullaryOnlyNotes =
      [ dmnNote "D-SUMTYPE" Lossy did (bestRange scrut)
          ("`" <> decideName d <> "` CONSIDERs `"
             <> Map.findWithDefault "" tu itemDeclNames
             <> "`, a payload-carrying sum type, over its nullary constructors only; no cell is \
                \emitted for " <> Text.intercalate ", " (map tick missing)
             <> ", and no FEEL value can stand for one")
          "the refused constructors' share of the domain -- the itemDefinition's allowedValues \
          \lists them, so a gap analyser reports the missing rows, which is the loss made visible"
      | Consider _ scrut brs <- subExprs
      , Just sty <- [annTypeSource oracle0 scrut]
      , Just tu <- [typeHeadUnique sty]
      , Set.member tu typeEnv.tePayload
      , let mentioned = Set.fromList [nameOf cn | MkBranch _ (When _ (PatApp _ cn _)) _ <- brs]
      , let missing =
              [c | c <- Map.findWithDefault [] tu typeEnv.teDomains, not (Set.member c mentioned)]
      , not (null missing)
      ]

    -- What survives is the type NAME, not the type: the component points at an
    -- itemDefinition over `string` whose allowedValues list every constructor as
    -- a bare tag. So the note names the typeRef it really emitted -- a reader
    -- can check that against the artifact -- and reports the loss that is
    -- actually there, which is the tag/payload distinction rather than the
    -- component's declared type.
    threadedRecordNotes =
      [ dmnNote "D-SUMTYPE" Lossy did Nothing
          ("`" <> decideName d <> "` threads `" <> Map.findWithDefault "" hu itemDeclNames
             <> "`, whose field `" <> fld <> "` is typed `" <> sumNm
             <> "`, a payload-carrying sum type; the itemComponent is emitted as typeRef=\""
             <> tref <> "\", which resolves to an itemDefinition over `string` listing every \
                \constructor as a bare tag -- FEEL has no tagged value, so a constructor that \
                \carries a payload and the same constructor without one are a single FEEL string")
          ("the tag/payload distinction: every `" <> sumNm
             <> "` constructor is spelled as a bare string, and the payload one of them carries \
                \has no image in the component at all")
      | bty <- boundaryTypes
      , Just hu <- [typeHeadUnique bty]
      , Just threaded <- [Map.lookup hu sumFieldRecords]
      , (fld, sumNm, tref) <- threaded
      ]

    -- R8-a at the decision's <variable>. This is also where a MAYBE-typed
    -- OUTPUT is reported: 'outputXml' emits no typeRef on an <output> at all
    -- (measured -- KIE says ILLEGAL_USE_OF_TYPEREF), so the decision's variable
    -- is the only place the type is written down.
    decisionMaybeNotes =
      [ maybeNullNote did (bestRange body) ("`" <> decideName d <> "`")
          (oneLine (prettyLayout sty)) declaredFlags.tfOptionalAlias
      | declaredFlags.tfMaybe
      , Just sty <- [givethSrc]
      ]

    (logic, tableNotes') = case sumTypeReasons of
      -- §4.2.1-8's diagnosis order, made structural.
      reason : _ -> literalFallback (SumTypeRead reason)
      [] -> plainLowering

    notes = tableNotes' <> sumTypeLossyNotes <> decisionMaybeNotes

    plainLowering = case peeled of
      Left loss -> literalFallback loss
      -- A whole body that IS the select idiom is a formula, not a one-case
      -- table. DMN's own answer for a formula is a boxed literal expression, so
      -- this is not a loss and gets no D-LITERALEXPR note -- only the threshold
      -- note, if a threshold went inside the expression.
      Right _ | isSelectIdiomIn (oracleOf tctx) body ->
        let rendered = renderFeelIn nameEnv constructors (oracleOf tctx) body
        in
        ( LogicLiteral rendered
        , [ dmnNote "D-LIFTEDTHRESHOLD" Advisory did (bestRange sub)
              ("`" <> oneLine (prettyLayout sub) <> "` was lifted to " <> fn
                 <> "(...): the threshold is now inside an expression rather than a row of a table")
              "a compliance reader's ability to point at the threshold as a rule"
          | (fn, sub) <- liftedThresholds tctx body
          ]
          -- ...and the third no-note hole. This branch deliberately emits no
          -- D-LITERALEXPR (a formula IS a boxed expression, so nothing is lost),
          -- which meant a max/min over an operand we cannot render shipped with
          -- ZERO fidelity notes. Real corpus instance: `max(cash out, conversion
          -- amount(liq))`, where the second operand is an L4 call.
          <> [ nonFeelOutput did (bestRange body) rendered
             | rendered.feFragment == L4Verbatim
             ]
        )
      Right _ -> case normaliseGuarded body of
        Nothing -> literalFallback NotAGuardedChain
        Just rs0
          | rowsElided body rs0 -> literalFallback RowsElided
          | otherwise ->
              let (rs, capped) = flattenGuarded rs0
              in case rowsToDmnWith' tctx inlined capped rs of
                   Right t   -> (LogicTable t, [])
                   Left loss -> literalFallback loss

    -- Never drop a decision. DMN's own answer for logic that is not tabular is a
    -- boxed literal expression, and a DRG that quietly omitted such decisions
    -- would describe a different rule set than the module does.
    --
    -- The loss chooses its own CODE ('fidelityLossCode'): a decision refused
    -- because FEEL has no sum type is @D-SUMTYPE@, everything else is
    -- @D-LITERALEXPR@. One shape, two diagnoses, which is §4.2.1-8's
    -- requirement expressed where it cannot be forgotten.
    literalFallback loss =
      ( LogicLiteral rendered
      , [ dmnNote (fidelityLossCode loss) Blocking did (bestRange body)
            ("`" <> decideName d <> "` is " <> renderFidelityLoss loss
               <> ", so it is emitted as a boxed literal expression rather than a decision table")
            "every decision-table analysis: gap, overlap, consistency and manual review"
        ]
      )
     where
      rendered = renderFeelIn nameEnv constructors (oracleOf tctx) body

    decision = MkDecision
      { dcnId           = did
      , dcnName         = decideName d
      , dcnFeelName     = feelName
      , dcnType         = case logic of
          LogicTable t -> t.dtOutput.ocType
          LogicLiteral _ -> declaredType
      , dcnLogic        = logic
      , dcnRequirements = sort (nubOrd (mapMaybe (classifyRef did) (freeRefs d)))
      }

  -- DMN 7.3.1: a Decision SHALL not require itself, "directly or indirectly".
  --
  -- The direct case is already handled upstream -- 'freeRefs' treats a
  -- decision's own name as bound -- and the guard below is belt-and-braces
  -- behind that.
  --
  -- The INDIRECT case is not detected, and deliberately so: a cycle among top-
  -- level DECIDEs would need a forward reference, which L4's one-pass scope
  -- checker does not currently admit, so no L4 module can produce one. If
  -- forward references land, this becomes a real gap and wants a cycle check
  -- with its own fidelity note.
  classifyRef did r = case Map.lookup u decideByUnique of
    Just target | target /= did -> Just (RequiredDecision target)
                | otherwise     -> Nothing
    Nothing -> RequiredInput <$> Map.lookup u inputByUnique
   where
    u = getUnique r

-- | Deterministic element ids: derived from the L4 name, with a positional
-- suffix only where two names sanitise to the same id.
--
-- This __is__ §5.2 stage 2, and always was — first claimant keeps the base, the
-- nth gets @base_\<n\>@ — applied to XML ids rather than to FEEL names. It is
-- now expressed in terms of 'uniquifyIn' so the id namespace and the FEEL
-- namespace cannot drift apart on the stepper they share. (The one behavioural
-- difference is a repair: 'uniquifyIn' takes the least FREE suffix, so a
-- source name that already spells @foo_2@ can no longer be handed out twice.)
assignIds :: Text -> [Text] -> [Text]
assignIds prefix names = uniquifyIn (map ((prefix <>) . sanitiseId) names)

-- | Small counts spelled as words, as a fidelity note's prose wants them.
englishCount :: Int -> Text
englishCount n = case n of
  2 -> "two"
  3 -> "three"
  4 -> "four"
  5 -> "five"
  6 -> "six"
  7 -> "seven"
  8 -> "eight"
  9 -> "nine"
  _ -> tshow n

-- | An XML @ID@-safe, deterministic slug.
sanitiseId :: Text -> Text
sanitiseId t
  | Text.null trimmed           = "unnamed"
  | isDigit (Text.head trimmed) = "_" <> trimmed
  | otherwise                   = trimmed
 where
  trimmed  = Text.intercalate "_" (filter (not . Text.null) (Text.split (== '_') lowered))
  lowered  = Text.map keep (Text.toLower t)
  keep c
    | isAscii c && isAlphaNum c = c
    | otherwise                 = '_'

------------------------------------------------------------------------
-- Module traversal
------------------------------------------------------------------------

-- | Every top-level declaration, descending through nested @SECTION@s.
-- | The module's own title: the name of its outermost @§@ heading, if it has
-- one.
--
-- This exists so that the @\<definitions\>@ name has a single source. It was
-- previously supplied by the caller in every case, which meant the Reg CF
-- corpus's model was called three different things at once — its own heading
-- (@SEC Regulation Crowdfunding — 17 CFR Part 227@), a string hand-typed in
-- the golden test, and the file's base name from the CLI. A title duplicated
-- across three files and stale in at least two of them is the exact defect
-- this exhibit exists to criticise.
moduleTitle :: Module Resolved -> Maybe Text
moduleTitle (MkModule _ _ (MkSection _ mName _ decls)) =
  listToMaybe
    ( [nameOf n | Just n <- [mName]]
        <> [nameOf n | Section _ (MkSection _ (Just n) _ _) <- decls]
    )

topDecls :: Module Resolved -> [TopDecl Resolved]
topDecls (MkModule _ _ sec) = section sec
 where
  section (MkSection _ _ _ ds) = concatMap decl ds
  decl d = case d of
    Section _ sub -> d : section sub
    _             -> [d]

decideResolved :: Decide Resolved -> Resolved
decideResolved (MkDecide _ _ (MkAppForm _ n _ _) _) = n

decideName :: Decide Resolved -> Text
decideName = nameOf . decideResolved

-- | Names a decision refers to but does not itself bind.
--
-- @Resolved@ already distinguishes defining from referring occurrences, so
-- "bound inside the body" is exactly "has a 'Def' inside the body" — which covers
-- lambda parameters, @LET@\/@WHERE@ locals and pattern binders without
-- enumerating them. @GIVEN@ parameters are bound in the /signature/, not the
-- body, so they correctly come out free and become @inputData@.
--
-- Record-field projections are dropped here (a selector is a reference but not a
-- term); constructors and names from other modules are dropped by the caller,
-- which is what keeps every prelude function and builtin out of the DRG.
freeRefs :: Decide Resolved -> [Resolved]
freeRefs d@(MkDecide _ _ _ body) =
  [r | r <- refs, not (Set.member (getUnique r) bound)]
 where
  allResolved = toList body
  bound = Set.fromList ([u | Def u _ <- allResolved] <> [getUnique (decideResolved d)])
  projFields = Set.fromList
    [getUnique n | Proj _ _ n <- toListOf (cosmosOf (gplate @(Expr Resolved))) body]
  refs = nubOrdOn getUnique
    [r | r@Ref {} <- allResolved, not (Set.member (getUnique r) projFields)]

-- | Did 'normaliseGuarded' drop a @CONSIDER@ arm, leaving nothing to cover the
-- inputs it used to catch?
--
-- @considerRows@ may elide an arm whose pattern binds but whose body is inert
-- (literally @FALSE@) -- which is what rescues the corpus's two widest diagrams.
-- For the ladder that is exact: a missing disjunct contributes FALSE. For DMN it
-- is not, because an unmatched input yields __null__, not @false@. When an
-- @OTHERWISE@ survives, its body becomes the default output and the hole is
-- plugged; when there is none, the table would answer differently from the rule,
-- so we refuse to emit one.
--
-- This check cannot live inside 'rowsToDmnWith', because 'GuardedRows' does not
-- record that an arm was elided -- which is also why 'rowsToDmn', whose signature
-- the spec fixes, cannot make it. A less conservative fix is available (the
-- elided arms are all FALSE by @considerRows@' own contract, so a @false@ default
-- output would be exactly right) but it would couple this module to that
-- contract, and the shape is rare.
rowsElided :: Expr Resolved -> GuardedRows -> Bool
rowsElided body rs = case body of
  Consider _ _ brs ->
    not (any isOtherwiseBranch brs)
      && length [() | MkBranch _ When {} _ <- brs] > length rs.grRows
  _ -> False
 where
  isOtherwiseBranch (MkBranch _ lhs _) = case lhs of
    Otherwise _ -> True
    When _ _    -> False

-- | Deontic material anywhere in the body. DMN models /decisions/; lifecycle is
-- BPMN's and CMMN's job, and there is no joint semantics across that seam (the
-- mechanism that would connect them lives in DMN's non-normative Annex A).
isRegulative :: Expr Resolved -> Bool
isRegulative = anyOf (cosmosOf (gplate @(Expr Resolved))) $ \case
  Regulative {} -> True
  Event {}      -> True
  Breach {}     -> True
  _             -> False

------------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------------

tshow :: Show a => a -> Text
tshow = Text.pack . show
