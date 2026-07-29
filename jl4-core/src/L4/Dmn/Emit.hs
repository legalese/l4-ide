-- | Render a 'Drg' as DMN 1.3 XML.
--
-- Hand-rolled over 'Text' rather than through an XML library: emission-only XML
-- is a few dozen lines of escaping and indentation, and @jl4-core@ builds with
-- @-Wunused-packages -Werror@, so a dependency added for one direction of one
-- format would be a poor trade. (The same reasoning is why 'L4.OpenFisca.Emit'
-- builds Python as plain 'Text'.)
--
-- Two things the reader should be able to check by eye:
--
-- [Child order is XSD order] DMN's complex types are @xsd:sequence@s, so the
--   order of child elements is /normative/, not cosmetic. @tDefinitions@ wants
--   every @itemDefinition@ before any @drgElement@; @tItemDefinition@ wants
--   @typeRef?@ then @allowedValues?@ then @itemComponent*@; @tDecision@ wants
--   @variable@ before @informationRequirement@ before the expression;
--   @tDecisionTable@ wants @input*@ then @output+@ then @rule*@; @tInputClause@
--   wants @inputExpression@ then @inputValues?@; @tOutputClause@
--   wants @outputValues?@ then @defaultOutputEntry?@. Getting this wrong
--   produces a file that opens in some tools and is rejected by others.
--
--   __The obvious validator does not catch it.__ libxml2 (and therefore
--   @xmllint@, and therefore @etc\/validate-dmn.mjs@, whose own header says it
--   "does NOT check XSD sequence order") silently accepts an @itemDefinition@
--   placed after an @inputData@; Xerces rejects it with
--   @cvc-complex-type.2.4.a@. The gate is @etc\/kie-dmn-check\/run.sh@, which
--   validates against the DMN 1.3 schema shipped inside the KIE jar (§4.3, §9).
--
--   __What the engines then do, measured rather than assumed__ (2026-07-29, on
--   the matched pair in @jl4\/tests-cli\/fixtures\/dmn-xsd-order\/@, which holds
--   the same lines in the two orders): Camunda 8.7.6 rejects the misordered file
--   outright, at @parse@. Drools\/KIE 8.44 does /not/ — its schema and validator
--   legs object, but @KieBuilder@ is clean and the runtime answers both cases
--   correctly. So the schema check is the only thing between a misordered
--   emitter and a shipped artifact, which is exactly why it has to be the gate;
--   "it would fail in the engine" is not something to rely on.
--
-- [Nothing here is time- or run-dependent] No timestamps, no GUIDs, no
--   traversal counters: every id comes from an L4 name plus a positional index,
--   so the same module always emits the same bytes. That is a hard requirement,
--   because the goldens and the "artifact you can diff" story both depend on it.
--
-- The diagram interchange (DMNDI) block is generated from a deterministic
-- layered layout — inputs on the bottom row, each decision one row above its
-- deepest requirement. Without it a DRD opens as an empty canvas in dmn-js.
module L4.Dmn.Emit
  ( emitDrg
  , emitDecisionTable
  , escapeXmlText
  , escapeXmlAttr
  ) where

import Base
import qualified Base.Text as Text
import qualified Data.Map.Strict as Map

import L4.Dmn.IR

------------------------------------------------------------------------
-- A minimal XML writer
------------------------------------------------------------------------

data Xml
  = Elem !Text ![(Text, Text)] ![Xml]
  | Chars !Text

-- | Render with two-space indentation. An element whose only child is text is
-- rendered on one line, which is what makes @\<text\>@ cells readable.
renderXml :: Int -> Xml -> [Text]
renderXml depth = \case
  Chars t -> [indent depth <> escapeXmlText t]
  Elem name attrs [] -> [indent depth <> "<" <> name <> renderAttrs attrs <> "/>"]
  Elem name attrs [Chars t] ->
    [indent depth <> "<" <> name <> renderAttrs attrs <> ">" <> escapeXmlText t <> "</" <> name <> ">"]
  Elem name attrs kids ->
    [indent depth <> "<" <> name <> renderAttrs attrs <> ">"]
      <> concatMap (renderXml (depth + 1)) kids
      <> [indent depth <> "</" <> name <> ">"]
 where
  renderAttrs = foldMap (\(k, v) -> " " <> k <> "=\"" <> escapeXmlAttr v <> "\"")

