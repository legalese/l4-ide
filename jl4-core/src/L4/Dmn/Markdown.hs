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
  LogicTable t
    | not (expressible t) -> Nothing
    | otherwise           -> Just (renderTable t)

-- | Can this table be said in dmnmd's grammar at all?
expressible :: DecisionTable -> Bool
expressible t =
  all columnHeaderOk t.dtInputs
    && isLegalVarname t.dtOutput.ocName
    && all ruleOk t.dtRules
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
  defaultRows =
    [ row $
        textShowInt (length t.dtRules + 1)
          : map (const "-") cols
            <> [fromMaybe "-" (mdOutput t.dtOutput.ocType d)]
    | Just d <- [t.dtOutput.ocDefault]
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
  TestEq v     -> Just (mdValue v)
  TestCmp op v -> Just (cmp op <> " " <> mdValue v)
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

-- | Values, sharing 'renderNumber' with the XML emitter so the two cannot drift
-- apart on what a number looks like. Strings differ deliberately: dmnmd reads a
-- bare token as a string, and a quoted one would keep its quotes.
mdValue :: FeelValue -> Text
mdValue = \case
  VNum r  -> renderNumber r
  VStr t  -> t
  VBool b -> if b then "true" else "false"

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
    drgNotes <> concatMap decisionNotes (drgDecisions drg)
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

  decisionNotes d = case d.dcnLogic of
    LogicLiteral e ->
      [ note "D-MD-NOLITERAL" Blocking d.dcnId
          ("`" <> d.dcnName <> "` is a formula (" <> e.feText
             <> "), and dmnmd has no boxed-expression form: a named quantity defined by one \
                \expression, rather than a decision over cases, cannot be written as a table")
          "the decision itself; it is omitted from the markdown"
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
             ("rule " <> r.drId <> " has a cell dmnmd cannot read (a negation, a half-open or \
                \non-integer range, or an output with parentheses or a comma), so this table is omitted")
             "the whole table"
         | r <- t.dtRules
         , any (isNothing . mdCell) r.drInputs || isNothing (mdOutput t.dtOutput.ocType r.drOutput)
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
