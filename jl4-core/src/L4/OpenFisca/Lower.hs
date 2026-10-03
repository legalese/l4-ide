-- | Lower a typechecked L4 module to the OpenFisca 'OFPackage' IR.
--
-- v1 scope (see specs): the @\@export@-annotated @DECIDE@/@MEANS@ subset over a
-- /subject/ parameter (a @DECLARE@ record → the OpenFisca entity) and an
-- optional conventional @period@ parameter. Stored record fields and free
-- scalar parameters become input variables; the decision body becomes a
-- formula. Deontic/regulative/IO constructs, recursion, list/collection inputs,
-- and general function application are rejected with a diagnostic — they are not
-- expressible as OpenFisca variables.
module L4.OpenFisca.Lower
  ( lowerModule
  , LowerError (..)
  , renderLowerError
  ) where

import Base
import Control.Applicative ((<|>))
import Data.Char (isAlphaNum, isDigit, toLower)
import Data.Either (partitionEithers)
import Data.Ratio (denominator)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text

import Optics ((^.))

import L4.Annotation (getAnno)
import L4.Export (ExportedFunction (..), getExportedFunctions)
import L4.Interchange.Typically (DefaultValue (..), classifyDefault, describeDefault)
import L4.OpenFisca.IR
import L4.Syntax
import L4.TypeCheck.Environment (emptyUnique, nothingUnique)

-- | A reason a decision could not be compiled to OpenFisca.
data LowerError = LowerError
  { errFn  :: !Text  -- ^ the offending decision (empty = module-level)
  , errMsg :: !Text
  }
  deriving stock (Eq, Show)

renderLowerError :: LowerError -> Text
renderLowerError e
  | Text.null e.errFn = e.errMsg
  | otherwise         = "in `" <> e.errFn <> "`: " <> e.errMsg

-- | Records reachable in the module, keyed by their L4 type name.
data RecordInfo = RecordInfo
  { riKey    :: !Text
  , riPlural :: !Text
  , riPy     :: !Text
  , riFields :: ![FieldInfo]
  }

-- | A field of a record. @fiListElem = Just R@ marks a @LIST OF R@ field, which
-- makes the owning record a /group entity/ whose members are @R@s.
data FieldInfo = FieldInfo
  { fiName     :: !Text
  , fiL4       :: !Text  -- ^ original (un-sanitised) field name
  , fiType     :: !OFType
  , fiStored   :: !Bool
  , fiListElem :: !(Maybe Text)
  , fiDefault  :: !(Maybe (Expr Resolved))
    -- ^ the field's @TYPICALLY@, if it wrote one. It becomes the input
    -- variable's @default_value@ (see 'lowerDefault'); OpenFisca has a default
    -- for every variable, so dropping it would assert a different one.
  }

lowerModule :: Module Resolved -> Either [LowerError] OFPackage
lowerModule mod' =
  case getExportedFunctions mod' of
    []  -> Left [LowerError "" "no @export-annotated DECIDE found to compile to OpenFisca"]
    efs ->
      let (enumDefs, enumCons) = collectEnums mod'
          records      = collectRecords enumDefs mod'
          scaleParams  = collectScaleParams mod'
          scalarParams = collectScalarParams mod'
          scalePaths   = Map.map (.spPath) scaleParams
          scalarPaths  = Map.map (.spsPath) scalarParams
          exportedU   = Map.fromList
            [ (getUnique (decideName ef.exportDecide), pyIdent ef.exportName)
            | ef <- efs
            ]
          results    = map (lowerOne enumDefs enumCons records exportedU scalePaths scalarPaths) efs
          (errs, ok) = partitionEithers results
      in if not (null errs)
           then Left errs
           else case checkCollisions enumDefs (concatMap snd ok) of
             Left e     -> Left [e]
             Right vars ->
               Right OFPackage
                 { pkgSource     = moduleSource mod'
                 , pkgEntities   = dedupOn (.entPy) (concatMap fst ok)
                 , pkgVariables  = vars
                 , pkgParameters = Map.elems scaleParams
                 , pkgScalars    = Map.elems scalarParams
                 , pkgEnums      = Map.elems enumDefs
                 }

-- | Lower a single exported decision into the entity it lives on plus the
-- variables it introduces (its inputs + the computed variable itself).
lowerOne
  :: Map Text OFEnumDef
  -> Map Unique (Text, Text)  -- ^ enum constructors: unique → (class, member)
  -> Map Text RecordInfo
  -> Map Unique Text          -- ^ exported decisions: unique → variable name
  -> Map Unique Text          -- ^ scale parameters: unique → dotted path
  -> Map Unique Text          -- ^ scalar parameters: unique → dotted path
  -> ExportedFunction
  -> Either LowerError ([OFEntity], [OFVariable])
