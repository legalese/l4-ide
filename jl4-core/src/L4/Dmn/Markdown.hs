-- | Render a 'Drg' as __dmnmd markdown__: GitHub-flavoured pipe tables that
-- @dmnmd@ can parse back.
--
-- The second emitter over the same 'L4.Dmn.IR'. That is the point of the
-- exercise, not a convenience: __one IR, two targets, two different loss
-- lists__. DMN 1.3 XML can hold a decision requirements graph, a default output
-- entry and a boxed literal expression; dmnmd markdown can hold none of those.
-- Naming what each target drops, separately, is what a fidelity report is for —
-- and it is the programme's own thesis applied to itself, since the alternative
-- is two hand-maintained exporters that quietly disagree about what a number
-- looks like.
--
-- Why bother emitting markdown at all, given the XML:
--
--   * __it is reviewable.__ A DMN XML diff in a pull request is unreadable; a
--     pipe table is the whole decision at a glance. For a project arguing that
--     legal logic should be legible, shipping only XML would be a bad look.
--   * __it closes a loop we already own.__ @dmnmd --to=l4@ exists, so
--     @L4 → dmnmd → L4′@ is a round-trip property that can be run, not claimed.
--
-- __Emit strictly within dmnmd's current grammar.__ Where the IR cannot be said
-- in that grammar, emit nothing for it and record a note; do not invent syntax.
-- The grammar is narrower than it looks, and three of its limits were found the
-- hard way:
--
--   * a column header is a /variable name/, not an expression:
--     @letterChar@ then @[alphanumeric | space | tab | underscore]@ only
--     (@DMN.ParseFEEL.parseVarname@). @income >= limit@ is not a legal header,
--     so a table with a computed column has no markdown form at all.
--   * every table line must end with a newline. @getTableLine@ is
--     @char \'|\' >> manyTill anyChar endOfLine@, so an unterminated final row
--     fails /after/ consuming its @|@, backtracks the whole table, and reports
--     the error at the table's __header__ row — eight lines from the fault.
--   * the post-label parens admit no interior space: @(out)@ parses, @(out )@
--     does not.
module L4.Dmn.Markdown
  ( emitMarkdown
  , markdownReport
  ) where

import Base
import qualified Base.Text as Text
import Data.Char (isAlphaNum, isAscii)

import L4.Dmn.IR
import L4.Interchange.Fidelity

------------------------------------------------------------------------
-- Entry point
------------------------------------------------------------------------

-- | One markdown document per module, one @##@-headed table per decision that
-- has a markdown form.
--
-- Multi-table markdown is fine: dmnmd separates tables on any line that does
-- not start with @|@, and takes a table's name from the last heading before it
-- (the first backticked token, if there is one).
emitMarkdown :: Drg -> Text
emitMarkdown drg =
  ensureTrailingNewline . Text.concat $
    [ "# " <> drg.drgName <> "\n\n"
    , "<!-- Generated from L4. One table per decision; hit policy is the first header cell. -->\n"
    ]
      <> concatMap block (drgDecisions drg)
 where
  block d = case renderDecision d of
    Nothing   -> []
    Just body -> ["\n## `" <> d.dcnName <> "`\n\n", body]

-- | dmnmd's parser accepts a table row only if it ends in a newline, and
-- diagnoses a missing one at the wrong line. Cheap to honour, expensive to debug.
ensureTrailingNewline :: Text -> Text
ensureTrailingNewline t = Text.dropWhileEnd (== '\n') t <> "\n"

------------------------------------------------------------------------
-- Tables
------------------------------------------------------------------------

renderDecision :: Decision -> Maybe Text
renderDecision d = case d.dcnLogic of
  LogicLiteral _ -> Nothing
  -- A boxed context has no dmnmd form at all: dmnmd can say a decision over
  -- cases and nothing else. D-MD-NOCONTEXT below discloses it.
  LogicContext _ -> Nothing
  LogicTable t
    | not (expressible t) -> Nothing
    | otherwise           -> Just (renderTable t)

