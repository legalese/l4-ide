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
  , DmnLowerOptions (..)
  , defaultDmnLowerOptions
    -- * Reusable pieces
  , renderFeel
  , renderFeelIn
  , sanitiseId
  , selectIdiom
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

-- | What a single table needs to know beyond its rows.
data TableCtx = MkTableCtx
  { tcName         :: !Text        -- ^ the decision's name; also the table's
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
  , tcEnums        :: !(Set Unique)
    -- ^ type constructors declared as @IS ONE OF@ over nullary constructors.
    -- FEEL has no sum types, so we serialise their values as strings; saying
    -- @typeRef="string"@ rather than @"Any"@ is what lets a DMN tool do
    -- anything at all with the column.
  , tcSubst        :: !TC.Substitution
  , tcUri          :: !NormalizedUri
  }

-- | Enough to satisfy 'rowsToDmn' standing alone. Knows no constructors, so a
-- @CONSIDER@ lowered through it degrades to boolean columns — which is why the
-- module-level path builds a real 'TableCtx'.
defaultTableCtx :: TableCtx
defaultTableCtx = MkTableCtx
  { tcName         = "decision"
  , tcIdPrefix     = "decision"
  , tcOutputType   = DmnAny
  , tcConstructors = Set.empty
  , tcConstants    = Set.empty
  , tcEnums        = Set.empty
  , tcSubst        = Map.empty
  , tcUri          = toNormalizedUri (Uri "")
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
  }

defaultDmnLowerOptions :: DmnLowerOptions
defaultDmnLowerOptions = MkDmnLowerOptions
  { dloModelName    = "L4"
  , dloSubstitution = Map.empty
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
    , drOutput      = renderFeel body
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
          , drOutput      = renderFeelIn ctx.tcConstructors b0
          , drDescription = Just "OTHERWISE"
          }
      ]
    _ -> []

  allRules   = rowRules <> catchAll
  defaultOut = renderFeelIn ctx.tcConstructors <$> rows.grOtherwise

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
    , ocName    = feelIdentText ctx.tcName
    , ocType    = resolveOutputType ctx (map (.drOutput) allRules <> maybeToList defaultOut)
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

  comparison op mirrored a b = case (constantOf ctx a, constantOf ctx b) of
    (Nothing, Just v) -> Just (a, TestCmp op v)
    (Just v, Nothing) -> Just (b, TestCmp mirrored v)
    _                 -> Nothing

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
  | isConstantRef ctors r = Just (VStr (nameOf r))
  | otherwise             = Nothing
 where
  u = getUnique r

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

nameOf :: Resolved -> Text
nameOf = rawNameToText . rawName . getOriginal

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

mkColumn :: TableCtx -> Int -> Cell -> InputColumn
mkColumn ctx i c = MkInputColumn
  { icId    = ctx.tcIdPrefix <> "_i" <> tshow i
  , icLabel = oneLine (prettyLayout c.cellSubject)
  , icExpr  = renderFeelIn ctx.tcConstructors c.cellSubject
  , icType  = annType ctx c.cellSubject
  }

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
renderFeel = renderFeelIn Set.empty

-- | 'renderFeel', told which nullary references are data constructors.
--
-- This matters on the OUTPUT side and is easy to get wrong: a constructor is a
-- /value/, and FEEL has no sum types, so it must be quoted. Rendered as a bare
-- name it would read as a reference to a variable of that name — and it would
-- disagree with the input side, where 'constantOf' has already quoted the same
-- constructor into a @\"red\"@ cell.
renderFeelIn :: Set Unique -> Expr Resolved -> FeelExpr
renderFeelIn ctors top = let (_, txt, frag) = go top in MkFeelExpr (oneLine txt) frag
 where
  -- (precedence, text, fragment)
  go :: Expr Resolved -> (Int, Text, FeelFragment)
  go e = case e of
    Lit _ (NumericLit _ r) -> (atomPrec, renderNumber r, SFeel)
    Lit _ (StringLit _ s)  -> (atomPrec, quoteFeelString s, SFeel)
    App _ r []             -> (atomPrec, nullaryText r, SFeel)
    Proj _ x n             -> unary e SFeel (\t -> t <> "." <> feelIdent n) x
    Plus      _ a b -> binary e 6 SFeel "+"  a b
    Minus     _ a b -> binary e 6 SFeel "-"  a b
    Times     _ a b -> binary e 7 SFeel "*"  a b
    DividedBy _ a b -> binary e 7 SFeel "/"  a b
    Lt        _ a b -> binary e 5 SFeel "<"  a b
    Leq       _ a b -> binary e 5 SFeel "<=" a b
    Gt        _ a b -> binary e 5 SFeel ">"  a b
    Geq       _ a b -> binary e 5 SFeel ">=" a b
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
    -- Record construction (@Assessment WITH rate IS 40 …@) is a FEEL CONTEXT
    -- literal. This is the one place FEEL has a structured value, and it lines up
    -- with 'Proj' above: we render the projection side as @r.f@, so construction
    -- and access round-trip through the same names.
    AppNamed _ _ nes _ -> contextLit e nes
    -- A conditional whose arms ARE its comparison's operands is not a decision;
    -- it is `max` / `min`. Lower it to FEEL's own function rather than to an
    -- `if`, the way a compiler backend recognises a select pattern instead of
    -- emitting a branch.
    IfThenElse _ c t f
      | Just (fn, a, b) <- selectIdiom e -> call e fn [a, b]
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

    -- Field ORDER is not reordered to the constructor's declaration order (the
    -- @Maybe [Int]@ 'AppNamed' carries): a FEEL context is keyed, so order is
    -- immaterial to its meaning, and keeping the drafter's order keeps the text
    -- next to the source.
    contextLit whole nes =
      nary whole FullFeel
        (\ts -> "{" <> Text.intercalate ", " (zipWith entry keys ts) <> "}")
        [v | MkNamedExpr _ _ v <- nes]
     where
      keys = [feelIdent n | MkNamedExpr _ n _ <- nes]
      entry k t = k <> ": " <> t

    verbatim whole = (atomPrec, prettyLayout whole, L4Verbatim)

    parenIf True t  = "(" <> t <> ")"
    parenIf False t = t

  nullaryText r = case constantRefIn ctors r of
    Just v  -> renderFeelValue v
    Nothing -> feelIdent r