lowerOne enums enumCons records exportedU scalePaths scalarPaths ef = do
  let MkDecide _ (MkTypeSig _ (MkGivenSig _ givens) mGiveth) (MkAppForm _ fnRes _ _) body = ef.exportDecide
      fnName  = pyIdent ef.exportName
      mSubj   = firstJust [ (g, ri) | g <- givens, ri <- maybeToList (givenRecord records g) ]
      mSubjRi = snd <$> mSubj
      mPeriod = find isPeriodGiven givens
      subjU   = (getUnique . givenName . fst) <$> mSubj
      periodU = (getUnique . givenName) <$> mPeriod
      subjUs  = maybeToList subjU
      periodUs = maybeToList periodU
      others  = [ g | g <- givens
                    , getUnique (givenName g) `notElem` (subjUs <> periodUs) ]
      ent     = maybe defaultEntity recordEntity mSubjRi
      ofPeriod = if isJust mPeriod then OFMonth else OFEternity
      -- Member (person) entities reached via the subject's @LIST OF R@ fields.
      memberRecords  = maybe [] (\ri -> mapMaybe (`Map.lookup` records)
                                          (mapMaybe (.fiListElem) ri.riFields)) mSubjRi
      memberEntities = map recordEntity memberRecords
      subjListFields = maybe [] (\ri -> [ fi.fiName | fi <- ri.riFields, isJust fi.fiListElem ]) mSubjRi

  let env = LowerEnv
        { envSubject    = subjU
        , envPeriod     = periodU
        , envMember     = Nothing
        , envScales     = scalePaths
        , envScalarParams = scalarPaths
        , envScalars    = Map.fromList [ (getUnique (givenName g), pyIdent (givenText g)) | g <- others ]
        , envExported   = exportedU
        , envListFields = subjListFields
        , envEnumCons   = enumCons
        }
  (undatedF, datedF) <- mapLeft (LowerError fnName) (lowerBody env body)

  -- Stored scalar (non-list) fields of an entity-record become input variables.
  -- A field's @TYPICALLY@ is mapped onto the variable's own default, or refused
  -- by 'lowerDefault': OpenFisca gives every variable one, so a default left
  -- unmapped would be replaced by the type's (@0.0@, @False@, the first member).
  let mkInput ent' fi0 = do
        let ty0 = fi0.fiType
        (ty, dflt, formula) <- case fi0.fiDefault of
          Nothing -> Right (ty0, Nothing, Nothing)
          Just e  -> mapLeft (LowerError fnName . (("the field `" <> fi0.fiL4 <> "`: ") <>))
                             (lowerDefault env ty0 e)
        pure OFVariable
            { varName    = fi0.fiName
            , varL4      = fi0.fiL4
            , varType    = ty
            , varEntity  = ent'.entPy
            , varEntKey  = ent'.entKey
            , varPeriod  = ofPeriod
            , varLabel   = fi0.fiName
            , varFormula = formula
            , varDated   = []
            , varDefault = dflt
            }
      inputsFor e ri = do
        -- A @LIST OF R@ field is a role, not an input variable, so 'mkInput' never
        -- sees it and cannot refuse its default: this is where that is decided.
        -- A role has no default list. @EMPTY@ says what a role nobody fills
        -- already is, so it is accepted; anything else would be lost, so it is
        -- refused.
        forM_ [ (fi, d) | fi <- ri.riFields, isJust fi.fiListElem
                        , Just d <- [fi.fiDefault], not (isEmptyList d) ] \(fi, d) ->
          Left (LowerError fnName
            ("the field `" <> fi.fiL4 <> "` is a LIST OF records and carries TYPICALLY "
             <> describeDefault (classifyDefault d) <> ", and OpenFisca turns it into a role, "
             <> "which has no default list (only EMPTY, which is what a role nobody fills already "
             <> "is, can be written there)"))
        traverse (mkInput e) [ fi | fi <- ri.riFields, fi.fiStored, isNothing fi.fiListElem ]
  subjectInputs <- maybe (Right []) (inputsFor ent) mSubjRi
  memberInputs  <- concat <$> sequence (zipWith inputsFor memberEntities memberRecords)
  -- The subject and the period are not inputs, so a default written on either
  -- has nothing to attach to. Refuse it rather than lose it.
  forM_ givens \g -> when (isJust (givenDefault g) &&
                           (Just (getUnique (givenName g)) `elem` [subjU, periodU])) $
    Left (LowerError fnName
      ("the GIVEN `" <> givenText g <> "` carries a TYPICALLY, but it is the "
       <> (if Just (getUnique (givenName g)) == subjU then "subject entity" else "period")
       <> ", which OpenFisca supplies from the simulation and not from an input variable"))
  scalarInputs <- forM others \g -> do
    let ty0 = maybe OFFloat (ofTypeOf enums) (givenType g)
        isList = maybe False isListType (givenType g)
    (ty, dflt, formula) <- case givenDefault g of
      Nothing -> Right (ty0, Nothing, Nothing)
      -- A LIST OF GIVEN is the twin of a LIST OF field above: OpenFisca has no
      -- list-valued variable, so a default list has nowhere to go. @EMPTY@ says
      -- nothing a variable without a default does not already say, so it is
      -- accepted and changes nothing in the output; any other default would be
      -- lost, so it is refused, naming the GIVEN. (Without this arm @EMPTY@ was
      -- lowered as an expression and refused as an unbound reference.)
      Just e
        | isList, isEmptyList e -> Right (ty0, Nothing, Nothing)
        | isList ->
            Left (LowerError fnName
              ("the GIVEN `" <> givenText g <> "` is a LIST and carries TYPICALLY "
               <> describeDefault (classifyDefault e) <> ", and OpenFisca has no list-valued "
               <> "variable to put a default on (only EMPTY, which says nothing, is accepted)"))
        | otherwise ->
            mapLeft (LowerError fnName . (("the GIVEN `" <> givenText g <> "`: ") <>))
                    (lowerDefault env ty0 e)
    pure OFVariable
      { varName    = pyIdent (givenText g)
      , varL4      = givenText g
      , varType    = ty
      , varEntity  = ent.entPy
      , varEntKey  = ent.entKey
      , varPeriod  = ofPeriod
      , varLabel   = givenText g
      , varFormula = formula
      , varDated   = []
      , varDefault = dflt
      }
  let
      computed =
        OFVariable
          { varName    = fnName
          , varL4      = resolvedToText fnRes
          , varType    = maybe OFFloat (ofTypeFromGiveth enums) mGiveth
          , varEntity  = ent.entPy
          , varEntKey  = ent.entKey
          , varPeriod  = ofPeriod
          , varLabel   = if Text.null ef.exportDescription
                           then resolvedToText fnRes
                           else ef.exportDescription
          , varFormula = Just undatedF
          , varDated   = datedF
          , varDefault = Nothing
          }
  pure (ent : memberEntities, subjectInputs <> memberInputs <> scalarInputs <> [computed])

-- ---------------------------------------------------------------------------
-- Expression lowering
-- ---------------------------------------------------------------------------

data LowerEnv = LowerEnv
  { envSubject    :: !(Maybe Unique)     -- ^ the subject (entity) parameter
  , envPeriod     :: !(Maybe Unique)     -- ^ the conventional period parameter
  , envMember     :: !(Maybe Unique)     -- ^ the lambda-bound member var, inside an aggregation
  , envScales     :: !(Map Unique Text)  -- ^ scale-parameter values → dotted path
  , envScalarParams :: !(Map Unique Text)  -- ^ scalar-parameter values → dotted path
  , envScalars    :: !(Map Unique Text)  -- ^ free scalar params → input-variable names
  , envExported   :: !(Map Unique Text)  -- ^ exported decisions → variable names
  , envListFields :: ![Text]             -- ^ the subject's @LIST OF@ field names (roles)
  , envEnumCons   :: !(Map Unique (Text, Text))  -- ^ enum constructor → (class, member)
  }

