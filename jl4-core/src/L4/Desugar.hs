module L4.Desugar (
  -- * Caramelize Expressions
  --
  carameliseExpr,
  carameliseNode,
  -- * Computed Fields
  --
  desugarComputedFields,
  detectComputedFieldCycles,
  extractComputedFieldNames,
  -- * Field opening (R5)
  --
  RecordFieldTable,
  recordFieldTable,
  shadowCandidates,
  openFields,
  -- * Type Synonyms
  --
  detectTypeSynonymCycles,
  -- * Section binders
  --
  desugarSectionGivens,
  detectMisattachedSectionGivens,
  collectSectionBinderNames,
  collectSectionBinderDecls,
  detectRestatedSectionBinders,
  ) where


import           Base
import           Data.Graph               (stronglyConnComp, SCC(..))
import qualified Data.Map.Strict          as Map
import qualified Data.Set                 as Set
import           L4.Annotation            (Anno_ (..), HasAnno (..), HasSrcRange (..), clearSourceAnno, emptyAnno, mkHoleWithSrcRangeHint)
import           L4.Names
import           L4.Parser.SrcSpan        (SrcPos (MkSrcPos), SrcRange (MkSrcRange))
import           L4.Syntax
import qualified L4.TypeCheck.Environment as TypeCheck
import           L4.TypeCheck.Types       (CheckEntity (..), EntityInfo)
import           Control.Monad.Writer.Strict (Writer, runWriter, tell)
import Control.Category ((>>>))
import qualified Optics

-- ----------------------------------------------------------------------------
-- Caramelize
-- ----------------------------------------------------------------------------

carameliseExpr :: HasName n => Expr n -> Expr n
carameliseExpr = carameliseExprWithContext InertCtxNone

