-- | The import direction's classifier: a @.blawx@ document, already decoded
-- from YAML, to the block IR (BLAWX-EXPORT-SPEC §8.14 R14, §10 P5).
--
-- __The pivot is the XML, not the encoding.__ R14 chose @xml_content@ as the
-- canonical parse source because the stored @scasp_encoding@ is regenerated
-- from blocks on every save and is stale in 10 of the 15 shipped examples.
-- This module therefore reads blocks and treats the stored encoding as a
-- __cross-check only__: it regenerates through "L4.Blawx.Emit" and reports the
-- first diverging line as a WARNING (ruling P5-2). It is never a failure —
-- failing would refuse two thirds of upstream's own corpus for being old,
-- which is exactly backwards.
--
-- __Layering__ (see "L4.Blawx.Blocks" for why the middle layer exists):
--
-- > bytes ─YAML→ BlawxSource ─XML→ XNode ─shape→ BlockTree ─classify→ BlawxDoc
-- >        (CLI)              (Xml)        (Blocks)          (here)
--
-- The YAML layer is deliberately __not__ here: @yaml@ pulls in a bundled C
-- library and @jl4-core@ is cross-compiled to @wasm32-wasi@
-- (@cabal-wasm.project@ already carries two flags whose only purpose is
-- excising dependencies that do not build there). 'BlawxSource' is the seam —
-- a plain record of already-decoded 'Text' — so this module never sees a YAML
-- @Value@ and the CLI never sees a block.
--
-- __Refusal is by name and batched.__ Every diagnostic carries a code and the
-- row it came from; classification collects all of them rather than stopping
-- at the first, following @L4.Cli.OpenFisca@'s "cannot compile these
-- decisions" presentation.
--
-- __What this module does NOT do__ is lift to L4 — that is "L4.Blawx.Lift".
-- The split is where the two kinds of refusal live: a block type with no IR
-- landing zone (the date and event layers) is refused __here__, by name; a
-- program that is unstratified, or whose expected result is unsatisfiability,
-- is refused there, on semantic grounds.
module L4.Blawx.Parse
  ( -- * The seam from the YAML layer
    BlawxRow (..)
  , BlawxSource (..)
    -- * Parsing
  , parseBlawx
  , ParseDiag (..)
  , Severity (..)
  , renderParseDiag
  , diagIsError
    -- * Pieces the CLI and the round-trip property need
  , parseRuleText
  , parseSectionName
  , parseTermText
  , stripProvenance
  , normaliseStacks
  ) where

import Base
import qualified Base.Map as Map
import qualified Base.Text as Text
import qualified Data.Set as Set
import Data.Char (isDigit)
import Data.Ratio ((%))

import L4.Blawx.Blocks
import L4.Blawx.Emit (renderTestScasp, renderWorkspaceScasp)
import L4.Blawx.IR
import L4.Blawx.Xml (parseXml, renderXmlError)

-- ---------------------------------------------------------------------------
-- The seam
-- ---------------------------------------------------------------------------