lowerExpr :: LowerEnv -> Expr Resolved -> Either Text OFExpr
lowerExpr env = go
 where
  go = \case
    And _ a b       -> OFAnd <$> go a <*> go b
    Or  _ a b       -> OFOr  <$> go a <*> go b
    Not _ a         -> OFNot <$> go a
    Equals _ a b    -> OFCmp OFEq  <$> go a <*> go b
    Leq _ a b       -> OFCmp OFLeq <$> go a <*> go b
    Geq _ a b       -> OFCmp OFGeq <$> go a <*> go b
    Lt  _ a b       -> OFCmp OFLt  <$> go a <*> go b
    Gt  _ a b       -> OFCmp OFGt  <$> go a <*> go b
    Plus _ a b      -> OFBin OFAdd <$> go a <*> go b
    Minus _ a b     -> OFBin OFSub <$> go a <*> go b
    Times _ a b     -> OFBin OFMul <$> go a <*> go b
    DividedBy _ a b -> OFBin OFDiv <$> go a <*> go b
    Modulo _ a b    -> OFBin OFMod <$> go a <*> go b
    IfThenElse _ c t e -> OFCond <$> go c <*> go t <*> go e
    Percent _ a     -> (\x -> OFBin OFDiv x (OFNum 100)) <$> go a
    Lit _ (NumericLit _ r) -> Right (OFNum r)
    Lit _ (StringLit _ t)  -> Right (OFStrLit t)
    Proj _ inner field -> lowerProj inner field
    App _ ref args     -> lowerApp ref args
    Consider _ scrut branches -> lowerConsider scrut branches
    MultiWayIf _ guards oth   -> lowerMultiWay guards oth
    other -> Left (unsupported other)

  -- @p's field@: on the subject → a variable read; on a member (inside an
  -- aggregation lambda) → a member-array read.
  lowerProj inner field = case inner of
    App _ s [] | Just (getUnique s) == env.envSubject ->
      Right (OFVarRef (pyIdent (resolvedToText field)))
    App _ s [] | Just (getUnique s) == env.envMember ->
      Right (OFMembersVar (pyIdent (resolvedToText field)))
    App _ s [] | Just (getUnique s) == env.envPeriod ->
      Right (OFPeriodField (pyIdent (resolvedToText field)))  -- period's year → period.start.year
    _ -> Left "only projection off the subject, a member, or the period is supported (nested records are a later milestone)"

  -- After resolution L4 desugars operators to builtin applications
  -- (@a * b@ → @App __TIMES__ [a, b]@), so arithmetic/boolean/comparison ops
  -- arrive here rather than as 'Times'/'And'/… constructors.
  lowerApp ref args =
    let u  = getUnique ref
        nm = resolvedToText ref
        -- specialised recognisers, each returning Maybe (Either Text OFExpr)
        recognised = scaleCall nm args <|> aggregation nm args <|> npFunc nm args
    in case recognised of
      Just res -> res
      Nothing -> case builtinOp nm of
        Just mk -> traverse go args >>= mk
        Nothing
          | Just b <- boolLit nm                      -> Right (OFBoolLit b)
          -- a scalar legislation parameter, read by period (args ignored)
          | Just path <- Map.lookup u env.envScalarParams -> Right (OFParamRef path)
          -- a call to another @export decision: on a member (inside an
          -- aggregation) it reads that member's variable; otherwise the entity's.
          | Just name <- Map.lookup u env.envExported ->
              Right $ case args of
                (App _ x [] : _) | Just (getUnique x) == env.envMember -> OFMembersVar name
                _                                                      -> OFVarRef name
          | not (null args)                           -> Left ("cannot compile call to `" <> nm <> "` — OpenFisca formulas take no arguments; only references to other @export decisions are supported")
          | Just name <- Map.lookup u env.envScalars  -> Right (OFVarRef name)
          | Just u == env.envPeriod                   -> Right (OFLocal "period")
          | Just u == env.envSubject                  -> Left "the subject entity cannot be used as a value"
          | otherwise                                 -> Left ("unbound reference `" <> nm <> "` (recursion, prelude functions, and local bindings are not supported in v1)")

  -- numpy elementwise functions reachable as plain L4 calls.
  npFunc nm args = case nm of
    "max" -> Just (OFNpCall "maximum" <$> traverse go args)
    "min" -> Just (OFNpCall "minimum" <$> traverse go args)
    _     -> Nothing

  -- Marginal-rate scale application. @scale tax OF <income>, <scaleRef>@ where
  -- <scaleRef> is a @desc scale <path>@ value → @parameters(period).<path>.calc(<income>)@.
  scaleCall nm args = case args of
    -- the scale ref may be nullary (single-period) or applied to a year
    -- (time-varying); either way OpenFisca resolves the brackets by period.
    [income, App _ sref _scaleArgs]
      | nm == "scale tax"
      , Just path <- Map.lookup (getUnique sref) env.envScales ->
          Just (OFScaleCalc path <$> go income)
    _ -> Nothing

  -- Group-entity aggregations over a member list:
  --   sum (map (GIVEN m YIELD <body>) <members>) → <group>.sum(<body>[, role=…])
  --   any (GIVEN m YIELD <pred>) <members>        → <group>.any(<pred>[, role=…])
  --   all (GIVEN m YIELD <pred>) <members>        → <group>.all(<pred>[, role=…])
  --   count <members>                             → <group>.nb_persons([role])
  -- where <members> is `h's <role>` (role-restricted) or `members of OF h` (all).
  aggregation nm args = case (nm, args) of
    ("sum",   [mapApp])    -> Just (aggSum mapApp)
    ("count", [lst])       -> Just (aggCount lst)
    ("any",   [lam, lst])  -> Just (aggPred OFAny lam lst)
    ("all",   [lam, lst])  -> Just (aggPred OFAll lam lst)
    _                      -> Nothing

  aggSum = \case
    App _ mref [Lam _ (MkGivenSig _ [mp]) lbody, lst]
      | resolvedToText mref == "map"
      , Just role <- resolveMembers lst ->
          OFSum role <$> lowerMember mp lbody
    _ -> Left "`sum` is only supported as `sum (map (GIVEN m YIELD …) (<members>))`"

  aggCount lst = case resolveMembers lst of
    Just role -> Right (OFNbPersons role)
    Nothing   -> Left "`count` expects a member list (`h's <role>` or `members of` OF h)"

  aggPred mk lam lst = case lam of
    Lam _ (MkGivenSig _ [mp]) pbody
      | Just role <- resolveMembers lst -> mk role <$> lowerMember mp pbody
    _ -> Left "`any`/`all` expect `(GIVEN m YIELD <pred>) (<members>)`"

  lowerMember mp body =
    lowerExpr (env { envMember = Just (getUnique (givenName mp)) }) body

  -- Resolve a member-list expression to a role selection: @Just Nothing@ = all
  -- members; @Just (Just role)@ = that role; @Nothing@ = not a member list.
  -- A subject with a single role list treats it as "all members".
  resolveMembers = \case
    Proj _ (App _ s []) fieldRes
      | Just (getUnique s) == env.envSubject
      , let fld = pyIdent (resolvedToText fieldRes)
      , fld `elem` env.envListFields ->
          Just (if length env.envListFields <= 1 then Nothing else Just (singularize fld))
    App _ ref [App _ s []]
      | Just (getUnique s) == env.envSubject
      , resolvedToText ref == "members of" -> Just Nothing
    _ -> Nothing

  boolLit t = case Text.toLower t of
    "true"  -> Just True
    "false" -> Just False
    _       -> Nothing

  -- @CONSIDER scrut WHEN C1 THEN v1 … OTHERWISE d@ over an enum becomes nested
  -- @np.where(scrut == Class.c1, v1, …, d)@.
  lowerConsider scrut branches = do
    scrutE <- go scrut
    let whens  = [ (con, body) | MkBranch _ (When _ (PatApp _ con [])) body <- branches ]
        others = [ body        | MkBranch _ (Otherwise _) body            <- branches ]
    def <- case others of
      (d : _) -> go d
      []      -> Left "CONSIDER without an OTHERWISE is not supported for OpenFisca"
    arms <- traverse (lowerArm scrutE) whens
    pure (foldr (\(c, v) acc -> OFCond c v acc) def arms)

  lowerArm scrutE (con, body) = case Map.lookup (getUnique con) env.envEnumCons of
    Just (cls, mem) -> (\v -> (OFCmp OFEq scrutE (OFEnumLit cls mem), v)) <$> go body
    Nothing -> Left ("CONSIDER: `" <> resolvedToText con <> "` is not an enum constructor (only enum CONSIDER is supported)")

  -- A general @BRANCH IF c THEN v … OTHERWISE d@ → nested @np.where@.
  lowerMultiWay guards oth = do
    d <- go oth
    arms <- traverse (\(MkGuardedExpr _ c b) -> (,) <$> go c <*> go b) guards
    pure (foldr (\(c, v) acc -> OFCond c v acc) d arms)