-- | Caramelize expression with context tracking for inert elements.
-- Inert elements evaluate to the identity for their containing operator:
-- - In AND context: True (AND identity)
-- - In OR context: False (OR identity)
carameliseExprWithContext :: HasName n => InertContext -> Expr n -> Expr n
carameliseExprWithContext ctx = carameliseNode >>> \ case
  Not        ann e -> Not ann (carameliseExprWithContext InertCtxNone e)
  -- For AND/OR, we propagate the context to children
  And        ann e1 e2 -> And       ann (carameliseExprWithContext InertCtxAnd e1) (carameliseExprWithContext InertCtxAnd e2)
  Or         ann e1 e2 -> Or        ann (carameliseExprWithContext InertCtxOr e1) (carameliseExprWithContext InertCtxOr e2)
  RAnd       ann e1 e2 -> RAnd      ann (carameliseExprWithContext InertCtxAnd e1) (carameliseExprWithContext InertCtxAnd e2)
  ROr        ann e1 e2 -> ROr       ann (carameliseExprWithContext InertCtxOr e1) (carameliseExprWithContext InertCtxOr e2)
  Implies    ann e1 e2 -> Implies   ann (carameliseExprWithContext InertCtxNone e1) (carameliseExprWithContext InertCtxNone e2)
  Equals     ann e1 e2 -> Equals    ann (carameliseExprWithContext InertCtxNone e1) (carameliseExprWithContext InertCtxNone e2)
  Plus       ann e1 e2 -> Plus      ann (carameliseExprWithContext InertCtxNone e1) (carameliseExprWithContext InertCtxNone e2)
  Minus      ann e1 e2 -> Minus     ann (carameliseExprWithContext InertCtxNone e1) (carameliseExprWithContext InertCtxNone e2)
  Times      ann e1 e2 -> Times     ann (carameliseExprWithContext InertCtxNone e1) (carameliseExprWithContext InertCtxNone e2)
  DividedBy  ann e1 e2 -> DividedBy ann (carameliseExprWithContext InertCtxNone e1) (carameliseExprWithContext InertCtxNone e2)
  Modulo     ann e1 e2 -> Modulo    ann (carameliseExprWithContext InertCtxNone e1) (carameliseExprWithContext InertCtxNone e2)
  Cons       ann e1 e2 -> Cons      ann (carameliseExprWithContext InertCtxNone e1) (carameliseExprWithContext InertCtxNone e2)
  Leq        ann e1 e2 -> Leq       ann (carameliseExprWithContext InertCtxNone e1) (carameliseExprWithContext InertCtxNone e2)
  Geq        ann e1 e2 -> Geq       ann (carameliseExprWithContext InertCtxNone e1) (carameliseExprWithContext InertCtxNone e2)
  Lt         ann e1 e2 -> Lt        ann (carameliseExprWithContext InertCtxNone e1) (carameliseExprWithContext InertCtxNone e2)
  Gt         ann e1 e2 -> Gt        ann (carameliseExprWithContext InertCtxNone e1) (carameliseExprWithContext InertCtxNone e2)
  Proj       ann e n   -> Proj ann (carameliseExprWithContext InertCtxNone e) n
  Var        ann n     -> Var  ann n
  Lam        ann sig e -> Lam ann sig (carameliseExprWithContext InertCtxNone e)
  App        ann n es  -> App ann n (fmap (carameliseExprWithContext InertCtxNone) es)
  AppNamed   ann n nes morder -> AppNamed ann n (fmap caramliseNamedExpr nes) morder
  IfThenElse ann b t e -> IfThenElse ann (carameliseExprWithContext InertCtxNone b) (carameliseExprWithContext InertCtxNone t) (carameliseExprWithContext InertCtxNone e)
  MultiWayIf ann es e -> MultiWayIf ann (map (\(MkGuardedExpr ann' a b) -> MkGuardedExpr ann' (carameliseExprWithContext InertCtxNone a) (carameliseExprWithContext InertCtxNone b)) es) (carameliseExprWithContext InertCtxNone e)
  Regulative ann o -> Regulative ann (carameliseDeonton o)
  Consider   ann e branches -> Consider ann (carameliseExprWithContext InertCtxNone e) (fmap carameliseBranch branches)
  Lit        ann l -> Lit ann l
  Percent    ann e -> Percent ann (carameliseExprWithContext InertCtxNone e)
  List       ann es -> List ann (fmap (carameliseExprWithContext InertCtxNone) es)
  Where      ann e ds -> Where ann (carameliseExprWithContext ctx e) (fmap carameliseLocalDecl ds)
  LetIn      ann ds e -> LetIn ann (fmap carameliseLocalDecl ds) (carameliseExprWithContext ctx e)
  Event      ann ev -> Event ann (carameliseEvent ev)
  Fetch      ann e -> Fetch ann (carameliseExprWithContext InertCtxNone e)
  Env        ann e -> Env ann (carameliseExprWithContext InertCtxNone e)
  Post       ann e1 e2 e3 -> Post ann (carameliseExprWithContext InertCtxNone e1) (carameliseExprWithContext InertCtxNone e2) (carameliseExprWithContext InertCtxNone e3)
  Record     ann mParty cell val isOfficial mHence -> Record ann (fmap (carameliseExprWithContext InertCtxNone) mParty) (carameliseExprWithContext InertCtxNone cell) (carameliseExprWithContext InertCtxNone val) isOfficial (fmap (carameliseExprWithContext InertCtxNone) mHence)
  ReadCell   ann mParty isOfficial mode cell -> ReadCell ann (fmap (carameliseExprWithContext InertCtxNone) mParty) isOfficial mode (carameliseExprWithContext InertCtxNone cell)
  Concat     ann es -> Concat ann (fmap (carameliseExprWithContext InertCtxNone) es)
  AsString   ann e -> AsString ann (carameliseExprWithContext InertCtxNone e)
  Breach     ann mParty mReason -> Breach ann (fmap (carameliseExprWithContext InertCtxNone) mParty) (fmap (carameliseExprWithContext InertCtxNone) mReason)
  -- The REFUSE message is a string literal and must not be turned into an
  -- 'Inert' node by an enclosing AND/OR context.
  Refuse     ann msg -> Refuse ann (carameliseExprWithContext InertCtxNone msg)
  -- Inert elements: update the context based on the desugaring context.
  -- The evaluator (Machine.hs) will read this context to determine the value.
  Inert      ann txt _oldCtx -> Inert ann txt ctx

carameliseLocalDecl :: HasName n => LocalDecl n -> LocalDecl n
carameliseLocalDecl = \ case
  LocalDecide ann decide -> LocalDecide ann (carameliseDecide decide)
  LocalAssume ann assume -> LocalAssume ann assume

carameliseDecide :: HasName n => Decide n -> Decide n
carameliseDecide = \ case
  MkDecide ann tySig appForm expr ->
    MkDecide ann tySig appForm (carameliseExpr expr)

carameliseBranch :: HasName n => Branch n -> Branch n
carameliseBranch = \ case
  MkBranch ann (When ann' pat) e -> MkBranch ann (When ann' (caramelisePattern pat)) (carameliseExpr e)
  MkBranch ann (Otherwise ann') e -> MkBranch ann (Otherwise ann') (carameliseExpr e)

caramelisePattern :: HasName n => Pattern n -> Pattern n
caramelisePattern = \ case
  PatVar ann n -> PatVar ann n
  PatApp ann n ps -> PatApp ann n (fmap caramelisePattern ps)
  PatCons ann p1 p2 -> PatCons ann (caramelisePattern p1) (caramelisePattern p2)
  PatExpr ann e -> PatExpr ann (carameliseExpr e)
  PatLit ann l -> PatLit ann l

carameliseEvent :: HasName n => Event n -> Event n
carameliseEvent = \ case
  MkEvent { anno, party, action, timestamp, atFirst} ->
    MkEvent
      { anno
      , party = carameliseExpr party
      , action = carameliseExpr action
      , timestamp = carameliseExpr timestamp
      , atFirst
      }

carameliseDeonton :: HasName n => Deonton n -> Deonton n
carameliseDeonton = \ case
  MkDeonton { anno, subject, action, due, join = mjoin, hence, lest} ->
    MkDeonton
      { anno
      , subject = carameliseSubject subject
      , action = carameliseRAction action
      , due = fmap carameliseExpr due
      , join = fmap carameliseJoin mjoin
      , hence = fmap carameliseExpr hence
      , lest = fmap carameliseExpr lest
      }

carameliseJoin :: HasName n => Join n -> Join n
carameliseJoin = \ case
  JoinOnce anno th due -> JoinOnce anno th (fmap carameliseExpr due)
  JoinUpon anno ue due -> JoinUpon anno ue (fmap carameliseExpr due)

carameliseSubject :: HasName n => Subject n -> Subject n
carameliseSubject = \ case
  Party ann party -> Party ann (carameliseExpr party)
  Every ann mCast v mRoll mFilter ->
    Every ann mCast v (fmap carameliseExpr mRoll) (fmap carameliseExpr mFilter)

carameliseRAction :: HasName n => RAction n -> RAction n
carameliseRAction = \ case
  MkAction { anno, modal, action, provided } ->
    MkAction
      { anno
      , modal
      , action
      , provided = fmap carameliseExpr provided
      }

caramliseNamedExpr :: HasName n => NamedExpr n -> NamedExpr n
caramliseNamedExpr = \ case
  MkNamedExpr ann n e -> MkNamedExpr ann n (carameliseExpr e)

-- | We desugar expressions during typechecking, for example, @2 PLUS 3@ is
-- turned into the function @\_\_PLUS\_\_ 2 3@. This is less readable during natural
-- language generation, so we undo some of our desugaring and add the syntactic sugar
-- back.
--
-- We call this process "caramelise". Primarily, because fendor likes caramel,
-- and it feels like a good name for the opposite of "desugaring".
carameliseNode :: HasName n => Expr n -> Expr n
carameliseNode = \ case
  App ann n es
    | Just caramelise <- isBuiltinBinary (rawName $ getName n)
    , [e1, e2] <- es ->
        setAnno ann $ caramelise e1 e2
    | Just caramelise <- isBuiltinUnary (rawName $ getName n)
    , [e1] <- es ->
        setAnno ann $ caramelise e1
  expr -> expr

-- ----------------------------------------------------------------------------
-- Builtins
-- ----------------------------------------------------------------------------

-- | Operations such as Plus and Minus are desugared to prefix function
-- notation.
-- However, we don't want to show the prefix function name
-- but rather the infix version. So, we translate the prefix function
-- notation back to the infix one. In a way, we are undoing the
-- desugaring again.
isBuiltinBinary :: RawName -> Maybe (Expr n -> Expr n -> Expr n)
isBuiltinBinary r =
  Map.lookup (rawNameToText r) builtinBinFunctions

isBuiltinUnary :: RawName -> Maybe (Expr n -> Expr n)
isBuiltinUnary r =
  Map.lookup (rawNameToText r) builtinUnaryFunctions

builtinBinFunctions :: Map Text (Expr n -> Expr n -> Expr n)
builtinBinFunctions = Map.fromList
  [ (rawNameToText $ rawName TypeCheck.plusName, Plus emptyAnno)
  , (rawNameToText $ rawName TypeCheck.minusName, Minus emptyAnno)
  , (rawNameToText $ rawName TypeCheck.timesName, Times emptyAnno)
  , (rawNameToText $ rawName TypeCheck.divideName, DividedBy emptyAnno)
  , (rawNameToText $ rawName TypeCheck.moduloName, Modulo emptyAnno)
  , (rawNameToText $ rawName TypeCheck.ltName, Lt emptyAnno)
  , (rawNameToText $ rawName TypeCheck.leqName, Leq emptyAnno)
  , (rawNameToText $ rawName TypeCheck.gtName, Gt emptyAnno)
  , (rawNameToText $ rawName TypeCheck.geqName, Geq emptyAnno)
  , (rawNameToText $ rawName TypeCheck.andName, And emptyAnno)
  , (rawNameToText $ rawName TypeCheck.orName, Or emptyAnno)
  , (rawNameToText $ rawName TypeCheck.impliesName, Implies emptyAnno)
  , (rawNameToText $ rawName TypeCheck.consName, Cons emptyAnno)
  , (rawNameToText $ rawName TypeCheck.equalsName, Equals emptyAnno)
  ]

builtinUnaryFunctions :: Map Text (Expr n -> Expr n)
builtinUnaryFunctions = Map.fromList
  [ (rawNameToText $ rawName TypeCheck.notName, Not emptyAnno)
  ]

-- ----------------------------------------------------------------------------
-- Desugar Computed Fields
-- ----------------------------------------------------------------------------

-- | Desugar computed fields in DECLARE blocks into synthetic DECIDE declarations.
--
-- For each computed field @f IS A T MEANS expr@ on record @R@, generates:
--
-- @
-- GIVEN _self IS A R
-- GIVETH A T
-- f _self MEANS LET s1 = _self\'s s1; ... IN expr
-- @
--
-- where s1..sN are all sibling fields (excluding f itself).
-- The original DECLARE retains only stored fields (without MEANS clauses).
--
-- __Trap for every post-resolution consumer (backends, exporters, analyses):__
-- this runs BEFORE type checking, so by @Module Resolved@ a computed field has
-- no trace in its 'RecordDecl' — \"the fields of a record\" is the /stored/
-- inventory only, and a projection onto a computed field must be routed to the
-- synthesized selector (an ordinary call, including whatever calling convention
-- the consumer gives calls — e.g. a boolean output-argument drop). Two backends
-- have independently shipped defects by missing this: a dead per-field pathway
-- plus a false \"record has no field\" diagnostic (docassemble M1), and an
-- arity miscompile in the computed-BOOLEAN selector path (L4.Relational M1).
-- The teaching witness is @jl4\/examples\/relational\/computed.l4@, whose golden
-- shows the field stripped from the record and the selector lowered as its own
-- predicate.
desugarComputedFields :: Module Name -> Module Name
desugarComputedFields (MkModule ann imports section) =
  MkModule ann imports (desugarCFSection section)

desugarCFSection :: Section Name -> Section Name
desugarCFSection (MkSection sAnn sMn sMaka sMgiven topDecls) =
  MkSection sAnn sMn sMaka sMgiven (concatMap desugarCFTopDecl topDecls)

desugarCFTopDecl :: TopDecl Name -> [TopDecl Name]
desugarCFTopDecl (Declare dAnn decl) = desugarCFDeclare dAnn decl
desugarCFTopDecl (Section sAnn section) = [Section sAnn (desugarCFSection section)]
desugarCFTopDecl other = [other]

desugarCFDeclare :: Anno -> Declare Name -> [TopDecl Name]
desugarCFDeclare dAnn (MkDeclare declAnn tysig appForm (RecordDecl rAnn mCon tns))
  | any isComputed tns =
    let
      -- Extract type parameters from the DECLARE's GIVEN (e.g., GIVEN a IS A TYPE)
      MkTypeSig _ (MkGivenSig _ typeParams) _ = tysig
      storedFields = [tn | tn@(MkTypedName _ _ _ _mTypically Nothing) <- tns]
      syntheticDecides = mapMaybe (makeComputedDecide appForm typeParams) tns
      newDeclare = Declare dAnn (MkDeclare declAnn tysig appForm (RecordDecl rAnn mCon storedFields))
    in newDeclare : map (uncurry Decide) syntheticDecides
desugarCFDeclare dAnn decl = [Declare dAnn decl]

isComputed :: TypedName n -> Bool
isComputed (MkTypedName _ _ _ _mTypically (Just _)) = True
isComputed _ = False

-- | Generate a synthetic Decide for a computed field.
--
-- For @adult IS A BOOLEAN MEANS age >= 18@ on @DECLARE Person HAS name, age, adult@:
--
-- @
-- GIVEN _self IS A Person
-- GIVETH A BOOLEAN
-- adult _self MEANS _self's age >= 18
-- @
--
-- Bare sibling-field references in the MEANS expression are NOT rewritten
-- here. The synthetic @DECIDE@ has a record-typed @GIVEN@ like any other, and
-- 'openFields' — which runs after this pass over the whole module — opens
-- @_self@'s fields in its body exactly as it opens @p@'s fields in a rule
-- written @GIVEN p IS A Person@. One mechanism (IMPLICIT-PROPS-DESIGN §11.7):
-- until R5 this function carried its own rewrite of the same shape.
makeComputedDecide :: AppForm Name -> [OptionallyTypedName Name] -> TypedName Name -> Maybe (Anno, Decide Name)
makeComputedDecide appForm typeParams (MkTypedName fieldAnn fieldName fieldType _mTypically (Just meansExpr)) =
  let
    -- Extract record name and type args from the DECLARE's AppForm
    MkAppForm _ recordName typeArgs _ = appForm
    -- Create a self parameter name
    selfName = MkName emptyAnno computedSelfName
    -- Build the record type: RecordName arg1 arg2 ...
    recordType = TyApp emptyAnno recordName (map (\n -> TyApp emptyAnno n []) typeArgs)
    -- Type signature: GIVEN <typeParams>, _self IS A <RecordType> GIVETH A <FieldType>
    -- Prepend type parameters from the DECLARE so parameterized types work.
    -- Use the field's annotation to preserve source range info.
    selfParam = MkOptionallyTypedName emptyAnno selfName (Just recordType) Nothing
    decideTypeSig = MkTypeSig fieldAnn
      (MkGivenSig emptyAnno (typeParams ++ [selfParam]))
      (Just (MkGivethSig emptyAnno fieldType))
    -- App form: <fieldName> _self
    decideAppForm = MkAppForm fieldAnn fieldName [selfName] Nothing
  in Just (fieldAnn, MkDecide fieldAnn decideTypeSig decideAppForm meansExpr)
makeComputedDecide _ _ _ = Nothing  -- stored field, no DECIDE needed

-- | The name 'makeComputedDecide' gives a computed field's record parameter.
computedSelfName :: RawName
computedSelfName = NormalName "_self"

-- | Is this @DECIDE@ one 'makeComputedDecide' synthesised for a computed
-- field, rather than something the author wrote?
--
-- It matters to 'openFields': a computed field's body is the body of a
-- @DECLARE@, and a @DECLARE@ is not "the function that declares or sees the
-- binder" of an enclosing section @GIVEN@ (§11.7). Walking it with the
-- section's frames in scope silently rebound a sibling read — measured
-- 2026-09-16, see §11.7.1 "what review changed": a computed field reading a
-- top-level @\`vat rate\` MEANS 7@ started reading @cfg's \`vat rate\`@ merely
-- because an unrelated @§ ... GIVEN cfg IS A Config@ sat above the @DECLARE@.
--
-- The test is the synthesis's own shape: the last @GIVEN@ binder and the sole
-- head argument are both @_self@. An author who writes that shape by hand
-- gets the same (narrower) scope, which is a boundary, not a defect.
isComputedFieldDecide :: Decide Name -> Bool
isComputedFieldDecide (MkDecide _ (MkTypeSig _ (MkGivenSig _ otns) _) (MkAppForm _ _ args _) _) =
  not (null otns)
    && rawName (getName (last otns)) == computedSelfName
    && map rawName args == [computedSelfName]

-- ----------------------------------------------------------------------------
-- Field opening (IMPLICIT-PROPS-DESIGN §11.7, R5)
-- ----------------------------------------------------------------------------

-- | The fields every record type a module can name declares, keyed by the
-- type's spelling (and each @AKA@ alias of it).
--
-- Two sources, unioned: the module's own @DECLARE@s — read off the /parsed/
-- module, so that computed fields are still in their record, before
-- 'desugarComputedFields' moves them out — and the records of every imported
-- module, which the checker knows only through their selectors
-- ('recordFieldTable'). A synonym for a record (@DECLARE Outline IS A RoseTree
-- OF Item@) is not followed: a binder declared at the synonym does not open.
type RecordFieldTable = Map RawName (Set RawName)

-- | The record field table a module is checked against.
--
-- Left-biased, NOT unioned: a record the module declares itself is what a
-- binder written with that spelling resolves to, so its fields are the ones
-- that open. Unioning the two made a local @DECLARE Dictionary HAS label@
-- open the prelude @Dictionary@'s @contents@ as well, and a bare read of
-- @contents@ then elaborated to a projection the checker refused
-- (@expected to be of type Dictionary OF k, v but is here of type
-- Dictionary@) — found in review 2026-09-16, see §11.7.1.
recordFieldTable :: EntityInfo -> Module Name -> RecordFieldTable
recordFieldTable ei m =
  Map.union (recordFieldsDeclared m) (recordFieldsImported ei)

recordFieldsDeclared :: Module Name -> RecordFieldTable
recordFieldsDeclared (MkModule _ _ section) = goSection section
 where
  goSection (MkSection _ _ _ _ decls) = Map.unionsWith Set.union (map goTopDecl decls)
  goTopDecl = \ case
    Declare _ (MkDeclare _ _ (MkAppForm _ recName _ mAka) (RecordDecl _ _ tns)) ->
      let fields = Set.fromList [ rawName fn | MkTypedName _ fn _ _ _ <- tns ]
          spellings = rawName recName : maybe [] (\ (MkAka _ ns) -> map rawName ns) mAka
      in Map.fromList [ (sp, fields) | sp <- spellings ]
    Section _ s -> goSection s
    _ -> Map.empty

-- | The records the checker's environment already knows, read back off their
-- selectors: a @KnownTerm@ of kind 'Selector' or 'ComputedSelector' has the
-- type @FUNCTION FROM R ... TO t@ (quantified over @R@'s parameters), and @R@
-- is the record. This is how a record declared in an imported module opens;
-- it is the selector-side twin of
-- 'L4.TypeCheck.constructorsInScopeFromEntityInfo'.
--
-- Both spellings are taken UNqualified. An entity declared under a section
-- heading is recorded in 'EntityInfo' under its last-registered alias, which
-- is the section-qualified one ('L4.TypeCheck.Types.extendEnv' inserts each
-- alias of one 'Unique' over the previous); the prelude's @Dictionary@ lives
-- under @§§ Dictionaries@, and would otherwise not open at all.
--
-- A spelling more than one /distinct/ record claims contributes nothing. Two
-- imported records with the same unqualified name cannot both be what a
-- binder written with that name resolves to, and unioning their fields opened
-- fields the binder does not have. Not opening is never a meaning change
-- against the pre-R5 tree; guessing is (review 2026-09-16, §11.7.1).
recordFieldsImported :: EntityInfo -> RecordFieldTable
recordFieldsImported ei =
  Map.mapMaybe onlyOneRecord $
    Map.fromListWith (Map.unionWith Set.union)
      [ ( unqualified (rawName (getName r))
        , Map.singleton (getUnique r) (Set.singleton (unqualified (rawName fieldName)))
        )
      | (_, (fieldName, KnownTerm ty kind)) <- Map.toList ei
      , kind == Selector || kind == ComputedSelector
      , Just r <- [selectorRecord ty]
      ]
 where
  onlyOneRecord :: Map Unique (Set RawName) -> Maybe (Set RawName)
  onlyOneRecord byRecord = case Map.elems byRecord of
    [fields] -> Just fields
    _        -> Nothing

  unqualified :: RawName -> RawName
  unqualified (QualifiedName _ n) = NormalName n
  unqualified rn                  = rn

  selectorRecord :: Type' Resolved -> Maybe Resolved
  selectorRecord = \ case
    Forall _ _ t -> selectorRecord t
    Fun _ [MkOptionallyNamedType _ _ (TyApp _ r _)] _ -> Just r
    _ -> Nothing

-- | The names an opened field can outrank silently: 0-ary constructors and
-- 0-ary definitions, from this module and from the import environment.
--
-- This is not the checker's resolution — it cannot be, it runs before the
-- checker — but it is the shape that the rank decides without saying so, and
-- it is what 'L4.TypeCheck.Types.OpenedFieldShadowsDefinition' warns about.
-- Deliberately 0-ary only: an applied head is never opened in the first
-- place, so a function of the same name is not at risk.
shadowCandidates :: EntityInfo -> Module Name -> Map RawName ShadowedByOpening
shadowCandidates ei (MkModule _ _ section) =
  Map.union (goSection section) imported
 where
  imported =
    Map.fromList
      [ (rawName (getName nm), kindOf kind)
      | (_, (nm, KnownTerm ty kind)) <- Map.toList ei
      , kind /= Selector && kind /= ComputedSelector
      , not (isFunctionType ty)
      ]
  kindOf Constructor = ShadowedConstructor
  kindOf _           = ShadowedDefinition

  isFunctionType = \ case
    Forall _ _ t -> isFunctionType t
    Fun {}       -> True
    _            -> False

  goSection (MkSection _ _ _ _ decls) = Map.unions (map goTopDecl decls)
  goTopDecl = \ case
    Section _ s -> goSection s
    Declare _ (MkDeclare _ _ _ (EnumDecl _ conDecls)) ->
      Map.fromList
        [ (rawName (getName cd), ShadowedConstructor)
        | cd@(MkConDecl _ _ tns) <- conDecls
        , null tns
        ]
    Decide _ (MkDecide _ (MkTypeSig _ (MkGivenSig _ otns) _) (MkAppForm _ n args _) _)
      | null otns, null args -> Map.singleton (rawName n) ShadowedDefinition
    Assume _ (MkAssume _ (MkTypeSig _ (MkGivenSig _ otns) _) (MkAppForm _ n args _) _ _)
      | null otns, null args -> Map.singleton (rawName n) ShadowedDefinition
    _ -> Map.empty

-- | One rung of the scope a bare name is resolved against, innermost first.
--
-- A declaration contributes one frame: the names it binds itself (its head,
-- its parameters), and the fields its record-typed @GIVEN@s open. Within a
-- frame a bound name beats an opened field — a binder named like one of its
-- own fields is the binder (the @amount's amount@ style, PROPS-REDTEAM
-- §2.7) — and the definition's own head name is bound too, so a reference to
-- it in its own body is never rewritten to a field of the same name (which is
-- what kept a computed field's own name out of its sibling set before R5, and
-- is why 'makeComputedDecide' no longer has to subtract it). A @WHERE@,
-- @LET@, lambda or @CONSIDER@ branch contributes a frame that only binds.
data Frame =
  MkFrame
    { bound  :: !(Set RawName)
    , opened :: !(Map RawName [OpenedBinderDecl])
      -- ^ In declaration order; more than one binder is a collision.
    , tyvars :: !(Set RawName)
      -- ^ The TYPE parameters this frame's signature quantifies over. A
      -- binder declared at one of them (@GIVEN Box IS A TYPE, x IS A Box@)
      -- is a universally quantified type, never the record that happens to
      -- share the spelling, so it opens nothing.
    , site   :: !OpeningSite
    }

bindingFrame :: Set RawName -> Frame
bindingFrame names = MkFrame names Map.empty Set.empty DeclarationOpening

-- | The frame a signature contributes: its binders, and the fields opened from
-- those of its binders whose declared type is a record in the table.
--
-- Only a binder written with a type opens. An un-annotated @GIVEN x@, or a
-- parameter that appears in the head alone (@f p MEANS ...@), has a type the
-- checker infers later, which this pass cannot see.
-- A binder whose type names a TYPE parameter in scope — this signature's own,
-- or an enclosing one's — opens nothing: it is a universally quantified type
-- variable, and the record that shares its spelling is not what the checker
-- resolves it to.
signatureFrame :: RecordFieldTable -> OpeningSite -> Set RawName -> [RawName] -> [OptionallyTypedName Name] -> Frame
signatureFrame table site outerTyVars extraBound otns =
  MkFrame bound opened tyvars site
 where
  bound = Set.fromList (extraBound <> [ rawName (getName otn) | otn <- otns ])
  tyvars =
    outerTyVars
      <> Set.fromList [ rawName n | MkOptionallyTypedName _ n (Just (Type _)) _ <- otns ]
  opened =
    Map.fromListWith (flip (<>))
      [ (field, [MkOpenedBinderDecl n ty])
      | MkOptionallyTypedName _ n (Just ty) _ <- otns
      , TyApp _ tyName _ <- [ty]
      , not (rawName tyName `Set.member` tyvars)
      , Just fields <- [Map.lookup (rawName tyName) table]
      , field <- Set.toList fields
      , not (field `Set.member` bound)
      ]

-- | Every TYPE parameter a stack of frames has in scope.
tyVarsInScope :: [Frame] -> Set RawName
tyVarsInScope = foldMap (.tyvars)

-- | Two enclosing sections' opened fields are ONE tier of the rank, so they
-- share one frame: a name both open is a collision, not a silent shadow.
-- Binding still beats opening, because 'lookupBare' consults @bound@ first
-- and the merged frame binds both sections' binder names.
mergeSectionFrames :: Frame -> Frame -> Frame
mergeSectionFrames outer inner =
  MkFrame
    { bound  = outer.bound <> inner.bound
    , opened = Map.unionWith (<>) outer.opened inner.opened
    , tyvars = outer.tyvars <> inner.tyvars
    , site   = SectionOpening
    }

-- | The writer 'openFields' runs in: collisions, and the silent-rank warnings.
type Opening = Writer ([OpenedFieldCollision], [OpenedFieldShadow])

-- | What a bare name resolves to under a stack of frames.
data Lookup
  = Unchanged
    -- ^ Bound at some rung before any opened field of that name, or nothing
    -- in the stack knows it: the checker resolves it as it always did.
  | Opened OpenedBinderDecl
  | Collided OpeningSite (NonEmpty OpenedBinderDecl)

lookupBare :: RawName -> [Frame] -> Lookup
lookupBare _ [] = Unchanged
lookupBare n (f : fs)
  | n `Set.member` f.bound = Unchanged
  | otherwise =
      case Map.lookup n f.opened of
        Just [b]       -> Opened b
        Just (b : bs)  -> Collided f.site (b :| bs)
        _              -> lookupBare n fs

-- | Open the fields of record-typed binders inside the bodies that see them.
--
-- The ruling (IMPLICIT-PROPS-DESIGN §11.7, R5). The fields of a record-typed
-- @GIVEN@ — a declaration's own, or a section's — are in scope by bare name
-- within the body that declares or sees the binder, and never in its callees.
-- Rank, innermost first: @WHERE@\/@LET@ locals; the function's own @GIVEN@;
-- fields opened from it; section @GIVEN@s; fields opened from those; and then
-- whatever the checker resolves a bare name to today. A bare occurrence @f@
-- of an opened field of binder @r@ becomes @r's f@ — the same
-- @Proj (App r []) f@ the author could have written, checked and consumed by
-- every backend exactly as if they had. @r's f@ is always available.
--
-- What "bare" means, precisely: an @App n []@ in expression position. An
-- applied head (@f x@, @f OF x@), the label of a projection, a @WITH@ label,
-- and anything inside an @EVENT@, a regulative (@PARTY ... MUST ...@) or an
-- inert element are left alone — the four exclusions the computed-field
-- rewrite this pass replaced always had, kept so that nothing which resolved
-- before R5 resolves differently after it.
--
-- Collisions. When two binders of ONE signature open the same field name, a
-- bare read of it is reported ('OpenedFieldCollision') and elaborated against
-- the first binder so the rest of the module still checks; the caller reports
-- it at the read and at the later binder's declaration. Nothing is reported
-- unless the name is actually read bare: the prelude itself declares
-- @dict1 IS A Dictionary k v, dict2 IS A Dictionary k v@ and reads both
-- explicitly. A field opened at two different rungs is a silent shadow, as the
-- rank says — but NOT between two enclosing sections: every enclosing
-- section's binders share ONE frame, because the ruling's rank has one tier
-- for "fields opened from" section @GIVEN@s, so two nested sections that open
-- the same field name collide rather than shadowing (review 2026-09-16).
--
-- Runs after 'desugarComputedFields', so a computed field's synthetic
-- @GIVEN _self IS A R@ opens its siblings through this pass and no other; the
-- table is nevertheless read off the module BEFORE that pass, so the computed
-- siblings are in it. A synthetic computed-field @DECIDE@ is walked with NO
-- enclosing frames: a @DECLARE@ is not a rule that sees its section's binder,
-- and giving its computed fields the section's opened fields silently changed
-- what a body already in the corpus meant ('isComputedFieldDecide').
--
-- 'shadowCandidates' names what the checker would otherwise have resolved a
-- bare name to — a 0-ary constructor or definition. An opened field that
-- outranks one of those is reported as a warning ('OpenedFieldShadow'); it is
-- not an error, because the rank is what it is, but it is the one silent case
-- of the rank worth saying out loud.
openFields
  :: RecordFieldTable
  -> Map RawName ShadowedByOpening
  -> Module Name
  -> (Module Name, [OpenedFieldCollision], [OpenedFieldShadow])
openFields table shadowed (MkModule mAnn uri sect) =
  let (sect', (collisions, shadows)) = runWriter (goSection [] sect)
  in (MkModule mAnn uri sect', collisions, shadows)
 where
  goSection :: [Frame] -> Section Name -> Opening (Section Name)
  goSection frames (MkSection sAnn mn maka mgiven decls) = do
    let frames' = case mgiven of
          Just (MkGivenSig _ otns) ->
            let inner = signatureFrame table SectionOpening (tyVarsInScope frames) [] otns
            in case frames of
                 -- One tier for every enclosing section, as the rank says.
                 (outer : rest) -> mergeSectionFrames outer inner : rest
                 []             -> [inner]
          Nothing                  -> frames
    MkSection sAnn mn maka mgiven <$> traverse (goTopDecl frames') decls

  goTopDecl :: [Frame] -> TopDecl Name -> Opening (TopDecl Name)
  goTopDecl frames = \ case
    Section a s -> Section a <$> goSection frames s
    Decide a d
      | isComputedFieldDecide d -> Decide a <$> goDecide [] d
      | otherwise               -> Decide a <$> goDecide frames d
    other       -> pure other

  goDecide :: [Frame] -> Decide Name -> Opening (Decide Name)
  goDecide frames (MkDecide dAnn tysig@(MkTypeSig _ (MkGivenSig _ otns) _) af@(MkAppForm _ hd args _) body) = do
    let frame =
          signatureFrame table DeclarationOpening (tyVarsInScope frames)
            (rawName hd : map rawName args) otns
    MkDecide dAnn tysig af <$> go (frame : frames) body

  opened :: Anno -> OpenedBinderDecl -> Name -> Opening (Expr Name)
  opened ann b n = do
    case Map.lookup (rawName n) shadowed of
      Nothing   -> pure ()
      Just what -> tell ([], [MkOpenedFieldShadow n b what])
    pure (projectOn ann b n)

  go :: [Frame] -> Expr Name -> Opening (Expr Name)
  go frames expr = case expr of
    -- Variable/application: elaborate a bare opened field, leave an applied head alone
    App ann n args
      | null args ->
          case lookupBare (rawName n) frames of
            Unchanged   -> pure expr
            Opened b    -> opened ann b n
            Collided site bs@(b :| _) -> do
              tell ([MkOpenedFieldCollision n site (toList bs)], [])
              opened ann b n
      | otherwise ->
          App ann n <$> traverse (go frames) args
    -- Binary operators
    And ann e1 e2       -> And ann <$> go frames e1 <*> go frames e2
    Or ann e1 e2        -> Or ann <$> go frames e1 <*> go frames e2
    RAnd ann e1 e2      -> RAnd ann <$> go frames e1 <*> go frames e2
    ROr ann e1 e2       -> ROr ann <$> go frames e1 <*> go frames e2
    Implies ann e1 e2   -> Implies ann <$> go frames e1 <*> go frames e2
    Equals ann e1 e2    -> Equals ann <$> go frames e1 <*> go frames e2
    Not ann e           -> Not ann <$> go frames e
    Plus ann e1 e2      -> Plus ann <$> go frames e1 <*> go frames e2
    Minus ann e1 e2     -> Minus ann <$> go frames e1 <*> go frames e2
    Times ann e1 e2     -> Times ann <$> go frames e1 <*> go frames e2
    DividedBy ann e1 e2 -> DividedBy ann <$> go frames e1 <*> go frames e2
    Modulo ann e1 e2    -> Modulo ann <$> go frames e1 <*> go frames e2
    Cons ann e1 e2      -> Cons ann <$> go frames e1 <*> go frames e2
    Leq ann e1 e2       -> Leq ann <$> go frames e1 <*> go frames e2
    Geq ann e1 e2       -> Geq ann <$> go frames e1 <*> go frames e2
    Lt ann e1 e2        -> Lt ann <$> go frames e1 <*> go frames e2
    Gt ann e1 e2        -> Gt ann <$> go frames e1 <*> go frames e2
    -- Projection: the record expression, but NOT the label
    Proj ann e n        -> (\ e' -> Proj ann e' n) <$> go frames e
    -- Control flow
    IfThenElse ann c t e -> IfThenElse ann <$> go frames c <*> go frames t <*> go frames e
    MultiWayIf ann gs e ->
      MultiWayIf ann <$> traverse (goGuarded frames) gs <*> go frames e
    Consider ann e bs   -> Consider ann <$> go frames e <*> traverse (goBranch frames) bs
    -- Binding forms push a frame that only binds; each local's own body then
    -- gets its own signature frame on top of that
    Where ann e locals  -> do
      let frames' = bindingFrame (localDeclNames locals) : frames
      Where ann <$> go frames' e <*> traverse (goLocal frames') locals
    LetIn ann locals e  -> do
      let frames' = bindingFrame (localDeclNames locals) : frames
      LetIn ann <$> traverse (goLocal frames') locals <*> go frames' e
    Lam ann sig e       ->
      -- A lambda's parameters bind but do not open (§11.7 says "function"
      -- GIVEN; a lambda declares a binder without being a definition).
      Lam ann sig <$> go (bindingFrame (givenSigNames sig) : frames) e
    -- Containers
    List ann es         -> List ann <$> traverse (go frames) es
    Concat ann es       -> Concat ann <$> traverse (go frames) es
    Percent ann e       -> Percent ann <$> go frames e
    AsString ann e      -> AsString ann <$> go frames e
    -- Named application: the arguments, never the labels
    AppNamed ann n nes order ->
      (\ nes' -> AppNamed ann n nes' order) <$> traverse (goNamed frames) nes
    -- Leaf nodes and everything else: unchanged
    Lit {} -> pure expr
    Fetch ann e         -> Fetch ann <$> go frames e
    Env ann e           -> Env ann <$> go frames e
    Post ann u h b      -> Post ann <$> go frames u <*> go frames h <*> go frames b
    Record ann mp c v off mh ->
      Record ann <$> traverse (go frames) mp <*> go frames c <*> go frames v <*> pure off <*> traverse (go frames) mh
    ReadCell ann mp off mode c ->
      (\ mp' c' -> ReadCell ann mp' off mode c') <$> traverse (go frames) mp <*> go frames c
    Breach ann mp mr    -> Breach ann <$> traverse (go frames) mp <*> traverse (go frames) mr
    Refuse ann msg      -> Refuse ann <$> go frames msg
    Event {}            -> pure expr  -- regulative events are complex; leave as-is
    Regulative {}       -> pure expr  -- regulative rules: leave as-is
    Inert {}            -> pure expr

  -- @r's f@, carrying the bare read's source range on the projection AND on
  -- its record operand, so that a diagnostic on either still points at what
  -- the author wrote. The holes are range-hinted and token-free, as
  -- 'elaborateSectionBinder' explains; the binder /occurrence/ is range-less
  -- (its 'Name' has 'clearSourceAnno' applied) so the read is not recorded as
  -- a reference at the GIVEN line.
  --
  -- TWO holes, as the parser's own projection has (@hole e@, @'s@, @hole n@).
  -- 'flattenConcreteNodes' zips holes against child node-lists positionally
  -- and drops the surplus, so with one hole the label @n@ was never reached:
  -- the type-checked semantic-token pass emitted nothing at the bare read and
  -- the editor left it unhighlighted (review 2026-09-16, witnessed by
  -- @lsp\/semantic-tokens\/field-opening.l4@).
  projectOn :: Anno -> OpenedBinderDecl -> Name -> Expr Name
  projectOn ann b n =
    Proj (Anno mempty (rangeOf ann) [ hole, mkHoleWithSrcRangeHint (rangeOf n) ])
      (Var (Anno mempty (rangeOf ann) [hole]) (clearSourceAnno b.binderName))
      n
   where
    hole = mkHoleWithSrcRangeHint (rangeOf ann)

  goGuarded frames (MkGuardedExpr ann c e) =
    MkGuardedExpr ann <$> go frames c <*> go frames e

  goBranch frames (MkBranch ann lhs e) =
    MkBranch ann lhs <$> go (bindingFrame (branchLhsNames lhs) : frames) e

  goLocal frames (LocalDecide ann d) = LocalDecide ann <$> goDecide frames d
  goLocal _ ld = pure ld  -- LocalAssume: no body

  goNamed frames (MkNamedExpr ann n e) = MkNamedExpr ann n <$> go frames e

  -- Extract names bound by local declarations
  localDeclNames :: [LocalDecl Name] -> Set RawName
  localDeclNames = Set.fromList . map localName
   where
    localName (LocalDecide _ (MkDecide _ _ (MkAppForm _ n _ _) _)) = rawName n
    localName (LocalAssume _ (MkAssume _ _ (MkAppForm _ n _ _) _ _)) = rawName n

  -- Extract names bound by a GIVEN signature
  givenSigNames :: GivenSig Name -> Set RawName
  givenSigNames (MkGivenSig _ otns) =
    Set.fromList [rawName (getName otn) | otn <- otns]

  -- Extract names bound by a branch LHS (pattern)
  branchLhsNames :: BranchLhs Name -> Set RawName
  branchLhsNames (When _ pat) = patternNames pat
  branchLhsNames (Otherwise _) = Set.empty

  -- A 0-ary 'PatApp' binds its name unless it is a constructor; the checker
  -- decides which ('L4.TypeCheck.inferPatternVar'), and this pass cannot, so
  -- it treats the name as bound either way — the choice that leaves a
  -- constructor pattern's body resolving exactly as it did before R5.
  patternNames :: Pattern Name -> Set RawName
  patternNames (PatApp _ n [])   = Set.singleton (rawName n)
  patternNames (PatApp _ _ pats) = Set.unions (map patternNames pats)
  patternNames (PatVar _ n)      = Set.singleton (rawName n)
  patternNames (PatCons _ p1 p2) = patternNames p1 <> patternNames p2
  patternNames _ = Set.empty

-- ----------------------------------------------------------------------------
-- Cycle Detection for Computed Fields
-- ----------------------------------------------------------------------------

-- | Detect cycles in computed field dependencies within DECLARE blocks.
-- Returns a list of @(record type name, cycle of field names)@ for each cycle found.
detectComputedFieldCycles :: Module Name -> [(Name, [Name])]
detectComputedFieldCycles (MkModule _ _ section) = detectCFCSection section

detectCFCSection :: Section Name -> [(Name, [Name])]
detectCFCSection (MkSection _ _ _ _ topDecls) = concatMap detectCFCTopDecl topDecls

detectCFCTopDecl :: TopDecl Name -> [(Name, [Name])]
detectCFCTopDecl (Declare _ decl) = detectCFCDeclare decl
detectCFCTopDecl (Section _ section) = detectCFCSection section
detectCFCTopDecl _ = []

detectCFCDeclare :: Declare Name -> [(Name, [Name])]
detectCFCDeclare (MkDeclare _ _ appForm (RecordDecl _ _ tns))
  | any isComputed tns =
    let
      MkAppForm _ recordName _ _ = appForm
      -- All field names in this record (for filtering references)
      allFieldRawNames = Set.fromList [rawName fn | MkTypedName _ fn _ _ _ <- tns]
      -- Build SCC graph: (node=Name, key=RawName, deps=[RawName])
      graphData =
        [ (fn, rawName fn, Set.toList (exprFieldRefs allFieldRawNames e))
        | MkTypedName _ fn _ _mTypically (Just e) <- tns
        ]
    in [ (recordName, cyc) | CyclicSCC cyc <- stronglyConnComp graphData ]
detectCFCDeclare _ = []

-- | Extract field name references from a MEANS expression.
-- Uses the 'Foldable' instance on 'Expr' to collect all names, then
-- intersects with the set of known field names in the record.
-- This is conservative (may over-approximate) but safe for cycle detection.
exprFieldRefs :: Set RawName -> Expr Name -> Set RawName
exprFieldRefs fieldNames expr =
  Set.fromList [rawName n | n <- toList expr, rawName n `Set.member` fieldNames]

-- ----------------------------------------------------------------------------
-- Cycle Detection for Type Synonyms
-- ----------------------------------------------------------------------------

-- | Detect cycles among the type synonym declarations of a module.
-- Returns the members of each cyclic strongly-connected component.
--
-- A recursive synonym has no finite expansion, so it would otherwise send
-- the type checker's synonym-expanding loops into infinite regress (those
-- loops carry fuel as a backstop, since a cycle can also arrive via
-- imports — see 'L4.TypeCheck.Unify').
--
-- Like 'detectComputedFieldCycles' this matches names textually, which
-- over-approximates references (it is blind to arity and to whether a
-- name would actually resolve to the sibling synonym); a synonym's own
-- type parameters are excluded from its dependencies so that a parameter
-- shadowing a sibling synonym's name cannot manufacture a spurious cycle.
-- A synonym is referenceable through its AKA aliases as well as its
-- primary name, so aliases participate on both sides of the graph.
detectTypeSynonymCycles :: Module Name -> [[Name]]
detectTypeSynonymCycles (MkModule _ _ section) =
  let
    synonyms = synonymsInSection section
    -- alias or primary raw name -> primary raw name. Primary names must
    -- win over aliases (left-biased union): an alias that collides with a
    -- sibling synonym's primary name would otherwise capture that
    -- sibling's references and manufacture a false, declaration-order-
    -- dependent cycle. Name resolution disambiguates such collisions by
    -- arity/kind, which this textual pass cannot see; when it cannot,
    -- the program is ambiguous and rejected anyway, and the expansion
    -- fuel in L4.TypeCheck.Unify remains the termination guarantee.
    primaryName =
      Map.fromList
        [ (rawName n, rawName n) | (n, _, _, _) <- synonyms ]
      `Map.union`
      Map.fromList
        [ (alias, rawName n) | (n, aliases, _, _) <- synonyms, alias <- aliases ]
    graphData =
      [ (n, rawName n, Set.toList deps)
      | (n, _aliases, params, ty) <- synonyms
      , let deps = Set.fromList
              [ primary
              | r <- toList ty
              , not (rawName r `Set.member` params)
              , Just primary <- [Map.lookup (rawName r) primaryName]
              ]
      ]
  in
    [ cyc | CyclicSCC cyc <- stronglyConnComp graphData ]

-- | All type synonym declarations in a section (recursively):
-- name, AKA aliases, type parameters, body.
synonymsInSection :: Section Name -> [(Name, [RawName], Set RawName, Type' Name)]
synonymsInSection (MkSection _ _ _ _ topDecls) = concatMap go topDecls
  where
    go (Declare _ (MkDeclare _ _ (MkAppForm _ n args mAka) (SynonymDecl _ ty))) =
      [(n, akaNames mAka, Set.fromList (rawName <$> args), ty)]
    go (Section _ s) = synonymsInSection s
    go _ = []

    akaNames Nothing              = []
    akaNames (Just (MkAka _ ns))  = rawName <$> ns

-- ----------------------------------------------------------------------------
-- Extract Computed Field Names
-- ----------------------------------------------------------------------------

-- | Extract a map from record type names to their computed field names.
-- Runs on the original program (before desugaring) so computed fields
-- are still visible in the AST.
extractComputedFieldNames :: Module Name -> Map.Map RawName (Set RawName)
extractComputedFieldNames (MkModule _ _ section) = extractCFNSection section

extractCFNSection :: Section Name -> Map.Map RawName (Set RawName)
extractCFNSection (MkSection _ _ _ _ topDecls) =
  Map.unionsWith Set.union (map extractCFNTopDecl topDecls)

extractCFNTopDecl :: TopDecl Name -> Map.Map RawName (Set RawName)
extractCFNTopDecl (Declare _ (MkDeclare _ _ (MkAppForm _ recName _ _) (RecordDecl _ _ tns)))
  | any isComputed tns =
    let cfNames = Set.fromList [rawName fn | MkTypedName _ fn _ _mTypically (Just _) <- tns]
    in Map.singleton (rawName recName) cfNames
extractCFNTopDecl (Section _ section) = extractCFNSection section
extractCFNTopDecl _ = Map.empty

-- ----------------------------------------------------------------------------
-- Section binders (the section-level GIVEN, R4)
-- ----------------------------------------------------------------------------

-- | Elaborate each section-level @GIVEN@ parameter into a synthetic 0-ary
-- @ASSUME@ prepended to that section's declaration list.
--
-- INVARIANT (cited from "L4.Print" and "L4.Export"). In a /parsed/ module a
-- section's 'GivenSig' stands alone. In a /desugared/ module the 'GivenSig' is
-- the declaration of record — it is what 'L4.Print.prettyLayout' re-emits —
-- and, for each of its parameters, there is exactly one 0-ary @ASSUME@ at the
-- head of that section's declaration list bearing the same name: the
-- parameter's /elaboration/. Any pass that drops or replaces an elaboration
-- must drop the matching parameter, or what 'L4.Print.prettyLayout' re-emits
-- stops being a faithful source of the module it holds.
--
-- Why elaborate at all: R3\/R4 rule that a section binder resolves, evaluates
-- and exports exactly as a same-section term @ASSUME@ does. Making the checker
-- literally see an @ASSUME@ in that section buys the resolution rules
-- (nearest-ancestor tiebreak, child shadows ancestor, ambiguity when a parent
-- reaches two children), the @ValAssumed@ evaluation path, the export schema
-- entry and all six backends by construction, instead of by a dozen parallel
-- edits that could each drift from the behaviour they mirror.
--
-- The elaboration is deliberately /token-free/: every annotation it introduces
-- is empty, so no traversal that walks concrete syntax (exact printing,
-- semantic tokens) descends into it and the binder's tokens are emitted once,
-- by the 'GivenSig' the section keeps. The parameter's own 'Name', type and
-- @TYPICALLY@ nodes are reused as-is, so the binder's defining occurrence still
-- carries the source range of the @GIVEN@ line — which is what makes
-- diagnostics, hover and go-to-definition point at the heading's binder rather
-- than at @1:1@.
desugarSectionGivens :: Module Name -> Module Name
desugarSectionGivens (MkModule ann uri sect) = MkModule ann uri (goSection sect)
 where
  goSection :: Section Name -> Section Name
  goSection (MkSection sAnn mn maka mgiven decls) =
    MkSection sAnn mn maka mgiven
      (map elaborateSectionBinder (sectionGivenParams mgiven) <> map goTopDecl decls)

  goTopDecl :: TopDecl Name -> TopDecl Name
  goTopDecl = \ case
    Section a s -> Section a (goSection s)
    other       -> other

-- | The parameters a section's own @GIVEN@ declares (none when it has no
-- @GIVEN@).
sectionGivenParams :: Maybe (GivenSig n) -> [OptionallyTypedName n]
sectionGivenParams = maybe [] (\ (MkGivenSig _ otns) -> otns)

-- | Every name a section-level @GIVEN@ binds anywhere in the module.
--
-- Read off the /parsed/ module, before 'desugarSectionGivens' turns each
-- parameter into an @ASSUME@ and before anything is resolved, because the
-- checker needs it while checking bodies: a @WITH@ site may name a section
-- binder that is not one of the callee's declared parameters
-- ('L4.TypeCheck.supplyAppNamed'), and this is the set that distinguishes such
-- a supply from a misspelt parameter name.
collectSectionBinderNames :: HasName n => Module n -> Set RawName
collectSectionBinderNames (MkModule _ _ sect) = goSection sect
 where
  goSection (MkSection _ _ _ mgiven decls) =
    Set.fromList (sectionGivenNames mgiven)
      <> foldMap goTopDecl decls
  goTopDecl = \ case
    Section _ s -> goSection s
    _           -> Set.empty

-- | Every section binder in the module, by spelling, with the heading path it
-- is declared at and the type it was declared with.
--
-- The same walk as 'collectSectionBinderNames', on the same /parsed/ module and
-- for a related reason: 'L4.TypeCheck.implicitSupply' has to check a @WITH@
-- supply against the binder's declared type, and by the time the elaboration's
-- own body is inferred it is too late for a supply site in an earlier section.
-- Reading the type off the parse is order-independent, because every @DECLARE@
-- in the module is already in scope before any body is checked
-- ('L4.TypeCheck.withScanTypeAndSigEnvironment' scans declarations first).
--
-- Entries stay in declaration order, so two same-spelled binders are offered to
-- the reader in the order the file declares them.
collectSectionBinderDecls :: Module Name -> Map RawName [SectionBinderDecl]
collectSectionBinderDecls (MkModule _ _ sect) = goSection [] sect
 where
  goSection :: [NonEmpty Text] -> Section Name -> Map RawName [SectionBinderDecl]
  goSection path (MkSection _ mname maka mgiven decls) =
    let path' = path <> sectionPathStep mname maka
    in Map.unionsWith (<>)
         ( Map.fromListWith (flip (<>))
             [ ( rawName (getName otn)
               , [MkSectionBinderDecl path' (getName otn) mty]
               )
             | otn@(MkOptionallyTypedName _ _ mty _) <- sectionGivenParams mgiven
             ]
         : [ goSection path' s | Section _ s <- decls ]
         )

-- | The one heading level a section contributes to a section path, spelled as
-- 'L4.TypeCheck.withSectionStack' spells it. An anonymous section contributes
-- nothing, which is likewise what 'withSectionStack' does with one.
sectionPathStep :: Maybe Name -> Maybe (Aka Name) -> [NonEmpty Text]
sectionPathStep Nothing     _    = []
sectionPathStep (Just name) maka =
  [rawNameToText <$> (rawName name :| maybe [] akaRawNames maka)]
 where
  akaRawNames (MkAka _ ns) = fmap rawName ns

-- | One section-binder parameter, as the 0-ary @ASSUME@ that stands for it.
--
-- The @extra@ of the parameter's annotation is carried onto the @ASSUME@ so
-- that a @\@desc@ written above a section-@GIVEN@ parameter reaches
-- 'L4.Export.assumeToParam', which reads the description off exactly this node.
-- The concrete-syntax payload is dropped, for the token-freeness reason given
-- on 'desugarSectionGivens'. The @range@ is NOT: the checker keys a
-- declaration's scanned signature by its annotation's source range
-- ('lookupFunTypeSigByAnno'), and a range-less declaration is a fatal
-- @MissingSrcRangeForDeclaration@. Each parameter has a distinct range, so the
-- keys stay distinct.
--
-- 'rangeOf' on an 'Anno' is computed from its payload, not read off the @range@
-- field, so the range has to be carried by exactly ONE 'AnnoHole'. One, not
-- four: 'flattenConcreteNodes' pairs holes with child node-lists positionally
-- and drops the surplus, so a single hole is filled by the (empty) TypeSig and
-- the reused type and @TYPICALLY@ nodes emit nothing — which is what keeps the
-- elaboration token-free.
elaborateSectionBinder :: OptionallyTypedName Name -> TopDecl Name
elaborateSectionBinder (MkOptionallyTypedName pAnn nm mTy mTypically) =
  Assume (Anno mempty pAnn.range [mkHoleWithSrcRangeHint pAnn.range])
    (MkAssume (Anno pAnn.extra pAnn.range [mkHoleWithSrcRangeHint pAnn.range])
      (MkTypeSig emptyAnno (MkGivenSig emptyAnno []) Nothing)
      (MkAppForm emptyAnno nm [] Nothing)
      mTy
      mTypically)

-- | R2: a declaration's own @GIVEN@ that restates a name a section-level
-- @GIVEN@ already binds.
--
-- After discharge the section binder is a trailing parameter of every
-- definition that reads it, so a same-named parameter of the same declaration
-- would give one name two binders in one body and make the answer depend on
-- which one the resolver picked. The ruling (R2, 2026-09-04) is that this is an
-- error at the declaration and the fix is to delete the restatement: the value
-- then flows, and a genuine per-call variation is written @callee WITH x IS y@.
--
-- Scope, deliberately: only a /declaration's/ signature. A section's own binder
-- lives in a bare 'GivenSig' hanging off the heading, and a lambda's parameters
-- in a bare 'GivenSig' too, so keying on 'TypeSig' picks out exactly the
-- @DECIDE@, @ASSUME@ and @DECLARE@ signatures the ruling is about — including
-- those of @WHERE@ and @LET@ locals, which are function signatures like any
-- other. A lambda parameter that shadows a binder is left alone: it is the
-- residual cost §2.3 records, not a second binder for the name.
--
-- Measured 2026-09-04 across 607 files: 235 term-role @ASSUME@ names and 2,311
-- function @GIVEN@ names, and no file in which the two sets overlap. So this
-- rule costs the corpus nothing; it governs the migration state.
detectRestatedSectionBinders :: Module Name -> [Name]
detectRestatedSectionBinders (MkModule _ _ sect) = goSection Set.empty sect
 where
  -- Scoped to the binders VISIBLE at the declaration: its own section's and
  -- those of its ancestors. Not the whole module.
  --
  -- Keying on the raw name module-wide was over-broad, and the cost stopped
  -- being hypothetical: @doc\/tutorials\/section-given\/what-a-section-needs-to-know.l4@
  -- is a before-and-after tutorial whose \"before\" section deliberately repeats
  -- @annual income@ in each rule's own @GIVEN@, and whose \"after\" section --
  -- a DIFFERENT section, later in the file -- declares it once as a section
  -- @GIVEN@. Nothing there gives one name two binders in one body; the module
  -- merely spells the name in two unrelated places, which is the whole point of
  -- the page.
  goSection visible (MkSection _ _ _ mgiven decls) =
    let visible' = visible <> Set.fromList (sectionGivenNames mgiven)
    in concatMap (goTopDecl visible') decls

  goTopDecl visible = \ case
    Section _ s -> goSection visible s
    d ->
      [ nm
      | MkTypeSig _ (MkGivenSig _ otns) _ <- Optics.toListOf (Optics.gplate @(TypeSig Name)) d
      , MkOptionallyTypedName _ nm _ _ <- otns
      , Set.member (rawName nm) visible
      ]

-- | The dedent hazard of R4, as a diagnosable shape.
--
-- A section binder that a paste or a hand-edit pushes back to column 1 stops
-- being the section's and silently becomes the signature of the declaration
-- below it: the checker rewrites a 0-ary head to take the GIVEN's names as its
-- arguments, so nothing complains. Reported here are the cases where that
-- reading cannot have been meant, because the declaration makes no use of the
-- name anywhere — not in its head, not in its result type, not in its body, and
-- not in another parameter's type.
--
-- The test is deliberately this narrow, in two ways, both of them measured
-- rather than reasoned.
--
-- First, a column-1 @GIVEN@ opening a section is how 736 declarations in this
-- tree spell an ordinary function signature, so flagging a name merely because
-- the /written/ head does not bind it would report every one of them (the
-- checker rewrites a 0-ary head to take the GIVEN's term names as arguments,
-- 'checkTermAppFormTypeSigConsistency'). Hence \"used nowhere at all\".
--
-- Second, only a @DECLARE@ or an @ASSUME@ is considered. Extending the same
-- test to @DECIDE@ was built and measured on 2026-09-04 and reports five
-- existing files — @jl4-core\/libraries\/actus.l4@ (@state@),
-- @legal\/ceo-performance-award.l4@ (@tranche number@),
-- @legal\/sg-succession\/cleanroom-2026-08\/wills-act.l4@ and
-- @family-cases.l4@ (@the will@) and @not-ok\/tc\/sing.l4@ (@p@) — each an
-- ordinary function that simply does not use one of its parameters, which is
-- indistinguishable from a dedented binder and is not this check's business.
-- Restricted to @DECLARE@ and @ASSUME@ the rule fires on no existing file under
-- @jl4\/examples@, @jl4-core\/libraries@ or @doc@.
--
-- The third shape the design names, a column-1 @GIVEN@ followed by another
-- heading, needs no check: it is a parse error already.
--
-- Returns the unused parameter and the heading it sits under.
detectMisattachedSectionGivens :: Module Name -> [(Name, Maybe Name)]
detectMisattachedSectionGivens (MkModule _ _ sect) = goSection sect
 where
  goSection :: Section Name -> [(Name, Maybe Name)]
  goSection (MkSection _ mn _ _ decls) =
    -- Only a section with a heading has a § to indent past; the anonymous root
    -- section's first GIVEN is an ordinary module-level signature.
    (case (mn, decls) of
       (Just _, d : _) -> misattachedIn mn d
       _               -> [])
    <> concat [ goSection s | Section _ s <- decls ]

  misattachedIn :: Maybe Name -> TopDecl Name -> [(Name, Maybe Name)]
  misattachedIn mn d = case typeSigOf d of
    Just (MkTypeSig _ (MkGivenSig gann params@(_ : _)) _)
      | startsAtColumnOne gann ->
          [ (nm, mn)
          | MkOptionallyTypedName _ nm _ _ <- params
          , occurrences (rawName nm) d <= 1
          ]
    _ -> []

  startsAtColumnOne :: Anno -> Bool
  startsAtColumnOne gann = case rangeOf gann of
    Just (MkSrcRange (MkSrcPos _ col) _ _ _) -> col == 1
    Nothing                                  -> False

  -- How many times this raw name occurs anywhere in the declaration. The
  -- parameter's own binding occurrence is one of them, so a name used nowhere
  -- else has a count of exactly one.
  occurrences :: RawName -> TopDecl Name -> Int
  occurrences rn d = length [ () | n <- toList d, rawName n == rn ]

  -- DECIDE is deliberately absent; see the note above.
  typeSigOf :: TopDecl Name -> Maybe (TypeSig Name)
  typeSigOf = \ case
    Declare _ (MkDeclare _ tysig _ _)   -> Just tysig
    Assume  _ (MkAssume  _ tysig _ _ _) -> Just tysig
    _                                   -> Nothing