indent :: Int -> Text
indent n = Text.replicate (n * 2) " "

-- | Escape XML character data. Control characters that XML 1.0 cannot carry at
-- all (not even as a numeric reference) become U+FFFD, so corruption is visible
-- rather than silent.
escapeXmlText :: Text -> Text
escapeXmlText = Text.concatMap esc
 where
  esc = \case
    '&' -> "&amp;"
    '<' -> "&lt;"
    '>' -> "&gt;"
    c | c == '\t' || c == '\n' || c == '\r' -> Text.singleton c
      | c < ' ' || c == '\x7f'              -> "\xfffd"
      | otherwise                           -> Text.singleton c

-- | As 'escapeXmlText', plus the quote characters and the whitespace that XML's
-- attribute-value normalisation would otherwise silently turn into spaces.
escapeXmlAttr :: Text -> Text
escapeXmlAttr = Text.concatMap esc
 where
  esc = \case
    '&'  -> "&amp;"
    '<'  -> "&lt;"
    '>'  -> "&gt;"
    '"'  -> "&quot;"
    '\'' -> "&apos;"
    '\t' -> "&#x9;"
    '\n' -> "&#xA;"
    '\r' -> "&#xD;"
    c | c < ' ' || c == '\x7f' -> "\xfffd"
      | otherwise              -> Text.singleton c

------------------------------------------------------------------------
-- Namespaces
------------------------------------------------------------------------

nsModel, nsDmndi, nsDc, nsDi :: Text
nsModel = "https://www.omg.org/spec/DMN/20191111/MODEL/"
nsDmndi = "https://www.omg.org/spec/DMN/20191111/DMNDI/"
nsDc    = "http://www.omg.org/spec/DMN/20180521/DC/"
nsDi    = "http://www.omg.org/spec/DMN/20180521/DI/"

------------------------------------------------------------------------
-- Emission
------------------------------------------------------------------------

emitDrg :: Drg -> Text
emitDrg drg =
  Text.unlines ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>" : renderXml 0 (definitionsXml drg))

-- | A single table, for tests and for embedding. Not a standalone DMN file.
emitDecisionTable :: DecisionTable -> Text
emitDecisionTable = Text.unlines . renderXml 0 . decisionTableXml

definitionsXml :: Drg -> Xml
definitionsXml drg =
  Elem "definitions"
    [ ("xmlns", nsModel)
    , ("xmlns:dmndi", nsDmndi)
    , ("xmlns:dc", nsDc)
    , ("xmlns:di", nsDi)
    , ("id", drg.drgId)
    , ("name", drg.drgName)
    , ("namespace", drg.drgNamespace)
    , ("exporter", "jl4")
    ]
    -- §4.3: itemDefinitions are the FIRST children of <definitions>, before
    -- every inputData and every decision. tDefinitions is an xsd:sequence.
    ( map itemDefinitionXml drg.drgItemDefs
        <> map nodeXml drg.drgNodes
        <> [dmndiXml drg]
    )

-- | A @\<itemDefinition\>@ (§4.1, §4.2).
--
-- @\<typeRef\>@ is a __child element__ here, not the attribute it is on a
-- @\<variable\>@ or an @\<inputExpression\>@ — @tItemDefinition@ declares it as
-- @xsd:sequence@ member, and the two spellings are not interchangeable.
--
-- Note what is __not__ emitted: no @isCollection@ (a @LIST OF@ field would need
-- an itemDefinition of its own, which is out of this phase's scope and reported
-- @D-ITEMDEF@), and no @typeLanguage@ (the default is FEEL, which is what we
-- mean).
itemDefinitionXml :: ItemDefinition -> Xml
itemDefinitionXml d =
  Elem "itemDefinition" (namedAttrs d.idfId d.idfName d.idfLabel) $
    [Elem "typeRef" [] [Chars (dmnTypeAttr b)] | b <- maybeToList d.idfBase]
      <> [valuesXml "allowedValues" vs | vs <- maybeToList d.idfValues]
      <> map componentXml d.idfComponents

