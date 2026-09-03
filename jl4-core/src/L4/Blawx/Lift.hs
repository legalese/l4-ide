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
-- __A value-typed attribute is a partial function, not a predicate__
-- (BLAWX-EXPORT-SPEC §11 W5). @facial_hair_length_mm(X,V)@ maps an object to
-- a /number/, and @throws(X,S)@ to another /object/; neither is a unary
-- predicate, so neither gets a @\<p\> fact@ channel. Each gets instead a
-- field of its own sort (@MAYBE NUMBER@; @MAYBE STRING@, holding the target
-- atom's __name__, because the universe is flat and an object is already
-- identified by @x's name@ throughout this module) and __two__ decisions:
-- @p x@, which is @isJust@ of the field and says the attribute is /defined/,
-- and @\`the p of\` x@, which is @fromMaybe \<default\>@ of it and is the
-- /value/. A binary goal @p(X,V)@ in a rule body is then a __binding__: L4
-- has no logic variables, so @V@ is substituted by the accessor at every use
-- (which is how @blawx_comparison(V,gte,5)@ becomes @… AT LEAST 5@) and the
-- goal itself contributes only the definedness conjunct. The accessor's
-- default is never observed alone, because both conjuncts land in the same
-- top-level @AND@ chain: an absent attribute makes the body @FALSE@, exactly
-- as @p(X,V)@ with no clause does. A rule that /concludes/ a value-typed
-- attribute, and a value variable used in /object/ position, are both refused
-- by name — the flat universe has no name-to-object lookup this phase.
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
import Data.Ratio (denominator, numerator)

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
  , dclValue   :: !(Maybe ValueSort)
    -- ^ 'Nothing' for a category, a boolean attribute or an OBJECT-valued
    -- attribute: each of those is a predicate over the object universe (the
    -- last a binary one). 'Just' for a __value-typed__ attribute, which is a
    -- partial function from the universe to a sort L4 has a type for, and is
    -- not a predicate at all.
  , dclRef     :: !Text     -- ^ the @\@ref@ line body
  }

-- | The two value sorts a non-boolean attribute has an L4 image for
-- (BLAWX-EXPORT-SPEC §11 W5). A @number@ attribute becomes a @MAYBE NUMBER@
-- field; a __category__-valued one becomes a @MAYBE STRING@ field holding the
-- target atom's name, because the universe is flat and an object is already
-- identified by @x's name@ everywhere else in this lift — a @MAYBE Object@
-- field would make the record recursive and would put record equality (the
-- W1 unsoundness) on the import side too.
data ValueSort = VSNumber
  deriving stock (Eq, Show)

-- | The L4 type of a value-typed attribute's field.
sortType :: ValueSort -> Text
sortType = \case
  VSNumber -> "NUMBER"

-- | The value 'fromMaybe' hands back when the attribute is absent. It is
-- never observed on its own: every use of a bound value variable is emitted
-- under the definedness conjunct the binding goal contributes, and both sit
-- in the same top-level @AND@ chain, so an absent attribute makes the whole
-- body @FALSE@ — which is what s(CASP) does when @attr(X,V)@ has no clause.
sortDefault :: ValueSort -> Text
sortDefault = \case
  VSNumber -> "0"

-- | The value sort of an attribute's declared type, or the reason it has no
-- image this phase.
valueSortOf :: BValueType -> Either Text (Maybe ValueSort)
valueSortOf = \case
  BVBoolean -> Right Nothing
  BVNumber -> Right (Just VSNumber)
  BVCategory _ -> Right Nothing
  t -> Left (renderValueType t)

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

  -- W5: a `number` attribute now has an image (a `MAYBE NUMBER` field plus an
  -- accessor) and a category-valued one lifts as a binary predicate; the date,
  -- time, duration and list sorts still do not.
  for_ attrDecls \(ws, d) -> case valueSortOf d.baType of
    Right _ -> pure ()
    Left ty ->
      refuse_ "attribute-type" (renderSectionRef ws)
        ( "attribute " <> bNameText d.baName <> " has value type " <> ty
            <> "; this phase lifts a BOOLEAN attribute as a unary predicate "
            <> "over the object universe, a category-valued one as a binary "
            <> "predicate and a number-valued one as a field plus an accessor, "
            <> "but the date/time/duration/list sorts are the date layer "
            <> "(owner: DATE-LIBRARY-SPEC)" )

  -- A value-typed attribute is a partial FUNCTION here, not a predicate a
  -- rule can conclude; it would collide with the accessor pair emitted for it
  -- in the ontology. (A conclusion of the wrong shape is already refused by
  -- `conclusion-shape`; this catches the well-shaped spellings.)
  for_ arules \(ws, r) ->
    when (bNameText r.brConclusion.bcPred `elem` valueNames) $
      refuse_ "value-attribute-concluded" (renderSectionRef ws)
        ( "the rule concludes " <> bNameText r.brConclusion.bcPred
            <> ", which is declared as a value-typed attribute; a value-typed "
            <> "attribute lifts to an input field plus an accessor, and has no "
            <> "rule-derived spelling this phase" )

  for_ facts \(ws, (_, p, as)) ->
    unless (all isAtomArg as && not (null as)) $
      refuse_ "fact-shape" (renderSectionRef ws)
        ( "the fact `" <> renderGoal (BGCall True p as)
            <> "` is not a predicate applied to object atoms" )

  -- ---- placement ------------------------------------------------------
  for_ arules \(ws, r) -> do
    unless (secOf r `elem` flatRefs) $
      refuse_ "rule-section" (renderSectionRef ws)
        ( "the rule is attributed to " <> renderSectionRef r.brSection
            <> ", which is neither a flat numbered section nor a paragraph of "
            <> "one; the § scaffolding has nowhere to put it" )
    when (secOf r /= r.brSection) $
      warn "rule-section-flattened" (renderSectionRef ws)
        ( "the rule is attributed to " <> renderSectionRef r.brSection
            <> ", a paragraph; R4 ruled flat numbered sections for v1 and the "
            <> "paragraph eId question is still open (§11 W3), so its decisions "
            <> "are filed under " <> renderSectionRef (secOf r)
            <> " and the paragraph survives only in the @ref line" )
    when (r.brSection /= ws) $
      warn "rule-filed-elsewhere" (renderSectionRef ws)
        ( "the rule's doc_selector names " <> renderSectionRef r.brSection
            <> ", not the workspace it is drawn in; the attribution wins" )
    -- __The APPLICABILITY layer has the same fold hazard as the defeat layer,
    -- and it was open until integration (2026-09-02).__
    -- `scasp_generator.js:1188-1194` injects `blawx_applies(<value_source>, X)`
    -- with @value_source@ the rule's OWN attributed section, while
    -- 'ruleCondition' injects `appliesName (secOf r)` — the FOLDED one. For a
    -- rule attributed to a paragraph those are two different gates: Blawx asks
    -- `blawx_applies(<paragraph>, X)`, which typically has no clause at all, so
    -- the rule can never fire there, while the lift asks the PARENT's gate,
    -- which is derivable. Measured on a variant of Jason Morris's bird.yaml with
    -- one `inapplicable TRUE` rule repointed at `sec_5__para_a_section`: L4
    -- answered TRUE and s(CASP) NOMODEL, and hand-adding
    -- `blawx_applies(sec_5__para_a_section,A) :- not -blawx_applies(...).`
    -- flipped it. Since the two gates cannot be reconciled by folding — one
    -- would be given a body the source does not have — it is refused by name,
    -- exactly as `defeat-target` and `defeat-fold-unsound` are.
    when (r.brInapplicable && secOf r /= r.brSection) $
      case appliesRule r.brSection of
        Nothing ->
          refuse_ "applies-target" (renderSectionRef ws)
            ( "the rule is `subject to applicability` and attributed to "
                <> renderSectionRef r.brSection <> ", a paragraph, but no "
                <> "unattributed_rule defines blawx_applies for THAT section, so "
                <> "s(CASP) derives no `blawx_applies(" <> renderSectionRef r.brSection
                <> ",X)` and the rule can never fire in Blawx; folding the gate "
                <> "into " <> renderSectionRef (secOf r) <> " (§11 W3) would give "
                <> "it a body the source does not have" )
        Just _ ->
          refuse_ "applies-fold-unsound" (renderSectionRef ws)
            ( "the rule is `subject to applicability` and attributed to "
                <> renderSectionRef r.brSection <> ", a paragraph with an "
                <> "applicability rule of its own; folding it into "
                <> renderSectionRef (secOf r) <> " (§11 W3) would swap that gate "
                <> "for the parent section's, which is a different condition" )

  -- __An `overrules` names three sections, and the fold has to be checked on
  -- all of them.__ Only the workspace was checked before, which is how a
  -- defeat naming a paragraph was silently dropped: the rule was filed under
  -- the FOLDED section while the group was keyed on the RAW one, so
  -- `isDefeated` was False, the `AND NOT <defeated>` conjunct was never
  -- emitted, and the `… is defeated` decision was defined and never used —
  -- exit 0, no diagnostic, clean `l4 check`.
  --
  -- Folding the group keys as well fixes that, but only where the fold is
  -- MEANING-PRESERVING, and measurement says it is not always. s(CASP) keys
  -- `holds/3` on the exact section, so `holds(sec_1_section, qualifies_s1b)`
  -- with the rule attributed to `sec_1__para_b_section` has no clause at all
  -- and the defeat is INERT in Blawx; the fold would give it a body and make
  -- it fire. The mirror hazard is on the defeated side: a defeat aimed at one
  -- paragraph would cover a sibling paragraph's rules that fold into the same
  -- §§. Both change the answer, so both are refused by name rather than
  -- folded quietly.
  for_ defeatGroups \g@((_, l), ms) -> do
    unless (groupHome g `elem` flatRefs) $
      refuse_ "defeat-section" (renderSectionRef (fst (fst g)))
        ( "an `overrules` is drawn in a workspace that is neither a flat "
            <> "numbered section nor a paragraph of one" )
    for_ (nub [o.bovDefeated | (_, _, o) <- ms]) \rd ->
      defeatSideOk "defeated" rd l
    for_ ms \(_, _, o) ->
      defeatSideOk "defeating" o.bovDefeating (overruleLit o.bovDefeatingStmt)

  -- The defeat layer's half of `rule-section-flattened`: say so when an
  -- `overrules` survives only because of the fold.
  for_ defeatGroups \g ->
    for_ [r | r <- groupRawSections g, foldSec r /= r] \r ->
      warn "defeat-section-flattened" (renderSectionRef r)
        ( "an `overrules` names " <> renderSectionRef r
            <> ", a paragraph; it is folded into " <> renderSectionRef (foldSec r)
            <> " with the rest of that paragraph's blocks (§11 W3 still owns "
            <> "the eId question), and the defeat is emitted as the parent "
            <> "section's. The fold is extension-preserving here, which is "
            <> "what `blawx-lift/defeat-fold-unsound` checks" )

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
          , dclValue = Nothing
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
          , dclValue = either (const Nothing) id (valueSortOf d.baType)
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
          , dclValue = Nothing
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
          , dclValue = Nothing
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
    [ (litOf r.brConclusion.bcSign r.brConclusion.bcPred r.brConclusion.bcArgs, (secOf r, r))
    | (_, r) <- arules
    ]

  concludedLits :: [Lit]
  concludedLits = nub (map fst concluding)

  -- `nub`bed: several `attributed_rule`s in ONE section may conclude the same
  -- literal (they are separate clauses of `according_to/3`, joined by
  -- 'rulePara'), and the base predicate must OR that section's `holds` in
  -- once, not once per clause.
  sectionsConcluding :: Lit -> [BSectionRef]
  sectionsConcluding l = nub [s | (l', (s, _)) <- concluding, l' == l]

  -- Every declared predicate gets an input channel, whatever its kind and
  -- whether or not a rule concludes it — see the module header for why the
  -- older category/attribute split was unsound. A predicate NO rule concludes
  -- gets its whole decision from the channel ('inputDecision'); one some rule
  -- concludes gets the channel as one more OR arm ('basePred').
  -- A boolean or object-valued predicate gets a `<p> fact` channel; a
  -- value-typed attribute gets a `<p>` field of its own sort plus the
  -- accessor pair in 'valueParas', and never a `fact` channel.
  channelDecls = [d | d <- decls, isNothing d.dclValue]
  inputDecls = [d | d <- channelDecls, MkLit d.dclName d.dclArity True `notElem` concludedLits]

  valueDecls = [d | d <- decls, isJust d.dclValue]
  valueNames = map (.dclName) valueDecls

  valueDeclOf :: Text -> Maybe Decl
  valueDeclOf n = find (\d -> d.dclName == n) valueDecls

  -- The accessor's name. `the name of` (the object's atom) already reads this
  -- way, so a value attribute's reader matches it.
  accessorName :: Text -> Text
  accessorName n = "the " <> n <> " of"

  -- The generator's own binary #pred sentence, with the object and the value
  -- in the slots the declaration's `order` field puts them in ('NlgBinary').
  valuePhrase :: Decl -> Text -> Text -> Text
  valuePhrase d subj val = case nlgSentence d.dclNlg [subj, val] of
    Just t -> t
    Nothing -> Text.unwords [subj, val]

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
    -- A VALUE-typed attribute is arity 2 in Blawx and no predicate at all
    -- here: it is a field plus an accessor, so it neither widens a decision
    -- nor needs a universe to range over.
    any (\d -> d.dclArity > 1 && isNothing d.dclValue) decls
      || any (\(_, r) -> not (null (ruleExVars r))) arules
      || or [True | t <- doc.bdTests, st <- t.btStacks, BDeclareObject _ <- st]

  litTakesWorld :: Lit -> Bool
  litTakesWorld l = needsWorld && l `elem` concludedLits

  -- | Does the L4 image of this body goal MENTION the world? Read straight off
  -- 'liftGoal': it emits @w@ exactly where 'callIdent' is given a 'True' world
  -- flag, which is 'litTakesWorld' for a predicate call and 'needsWorld' for
  -- the applicability goals. Everything else — the atom comparisons, the
  -- @naf@ over the negative-applicability input — is world-free.
  --
  -- Used by 'rulePara' to keep the WITNESS decision honest: a rule whose body
  -- is all base predicates (rps s.4 is one) would otherwise declare a
  -- @w IS A LIST OF Object@ parameter it never reads, and a reader would go
  -- looking for the use.
  --
  -- Total by construction, for the reason 'goalDeps' is: a catch-all reading
  -- "no world" would silently drop the parameter from a decision that needs
  -- it, and the module would stop compiling only if the shape ever reached
  -- here. The arms that 'liftGoal' refuses answer 'False' because a refusal
  -- makes 'liftBlawx' return 'Left' and nothing is emitted at all.
  goalUsesWorld :: BGoal -> Bool
  goalUsesWorld = \case
    BGCall s p as -> litTakesWorld (litOf s p as)
    BGNewObjectCategory p tm -> litTakesWorld (litOf True p [tm])
    BGNaf p as -> litTakesWorld (litOf True p as)
    BGApplies _ _ -> needsWorld
    -- the `naf (<negApplies> t)` spelling: an INPUT decision, never worlded
    BGNegated BNegDefault (BGNegated BNegClassical (BGApplies _ _)) -> False
    BGNegated BNegClassical (BGCall True p as) -> litTakesWorld (litOf False p as)
    BGNegated BNegDefault g -> goalUsesWorld g
    BGNegated BNegClassical _ -> False
    BGDiseq _ _ -> False
    BGUnify _ _ -> False
    -- refused by 'liftGoal', so never emitted
    BGCompare {} -> False
    BGIs {} -> False
    BGFindall {} -> False
    BGAggregate {} -> False
    BGHolds {} -> False
    BGAccordingTo {} -> False

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
  -- order; two `overrules` naming the same pair become one OR. The key is the
  -- FOLDED section, because that is the section the defeated rule's decisions
  -- are filed under ('foldSec'); keying it raw is what silently dropped a
  -- paragraph's defeat.
  defeatGroups :: [((BSectionRef, Lit), [(Int, BSectionRef, BOverrule)])]
  defeatGroups =
    [ (k, [(i, ws, o) | (i, (ws, o)) <- overrs, key o == k])
    | k <- nub [key o | (_, (_, o)) <- overrs]
    ]
   where
    key o = (foldSec o.bovDefeated, overruleLit o.bovDefeatedStmt)

  -- A group is emitted in the section of its first defeating block — which is
  -- where a reader looks for "what this section overrides". A defeater drawn
  -- somewhere unplaceable falls back to the defeated section. Folded, for the
  -- same reason the key is: an `overrules` drawn on a paragraph canvas belongs
  -- to that paragraph's parent §§, which is the only §§ that exists.
  groupHome :: ((BSectionRef, Lit), [(Int, BSectionRef, BOverrule)]) -> BSectionRef
  groupHome (k, ms) = case ms of
    (_, ws, _) : _ | foldSec ws `elem` flatRefs -> foldSec ws
    _ -> fst k

  -- The raw (unfolded) sections a defeat group names, for provenance and for
  -- the flattening warnings. @fst (fst g)@ is already folded.
  groupRawSections :: ((BSectionRef, Lit), [(Int, BSectionRef, BOverrule)]) -> [BSectionRef]
  groupRawSections (_, ms) =
    nub (concat [[ws, o.bovDefeating, o.bovDefeated] | (_, ws, o) <- ms])

  -- | The rules the LIFT files under @(s, l)@ — the extension of the emitted
  -- @according_to@\/@holds@ pair.
  rulesFiledUnder :: BSectionRef -> Lit -> [BRule]
  rulesFiledUnder s l = [r | (_, r) <- arules, secOf r == s, litOfRule r == l]

  -- | …of which the ones BLAWX files under the raw section: the extension
  -- s(CASP)'s own @holds(s, l, X)@ has. Always a subset of the above, since
  -- @secOf r == foldSec r.brSection@.
  rulesAttributedTo :: BSectionRef -> Lit -> [BRule]
  rulesAttributedTo s l = [r | (_, r) <- arules, r.brSection == s, litOfRule r == l]

  -- | One side of one `overrules`, checked against the fold. @side@ is
  -- \"defeated\" or \"defeating\", for the message.
  defeatSideOk :: Text -> BSectionRef -> Lit -> L ()
  defeatSideOk side raw l = do
    unless (foldSec raw `elem` flatRefs) $
      refuse_ "defeat-section" (renderSectionRef raw)
        ( "an `overrules` names " <> renderSectionRef raw <> " as its " <> side
            <> " section, which is neither a flat numbered section nor a "
            <> "paragraph of one" )
    when (null attributed) $
      refuse_ "defeat-target" (renderSectionRef raw)
        ( "the `overrules` names " <> scaspLit l <> " in " <> renderSectionRef raw
            <> " as its " <> side <> " conclusion, but no attributed_rule is "
            <> "attributed to that section with that conclusion, so s(CASP) "
            <> "derives no `holds(" <> renderSectionRef raw <> "," <> scaspLit l
            <> ",X)` and the defeat has no effect in Blawx; folding the section "
            <> "would either dangle the reference or give the defeat a body it "
            <> "does not have" )
    unless (null attributed || length filed == length attributed) $
      refuse_ "defeat-fold-unsound" (renderSectionRef raw)
        ( "the `overrules` names " <> scaspLit l <> " in " <> renderSectionRef raw
            <> " as its " <> side <> " conclusion, but folding that section into "
            <> renderSectionRef (foldSec raw) <> " (§11 W3) would widen the "
            <> "defeat from " <> Text.textShow (length attributed) <> " rule(s) to "
            <> Text.textShow (length filed)
            <> ": the lifted defeat would cover rules Blawx's does not" )
   where
    attributed = rulesAttributedTo raw l
    filed = rulesFiledUnder (foldSec raw) l

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
          <> [secOf r | (_, r) <- arules, r.brInapplicable] )
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
  -- `testgame`'s `player/2 fact`. A value-typed attribute has no channel at
  -- all: it gets a field of its own sort, read by the accessor 'valueParas'
  -- emits.
  fieldSpecs :: [(Text, Text, Text)]
  fieldSpecs =
    [("name", "the object's Blawx atom", "IS A STRING")]
      <> [ (fieldOf d, phrase (MkLit d.dclName d.dclArity True), chanType d.dclArity)
         | d <- channelDecls
         ]
      <> [ (d.dclName, valuePhrase d "x" "v", "IS A MAYBE " <> sortType vs)
         | d <- valueDecls
         , Just vs <- [d.dclValue]
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

  -- The rule's head variables, mapped to the L4 parameters they lift to.
  ruleHenv :: BRule -> Map BVar Text
  ruleHenv r =
    Map.fromList (zip (ruleHeadVars r) (argVars (max 1 (length r.brConclusion.bcArgs))))

  -- The body variables that actually become EXISTENTIALS. A variable a binary
  -- VALUE-attribute goal binds is not one: it is discharged by substituting
  -- the accessor at every use, so it is quantified over nothing and does not
  -- make the module need a world.
  ruleExVars :: BRule -> [BVar]
  ruleExVars r =
    [ v
    | v <- ruleBodyVars r
    , v `notElem` map fst (valueBindings (ruleHenv r) r.brConditions)
    ]

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
      , let s = secOf r
      , let l = litOf r.brConclusion.bcSign r.brConclusion.bcPred r.brConclusion.bcArgs
      ]
    baseEdges =
      [(NLit l, NHolds s l, False) | l <- concludedLits, s <- sectionsConcluding l]
    defeatEdges =
      [ (NDefeated s l, NHolds (foldSec o.bovDefeating) (overruleLit o.bovDefeatingStmt), False)
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

  -- __The section a decision is FILED under__, as distinct from the section it
  -- is ATTRIBUTED to. R4 ruled flat numbered sections for v1, and Blawx files
  -- a paragraph's blocks under a nested workspace (`sec_1__para_a_section`).
  -- Until W3 gives paragraphs their own eId, the least-bad handling is to fold
  -- a paragraph into its parent `sec_n`: the rules still fire and the
  -- attribution is still printed on the decision's @ref line.
  --
  -- __EVERY reference to a section that names or places a decision has to go
  -- through here, not just a rule's own attribution.__ The defeat layer is
  -- keyed on (section, literal) pairs, so a fold applied to the rule but not
  -- to the `overrules` that defeats it leaves the two keyed differently: the
  -- `AND NOT <defeated>` conjunct is then never emitted and the
  -- `… is defeated` decision is defined and never used, with no diagnostic
  -- and a clean `l4 check`. That was this branch's own defect, found in
  -- review; the guards and warnings below are what replaced it.
  --
  -- What the fold costs, disclosed rather than hidden. The § nesting goes, and
  -- the flat scaffolding never had it. What it must NOT do is change which
  -- rules a defeat reaches, and it would in two directions — a sibling
  -- paragraph concluding the same literal folds into the same §§, and an
  -- `overrules` naming the flat parent while the rule sits in a paragraph is
  -- inert in s(CASP) but would gain a body here. Both are refused by name
  -- (`defeat-fold-unsound`, `defeat-target`); the surviving fold is
  -- extension-preserving and only warns (`defeat-section-flattened`).
  foldSec :: BSectionRef -> BSectionRef
  foldSec = \case
    BPath (st :| _ : _) | bStepKind st == "sec", BPath (st :| []) `elem` flatRefs ->
      BPath (st :| [])
    other -> other

  secOf :: BRule -> BSectionRef
  secOf r = foldSec r.brSection

  -- | The literal an attributed rule concludes.
  litOfRule :: BRule -> Lit
  litOfRule r = litOf r.brConclusion.bcSign r.brConclusion.bcPred r.brConclusion.bcArgs

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
        -- Emitted only when the document has one, so a boolean-only import
        -- (bird) is byte-for-byte what it was before §11 W5.
        <> [ line
           | not (null valueDecls)
           , line <-
               [ "--"
               , "-- A value-typed attribute is a partial FUNCTION, not a predicate: it gets a"
               , "-- field of its own sort instead of a `<p> fact` channel, a `p x` decision"
               , "-- saying the attribute is DEFINED, and a `the p of x` reader for the VALUE."
               ]
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
    pure
      ( ["§§ `Ontology`"]
          <> map commentPara rootComments
          <> [declarePara]
          <> valueParas
          <> inputs )

  -- A value-typed attribute is a PARTIAL FUNCTION from the universe to a
  -- sort, so it lifts to two decisions rather than one: `p x` says the
  -- attribute is defined (s(CASP)'s `p(X,V)` succeeding at all), and
  -- `the p of x` is the value. The accessor is total by `fromMaybe`, and its
  -- default is never observed on its own — every use of a bound value
  -- variable is emitted in the same top-level AND chain as the definedness
  -- conjunct the binding goal contributes, so an absent attribute makes the
  -- whole body FALSE, exactly as `p(X,V)` having no clause does.
  valueParas :: [Text]
  valueParas =
    concat
      [ [ Text.intercalate "\n"
            [ "@ref " <> d.dclRef
            , givenBooleanFor False ["x"]
            , "DECIDE " <> ident d.dclName <> " x @nlg there is a value v such that "
                <> valuePhrase d "%x%" "v"
            , "    IF isJust (x's " <> ident d.dclName <> ")"
            ]
        , Text.intercalate "\n"
            [ "-- the value itself, read under the definedness conjunct above."
            , "GIVEN x IS AN Object"
            , "GIVETH A " <> sortType vs
            , ident (accessorName d.dclName) <> " x"
            , "    MEANS fromMaybe " <> sortDefault vs <> " (x's " <> ident d.dclName <> ")"
            ]
        ]
      | d <- valueDecls
      , Just vs <- [d.dclValue]
      ]

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
        mine = [r | (_, r) <- arules, secOf r == s]
        -- Blawx admits several `attributed_rule`s in one section concluding
        -- the same literal — they are separate clauses of `according_to/3`
        -- and their meaning is the OR of their bodies. One decision per RULE
        -- would emit the same name twice; one per (section, literal) pair, as
        -- the unfolding requires, has to join them.
        groups = [(l, [r | r <- mine, litOfRule r == l]) | l <- nub (map litOfRule mine)]
    outs <- traverse defeatPara outward
    apps <- if s `elem` appliesSections then appliesParas s else pure []
    rulePs <- concat <$> traverse (uncurry (rulePara s)) groups
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

  -- One (section, literal) pair, and every `attributed_rule` that concludes
  -- it in that section. With one rule the shape is what it always was; with
  -- n > 1 each rule keeps its own named decision — one per Blawx block, which
  -- is MORE isomorphic, not less — and `according_to` becomes their OR. The
  -- dependency edges are unchanged by the split: a clause decision is a pure
  -- conjunction of the very nodes 'depEdges' already draws from `NAcc s l`.
  rulePara :: BSectionRef -> Lit -> [BRule] -> L [Text]
  rulePara _ _ [] = pure []
  rulePara s l rs@(r0 : _) = do
    let who = renderSectionRef s
    when (length (nub [(r.brDefeasible, r.brInapplicable) | r <- rs]) > 1) $
      refuse_ "rule-flag-mismatch" who
        ( "the " <> Text.textShow (length rs) <> " rules concluding " <> scaspLit l
            <> " in " <> labelOf s <> " disagree on `defeasible`/`inapplicable`; "
            <> "the holds-layer is per (section, literal) and cannot represent "
            <> "two answers" )
    let accName = accordingName s l
        clauseName i = accName <> " (clause " <> Text.textShow (i :: Int) <> ")"
        world = needsWorld
        hvs = argVars (max 1 l.litArity)
    (clausePs, accPs) <- case rs of
      [r] -> do
        ps <- ruleClause s accName r
        pure (ps, [])
      _ -> do
        pss <- traverse (\(i, r) -> ruleClause s (clauseName i) r) (zip [1 ..] rs)
        arms <- armsBody accName [callIdent (clauseName i) world hvs | i <- [1 .. length rs]]
        pure
          ( concat pss
          , [ Text.intercalate "\n"
                ( [ "-- `according_to(" <> renderSectionRef s <> "," <> scaspLit l
                      <> ",X)` has " <> Text.textShow (length rs)
                      <> " clauses in this section; their disjunction is the section's answer."
                  , givenBooleanFor world hvs
                  , "DECIDE " <> callIdent accName world hvs
                  ]
                    <> arms )
            ] )
    let r = r0
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
    pure (clausePs <> accPs <> [holdsPara])

  -- One rule's own paragraphs, with its top-level decision named @nm@ — the
  -- section's `according_to` when the section files one rule, that rule's own
  -- clause decision when it files several. Everything that is per-RULE rather
  -- than per-(section, literal) lives here: the conclusion shape, the two
  -- variable environments, the `inapplicable` guard's position, and the
  -- existential closure over the variables the body binds and the head does
  -- not.
  ruleClause :: BSectionRef -> Text -> BRule -> L [Text]
  ruleClause s nm r = do
    let who = renderSectionRef s
        hvs = argVars (max 1 (length r.brConclusion.bcArgs))
        headVs = ruleHeadVars r
        vpairs = valueBindings (ruleHenv r) r.brConditions
        venv = Map.fromList vpairs
        -- A variable a binary VALUE-attribute goal binds is not existentially
        -- quantified: it is discharged by substituting the accessor at every
        -- use, so it must not also become a `GIVEN` of the witness decision.
        bodyVs = ruleExVars r
        exNames = l4VarNames hvs bodyVs
        env = Map.fromList (zip headVs hvs <> zip bodyVs exNames)
        world = needsWorld
    unless (distinctVars r.brConclusion) $
      refuse_ "conclusion-shape" who
        ( "the conclusion `"
            <> renderGoal (BGCall r.brConclusion.bcSign r.brConclusion.bcPred r.brConclusion.bcArgs)
            <> "` is not a predicate applied to distinct object variables" )
    for_ (nub [v | (v, _) <- vpairs, length [() | (v', _) <- vpairs, v' == v] > 1]) \(MkBVar v) ->
      refuse_ "value-variable-rebound" who
        ( "the variable " <> v <> " is bound to an attribute value by more than "
            <> "one binary attribute goal; the substitution has no single answer" )
    conds <- concat <$> traverse (ruleCondition who s r.brInapplicable env venv) r.brConditions
    let witName = nm <> ", witnessed by " <> englishList exNames
        bodyName = if null exNames then nm else witName
        bodyVsAll = hvs <> exNames
        -- The witness decision is the ONE decision in the derived layer whose
        -- world parameter is not forced: nothing calls it but the quantifier
        -- immediately below, so it can take the world only when its own body
        -- reads it. Every other derived decision keeps the uniform flag,
        -- because 'basePred', 'defeatPara' and the holds layer call each other
        -- across paragraphs and must agree on arity.
        witUsesWorld =
          any goalUsesWorld r.brConditions
            || ( needsWorld
                   && r.brInapplicable
                   && or [True | BGNewObjectCategory _ _ <- r.brConditions] )
        bodyWorld = if null exNames then world else witUsesWorld
        accRef =
          "@ref " <> labelOf s <> " — " <> renderSectionRef r.brSection
            <> " attributed_rule (defeasible " <> yesNo r.brDefeasible
            <> ", inapplicable " <> yesNo r.brInapplicable <> ")"
        bodyHead = "DECIDE " <> callIdent bodyName bodyWorld bodyVsAll
        bodyGiven = givenBooleanFor bodyWorld bodyVsAll
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
            , "@ref " <> labelOf s <> " — " <> renderSectionRef r.brSection
                <> " attributed_rule, existential closure"
            , givenBooleanFor world hvs
            , "DECIDE " <> callIdent nm world hvs
            , "    IF " <> quantify exNames (callIdent witName bodyWorld bodyVsAll)
            ]
    pure ([bodyPara] <> [quantPara | not (null exNames)])

  -- `attr(X, V)`, for a value-typed `attr` and a variable `V`, is a BINDING:
  -- s(CASP) unifies V with the value and every later goal sees it. L4 has no
  -- logic variables, so the binding is discharged by substitution — V becomes
  -- `the attr of x` at every use — and the goal itself contributes only the
  -- definedness conjunct. The object slot has to be a variable the HEAD binds:
  -- that is what makes the substituted expression well-scoped wherever it
  -- lands.
  valueBindings :: Map BVar Text -> [BGoal] -> [(BVar, Text)]
  valueBindings henv gs =
    [ (v, ident (accessorName d.dclName) <> " " <> ident ov)
    | BGCall True p [BTVar o, BTVar v@(MkBVar vt)] <- gs
    , vt /= "_"
    , Just d <- [valueDeclOf (bNameText p)]
    , Just ov <- [Map.lookup o henv]
    ]

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
  ruleCondition :: Text -> BSectionRef -> Bool -> Map BVar Text -> Map BVar Text -> BGoal -> L [Text]
  ruleCondition who s inapplicable env venv g = do
    t <- liftGoal who env venv g
    case g of
      BGNewObjectCategory _ obj | inapplicable -> do
        o <- liftTerm who env venv obj
        pure [t, callIdent (appliesName s) needsWorld [o]]
      _ -> pure [t]

  defeatPara :: ((BSectionRef, Lit), [(Int, BSectionRef, BOverrule)]) -> L Text
  defeatPara ((s, l), ms) = do
    let world = needsWorld
        hvs = argVars (max 1 l.litArity)
    for_ ms \(_, ws, o) ->
      unless ((overruleLit o.bovDefeatingStmt).litArity == l.litArity) $
        refuse_ "defeat-arity" (renderSectionRef ws)
          ( "the overrules pairs " <> scaspLit (overruleLit o.bovDefeatingStmt)
              <> " with " <> scaspLit l <> ", which take different numbers of "
              <> "arguments, so the defeat has no well-typed L4 image" )
    -- The arm names the DEFEATING section's `holds` decision, which is filed
    -- under the folded section — so the reference has to be folded too, or it
    -- dangles.
    let arms =
          [ callIdent
              (holdsName (foldSec o.bovDefeating) (overruleLit o.bovDefeatingStmt)) world hvs
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
        conds <- traverse (liftGoal (renderSectionRef ws) env mempty) r.burConditions
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
          [channelArm d | l.litSign, Just d <- [declOf l.litPred l.litArity], isNothing d.dclValue]
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
      | ty == "IS A LIST OF (LIST OF STRING)" =
          case [drop 1 as | (l, as) <- sc, fieldKey l == f, take 1 as == [objName]] of
            [] -> "EMPTY"
            ts ->
              "LIST "
                <> Text.intercalate ", "
                     ["(LIST " <> Text.intercalate ", " (map quoted t) <> ")" | t <- ts]
      -- A value-typed attribute's own field. Only a boolean channel can carry
      -- a scenario fact; a binary ground fact over a value attribute has no
      -- lifted image, so the field is absent.
      | otherwise = "NOTHING"

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
            -- __A free-variable query over an EMPTY universe warns rather than
            -- refuses__ (BLAWX-EXPORT-SPEC §11 W5). `?- p(X).` lifts to a
            -- filter over the objects the test runs against, and a document
            -- that declares none -- Blawx's `beard_tax` is one: its single
            -- test is an interview seed, where the Blawx UI asks the user for
            -- the facts -- has nothing to filter. 'testExpr' would refuse it
            -- ("unbound-query"), costing the whole document for the sake of
            -- one unanswerable test, so it is caught here instead.
            <> [ ( "unbound-query-empty-universe"
                 , "the query binds a free variable and the document declares no objects "
                     <> "and asserts no ground facts, so there is nothing for an #EVAL to "
                     <> "range over" )
               | null objectNames
               , null localAtoms
               , gs : _ <- [queries]
               , any freeVarGoal gs
               ]
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

  -- A query goal whose object argument is a free variable.
  freeVarGoal :: BGoal -> Bool
  freeVarGoal = \case
    BGCall True _ [BTVar _] -> True
    BGNewObjectCategory _ (BTVar _) -> True
    BGNegated _ g -> freeVarGoal g
    _ -> False

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
  -- @env@ maps a variable the rule's head or body binds to its L4 name;
  -- @venv@ maps a variable bound by a binary VALUE-attribute goal to the L4
  -- expression that reads it. A variable in @venv@ used in object position is
  -- refused: the flat universe has no name-to-object lookup this phase.
  --
  -- The @Bool@ threaded through @go@ is \"this goal sits under default
  -- negation\". It matters for exactly one shape: a binary attribute goal is a
  -- BINDING only in a positive position. Under @not@ it binds nothing — the
  -- value variable must already be bound elsewhere — so the goal is a TEST of
  -- that value and has to lift to the definedness conjunct AND the equality,
  -- which the surrounding @NOT@ then negates. Reusing the positive image there
  -- turned @not attr(X,V)@ into \"attr is undefined\", dropping the comparison.
  liftGoal :: Text -> Map BVar Text -> Map BVar Text -> BGoal -> L Text
  liftGoal who env venv = go False
   where
    go neg = \case
      BGCall True p [o, v] | Just d <- valueDeclOf (bNameText p) -> binary neg d o v
      BGCall s p as -> call (litOf s p as) as
      BGNewObjectCategory p tm -> call (litOf True p [tm]) [tm]
      BGApplies s tm -> do
        t <- liftTerm who env venv tm
        pure (callIdent (appliesName s) needsWorld [t])
      BGCompare op a b -> do
        lt <- value a
        rt <- value b
        pure (compareText op lt rt)
      -- The one place negation-as-failure earns its keep: the negated
      -- predicate is an INPUT, so "unknown" must behave as "absent", which a
      -- plain NOT over a total BOOLEAN cannot say.
      BGNegated BNegDefault (BGNegated BNegClassical (BGApplies s tm)) -> do
        t <- liftTerm who env venv tm
        pure ("naf (" <> ident (negAppliesName s) <> " " <> t <> ")")
      BGNaf p as -> do
        t <- call (litOf True p as) as
        pure (notOf t)
      BGNegated BNegClassical (BGCall True p as) -> call (litOf False p as) as
      BGNegated BNegDefault g -> notOf <$> go True g
      -- Blawx compares OBJECTS by atom; L4 compares records by value. The
      -- atom is the `name` field, so that is what the two agree on — see the
      -- module header, and W1 on the export side for the same finding read
      -- from the other direction.
      BGDiseq a b -> do
        ta <- liftTerm who env venv a
        tb <- liftTerm who env venv b
        pure ("NOT (" <> ta <> "'s name EQUALS " <> tb <> "'s name)")
      BGUnify a b -> do
        ta <- liftTerm who env venv a
        tb <- liftTerm who env venv b
        pure (ta <> "'s name EQUALS " <> tb <> "'s name")
      g -> refuse "goal-shape" who ("the condition `" <> renderGoal g <> "` has no L4 image this phase")
    -- `attr(X, V)`, for a value-typed `attr`: the object slot is an ordinary
    -- object term. A variable value slot is a binding, already discharged into
    -- @venv@, so all that is left of the goal is definedness; a literal value
    -- slot is a test, and gets the definedness conjunct plus the equality.
    binary neg d o v = case o of
      BTVar ov | not (Map.member ov venv) -> do
        ot <- liftTerm who env venv (BTVar ov)
        let defined = ident d.dclName <> " " <> ot
            accessor = ident (accessorName d.dclName) <> " " <> ot
        case v of
          -- `_` is anonymous on both sides of the polarity: positively it is
          -- \"attr is defined\", negatedly \"attr is undefined\".
          BTVar (MkBVar "_") -> pure defined
          -- Positively, a bound variable is the binding itself, already
          -- discharged into @venv@ by 'valueBindings'; nothing is left but
          -- definedness. Negatedly it is a test against the value @venv@
          -- carries, and falls through to the equality arm below.
          BTVar vn | Map.member vn venv, not neg -> pure defined
          BTVar vn@(MkBVar vt) | not (Map.member vn venv) ->
            refuse "unbound-value" who
              ( "the variable " <> vt <> " sits in the value slot of `"
                  <> d.dclName <> "(X,V)`"
                  <> (if neg then " under `not`, which binds nothing," else "")
                  <> " but is not bound there" )
          _ -> do
            t <- value v
            pure ("(" <> defined <> " AND " <> accessor <> " EQUALS " <> t <> ")")
      _ ->
        refuse "binary-attribute-shape" who
          ( "the object slot of `" <> d.dclName
              <> "(X,V)` must be an object variable the rule binds" )
    -- A term in VALUE position: a literal, or a variable a binary attribute
    -- goal bound.
    value = \case
      BTNum q -> pure (l4Number q)
      BTAtom a -> pure (quoted (bNameText a))
      BTVar v@(MkBVar vt) -> case Map.lookup v venv of
        Just e -> pure e
        Nothing ->
          refuse "unbound-value" who
            ( "the variable " <> vt <> " is compared as a value but no binary "
                <> "attribute goal binds it" )
      t -> refuse "term-shape" who ("the term `" <> renderTerm t <> "` is not a value")
    call l as = do
      ts <- traverse (liftTerm who env venv) as
      pure (callIdent (litIdent l) (litTakesWorld l) ts)

  liftTerm :: Text -> Map BVar Text -> Map BVar Text -> BTerm -> L Text
  liftTerm who env venv = \case
    BTVar v@(MkBVar vt)
      | Map.member v venv ->
          refuse "value-variable-in-object-position" who
            ( "the variable " <> vt <> " is bound to an attribute VALUE, and this "
                <> "goal uses it as an OBJECT; the flat universe has no "
                <> "name-to-object lookup this phase" )
      | otherwise -> case Map.lookup v env of
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

-- | @NOT@ over an already-parenthesised operand, without doubling the
-- brackets. A binary attribute goal under negation lifts to
-- @(p x AND `the p of` x EQUALS v)@, and @\"NOT (\" <> that <> \")\"@ would
-- read @NOT ((… ))@ — valid, and a distraction in an artifact whose whole
-- point is being read.
notOf :: Text -> Text
notOf t
  | wholeParen = "NOT " <> t
  | otherwise = "NOT (" <> t <> ")"
 where
  wholeParen = case Text.uncons t of
    Just ('(', rest) -> Text.length rest > 0 && Text.last rest == ')' && closesAtEnd rest 0
    _ -> False
  -- the opening bracket's partner is the LAST character, not an earlier one:
  -- @(a) AND (b)@ must not be treated as one parenthesised whole.
  closesAtEnd :: Text -> Int -> Bool
  closesAtEnd rest d = case Text.uncons rest of
    Nothing -> False
    Just (')', r)
      | Text.null r -> d == 0
      | d == 0 -> False -- the opening bracket closed early: `(a) AND (b)`
      | otherwise -> closesAtEnd r (d - 1)
    Just ('(', r) -> closesAtEnd r (d + 1)
    Just (_, r) -> closesAtEnd r d

-- | @blawx_comparison(X,op,Y)@ in L4's spelling. There is no disequality
-- operator, so @neq@ is the negation of @EQUALS@ — which is also why it is
-- the only arm that parenthesises: the other five are all at precedence 4,
-- tighter than the @AND@ they are conjoined with.
compareText :: BCmpOp -> Text -> Text -> Text
compareText op l r = case op of
  BEq -> l <> " EQUALS " <> r
  BNeq -> "NOT (" <> l <> " EQUALS " <> r <> ")"
  BGt -> l <> " GREATER THAN " <> r
  BGte -> l <> " AT LEAST " <> r
  BLt -> l <> " LESS THAN " <> r
  BLte -> l <> " AT MOST " <> r

-- | A Blawx @number_value@ as an L4 numeric literal. The field is a JS
-- number, so every value the corpus stores is integral or a terminating
-- decimal; 'L4.Blawx.IR.readRational' turns the latter into a ratio, and a
-- non-integral ratio has no literal spelling in L4 — the exact division does,
-- and is exact.
l4Number :: Rational -> Text
l4Number q
  | denominator q == 1 = Text.textShow (numerator q)
  | otherwise = "(" <> Text.textShow (numerator q) <> " / " <> Text.textShow (denominator q) <> ")"

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