-- | The builtin operators L4 desugars infix syntax into. Returns a combiner
-- that consumes the already-lowered argument expressions.
builtinOp :: Text -> Maybe ([OFExpr] -> Either Text OFExpr)
builtinOp nm = case nm of
  "__PLUS__"    -> Just (bin OFAdd)
  "__MINUS__"   -> Just (bin OFSub)
  "__TIMES__"   -> Just (bin OFMul)
  "__DIVIDE__"  -> Just (bin OFDiv)
  "__MODULO__"  -> Just (bin OFMod)
  "__EQUALS__"  -> Just (cmp OFEq)
  "__LEQ__"     -> Just (cmp OFLeq)
  "__GEQ__"     -> Just (cmp OFGeq)
  "__LT__"      -> Just (cmp OFLt)
  "__GT__"      -> Just (cmp OFGt)
  "__AND__"     -> Just (logic2 OFAnd)
  "__OR__"      -> Just (logic2 OFOr)
  "__NOT__"     -> Just notOp
  "__IMPLIES__" -> Just impliesOp     -- a ⇒ b  ≡  (¬a) ∨ b
  _             -> Nothing
 where
  bin op   = \case [a, b] -> Right (OFBin op a b); xs -> arity 2 xs
  cmp op   = \case [a, b] -> Right (OFCmp op a b); xs -> arity 2 xs
  logic2 f = \case [a, b] -> Right (f a b);        xs -> arity 2 xs
  notOp    = \case [a]    -> Right (OFNot a);       xs -> arity 1 xs
  impliesOp = \case [a, b] -> Right (OFOr (OFNot a) b); xs -> arity 2 xs
  arity :: Int -> [OFExpr] -> Either Text OFExpr
  arity n xs = Left ("operator `" <> nm <> "` expected " <> tshow n <> " argument(s), got " <> tshow (length xs))

unsupported :: Expr Resolved -> Text
unsupported e = "unsupported construct for OpenFisca: " <> constructorName e

-- | A short human label for the rejected node.
constructorName :: Expr Resolved -> Text
constructorName = \case
  Regulative{} -> "deontic/regulative rule (PARTY/MUST/MAY)"
  Event{}      -> "EVENT"
  Fetch{}      -> "FETCH"; Post{} -> "POST"; Env{} -> "environment lookup"
  Breach{}     -> "BREACH"
  RAnd{}       -> "regulative AND"; ROr{} -> "regulative OR"
  Implies{}    -> "IMPLIES"
  Consider{}   -> "CONSIDER / pattern match (later milestone)"
  MultiWayIf{} -> "multi-way IF (later milestone)"
  Where{}      -> "WHERE binding (later milestone)"
  LetIn{}      -> "LET binding (later milestone)"
  Lam{}        -> "lambda"
  List{}       -> "list literal (collections are a later milestone)"
  Cons{}       -> "list cons (collections are a later milestone)"
  Concat{}     -> "string concat"; AsString{} -> "string coercion"
  AppNamed{}   -> "named-argument application"
  Inert{}      -> "inert scaffolding"
  -- Explicit, ABOVE the wildcard: without this a refusal is rejected as a
  -- nameless "expression" and the author cannot tell what was refused.
  Refuse{}     -> "REFUSE (a refusal has no OpenFisca form: a variable always returns a value)"
  _            -> "expression"

-- ---------------------------------------------------------------------------
-- Module scanning helpers
-- ---------------------------------------------------------------------------

collectRecords :: Map Text OFEnumDef -> Module Resolved -> Map Text RecordInfo
collectRecords enums (MkModule _ _ section) = Map.fromList (goSection section)
 where
  goSection (MkSection _ _ _ _ decls) = decls >>= goDecl
  goDecl = \case
    Declare _ (MkDeclare _ _ (MkAppForm _ recRes _ _) (RecordDecl _ _ fields)) ->
      let nm = resolvedToText recRes
      in [(nm, RecordInfo
              { riKey    = Text.toLower (pyIdent nm)
              , riPlural = Text.toLower (pyIdent nm) <> "s"
              , riPy     = pyType nm
              , riFields =
                  -- 4th slot of 'MkTypedName' is the TYPICALLY default, the 5th a
                  -- computed field's MEANS body. Reading the 4th as the MEANS body
                  -- made every defaulted field look computed, so it never became an
                  -- input variable while the formulas that read it still named it.
                  [ fieldInfo enums fRes fTy mDefault mMeans
                  | MkTypedName _ fRes fTy mDefault mMeans <- fields
                  ]
              })]
    Section _ sub -> goSection sub
    _ -> []