componentXml :: ItemComponent -> Xml
componentXml c =
  Elem "itemComponent" (namedAttrs c.icmId c.icmName c.icmLabel)
    [Elem "typeRef" [] [Chars (dmnTypeAttr c.icmType)]]

-- | @allowedValues@ \/ @inputValues@ \/ @outputValues@: all three are
-- @tUnaryTests@, whose content is one @\<text\>@ holding a comma-separated list
-- of unary tests. Every value this exporter puts in one is a constructor name,
-- and 'quoteFeelString' is what spells it — the same function the /cells/ go
-- through, so a domain and a cell cannot disagree about what a value looks like.
valuesXml :: Text -> [Text] -> Xml
valuesXml name vs =
  Elem name [] [Elem "text" [] [Chars (Text.intercalate "," (map quoteFeelString vs))]]

-- | @id@, a FEEL-safe @name@, and — only when mangling changed something — the
-- verbatim L4 name as @label@.
--
-- __The node's @\@name@ and its variable's @\@name@ must be the same string.__
-- The two engines bind the FEEL name off different attributes: KIE resolves an
-- @inputData@ by the node's @\@name@, Camunda by the @\<variable\>@'s. This
-- emitter used to mangle only the latter, which is why the shipped golden was
-- rejected by both, for opposite reasons — KIE with @VARIABLE_NAME_MISMATCH@ and
-- then a build failure, Camunda 8 at @parse()@. Measured; see
-- @specs\/todo\/DMN-EXPORT-PROGRAM-MODEL-SPEC.md@ §13.2.
--
-- @label@ is an attribute of @tDMNElement@, so it is available on every element
-- type this emitter names. It is what makes the mangling cost nothing in
-- readability: the L4 name is still in the file, just not in the place FEEL
-- reads.
-- __The FEEL name is taken, not recomputed.__ This function used to call
-- @feelIdentText@ on the L4 name at emission time. That was correct only while
-- the mapping was a pure per-name fold; after §5.2 stage 2 (@uniquifyIn@) the
-- FEEL name is a property of the whole DRG — which of two colliding names got
-- the @_2@ depends on source order, not on the string — so it is resolved once
-- in "L4.Dmn.Lower" and carried on the IR. Recomputing it here would silently
-- undo every collision rename.
namedAttrs :: Text -> Text -> Text -> [(Text, Text)]
namedAttrs eid feel nm =
  [("id", eid), ("name", feel)] <> [("label", nm) | feel /= nm]

nodeXml :: DrgNode -> Xml
nodeXml = \case
  NodeInputData i ->
    Elem "inputData" (namedAttrs i.idId i.idFeelName i.idName)
      [ Elem "variable"
          (namedAttrs (i.idId <> "_var") i.idFeelName i.idName
             <> [("typeRef", dmnTypeAttr i.idType)])
          []
      ]
  NodeDecision d ->
    Elem "decision" (namedAttrs d.dcnId d.dcnFeelName d.dcnName) $
      -- tDecision is an xsd:sequence: variable, then informationRequirement*,
      -- then the expression.
      [ Elem "variable"
          (namedAttrs (d.dcnId <> "_var") d.dcnFeelName d.dcnName
             <> [("typeRef", dmnTypeAttr d.dcnType)])
          []
      ]
        <> zipWith (requirementXml d.dcnId) [1 :: Int ..] d.dcnRequirements
        <> [ case d.dcnLogic of
               LogicTable t   -> decisionTableXml t
               LogicLiteral e -> literalXml (d.dcnId <> "_literal") e
           ]

requirementXml :: Text -> Int -> Requirement -> Xml
requirementXml owner i req =
  Elem "informationRequirement" [("id", requirementId owner i)] [child]
 where
  child = case req of
    RequiredDecision target -> Elem "requiredDecision" [("href", "#" <> target)] []
    RequiredInput target    -> Elem "requiredInput" [("href", "#" <> target)] []