-- | Can this table be said in dmnmd's grammar at all?
--
-- ★ The @\<defaultOutputEntry\>@ is checked, not only the rules. R8-d′ made
-- FEEL @null@ a default output entry this backend genuinely emits, and @null@
-- is 'FullFeel' by design, so 'mdOutput' refuses it — at which point the
-- catch-all row rendered as @-@, which is dmnmd's INPUT-column "any" token and
-- reads back as "output unspecified" rather than "no value". A table that says
-- something else is worse than a table that is honestly omitted, which is the
-- standard 'mdConstant' already states for a date.
expressible :: DecisionTable -> Bool
expressible t =
  all columnHeaderOk t.dtInputs
    && isLegalVarname t.dtOutput.ocName
    && all ruleOk t.dtRules
    && all (isJust . mdOutput t.dtOutput.ocType) t.dtOutput.ocDefault
 where
  ruleOk r = all (isJust . mdCell) r.drInputs && isJust (mdOutput t.dtOutput.ocType r.drOutput)

renderTable :: DecisionTable -> Text
renderTable t =
  Text.unlines (headerRow : dividerRow : zipWith dataRow [1 :: Int ..] t.dtRules <> defaultRows)
 where
  -- Under Unique, dmnmd has no <defaultOutputEntry>, so an OTHERWISE has to
  -- become a final all-`-` row -- and an all-`-` row overlaps every other rule,
  -- which is illegal under U. Emitting `U` with a catch-all would be a table
  -- dmnmd reads back as saying something else, so the policy goes down to F.
  policy = case (t.dtHitPolicy, t.dtOutput.ocDefault) of
    (HitUnique, Just _) -> "F"
    (HitUnique, Nothing) -> "U"
    (HitFirst, _) -> "F"

  cols = t.dtInputs

  headerRow =
    row $
      policy
        : [ mdIdent c.icExpr.feText <> " : " <> mdType c.icType | c <- cols ]
          <> [mdIdent t.dtOutput.ocName <> " (out) : " <> mdType t.dtOutput.ocType]

  dividerRow = row (replicate (2 + length cols) "---")

  dataRow i r =
    row $
      textShowInt i
        : map (fromMaybe "-" . mdCell) r.drInputs
          <> [fromMaybe "-" (mdOutput t.dtOutput.ocType r.drOutput)]

  -- The <defaultOutputEntry>, as the catch-all row the downgrade above bought.
  -- It goes LAST, so First reaches it only when nothing above matched.
  -- No `fromMaybe "-"` here, deliberately: 'expressible' has already
  -- established that this is 'Just', and a dash in the OUTPUT column would be
  -- read as dmnmd's "any" token and silently misstate the catch-all.
  defaultRows =
    [ row $
        textShowInt (length t.dtRules + 1)
          : map (const "-") cols
            <> [out]
    | Just d   <- [t.dtOutput.ocDefault]
    , Just out <- [mdOutput t.dtOutput.ocType d]
    ]

  row cells = "| " <> Text.intercalate " | " cells <> " |"

------------------------------------------------------------------------
-- Cells
------------------------------------------------------------------------

-- | A unary test as a dmnmd cell, or 'Nothing' if the grammar cannot say it.
--
-- @mkF@ reads a numeric cell by looking for a leading @<@ @<=@ @>@ @>=@, an
-- @[m..n]@ range (integers only, both ends closed) or a bare value; a string or
-- boolean cell is the bare token. Commas separate alternatives. There is no
-- negation, and no half-open range.
mdCell :: UnaryTest -> Maybe Text
mdCell = \case
  TestAny      -> Just "-"
  TestEq v     -> mdConstant v
  TestCmp op v -> (\t -> cmp op <> " " <> t) <$> mdConstant v
  TestOneOf ts -> Text.intercalate ", " <$> traverse mdCell ts
  -- `not(...)` has no dmnmd form.
  TestNot _    -> Nothing
  -- dmnmd's range regex is `\[\s*(\d+)\s*\.\.\s*(\d+)\s*\]`: integer bounds,
  -- both ends closed. A half-open or non-integer interval cannot be written.
  TestRange lc lo hi hc
    | lc && hc, Just a <- wholeNumber lo, Just b <- wholeNumber hi ->
        Just ("[" <> a <> ".." <> b <> "]")
    | otherwise -> Nothing
 where
  cmp = \case
    OpLt  -> "<"
    OpLeq -> "<="
    OpGt  -> ">"
    OpGeq -> ">="