-- | Scan for values annotated @\@desc scale <dotted.path>@ and read their
-- bracket tables. Returns a map keyed by the value's 'Unique' so that a
-- @scale tax@ call referencing the value can resolve its path.
collectScaleParams :: Module Resolved -> Map Unique OFScaleParam
collectScaleParams (MkModule _ _ section) = Map.fromList (goSection section)
 where
  goSection (MkSection _ _ _ _ decls) = decls >>= goDecl
  goDecl = \case
    Decide _ d@(MkDecide _ _ (MkAppForm _ nameRes _ _) body)
      | Just path <- scaleAnnotation d
      , Just bs   <- readScale body ->
          [(getUnique nameRes, OFScaleParam { spPath = path, spBrackets = bs })]
    Section _ sub -> goSection sub
    _ -> []

-- | The dotted path from a @<keyword> a.b.c@ description annotation.
descKeyword :: Text -> Decide Resolved -> Maybe Text
descKeyword kw d = do
  desc <- getAnno d ^. annDesc
  case Text.words (getDesc desc) of
    (w : rest) | w == kw, not (null rest) -> Just (Text.intercalate "." rest)
    _                                     -> Nothing

scaleAnnotation, paramAnnotation :: Decide Resolved -> Maybe Text
scaleAnnotation = descKeyword "scale"
paramAnnotation = descKeyword "parameter"

-- | Scan @\@desc parameter <path>@ scalar legislation parameters. Their bodies
-- are a constant, a @IF y AT LEAST Y THEN v ELSE v0@, or a year-keyed BRANCH.
collectScalarParams :: Module Resolved -> Map Unique OFScalarParam
collectScalarParams (MkModule _ _ section) = Map.fromList (goSection section)
 where
  goSection (MkSection _ _ _ _ decls) = decls >>= goDecl
  goDecl = \case
    Decide _ d@(MkDecide _ _ (MkAppForm _ nameRes _ _) body)
      | Just path <- paramAnnotation d
      , Just vs   <- readScalarParam body ->
          [(getUnique nameRes, OFScalarParam { spsPath = path, spsValues = vs })]
    Section _ sub -> goSection sub
    _ -> []

-- | Read a scalar parameter body into a date-indexed value series.
readScalarParam :: Expr Resolved -> Maybe [(Text, Rational)]
readScalarParam = \case
  Lit _ (NumericLit _ v) -> Just [(epochDate, v)]
  IfThenElse _ cond thenE elseE -> do
    y  <- guardYear cond
    tv <- litNum thenE
    ev <- litNum elseE
    pure [(epochDate, ev), (isoYM y 1, tv)]
  MultiWayIf _ guards oth -> do
    arms <- traverse scalarArm guards
    guard (strictlyDescDates (map fst arms))   -- first-match must equal latest-date
    ov   <- litNum oth
    pure ((epochDate, ov) : arms)
  _ -> Nothing
 where
  scalarArm (MkGuardedExpr _ cond body) = do
    y <- guardYear cond
    v <- litNum body
    pure (isoYM y 1, v)
  litNum = \case Lit _ (NumericLit _ v) -> Just v; _ -> Nothing

