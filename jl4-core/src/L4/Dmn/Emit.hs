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
--   order of child elements is /normative/, not cosmetic. @tDecision@ wants
--   @variable@ before @informationRequirement@ before the expression;
--   @tDecisionTable@ wants @input*@ then @output+@ then @rule*@; @tOutputClause@
--   wants @outputValues?@ then @defaultOutputEntry?@. Getting this wrong
--   produces a file that opens in some tools and is rejected by others.
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
    (map nodeXml drg.drgNodes <> [dmndiXml drg])

nodeXml :: DrgNode -> Xml
nodeXml = \case
  NodeInputData i ->
    Elem "inputData" [("id", i.idId), ("name", i.idName)]
      -- The element's `name` is the L4 name as written, for a human; the
      -- variable's is the FEEL name a decision's expressions actually use.
      -- These differ only for names FEEL cannot carry verbatim.
      [ Elem "variable"
          [ ("id", i.idId <> "_var")
          , ("name", feelIdentText i.idName)
          , ("typeRef", dmnTypeAttr i.idType)
          ]
          []
      ]
  NodeDecision d ->
    Elem "decision" [("id", d.dcnId), ("name", d.dcnName)] $
      -- tDecision is an xsd:sequence: variable, then informationRequirement*,
      -- then the expression.
      [ Elem "variable"
          [ ("id", d.dcnId <> "_var")
          , ("name", feelIdentText d.dcnName)
          , ("typeRef", dmnTypeAttr d.dcnType)
          ]
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

inputXml :: InputColumn -> Xml
inputXml c =
  Elem "input" [("id", c.icId), ("label", c.icLabel)]
    [ Elem "inputExpression"
        [("id", c.icId <> "_expr"), ("typeRef", dmnTypeAttr c.icType)]
        [Elem "text" [] [Chars c.icExpr.feText]]
    ]

outputXml :: OutputColumn -> Xml
outputXml o =
  Elem "output" [("id", o.ocId), ("name", o.ocName), ("typeRef", dmnTypeAttr o.ocType)] $
    -- tOutputClause: outputValues? then defaultOutputEntry?. We never emit
    -- outputValues, because we only know the values a table happens to mention,
    -- not the domain -- and asserting a domain we have not checked is exactly the
    -- kind of thing this exporter refuses to do.
    [ Elem "defaultOutputEntry" [("id", o.ocId <> "_default")] [Elem "text" [] [Chars d.feText]]
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