-- | An output entry as a dmnmd cell.
--
-- In a Number column an arithmetic expression is legal (@mkF@ detects one by the
-- presence of @+-*\/@ and parses it with @parseFNumFunction@), but that parser
-- has no function invocation and no parentheses at the top level, and a comma
-- would be read as a cell separator. In a String or Boolean column only a bare
-- value is legal.
mdOutput :: DmnType -> FeelExpr -> Maybe Text
mdOutput ty e
  | Text.any (`elem` ("|,()[]" :: String)) txt = Nothing
  | e.feFragment /= SFeel                      = Nothing
  | ty == DmnNumber                            = Just txt
  | otherwise                                  = Just (Text.dropAround (== '"') txt)
 where
  txt = e.feText

-- | A cell CONSTANT, sharing 'renderNumber' with the XML emitter so the two
-- cannot drift apart on what a number looks like. Strings differ deliberately:
-- dmnmd reads a bare token as a string, and a quoted one would keep its quotes.
--
-- __A date has no dmnmd form and is refused, not rendered.__ dmnmd's cell
-- grammar has no date datatype at all: @mkF@ reads a cell as a number, a range
-- of integers, or a bare token, so @>= 1994-04-01@ would be /emitted/ and then
-- misread by dmnmd's own numeric parser. Returning 'Nothing' routes the whole
-- table to @D-MD-CELLSYNTAX@ Blocking and omits it honestly, which is what this
-- module already does for a half-open range. That is not a workaround for the
-- gap; it __is__ the gap being reported.
mdConstant :: FeelValue -> Maybe Text
mdConstant = \case
  VNum r  -> Just (renderNumber r)
  VStr t  -> Just t
  VBool b -> Just (if b then "true" else "false")
  VDate _ -> Nothing

-- | Which of dmnmd's cell-grammar gaps this rule actually fell into.
--
-- __Naming the enumeration rather than the instance was wrong the moment dates
-- existed.__ @>= date("2024-01-01")@ is not a negation, not a range and not an
-- output with parentheses, so a reader told "a negation, a half-open or
-- non-integer range, or an output with parentheses or a comma" would go looking
-- for a defect that is not there — and on the Reg CF corpus that misdiagnosis
-- would be the MAJORITY of the instances.
cellSyntaxReason :: DmnType -> DmnRule -> Text
cellSyntaxReason outTy r
  | null reasons = "a cell outside dmnmd's grammar"
  | otherwise    = Text.intercalate "; " reasons
 where
  reasons =
    [ "a DATE cell -- dmnmd's cell grammar has no date datatype at all"
    | any (anyTest isDateTest) r.drInputs
    ]
      <> [ "a `not(...)` cell, which dmnmd's grammar cannot spell"
         | any (anyTest isNotTest) r.drInputs
         ]
      <> [ "a half-open or non-integer range"
         | any (anyTest isBadRange) r.drInputs
         ]
      <> [ "an output dmnmd cannot read: parentheses, a comma, or an expression outside S-FEEL"
         | isNothing (mdOutput outTy r.drOutput)
         ]

  -- 'TestOneOf' nests, so the search must too.
  anyTest p u = p u || case u of
    TestOneOf ts -> any (anyTest p) ts
    TestNot t    -> anyTest p t
    _            -> False

  isDateTest = \case
    TestEq v            -> isDate v
    TestCmp _ v         -> isDate v
    TestRange _ lo hi _ -> isDate lo || isDate hi
    _                   -> False

  isDate = \case
    VDate _ -> True
    _       -> False

  isNotTest = \case
    TestNot _ -> True
    _         -> False

  isBadRange = \case
    TestRange lc lo hi hc ->
      not (lc && hc) || isNothing (wholeNumber lo) || isNothing (wholeNumber hi)
    _ -> False

wholeNumber :: FeelValue -> Maybe Text
wholeNumber = \case
  VNum r | Text.all (\c -> c `elem` ("0123456789" :: String)) (renderNumber r) -> Just (renderNumber r)
  _ -> Nothing

-- | @DMNType@ is @String | Number | Boolean | List@. Everything else collapses.
--
-- A __named__ type maps to its base, not to its name: dmnmd's pipe grammar has
-- no notion of an @itemDefinition@, so an enum — whose values serialise as
-- strings on both sides — is @String@ here exactly as it was before item
-- definitions existed, and a record is @String@ for the same reason @Any@ was.
-- Reading the base rather than the constructor is what keeps 'collapses' from
-- reporting a loss the carrier does not incur (§8 is Phase 6).
mdType :: DmnType -> Text
mdType ty = case dmnTypeBase ty of
  DmnNumber  -> "Number"
  DmnBoolean -> "Boolean"
  _          -> "String"