-- | An L4 name as the FEEL name that refers to it. The declaring side (an
-- @inputData@\'s or a @decision@\'s @\<variable\>@) uses the same
-- 'feelIdentText', so the two always agree.
feelIdent :: Resolved -> Text
feelIdent = feelIdentText . nameOf

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
-- @matchSelectPattern@ folding a branch into @SPF_SMAX@\/@SMIN@), and it matters
-- here for a structural reason: without it, 'flattenGuarded' would expand a
-- @max@ into extra table rows, manufacturing cases the regulation does not have.
-- 17 CFR 227.100(a)(2)(i) says "__The greater of__ $2,500, or 5 percent of …" —
-- the statute states an operator, so @max@ is the isomorphic rendering and the
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
selectIdiom :: Expr Resolved -> Maybe (Text, Expr Resolved, Expr Resolved)
selectIdiom = \case
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

isSelectIdiom :: Expr Resolved -> Bool
isSelectIdiom = isJust . selectIdiom

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
  , Just (fn, a, b) <- [selectIdiom sub]
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
    | isSelectIdiom b    = Nothing
    | hasEffectfulNode b = Nothing
    | otherwise = case normaliseGuarded b of
        Just sub
          | not (rowsElided b sub)
          , not (any (hasEffectfulNode . fst) sub.grRows) -> Just sub
        _ -> Nothing

------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------

annType :: TableCtx -> Expr Resolved -> DmnType
annType ctx = annTypeOf ctx.tcEnums ctx.tcSubst ctx.tcUri

-- | Kept separate from 'annType' on purpose: 'TableCtx' has strict fields, so a
-- caller computing @tcOutputType@ from an expression's annotation cannot go
-- through the context it is in the middle of building.
annTypeOf :: Set Unique -> TC.Substitution -> NormalizedUri -> Expr Resolved -> DmnType
annTypeOf enums subst uri e = case (getAnno e).extra.resolvedInfo of
  Just (TypeInfo ty _) -> dmnTypeOf enums (TC.applyFinalSubstitution subst uri ty)
  _                    -> DmnAny