requirementId :: Text -> Int -> Text
requirementId owner i = owner <> "_ir" <> Text.pack (show i)

literalXml :: Text -> FeelExpr -> Xml
literalXml eid e = Elem "literalExpression" [("id", eid)] [Elem "text" [] [Chars e.feText]]

decisionTableXml :: DecisionTable -> Xml
decisionTableXml t =
  Elem "decisionTable"
    [ ("id", t.dtId)
    , ("hitPolicy", hitPolicyAttr t.dtHitPolicy)
    , ("preferredOrientation", "Rule-as-Row")
    , ("outputLabel", t.dtName)
    ]
    (map inputXml t.dtInputs <> [outputXml t.dtOutput] <> map ruleXml t.dtRules)

-- | One input clause. @tInputClause@ is @inputExpression@ then @inputValues?@.
--
-- The @\<inputValues\>@ is the whole of §3.1: DMN §8.2.4 assesses completeness
-- against the column's expected values, so a column that ships none hands an
-- analyser an unbounded domain and cannot be checked at all.
inputXml :: InputColumn -> Xml
inputXml c =
  Elem "input" [("id", c.icId), ("label", c.icLabel)] $
    [ Elem "inputExpression"
        [("id", c.icId <> "_expr"), ("typeRef", dmnTypeAttr c.icType)]
        [Elem "text" [] [Chars c.icExpr.feText]]
    ]
      <> [valuesXml "inputValues" vs | vs <- maybeToList c.icValues]

-- | The single output clause.
--
-- __No @\@name@ and no @\@typeRef@.__ /Read from/ DMN 8.2.11: an output clause
-- is named so that a multi-output table's result can be keyed, and with one
-- output the result /is/ the value. /Measured/, which is the part that decides
-- it: KIE says so out loud — @ILLEGAL_USE_OF_NAME@ and @ILLEGAL_USE_OF_TYPEREF@,
-- six warnings on the Reg CF exhibit alone — and dropping both takes KIE to 0
-- errors and 0 warnings and leaves Camunda 8's answers unchanged. Camunda 7
-- loses only the result-map /key/ (@{investor limit=80000}@ becomes
-- @{null=80000}@), and is not a target anyway. Nothing a reader needs is lost:
-- the decision's own @\<variable typeRef\>@ carries the type and
-- @decisionTable\/\@outputLabel@ carries the name. (§13.2. The DMN-clause
-- sentence is a reading of the specification; only the engine sentences are
-- measurements.)
--
-- 'OutputColumn' keeps both fields regardless, because "L4.Dmn.Markdown" needs
-- them — a dmnmd header is @name (out) : Type@ — and because a multi-output
-- table is a live Phase 4 item.
outputXml :: OutputColumn -> Xml
outputXml o =
  Elem "output" [("id", o.ocId)] $
    -- tOutputClause: outputValues? then defaultOutputEntry?, in that order.
    --
    -- outputValues is emitted for an ENUM-typed output only, and the narrowing
    -- is deliberate (§3.2). This used to say "we never emit outputValues,
    -- because we only know the values a table happens to mention, not the
    -- domain" -- true for a computed output, and false for one whose L4 type is
    -- an `IS ONE OF`, where the domain is the declaration. Not for a boolean
    -- either: there the domain IS the typeRef, so restating it would add no
    -- information while making every computed boolean entry violate §8.2.7.
    [valuesXml "outputValues" vs | vs <- maybeToList o.ocValues]
      <> [ Elem "defaultOutputEntry" [("id", o.ocId <> "_default")]
             [Elem "text" [] [Chars d.feText]]
         | d <- maybeToList o.ocDefault
         ]

