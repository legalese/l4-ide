-- | The import direction's back end: a parsed 'BlawxDoc' to __L4 source text__
-- (BLAWX-EXPORT-SPEC §8.14 R14, §10 P5; design in @p5-design\/lift-plan.md@).
--
-- __What this module is for.__ "L4.Blawx.Parse" answers /what blocks are
-- there/; this answers /what do they mean/. The split is where the two kinds
-- of refusal live: a block type with no IR landing zone (the date and event
-- layers) is refused there, by name; a program whose /semantics/ has no L4
-- image — an n-ary relation, a constraint whose expected answer is
-- unsatisfiability, an unbound query with no object universe to range over —
-- is refused here.
--
-- __The one idea.__ Blawx does not evaluate rules directly. Every
-- @attributed_rule@ in section @S@ concluding literal @L@ compiles to three
-- s(CASP) clauses, and the defeat relation is a fourth predicate:
--
-- > according_to(S, L, X)   :- <conditions> [, blawx_applies(S,X)  if inapplicable].
-- > holds(S, L, X)          :- according_to(S, L, X) [, not blawx_defeated(S,L,X)].
-- > L(X)                    :- holds(S, L, X).
-- > blawx_defeated(E, M, X) :- holds(D, M', X).          -- one per `overrules`
-- > blawx_applies(S, X)     :- not -blawx_applies(S, X). -- the `unattributed_rule` default
--
-- The lift __monomorphises those five schemas__: one named @BOOLEAN@ decision
-- per @(section, literal)@ pair, so the s(CASP) program becomes a stratified
-- boolean circuit L4 evaluates classically. That is legitimate exactly because
-- the negation is stratified — after stratification the well-founded, stable
-- and classical readings coincide — and it is checked, not assumed: the
-- dependency scan below refuses a program in which a node reaches itself
-- through a negative edge.
--
-- __The scan runs over the program the lift EMITS, not over the rules it read.__
-- That distinction is the whole point. Every negation in the output is
-- /introduced by the unfolding/: the @AND NOT \<defeated\>@ conjunct on a
-- defeasible rule, and the @naf@ in the applicability default. A scan over
-- @attributed_rule@ bodies alone sees no negative edge on bird at all — the
-- five rule-body edges are all positive — so it would be green on the very
-- document it exists to guard, and a second @overrules@ making two sections
-- defeat each other would emit a mutual recursion through @NOT@ that
-- type-checks and diverges. So 'Node' below has an arm per synthetic layer
-- (@according_to@, @holds@, @blawx_defeated@, @blawx_applies@), and
-- 'renderDoc' builds an edge for every clause it is about to write.
--
-- __The universe is flat.__ Blawx categories are unary predicates over one
-- universe of atoms (@penguin@, @bird@, @thing@ are all @_\/1@), so there is
-- __one__ record type per document, never one per category: a /derived/
-- category is not a type.
--
-- __Every declared predicate gets an input channel.__ Each category,
-- attribute and abducible gets one @MAYBE BOOLEAN@ field (@\<atom\> fact@),
-- OR-ed into that predicate's decision beneath whatever rules conclude it.
-- @holds@ from @negation-as-failure.l4@ is @fromMaybe FALSE@, which is
-- exactly s(CASP)'s \"unproven fails\", so an absent fact costs nothing.
--
-- (@p5-design\/lift-plan.md@ §3's table gave @flies@ — a /concluded/
-- attribute — a field and denied @bird@ — a /concluded/ category — one, and
-- an earlier revision of this module implemented the table. The asymmetry
-- cannot be right in both halves, and the faithful half is @flies@: a
-- declaration emits @:- dynamic p\/1.@ regardless of kind
-- (@scasp_generator.js:1088@), so a scenario may assert @bird(x).@ exactly
-- the way bird's own tests assert @on_plane(pingu).@. With no field to carry
-- it, such a scenario fact was __silently dropped__ by 'recordFields' —
-- a wrong answer, not a missing feature. Uniform channels fix it; a test
-- asserting a fact about an /undeclared/ predicate is now refused by name
-- rather than dropped.)
--
-- __@logical_negation@ is not @NOT@.__ @-p@ is a /different predicate/ from
-- @p@, not its negation: both can be false at once. Rendering it as L4's @NOT@
-- agrees on bird's four tests and diverges on a fifth, so a negative literal
-- becomes its own named decision, and only @default_negation@ becomes @NOT@ /
-- @naf@. @naf@ (over a @MAYBE BOOLEAN@) is used exactly where the negated
-- predicate is an INPUT, because only there does \"unknown\" have to behave as
-- \"absent\"; over a total @BOOLEAN@ it would be a no-op.
--
-- __Comments (ruling P5-4)__ ride in on 'BTest' and on 'BWorkspace', and are
-- re-wrapped as @--@ lines: a test's above the @#EVAL@ it annotates, a
-- workspace's under the @§§@ of the section it belongs to (@root_section@'s
-- under @§§ Ontology@). Measured over the corpus's 18 @\<comment\>@ elements,
-- __6 sit on workspaces__ — @oasa@'s and @r34@'s drafter rationale, the prose
-- a lift most wants to carry — so reading only the test's would have honoured
-- P5-4 for two thirds of the corpus and silently dropped the rest. A comment
-- on a workspace whose path is not rooted at a @sec@ step has nowhere to go
-- and __warns__ rather than vanishing. They are __import-only__: neither
-- @renderScasp@ nor @renderXml@ images them, so a re-emitted @.blawx@ drops
-- them. That is deliberate, and it is what keeps the re-save fixpoint green —
-- the generator prefixes a block comment through @Blockly.utils.string.wrap@
-- (@scasp_generator.js:41-49@), whose line balancing we do not reproduce, so
-- emitting the XML comment without that exact wrap would break the byte-diff.
-- Dropping it on __both__ sides keeps the two agreeing.
module L4.Blawx.Lift
  ( liftBlawx
  , LiftContext (..)
  , emptyLiftContext
  , LiftDiag (..)
  , LiftSeverity (..)
  , renderLiftDiag
  ) where

import Base
import qualified Base.Map as Map
import qualified Base.Text as Text
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)

import L4.Blawx.Emit (renderGoal)
import L4.Blawx.IR

-- ---------------------------------------------------------------------------
-- Diagnostics
-- ---------------------------------------------------------------------------

data LiftSeverity = LiftError | LiftWarning
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData)