------------------------------------------------------------------------
-- Identifiers
------------------------------------------------------------------------

-- | @DMN.ParseFEEL.parseVarname@: a letter, then alphanumerics, spaces, tabs and
-- underscores. Nothing else — not @.@, not @-@, not an operator.
isLegalVarname :: Text -> Bool
isLegalVarname t = case Text.uncons stripped of
  Nothing        -> False
  Just (c, rest) -> isAscii c && isAlpha' c && Text.all legalRest rest
 where
  stripped = Text.strip t
  isAlpha' c = isAlphaNum c && not (c `elem` ("0123456789" :: String))
  legalRest c = (isAscii c && isAlphaNum c) || c `elem` (" _\t" :: String)

-- | 'isLegalVarname' is necessary but not sufficient for a column header.
--
-- Its grammar admits spaces, so an L4 phrase can satisfy it by accident:
-- @double OF n@ is "a letter, then alphanumerics and spaces" and would have been
-- written into a header as though it named a variable. It does not — it is L4
-- source that this backend could not render as FEEL ('L4Verbatim'), and a dmnmd
-- reader would silently take it for a column called @double OF n@. Consult the
-- fragment, not just the spelling.
columnHeaderOk :: InputColumn -> Bool
columnHeaderOk c = isLegalVarname c.icExpr.feText && c.icExpr.feFragment /= L4Verbatim

mdIdent :: Text -> Text
mdIdent = Text.strip

textShowInt :: Int -> Text
textShowInt = Text.pack . show

------------------------------------------------------------------------
-- The report
------------------------------------------------------------------------