ruleXml :: DmnRule -> Xml
ruleXml r =
  Elem "rule" [("id", r.drId)] $
    [Elem "description" [] [Chars d] | d <- maybeToList r.drDescription]
      <> [ Elem "inputEntry" [("id", r.drId <> "_i" <> Text.pack (show i))]
             [Elem "text" [] [Chars (renderUnaryTest test)]]
         | (i, test) <- zip [1 :: Int ..] r.drInputs
         ]
      <> [ Elem "outputEntry" [("id", r.drId <> "_o1")]
             [Elem "text" [] [Chars r.drOutput.feText]]
         ]

------------------------------------------------------------------------
-- Diagram interchange
------------------------------------------------------------------------

shapeWidth, shapeHeight, xGap, yGap, xOrigin, yOrigin :: Int
shapeWidth  = 180
shapeHeight = 80
xGap        = 220
yGap        = 160
xOrigin     = 60
yOrigin     = 60

-- | Deterministic layered layout: input data on the bottom row, each decision
-- one row above the deepest thing it requires.
dmndiXml :: Drg -> Xml
dmndiXml drg =
  Elem "dmndi:DMNDI" []
    [ Elem "dmndi:DMNDiagram"
        [("id", drg.drgId <> "_diagram"), ("name", drg.drgName)]
        (map shapeXml placed <> concatMap edgesXml (drgDecisions drg))
    ]
 where
  levels = decisionLevels drg
  levelOf eid = Map.findWithDefault 0 eid levels
  maxLevel = maximum (0 : Map.elems levels)

  -- Group by level in node order, so x positions are source-determined.
  byLevel :: Map Int [Text]
  byLevel = Map.fromListWith (flip (<>)) [(levelOf eid, [eid]) | eid <- nodeIds]

  nodeIds = map nodeId drg.drgNodes
  nodeId = \case
    NodeInputData i -> i.idId
    NodeDecision d  -> d.dcnId

  placed =
    [ (eid, x, y)
    | (lvl, ids) <- Map.toAscList byLevel
    , (i, eid) <- zip [0 :: Int ..] ids
    , let x = xOrigin + i * xGap
    , let y = yOrigin + (maxLevel - lvl) * yGap
    ]

  positions = Map.fromList [(eid, (x, y)) | (eid, x, y) <- placed]

  shapeXml (eid, x, y) =
    Elem "dmndi:DMNShape" [("id", eid <> "_shape"), ("dmnElementRef", eid)]
      [ Elem "dc:Bounds"
          [ ("x", tshowInt x)
          , ("y", tshowInt y)
          , ("width", tshowInt shapeWidth)
          , ("height", tshowInt shapeHeight)
          ]
          []
      ]

  edgesXml d =
    [ Elem "dmndi:DMNEdge"
        [ ("id", requirementId d.dcnId i <> "_edge")
        , ("dmnElementRef", requirementId d.dcnId i)
        ]
        [ waypoint (sx + shapeWidth `div` 2) sy
        , waypoint (tx + shapeWidth `div` 2) (ty + shapeHeight)
        ]
    | (i, req) <- zip [1 :: Int ..] d.dcnRequirements
    , Just (sx, sy) <- [Map.lookup (requirementTarget req) positions]
    , Just (tx, ty) <- [Map.lookup d.dcnId positions]
    ]

  waypoint x y = Elem "di:waypoint" [("x", tshowInt x), ("y", tshowInt y)] []

-- | Longest path to an input, so an edge always points from a lower row to a
-- higher one. The fold is bounded by the number of decisions, which terminates
-- even if a cycle sneaks past the self-reference filter in "L4.Dmn.Lower".
decisionLevels :: Drg -> Map Text Int
decisionLevels drg = go (Map.fromList [(i.idId, 0) | i <- drgInputData drg]) (length ds)
 where
  ds = drgDecisions drg
  go acc 0 = step acc
  go acc n = let acc' = step acc in if acc' == acc then acc else go acc' (n - 1 :: Int)
  step acc = foldl' bump acc ds
  bump acc d =
    let deps = [Map.findWithDefault 0 (requirementTarget r) acc | r <- d.dcnRequirements]
    in Map.insert d.dcnId (1 + maximum (0 : deps)) acc

tshowInt :: Int -> Text
tshowInt = Text.pack . show