-- | FEEL's type system is numbers, strings, booleans, dates, lists and contexts
-- -- no algebraic data types. An @IS ONE OF@ over nullary constructors is the one
-- L4 type with a faithful FEEL image, because its values serialise as strings.
dmnTypeOf :: Set Unique -> Type' Resolved -> DmnType
dmnTypeOf enums = \case
  TyApp _ n [] | Set.member (getUnique n) enums -> DmnString
               | otherwise                      -> builtinType (getUnique n)
  _            -> DmnAny

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
      <> inlineNotes <> capNotes <> thresholdNotes
 where
  here = ctx.tcIdPrefix

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
    , let fe = renderFeelIn ctx.tcConstructors body
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
    , let fe = renderFeelIn ctx.tcConstructors body
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
    , drgNodes     = map NodeInputData inputNodes <> map (NodeDecision . fst) lowered
    , drgNotes     = sharedInputNotes <> concatMap snd lowered
    }
 where
  modelId = sanitiseId opts.dloModelName

  decls   = topDecls modul
  decides = [d | Decide _ d <- decls]
  assumes = [a | Assume _ a <- decls]

  constructors = Set.fromList
    [ getUnique n | Declare _ (MkDeclare _ _ _ td) <- decls, n <- constructorNames td ]

  -- An enum ALL of whose constructors are nullary. One with fields is a tagged
  -- union, which FEEL cannot represent as a string, so it stays Any.
  enums = Set.fromList
    [ getUnique n
    | Declare _ (MkDeclare _ _ (MkAppForm _ n _ _) (EnumDecl _ cds)) <- decls
    , all (\(MkConDecl _ _ fs) -> null fs) cds
    ]

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
        { idId   = iid
        , idName = nm
        , idType = Map.findWithDefault DmnAny u freeTermTypes
        }
    | ((u, nm), iid) <- zip freeTerms inputIds
    ]

  -- A GIVEN's declared type is the best evidence about a free term; an ASSUME's
  -- is the other source. Anything else stays Any.
  freeTermTypes = Map.fromList
    ( [ (getUnique n, dmnTypeOf enums ty)
      | MkDecide _ (MkTypeSig _ (MkGivenSig _ gs) _) _ _ <- decides
      , MkOptionallyTypedName _ n (Just ty) _ <- gs
      ]
        <> [ (getUnique n, dmnTypeOf enums ty)
           | MkAssume _ _ (MkAppForm _ n _ _) (Just ty) _ <- assumes
           ]
    )

  -- TWO DIFFERENT free terms that spell the same FEEL name. L4 scopes a GIVEN
  -- to its own decision, so `n` in one rule and `n` in another are unrelated;
  -- DMN's variables are 0-ary functions with no scope at all ("the 'variables'
  -- of standard DMN correspond to constants", Vandevelde et al. on cDMN), so the
  -- emitted model has two inputData elements a FEEL expression cannot tell
  -- apart. Note that the same term used by two decisions is NOT this, and does
  -- not warn.
  sharedInputNotes =
    [ dmnNote "D-SCOPE" Lossy ("input_" <> sanitiseId nm) Nothing
        ("two different terms are both named `" <> nm <> "` (in "
           <> Text.intercalate ", " users
           <> "); DMN's inputData is global, so the emitted model has two elements a FEEL \
              \expression cannot tell apart")
        "L4's lexical scoping of GIVEN parameters"
    | (nm, us) <- Map.toAscList sharedNames
    , length us > 1
    , let users = nubOrd [decideName d | d <- decides, any ((`elem` us) . fst) (decideFreeTerms d)]
    ]

  sharedNames = Map.fromListWith (flip (<>))
    [ (feelIdentText tnm, [u]) | (u, tnm) <- freeTerms ]

  lowered = zipWith lowerOne decides decideIds

  lowerOne d did = (decision, notes)
   where
    MkDecide _ (MkTypeSig _ _ mGiveth) _ rawBody = d
    -- The typechecker desugars every binary operator into a function
    -- application; 'carameliseExpr' undoes that, which is what makes a
    -- comparison recognisable as a comparison. The ladder does the same.
    caramelised = carameliseExpr rawBody

    -- WHERE/LET first: 'normaliseGuarded' cannot see through a wrapper, and the
    -- corpus's best tables are all WHERE-wrapped.
    peeled = peelLocals caramelised
    (body, inlined) = either (const (caramelised, [])) id peeled

    declaredType = case mGiveth of
      Just (MkGivethSig _ ty) -> dmnTypeOf enums ty
      Nothing                 -> annTypeOf enums opts.dloSubstitution uri body

    tctx = MkTableCtx
      { tcName         = decideName d
      , tcIdPrefix     = did
      , tcOutputType   = declaredType
      , tcConstructors = constructors
      , tcConstants    = namedConstants
      , tcEnums        = enums
      , tcSubst        = opts.dloSubstitution
      , tcUri          = uri
      }

    (logic, notes) = case peeled of
      Left loss -> literalFallback loss
      -- A whole body that IS the select idiom is a formula, not a one-case
      -- table. DMN's own answer for a formula is a boxed literal expression, so
      -- this is not a loss and gets no D-LITERALEXPR note -- only the threshold
      -- note, if a threshold went inside the expression.
      Right _ | isSelectIdiom body ->
        let rendered = renderFeelIn constructors body
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
    literalFallback loss =
      ( LogicLiteral rendered
      , [ dmnNote "D-LITERALEXPR" Blocking did (bestRange body)
            ("`" <> decideName d <> "` is " <> renderFidelityLoss loss
               <> ", so it is emitted as a boxed literal expression rather than a decision table")
            "every decision-table analysis: gap, overlap, consistency and manual review"
        ]
      )
     where
      rendered = renderFeelIn constructors body

    decision = MkDecision
      { dcnId           = did
      , dcnName         = decideName d
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
assignIds :: Text -> [Text] -> [Text]
assignIds prefix names = reverse (snd (foldl' step (Map.empty, []) names))
 where
  step (seen, acc) nm =
    let base = prefix <> sanitiseId nm
        n    = Map.findWithDefault (0 :: Int) base seen
        this = if n == 0 then base else base <> "_" <> tshow (n + 1)
    in (Map.insert base (n + 1) seen, this : acc)

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