-- | One @blawx.workspace@ or @blawx.blawxtest@ row, with its two stored texts
-- already YAML-decoded. @pk@, @owner@, @tutorial@, @view@ and
-- @fact_scenario@ are server bookkeeping and never reach this type;
-- @fact_scenario@ in particular is a /field/ of @blawx.blawxtest@ (empty in
-- all 41 corpus rows), not a model, and R11 keeps scenario facts in the body.
data BlawxRow = MkBlawxRow
  { brwName  :: !Text  -- ^ @workspace_name@ or @test_name@
  , brwXml   :: !Text  -- ^ @xml_content@
  , brwScasp :: !Text  -- ^ @scasp_encoding@ — cross-check only (P5-2)
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | One decoded @.blawx@ dumpdata stream. @akoma_ntoso@ and @navtree@ are
-- optional (absent in 4 of the 15 examples, because Blawx's own @pre_save@
-- receiver recomputes them) and are carried opaquely for the lift's @\@ref@
-- scaffolding; @rule_slug@ is absent in all 15 and is neither required nor
-- synthesised.
data BlawxSource = MkBlawxSource
  { bsRuledocName :: !Text
  , bsRuleText    :: !Text
  , bsAkoma       :: !(Maybe Text)
  , bsNavtree     :: !(Maybe Text)
  , bsWorkspaces  :: ![BlawxRow]
  , bsTests       :: ![BlawxRow]
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- ---------------------------------------------------------------------------
-- Diagnostics
-- ---------------------------------------------------------------------------

data Severity = SevError | SevWarning
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData)

-- | One finding, named. The code is the stable half — messages may be
-- reworded, codes are what a harness greps for.
data ParseDiag = MkParseDiag
  { pdCode     :: !Text  -- ^ e.g. @blawx-parse\/unsupported-block@
  , pdSeverity :: !Severity
  , pdRow      :: !Text  -- ^ workspace or test name, @""@ for document-level
  , pdMessage  :: !Text
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

diagIsError :: ParseDiag -> Bool
diagIsError d = d.pdSeverity == SevError

renderParseDiag :: ParseDiag -> Text
renderParseDiag d =
  sev <> " " <> d.pdCode <> ": " <> where_ <> d.pdMessage
 where
  sev = case d.pdSeverity of
    SevError -> "ERROR"
    SevWarning -> "WARNING"
  where_ = if Text.null d.pdRow then "" else d.pdRow <> ": "

-- ---------------------------------------------------------------------------
-- The classifier's own error type
-- ---------------------------------------------------------------------------

data ClassErr = MkClassErr
  { ceCode :: !Text
  , ceMsg  :: !Text
  }

type C = Either ClassErr

cerr :: Text -> Text -> C a
cerr code msg = Left (MkClassErr code msg)

-- | A known block type with no IR landing zone this phase, and the spec that
-- owns its future. Refusing here rather than at lift is what ruling P5-1's
-- "dates stay OUT" and the brief's "the date-layer examples parse" can both
-- mean at once: they parse to a 'BlockTree', and are refused at
-- classification.
unsupportedLayer :: Text -> Maybe Text
unsupportedLayer = \case
  "date_value" -> date
  "time_value" -> date
  "datetime_value" -> date
  "duration_value" -> date
  "datetime_construct" -> date
  "date_add" -> date
  "date_add_days" -> date
  "date_difference" -> date
  "date_difference_days" -> date
  "date_comparison" -> date
  "duration_comparison" -> date
  "date_calculate" -> date
  "duration_calculate" -> date
  "datetime_calculate" -> date
  "time_calculate" -> date
  "date_element" -> date
  "duration_element" -> date
  "today" -> date
  "now" -> date
  "from" -> event
  "holds_during" -> event
  "initially" -> event
  "ultimately" -> event
  "as_of" -> event
  _ -> Nothing
 where
  date = Just "the date layer; owner: DATE-LIBRARY-SPEC"
  event = Just "the event/temporal layer; owner: DATE-LIBRARY-SPEC"

unsupported :: BlockTree -> Text -> C a
unsupported b layer =
  cerr "unsupported-block" ("<" <> b.btType <> "> is not supported this phase (" <> layer <> ")")

-- | The fall-through for a block type this module does not route. Names the
-- layer when it is a known-but-deferred type, so the message says "not yet"
-- rather than "never".
unrouted :: Text -> BlockTree -> C a
unrouted position b = case unsupportedLayer b.btType of
  Just layer -> unsupported b layer
  Nothing -> cerr "unknown-block" ("<" <> b.btType <> "> has no meaning in " <> position)

shapeErr :: BlockTree -> Text -> C a
shapeErr b m = cerr "block-shape" ("<" <> b.btType <> ">: " <> m)

-- ---------------------------------------------------------------------------
-- The document
-- ---------------------------------------------------------------------------

-- | Parse one decoded @.blawx@ stream. 'Nothing' — with at least one ERROR
-- diagnostic — when any row failed to classify; a document plus WARNINGs
-- otherwise.
parseBlawx :: BlawxSource -> (Maybe BlawxDoc, [ParseDiag])
parseBlawx src
  | any diagIsError diags = (Nothing, diags)
  | otherwise = (Just doc, diags)
 where
  wsNames = Set.fromList [r.brwName | r <- src.bsWorkspaces]
  wsRows = map (parseRow wsNames) src.bsWorkspaces
  tsRows = map (parseRow wsNames) src.bsTests

  nameDiags =
    [ MkParseDiag "blawx-parse/section-name" SevError r.brwName
        ("workspace name is not an AKN-shaped section reference")
    | r <- src.bsWorkspaces
    , isNothing (parseSectionName r.brwName)
    ]

  workspaces =
    [ MkBWorkspace {bwName = ref, bwStacks = res.rrStacks, bwComment = res.rrComment}
    | (r, res) <- zip src.bsWorkspaces wsRows
    , Just ref <- [parseSectionName r.brwName]
    ]
  tests =
    [ MkBTest
        { btName = r.brwName
        , btStacks = res.rrStacks
        , btComment = res.rrComment
        , btProv = Nothing
        }
    | (r, res) <- zip src.bsTests tsRows
    ]

  doc =
    MkBlawxDoc
      { bdName = src.bsRuledocName
      , bdRuleText = parseRuleText src.bsRuleText
      , bdWorkspaces = workspaces
      , bdTests = tests
      , bdDocPartNames =
          Map.fromListWith (\_new old -> old) (concatMap (\r -> r.rrDocParts) (wsRows <> tsRows))
      }

  -- The staleness cross-check needs the IR, so it runs last and only over
  -- rows that classified and that store a non-empty encoding (P5-2).
  --
  -- These two zips are aligned ONLY because 'workspaces' drops a row whose
  -- name is not AKN-shaped — and that same condition is an ERROR in
  -- 'nameDiags', which makes the guard below discard the whole list. Do not
  -- remove that guard without making the pairing explicit first.
  staleWs =
    [ d
    | (r, ws) <- zip src.bsWorkspaces workspaces
    , d <- staleness r (renderWorkspaceScasp ws)
    ]
  staleTs =
    [ d
    | (r, t) <- zip src.bsTests tests
    , d <- staleness r (renderTestScasp t)
    ]

  diags =
    nameDiags
      <> concatMap (\r -> r.rrDiags) wsRows
      <> concatMap (\r -> r.rrDiags) tsRows
      <> if any diagIsError (nameDiags <> concatMap (\r -> r.rrDiags) (wsRows <> tsRows))
           then []
           else staleWs <> staleTs

-- | One row's result: its stacks (empty when the row failed, which only
-- matters because the caller has already decided to fail), the
-- @doc_selector@ labels it stores, and everything it has to say.
data RowResult = MkRowResult
  { rrStacks   :: ![[BBlock]]
  , rrDocParts :: ![(BSectionRef, Text)]
  , rrComment  :: !(Maybe Text)
    -- ^ every @\<comment\>@ in the row, in canvas order, joined by newlines
    -- (ruling P5-4). Only a test's reaches the IR — 'BTest' is where the lift
    -- reads it — and neither renderer images it; see 'L4.Blawx.IR.btComment'
    -- for why dropping it on both sides is what keeps the R12 fixpoint green.
  , rrDiags    :: ![ParseDiag]
  }

parseRow :: Set Text -> BlawxRow -> RowResult
parseRow wsNames row
  | Text.null (Text.strip row.brwXml) = MkRowResult [] [] Nothing []
  | otherwise = case parseXml row.brwXml of
      Left e -> failed "blawx-parse/xml-malformed" (renderXmlError e)
      Right node -> case toBlockTrees node of
        Left m -> failed "blawx-parse/xml-shape" m
        Right (roots, warns) ->
          let skipped =
                [ diag "blawx-parse/disabled-block-skipped" SevWarning (renderBlockWarning w)
                | w <- warns
                ]
              ordered = sortOn canvasKey roots
              docParts = concatMap docSelectorLabels roots
              dangling =
                [ diag "blawx-parse/dangling-section-ref" SevError
                    ("<doc_selector> names workspace " <> quoted sr <> ", which this file does not define")
                | sr <- nubOrd (concatMap sectionRefs roots)
                , not (Set.member sr wsNames)
                ]
              classified = map classifyRoot ordered
              errs =
                [ diag ("blawx-parse/" <> e.ceCode) SevError e.ceMsg
                | Left e <- classified
                ]
              stacks = [bs | Right bs <- classified, not (null bs)]
          in  MkRowResult
                { rrStacks = if null errs && null dangling then stacks else []
                , rrDocParts = docParts
                , rrComment = case concatMap (foldTree (maybeToList . (.btComment))) ordered of
                    [] -> Nothing
                    cs -> Just (Text.intercalate "\n" cs)
                , rrDiags = skipped <> dangling <> errs
                }
 where
  failed code m = MkRowResult [] [] Nothing [diag code SevError m]
  diag code sev m = MkParseDiag code sev row.brwName m
  -- Blockly's getTopBlocks(true) order, which is what workspaceToCode
  -- iterates: y + sin(3°)·x. Document order is NOT canvas order, and the
  -- blank line between roots in the regenerated s(CASP) follows this one.
  canvasKey b = case b.btPos of
    Just (x, y) -> fromIntegral y + 0.05233595624294383 * fromIntegral x :: Double
    Nothing -> 0

-- | @doc_selector@'s display label, by the section it points at. Display-only
-- (the generator reads the mutation), but stored bytes: a re-emission that
-- invents @NBA 5@ where bird wrote @NBA 5pingu@ fails the XML fixpoint even
-- though the s(CASP) matches.
docSelectorLabels :: BlockTree -> [(BSectionRef, Text)]
docSelectorLabels = foldTree step
 where
  step b
    | b.btType == "doc_selector"
    , Just sr <- btMut "section_reference" b
    , Just ref <- parseSectionName sr
    , Just lbl <- btField "doc_part_name" b =
        [(ref, lbl)]
    | otherwise = []

sectionRefs :: BlockTree -> [Text]
sectionRefs = foldTree step
 where
  step b
    | b.btType == "doc_selector" = maybeToList (btMut "section_reference" b)
    | otherwise = []

foldTree :: Monoid m => (BlockTree -> m) -> BlockTree -> m
foldTree f b =
  f b
    <> foldMap (foldTree f . snd) b.btValues
    <> foldMap (foldMap (foldTree f) . snd) b.btStmts

-- | Ruling P5-2. Regenerate the row's s(CASP) from the blocks we just parsed
-- and name the first line on which the stored text disagrees. Informational:
-- only @life_act@ of the 15 shipped examples matches the current generator.
staleness :: BlawxRow -> Text -> [ParseDiag]
staleness row regenerated
  | Text.null (Text.strip row.brwScasp) = []
  | stored == fresh = []
  | otherwise =
      [ MkParseDiag "blawx-parse/stale-encoding" SevWarning row.brwName
          ( "stored scasp_encoding diverges from the current generator at line "
              <> Text.textShow lineNo
              <> "\n    stored:      " <> at stored
              <> "\n    regenerated: " <> at fresh
              <> "\n    (the XML is canonical, R14; this is informational)" )
      ]
 where
  stored = Text.splitOn "\n" (Text.stripEnd row.brwScasp)
  fresh = Text.splitOn "\n" (Text.stripEnd regenerated)
  lineNo = 1 + length (takeWhile id (zipWith (==) stored fresh))
  at ls = case drop (lineNo - 1) ls of
    l : _ -> l
    [] -> "<end of text>"

-- ---------------------------------------------------------------------------
-- Roots
-- ---------------------------------------------------------------------------

-- | One canvas root becomes one 'BWorkspace' stack. The six root-capable
-- types are exactly the 227 top-level blocks the corpus measures; anything
-- else at top level is a shape error, because Blockly would not have put it
-- there.
classifyRoot :: BlockTree -> C [BBlock]
classifyRoot b = case b.btType of
  "unattributed_fact" -> traverse classifyMember (btStmt "statements" b)
  "unattributed_constraint" -> do
    gs <- traverse classifyGoal (btStmt "conditions" b)
    pure [BConstraint gs]
  -- One `assume` root with n statements emits n `#abducible` lines with no
  -- blank between them, where n separate BAbducible blocks re-emit as n roots
  -- (they have no previousStatement). Every `assume` in both corpora holds
  -- exactly one statement, so the two agree there; a multi-statement one
  -- would round-trip a blank line richer.
  "assume" -> traverse abducible (btStmt "statements" b)
  "query" -> do
    gs <- traverse classifyGoal (btStmt "query" b)
    pure [BQuery gs]
  "attributed_rule" -> do
    r <- attributedRule b
    pure [BAttributedRule r]
  "unattributed_rule" -> do
    cs <- traverse classifyGoal (btStmt "conditions" b)
    hs <- traverse classifyGoal (btStmt "conclusion" b)
    pure [BUnattributedRule MkBURule {burConclusion = hs, burConditions = cs, burProv = Nothing}]
  _ -> unrouted "canvas-root position" b

abducible :: BlockTree -> C BBlock
abducible t = do
  g <- classifyGoal t
  case g of
    BGCall True p as -> pure (BAbducible p as)
    BGNewObjectCategory c x -> pure (BAbducible c [x])
    _ -> shapeErr t "an `assume` statement must be a positive predicate application"

-- | A statement-position member of an @unattributed_fact@ chain.
classifyMember :: BlockTree -> C BBlock
classifyMember b = case b.btType of
  "new_category_declaration" -> BDeclareCategory <$> categoryDecl b
  "new_attribute_declaration" -> BDeclareAttribute <$> attributeDecl b
  "relationship_declaration" -> BDeclareRelationship <$> relationshipDecl b
  "object_declaration" -> BDeclareObject <$> objectDecl b
  "overrules" -> BOverrules <$> overrule b
  _ -> do
    g <- classifyGoal b
    case g of
      BGCall s p as -> pure (BFact s p as)
      _ -> case mkBAssertGoal g of
        Just blk -> pure blk
        Nothing ->
          shapeErr b "this block has no fact-position spelling in the block IR"

-- ---------------------------------------------------------------------------
-- Rules
-- ---------------------------------------------------------------------------

attributedRule :: BlockTree -> C BRule
attributedRule b = do
  sec <- reqValue "source" b >>= docSelector
  conds <- traverse classifyGoal (btStmt "conditions" b)
  concl <- reqStmt1 "conclusion" b >>= conclusion
  pure
    MkBRule
      { brSection = sec
      , brConclusion = concl
      , brConditions = conds
      , brDefeasible = btField "defeasible" b == Just "TRUE"
      , brInapplicable = btField "inapplicable" b == Just "TRUE"
      , brProvenance = Nothing
      }

overrule :: BlockTree -> C BOverrule
overrule b = do
  ing <- reqValue "defeating_rule" b >>= docSelector
  ingS <- reqStmt1 "defeating_statement" b >>= conclusion
  ed <- reqValue "defeated_rule" b >>= docSelector
  edS <- reqStmt1 "defeated_statement" b >>= conclusion
  pure
    MkBOverrule
      { bovDefeating = ing
      , bovDefeatingStmt = ingS
      , bovDefeated = ed
      , bovDefeatedStmt = edS
      , bovProv = Nothing
      }

-- | A statement slot that the generator feeds through @deconstruct_term@:
-- functor and arguments, with a sign. A comparison or a NAF goal there is
-- silently mangled by the generator, so this refuses it instead.
conclusion :: BlockTree -> C BConclusion
conclusion b = do
  g <- classifyGoal b
  go g
 where
  go = \case
    BGCall s p as -> pure MkBConclusion {bcSign = s, bcPred = p, bcArgs = as}
    BGNewObjectCategory c t -> pure MkBConclusion {bcSign = True, bcPred = c, bcArgs = [t]}
    BGNegated BNegClassical inner -> do
      c <- go inner
      pure c {bcSign = not c.bcSign}
    _ -> shapeErr b "a conclusion slot must hold a predicate application"

-- ---------------------------------------------------------------------------
-- Goals
-- ---------------------------------------------------------------------------

classifyGoal :: BlockTree -> C BGoal
classifyGoal b = case b.btType of
  "logical_negation" ->
    mkBGNegated BNegClassical <$> (reqStmt1 "negated_statement" b >>= classifyGoal)
  "default_negation" ->
    mkBGNegated BNegDefault <$> (reqStmt1 "default_negated_statement" b >>= classifyGoal)
  -- object_category holds its category in a category_selector; both it and
  -- new_object_category print @cat(obj)@, and they are DISTINCT in the IR
  -- because the attributed_rule generator injects the applicability guard for
  -- the latter only (scasp_generator.js:1188-1194).
  "object_category" -> do
    obj <- reqValue "object" b >>= classifyTerm
    cat <- reqValue "category" b >>= categorySelector
    pure (BGCall True cat [obj])
  "new_object_category" -> do
    obj <- reqValue "object" b >>= classifyTerm
    cat <- reqField "category_name" b >>= atomOf "category"
    pure (BGNewObjectCategory cat obj)
  "attribute_selector" -> do
    n <- reqMut "attributename" b >>= atomOf "attribute"
    x <- reqValue "first_element" b >>= classifyTerm
    y <- reqValue "second_element" b >>= classifyTerm
    -- The generator reads the mutation-restored blawxAttributeOrder and swaps
    -- unless it is exactly "ov" — an absent mutation attribute reads as
    -- undefined, i.e. swapped (scasp_generator.js:683-697).
    pure (BGCall True n (if btMut "attributeorder" b == Just "ov" then [x, y] else [y, x]))
  "unary_attribute_selector" -> do
    n <- reqMut "attributename" b >>= atomOf "attribute"
    x <- reqValue "first_element" b >>= classifyTerm
    pure (BGCall True n [x])
  "object_disequality" -> do
    x <- reqValue "first_object" b >>= classifyTerm
    y <- reqValue "second_object" b >>= classifyTerm
    pure (BGDiseq x y)
  -- variable_assignment ALWAYS emits `=` (scasp_generator.js:139-145); it is
  -- `calculation` that emits `is`. The design plan's table listed them as one
  -- arm dispatched by operand sort; the generator says otherwise, and the
  -- generator is R10's authority.
  "variable_assignment" -> do
    x <- reqValue "variable" b >>= classifyTerm
    y <- reqValue "value" b >>= classifyTerm
    pure (BGUnify x y)
  "calculation" -> do
    v <- reqValue "variable" b >>= variableOf
    e <- reqValue "calculation" b >>= classifyArith
    pure (BGIs v e)
  -- numerical_constraint prints blawx_comparison(X,op,Y); `comparison` prints
  -- the infix `X op Y`. They share one IR spelling, so a parsed `comparison`
  -- re-emits as a numerical_constraint — recorded in p5-design/census-results.md
  -- as the one normalising arm.
  "numerical_constraint" -> compareGoal b
  "comparison" -> compareGoal b
  "collect_list" -> do
    out <- reqValue "list_name" b >>= variableOf
    tmpl <- reqValue "variable_name" b >>= variableOf
    body <- traverse classifyGoal (btStmt "search" b)
    pure (BGFindall tmpl body out)
  "list_aggregation" -> do
    fn <- reqField "aggregation" b >>= aggFn b
    out <- reqValue "output" b >>= variableOf
    lst <- reqValue "list" b >>= variableOf
    pure (BGAggregate fn lst out)
  "applies" -> do
    sec <- reqValue "applicable_rule" b >>= docSelector
    obj <- reqValue "object" b >>= classifyTerm
    pure (BGApplies sec obj)
  "holds" -> do
    sec <- reqValue "section" b >>= docSelector
    inner <- reqStmt1 "statement" b >>= classifyGoal
    pure (BGHolds sec inner)
  "according_to" -> do
    sec <- reqValue "rule" b >>= docSelector
    inner <- reqStmt1 "statement" b >>= classifyGoal
    pure (BGAccordingTo sec inner)
  ty | Just n <- relationshipArity ty -> do
    p <- reqMut "relationship_name" b >>= atomOf "relationship"
    args <- traverse (\i -> reqValue ("parameter" <> Text.textShow i) b >>= classifyTerm) [1 .. n]
    pure (BGCall True p args)
  _ -> unrouted "statement position" b

compareGoal :: BlockTree -> C BGoal
compareGoal b = do
  op <- reqField "operator" b >>= cmpOp b
  x <- reqValue "first_comparator" b >>= classifyTerm
  y <- reqValue "second_comparator" b >>= classifyTerm
  pure (BGCompare op x y)

relationshipArity :: Text -> Maybe Int
relationshipArity ty = do
  ds <- Text.stripPrefix "relationship_selector" ty
  guard (not (Text.null ds) && Text.all isDigit ds)
  let n = readDigits ds
  guard (n >= 3 && n <= 10)
  pure n

cmpOp :: BlockTree -> Text -> C BCmpOp
cmpOp b = \case
  "eq" -> pure BEq
  "neq" -> pure BNeq
  "gt" -> pure BGt
  "gte" -> pure BGte
  "lt" -> pure BLt
  "lte" -> pure BLte
  t -> shapeErr b ("unknown comparison operator " <> quoted t)

aggFn :: BlockTree -> Text -> C BAggFn
aggFn b = \case
  "cnt" -> pure BCount
  "sum" -> pure BSum
  "ave" -> pure BAverage
  "min" -> pure BMin
  "max" -> pure BMax
  t -> shapeErr b ("unknown aggregation " <> quoted t)

-- ---------------------------------------------------------------------------
-- Terms
-- ---------------------------------------------------------------------------

classifyTerm :: BlockTree -> C BTerm
classifyTerm b = case b.btType of
  "variable" -> BTVar . MkBVar <$> reqField "variable_name" b
  "unnamed_variable" -> pure (BTVar (MkBVar "_"))
  "number_value" -> BTNum <$> (reqField "value" b >>= numberOf b)
  "empty_list" -> pure BTNil
  "head_tail" -> do
    h <- reqValue "head" b >>= classifyTerm
    t <- reqValue "tail" b >>= classifyTerm
    pure (BTCons h t)
  -- object_selector is a field_label_serializable the generator returns
  -- verbatim, so it is BOTH an object atom (101 of them in the wild corpus)
  -- and "L4.Blawx.EmitXml"'s surrogate for a term with no structural image in
  -- a pinned [OBJECT,VARIABLE] slot — a list, typically. Reading it back
  -- through the inverse of 'L4.Blawx.IR.renderTerm' is what makes
  -- @lift . emit = id@ hold on the seeds that carry one.
  "object_selector" -> do
    t <- reqField "object_name" b
    case parseTermText t of
      Just term -> pure term
      Nothing -> cerr "object-label" ("object_selector label " <> quoted t <> " is not a term")
  _ -> unrouted "term position" b

variableOf :: BlockTree -> C BVar
variableOf b = case b.btType of
  "variable" -> MkBVar <$> reqField "variable_name" b
  "unnamed_variable" -> pure (MkBVar "_")
  _ -> shapeErr b "expected a variable block here"

classifyArith :: BlockTree -> C BArith
classifyArith b = case b.btType of
  "number_value" -> BANum <$> (reqField "value" b >>= numberOf b)
  "variable" -> BAVar . MkBVar <$> reqField "variable_name" b
  "math_operation" -> do
    op <- reqField "operator" b >>= arithOp b
    l <- reqValue "left_side" b >>= classifyArith
    r <- reqValue "right_side" b >>= classifyArith
    pure (BABin op l r)
  _ -> unrouted "arithmetic position" b

arithOp :: BlockTree -> Text -> C BArithOp
arithOp b = \case
  "add" -> pure BAdd
  "sub" -> pure BSub
  "mul" -> pure BMul
  "div" -> pure BDiv
  t -> shapeErr b ("unknown arithmetic operator " <> quoted t)

-- | The inverse of 'L4.Blawx.IR.renderTerm', for the one slot that stores a
-- term as text. Deliberately total-or-'Nothing': a label it cannot read is a
-- named diagnostic, never a guess.
parseTermText :: Text -> Maybe BTerm
parseTermText t0 = case term (Text.strip t0) of
  Just (v, rest) | Text.null (Text.strip rest) -> Just v
  _ -> Nothing
 where
  term s = case Text.uncons (Text.stripStart s) of
    Just ('[', r) ->
      let r' = Text.stripStart r
      in  case Text.stripPrefix "]" r' of
            Just rest -> Just (BTNil, rest)
            Nothing -> do
              (h, r1) <- term r'
              r2 <- Text.stripPrefix "|" (Text.stripStart r1)
              (tl, r3) <- term r2
              r4 <- Text.stripPrefix "]" (Text.stripStart r3)
              pure (BTCons h tl, r4)
    _ ->
      let s' = Text.stripStart s
          (tok, rest) = Text.span atomish s'
      in  if Text.null tok then Nothing else (,rest) <$> leaf tok
  atomish c = c `notElem` (" |[]" :: String)
  leaf tok
    | Just q <- readRational tok = Just (BTNum q)
    | Just n <- mkBName Nothing tok = Just (BTAtom n)
    | Just (c, _) <- Text.uncons tok, c == '_' || (c >= 'A' && c <= 'Z') = Just (BTVar (MkBVar tok))
    | otherwise = Nothing

-- | @number_value@'s field is a JS number: an integral one carries no decimal
-- point and a negative sign lives inside the field. Decimals and the @n\/d@
-- form 'L4.Blawx.IR.renderRational' can print are both accepted.
numberOf :: BlockTree -> Text -> C Rational
numberOf b t = maybe (shapeErr b ("field value " <> quoted t <> " is not a number")) pure (readRational t)

readRational :: Text -> Maybe Rational
readRational t0 = case Text.uncons t0 of
  Just ('-', r) -> negate <$> unsigned r
  _ -> unsigned t0
 where
  unsigned t
    | Just (n, d) <- split "/" t = (%) <$> integer n <*> (nonZero =<< integer d)
    | Just (n, f) <- split "." t = do
        whole <- integer n
        guard (not (Text.null f) && Text.all isDigit f)
        let scale = 10 ^ Text.length f
        frac <- integer f
        pure (fromInteger whole + frac % scale)
    | otherwise = fromInteger <$> integer t
  split sep t = case Text.breakOn sep t of
    (a, b) | Text.null b -> Nothing
           | otherwise -> Just (a, Text.drop (Text.length sep) b)
  integer t
    | Text.null t || not (Text.all isDigit t) = Nothing
    | otherwise = Just (toInteger (readDigits t))
  nonZero 0 = Nothing
  nonZero n = Just n

readDigits :: Text -> Int
readDigits = Text.foldl' (\ !a c -> a * 10 + (fromEnum c - fromEnum '0')) 0

-- ---------------------------------------------------------------------------
-- Declarations
-- ---------------------------------------------------------------------------

categoryDecl :: BlockTree -> C BCategoryDecl
categoryDecl b = do
  n <- reqField "category_name" b >>= atomOf "category"
  pure
    MkBCategoryDecl
      { bcName = n
      , bcPrefix = fromMaybe "" (btField "prefix" b)
      , bcPostfix = fromMaybe "" (btField "postfix" b)
      , bcProv = Nothing
      }

attributeDecl :: BlockTree -> C BAttributeDecl
attributeDecl b = do
  cat <- reqField "category_name" b >>= atomOf "category"
  n <- reqField "attribute_name" b >>= atomOf "attribute"
  ty <- reqField "attribute_type" b >>= valueType
  pure
    MkBAttributeDecl
      { baCategory = cat
      , baName = n
      , baType = ty
      , baOrder = if btField "order" b == Just "vo" then BOrderVO else BOrderOV
      , baPrefix = fromMaybe "" (btField "prefix" b)
      , baInfix = fromMaybe "" (btField "infix" b)
      , baPostfix = fromMaybe "" (btField "postfix" b)
      , baProv = Nothing
      }

relationshipDecl :: BlockTree -> C BRelationshipDecl
relationshipDecl b = do
  n <- reqField "relationship_name" b >>= atomOf "relationship"
  arityT <- reqField "relationship_arity" b
  arity <-
    if Text.all isDigit arityT && not (Text.null arityT)
      then pure (readDigits arityT)
      else shapeErr b ("relationship_arity " <> quoted arityT <> " is not a number")
  when (arity < 3 || arity > 10) $
    shapeErr b ("relationship_declaration covers arity 3..10, not " <> arityT)
  tys <- traverse (\i -> reqField ("type" <> Text.textShow i) b >>= valueType) [1 .. arity]
  pure
    MkBRelationshipDecl
      { brName = n
      , brTypes = tys
      , brPrefixes = [fromMaybe "" (btField ("prefix" <> Text.textShow i) b) | i <- [1 .. arity]]
      , brPostfix = fromMaybe "" (btField "postfix" b)
      , brProv = Nothing
      }

-- | @object_declaration@. The mutation's @category_name@ is mandatory (the
-- generator reads @block.blawxCategoryName@, which only @domToMutation@
-- sets); its @prefix@\/@postfix@ are write-only and stale in the wild, so
-- they are carried verbatim and the literal pair @(\"null\",\"null\")@ —
-- which is what an absent attribute round-trips to — reads back as 'Nothing'.
objectDecl :: BlockTree -> C BObjectDecl
objectDecl b = do
  n <- reqField "object_name" b >>= atomOf "object"
  cat <- reqMut "category_name" b >>= atomOf "category"
  pure
    MkBObjectDecl
      { bodName = n
      , bodCategory = cat
      , bodPrefix = fromMaybe "" (btField "prefix" b)
      , bodPostfix = fromMaybe "" (btField "postfix" b)
      , bodMutNlg = case (fromMaybe "null" (btMut "prefix" b), fromMaybe "null" (btMut "postfix" b)) of
          ("null", "null") -> Nothing
          pair -> Just pair
      , bodProv = Nothing
      }

valueType :: Text -> C BValueType
valueType = \case
  "boolean" -> pure BVBoolean
  "number" -> pure BVNumber
  "date" -> pure BVDate
  "time" -> pure BVTime
  "datetime" -> pure BVDatetime
  "duration" -> pure BVDuration
  "list" -> pure BVList
  t -> BVCategory <$> atomOf "value type" t

-- ---------------------------------------------------------------------------
-- Slots
-- ---------------------------------------------------------------------------

reqField :: Text -> BlockTree -> C Text
reqField n b = maybe (shapeErr b ("no <field name=" <> quoted n <> ">")) pure (btField n b)

reqMut :: Text -> BlockTree -> C Text
reqMut n b = maybe (shapeErr b ("no <mutation " <> n <> "=…>")) pure (btMut n b)

reqValue :: Text -> BlockTree -> C BlockTree
reqValue n b =
  maybe
    (shapeErr b ("no <value name=" <> quoted n <> "> (slots present: " <> slots <> ")"))
    pure
    (btValue n b)
 where
  slots = Text.intercalate ", " (btSlotNames b)

reqStmt1 :: Text -> BlockTree -> C BlockTree
reqStmt1 n b = case btStmt n b of
  [x] -> pure x
  [] -> shapeErr b ("<statement name=" <> quoted n <> "> is empty")
  xs ->
    shapeErr b
      ( "<statement name=" <> quoted n <> "> holds "
          <> Text.textShow (length xs)
          <> " blocks where the IR admits one" )

docSelector :: BlockTree -> C BSectionRef
docSelector b
  | b.btType /= "doc_selector" =
      cerr "section-slot"
        ("a section slot holds <" <> b.btType <> "> where only a doc_selector has an IR spelling")
  | otherwise = do
      sr <- reqMut "section_reference" b
      case parseSectionName sr of
        Just ref -> pure ref
        Nothing -> cerr "section-name" ("section reference " <> quoted sr <> " is not AKN-shaped")

categorySelector :: BlockTree -> C BName
categorySelector b
  | b.btType /= "category_selector" =
      shapeErr b "a category slot must hold a category_selector"
  | otherwise = reqField "category_name" b >>= atomOf "category"

atomOf :: Text -> Text -> C BName
atomOf what t =
  maybe (cerr "atom" (what <> " name " <> quoted t <> " is not a Blawx atom")) pure (mkBName Nothing t)

quoted :: Text -> Text
quoted t = "\"" <> t <> "\""

-- ---------------------------------------------------------------------------
-- Names and rule text
-- ---------------------------------------------------------------------------

-- | The inverse of 'L4.Blawx.IR.renderSectionRef': @root_section@, or
-- @__@-separated @kind_label@ components with a @_section@ suffix. The
-- kind\/label split is at the FIRST underscore of each component, which is
-- what makes @subpara_i@ and @span_pingu@ recoverable.
parseSectionName :: Text -> Maybe BSectionRef
parseSectionName "root_section" = Just BRoot
parseSectionName t = do
  core <- Text.stripSuffix "_section" t
  steps <- traverse step (Text.splitOn "__" core)
  BPath <$> nonEmpty steps
 where
  step c = case Text.breakOn "_" c of
    (_, rest) | Text.null rest -> Nothing
    (kind, rest) -> mkBStep kind (Text.drop 1 rest)

-- | The inverse of 'L4.Blawx.Emit.renderRuleText', and deliberately total:
-- @rule_text@ is CLEAN prose that a human may have edited, and refusing to
-- import a document because its prose is not flat-numbered would be refusing
-- the wrong thing. A remainder that does not start with a numbered line stays
-- in the title, which re-renders byte-identically.
--
-- __Line endings are normalised to LF first.__ The CLEAN editor stores CRLF
-- (bird's @rule_text@ is CRLF throughout), so a reader that split on
-- @\"\\n\\n\"@ would find no paragraph break and swallow the whole Act into the
-- title. That is the __one__ place this parser is not byte-faithful to its
-- input, and it is deliberate: 'L4.Blawx.IR.BSection' documents @bsText@ as
-- \"one paragraph, no newlines\", so a CR inside one was never representable.
-- Our own emission has no CRs, so every P1\/P3 golden and the @--roundtrip@
-- property are unaffected.
parseRuleText :: Text -> BRuleText
parseRuleText t0 = case Text.breakOn "\n\n" t of
  (title, rest)
    | Text.null rest -> MkBRuleText {brTitle = title, brSections = []}
    | (l : ls) <- Text.splitOn "\n" (Text.drop 2 rest)
    , Just s0 <- numbered l ->
        MkBRuleText {brTitle = title, brSections = reverse (foldl' add [s0] ls)}
  _ -> MkBRuleText {brTitle = t, brSections = []}
 where
  t = Text.replace "\r\n" "\n" t0
  numbered l =
    let (ds, r) = Text.span isDigit l
    in  if Text.null ds
          then Nothing
          else do
            body <- Text.stripPrefix ". " r
            pure MkBSection {bsNumber = readDigits ds, bsText = body}
  add acc l = case numbered l of
    Just s -> s : acc
    -- A continuation line joins the section above it with its newline intact,
    -- so renderRuleText reproduces the original bytes.
    Nothing -> case acc of
      s : rest -> s {bsText = s.bsText <> "\n" <> l} : rest
      [] -> acc

-- ---------------------------------------------------------------------------
-- Round-trip normal forms
-- ---------------------------------------------------------------------------

-- | Everything the import cannot know, cleared on both sides of the
-- @lift . emit = id@ comparison: the 'Unique'\/'SrcRange' provenance that
-- points at L4 source, and 'L4.Blawx.IR.bdDocPartNames', which is the
-- /observed/ @doc_selector@ label — display-only bytes that Mode-A export
-- leaves empty and that "L4.Blawx.EmitXml" then recomputes identically. The
-- labels themselves are still checked, by the byte-level re-emission.
stripProvenance :: BlawxDoc -> BlawxDoc
stripProvenance doc =
  doc
    { bdDocPartNames = mempty
    , bdWorkspaces = [ws {bwStacks = map (map block) ws.bwStacks} | ws <- doc.bdWorkspaces]
    , bdTests = [t {btStacks = map (map block) t.btStacks, btProv = Nothing} | t <- doc.bdTests]
    }
 where
  block = \case
    BDeclareCategory d -> BDeclareCategory d {bcProv = Nothing}
    BDeclareAttribute d -> BDeclareAttribute d {baProv = Nothing}
    BDeclareRelationship d -> BDeclareRelationship d {brProv = Nothing}
    BDeclareObject d -> BDeclareObject d {bodProv = Nothing}
    BAttributedRule r -> BAttributedRule r {brProvenance = Nothing}
    BOverrules o -> BOverrules o {bovProv = Nothing}
    BUnattributedRule r -> BUnattributedRule r {burProv = Nothing}
    b@BFact{} -> b
    b@BConstraint{} -> b
    b@BAbducible{} -> b
    b@BQuery{} -> b
    b@BAssertGoal{} -> b

-- | The run partition as the normal form of a stack list. One
-- 'L4.Blawx.IR.bwStacks' entry is not one Blockly stack — a stack that mixes
-- chainable and root-only blocks draws as several roots — and the import can
-- only ever see the roots. Comparing modulo 'L4.Blawx.IR.blockRuns' therefore
-- compares exactly what both wire formats observe, and nothing else.
normaliseStacks :: BlawxDoc -> BlawxDoc
normaliseStacks doc =
  doc
    { bdWorkspaces = [ws {bwStacks = split ws.bwStacks} | ws <- doc.bdWorkspaces]
    , bdTests = [t {btStacks = split t.btStacks} | t <- doc.bdTests]
    }
 where
  split = concatMap (map runBlocks . blockRuns) . filter (not . null)