-- | One finding. The code is the stable half — messages may be reworded,
-- codes are what a harness greps for.
data LiftDiag = MkLiftDiag
  { ldCode     :: !Text
  , ldSeverity :: !LiftSeverity
  , ldWhere    :: !Text   -- ^ workspace or test name; @""@ for document-level
  , ldMessage  :: !Text
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

renderLiftDiag :: LiftDiag -> Text
renderLiftDiag d =
  sev <> " blawx-lift/" <> d.ldCode <> ": " <> whence <> d.ldMessage
 where
  sev = case d.ldSeverity of
    LiftError -> "ERROR"
    LiftWarning -> "WARNING"
  whence = if Text.null d.ldWhere then "" else d.ldWhere <> ": "

-- | Everything the lift needs that the block IR does not carry: where the
-- document came from, and whatever the YAML and parse layers observed that
-- belongs in the emitted file's provenance header (row and block counts, the
-- P5-2 staleness warning). Opaque lines, so this module never grows a second
-- opinion about what the parse found.
data LiftContext = MkLiftContext
  { lcSource :: !Text
  , lcNotes  :: ![Text]
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

emptyLiftContext :: LiftContext
emptyLiftContext = MkLiftContext {lcSource = "", lcNotes = []}

-- ---------------------------------------------------------------------------
-- The monad
-- ---------------------------------------------------------------------------

-- | Diagnostics accumulate while the text is built, so a refusal is reported
-- from the place that found it and the walk still finishes — one run names
-- every unliftable construct, not just the first. The placeholder text an
-- error leaves behind is never emitted: 'liftBlawx' returns 'Left' whenever
-- any error was recorded.
type L = State [LiftDiag]

say :: LiftSeverity -> Text -> Text -> Text -> L ()
say sev code whence msg =
  modify' (MkLiftDiag {ldCode = code, ldSeverity = sev, ldWhere = whence, ldMessage = msg} :)

refuse :: Text -> Text -> Text -> L Text
refuse code whence msg = do
  say LiftError code whence msg
  pure ("<<" <> code <> ">>")

refuse_ :: Text -> Text -> Text -> L ()
refuse_ code whence msg = void (refuse code whence msg)

warn :: Text -> Text -> Text -> L ()
warn = say LiftWarning

-- ---------------------------------------------------------------------------
-- Entry point
-- ---------------------------------------------------------------------------

-- | Lift a parsed document to L4 source. 'Left' — with at least one error —
-- when any construct has no L4 image; the source plus warnings otherwise.
liftBlawx :: LiftContext -> BlawxDoc -> Either [LiftDiag] (Text, [LiftDiag])
liftBlawx ctx doc
  | null errs = Right (src, warns)
  | otherwise = Left errs
 where
  (src, ds) = runState (renderDoc ctx doc) []
  ordered = reverse ds
  errs = [d | d <- ordered, d.ldSeverity == LiftError]
  warns = [d | d <- ordered, d.ldSeverity == LiftWarning]

-- ---------------------------------------------------------------------------
-- Analysis and rendering
-- ---------------------------------------------------------------------------

-- | A predicate as the lift names it: an atom plus a classical sign.
-- @(\"flies\", False)@ is @-flies@, a different predicate from
-- @(\"flies\", True)@, and it gets its own decision.
type Lit = (Text, Bool)

-- | A declaration that reached the ontology.
--
-- There is deliberately no @dclKind@ field. It existed to drive @hasChannel@'s
-- category\/attribute split, that split turned out to be unsound (see the
-- module header), and a field nobody reads is a claim nobody re-checks — which
-- @-Wall@ cannot tell you about under @NoFieldSelectors@. The three source
-- lists in 'decls' still carry the distinction where it is actually used.
data Decl = MkDecl
  { dclName    :: !Text
  , dclPrefix  :: !Text
  , dclPostfix :: !Text
  , dclRef     :: !Text     -- ^ the @\@ref@ line body
  }

-- | How an atom got into the object universe: an @object_declaration@ names
-- it and gives it a category, or a ground fact merely mentions it.
data UnivFrom
  = UnivDeclared !BSectionRef !BObjectDecl
  | UnivFact !BSectionRef

-- | A node of the dependency graph __of the module this lift emits__ — one
-- arm per named decision the paragraph builders write. 'NLit' is the base
-- predicate; the other five are the layers the boolean unfolding
-- monomorphises, and they are where every negation in the output lives.
--
-- 'NNegApplies' is a sink: @-blawx_applies@ is rendered as a @MEANS@ over an
-- input field plus the span carve-outs, so it has no outgoing edges. It is
-- still a node, because a scan that silently discarded it would be discarding
-- the target of the applicability default's @naf@.
data Node
  = NLit !Lit
  | NAcc !BSectionRef !Lit
  | NHolds !BSectionRef !Lit
  | NDefeated !BSectionRef !Lit
  | NApplies !BSectionRef
  | NNegApplies !BSectionRef
  deriving stock (Eq, Ord, Show)

-- | Classical negation, at the node level: @-p@ for a base literal, and the
-- @blawx_applies@ \/ @-blawx_applies@ pair for the applicability layer.
flipNode :: Node -> Node
flipNode = \case
  NLit (n, s) -> NLit (n, not s)
  NAcc r (n, s) -> NAcc r (n, not s)
  NHolds r (n, s) -> NHolds r (n, not s)
  NDefeated r (n, s) -> NDefeated r (n, not s)
  NApplies r -> NNegApplies r
  NNegApplies r -> NApplies r

-- | A node as the s(CASP) spells it, for the @unstratified@ diagnostic.
renderNode :: Node -> Text
renderNode = \case
  NLit l -> scaspLit l
  NAcc r l -> "according_to(" <> renderSectionRef r <> "," <> scaspLit l <> ")"
  NHolds r l -> "holds(" <> renderSectionRef r <> "," <> scaspLit l <> ")"
  NDefeated r l -> "blawx_defeated(" <> renderSectionRef r <> "," <> scaspLit l <> ")"
  NApplies r -> "blawx_applies(" <> renderSectionRef r <> ")"
  NNegApplies r -> "-blawx_applies(" <> renderSectionRef r <> ")"

scaspLit :: Lit -> Text
scaspLit (n, True) = n
scaspLit (n, False) = "-" <> n

-- | The block type, for a diagnostic that has to name what it refused.
blockLabel :: BBlock -> Text
blockLabel = \case
  BDeclareCategory {} -> "a `new_category_declaration`"
  BDeclareAttribute {} -> "a `new_attribute_declaration`"
  BDeclareRelationship {} -> "a `relationship_declaration`"
  BAttributedRule {} -> "an `attributed_rule`"
  BFact True _ _ -> "a fact that is not a unary predicate applied to one atom"
  BFact False _ _ -> "a `logical_negation` fact (a NEGATIVE scenario fact)"
  BConstraint {} -> "a `constraint`"
  BAbducible {} -> "an `assume`"
  BQuery {} -> "a `query`"
  BDeclareObject {} -> "an `object_declaration`"
  BOverrules {} -> "an `overrules`"
  BUnattributedRule {} -> "an `unattributed_rule`"
  BAssertGoal g -> "a fact-position `" <> renderGoal g <> "`"

renderDoc :: LiftContext -> BlawxDoc -> L Text
renderDoc ctx doc = do
  -- ---- constructs with no L4 image ------------------------------------
  for_ blocks \(ws, b) -> case b of
    BDeclareRelationship d ->
      refuse_ "relationship" (renderSectionRef ws)
        ( "relationship_declaration " <> bNameText d.brName <> "/"
            <> Text.textShow (length d.brTypes)
            <> " has no L4 image this phase: the lift models one flat universe of "
            <> "objects under UNARY predicates, and an n-ary relation is not one" )
    BConstraint _ ->
      refuse_ "constraint" (renderSectionRef ws)
        ( "a `false :- …` constraint says the program must have no stable model; "
            <> "L4 evaluation is total and has no \"no model\" answer "
            <> "(BLAWX-EXPORT-SPEC §5.2, the logical_constraints OUT entry)" )
    BQuery _ ->
      refuse_ "query-in-workspace" (renderSectionRef ws)
        "a `query` block belongs to a test, not to a rule workspace"
    _ -> pure ()

  for_ attrDecls \(ws, d) ->
    when (d.baType /= BVBoolean) $
      refuse_ "attribute-type" (renderSectionRef ws)
        ( "attribute " <> bNameText d.baName <> " has value type "
            <> renderValueType d.baType
            <> "; only a boolean attribute is a unary predicate over the object "
            <> "universe, and only those lift this phase" )

  for_ facts \(ws, (_, p, as)) ->
    unless (all isAtomArg as && length as == 1) $
      refuse_ "fact-shape" (renderSectionRef ws)
        ( "the fact `" <> renderGoal (BGCall True p as)
            <> "` is not a unary predicate applied to one object atom" )

  -- A test canvas gets the same vetting a workspace canvas gets. 'testPara'
  -- consumes exactly two shapes — a positive unary ground fact and the query
  -- — and everything else it simply does not look at, so without this pass a
  -- test's `object_declaration`, `assume`, `logical_negation` or nested rule
  -- is dropped with no diagnostic. Measured over the shipped corpus that is
  -- not hypothetical: 11 tests across 8 examples declare their own objects,
  -- 3 carry `assume`, and 2 assert a NEGATIVE scenario fact — which would
  -- have made the #EVAL answer a question the Blawx test did not ask.
  for_ [(t, b) | t <- doc.bdTests, st <- t.btStacks, b <- st] \(t, b) ->
    case b of
      BQuery _ -> pure ()
      BFact True p as
        | all isAtomArg as && length as == 1 ->
            unless ((bNameText p <> " fact") `elem` fieldNames) $
              refuse_ "scenario-undeclared" t.btName
                ( "the scenario asserts `" <> renderGoal (BGCall True p as)
                    <> "` but `" <> bNameText p
                    <> "` is not declared, so there is no field to carry it" )
      _ ->
        refuse_ "test-block" t.btName
          ( "a test canvas may hold only positive unary ground facts and one "
              <> "`query`; " <> blockLabel b <> " has no #EVAL image this phase" )

  -- ---- placement ------------------------------------------------------
  for_ arules \(ws, r) -> do
    unless (r.brSection `elem` flatRefs) $
      refuse_ "rule-section" (renderSectionRef ws)
        ( "the rule is attributed to " <> renderSectionRef r.brSection
            <> ", which is not a flat numbered section; the § scaffolding has "
            <> "nowhere to put it" )
    when (r.brSection /= ws) $
      warn "rule-filed-elsewhere" (renderSectionRef ws)
        ( "the rule's doc_selector names " <> renderSectionRef r.brSection
            <> ", not the workspace it is drawn in; the attribution wins" )

  for_ defeatGroups \g ->
    unless (groupHome g `elem` flatRefs) $
      refuse_ "defeat-section" (renderSectionRef (fst (fst g)))
        "an `overrules` names a section that is not a flat numbered section"

  for_ appliesSections \s ->
    unless (s `elem` flatRefs) $
      refuse_ "applies-section" (renderSectionRef s)
        "`applies` names a section that is not a flat numbered section"

  -- ---- stratification -------------------------------------------------
  for_ negCycles \n ->
    refuse_ "unstratified" ""
      ( "unstratified: " <> renderNode n <> " reaches itself through a negated "
          <> "conjunct, so the well-founded and classical readings differ and "
          <> "the boolean unfolding is not sound" )

  -- ---- warnings -------------------------------------------------------
  for_ emptyWorkspaces \ws ->
    warn "empty-workspace" (renderSectionRef ws)
      "the workspace carries no blocks; its section heading is emitted with no decisions"

  for_ unplacedComments \(ws, _) ->
    warn "comment-unplaced" (renderSectionRef ws)
      ( "the workspace carries a `<comment>` but its name is not rooted at a "
          <> "numbered section, so the prose has no § to sit under (ruling P5-4)" )

  ontology <- ontologyParas
  clauses <- concat <$> traverse clausePara secNumbers
  basePreds <- basePredParas
  tests <- testParas

  pure $
    Text.intercalate "\n\n"
      ( [headerPara, importsPara, titlePara]
          <> ontology
          <> clauses
          <> basePreds
          <> objectParas
          <> tests )
      <> "\n"
 where
  -- ------------------------------------------------------------------
  -- Inventory
  -- ------------------------------------------------------------------
  blocks :: [(BSectionRef, BBlock)]
  blocks = [(ws.bwName, b) | ws <- doc.bdWorkspaces, st <- ws.bwStacks, b <- st]

  catDecls = [(ws, d) | (ws, BDeclareCategory d) <- blocks]
  attrDecls = [(ws, d) | (ws, BDeclareAttribute d) <- blocks]
  objDecls = [(ws, d) | (ws, BDeclareObject d) <- blocks]
  arules = [(ws, r) | (ws, BAttributedRule r) <- blocks]
  overrs = zip [1 :: Int ..] [(ws, o) | (ws, BOverrules o) <- blocks]
  urules = [(ws, r) | (ws, BUnattributedRule r) <- blocks]
  asserts = [(ws, g) | (ws, BAssertGoal g) <- blocks]
  facts = [(ws, (s, p, as)) | (ws, BFact s p as) <- blocks]
  abducs = [(ws, p) | (ws, BAbducible p _) <- blocks]

  emptyWorkspaces = [ws.bwName | ws <- doc.bdWorkspaces, all null ws.bwStacks]

  isAtomArg = \case
    BTAtom _ -> True
    _ -> False

  -- ------------------------------------------------------------------
  -- Declarations
  -- ------------------------------------------------------------------
  decls :: [Decl]
  decls = catList <> attrList <> abducList
   where
    catList =
      [ MkDecl
          { dclName = bNameText d.bcName
          , dclPrefix = d.bcPrefix
          , dclPostfix = d.bcPostfix
          , dclRef =
              renderSectionRef ws <> " new_category_declaration "
                <> padTo (declNameWidth + 2) (bNameText d.bcName)
                <> "(NLG " <> quoted d.bcPrefix <> " / " <> quoted d.bcPostfix <> ")"
          }
      | (ws, d) <- catDecls
      ]
    attrList =
      [ MkDecl
          { dclName = bNameText d.baName
          , dclPrefix = d.baPrefix
          , dclPostfix = d.baPostfix
          , dclRef =
              renderSectionRef ws <> " new_attribute_declaration "
                <> bNameText d.baCategory <> "." <> bNameText d.baName
                <> " : " <> renderValueType d.baType
          }
      | (ws, d) <- attrDecls
      ]
    declaredNames = map (.dclName) (catList <> attrList)
    abducList =
      [ MkDecl
          { dclName = bNameText p
          , dclPrefix = ""
          , dclPostfix = ""
          , dclRef = renderSectionRef ws <> " assume " <> bNameText p
          }
      | (ws, p) <- nubOn (bNameText . snd) abducs
      , bNameText p `notElem` declaredNames
      ]

  declNameWidth = maximum (1 : [Text.length (bNameText d.bcName) | (_, d) <- catDecls])

  declOf :: Text -> Maybe Decl
  declOf n = find (\d -> d.dclName == n) decls

  -- ------------------------------------------------------------------
  -- Rules and literals
  -- ------------------------------------------------------------------
  concluding :: [(Lit, (BSectionRef, BRule))]
  concluding =
    [ ((bNameText r.brConclusion.bcPred, r.brConclusion.bcSign), (r.brSection, r))
    | (_, r) <- arules
    ]

  concludedLits :: [Lit]
  concludedLits = nub (map fst concluding)

  sectionsConcluding :: Lit -> [BSectionRef]
  sectionsConcluding l = [s | (l', (s, _)) <- concluding, l' == l]

  -- Every declared predicate gets an input channel, whatever its kind and
  -- whether or not a rule concludes it — see the module header for why the
  -- older category/attribute split was unsound. A predicate NO rule concludes
  -- gets its whole decision from the channel ('inputDecision'); one some rule
  -- concludes gets the channel as one more OR arm ('basePred').
  channelDecls = decls
  channelNames = map (.dclName) channelDecls
  inputDecls = [d | d <- decls, (d.dclName, True) `notElem` concludedLits]

  -- ------------------------------------------------------------------
  -- Section labels
  -- ------------------------------------------------------------------
  labelOf :: BSectionRef -> Text
  labelOf s = case Map.lookup s doc.bdDocPartNames of
    Just l -> l
    Nothing -> case (labelPrefix, s) of
      (Just p, BPath (st :| [])) | bStepKind st == "sec" -> p <> bStepLabel st
      _ -> renderSectionRef s

  -- The stored `doc_part_name`s of the flat sections agree on everything but
  -- the number in the examples that carry them, so a section with no
  -- doc_selector pointing at it (bird's sec_6) still gets the label the Act
  -- uses. When they do not agree, the workspace name is the honest answer.
  labelPrefix :: Maybe Text
  labelPrefix = case nub stems of
    [p] -> Just p
    _ -> Nothing
   where
    stems =
      [ Text.dropEnd (Text.length lbl) l
      | (BPath (st :| []), l) <- Map.toList doc.bdDocPartNames
      , bStepKind st == "sec"
      , let lbl = bStepLabel st
      , lbl `Text.isSuffixOf` l
      ]

  -- ------------------------------------------------------------------
  -- Literal phrasing (the generator's own #pred sentences)
  -- ------------------------------------------------------------------
  phrase :: Lit -> Text
  phrase (n, True) = nlgWith "x" n
  phrase (n, False) = "it is not the case that " <> nlgWith "x" n

  nlgWith :: Text -> Text -> Text
  nlgWith subj n = case declOf n of
    Just d | not (Text.null (Text.strip d.dclPostfix)) ->
      Text.unwords
        (filter (not . Text.null) [Text.strip d.dclPrefix, subj, Text.strip d.dclPostfix])
    _ -> Text.unwords [n, subj]

  hasNlg :: Text -> Bool
  hasNlg n = case declOf n of
    Just d -> not (Text.null (Text.strip d.dclPostfix))
    Nothing -> False

  litName :: Lit -> Text
  litName (n, True) = n
  litName l@(_, False) = phrase l

  nlgSuffix :: Lit -> Text
  nlgSuffix (n, sign)
    | not (hasNlg n) = ""
    | sign = " @nlg " <> nlgWith "%x%" n
    | otherwise = " @nlg it is not the case that " <> nlgWith "%x%" n

  accordingName s l = "according to " <> labelOf s <> ", " <> phrase l
  holdsName s l = "the conclusion in " <> labelOf s <> " that " <> phrase l <> " holds"
  defeatedName s l = "the conclusion in " <> labelOf s <> " that " <> phrase l <> " is defeated"
  appliesName s = labelOf s <> " applies to x"
  negAppliesName s = "it is not the case that " <> labelOf s <> " applies to x"
  exclusionField s = labelOf s <> " exclusion fact"

  -- ------------------------------------------------------------------
  -- The defeat layer
  -- ------------------------------------------------------------------
  overruleLit :: BConclusion -> Lit
  overruleLit c = (bNameText c.bcPred, c.bcSign)

  -- One group per defeated (section, literal) pair, in first-appearance
  -- order; two `overrules` naming the same pair become one OR.
  defeatGroups :: [((BSectionRef, Lit), [(Int, BSectionRef, BOverrule)])]
  defeatGroups =
    [ (k, [(i, ws, o) | (i, (ws, o)) <- overrs, key o == k])
    | k <- nub [key o | (_, (_, o)) <- overrs]
    ]
   where
    key o = (o.bovDefeated, overruleLit o.bovDefeatedStmt)

  -- A group is emitted in the section of its first defeating block — which is
  -- where a reader looks for "what this section overrides". A defeater drawn
  -- somewhere unplaceable falls back to the defeated section.
  groupHome :: ((BSectionRef, Lit), [(Int, BSectionRef, BOverrule)]) -> BSectionRef
  groupHome (k, ms) = case ms of
    (_, ws, _) : _ | ws `elem` flatRefs -> ws
    _ -> fst k

  isDefeated :: BSectionRef -> Lit -> Bool
  isDefeated s l = any ((== (s, l)) . fst) defeatGroups

  -- ------------------------------------------------------------------
  -- Applicability
  -- ------------------------------------------------------------------
  appliesSections :: [BSectionRef]
  appliesSections =
    nub
      ( [s | (_, g) <- asserts, s <- appliesOf g]
          <> [s | (_, r) <- arules, g <- r.brConditions, s <- appliesOf g]
          <> [s | (_, r) <- urules, g <- r.burConclusion <> r.burConditions, s <- appliesOf g]
          <> [r.brSection | (_, r) <- arules, r.brInapplicable] )
   where
    appliesOf = \case
      BGApplies s _ -> [s]
      BGNegated _ g -> appliesOf g
      BGHolds _ g -> appliesOf g
      BGAccordingTo _ g -> appliesOf g
      _ -> []

  unwrapAssert :: BGoal -> BGoal
  unwrapAssert = \case
    BGHolds _ g -> g
    BGAccordingTo _ g -> g
    g -> g

  -- The atoms a `holds( -blawx_applies(S, o) )` assertion carves out of S.
  carveOuts :: BSectionRef -> [Text]
  carveOuts s =
    nub
      [ bNameText o
      | (_, g) <- asserts
      , BGNegated BNegClassical (BGApplies s' (BTAtom o)) <- [unwrapAssert g]
      , s' == s
      ]

  carveWorkspaces :: BSectionRef -> [BSectionRef]
  carveWorkspaces s =
    nub
      [ ws
      | (ws, g) <- asserts
      , BGNegated BNegClassical (BGApplies s' _) <- [unwrapAssert g]
      , s' == s
      ]

  appliesRule :: BSectionRef -> Maybe (BSectionRef, BURule)
  appliesRule s = find (\(_, r) -> any headIsApplies r.burConclusion) urules
   where
    headIsApplies = \case
      BGApplies s' _ -> s' == s
      _ -> False

  -- ------------------------------------------------------------------
  -- Objects
  -- ------------------------------------------------------------------
  objects :: [(BSectionRef, BObjectDecl)]
  objects = objDecls

  -- __The universe, and why it is not just the declarations.__ Blawx has no
  -- open domain: an atom exists because an `object_declaration` introduced it
  -- OR because a ground fact mentioned it (the declaration emits
  -- `:- dynamic p/1.`, so `penguin(tweety).` is an ordinary clause and
  -- `tweety` an ordinary atom). 'membersOf' already counts both; drawing
  -- 'objectNames' from the declarations alone made the two halves of this
  -- lift disagree about who exists — `penguin tweety` would come back TRUE
  -- while `filter penguin \`all objects\`` could not see it, so an
  -- existential #EVAL answered over a smaller universe than s(CASP) enumerates.
  universe :: [(Text, UnivFrom)]
  universe =
    nubOn fst $
      [(bNameText d.bodName, UnivDeclared ws d) | (ws, d) <- objects]
        <> [ (bNameText o, UnivFact ws)
           | (ws, (_, _, as)) <- facts
           , BTAtom o <- as
           ]

  objectNames = map fst universe

  -- A category's members, from `object_declaration` and from ground facts.
  membersOf :: Text -> [Text]
  membersOf c =
    nub
      ( [bNameText d.bodName | (_, d) <- objects, bNameText d.bodCategory == c]
          <> [bNameText o | (_, (True, p, [BTAtom o])) <- facts, bNameText p == c] )

  -- ------------------------------------------------------------------
  -- Record fields
  -- ------------------------------------------------------------------
  fieldDescs :: [(Text, Text)]
  fieldDescs =
    [("name", "the object's Blawx atom")]
      <> [(d.dclName <> " fact", phrase (d.dclName, True)) | d <- channelDecls]
      <> [(exclusionField s, negAppliesName s) | s <- appliesSections]

  fieldNames :: [Text]
  fieldNames = map fst fieldDescs

  fieldWidth = maximum (1 : map (Text.length . ident) fieldNames)

  -- ------------------------------------------------------------------
  -- Stratification
  -- ------------------------------------------------------------------
  -- Edges are head-node -> body-node, tagged with whether the dependency
  -- passed under a negation. The program is unstratified when a negative edge
  -- sits inside a cycle; reachability is a fixpoint rather than a path
  -- enumeration, so a 900-block document does not take exponential time.
  --
  -- ONE EDGE PER CLAUSE THIS MODULE IS ABOUT TO EMIT. The four groups below
  -- are, in order, the four paragraph builders: 'rulePara' (the
  -- according_to/holds pair and the `inapplicable` guard), 'basePred',
  -- 'defeatPara' and 'appliesParas'. If a builder gains a clause, it gains an
  -- edge here, or the guard goes quietly blind again.
  depEdges :: [(Node, Node, Bool)]
  depEdges = ruleEdges <> baseEdges <> defeatEdges <> appliesEdges
   where
    ruleEdges = concat
      [ [(NAcc s l, n, neg) | g <- r.brConditions, (n, neg) <- goalDeps False g]
          -- `inapplicable` injects `blawx_applies(S,x)` after every
          -- new_object_category condition ('ruleCondition').
          <> [ (NAcc s l, NApplies s, False)
             | r.brInapplicable
             , BGNewObjectCategory _ _ <- r.brConditions
             ]
          <> [(NHolds s l, NAcc s l, False)]
          -- the `AND NOT <defeated>` conjunct: the first negative edge the
          -- unfolding introduces, and invisible to a scan over rule bodies.
          <> [(NHolds s l, NDefeated s l, True) | r.brDefeasible, isDefeated s l]
      | (_, r) <- arules
      , let s = r.brSection
      , let l = (bNameText r.brConclusion.bcPred, r.brConclusion.bcSign)
      ]
    baseEdges =
      [(NLit l, NHolds s l, False) | l <- concludedLits, s <- sectionsConcluding l]
    defeatEdges =
      [ (NDefeated s l, NHolds o.bovDefeating (overruleLit o.bovDefeatingStmt), False)
      | ((s, l), ms) <- defeatGroups
      , (_, _, o) <- ms
      ]
    -- the closed-world applicability default, whose whole content is a `naf`:
    -- the second negative edge, equally invisible to a rule-body scan.
    appliesEdges =
      [ (NApplies s, n, neg)
      | s <- appliesSections
      , Just (_, r) <- [appliesRule s]
      , g <- r.burConditions
      , (n, neg) <- goalDeps False g
      ]

  -- | The literal a conclusion-shaped goal names, for the @holds@ and
  -- @according_to@ wrappers. Empty when the payload is not a plain predicate
  -- (bird's @holds( -blawx_applies(…) )@), in which case 'goalDeps' keeps the
  -- inner goal's own dependencies rather than dropping the edge.
  goalLit :: BGoal -> [Lit]
  goalLit = \case
    BGCall s p _ -> [(bNameText p, s)]
    BGNewObjectCategory p _ -> [(bNameText p, True)]
    BGNaf p _ -> [(bNameText p, True)]
    BGNegated BNegClassical g -> [(n, not s) | (n, s) <- goalLit g]
    BGNegated BNegDefault g -> goalLit g
    _ -> []

  -- | Total by construction: every 'BGoal' arm is spelled out, because a
  -- catch-all returning \"no dependency\" is the wrong default for a
  -- soundness scan — it is how 'BGApplies', 'BGHolds' and 'BGAccordingTo',
  -- the three constructors ruling P5-1 added, contributed no edge at all.
  goalDeps :: Bool -> BGoal -> [(Node, Bool)]
  goalDeps neg = \case
    BGCall s p _ -> [(NLit (bNameText p, s), neg)]
    BGNaf p _ -> [(NLit (bNameText p, True), True)]
    BGNewObjectCategory p _ -> [(NLit (bNameText p, True), neg)]
    BGApplies s _ -> [(NApplies s, neg)]
    BGHolds s g -> wrap (NHolds s) g
    BGAccordingTo s g -> wrap (NAcc s) g
    BGNegated BNegDefault g -> goalDeps True g
    BGNegated BNegClassical g -> [(flipNode n, b) | (n, b) <- goalDeps neg g]
    BGFindall _ gs _ -> concatMap (goalDeps neg) gs
    -- arithmetic, comparison, unification and aggregation carry no literal
    BGCompare {} -> []
    BGUnify {} -> []
    BGDiseq {} -> []
    BGIs {} -> []
    BGAggregate {} -> []
   where
    wrap mk g = case goalLit g of
      [] -> goalDeps neg g
      ls -> [(mk l, neg) | l <- ls]

  reachable :: [(Node, Node)]
  reachable = close (nubOrd [(a, b) | (a, b, _) <- depEdges])
   where
    step cur =
      nubOrd (cur <> [(a, c) | (a, b) <- cur, (b', c, _) <- depEdges, b == b'])
    close cur =
      let nxt = step cur
      in  if length nxt == length cur then cur else close nxt

  negCycles :: [Node]
  negCycles =
    nubOrd [a | (a, b, True) <- depEdges, b == a || (b, a) `elem` reachable]

  -- ------------------------------------------------------------------
  -- Section numbering
  -- ------------------------------------------------------------------
  clauseTexts :: Map Int Text
  clauseTexts = Map.fromList [(s.bsNumber, s.bsText) | s <- doc.bdRuleText.brSections]

  workspaceNumbers :: [Int]
  workspaceNumbers =
    [ n
    | ws <- doc.bdWorkspaces
    , BPath (st :| []) <- [ws.bwName]
    , bStepKind st == "sec"
    , Just n <- [readInt (bStepLabel st)]
    ]

  secNumbers :: [Int]
  secNumbers = sort (nub (Map.keys clauseTexts <> workspaceNumbers))

  flatRefs :: [BSectionRef]
  flatRefs = map bSec secNumbers

  -- ------------------------------------------------------------------
  -- Workspace comments (ruling P5-4)
  -- ------------------------------------------------------------------
  -- Placed by the workspace's ROOT step, not by its full path, so a span
  -- (`sec_5__span_pingu_section`) lands under the § of the section it carves
  -- out of. `root_section` goes to the ontology, which is where its blocks go.
  wsComments :: [(BSectionRef, Text)]
  wsComments = [(ws.bwName, c) | ws <- doc.bdWorkspaces, Just c <- [ws.bwComment]]

  rootComments :: [(BSectionRef, Text)]
  rootComments = [wc | wc@(BRoot, _) <- wsComments]

  secComments :: Int -> [(BSectionRef, Text)]
  secComments n =
    [ wc
    | wc@(BPath (st :| _), _) <- wsComments
    , bStepKind st == "sec"
    , readInt (bStepLabel st) == Just n
    ]

  unplacedComments :: [(BSectionRef, Text)]
  unplacedComments =
    [ wc
    | wc@(r, _) <- wsComments
    , r `notElem` map fst (rootComments <> concatMap secComments secNumbers)
    ]

  commentPara :: (BSectionRef, Text) -> Text
  commentPara (ws, c) =
    Text.intercalate "\n"
      ( ("-- <comment> on " <> renderSectionRef ws <> ":")
          : concatMap (wrapPrefixed "-- " "-- ") (Text.splitOn "\n" c) )

  -- ------------------------------------------------------------------
  -- Paragraphs
  -- ------------------------------------------------------------------
  headerPara =
    Text.intercalate "\n" $
      [ "-- Imported from Blawx by `l4 blawx --import` (BLAWX-EXPORT-SPEC R14, §10 P5)."
      , "--"
      ]
        <> ["--   source        " <> ctx.lcSource | not (Text.null ctx.lcSource)]
        <> [ "--   ruledoc       " <> quoted doc.bdName
           , "--   rows          "
               <> Text.textShow (length doc.bdWorkspaces)
               <> " blawx.workspace, "
               <> Text.textShow (length doc.bdTests)
               <> " blawx.blawxtest"
           ]
        <> concat [prefixLines "--   " "--                 " n | n <- ctx.lcNotes]
        <> [ "--"
           , "-- Blawx models a flat universe of atoms under unary predicates. Every"
           , "-- category and every boolean attribute is one such predicate, so this lift"
           , "-- declares ONE record for the universe, carrying a `MAYBE BOOLEAN` input"
           , "-- slot per predicate that is not derived (the s(CASP) fact channel) and one"
           , "-- BOOLEAN decision per predicate. The defeat layer is unfolded: one decision"
           , "-- per (section, literal) pair, named from the generator's own #pred wording."
           ]

  importsPara = "IMPORT prelude\nIMPORT `negation-as-failure`"

  -- CLEAN `rule_text` is CRLF-separated in the wild (bird's is), and a stray
  -- CR inside a backticked name is a lexer error, not a cosmetic blemish.
  -- Normalised here rather than in Parse, so the IR keeps the stored bytes and
  -- a re-emitted `.blawx` still reproduces them.
  titlePara = "§ " <> ident (noCR (Text.strip doc.bdRuleText.brTitle))

  -- ---- ontology -------------------------------------------------------
  ontologyParas :: L [Text]
  ontologyParas = do
    inputs <- traverse inputDecision inputDecls
    pure (["§§ `Ontology`"] <> map commentPara rootComments <> [declarePara] <> inputs)

  declarePara =
    Text.intercalate "\n" $
      ["-- @ref " <> d.dclRef | d <- decls]
        <> ["DECLARE Object", "    HAS"]
        <> concat
          [ [ "      @desc " <> desc
            , "      " <> padTo (fieldWidth + 3) (ident f) <> ty f
            ]
          | (f, desc) <- fieldDescs
          ]
   where
    ty f = if f == "name" then "IS A STRING" else "IS A MAYBE BOOLEAN"

  inputDecision :: Decl -> L Text
  inputDecision d = do
    let n = d.dclName
        arms =
          ["holds (x's " <> ident (n <> " fact") <> ")" | n `elem` channelNames]
            <> ["x's name EQUALS " <> quoted o | o <- membersOf n]
        refLine =
          [ "@ref " <> renderSectionRef ws <> " object_declaration — "
              <> bNameText od.bodName <> " is a " <> n
          | (ws, od) <- objects
          , bNameText od.bodCategory == n
          ]
    body <- armsBody n arms
    pure $
      Text.intercalate "\n"
        ( take 1 refLine
            <> [givenBoolean, "DECIDE " <> ident n <> " x" <> nlgSuffix (n, True)]
            <> body )

  armsBody :: Text -> [Text] -> L [Text]
  armsBody who = \case
    [] -> do
      _ <-
        refuse "empty-decision" who
          "the predicate has no arms: neither an input channel nor a rule concludes it"
      pure ["    IF FALSE"]
    a : as -> pure (("    IF " <> a) : map ("    OR " <>) as)

  givenBoolean = "GIVEN x IS AN Object\nGIVETH A BOOLEAN"

  -- ---- one numbered clause --------------------------------------------
  clausePara :: Int -> L [Text]
  clausePara n = do
    let s = bSec n
        heading =
          "§§ "
            <> ident
              ( labelOf s
                  <> maybe "" (\t -> " — " <> noCR (Text.replace "\n" " " t)) (Map.lookup n clauseTexts) )
        outward = [g | g <- defeatGroups, groupHome g == s, fst (fst g) /= s]
        inward = [g | g <- defeatGroups, groupHome g == s, fst (fst g) == s]
        mine = [r | (_, r) <- arules, r.brSection == s]
    outs <- traverse defeatPara outward
    apps <- if s `elem` appliesSections then appliesParas s else pure []
    rulePs <- concat <$> traverse (rulePara s) mine
    ins <- traverse defeatPara inward
    let cs = map commentPara (secComments n)
        filler
          | null outs && null apps && null rulePs && null ins =
              ["-- " <> renderSectionRef s <> " carries no blocks."]
          | otherwise = []
    pure ([heading] <> cs <> outs <> apps <> rulePs <> ins <> filler)

  rulePara :: BSectionRef -> BRule -> L [Text]
  rulePara s r = do
    let l = (bNameText r.brConclusion.bcPred, r.brConclusion.bcSign)
        who = renderSectionRef s
    unless (unaryVar r.brConclusion) $
      refuse_ "conclusion-shape" who
        ( "the conclusion `"
            <> renderGoal (BGCall r.brConclusion.bcSign r.brConclusion.bcPred r.brConclusion.bcArgs)
            <> "` is not a unary predicate applied to one object variable" )
    conds <- concat <$> traverse (ruleCondition who s r.brInapplicable) r.brConditions
    let accName = accordingName s l
        accRef =
          "@ref " <> labelOf s <> " — " <> renderSectionRef s
            <> " attributed_rule (defeasible " <> yesNo r.brDefeasible
            <> ", inapplicable " <> yesNo r.brInapplicable <> ")"
        accPara = case conds of
          [] -> Text.intercalate "\n" [accRef, givenBoolean, "DECIDE " <> ident accName <> " x IF TRUE"]
          [c] -> Text.intercalate "\n" [accRef, givenBoolean, "DECIDE " <> ident accName <> " x IF " <> c]
          c : cs ->
            Text.intercalate "\n"
              ( [accRef, givenBoolean, "DECIDE " <> ident accName <> " x", "    IF  " <> c]
                  <> map ("    AND " <>) cs )
        defeated = isDefeated s l
        holdsRef
          | not r.brDefeasible =
              ["@ref " <> labelOf s <> " — indefeasible: no `not blawx_defeated` conjunct"]
          | defeated =
              [ "@ref " <> labelOf s <> " — defeasible: `not blawx_defeated("
                  <> renderSectionRef s <> ", " <> scaspLit l <> ", x)`"
              ]
          | otherwise =
              [ "-- defeasible TRUE, but no overrules names " <> labelOf s <> " as defeated,"
              , "-- so the `not blawx_defeated(" <> renderSectionRef s <> ", " <> scaspLit l
                  <> ", x)` conjunct is vacuous."
              , "@ref " <> labelOf s <> " — " <> renderSectionRef s <> " attributed_rule, holds-layer"
              ]
        holdsBody
          | r.brDefeasible && defeated =
              [ "    IF      " <> ident accName <> " x"
              , "    AND NOT " <> ident (defeatedName s l) <> " x"
              ]
          | otherwise = ["    IF " <> ident accName <> " x"]
        holdsPara =
          Text.intercalate "\n"
            (holdsRef <> [givenBoolean, "DECIDE " <> ident (holdsName s l) <> " x"] <> holdsBody)
    pure [accPara, holdsPara]

  yesNo b = if b then "TRUE" else "FALSE"

  unaryVar c = case c.bcArgs of
    [BTVar _] -> True
    _ -> False

  -- `inapplicable` injects the guard immediately after every condition whose
  -- block image is literally `new_object_category`
  -- (scasp_generator.js:1188-1194) and after nothing else. The POSITION is
  -- load-bearing, not just the presence.
  ruleCondition :: Text -> BSectionRef -> Bool -> BGoal -> L [Text]
  ruleCondition who s inapplicable g = do
    t <- liftGoal who g
    pure $ case g of
      BGNewObjectCategory _ _ | inapplicable -> [t, ident (appliesName s) <> " x"]
      _ -> [t]

  defeatPara :: ((BSectionRef, Lit), [(Int, BSectionRef, BOverrule)]) -> L Text
  defeatPara ((s, l), ms) = do
    let arms = [ident (holdsName o.bovDefeating (overruleLit o.bovDefeatingStmt)) <> " x" | (_, _, o) <- ms]
        edge o =
          labelOf o.bovDefeating <> " (" <> scaspLit (overruleLit o.bovDefeatingStmt)
            <> ") defeats " <> labelOf o.bovDefeated
            <> " (" <> scaspLit (overruleLit o.bovDefeatedStmt) <> ")"
        hdr = case ms of
          [(_, ws, o)] ->
            ["@ref " <> labelOf ws <> " — " <> renderSectionRef ws <> " overrules: " <> edge o]
          _ ->
            [ "-- overrules #" <> Text.textShow i <> ": " <> renderSectionRef ws <> ", " <> edge o
            | (i, ws, o) <- ms
            ]
              <> [ "@ref " <> labelOf s <> " — defeated by "
                     <> Text.intercalate " and by " [labelOf o.bovDefeating | (_, _, o) <- ms]
                 ]
    body <- armsBody (defeatedName s l) arms
    pure $
      Text.intercalate "\n"
        (hdr <> [givenBoolean, "DECIDE " <> ident (defeatedName s l) <> " x"] <> body)

  -- ---- the applicability layer -----------------------------------------
  appliesParas :: BSectionRef -> L [Text]
  appliesParas s = do
    let outs = carveOuts s
        negRef = case carveWorkspaces s of
          w : _ ->
            -- The artifact has to carry its own disclosure. A reader who takes
            -- this .l4 to the shipped Blawx and runs the same query gets a
            -- DIFFERENT answer, and nothing else in the file says so.
            [ "-- UPSTREAM: the shipped Blawx generator emits no consumer for a `holds` block"
            , "-- naming blawx_applies (ldap.py declares only #pred NLG for holds/4, and"
            , "-- reasoner.py has no occurrence of `holds` at all), so real Blawx derives"
            , "-- nothing from the carve-out below and answers as if " <> labelOf s <> " applied."
            , "-- The lift implements the INTENDED semantics — the carve-out is effective —"
            , "-- and the s(CASP) leg of the cross-engine check runs against a bridged"
            , "-- program: see etc/blawx-tier1-harness.py IMPORT_BRIDGE, spec §10 P5 finding 1."
            , "@ref " <> labelOf w <> " — " <> renderSectionRef w <> " holds( -blawx_applies("
                <> labelOf s <> ", " <> Text.intercalate ", " outs <> ") )"
            ]
          [] ->
            [ "@ref " <> labelOf s <> " — the input channel for -blawx_applies("
                <> renderSectionRef s <> ", x)"
            ]
        negBody
          | null outs = ["    MEANS x's " <> ident (exclusionField s)]
          | otherwise =
              [ "    MEANS IF   "
                  <> Text.intercalate " OR " ["x's name EQUALS " <> quoted o | o <- outs]
              , "          THEN JUST TRUE"
              , "          ELSE x's " <> ident (exclusionField s)
              ]
        negPara =
          Text.intercalate "\n" $
            negRef
              <> [ "GIVEN x IS AN Object"
                 , "GIVETH A MAYBE BOOLEAN"
                 , ident (negAppliesName s) <> " x"
                 ]
              <> negBody
    posPara <- case appliesRule s of
      Nothing ->
        refuse "applies-undefined" (renderSectionRef s)
          ( "a rule is `subject to applicability` for " <> labelOf s
              <> " but no unattributed_rule defines blawx_applies for it, so the "
              <> "predicate has no clauses and the rule could never fire" )
      Just (ws, r) -> do
        conds <- traverse (liftGoal (renderSectionRef ws)) r.burConditions
        body <- armsBody (appliesName s) conds
        pure $
          Text.intercalate "\n" $
            [ "-- the closed-world applicability default"
            , "-- `blawx_applies(S,x) :- not -blawx_applies(S,x)`"
            , "@ref " <> labelOf s <> " — " <> renderSectionRef ws <> " unattributed_rule"
            , givenBoolean
            , "DECIDE " <> ident (appliesName s) <> " x"
            ]
              <> body
    pure [negPara, posPara]

  -- ---- base predicates -------------------------------------------------
  basePredParas :: L [Text]
  basePredParas
    | null concludedLits = pure []
    | otherwise = do
        ps <- traverse basePred concludedLits
        pure
          ( [ "§§ `The base predicates`"
            , Text.intercalate "\n"
                [ "-- `p(x) :- holds(sec_N, p, x).` for every section concluding p, OR-joined,"
                , "-- plus the scenario fact channel (a bare `p(a).` is another clause of p)."
                ]
            ]
              <> ps )

  basePred :: Lit -> L Text
  basePred l@(n, sign) = do
    let arms =
          ["holds (x's " <> ident (n <> " fact") <> ")" | sign, n `elem` channelNames]
            <> ["x's name EQUALS " <> quoted o | sign, o <- membersOf n]
            <> [ident (holdsName s l) <> " x" | s <- sectionsConcluding l]
    body <- armsBody (litName l) arms
    pure $
      Text.intercalate "\n"
        ([givenBoolean, "DECIDE " <> ident (litName l) <> " x" <> nlgSuffix l] <> body)

  -- ---- objects ---------------------------------------------------------
  objectParas :: [Text]
  objectParas
    | null universe = []
    | otherwise =
        ["§§ `Objects`"]
          <> [ Text.intercalate "\n"
                 ([refLine, ident n <> " MEANS", "    Object WITH"] <> recordFields 8 n [])
             | (n, from) <- universe
             , let refLine = case from of
                     UnivDeclared ws d ->
                       "@ref " <> renderSectionRef ws <> " object_declaration " <> bNameText d.bodName
                     UnivFact ws ->
                       "@ref " <> renderSectionRef ws
                         <> " — introduced by a ground fact, not an object_declaration"
             ]
          <> [ ident "all objects" <> " MEANS LIST " <> Text.intercalate ", " (map ident objectNames)
             , Text.intercalate "\n"
                 [ "GIVEN x IS AN Object"
                 , "GIVETH A STRING"
                 , "`the name of` x MEANS x's name"
                 ]
             ]

  -- One `IS` line per field at the given indent: `JUST TRUE` for every
  -- predicate the scenario asserts of this object, NOTHING elsewhere.
  recordFields :: Int -> Text -> [Text] -> [Text]
  recordFields ind objName trues =
    [pad <> padTo (fieldWidth + 1) (ident f) <> "IS " <> val f | f <- fieldNames]
   where
    pad = Text.replicate ind " "
    val "name" = quoted objName
    val f = if Text.dropEnd 5 f `elem` trues then "JUST TRUE" else "NOTHING"

  -- ---- tests -----------------------------------------------------------
  testParas :: L [Text]
  testParas
    | null doc.bdTests = pure []
    | otherwise = do
        ts <- traverse testPara doc.bdTests
        pure (["§§ `Tests`"] <> ts)

  testPara :: BTest -> L Text
  testPara t = do
    let scenario = [(bNameText p, bNameText o) | st <- t.btStacks, BFact True p [BTAtom o] <- st]
        queries = [gs | st <- t.btStacks, BQuery gs <- st]
    -- A test row whose canvas holds no `query` block asks nothing. That is a
    -- half-finished test in the editor, not a construct with no L4 image, so
    -- it warns and contributes no #EVAL rather than refusing the document.
    -- (Witness: `wills_tutorial`, whose only rows are empty.)
    directive <- case queries of
      [] -> do
        warn "test-without-query" t.btName
          "the test carries no `query` block, so it asks nothing and emits no #EVAL"
        pure []
      [gs] -> do
        body <- testExpr t.btName scenario gs
        pure ["#EVAL " <> body]
      _ -> do
        body <- refuse "many-queries" t.btName "the test carries more than one `query` block"
        pure ["#EVAL " <> body]
    let scaspFacts = ["`" <> p <> "(" <> o <> ").`" | (p, o) <- scenario]
        queryText = case queries of
          gs : _ -> ["`?- " <> Text.intercalate ", " (map renderGoal gs) <> ".`"]
          [] -> ["(no query block)"]
        provenance =
          "-- blawxtest " <> t.btName <> " — " <> Text.unwords (scaspFacts <> queryText)
        commentLines = case t.btComment of
          Nothing -> []
          Just c -> concatMap (wrapPrefixed "-- " "-- ") (Text.splitOn "\n" c)
    pure (Text.intercalate "\n" ([provenance] <> commentLines <> directive))

  -- The query, as an L4 expression. A free variable is a filter over the
  -- declared object universe — exact because Blawx has no open domain: an
  -- atom must be introduced by an object_declaration or by a fact.
  testExpr :: Text -> [(Text, Text)] -> [BGoal] -> L Text
  testExpr who scenario = \case
    [] -> refuse "empty-query" who "the query block holds no goals"
    [g] -> one g
    gs -> Text.intercalate " AND " <$> traverse one gs
   where
    one = \case
      BGCall True p [BTVar _] -> existential p
      BGNewObjectCategory p (BTVar _) -> existential p
      BGCall True p [BTAtom o] -> pure (ident (bNameText p) <> " " <> obj (bNameText o))
      BGNewObjectCategory p (BTAtom o) -> pure (ident (bNameText p) <> " " <> obj (bNameText o))
      BGCall False p [BTAtom o] ->
        pure (ident (phrase (bNameText p, False)) <> " " <> obj (bNameText o))
      BGNaf p [BTAtom o] ->
        pure ("NOT (" <> ident (bNameText p) <> " " <> obj (bNameText o) <> ")")
      BGNegated BNegDefault g -> do
        t <- one g
        pure ("NOT (" <> t <> ")")
      g -> refuse "query-shape" who ("the goal `" <> renderGoal g <> "` has no #EVAL image")
    existential p
      | not (null scenario) =
          refuse "scenario-with-free-variable" who
            ( "the query binds a free variable while the test also asserts scenario "
                <> "facts; the filter-over-declared-objects rendering would not see them" )
      | null universe =
          refuse "unbound-query" who
            "the query binds a free variable but the document declares no objects to range over"
      | otherwise =
          pure ("map `the name of` (filter " <> ident (bNameText p) <> " `all objects`)")
    obj o
      | null [() | (_, o') <- scenario, o' == o] = ident o
      | otherwise =
          "(Object WITH\n"
            <> Text.intercalate "\n" (recordFields 17 o [p | (p, o') <- scenario, o' == o])
            <> ")"

  -- ------------------------------------------------------------------
  -- Goals
  -- ------------------------------------------------------------------
  liftGoal :: Text -> BGoal -> L Text
  liftGoal who = go
   where
    go = \case
      BGCall True p [a] -> app (bNameText p) a
      BGCall False p [a] -> app (phrase (bNameText p, False)) a
      BGNewObjectCategory p a -> app (bNameText p) a
      BGApplies s a -> app (appliesName s) a
      -- The one place negation-as-failure earns its keep: the negated
      -- predicate is an INPUT, so "unknown" must behave as "absent", which a
      -- plain NOT over a total BOOLEAN cannot say.
      BGNegated BNegDefault (BGNegated BNegClassical (BGApplies s a)) -> do
        t <- arg a
        pure ("naf (" <> ident (negAppliesName s) <> " " <> t <> ")")
      BGNaf p [a] -> do
        t <- app (bNameText p) a
        pure ("NOT (" <> t <> ")")
      BGNegated BNegClassical (BGCall True p [a]) -> app (phrase (bNameText p, False)) a
      BGNegated BNegDefault g -> do
        t <- go g
        pure ("NOT (" <> t <> ")")
      g -> refuse "goal-shape" who ("the condition `" <> renderGoal g <> "` has no L4 image this phase")
    app n a = do
      t <- arg a
      pure (ident n <> " " <> t)
    arg = \case
      BTVar _ -> pure "x"
      BTAtom o
        | bNameText o `elem` objectNames -> pure (ident (bNameText o))
        | otherwise ->
            refuse "unknown-object" who
              ("the atom `" <> bNameText o <> "` is used as an object but never declared")
      t -> refuse "term-shape" who ("the term `" <> renderTerm t <> "` is not an object")

-- ---------------------------------------------------------------------------
-- Text helpers
-- ---------------------------------------------------------------------------

-- | Backtick-quote unless the text is already a plain L4 identifier.
ident :: Text -> Text
ident t
  | plain = t
  | otherwise = "`" <> t <> "`"
 where
  plain = case Text.uncons t of
    Just (c, cs) ->
      (isAsciiLower c || isAsciiUpper c)
        && Text.all wordChar cs
        && t `notElem` reserved
    Nothing -> False
  wordChar c = isAsciiLower c || isAsciiUpper c || isDigit c || c == '_'
  reserved :: [Text]
  reserved =
    [ "IF", "THEN", "ELSE", "AND", "OR", "NOT", "MEANS", "DECIDE", "DECLARE"
    , "GIVEN", "GIVETH", "HAS", "IS", "A", "AN", "THE", "OF", "WITH", "LIST"
    , "TRUE", "FALSE", "JUST", "NOTHING", "MAYBE", "BOOLEAN", "STRING"
    , "NUMBER", "WHERE", "YIELD", "EQUALS", "IMPORT", "ASSUME", "CONSIDER"
    , "WHEN", "OTHERWISE", "TYPE", "ONE", "FROM", "TO", "AT", "BY", "FOR"
    ]

quoted :: Text -> Text
quoted t = "\"" <> t <> "\""

-- | Drop carriage returns and collapse the whitespace they leave behind. A
-- name is backtick-delimited in L4, and a CR inside one is a lexer error.
noCR :: Text -> Text
noCR = Text.strip . Text.unwords . Text.words . Text.filter (/= '\r')

padTo :: Int -> Text -> Text
padTo n t = t <> Text.replicate (max 0 (n - Text.length t)) " "

readInt :: Text -> Maybe Int
readInt t
  | Text.null t || not (Text.all isDigit t) = Nothing
  | otherwise = Just (Text.foldl' (\ !a c -> a * 10 + (fromEnum c - fromEnum '0')) 0 t)

nubOn :: Eq b => (a -> b) -> [a] -> [a]
nubOn f = go []
 where
  go _ [] = []
  go seen (x : xs)
    | f x `elem` seen = go seen xs
    | otherwise = x : go (f x : seen) xs

-- | Prefix a possibly-multi-line note verbatim: the caller has already laid
-- it out in columns, and re-wrapping would collapse the alignment.
prefixLines :: Text -> Text -> Text -> [Text]
prefixLines first' cont body = case Text.splitOn "\n" body of
  [] -> []
  l : ls -> (first' <> l) : map (cont <>) ls

-- | Greedy wrap at 78 columns, with a first-line prefix and a continuation
-- prefix. A word longer than the budget goes on its own line rather than
-- being split.
--
-- The empty body is the case that matters: a blank line inside a Blawx
-- @\<comment\>@ (r34's @MaterialInterference@ has one) is a paragraph break,
-- and the naive @first' \<\> \"\"@ writes @\"-- \"@ — a line with trailing
-- whitespace, which nothing in this repo strips out of a @.l4@. 'Text.stripEnd'
-- makes it a bare @--@, which is what \"newlines intact\" (P5-4) has to mean.
wrapPrefixed :: Text -> Text -> Text -> [Text]
wrapPrefixed first' cont body = case go (Text.words body) of
  [] -> [Text.stripEnd (first' <> Text.strip body)]
  l : ls -> (first' <> l) : map (cont <>) ls
 where
  budget = max 20 (78 - Text.length cont)
  go [] = []
  go (w : ws) = fill w ws
  fill acc [] = [acc]
  fill acc (w : ws)
    | Text.length acc + 1 + Text.length w <= budget = fill (acc <> " " <> w) ws
    | otherwise = acc : fill w ws