-- | Read a scale body into dated brackets. Two shapes:
--
--   * @LIST (band OF t, r), …@                       — a single-period scale
--     (all values dated at a neutral epoch).
--   * @BRANCH IF y AT LEAST <year> THEN LIST … …@    — a time-varying scale; each
--     arm's @year@ becomes the effective date and brackets are aligned by index.
readScale :: Expr Resolved -> Maybe [OFBracket]
readScale = \case
  List _ elems -> do
    rows <- traverse readRow elems
    pure [ OFBracket [(epochDate, t)] [(epochDate, r)] | (t, r) <- rows ]
  MultiWayIf _ guards otherwise' -> do
    arms    <- traverse readArm guards
    othRows <- readOtherwiseRows otherwise'
    -- arms as written must be strictly descending by date: L4 BRANCH is
    -- first-match, OpenFisca resolves by latest date — they agree only so.
    guard (strictlyDescDates (map fst arms))
    -- the OTHERWISE brackets apply before the earliest dated arm.
    let allArms = arms <> [(epochDate, othRows)]
    -- a bracket may appear over time but must not vanish (OpenFisca can't drop one).
    guard (nonShrinking allArms)
    pure (alignByIndex allArms)
  _ -> Nothing
 where
  readOtherwiseRows = \case
    List _ es -> traverse readRow es
    _         -> Just []   -- EMPTY / nil → no pre-dated brackets

-- | As-written dates strictly decreasing (so first-match == latest-date).
strictlyDescDates :: [Text] -> Bool
strictlyDescDates ds = and (zipWith (>) ds (drop 1 ds))

-- | In ascending date order, the per-arm element count is non-decreasing.
nonShrinking :: [(Text, [a])] -> Bool
nonShrinking arms =
  let counts = map (length . snd) (sortOn fst arms)
  in and (zipWith (<=) counts (drop 1 counts))

-- | @band OF threshold, rate@ → (threshold, rate). Name-agnostic: any 2-arg
-- application of numeric literals (the bracket constructor).
readRow :: Expr Resolved -> Maybe (Rational, Rational)
readRow = \case
  App _ _ [Lit _ (NumericLit _ t), Lit _ (NumericLit _ r)] -> Just (t, r)
  _ -> Nothing

-- | One @IF y AT LEAST <year> THEN LIST …@ arm → (effective date, bracket rows).
readArm :: GuardedExpr Resolved -> Maybe (Text, [(Rational, Rational)])
readArm (MkGuardedExpr _ cond body) = do
  yr   <- guardYear cond
  rows <- case body of
    List _ es -> traverse readRow es
    _         -> Nothing
  pure (isoDate yr, rows)

-- | Pull the year from a @y AT LEAST <year>@ / @y >= <year>@ guard.
guardYear :: Expr Resolved -> Maybe Integer
guardYear = \case
  App _ ref [_, Lit _ (NumericLit _ y)]
    | resolvedToText ref `elem` ["__GEQ__", "__GT__"] -> Just (round y)
  _ -> Nothing

isoDate :: Integer -> Text
isoDate y = tshow y <> "-01-01"

-- | Align brackets across arms by position: bracket /i/ collects (date, value)
-- from every arm that has an /i/-th bracket, dates ascending. A bracket that
-- only appears in later years (e.g. a new top band) gets only those dates.
alignByIndex :: [(Text, [(Rational, Rational)])] -> [OFBracket]
alignByIndex arms =
  let sorted = sortOn fst arms
      width  = maximum (0 : map (length . snd) arms)
  in [ OFBracket
         { brThreshold = [ (d, fst (rows !! i)) | (d, rows) <- sorted, i < length rows ]
         , brRate      = [ (d, snd (rows !! i)) | (d, rows) <- sorted, i < length rows ]
         }
     | i <- [0 .. width - 1]
     ]

-- | The date a single-period (non-time-varying) scale's values take effect.
epochDate :: Text
epochDate = "1900-01-01"

-- | Lower a decision body, splitting a top-level @BRANCH IF period reaches …@
-- into an undated @formula@ (the OTHERWISE) plus dated @formula_YYYY_MM@ arms.
lowerBody :: LowerEnv -> Expr Resolved -> Either Text (OFExpr, [(Text, OFExpr)])
lowerBody env body = case splitDated body of
  Just (arms, oth)
    | strictlyDescDates (map fst arms) ->
        (,) <$> lowerExpr env oth
            <*> traverse (\(d, b) -> (,) d <$> lowerExpr env b) arms
    | otherwise ->
        Left "dated-formula BRANCH arms must be in strictly-descending date order \
             \(OpenFisca selects the latest formula by date, but L4 BRANCH is first-match)"
  Nothing -> (\b -> (b, [])) <$> lowerExpr env body

-- | Recognise a dated-formula BRANCH: every arm guarded by @period reaches@.
splitDated :: Expr Resolved -> Maybe ([(Text, Expr Resolved)], Expr Resolved)
splitDated (MultiWayIf _ guards oth) = do
  arms <- traverse datedArm guards
  pure (arms, oth)
splitDated _ = Nothing

datedArm :: GuardedExpr Resolved -> Maybe (Text, Expr Resolved)
datedArm (MkGuardedExpr _ cond body) = do
  (y, m) <- periodReaches cond
  pure (isoYM y m, body)

-- | @period reaches OF period, <year>, <month>@ → (year, month).
periodReaches :: Expr Resolved -> Maybe (Integer, Integer)
periodReaches = \case
  App _ ref [_period, Lit _ (NumericLit _ y), Lit _ (NumericLit _ m)]
    | resolvedToText ref == "period reaches" -> Just (round y, round m)
  _ -> Nothing

isoYM :: Integer -> Integer -> Text
isoYM y m = tshow y <> "-" <> pad m <> "-01"
 where
  pad n = (if n < 10 then "0" else "") <> tshow n

fieldInfo
  :: Map Text OFEnumDef -> Resolved -> Type' Resolved
  -> Maybe (Expr Resolved)  -- ^ the TYPICALLY default
  -> Maybe (Expr Resolved)  -- ^ the MEANS body of a computed field
  -> FieldInfo
fieldInfo enums fRes fTy mDefault mMeans =
  case listElemRecord fTy of
    Just elemName -> FieldInfo nm l4 OFFloat             stored (Just elemName) mDefault
    Nothing       -> FieldInfo nm l4 (ofTypeOf enums fTy) stored Nothing mDefault
 where
  l4     = resolvedToText fRes
  nm     = pyIdent l4
  stored = isNothing mMeans

-- | Scan @DECLARE X IS ONE OF a, b, …@ enum declarations. Returns the enum defs
-- keyed by L4 type name, plus a map from each constructor's 'Unique' to its
-- (Python enum class, Python member) — used to lower @CONSIDER@.
collectEnums :: Module Resolved -> (Map Text OFEnumDef, Map Unique (Text, Text))
collectEnums (MkModule _ _ section) =
  ( Map.fromList [ (ty, ed) | (ty, ed, _)  <- defs ]
  , Map.fromList (concat   [ cs | (_, _, cs) <- defs ])
  )
 where
  defs = goSection section
  goSection (MkSection _ _ _ _ decls) = decls >>= goDecl
  goDecl = \case
    Declare _ (MkDeclare _ _ (MkAppForm _ tyRes _ _) (EnumDecl _ conDecls)) ->
      let ty      = resolvedToText tyRes
          enPy    = pyType ty
          members = [ (pyIdent (resolvedToText c), resolvedToText c)      | MkConDecl _ c _ <- conDecls ]
          cons    = [ (getUnique c, (enPy, pyIdent (resolvedToText c)))   | MkConDecl _ c _ <- conDecls ]
      in [(ty, OFEnumDef { enName = enPy, enMembers = members }, cons)]
    Section _ sub -> goSection sub
    _ -> []

-- | If a type is @LIST OF <Record>@, return the element record's name.
listElemRecord :: Type' Resolved -> Maybe Text
listElemRecord (TyApp _ lname [inner])
  | Text.toLower (resolvedToText lname) `elem` ["list", "listof"] = typeRecordName inner
listElemRecord _ = Nothing

-- | A stable, human-friendly provenance string for the file header: the
-- source file's basename (so output does not depend on the invocation path).
moduleSource :: Module Resolved -> Text
moduleSource (MkModule _ uri _) =
  let t = getUri (fromNormalizedUri uri)
  in case reverse (Text.splitOn "/" t) of
       (base : _) | not (Text.null base) -> base
       _                                 -> t

defaultEntity :: OFEntity
defaultEntity = OFEntity
  { entKey = "person", entPlural = "persons", entPy = "Person"
  , entLabel = "Person", entIsPerson = True, entRoles = [] }

-- | Turn a record into an OpenFisca entity. A record with @LIST OF R@ fields is
-- a /group entity/ (one role per such field); otherwise it is the person entity.
recordEntity :: RecordInfo -> OFEntity
recordEntity ri =
  let listFields = [ fi | fi <- ri.riFields, isJust fi.fiListElem ]
  in OFEntity
       { entKey      = ri.riKey
       , entPlural   = ri.riPlural
       , entPy       = ri.riPy
       , entLabel    = ri.riPy
       , entIsPerson = null listFields
       , entRoles    = map fieldRole listFields
       }

-- | A @LIST OF R@ field becomes a role: plural = the field name, key = its
-- (naive) singular, so @adults@ → role @adult@ (constant @Entity.ADULT@).
fieldRole :: FieldInfo -> OFRole
fieldRole fi = OFRole
  { roleKey    = singularize fi.fiName
  , rolePlural = fi.fiName
  , roleLabel  = fi.fiName
  }

singularize :: Text -> Text
singularize t = case Text.unsnoc t of
  Just (pre, 's') | not (Text.null pre) -> pre
  _                                     -> t

-- ---------------------------------------------------------------------------
-- GIVEN parameter helpers
-- ---------------------------------------------------------------------------

givenName :: OptionallyTypedName Resolved -> Resolved
givenName (MkOptionallyTypedName _ r _ _) = r

givenType :: OptionallyTypedName Resolved -> Maybe (Type' Resolved)
givenType (MkOptionallyTypedName _ _ ty _) = ty

givenText :: OptionallyTypedName Resolved -> Text
givenText = resolvedToText . givenName

givenDefault :: OptionallyTypedName Resolved -> Maybe (Expr Resolved)
givenDefault (MkOptionallyTypedName _ _ _ d) = d

isPeriodGiven :: OptionallyTypedName Resolved -> Bool
-- Detect the conventional period parameter by its raw L4 name (not the
-- keyword-safe pyIdent, which would rename @period@ → @period_@).
isPeriodGiven g = Text.toLower (Text.strip (givenText g)) == "period"

-- | If a GIVEN's type names a known record, return that record (it is a subject).
givenRecord :: Map Text RecordInfo -> OptionallyTypedName Resolved -> Maybe RecordInfo
givenRecord records g = do
  ty <- givenType g
  nm <- typeRecordName ty
  Map.lookup nm records

typeRecordName :: Type' Resolved -> Maybe Text
typeRecordName (TyApp _ name _) = Just (resolvedToText name)
typeRecordName _                = Nothing

-- ---------------------------------------------------------------------------
-- TYPICALLY
-- ---------------------------------------------------------------------------

-- | Map a @TYPICALLY@ default onto the OpenFisca variable it is written on.
--
-- __OpenFisca always has a default__, so this either maps or refuses; there is
-- no "say so and carry on" for a backend whose target will write its own
-- presumption (@0.0@, @False@, the first enum member) into the module the
-- moment the source's is left out (TYPICALLY-ONE-BEHAVIOUR-SPEC ruling T5, and
-- T5b: "OpenFisca maps every default ... it refuses only what it cannot map").
--
-- The result is the variable's (possibly adjusted) type, a literal
-- @default_value@, and a formula; exactly one of the last two is 'Just' unless
-- the default is the enum's first member, which needs neither.
--
-- * A literal of the variable's own type becomes @default_value@. An enum
--   constructor becomes the enum's default member, replacing the first declared
--   one that 'ofTypeOf' would otherwise have written.
-- * An expression becomes a @formula@ on the input variable. OpenFisca computes
--   a variable's formula only for a period the simulation left without an input
--   value, so a supplied input overrides it, which is what a default means.
--   The checker does not accept an expression default today (R8 rule 3 is
--   unbuilt), so this arm is reached only once it does; it reuses the decision
--   bodies' lowering, so anything that lowering refuses is refused here too.
-- * Anything else — @NOTHING@, a literal whose type is not the variable's —
--   is refused with the reason, because there is no OpenFisca value for it.
lowerDefault :: LowerEnv -> OFType -> Expr Resolved -> Either Text (OFType, Maybe OFDefault, Maybe OFExpr)
lowerDefault env ty e = case (classified, ty) of
  (DefNumber r, OFFloat) -> Right (ty, Just (OFDefNum r), Nothing)
  (DefNumber r, OFInt)
    | denominator r == 1 -> Right (ty, Just (OFDefNum r), Nothing)
    | otherwise ->
        Left ("TYPICALLY " <> described <> " is not a whole number, and this variable is an integer")
  (DefBool b, OFBool) -> Right (ty, Just (OFDefBool b), Nothing)
  (DefString t, OFStr) -> Right (ty, Just (OFDefStr t), Nothing)
  (DefConstructor c, OFEnum cls _) -> case Map.lookup (getUnique c) env.envEnumCons of
    Just (cls', member) | cls' == cls -> Right (OFEnum cls member, Nothing, Nothing)
    _ -> Left ("TYPICALLY " <> described <> " is not a member of the enum `" <> cls <> "`")
  (DefComputed ex, _) -> (\f -> (ty, Nothing, Just f)) <$> lowerExpr env ex
  (d, _) -> Left ("TYPICALLY " <> describeDefault d <> " has no OpenFisca value: "
                  <> reason d)
 where
  -- 'classifyDefault' calls every nullary application a constructor, because the
  -- AST does not tell @NOTHING@ or an enum member from a reference to another
  -- input, which has exactly that shape and which R8 rule 3 (W7) admits as a
  -- default. The checker tells them apart through its entity map; here the
  -- constructors this module knows are the enum members and @NOTHING@, and a
  -- nullary application of anything else is the expression it is, which becomes
  -- a formula like any other expression default.
  classified = case classifyDefault e of
    DefConstructor c
      | getUnique c /= nothingUnique
      , not (Map.member (getUnique c) env.envEnumCons) -> DefComputed e
    d -> d
  described = describeDefault classified
  reason = \case
    DefConstructor _ -> "OpenFisca has no way to say a variable has no value; every variable has one"
    _                -> "it is not a " <> typeName <> ", which is what this variable holds"
  typeName = case ty of
    OFFloat  -> "number"
    OFInt    -> "whole number"
    OFBool   -> "boolean"
    OFStr    -> "string"
    OFEnum{} -> "member of an enum"

-- | @EMPTY@, the one nullary list constructor.
isEmptyList :: Expr Resolved -> Bool
isEmptyList = \case
  App _ r [] -> getUnique r == emptyUnique
  _          -> False

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

ofTypeFromGiveth :: Map Text OFEnumDef -> GivethSig Resolved -> OFType
ofTypeFromGiveth enums (MkGivethSig _ ty) = ofTypeOf enums ty

ofTypeOf :: Map Text OFEnumDef -> Type' Resolved -> OFType
ofTypeOf enums = \case
  TyApp _ name _ ->
    let nm = resolvedToText name
    in case Map.lookup nm enums of
         Just ed | ((m, _) : _) <- ed.enMembers -> OFEnum ed.enName m
         _ -> case Text.toLower nm of
           t | t `elem` ["number", "float", "double", "money", "decimal"] -> OFFloat
             | t `elem` ["int", "integer"]                                -> OFInt
             | t `elem` ["boolean", "bool"]                               -> OFBool
             | t `elem` ["string", "text"]                                -> OFStr
           _ -> OFFloat
  _ -> OFFloat

-- | @LIST OF x@, for any @x@.
isListType :: Type' Resolved -> Bool
isListType (TyApp _ lname [_]) = Text.toLower (resolvedToText lname) `elem` ["list", "listof"]
isListType _                   = False

-- ---------------------------------------------------------------------------
-- Name helpers
-- ---------------------------------------------------------------------------

decideName :: Decide Resolved -> Resolved
decideName (MkDecide _ _ (MkAppForm _ r _ _) _) = r

resolvedToText :: Resolved -> Text
resolvedToText = rawNameToText . rawName . getActual

-- | Sanitise an L4 name into a snake_case Python identifier. Must be a total,
-- deterministic function: the same L4 name always yields the same identifier so
-- variable definitions and references stay in sync.
pyIdent :: Text -> Text
pyIdent raw =
  let cleaned = Text.map (\c -> if isIdentChar c then toLower c else ' ') raw
      parts   = Text.words cleaned
      joined  = Text.intercalate "_" parts
  in keywordSafe (ensureNonDigit (if Text.null joined then "v" else joined))
 where
  isIdentChar c = isAlphaNum c || c == '_'
  ensureNonDigit t = case Text.uncons t of
    Just (h, _) | isDigit h -> "v_" <> t
    _                       -> t
  keywordSafe t
    | t `Set.member` pyReserved = t <> "_"
    | otherwise                 = t

-- | Python keywords (plus the formula-local names @period@/@parameters@/@entity@/
-- @formula@) that a variable name must not shadow; such names get a @_@ suffix.
pyReserved :: Set Text
pyReserved = Set.fromList
  [ "and","as","assert","async","await","break","class","continue","def","del"
  , "elif","else","except","false","finally","for","from","global","if","import"
  , "in","is","lambda","nonlocal","none","not","or","pass","raise","return","true"
  , "try","while","with","yield","match","case"
  , "period","parameters","entity","formula" ]

-- | A Python class/variable name for a type, preserving case (e.g. @Person@).
pyType :: Text -> Text
pyType raw =
  let cleaned = Text.map (\c -> if isAlphaNum c || c == '_' then c else '_') raw
  in case Text.uncons cleaned of
       Just (h, _) | isDigit h -> "T_" <> cleaned
       Nothing                 -> "T"
       _                       -> cleaned

-- ---------------------------------------------------------------------------
-- Small utilities
-- ---------------------------------------------------------------------------

tshow :: Show a => a -> Text
tshow = Text.pack . show

firstJust :: [a] -> Maybe a
firstJust = listToMaybe

mapLeft :: (e -> e') -> Either e a -> Either e' a
mapLeft f = either (Left . f) Right

dedupOn :: Ord k => (a -> k) -> [a] -> [a]
dedupOn key = go Set.empty
 where
  go _ [] = []
  go seen (x : xs)
    | k `Set.member` seen = go seen xs
    | otherwise           = x : go (Set.insert k seen) xs
    where k = key x

-- | OpenFisca variable names are global, so distinct L4 definitions that
-- sanitise to the same Python identifier would silently conflate (or, worse,
-- drop a formula). Reject that. Exact duplicates — the same field read by
-- several decisions — are collapsed to one.
checkCollisions :: Map Text OFEnumDef -> [OFVariable] -> Either LowerError [OFVariable]
checkCollisions enums vs =
  case [ (nm, grp) | (nm, grp) <- Map.toList byName, length (nub (map effective grp)) > 1 ] of
    ((nm, grp0) : _)
      -- The same input read by several exported decisions is one variable; if
      -- they disagree only about its default, there is no single default to
      -- write, and picking one would silently make the others wrong. "Disagree"
      -- means the variable would DIFFER in OpenFisca: a decision that writes no
      -- TYPICALLY gets OpenFisca's own default for the type, so @TYPICALLY 0@
      -- against none is not a disagreement and @TYPICALLY 3@ against none is.
      | (g0 : gs) <- nubBy (\a b -> effective a == effective b) (reverse grp0)
      , all (sameApartFromDefault g0) gs ->
          Left $ LowerError ""
            ( "`" <> nm <> "` is an input of more than one exported decision, and they give it "
            <> "different TYPICALLY defaults (" <> Text.intercalate " and " (map defaultText (g0 : gs))
            <> (if any ((== "none") . defaultText) (g0 : gs)
                  then ", where none means that decision writes no TYPICALLY, and OpenFisca then "
                       <> "gives the input its own default for its type: 0.0, False, '' or the first "
                       <> "member of the enum"
                  else "")
            <> "). OpenFisca has one variable of that name, and so one default for it: "
            <> "make the decisions agree, or rename one." )
      | otherwise ->
      Left $ LowerError ""
        ( "name collision: distinct L4 definitions ("
        <> Text.intercalate ", " [ "`" <> v.varL4 <> "`" | v <- nub grp0 ]
        <> ") both compile to the OpenFisca variable `" <> nm
        <> "`. A decision, field, or parameter that shares a (sanitised) name "
        <> "with another is unsafe in OpenFisca — rename one." )
    [] -> Right (dedupOn (.varName) (map prefer vs))
 where
  byName = Map.fromListWith (<>) [ (v.varName, [v]) | v <- vs ]

  -- Variables that agree once each is given the default OpenFisca would give it
  -- are one variable. Of such a group the artifact carries the one that WROTE a
  -- default, so the generated class says what the source said.
  best = Map.mapMaybe (\grp -> find (isJust . (.varDefault)) (reverse grp) <|> listToMaybe (reverse grp)) byName
  prefer v = fromMaybe v (Map.lookup v.varName best)

  -- The default a variable has in OpenFisca: what was written, else its own.
  -- (An enum's is carried in its type, which already holds the member.)
  effective v = v { varDefault = effectiveDefault v }
  effectiveDefault v = case v.varDefault of
    Just d -> Just d
    Nothing
      | isJust v.varFormula -> Nothing
      | otherwise -> case v.varType of
          OFFloat  -> Just (OFDefNum 0)
          OFInt    -> Just (OFDefNum 0)
          OFBool   -> Just (OFDefBool False)
          OFStr    -> Just (OFDefStr "")
          OFEnum{} -> Nothing

  -- Two variables that are the same input apart from the default each carries.
  sameApartFromDefault a b = bare a == bare b
  bare v = v { varDefault = Nothing, varType = bareType v.varType }
  bareType = \case OFEnum cls _ -> OFEnum cls ""; t -> t

  defaultText v = case (v.varDefault, v.varFormula, v.varType) of
    (Just (OFDefNum r), _, _)  -> describeDefault (DefNumber r)
    (Just (OFDefBool b), _, _) -> if b then "TRUE" else "FALSE"
    (Just (OFDefStr t), _, _)  -> "\"" <> t <> "\""
    (_, Just _, _)             -> "a computed default"
    -- An enum's default is its member, written or not: the first declared
    -- member is also what a decision that writes nothing gets, so it is said so.
    (_, _, OFEnum cls m)
      | isFirstMember cls m    -> cls <> "." <> m <> " (the first member, which is also what no TYPICALLY gives)"
      | otherwise              -> cls <> "." <> m
    _                          -> "none"

  isFirstMember cls m = case Map.lookup cls enums of
    Just ed | ((m0, _) : _) <- ed.enMembers -> m0 == m
    _                                       -> False
