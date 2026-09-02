-- | The import direction's back end: a parsed 'BlawxDoc' to __L4 source text__
-- (BLAWX-EXPORT-SPEC §8.14 R14, §10 P5; design in @p5-design\/lift-plan.md@).
--
-- __What this module is for.__ "L4.Blawx.Parse" answers /what blocks are
-- there/; this answers /what do they mean/. The split is where the two kinds
-- of refusal live: a block type with no IR landing zone (the date and event
-- layers) is refused there, by name; a program whose /semantics/ has no L4
-- image — a constraint whose expected answer is unsatisfiability, an
-- arithmetic comparison, a query over a universe with no objects in it — is
-- refused here.
--
-- __The one idea.__ Blawx does not evaluate rules directly. Every
-- @attributed_rule@ in section @S@ concluding literal @L@ compiles to three
-- s(CASP) clauses, and the defeat relation is a fourth predicate:
--
-- > according_to(S, L, X…) :- <conditions> [, blawx_applies(S,X)  if inapplicable].
-- > holds(S, L, X…)        :- according_to(S, L, X…) [, not blawx_defeated(S,L,X…)].
-- > L(X…)                  :- holds(S, L, X…).
-- > blawx_defeated(E,M,X…) :- holds(D, M', X…).          -- one per `overrules`
-- > blawx_applies(S, X)    :- not -blawx_applies(S, X). -- the `unattributed_rule` default
--
-- (@X…@ is one argument per place of @L@: a category is @c(X)@, a
-- category-valued attribute @a(X,Y)@, a relationship @r(X,Y,Z)@.
-- @blawx_applies@ is always about ONE object.)
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
-- __The universe is flat, and the predicates over it are n-ary.__ Blawx
-- categories, attributes and relationships are all predicates over __one__
-- universe of atoms (@penguin@, @bird@, @thing@, @rock@, @testgame@ are all
-- just atoms), so there is __one__ record type per document, never one per
-- category: a /derived/ category is not a type. What varies is the arity — a
-- category is @c\/1@, a category-valued attribute is @a\/2@, a relationship is
-- @r\/n@ — and __arity is part of a predicate's identity__, because Blawx
-- overloads on it: @rps@ declares both the category @player\/1@ and the
-- attribute @player\/2@ and s(CASP) keeps them apart. 'Lit' therefore carries
-- the arity, and 'predIdent' spells the higher arities Prolog-style
-- (@\`player\/2\`@) so one L4 name never has to mean two predicates.
--
-- __Existential body variables become @any@ over the world (W5).__ A rule
-- whose body mentions a variable its head does not — @rps@ s.4 quantifies over
-- the /other/ player and over both thrown signs — has no direct L4 image: an
-- L4 decision's parameters are all universally quantified. It is split in two:
-- a __witness__ decision that takes the extra variables as ordinary
-- parameters, and the rule's own decision, whose body is @any (GIVEN v YIELD
-- \<witness\> …) w@ once per witness. That is exact because Blawx has no open
-- domain — an atom exists because an @object_declaration@ introduced it or
-- because a fact mentioned it — so quantifying over the enumerated universe
-- enumerates exactly what s(CASP) enumerates.
--
-- __The universe is a parameter (@w@), not a constant, as soon as a test can
-- extend it.__ A Blawx test loads its own @object_declaration@s and facts
-- alongside the rules, so each test runs against its /own/ universe. Baking
-- every test's objects into one module-level @all objects@ would make each
-- test see the others' — @rps@'s @who_wins@ would find @bobjane@'s game and
-- answer where real Blawx answers nothing. So when any test declares objects,
-- or any rule quantifies, or any predicate has arity above one, every derived
-- decision takes a leading @w IS A LIST OF Object@ and each test passes its
-- own world. A document that needs none of that (bird) is emitted exactly as
-- before — the flag is off and not one byte moves.
--
-- __Every declared predicate gets an input channel.__ Each category,
-- attribute, relationship and abducible gets one field on @Object@, carried by
-- its __first__ argument: @MAYBE BOOLEAN@ at arity 1 (@\<atom\> fact@), and a
-- @LIST OF (LIST OF STRING)@ of the remaining arguments' names above it, so
-- @player(testgame,bob)@ is @\`player\/2 fact\` IS LIST (LIST \"bob\")@ on
-- @testgame@. @holds@ from @negation-as-failure.l4@ is @fromMaybe FALSE@,
-- which is exactly s(CASP)'s \"unproven fails\", so an absent fact costs
-- nothing; the list channel's empty case is @EMPTY@, which costs nothing for
-- the same reason.
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
-- asserting a fact about an /undeclared/ predicate is not lifted rather than
-- dropped.)
--
-- __@logical_negation@ is not @NOT@.__ @-p@ is a /different predicate/ from
-- @p@, not its negation: both can be false at once. Rendering it as L4's @NOT@
-- agrees on bird's four tests and diverges on a fifth, so a negative literal
-- becomes its own named decision, and only @default_negation@ becomes @NOT@ /
-- @naf@. @naf@ (over a @MAYBE BOOLEAN@) is used exactly where the negated
-- predicate is an INPUT, because only there does \"unknown\" have to behave as
-- \"absent\"; over a total @BOOLEAN@ it would be a no-op.
--
-- __Disequality is disequality of atoms.__ @blawx_diseq(X,Y)@ becomes
-- @NOT (x1's name EQUALS x2's name)@ and @X = Y@ becomes the same comparison
-- without the @NOT@ — never a record comparison. That direction is forced by
-- the same measurement that produced W1 on the export side: Blawx compares
-- objects by atom and L4 compares records by value, so the atom (the @name@
-- field) is the only thing the two agree on.
--
-- __A test that cannot be lifted is dropped, by name, with the reason written
-- into the artifact.__ A rule that cannot be lifted refuses the document,
-- because emitting the rest would be emitting a program that says something
-- the Blawx document does not. A __test__ is an oracle rather than a rule, and
-- dropping it can only lose a check, never make an emitted rule wrong — so a
-- test canvas carrying an @assume@ (abducibles: @rps@'s @hypothetical@), a
-- negative scenario fact, a nested rule, a fact about an undeclared predicate
-- or a second @query@ warns, emits @-- NOT LIFTED: \<code\> …@ where its
-- @#EVAL@ would have gone, and contributes no directive. That is strictly
-- stronger than the alternative the 2026-08-19 review pass replaced (silently
-- ignoring the block while still emitting the @#EVAL@): here there is no
-- @#EVAL@ to answer the wrong question.
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

-- | A predicate as the lift names it: an atom, an __arity__ and a classical
-- sign. @MkLit \"flies\" 1 False@ is @-flies@, a different predicate from
-- @MkLit \"flies\" 1 True@, and it gets its own decision; @MkLit \"player\" 2
-- True@ is a different predicate again from @MkLit \"player\" 1 True@, because
-- Blawx overloads a name across arities and s(CASP) keeps @player\/1@ and
-- @player\/2@ apart. Dropping the arity here is how one L4 name would come to
-- mean two things.
data Lit = MkLit
  { litPred  :: !Text
  , litArity :: !Int
  , litSign  :: !Bool
  }
  deriving stock (Eq, Ord, Show)

-- | The literal a signed call names.
litOf :: Bool -> BName -> [a] -> Lit
litOf s p as = MkLit {litPred = bNameText p, litArity = length as, litSign = s}

-- | The NLG a declaration carries, in the shape its block stores it. Kept
-- unfused (prefix\/infix\/postfix as separate slots) because the emitter's
-- byte-exactness and the R12 fixpoint depend on the split, and because the
-- sentence a lift wants differs by arity and by 'BNlgOrder'.
data DeclNlg
  = NlgUnary !Text !Text
    -- ^ @new_category_declaration@ and boolean @new_attribute_declaration@:
    -- prefix and postfix around the single argument.
  | NlgBinary !BNlgOrder !Text !Text !Text
    -- ^ category-valued @new_attribute_declaration@: order, prefix, infix,
    -- postfix. @ov@ reads @prefix X infix Y postfix@, @vo@ swaps the two.
  | NlgNary ![Text] !Text
    -- ^ @relationship_declaration@: one prefix per argument, then a postfix.

-- | The sentence a declaration's NLG makes of the given argument renderings,
-- or 'Nothing' when every slot is blank — which is what
-- @blawx_category_nlg(c,\"\",\"\")@ means and why a bird category with no
-- postfix gets no @\@nlg@.
nlgSentence :: DeclNlg -> [Text] -> Maybe Text
nlgSentence d args = case d of
  NlgUnary pre post
    | blank post -> Nothing
    | otherwise -> Just (ws [Text.strip pre, at 0, Text.strip post])
  NlgBinary order pre inf post
    | all blank [pre, inf, post] -> Nothing
    | otherwise -> Just $ case order of
        BOrderOV -> ws [Text.strip pre, at 0, Text.strip inf, at 1, Text.strip post]
        BOrderVO -> ws [Text.strip pre, at 1, Text.strip inf, at 0, Text.strip post]
  NlgNary pres post
    | all blank (post : pres) -> Nothing
    | otherwise ->
        Just (ws (concat [[Text.strip p, a] | (p, a) <- zip (pres <> repeat "") args] <> [Text.strip post]))
 where
  blank = Text.null . Text.strip
  ws = Text.unwords . filter (not . Text.null)
  at i = case drop i args of
    a : _ -> a
    [] -> "?"

-- | A declaration that reached the ontology.
--
-- There is deliberately no @dclKind@ field. It existed to drive @hasChannel@'s
-- category\/attribute split, that split turned out to be unsound (see the
-- module header), and a field nobody reads is a claim nobody re-checks — which
-- @-Wall@ cannot tell you about under @NoFieldSelectors@. The three source
-- lists in 'decls' still carry the distinction where it is actually used.
-- 'dclArity' by contrast /is/ read everywhere, because it decides the
-- predicate's identity, its channel's type and its parameter list.
data Decl = MkDecl
  { dclName    :: !Text
  , dclArity   :: !Int
  , dclNlg     :: !DeclNlg
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
  NLit l -> NLit (flipLit l)
  NAcc r l -> NAcc r (flipLit l)
  NHolds r l -> NHolds r (flipLit l)
  NDefeated r l -> NDefeated r (flipLit l)
  NApplies r -> NNegApplies r
  NNegApplies r -> NApplies r

flipLit :: Lit -> Lit
flipLit l = l {litSign = not l.litSign}

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
scaspLit l = (if l.litSign then "" else "-") <> l.litPred

-- | The block type, for a diagnostic that has to name what it refused.
blockLabel :: BBlock -> Text
blockLabel = \case
  BDeclareCategory {} -> "a `new_category_declaration`"
  BDeclareAttribute {} -> "a `new_attribute_declaration`"
  BDeclareRelationship {} -> "a `relationship_declaration`"
  BAttributedRule {} -> "an `attributed_rule`"
  BFact True _ _ -> "a fact whose arguments are not all object atoms"
  BFact False _ _ -> "a `logical_negation` fact (a NEGATIVE scenario fact)"
  BConstraint {} -> "a `constraint`"
  BAbducible {} -> "an `assume` (an abducible: hypothetical reasoning)"
  BQuery {} -> "a `query`"
  BDeclareObject {} -> "an `object_declaration`"
  BOverrules {} -> "an `overrules`"
  BUnattributedRule {} -> "an `unattributed_rule`"
  BAssertGoal g -> "a fact-position `" <> renderGoal g <> "`"

-- | The parameter names an n-ary predicate's decision uses. Arity one keeps
-- the bare @x@ the flat-universe phase emitted, so a document with no
-- higher-arity predicate (bird) is byte-identical through this change.
argVars :: Int -> [Text]
argVars 1 = ["x"]
argVars n = ["x" <> Text.textShow i | i <- [1 .. n]]

-- | The extra parameter that carries the object universe. Chosen not to
-- collide with 'argVars'.
worldVar :: Text
worldVar = "w"

renderDoc :: LiftContext -> BlawxDoc -> L Text
renderDoc ctx doc = do
  -- ---- constructs with no L4 image ------------------------------------
  for_ blocks \(ws, b) -> case b of
    BDeclareRelationship d ->
      unless (all isCategoryType d.brTypes) $
        refuse_ "relationship" (renderSectionRef ws)
          ( "relationship_declaration " <> bNameText d.brName <> "/"
              <> Text.textShow (length d.brTypes)
              <> " relates " <> Text.intercalate ", " (map renderValueType d.brTypes)
              <> "; only a relationship all of whose argument types are declared "
              <> "categories lifts, because the lift models one universe of objects "
              <> "and a NUMBER or a date is not an object" )
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
    unless (d.baType == BVBoolean || isCategoryType d.baType) $
      refuse_ "attribute-type" (renderSectionRef ws)
        ( "attribute " <> bNameText d.baName <> " has value type "
            <> renderValueType d.baType
            <> "; a BOOLEAN attribute lifts as a unary predicate over the object "
            <> "universe and a category-valued one as a binary predicate, but a "
            <> "value that is not an object has no image in this phase "
            <> "(numbers and comparisons: BLAWX-EXPORT-SPEC §11 W5a)" )

  for_ facts \(ws, (_, p, as)) ->
    unless (all isAtomArg as && not (null as)) $
      refuse_ "fact-shape" (renderSectionRef ws)
        ( "the fact `" <> renderGoal (BGCall True p as)
            <> "` is not a predicate applied to object atoms" )

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

  titleRest <- titleRestParas
  ontology <- ontologyParas
  clauses <- concat <$> traverse clausePara secNumbers
  basePreds <- basePredParas
  tests <- testParas

  pure $
    Text.intercalate "\n\n"
      ( [headerPara, importsPara, titlePara]
          <> titleRest
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
  relDecls = [(ws, d) | (ws, BDeclareRelationship d) <- blocks]
  objDecls = [(ws, d) | (ws, BDeclareObject d) <- blocks]
  arules = [(ws, r) | (ws, BAttributedRule r) <- blocks]
  overrs = zip [1 :: Int ..] [(ws, o) | (ws, BOverrules o) <- blocks]
  urules = [(ws, r) | (ws, BUnattributedRule r) <- blocks]
  asserts = [(ws, g) | (ws, BAssertGoal g) <- blocks]
  facts = [(ws, (s, p, as)) | (ws, BFact s p as) <- blocks]

  emptyWorkspaces = [ws.bwName | ws <- doc.bdWorkspaces, all null ws.bwStacks]

  isAtomArg = \case
    BTAtom _ -> True
    _ -> False

  atomName = \case
    BTAtom o -> bNameText o
    t -> renderTerm t

  isCategoryType = \case
    BVCategory _ -> True
    _ -> False

  -- ------------------------------------------------------------------
  -- Declarations
  -- ------------------------------------------------------------------
  decls :: [Decl]
  decls = catList <> attrList <> relList <> abducList
   where
    catList =
      [ MkDecl
          { dclName = bNameText d.bcName
          , dclArity = 1
          , dclNlg = NlgUnary d.bcPrefix d.bcPostfix
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
          , dclArity = if d.baType == BVBoolean then 1 else 2
          , dclNlg =
              if d.baType == BVBoolean
                then NlgUnary d.baPrefix d.baPostfix
                else NlgBinary d.baOrder d.baPrefix d.baInfix d.baPostfix
          , dclRef =
              renderSectionRef ws <> " new_attribute_declaration "
                <> bNameText d.baCategory <> "." <> bNameText d.baName
                <> " : " <> renderValueType d.baType
          }
      | (ws, d) <- attrDecls
      ]
    relList =
      [ MkDecl
          { dclName = bNameText d.brName
          , dclArity = length d.brTypes
          , dclNlg = NlgNary d.brPrefixes d.brPostfix
          , dclRef =
              renderSectionRef ws <> " relationship_declaration "
                <> bNameText d.brName <> "(" 
                <> Text.intercalate ", " (map renderValueType d.brTypes) <> ")"
          }
      | (ws, d) <- relDecls
      ]
    declaredNames = [(d.dclName, d.dclArity) | d <- catList <> attrList <> relList]
    abducList =
      [ MkDecl
          { dclName = bNameText p
          , dclArity = length as
          , dclNlg = NlgUnary "" ""
          , dclRef = renderSectionRef ws <> " assume " <> bNameText p
          }
      | (ws, (p, as)) <- nubOn (bNameText . fst . snd) abducsWithArity
      , (bNameText p, length as) `notElem` declaredNames
      ]
    abducsWithArity = [(ws, (p, as)) | (ws, BAbducible p as) <- blocks]

  declNameWidth = maximum (1 : [Text.length (bNameText d.bcName) | (_, d) <- catDecls])

  declOf :: Text -> Int -> Maybe Decl
  declOf n a = find (\d -> d.dclName == n && d.dclArity == a) decls

  -- __Arity is part of the name.__ Blawx overloads: `rps` declares the
  -- category `player/1` and the attribute `player/2`, and s(CASP) tells them
  -- apart by arity. L4 cannot, so the LOWEST arity keeps the bare name and
  -- every other arity is spelled Prolog-style. The arities are drawn from the
  -- declarations AND from the ground facts and rule conclusions, because a
  -- predicate can be used without being declared.
  predArities :: Text -> [Int]
  predArities n =
    sort (nub ([d.dclArity | d <- decls, d.dclName == n]
                 <> [length as | (_, (_, p, as)) <- facts, bNameText p == n]
                 <> [l.litArity | (l, _) <- concluding, l.litPred == n]))

  predIdent :: Text -> Int -> Text
  predIdent n a = case predArities n of
    a0 : _ : _ | a /= a0 -> n <> "/" <> Text.textShow a
    _ -> n

  fieldOf :: Decl -> Text
  fieldOf d = predIdent d.dclName d.dclArity <> " fact"

  -- ------------------------------------------------------------------
  -- Rules and literals
  -- ------------------------------------------------------------------
  concluding :: [(Lit, (BSectionRef, BRule))]
  concluding =
    [ (litOf r.brConclusion.bcSign r.brConclusion.bcPred r.brConclusion.bcArgs, (r.brSection, r))
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
  inputDecls = [d | d <- decls, MkLit d.dclName d.dclArity True `notElem` concludedLits]

  -- ------------------------------------------------------------------
  -- The world parameter
  -- ------------------------------------------------------------------
  -- A decision in the DERIVED layer (according_to / holds / blawx_defeated /
  -- blawx_applies / a base predicate some rule concludes) takes the object
  -- universe as a leading parameter as soon as anything in the document can
  -- make the universe depend on which test is running, or make a rule
  -- quantify over it. The input decisions never do: their whole body is a
  -- field read and a name comparison.
  needsWorld :: Bool
  needsWorld =
    any (\d -> d.dclArity > 1) decls
      || any (\(_, r) -> not (null (ruleBodyVars r))) arules
      || or [True | t <- doc.bdTests, st <- t.btStacks, BDeclareObject _ <- st]

  litTakesWorld :: Lit -> Bool
  litTakesWorld l = needsWorld && l `elem` concludedLits

  -- | @GIVEN@ block for a decision with the given extra parameters.
  givenBooleanFor :: Bool -> [Text] -> Text
  givenBooleanFor world vs =
    "GIVEN " <> Text.intercalate "\n      " ps <> "\nGIVETH A BOOLEAN"
   where
    names = [worldVar | world] <> vs
    wid = maximum (1 : map Text.length names)
    ps =
      [ padTo wid n <> " " <> (if world && n == worldVar then "IS A LIST OF Object" else "IS AN Object")
      | n <- names
      ]

  headTerms :: Bool -> [Text] -> Text
  headTerms world vs = Text.unwords ([worldVar | world] <> vs)

  callIdent :: Text -> Bool -> [Text] -> Text
  callIdent nm world ts = ident nm <> " " <> headTerms world ts

  -- ------------------------------------------------------------------
  -- Literal phrasing (the generator's own #pred sentences)
  -- ------------------------------------------------------------------
  phraseFor :: [Text] -> Lit -> Text
  phraseFor args l
    | l.litSign = sentence
    | otherwise = "it is not the case that " <> sentence
   where
    sentence = case declOf l.litPred l.litArity >>= \d -> nlgSentence d.dclNlg args of
      Just s -> s
      Nothing -> Text.unwords (l.litPred : args)

  phrase :: Lit -> Text
  phrase l = phraseFor (argVars l.litArity) l

  hasNlg :: Lit -> Bool
  hasNlg l = case declOf l.litPred l.litArity of
    Just d -> isJust (nlgSentence d.dclNlg (argVars l.litArity))
    Nothing -> False

  -- | The L4 name of a base predicate's decision. A positive literal is the
  -- (arity-disambiguated) atom; a negative one is its English sentence,
  -- because @-p@ has no atom of its own.
  litIdent :: Lit -> Text
  litIdent l
    | l.litSign = predIdent l.litPred l.litArity
    | otherwise = phrase l

  nlgSuffix :: Lit -> Text
  nlgSuffix l
    | not (hasNlg l) = ""
    | otherwise = " @nlg " <> phraseFor [pct v | v <- argVars l.litArity] l
   where
    pct v = "%" <> v <> "%"

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
  overruleLit c = litOf c.bcSign c.bcPred c.bcArgs

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
  -- `tweety` an ordinary atom). 'groundTuples' already counts both; drawing
  -- 'objectNames' from the declarations alone made the two halves of this
  -- lift disagree about who exists — `penguin tweety` would come back TRUE
  -- while `filter penguin \`all objects\`` could not see it, so an
  -- existential #EVAL answered over a smaller universe than s(CASP) enumerates.
  --
  -- These are the objects the WORKSPACES introduce. A test's own
  -- `object_declaration`s are test-local and land in that test's world.
  universe :: [(Text, UnivFrom)]
  universe =
    nubOn fst $
      [(bNameText d.bodName, UnivDeclared ws d) | (ws, d) <- objects]
        <> [ (bNameText o, UnivFact ws)
           | (ws, (_, _, as)) <- facts
           , BTAtom o <- as
           ]

  objectNames = map fst universe

  -- The argument tuples a predicate is given outright: by an
  -- `object_declaration` (unary, the category) and by every ground fact.
  groundTuples :: Text -> Int -> [[Text]]
  groundTuples n a =
    nub
      ( [[bNameText d.bodName] | a == 1, (_, d) <- objects, bNameText d.bodCategory == n]
          <> [ map atomName as
             | (_, (True, p, as)) <- facts
             , bNameText p == n
             , length as == a
             , all isAtomArg as
             ] )

  -- ------------------------------------------------------------------
  -- Record fields
  -- ------------------------------------------------------------------
  -- @(field name, @desc, the type)@. A unary predicate's channel is the
  -- three-valued @MAYBE BOOLEAN@ of the flat-universe phase; an n-ary
  -- predicate's is the set of tuples of its remaining arguments' names,
  -- carried by its FIRST argument, so `player(testgame,bob)` is a row of
  -- `testgame`'s `player/2 fact`.
  fieldSpecs :: [(Text, Text, Text)]
  fieldSpecs =
    [("name", "the object's Blawx atom", "IS A STRING")]
      <> [ (fieldOf d, phrase (MkLit d.dclName d.dclArity True), chanType d.dclArity)
         | d <- decls
         ]
      <> [(exclusionField s, negAppliesName s, "IS A MAYBE BOOLEAN") | s <- appliesSections]
   where
    chanType 1 = "IS A MAYBE BOOLEAN"
    chanType _ = "IS A LIST OF (LIST OF STRING)"

  fieldNames :: [Text]
  fieldNames = [f | (f, _, _) <- fieldSpecs]

  fieldWidth = maximum (1 : map (Text.length . ident) fieldNames)

  -- ------------------------------------------------------------------
  -- Variables
  -- ------------------------------------------------------------------
  termVars :: BTerm -> [BVar]
  termVars = \case
    BTVar v -> [v]
    BTCons a b -> termVars a <> termVars b
    _ -> []

  -- Total by construction, for the same reason 'goalDeps' is: a catch-all
  -- returning "no variables" would silently make an existential look like a
  -- head variable, and the rule would then quantify over nothing.
  goalVars :: BGoal -> [BVar]
  goalVars = \case
    BGCall _ _ as -> concatMap termVars as
    BGNaf _ as -> concatMap termVars as
    BGCompare _ a b -> termVars a <> termVars b
    BGUnify a b -> termVars a <> termVars b
    BGDiseq a b -> termVars a <> termVars b
    BGIs v _ -> [v]
    BGFindall v gs o -> [v] <> concatMap goalVars gs <> [o]
    BGAggregate _ a b -> [a, b]
    BGApplies _ t -> termVars t
    BGHolds _ g -> goalVars g
    BGAccordingTo _ g -> goalVars g
    BGNegated _ g -> goalVars g
    BGNewObjectCategory _ t -> termVars t

  ruleHeadVars :: BRule -> [BVar]
  ruleHeadVars r = nub [v | BTVar v <- r.brConclusion.bcArgs]

  -- The variables the body introduces and the head does not bind: the
  -- existentials of s(CASP)'s clause reading, in first-appearance order.
  ruleBodyVars :: BRule -> [BVar]
  ruleBodyVars r =
    [v | v <- nub (concatMap goalVars r.brConditions), v `notElem` ruleHeadVars r]

  -- An L4 parameter name for a Blawx variable. Lower-cased, ASCII-clean, and
  -- pushed off any name it would shadow — a predicate's own identifier, a
  -- positional parameter, or a name already taken in this clause.
  l4VarName :: [Text] -> BVar -> Text
  l4VarName taken (MkBVar t) = uniq base
   where
    base =
      let cleaned = Text.filter ok (Text.toLower t)
      in  if Text.null cleaned then "v" else cleaned
    ok c = isAsciiLower c || isDigit c || c == '_'
    reservedHere = taken <> [worldVar] <> map (.dclName) decls <> map (\d -> predIdent d.dclName d.dclArity) decls
    uniq n = if n `elem` reservedHere then uniq (n <> "_") else n

  -- Successive fresh names for a list of variables, each avoiding the ones
  -- chosen before it.
  l4VarNames :: [Text] -> [BVar] -> [Text]
  l4VarNames taken0 = go taken0
   where
    go _ [] = []
    go taken (v : vs) = let n = l4VarName taken v in n : go (n : taken) vs

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
  -- edge here, or the guard goes quietly blind again. (The witness split
  -- 'rulePara' performs for an existential body variable adds no edge: the
  -- witness decision has exactly the rule's own conditions, and the
  -- quantifier decision depends only on the witness, positively.)
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
      , let l = litOf r.brConclusion.bcSign r.brConclusion.bcPred r.brConclusion.bcArgs
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
    BGCall s p as -> [litOf s p as]
    BGNewObjectCategory p t -> [litOf True p [t]]
    BGNaf p as -> [litOf True p as]
    BGNegated BNegClassical g -> map flipLit (goalLit g)
    BGNegated BNegDefault g -> goalLit g
    _ -> []

  -- | Total by construction: every 'BGoal' arm is spelled out, because a
  -- catch-all returning \"no dependency\" is the wrong default for a
  -- soundness scan — it is how 'BGApplies', 'BGHolds' and 'BGAccordingTo',
  -- the three constructors ruling P5-1 added, contributed no edge at all.
  goalDeps :: Bool -> BGoal -> [(Node, Bool)]
  goalDeps neg = \case
    BGCall s p as -> [(NLit (litOf s p as), neg)]
    BGNaf p as -> [(NLit (litOf True p as), True)]
    BGNewObjectCategory p t -> [(NLit (litOf True p [t]), neg)]
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
           , "-- Blawx models a flat universe of atoms under predicates of one, two or"
           , "-- more places: a category is `c(X)`, a category-valued attribute is"
           , "-- `a(X,Y)`, a relationship is `r(X,Y,Z)`. So this lift declares ONE record"
           , "-- for the universe, carrying one input slot per declared predicate (the"
           , "-- s(CASP) fact channel: `MAYBE BOOLEAN` at one place, a list of argument"
           , "-- tuples above it) and one BOOLEAN decision per predicate. The defeat layer"
           , "-- is unfolded: one decision per (section, literal) pair, named from the"
           , "-- generator's own #pred wording."
           ]
        <> ( if not needsWorld
               then []
               else
                 [ "--"
                 , "-- Because a Blawx test loads its own objects and facts beside the rules,"
                 , "-- the universe is a PARAMETER (`w`) of every derived decision rather than a"
                 , "-- module-level constant, and each test passes its own world."
                 ] )

  importsPara = "IMPORT prelude\nIMPORT `negation-as-failure`"

  -- CLEAN `rule_text` is CRLF-separated in the wild (bird's is), and a stray
  -- CR inside a backticked name is a lexer error, not a cosmetic blemish.
  -- Normalised here rather than in Parse, so the IR keeps the stored bytes and
  -- a re-emitted `.blawx` still reproduces them.
  --
  -- `parseRuleText` keeps everything before the first NUMBERED line in the
  -- title, so a CLEAN whose sections are introduced by an un-numbered heading
  -- (rps: "Players", "Defeating Relationships", "Winner") arrives with the
  -- whole Act in `brTitle`. The § takes the first line, which is the title in
  -- every shipped example; the remainder has no § to sit under until W3 gives
  -- CLEAN headings and paragraph eIds an image, so it is reproduced verbatim
  -- as comment lines and warned about. Dropping it would be dropping the
  -- statute.
  titleLines :: [Text]
  titleLines =
    [ l
    | l <- Text.splitOn "\n" (Text.replace "\r\n" "\n" (Text.strip doc.bdRuleText.brTitle))
    ]

  titlePara = "§ " <> ident (noCR (case titleLines of l : _ -> l; [] -> ""))

  titleRestParas :: L [Text]
  titleRestParas = case drop 1 titleLines of
    [] -> pure []
    rest -> do
      warn "rule-text-unstructured" ""
        ( "the CLEAN `rule_text` does not become flat numbered sections from its "
            <> "first line, so `parseRuleText` kept " <> Text.textShow (length rest)
            <> " further line(s) in the title; they are reproduced as comments "
            <> "because no § can carry them yet (BLAWX-EXPORT-SPEC §11 W3)" )
      pure
        [ Text.intercalate "\n"
            ( [ "-- The CLEAN `rule_text` continues past its title line. It is not flat"
              , "-- numbered from the start — an un-numbered heading intervenes — so the"
              , "-- lift has no § to put the rest under (W3). Verbatim:"
              ]
                <> [ "--" <> (if Text.null (Text.stripEnd l') then "" else " " <> l')
                   | l <- rest
                   , let l' = Text.stripEnd (Text.filter (/= '\r') l)
                   ] )
        ]

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
            , "      " <> padTo (fieldWidth + 3) (ident f) <> ty
            ]
          | (f, desc, ty) <- fieldSpecs
          ]

  -- The channel arm: an input the scenario may supply directly.
  channelArm :: Decl -> Text
  channelArm d = case argVars d.dclArity of
    [v] -> "holds (" <> v <> "'s " <> ident (fieldOf d) <> ")"
    v0 : rest ->
      "elem (LIST " <> Text.intercalate ", " [v <> "'s name" | v <- rest] <> ") ("
        <> v0 <> "'s " <> ident (fieldOf d) <> ")"
    [] -> "FALSE"

  -- The arm a ground fact contributes: the argument atoms, by name.
  memberArm :: Int -> [Text] -> Text
  memberArm 1 [o] = "x's name EQUALS " <> quoted o
  memberArm a os =
    "("
      <> Text.intercalate " AND "
           [v <> "'s name EQUALS " <> quoted o | (v, o) <- zip (argVars a) os]
      <> ")"

  inputDecision :: Decl -> L Text
  inputDecision d = do
    let l = MkLit d.dclName d.dclArity True
        vs = argVars d.dclArity
        arms = channelArm d : [memberArm d.dclArity tup | tup <- groundTuples d.dclName d.dclArity]
        refLine =
          [ "@ref " <> renderSectionRef ws <> " object_declaration — "
              <> bNameText od.bodName <> " is a " <> d.dclName
          | d.dclArity == 1
          , (ws, od) <- objects
          , bNameText od.bodCategory == d.dclName
          ]
    body <- armsBody (litIdent l) arms
    pure $
      Text.intercalate "\n"
        ( take 1 refLine
            <> [givenBooleanFor False vs, "DECIDE " <> callIdent (litIdent l) False vs <> nlgSuffix l]
            <> body )

  armsBody :: Text -> [Text] -> L [Text]
  armsBody who = \case
    [] -> do
      _ <-
        refuse "empty-decision" who
          "the predicate has no arms: neither an input channel nor a rule concludes it"
      pure ["    IF FALSE"]
    a : as -> pure (("    IF " <> a) : map ("    OR " <>) as)

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
        wsBlocks = [b | (ws, b) <- blocks, ws == s]
        filler
          | not (null outs) || not (null apps) || not (null rulePs) || not (null ins) = []
          | null wsBlocks = ["-- " <> renderSectionRef s <> " carries no blocks."]
          | otherwise =
              [ Text.intercalate "\n"
                  [ "-- " <> renderSectionRef s <> " carries no rules of its own; "
                      <> ( if length wsBlocks == 1
                             then "its one block is"
                             else "its " <> Text.textShow (length wsBlocks) <> " blocks are" )
                      <> " lifted elsewhere:"
                  , "-- declarations into `§§ Ontology`, ground facts into the predicates they ground."
                  ]
              ]
    pure ([heading] <> cs <> outs <> apps <> rulePs <> ins <> filler)

  rulePara :: BSectionRef -> BRule -> L [Text]
  rulePara s r = do
    let l = litOf r.brConclusion.bcSign r.brConclusion.bcPred r.brConclusion.bcArgs
        who = renderSectionRef s
        hvs = argVars (max 1 (length r.brConclusion.bcArgs))
        headVs = ruleHeadVars r
        bodyVs = ruleBodyVars r
        exNames = l4VarNames hvs bodyVs
        env = Map.fromList (zip headVs hvs <> zip bodyVs exNames)
        world = needsWorld
    unless (distinctVars r.brConclusion) $
      refuse_ "conclusion-shape" who
        ( "the conclusion `"
            <> renderGoal (BGCall r.brConclusion.bcSign r.brConclusion.bcPred r.brConclusion.bcArgs)
            <> "` is not a predicate applied to distinct object variables" )
    conds <- concat <$> traverse (ruleCondition who s r.brInapplicable env) r.brConditions
    let accName = accordingName s l
        witName = accName <> ", witnessed by " <> englishList exNames
        bodyName = if null exNames then accName else witName
        bodyVsAll = hvs <> exNames
        accRef =
          "@ref " <> labelOf s <> " — " <> renderSectionRef s
            <> " attributed_rule (defeasible " <> yesNo r.brDefeasible
            <> ", inapplicable " <> yesNo r.brInapplicable <> ")"
        bodyHead = "DECIDE " <> callIdent bodyName world bodyVsAll
        bodyGiven = givenBooleanFor world bodyVsAll
        bodyPara = case conds of
          [] -> Text.intercalate "\n" [accRef, bodyGiven, bodyHead <> " IF TRUE"]
          [c] -> Text.intercalate "\n" [accRef, bodyGiven, bodyHead <> " IF " <> c]
          c : cs ->
            Text.intercalate "\n"
              ([accRef, bodyGiven, bodyHead, "    IF  " <> c] <> map ("    AND " <>) cs)
        quantPara =
          Text.intercalate "\n"
            [ "-- The rule's body binds " <> englishList exNames <> ", which its head does not."
            , "-- s(CASP) reads those existentially; Blawx has no open domain, so the"
            , "-- quantifier below ranges over exactly the objects the universe holds."
            , "@ref " <> labelOf s <> " — " <> renderSectionRef s
                <> " attributed_rule, existential closure"
            , givenBooleanFor world hvs
            , "DECIDE " <> callIdent accName world hvs
            , "    IF " <> quantify exNames (callIdent witName world bodyVsAll)
            ]
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
              [ "    IF      " <> callIdent accName world hvs
              , "    AND NOT " <> callIdent (defeatedName s l) world hvs
              ]
          | otherwise = ["    IF " <> callIdent accName world hvs]
        holdsPara =
          Text.intercalate "\n"
            ( holdsRef
                <> [givenBooleanFor world hvs, "DECIDE " <> callIdent (holdsName s l) world hvs]
                <> holdsBody )
    pure ([bodyPara] <> [quantPara | not (null exNames)] <> [holdsPara])

  quantify :: [Text] -> Text -> Text
  quantify [] inner = inner
  quantify (v : vs) inner =
    "any (GIVEN " <> ident v <> " YIELD " <> quantify vs inner <> ") " <> worldVar

  yesNo b = if b then "TRUE" else "FALSE"

  distinctVars c = case [v | BTVar v <- c.bcArgs] of
    [] -> False
    vs -> length vs == length c.bcArgs && length (nub vs) == length vs

  -- `inapplicable` injects the guard immediately after every condition whose
  -- block image is literally `new_object_category`
  -- (scasp_generator.js:1188-1194) and after nothing else. The POSITION is
  -- load-bearing, not just the presence.
  ruleCondition :: Text -> BSectionRef -> Bool -> Map BVar Text -> BGoal -> L [Text]
  ruleCondition who s inapplicable env g = do
    t <- liftGoal who env g
    case g of
      BGNewObjectCategory _ obj | inapplicable -> do
        o <- liftTerm who env obj
        pure [t, callIdent (appliesName s) needsWorld [o]]
      _ -> pure [t]

  defeatPara :: ((BSectionRef, Lit), [(Int, BSectionRef, BOverrule)]) -> L Text
  defeatPara ((s, l), ms) = do
    let world = needsWorld
        hvs = argVars l.litArity
    for_ ms \(_, ws, o) ->
      unless ((overruleLit o.bovDefeatingStmt).litArity == l.litArity) $
        refuse_ "defeat-arity" (renderSectionRef ws)
          ( "the overrules pairs " <> scaspLit (overruleLit o.bovDefeatingStmt)
              <> " with " <> scaspLit l <> ", which take different numbers of "
              <> "arguments, so the defeat has no well-typed L4 image" )
    let arms =
          [ callIdent (holdsName o.bovDefeating (overruleLit o.bovDefeatingStmt)) world hvs
          | (_, _, o) <- ms
          ]
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
        ( hdr
            <> [givenBooleanFor world hvs, "DECIDE " <> callIdent (defeatedName s l) world hvs]
            <> body )

  -- ---- the applicability layer -----------------------------------------
  appliesParas :: BSectionRef -> L [Text]
  appliesParas s = do
    let world = needsWorld
        outs = carveOuts s
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
        let env = Map.fromList [(v, "x") | v <- nub (concatMap goalVars r.burConclusion)]
        conds <- traverse (liftGoal (renderSectionRef ws) env) r.burConditions
        body <- armsBody (appliesName s) conds
        pure $
          Text.intercalate "\n" $
            [ "-- the closed-world applicability default"
            , "-- `blawx_applies(S,x) :- not -blawx_applies(S,x)`"
            , "@ref " <> labelOf s <> " — " <> renderSectionRef ws <> " unattributed_rule"
            , givenBooleanFor world ["x"]
            , "DECIDE " <> callIdent (appliesName s) world ["x"]
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
  basePred l = do
    let world = litTakesWorld l
        vs = argVars l.litArity
        arms =
          [channelArm d | l.litSign, Just d <- [declOf l.litPred l.litArity]]
            <> [memberArm l.litArity tup | l.litSign, tup <- groundTuples l.litPred l.litArity]
            <> [callIdent (holdsName s l) world vs | s <- sectionsConcluding l]
    body <- armsBody (litIdent l) arms
    pure $
      Text.intercalate "\n"
        ( [givenBooleanFor world vs, "DECIDE " <> callIdent (litIdent l) world vs <> nlgSuffix l]
            <> body )

  -- ---- objects ---------------------------------------------------------
  -- What a test canvas asserts, as (predicate, argument atoms). An
  -- `object_declaration` on a test canvas is a category fact about a
  -- TEST-LOCAL atom — its s(CASP) image is exactly `<category>(<name>).` —
  -- so the two sources are one list.
  scenarioOf :: BTest -> [(Lit, [Text])]
  scenarioOf t =
    [ (MkLit (bNameText d.bodCategory) 1 True, [bNameText d.bodName])
    | BDeclareObject d <- concat t.btStacks
    ]
      <> [ (litOf True p as, map atomName as)
         | BFact True p as <- concat t.btStacks
         , all isAtomArg as
         , not (null as)
         ]

  -- The atoms a test brings with it: the ones it declares, and the ones its
  -- scenario facts are ABOUT (a fact's channel rides on its first argument).
  localAtomsOf :: BTest -> [Text]
  localAtomsOf t =
    nub
      ( [bNameText d.bodName | BDeclareObject d <- concat t.btStacks]
          <> [a | (_, a : _) <- scenarioOf t] )

  testLocalAtoms :: [Text]
  testLocalAtoms = nub (concatMap localAtomsOf doc.bdTests)

  objectParas :: [Text]
  objectParas
    | null universe && null testLocalAtoms = []
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
          -- `all objects` is the WORKSPACES' universe. A document whose only
          -- atoms are a test's own has none, and must still get `the name of`:
          -- the query rendering uses it whatever world it ranges over, and
          -- emitting the § without it produced a module that did not compile
          -- (measured on `mortality`, 2026-09-02).
          <> [ ident "all objects" <> " MEANS LIST " <> Text.intercalate ", " (map ident objectNames)
             | not (null universe)
             ]
          <> [ Text.intercalate "\n"
                 [ "GIVEN x IS AN Object"
                 , "GIVETH A STRING"
                 , "`the name of` x MEANS x's name"
                 ]
             ]

  -- One `IS` line per field at the given indent. A unary channel is
  -- `JUST TRUE` where the scenario asserts the predicate of this object and
  -- `NOTHING` elsewhere; an n-ary channel is the list of the remaining
  -- arguments' names, and `EMPTY` where the scenario says nothing.
  recordFields :: Int -> Text -> [(Lit, [Text])] -> [Text]
  recordFields ind objName sc =
    [pad <> padTo (fieldWidth + 1) (ident f) <> "IS " <> val f ty | (f, _, ty) <- fieldSpecs]
   where
    pad = Text.replicate ind " "
    fieldKey l = predIdent l.litPred l.litArity <> " fact"
    val f ty
      | f == "name" = quoted objName
      | ty == "IS A MAYBE BOOLEAN" =
          if any (\(l, as) -> fieldKey l == f && as == [objName]) sc then "JUST TRUE" else "NOTHING"
      | otherwise =
          case [drop 1 as | (l, as) <- sc, fieldKey l == f, take 1 as == [objName]] of
            [] -> "EMPTY"
            ts ->
              "LIST "
                <> Text.intercalate ", "
                     ["(LIST " <> Text.intercalate ", " (map quoted t) <> ")" | t <- ts]

  -- ---- tests -----------------------------------------------------------
  testParas :: L [Text]
  testParas
    | null doc.bdTests = pure []
    | otherwise = do
        ts <- concat <$> traverse testParaBlocks doc.bdTests
        pure (["§§ `Tests`"] <> ts)

  -- A test canvas gets the same vetting a workspace canvas gets, and the same
  -- refusal codes — but at WARNING severity, dropping the test rather than the
  -- document. See the module header: a rule that cannot be lifted must refuse,
  -- because the emitted program would say something the Blawx document does
  -- not; a test that cannot be lifted only costs a check, and the reason is
  -- written where its `#EVAL` would have been.
  testParaBlocks :: BTest -> L [Text]
  testParaBlocks t = do
    let bs = concat t.btStacks
        queries = [gs | BQuery gs <- bs]
        handled = \case
          BQuery _ -> True
          BDeclareObject _ -> True
          BFact True _ as -> all isAtomArg as && not (null as)
          _ -> False
        strays = [b | b <- bs, not (handled b)]
        scenario = scenarioOf t
        undeclared = [l | (l, _) <- scenario, isNothing (declOf l.litPred l.litArity)]
        localAtoms = localAtomsOf t
        scaspFacts =
          [ "`" <> l.litPred <> "(" <> Text.intercalate "," as <> ").`" | (l, as) <- scenario ]
        queryText = case queries of
          gs : _ -> ["`?- " <> Text.intercalate ", " (map renderGoal gs) <> ".`"]
          [] -> ["(no query block)"]
        provenance =
          "-- blawxtest " <> t.btName <> " — " <> Text.unwords (scaspFacts <> queryText)
        commentLines = case t.btComment of
          Nothing -> []
          Just c -> concatMap (wrapPrefixed "-- " "-- ") (Text.splitOn "\n" c)
        blocked =
          [ ("test-block", blockLabel b <> " has no #EVAL image this phase")
          | b <- take 1 strays
          ]
            <> [ ( "scenario-undeclared"
                 , "the scenario asserts `" <> l.litPred <> "/" <> Text.textShow l.litArity
                     <> "` but that predicate is not declared, so there is no field to carry it" )
               | l <- take 1 undeclared
               ]
            <> [("many-queries", "the test carries more than one `query` block") | length queries > 1]
    case blocked of
      (code, msg) : _ -> do
        warn code t.btName (msg <> "; the test is not lifted and emits no #EVAL")
        pure
          [ Text.intercalate "\n"
              ( [provenance]
                  <> commentLines
                  <> ["-- NOT LIFTED (blawx-lift/" <> code <> "): " <> msg <> "."] )
          ]
      [] -> case queries of
        -- A test row whose canvas holds no `query` block asks nothing. That is
        -- a half-finished test in the editor, not a construct with no L4
        -- image, so it warns and contributes no #EVAL rather than refusing the
        -- document. (Witness: `wills_tutorial`, whose only rows are empty.)
        [] -> do
          warn "test-without-query" t.btName
            "the test carries no `query` block, so it asks nothing and emits no #EVAL"
          pure [Text.intercalate "\n" ([provenance] <> commentLines)]
        gs : _ -> do
          let localName a = t.btName <> " " <> a
              worldName = t.btName <> " world"
              wExpr
                | not needsWorld = ident "all objects"
                | null localAtoms = ident "all objects"
                | otherwise = ident worldName
              objE a
                | needsWorld = if a `elem` localAtoms then ident (localName a) else ident a
                | not (any (\(_, as) -> take 1 as == [a]) scenario) = ident a
                | otherwise =
                    "(Object WITH\n"
                      <> Text.intercalate "\n" (recordFields 17 a scenario)
                      <> ")"
              extras
                | not needsWorld || null localAtoms = []
                | otherwise =
                    [ Text.intercalate "\n"
                        ( [ident (localName a) <> " MEANS", "    Object WITH"]
                            <> recordFields 8 a scenario )
                    | a <- localAtoms
                    ]
                      <> [ ident worldName <> " MEANS LIST "
                             <> Text.intercalate ", "
                                  ( map (ident . localName) localAtoms
                                      <> [ident n | n <- objectNames, n `notElem` localAtoms] )
                         ]
              anyObjects = not (null objectNames) || not (null localAtoms)
          body <- testExpr t.btName wExpr objE (not (null scenario)) anyObjects gs
          let hd = [provenance] <> commentLines
              directive = ["#EVAL " <> body]
          pure $
            if null extras
              then [Text.intercalate "\n" (hd <> directive)]
              else [Text.intercalate "\n" hd] <> extras <> [Text.intercalate "\n" directive]

  -- The query, as an L4 expression. A free variable is a filter over the
  -- object universe the test runs against — exact because Blawx has no open
  -- domain: an atom must be introduced by an object_declaration or by a fact.
  -- Two free variables nest, and the answer is a list of name tuples.
  testExpr :: Text -> Text -> (Text -> Text) -> Bool -> Bool -> [BGoal] -> L Text
  testExpr who wExpr objE hasScenario anyObjects = \case
    [] -> refuse "empty-query" who "the query block holds no goals"
    [g] -> one g
    gs
      | any hasFreeVar gs ->
          refuse "query-shape" who
            "a multi-goal query that binds a free variable has no #EVAL image this phase"
      | otherwise -> Text.intercalate " AND " <$> traverse one gs
   where
    hasFreeVar = \case
      BGCall _ _ as -> any isVar as
      BGNewObjectCategory _ tm -> isVar tm
      BGNaf _ as -> any isVar as
      BGNegated _ g -> hasFreeVar g
      _ -> False
    isVar = \case
      BTVar _ -> True
      _ -> False
    one = \case
      BGCall s p as -> call (litOf s p as) as
      BGNewObjectCategory p tm -> call (litOf True p [tm]) [tm]
      BGNaf p as -> do
        t <- call (litOf True p as) as
        pure ("NOT (" <> t <> ")")
      BGNegated BNegDefault g -> do
        t <- one g
        pure ("NOT (" <> t <> ")")
      g -> refuse "query-shape" who ("the goal `" <> renderGoal g <> "` has no #EVAL image")
    call l as
      | null freeVs = pure inner
      | hasScenario && not needsWorld =
          refuse "scenario-with-free-variable" who
            ( "the query binds a free variable while the test also asserts scenario "
                <> "facts; the filter-over-declared-objects rendering would not see them" )
      | not anyObjects =
          refuse "unbound-query" who
            "the query binds a free variable but the document declares no objects to range over"
      | otherwise = pure comprehension
     where
      freeVs = [v | BTVar v <- as]
      names = l4VarNames [] freeVs
      binding = zip freeVs names
      argText = \case
        BTVar v -> case lookup v binding of
          Just n -> ident n
          Nothing -> "?"
        BTAtom o -> objE (bNameText o)
        other -> renderTerm other
      -- NOT 'callIdent': at a query site the world is the test's own world
      -- EXPRESSION, and `w` is not in scope.
      inner =
        ident (litIdent l) <> " "
          <> Text.unwords ([wExpr | litTakesWorld l] <> map argText as)
      tuple = "LIST " <> Text.intercalate ", " ["`the name of` " <> ident v | v <- names]
      comprehension = case names of
        -- The eta-reduced spelling the flat-universe phase emitted, kept so a
        -- document that needs no world (bird) is byte-identical.
        [v]
          | not needsWorld, l.litArity == 1 ->
              "map `the name of` (filter " <> ident (litIdent l) <> " " <> wExpr <> ")"
          | otherwise ->
              "map `the name of` (filter (GIVEN " <> ident v <> " YIELD " <> inner <> ") "
                <> wExpr <> ")"
        _ -> nest names
      nest = \case
        [] -> inner
        [v] ->
          "map (GIVEN " <> ident v <> " YIELD " <> tuple <> ") (filter (GIVEN " <> ident v
            <> " YIELD " <> inner <> ") " <> wExpr <> ")"
        v : vs ->
          "concat (map (GIVEN " <> ident v <> " YIELD " <> nest vs <> ") " <> wExpr <> ")"

  -- ------------------------------------------------------------------
  -- Goals
  -- ------------------------------------------------------------------
  liftGoal :: Text -> Map BVar Text -> BGoal -> L Text
  liftGoal who env = go
   where
    go = \case
      BGCall s p as -> call (litOf s p as) as
      BGNewObjectCategory p tm -> call (litOf True p [tm]) [tm]
      BGApplies s tm -> do
        t <- liftTerm who env tm
        pure (callIdent (appliesName s) needsWorld [t])
      -- The one place negation-as-failure earns its keep: the negated
      -- predicate is an INPUT, so "unknown" must behave as "absent", which a
      -- plain NOT over a total BOOLEAN cannot say.
      BGNegated BNegDefault (BGNegated BNegClassical (BGApplies s tm)) -> do
        t <- liftTerm who env tm
        pure ("naf (" <> ident (negAppliesName s) <> " " <> t <> ")")
      BGNaf p as -> do
        t <- call (litOf True p as) as
        pure ("NOT (" <> t <> ")")
      BGNegated BNegClassical (BGCall True p as) -> call (litOf False p as) as
      BGNegated BNegDefault g -> do
        t <- go g
        pure ("NOT (" <> t <> ")")
      -- Blawx compares OBJECTS by atom; L4 compares records by value. The
      -- atom is the `name` field, so that is what the two agree on — see the
      -- module header, and W1 on the export side for the same finding read
      -- from the other direction.
      BGDiseq a b -> do
        ta <- liftTerm who env a
        tb <- liftTerm who env b
        pure ("NOT (" <> ta <> "'s name EQUALS " <> tb <> "'s name)")
      BGUnify a b -> do
        ta <- liftTerm who env a
        tb <- liftTerm who env b
        pure (ta <> "'s name EQUALS " <> tb <> "'s name")
      g -> refuse "goal-shape" who ("the condition `" <> renderGoal g <> "` has no L4 image this phase")
    call l as = do
      ts <- traverse (liftTerm who env) as
      pure (callIdent (litIdent l) (litTakesWorld l) ts)

  liftTerm :: Text -> Map BVar Text -> BTerm -> L Text
  liftTerm who env = \case
    BTVar v@(MkBVar vt) -> case Map.lookup v env of
      Just n -> pure (ident n)
      Nothing ->
        refuse "unbound-variable" who
          ("the variable `" <> vt <> "` is bound neither by the rule's head nor by its body")
    BTAtom o
      | bNameText o `elem` objectNames -> pure (ident (bNameText o))
      | otherwise ->
          refuse "unknown-object" who
            ("the atom `" <> bNameText o <> "` is used as an object but never declared")
    t -> refuse "term-shape" who ("the term `" <> renderTerm t <> "` is not an object")

-- ---------------------------------------------------------------------------
-- Text helpers
-- ---------------------------------------------------------------------------

-- | @a, b and c@ — for a diagnostic and for a synthesised decision name.
englishList :: [Text] -> Text
englishList = \case
  [] -> ""
  [a] -> a
  [a, b] -> a <> " and " <> b
  xs -> Text.intercalate ", " (init xs) <> " and " <> last xs

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
