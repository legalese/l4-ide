-- | A deterministic, line-oriented rendering of a 'RelProgram'.
--
-- __This format is the golden contract for the relational middle-end.__ M1 ships
-- no CLI verb (#258 LP-R11 is deferred), so the Debug render is the /only/
-- observation point the test suite has: every relational golden is a hostage to
-- what this module prints, and \"the render of @benefit.l4@ inspected against
-- Appendix A of BLAWX-EXPORT-SPEC\" is checkable only because the render is
-- recognisably Prolog-shaped. Treat a change here as a change to a public
-- interface — it re-blesses every golden in the corpus.
--
-- Output is built as plain 'Text' rather than a @Doc@, following
-- 'L4.OpenFisca.Emit', so that line breaks and indentation are exact and no
-- layout algorithm can silently reflow a golden.
--
-- == The grammar
--
-- Sections appear in a fixed order, each omitted when empty except the header:
--
-- > relational program — <source>
-- > title: <§ heading>
-- >
-- > records:
-- >   Applicant
-- >     age : NUMBER
-- > abstract categories:
-- >   Person
-- > enums:
-- >   Colour = Red | Green
-- > predicates:
-- >   computed exported eligible/1 : (goal)
-- >     params: Applicant
-- >     desc: whether the applicant qualifies
-- >     eligible(A) :- [ not disqualified(A) ], income(A, I_1), I_1 =< 100000.  % benefit.l4:12:3-14:20
-- > queries:
-- >   EVAL q1: eligible(A_0) => TRUE
-- >     facts: age(A_0, 70)
-- > dependencies:
-- >   eligible -> income (+)
-- >   eligible -> disqualified (-)
-- > stratification:
-- >   stratified
-- >     0  income
-- >     1  eligible
-- > fidelity report — relational
-- >   (nothing lost)
--
-- Three notational choices carry meaning and are not cosmetic:
--
-- * @[ … ]@ around the leading goals of a body marks the __materialised guard
--   prefix__ ('rcGuardPrefix'). A reader — and a reviewer comparing against a
--   spec appendix — must be able to tell a synthesised @BRANCH@-priority
--   negation from a condition the author wrote. The brackets are that mark.
--
-- * @proj(Subj, field, Out)@ and @match(V, ctor)@ are printed as neutral
--   pseudo-goals rather than as @field(Subj, Out)@ or @Subj = ctor@, because the
--   IR deliberately has not chosen between the attribute-predicate and
--   functor-term encodings (see "L4.Relational.IR"). Printing either encoding
--   here would quietly teach every reader of a golden that the choice had been
--   made.
--
-- * Goals are printed in body order and __never sorted__. The order is
--   semantics (see "L4.Relational.IR"); a renderer that canonicalised it would
--   hide exactly the class of bug — a binding moved after its use, a guard moved
--   after the division it guards — the goldens exist to catch. For the same
--   reason nothing here claims the body is a strict conjunction equivalent to
--   L4's lazy connectives; it prints what the IR holds.
--
-- Everything else is ordered by the program's own list order, which Lower fixes
-- — including the record, enum and input-predicate blocks, which Lower builds in
-- source declaration order for this reason and not from a 'Map' (see
-- @ctxRecOrder@ there). The one place a 'Map' is read here — the stratum
-- assignment — is sorted explicitly. So no container iteration order reaches a
-- golden, and in particular no golden is ordered by a type-checker counter,
-- which would let a declaration inserted early in a file permute an unrelated
-- block.
module L4.Relational.Debug
  ( renderProgram
  , renderErrors
  ) where

import Base
import qualified Base.Map as Map
import qualified Base.Text as Text
import Data.Char (isAlphaNum, isDigit)

import L4.Interchange.Fidelity (renderReport)
import L4.Parser.SrcSpan (prettySrcRange)
import L4.Relational.IR
import L4.Syntax (Unique)
import L4.Utils.Ratio (prettyRatio)

-- ---------------------------------------------------------------------------
-- Entry points
-- ---------------------------------------------------------------------------

-- | Render a whole program. Ends with a trailing newline.
renderProgram :: RelProgram -> Text
renderProgram prog =
  Text.unlines $
       header
    <> section "records:"      (concatMap (recordLines nm) prog.rpgRecords)
    -- An ASSUMEd TYPE is a category with no fields, so it gets its own block
    -- rather than printing as a fieldless record — a reader of a golden must be
    -- able to tell "declared, no fields projected" from "assumed, has none".
    <> section "abstract categories:" (map (abstractLine nm) prog.rpgAbstract)
    <> section "enums:"        (map (enumLine nm) prog.rpgEnums)
    <> section "predicates:"   (concatMap (predLines nm) prog.rpgPreds)
    <> section "queries:"      (concatMap (queryLines nm) prog.rpgQueries)
    <> section "dependencies:" (map (depLine nm) prog.rpgDeps)
    <> ["stratification:"]
    <> strataLines nm prog.rpgStrata
    <> [""]
    <> Text.lines (renderReport prog.rpgFidelity)
 where
  nm     = displayNames prog
  header =
       ["relational program — " <> prog.rpgSource]
    <> maybe [] (\t -> ["title: " <> t]) prog.rpgTitle
    <> [""]

  section _ []    = []
  section h ls    = (h : ls) <> [""]

-- | Render an accumulated batch of lowering errors, one per line, in the order
-- given. Lower is responsible for the order (source order); this function must
-- not re-sort, or a golden stops witnessing that Lower sorted.
renderErrors :: [LowerError] -> Text
renderErrors errs
  | null errs = "no lowering errors\n"
  | otherwise =
      Text.unlines $
        ("lowering errors: " <> Text.textShow (length errs))
          : map (\e -> "  " <> renderLowerError e) errs

-- ---------------------------------------------------------------------------
-- Display names
-- ---------------------------------------------------------------------------

-- | 'RName' identity is a 'Unique', but a golden must not print one: a 'Unique'
-- is a counter into the type checker's state and would churn on unrelated edits.
-- So we print 'rnText' — and two genuinely distinct entities can share it, which
-- is not a defect but a designed outcome (two @WHERE bonus@ helpers in two
-- decisions are two predicates under one spelling, "L4.Relational.IR").
--
-- Printing them identically would make a golden blind to exactly that case, so a
-- spelling shared by more than one 'Unique' gets a @\/1@, @\/2@ … suffix,
-- assigned in 'Unique' order. Programs without collisions — every seed we expect
-- — render with bare source names and no suffix at all.
type DisplayNames = Map Unique Text

displayNames :: RelProgram -> DisplayNames
displayNames prog =
  Map.fromList
    [ (u, disambiguated)
    | (txt, us) <- Map.toList byText
    , let sorted = nubOrd (sort us)
    , (i, u) <- zip [(1 :: Int) ..] sorted
    , let disambiguated
            | length sorted <= 1 = txt
            | otherwise          = txt <> "/" <> Text.textShow i
    ]
 where
  byText = Map.fromListWith (<>) [ (n.rnText, [n.rnUnique]) | n <- allNames prog ]

-- | Every 'RName' reachable in the program. Order is irrelevant (the result is
-- keyed by 'Unique'), but totality is not: a name missed here renders as its raw
-- 'rnText' and would silently escape disambiguation.
allNames :: RelProgram -> [RName]
allNames prog =
     concatMap recNames prog.rpgRecords
  <> map (.raName) prog.rpgAbstract
  <> concatMap enumNames prog.rpgEnums
  <> concatMap predNames prog.rpgPreds
  <> concatMap queryNames prog.rpgQueries
  <> concatMap (\e -> [e.redFrom, e.redTo]) prog.rpgDeps
  <> strataNames prog.rpgStrata
 where
  recNames r    = r.rrName : concatMap (\f -> f.rfName : sortNames f.rfSort) r.rrFields
  enumNames e   = e.reName : e.reCons
  predNames p   =
       [p.rpName]
    <> concatMap sortNames p.rpParams
    <> maybe [] sortNames p.rpResult
    <> concatMap clauseNames p.rpClauses
  clauseNames c = concatMap termNames c.rcHead <> concatMap goalNames c.rcBody
  queryNames q  =
       (q.rqGoal : concatMap termNames q.rqArgs)
    <> concatMap (\f -> f.rfaPred : concatMap termNames f.rfaArgs) q.rqFacts
    <> maybe [] termNames q.rqExpected
  strataNames = \case
    RStratified m   -> Map.keys m
    RUnstratified cs -> concat cs

sortNames :: RSort -> [RName]
sortNames = \case
  RSBool     -> []
  RSNum      -> []
  RSString   -> []
  RSEnum n   -> [n]
  RSRecord n -> [n]
  RSList s   -> sortNames s
  RSMaybe s  -> sortNames s
  RSOpaque _ -> []

termNames :: RTerm -> [RName]
termNames = \case
  RTVar _    -> []
  RTNum _    -> []
  RTStr _    -> []
  RTBool _   -> []
  RTAtom n   -> [n]
  RTNil      -> []
  RTCons h t -> termNames h <> termNames t

goalNames :: RGoal -> [RName]
goalNames = \case
  RCall n ts       -> n : concatMap termNames ts
  RNotCall n ts    -> n : concatMap termNames ts
  RProj t f _      -> termNames t <> [f]
  RUnify _ t       -> termNames t
  RMatch _ n       -> [n]
  RCmp _ a b       -> termNames a <> termNames b
  REval _ _        -> []
  RFindAll _ gs _  -> concatMap goalNames gs
  RAggregate{}     -> []

-- | The printed form of a name. Falls back to 'rnText' for a name 'allNames'
-- did not reach, which is a bug in 'allNames' rather than in the caller — but a
-- legible one, since the fallback is the source spelling.
nameOf :: DisplayNames -> RName -> Text
nameOf nm n = fromMaybe n.rnText (Map.lookup n.rnUnique nm)

-- ---------------------------------------------------------------------------
-- Ontology
-- ---------------------------------------------------------------------------

recordLines :: DisplayNames -> RRecordDef -> [Text]
recordLines nm r =
  (ind 1 <> nameOf nm r.rrName <> prov r.rrProv)
    : map field r.rrFields
 where
  field f =
    ind 2 <> nameOf nm f.rfName <> " : " <> renderSort nm f.rfSort
      <> maybe "" (\d -> "  -- " <> d) f.rfDesc
      <> maybe "" (\n -> "  -- nlg: " <> n) f.rfNlg

abstractLine :: DisplayNames -> RAbstractDef -> Text
abstractLine nm a = ind 1 <> nameOf nm a.raName <> prov a.raProv

enumLine :: DisplayNames -> REnumDef -> Text
enumLine nm e =
  ind 1 <> nameOf nm e.reName <> " = "
    <> Text.intercalate " | " (map (nameOf nm) e.reCons)
    <> prov e.reProv

renderSort :: DisplayNames -> RSort -> Text
renderSort nm = \case
  RSBool     -> "BOOLEAN"
  RSNum      -> "NUMBER"
  RSString   -> "STRING"
  RSEnum n   -> nameOf nm n
  RSRecord n -> nameOf nm n
  RSList s   -> "LIST OF " <> renderSort nm s
  RSMaybe s  -> "MAYBE " <> renderSort nm s
  RSOpaque t -> "OPAQUE<" <> t <> ">"

-- ---------------------------------------------------------------------------
-- Predicates
-- ---------------------------------------------------------------------------

predLines :: DisplayNames -> RPred -> [Text]
predLines nm p =
     [ ind 1 <> Text.unwords (filter (not . Text.null) [kindWord, exportWord])
        <> " " <> nameOf nm p.rpName <> "/" <> Text.textShow (length p.rpParams)
        <> " : " <> resultWord
        <> prov p.rpProv
     ]
  <> [ ind 2 <> "params: " <> Text.intercalate ", " (map (renderSort nm) p.rpParams)
     | not (null p.rpParams) ]
  <> [ ind 2 <> "recursion: structural on argument " <> Text.textShow i
     | RStructural i <- [p.rpRecursion] ]
  <> [ ind 2 <> "desc: " <> d | Just d <- [p.rpDesc] ]
  -- Printed only when present, so a corpus without annotations is unaffected.
  -- They are printed at all because they are what BLAWX-EXPORT-SPEC R10/R4
  -- consume, and an IR field no golden witnesses is a field that can go silently
  -- empty.
  <> [ ind 2 <> "nlg: " <> n | Just n <- [p.rpNlg] ]
  <> [ ind 2 <> "ref: " <> r | Just r <- [p.rpRef] ]
  <> [ ind 2 <> "(no clauses)" | null p.rpClauses ]
  <> map (clauseLine nm p) p.rpClauses
 where
  kindWord = case p.rpKind of
    RInput     -> "input"
    RComputed  -> "computed"
    RAuxiliary -> "auxiliary"
  exportWord = if p.rpExported then "exported" else ""
  resultWord = maybe "(goal)" (renderSort nm) p.rpResult

-- | One clause, Prolog-shaped, on one line.
--
-- The materialised guard prefix is wrapped in @[ … ]@ — see the module header
-- for why that mark is load-bearing. A 'rcGuardPrefix' larger than the body is
-- clamped rather than crashing: the render is a diagnostic tool and must survive
-- a malformed IR long enough to show it.
clauseLine :: DisplayNames -> RPred -> RClause -> Text
clauseLine nm p c =
  ind 2 <> atom nm (nameOf nm p.rpName) c.rcHead <> body <> "." <> prov c.rcProv
 where
  k            = max 0 (min c.rcGuardPrefix (length c.rcBody))
  (pre, rest)  = splitAt k c.rcBody
  goals gs     = Text.intercalate ", " (map (renderGoal nm) gs)
  body
    | null c.rcBody = ""
    | null pre      = " :- " <> goals rest
    | null rest     = " :- [ " <> goals pre <> " ]"
    | otherwise     = " :- [ " <> goals pre <> " ], " <> goals rest

renderGoal :: DisplayNames -> RGoal -> Text
renderGoal nm = \case
  RCall n ts        -> atom nm (nameOf nm n) ts
  RNotCall n ts     -> "not " <> atom nm (nameOf nm n) ts
  RProj subj f out  -> "proj(" <> renderTerm nm subj <> ", " <> nameOf nm f
                         <> ", " <> renderVar out <> ")"
  RUnify v t        -> renderVar v <> " = " <> renderTerm nm t
  RMatch v n        -> "match(" <> renderVar v <> ", " <> nameOf nm n <> ")"
  RCmp op a b       -> renderTerm nm a <> " " <> renderCmp op (numericCmp a b)
                         <> " " <> renderTerm nm b
  REval out e       -> renderVar out <> " is " <> renderArith e
  RFindAll tmpl gs out ->
    "findall(" <> renderVar tmpl <> ", ("
      <> Text.intercalate ", " (map (renderGoal nm) gs)
      <> "), " <> renderVar out <> ")"
  RAggregate op lst out ->
    renderVar out <> " is " <> renderAgg op <> "(" <> renderVar lst <> ")"

-- | @p@ for a nullary predicate, @p(a, b)@ otherwise — the Prolog convention,
-- and the shape a reviewer expects when checking a render against a spec.
atom :: DisplayNames -> Text -> [RTerm] -> Text
atom _nm n [] = n
atom nm  n ts = n <> "(" <> Text.intercalate ", " (map (renderTerm nm) ts) <> ")"

-- | The comparison operator, __chosen by operand shape__ for the two
-- equalities.
--
-- 'REq' \/ 'RNeq' are generic equality in the IR, not arithmetic equality (see
-- "L4.Relational.IR"): a negated @CONSIDER@ row over a payload-free enum lowers
-- to @'RCmp' 'RNeq' v ('RTAtom' c)@, because 'RMatch' has no negative form.
-- Printing that as @=\\=@ would show a goal that /raises a type error/ in every
-- Prolog-family target rather than failing — and the render's whole claim on the
-- reader is that it is recognisably the program a target would run. So an
-- equality with a non-numeric operand prints @==@ \/ @\\==@, and every emitter
-- has to make the same choice.
renderCmp :: RCmpOp -> Bool -> Text
renderCmp op numeric = case op of
  RLt  -> "<"
  RLeq -> "=<"
  RGt  -> ">"
  RGeq -> ">="
  REq  -> if numeric then "=:=" else "=="
  RNeq -> if numeric then "=\\=" else "\\=="

-- | Whether a comparison's operands are numbers. Conservative in the direction
-- that is safe to print: a variable says nothing about its own sort (that is
-- what 'RVar' does not carry), so a comparison of two variables — the ordinary
-- numeric case — stays arithmetic, and only a visibly non-numeric literal moves
-- it. The orderings are unaffected either way; they only ever relate numbers.
numericCmp :: RTerm -> RTerm -> Bool
numericCmp a b = ok a && ok b
 where
  ok = \case
    RTAtom{} -> False
    RTStr{}  -> False
    RTBool{} -> False
    RTNil    -> False
    RTCons{} -> False
    RTNum{}  -> True
    RTVar{}  -> True

renderAgg :: RAggOp -> Text
renderAgg = \case
  RSum     -> "sum"
  RCount   -> "count"
  RMinimum -> "minimum"
  RMaximum -> "maximum"
  RAvg     -> "average"

-- ---------------------------------------------------------------------------
-- Terms
-- ---------------------------------------------------------------------------

renderTerm :: DisplayNames -> RTerm -> Text
renderTerm nm = \case
  RTVar v    -> renderVar v
  RTNum r    -> prettyRatio r
  RTStr t    -> quoted t
  RTBool b   -> if b then "TRUE" else "FALSE"
  RTAtom n   -> nameOf nm n
  RTNil      -> "[]"
  t@RTCons{} -> renderList nm t

-- | A list prints as @[a, b, c]@ when it is proper and as @[a, b | T]@ when its
-- tail is a variable — the improper case is not an error but a partial list,
-- which is how structural recursion decomposes a head.
renderList :: DisplayNames -> RTerm -> Text
renderList nm t0 = "[" <> Text.intercalate ", " (map (renderTerm nm) elems) <> tailPart <> "]"
 where
  (elems, rest) = spine t0
  spine = \case
    RTCons h t -> let (es, r) = spine t in (h : es, r)
    other      -> ([], other)
  tailPart = case rest of
    RTNil -> ""
    other -> " | " <> renderTerm nm other

-- | @Hint_id@, or @V_id@ when the hint is unusable. The numeric suffix is not
-- decoration: 'RVar' identity is 'rvId' alone and two variables may legitimately
-- share a hint, so dropping it would let a golden pass while two distinct
-- variables were conflated.
renderVar :: RVar -> Text
renderVar v = base <> "_" <> Text.textShow v.rvId
 where
  cleaned = Text.filter (\ch -> isAlphaNum ch || ch == '_') v.rvHint
  base
    | Text.null cleaned            = "V"
    | isDigit (Text.head cleaned)  = "V" <> cleaned
    | otherwise                    = Text.toUpper (Text.take 1 cleaned) <> Text.drop 1 cleaned

quoted :: Text -> Text
quoted t = "\"" <> Text.concatMap esc t <> "\""
 where
  esc '"'  = "\\\""
  esc '\\' = "\\\\"
  esc '\n' = "\\n"
  esc ch   = Text.singleton ch

-- ---------------------------------------------------------------------------
-- Arithmetic
-- ---------------------------------------------------------------------------

-- | Fully parenthesised. Precedence-aware printing would be prettier and would
-- also make @(a - b) - c@ and @a - (b - c)@ print alike at some future
-- precedence table edit; the IR forbids reassociation, so the render refuses to
-- make association invisible.
renderArith :: RArith -> Text
renderArith = \case
  RANum r      -> prettyRatio r
  RAVar v      -> renderVar v
  RANeg e      -> "-(" <> renderArith e <> ")"
  RABin op a b -> "(" <> renderArith a <> " " <> renderArithOp op <> " " <> renderArith b <> ")"

renderArithOp :: RArithOp -> Text
renderArithOp = \case
  RAdd -> "+"
  RSub -> "-"
  RMul -> "*"
  RDiv -> "/"
  RMod -> "mod"

-- ---------------------------------------------------------------------------
-- Queries, dependencies, stratification
-- ---------------------------------------------------------------------------

queryLines :: DisplayNames -> RQuery -> [Text]
queryLines nm q =
     [ ind 1 <> kindWord <> " " <> q.rqId <> ": "
        <> atom nm (nameOf nm q.rqGoal) q.rqArgs
        <> maybe "" (\v -> " -> " <> renderVar v) q.rqOut
        <> expected
        <> prov q.rqProv
     ]
  <> [ ind 2 <> "facts: " <> Text.intercalate ", "
         [ atom nm (nameOf nm f.rfaPred) f.rfaArgs | f <- q.rqFacts ]
     | not (null q.rqFacts) ]
 where
  kindWord = case q.rqKind of
    RQEval   -> "EVAL"
    RQAssert -> "ASSERT"
  -- An absent expectation is printed, not elided: BLAWX-EXPORT-SPEC R11 puts the
  -- oracle outside the artifact, and a silently missing expectation is exactly
  -- the state in which a differential harness compares nothing and passes.
  expected = case q.rqExpected of
    Nothing -> " => (expectation from the L4 evaluator)"
    Just t  -> " => " <> renderTerm nm t

depLine :: DisplayNames -> RDepEdge -> Text
depLine nm e =
  ind 1 <> nameOf nm e.redFrom <> " -> " <> nameOf nm e.redTo <> " (" <> sgn <> ")"
 where
  sgn = case e.redSign of
    RPositive -> "+"
    RNegative -> "-"

-- | Recorded, never enforced (see "L4.Relational.IR"): this section reports the
-- Apt–Blair–Walker result and a non-stratified program still renders as a
-- program. A negative fixture with a through-negation cycle is expected to lower
-- successfully and to be witnessed /here/.
strataLines :: DisplayNames -> RStratification -> [Text]
strataLines nm = \case
  RStratified m ->
    (ind 1 <> "stratified")
      : [ ind 2 <> Text.textShow s <> "  " <> nameOf nm n
        | (n, s) <- sortOn (\(n, s) -> (s, nameOf nm n)) (Map.toList m)
        ]
  RUnstratified comps ->
    (ind 1 <> "NOT stratified")
      : [ ind 2 <> "cycle: " <> Text.intercalate " -> " (map (nameOf nm) comp)
        | comp <- comps
        ]

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

ind :: Int -> Text
ind n = Text.replicate n "  "

-- | Provenance as a trailing comment. A 'Nothing' range prints explicitly rather
-- than vanishing: a synthesised node genuinely has no span, and that fact should
-- be visible in a golden instead of looking like a renderer that forgot.
prov :: RProv -> Text
prov p = "  % " <> maybe "<no source range>" prettySrcRange p.rpvRange