-- | What dmnmd could not carry. A different list from the XML backend's, over
-- the same IR — which is the whole demonstration.
markdownReport :: Drg -> FidelityReport
markdownReport drg =
  foldl' (flip addNote) (emptyReport "dmnmd") $
    drgNotes <> bkmNotes <> concatMap decisionNotes (drgDecisions drg)
 where
  drgNotes =
    [ note "D-MD-NODRG" Blocking drg.drgId
        ("dmnmd is a table format, not a graph: the "
           <> textShowInt (length requirements)
           <> " information requirement(s) between these decisions have no markdown form")
        "the decision requirements graph; which decision feeds which is invisible"
    | not (null requirements)
    ]

  requirements = concatMap (.dcnRequirements) (drgDecisions drg)

  -- Ruled at the Phase 5 build (recorded in spec §8): dmnmd says a decision
  -- over cases and NOTHING else — it has no DRG (D-MD-NODRG already says so),
  -- no invocable, and no formalParameter — so a businessKnowledgeModel is
  -- omitted whole, whatever its logic shape. Rendering its table as a plain
  -- dmnmd table was considered and refused: the columns would read the BKM's
  -- parameters as though they were the module's inputs, which is a silently
  -- different model. Its own code, for D-MD-NOCONTEXT's reason: widening
  -- D-MD-NOLITERAL's "is a formula" to a function would make one counted line
  -- describe two losses.
  bkmNotes =
    [ note "D-MD-NOBKM" Blocking b.bkmId
        ("`" <> b.bkmName <> "` is a businessKnowledgeModel — a named function of "
           <> textShowInt (length b.bkmParams)
           <> " parameter(s) — and dmnmd has no function form, so it is omitted, along \
              \with every invocation of it inside the decisions that remain")
        "the function itself, and the meaning of every call site that names it: in the \
        \markdown those calls reference a definition that is not there"
    | b <- drgBkms drg
    ]

  decisionNotes d = case d.dcnLogic of
    LogicLiteral e ->
      [ note "D-MD-NOLITERAL" Blocking d.dcnId
          ("`" <> d.dcnName <> "` is a formula (" <> e.feText
             <> "), and dmnmd has no boxed-expression form: a named quantity defined by one \
                \expression, rather than a decision over cases, cannot be written as a table")
          "the decision itself; it is omitted from the markdown"
      ]
    -- Its OWN code, not a widening of D-MD-NOLITERAL. That note's message says
    -- "is a formula", which is false of a context, and its code is counted in
    -- FIDELITY-SEVERITY-AXIS-SPEC.md -- so widening it would make one line of
    -- that spec's table describe two different losses.
    LogicContext es ->
      [ note "D-MD-NOCONTEXT" Blocking d.dcnId
          ("`" <> d.dcnName <> "` is a boxed context: a record hydrated from its source with "
             <> textShowInt (length es)
             <> " component(s), of which the derived ones are computed from earlier siblings. \
                \dmnmd has no boxed-context form -- it can say a decision over cases and \
                \nothing else -- so this decision is omitted")
          "the decision itself, and with it every derived component the tables downstream read \
          \through: in the markdown those reads name a decision that is not there"
      ]
    LogicTable t -> tableNotes d t

  tableNotes d t =
    [ note "D-MD-NONIDENTCOLUMN" Blocking d.dcnId
        ("`" <> c.icExpr.feText <> "` is "
           <> (if c.icExpr.feFragment == L4Verbatim
                 then "L4 source, not FEEL" else "an input EXPRESSION")
           <> "; a dmnmd column header is a variable name \
              \(letter, then alphanumerics/spaces/underscores), so this table is omitted")
        "the whole table"
    | c <- t.dtInputs
    , not (columnHeaderOk c)
    ]
      <> [ note "D-MD-CELLSYNTAX" Blocking d.dcnId
             ("rule " <> r.drId <> " has a cell dmnmd cannot read ("
                <> cellSyntaxReason t.dtOutput.ocType r <> "), so this table is omitted")
             "the whole table"
         | r <- t.dtRules
         , any (isNothing . mdCell) r.drInputs || isNothing (mdOutput t.dtOutput.ocType r.drOutput)
         ]
      -- The same loss at the <defaultOutputEntry>, which is not one of
      -- 'dtRules' and so is not reached by the comprehension above. Reusing
      -- D-MD-CELLSYNTAX rather than minting a code: the loss IS "a cell dmnmd's
      -- grammar cannot say", and the code is already carried in
      -- FIDELITY-SEVERITY-AXIS-SPEC.md §5.2 with that meaning.
      --
      -- R8-d′ is what made this reachable: a MAYBE-valued decision tabulates
      -- with a FEEL `null` catch-all, `null` is FullFeel by design, and
      -- 'mdOutput' refuses anything that is not S-FEEL. Without this note the
      -- table would be omitted in silence, which is the one outcome worse than
      -- omitting it loudly.
      <> [ note "D-MD-CELLSYNTAX" Blocking d.dcnId
             ("`" <> d.dcnName <> "`'s OTHERWISE is `" <> dflt.feText
                <> "`, and dmnmd's cell grammar cannot say it (a cell is a number, an "
                <> "integer range, or a bare token), so this table is omitted")
             "the whole table"
         | Just dflt <- [t.dtOutput.ocDefault]
         , isNothing (mdOutput t.dtOutput.ocType dflt)
         ]
      <> [ note "D-MD-NODEFAULT" Lossy d.dcnId
             ("dmnmd has no <defaultOutputEntry>, so `" <> d.dcnName
                <> "`'s OTHERWISE became a final catch-all row — which overlaps every other rule, \
                   \so the hit policy had to go from U down to F")
             "the order-free reading of a Unique table"
         | t.dtHitPolicy == HitUnique
         , isJust t.dtOutput.ocDefault
         , expressible t
         ]
      <> [ note "D-MD-TYPE" Lossy d.dcnId
             ("`" <> c.icExpr.feText <> "` is typed " <> dmnTypeAttr c.icType
                <> " in DMN; dmnmd has only String, Number, Boolean and List, so it collapses to "
                <> mdType c.icType)
             "the column's declared domain"
         | c <- t.dtInputs
         , collapses c.icType
         , expressible t
         ]
      <> [ note "D-MD-TYPE" Lossy d.dcnId
             ("`" <> d.dcnName <> "`'s output is typed " <> dmnTypeAttr t.dtOutput.ocType
                <> " in DMN; dmnmd collapses it to " <> mdType t.dtOutput.ocType)
             "the output's declared domain"
         | collapses t.dtOutput.ocType
         , expressible t
         ]

  collapses ty = base /= DmnNumber && base /= DmnBoolean && base /= DmnString
   where
    base = dmnTypeBase ty

  note c sev el msg lostWhat =
    MkFidelityNote
      { code = c, severity = sev, element = el, range = Nothing, message = msg, lost = lostWhat }
