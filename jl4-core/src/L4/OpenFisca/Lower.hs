-- | Lower a typechecked L4 module to the OpenFisca 'OFPackage' IR.
--
-- Scope: the @\@export@-annotated @DECIDE@/@MEANS@ subset over a /subject/
-- parameter (a @DECLARE@ record → the OpenFisca entity) and an optional
-- conventional @period@ parameter. Stored record fields and free scalar
-- parameters become input variables; the decision body becomes a formula.
-- A record with a @LIST OF <record>@ field becomes a group entity whose members
-- are reached through the aggregations @sum@ / @count@ / @any@ / @all@.
-- Values annotated @\@desc parameter <path>@ / @\@desc scale <path>@ become
-- OpenFisca legislation parameters.
--
-- __The rule this module keeps:__ anything the lowering does not fully
-- understand is a 'LowerError' that says what is unsupported and what to do
-- instead. It never falls back to a guess. A guess is how a construct slightly
-- outside the examples used to compile with exit 0 and return a different
-- number from L4 (a @>@ read as @>=@, a call's arguments dropped, a
-- @CONSIDER@ arm dropped, a @DATE@ field emitted as a float). Deontic,
-- regulative and IO constructs, recursion, local bindings, nested records and
-- general function application are all refused.
module L4.OpenFisca.Lower
  ( lowerModule
  , LowerError (..)
  , renderLowerError
  ) where

import Base
import Data.Char (isAlphaNum, isAsciiLower, isAsciiUpper, isDigit, toLower)
import Data.Either (partitionEithers)
import qualified Data.Map.Strict as Map
import Data.Ratio (denominator, numerator)
import qualified Data.Set as Set
import qualified Data.Text as Text

import Optics ((^.))

import L4.Annotation (getAnno)
import L4.Export (ExportedFunction (..), enrichReturnTypes, getExportedFunctions)
import L4.OpenFisca.IR
import L4.Syntax
import L4.TypeCheck.Environment
  ( booleanUnique, emptyUnique, falseUnique, listUnique, numberUnique
  , stringUnique, trueUnique )
import L4.TypeCheck.Environment.TH (builtinUri)
import L4.TypeCheck.Types (EntityInfo)

-- | A reason a decision could not be compiled to OpenFisca.
data LowerError = LowerError
  { errFn  :: !Text  -- ^ the offending decision or parameter (empty = module-level)
  , errMsg :: !Text
  }
  deriving stock (Eq, Show)

renderLowerError :: LowerError -> Text
renderLowerError e
  | Text.null e.errFn = e.errMsg
  | otherwise         = "in `" <> e.errFn <> "`: " <> e.errMsg

-- ---------------------------------------------------------------------------
-- What the module declares
-- ---------------------------------------------------------------------------

-- | Records declared in the module, keyed by their L4 type name.
data RecordInfo = RecordInfo
  { riName   :: !Text  -- ^ the L4 name
  , riKey    :: !Text
  , riPlural :: !Text
  , riPy     :: !Text
  , riFields :: ![FieldInfo]
  }

-- | A field of a record. @fiListElem = Just R@ marks a @LIST OF R@ field (R a
-- record declared in this module), which makes the owning record a /group
-- entity/ whose members are @R@s. @fiType@ is 'Left' (the printed L4 type)
-- when OpenFisca has no value type for it.
data FieldInfo = FieldInfo
  { fiName     :: !Text  -- ^ the Python name
  , fiL4       :: !Text  -- ^ original (un-sanitised) field name
  , fiType     :: !(Either Text OFType)
  , fiStored   :: !Bool
  , fiListElem :: !(Maybe Text)
  }

-- | An enum declared in the module.
data EnumInfo = EnumInfo
  { eiDef        :: !OFEnumDef
  , eiL4         :: !Text
  , eiWithFields :: ![Text]  -- ^ constructors that carry fields (an OpenFisca Enum cannot)
  }

-- | An enum constructor: its Python class and member.
data EnumCon = EnumCon
  { ecClass  :: !Text
  , ecMember :: !Text
  }

-- | A legislation parameter (@\@desc parameter@ or @\@desc scale@).
data ParamInfo = ParamInfo
  { piL4       :: !Text
  , piKind     :: !Text  -- ^ "parameter" or "scale"
  , piPath     :: !Text
  , piTakesYear :: !Bool -- ^ does the L4 definition take the year as its one input?
  }

-- | How an @\@export@ decision is called from another one.
data Callee = Callee
  { calName   :: !Text           -- ^ the OpenFisca variable name
  , calL4     :: !Text
  , calRoles  :: ![(ParamRole, Text)]  -- ^ each GIVEN, in order, with its L4 name
  }

data ParamRole = RoleSubject | RolePeriod | RoleOther
  deriving stock Eq

-- | Everything about the module that lowering a decision needs.
data Ctx = Ctx
  { ctxEnums        :: !(Map Text EnumInfo)
  , ctxEnumCons     :: !(Map Unique EnumCon)
  , ctxSynonyms     :: !(Map Text (Type' Resolved))
  , ctxRecords      :: !(Map Text RecordInfo)
  , ctxScalarParams :: !(Map Unique ParamInfo)
  , ctxScaleParams  :: !(Map Unique ParamInfo)
  , ctxCallees      :: !(Map Unique Callee)
  }

-- | The 'EntityInfo' supplies the inferred result type of a decision that has
-- no GIVETH.
lowerModule :: EntityInfo -> Module Resolved -> Either [LowerError] OFPackage
lowerModule entInfo mod' =
  case enrichReturnTypes entInfo (getExportedFunctions mod') of
    []  -> Left [LowerError "" "no @export-annotated DECIDE found to compile to OpenFisca"]
    efs ->
      let (enums, enumCons) = collectEnums mod'
          synonyms    = collectSynonyms mod'
          ctx0 = Ctx
            { ctxEnums        = enums
            , ctxEnumCons     = enumCons
            , ctxSynonyms     = synonyms
            , ctxRecords      = Map.empty
            , ctxScalarParams = Map.empty
            , ctxScaleParams  = Map.empty
            , ctxCallees      = Map.empty
            }
          records = collectRecords ctx0 mod'
          ctx1    = ctx0 { ctxRecords = records }
          (paramErrs, _, scalars, scales) = collectParams mod'
          ctx = ctx1
            { ctxScalarParams = Map.map fst scalars
            , ctxScaleParams  = Map.map fst scales
            , ctxCallees      = Map.fromList
                [ (getUnique (decideName ef.exportDecide), calleeOf ctx1 ef) | ef <- efs ]
            }
          (errs, ok) = partitionEithers (map (lowerOne ctx) efs)
      in if not (null (paramErrs <> errs))
           then Left (paramErrs <> errs)
           else case checkCollisions (concatMap snd ok) of
             Left e     -> Left [e]
             Right vars ->
               let pkg = OFPackage
                     { pkgSource     = moduleSource mod'
                     , pkgEntities   = dedupOn (.entPy) (concatMap fst ok)
                     , pkgVariables  = vars
                     , pkgParameters = map snd (Map.elems scales)
                     , pkgScalars    = map snd (Map.elems scalars)
                     , pkgEnums      = map (.eiDef) (Map.elems enums)
                     }
               in case validateIdents pkg of
                    []    -> Right pkg
                    vErrs -> Left vErrs

-- | Lower a single exported decision into the entities it lives on plus the
-- variables it introduces (its inputs + the computed variable itself).
lowerOne :: Ctx -> ExportedFunction -> Either LowerError ([OFEntity], [OFVariable])
lowerOne ctx ef = mapLeft (LowerError fnName) $ do
  let MkDecide _ (MkTypeSig _ (MkGivenSig _ givens) _) (MkAppForm _ fnRes _ _) body = ef.exportDecide
      sig = signatureOf ctx givens
      ofPeriod = if isJust sig.sigPeriod then OFMonth else OFEternity

  -- The GIVETH, or the type the typechecker inferred ('enrichReturnTypes').
  resultTy <- case ef.exportReturnType of
    Just ty -> resultType ty
    Nothing -> Left "no GIVETH, and the typechecker inferred no result type: declare it (GIVETH A NUMBER, BOOLEAN or STRING) so the OpenFisca variable gets a value type"

  let (ent, members) = entitiesFor ctx sig

  let env = LowerEnv
        { envCtx        = ctx
        , envEntity     = ent.entPy
        , envSubject    = (getUnique . givenName . fst) <$> sig.sigSubject
        , envSubjectL4  = (givenText . fst) <$> sig.sigSubject
        , envSubjectRi  = snd <$> sig.sigSubject
        , envPeriod     = (getUnique . givenName) <$> sig.sigPeriod
        , envMember     = Nothing
        , envScalars    = Map.fromList [ (getUnique (givenName g), pyIdent (givenText g)) | g <- sig.sigOthers ]
        }
  (undatedF, datedF) <- lowerBody env body

  -- Stored scalar (non-list) fields of an entity-record become input variables.
  let inputsFor e ri = sequence
        [ (\ty -> OFVariable
            { varName    = fi.fiName
            , varL4      = fi.fiL4
            , varType    = ty
            , varEntity  = e.entPy
            , varEntKey  = e.entKey
            , varPeriod  = ofPeriod
            , varLabel   = fi.fiName
            , varFormula = Nothing
            , varDated   = []
            }) <$> first (fieldTypeMsg ri fi) fi.fiType
        | fi <- ri.riFields, fi.fiStored, isNothing fi.fiListElem
        ]
      scalarInput g = do
        ty <- case givenType g of
          Nothing -> Left ("input `" <> givenText g <> "` has no declared type; declare it IS A NUMBER, BOOLEAN or STRING")
          Just t  -> first (unrepresentable ("input `" <> givenText g <> "`")) (ofTypeOf ctx t)
        pure OFVariable
          { varName    = pyIdent (givenText g)
          , varL4      = givenText g
          , varType    = ty
          , varEntity  = ent.entPy
          , varEntKey  = ent.entKey
          , varPeriod  = ofPeriod
          , varLabel   = givenText g
          , varFormula = Nothing
          , varDated   = []
          }
  subjectInputs <- maybe (pure []) (inputsFor ent . snd) sig.sigSubject
  memberInputs  <- concat <$> traverse (uncurry inputsFor) members
  scalarInputs  <- traverse scalarInput sig.sigOthers
  let computed =
        OFVariable
          { varName    = fnName
          , varL4      = resolvedToText fnRes
          , varType    = resultTy
          , varEntity  = ent.entPy
          , varEntKey  = ent.entKey
          , varPeriod  = ofPeriod
          , varLabel   = if Text.null ef.exportDescription
                           then resolvedToText fnRes
                           else ef.exportDescription
          , varFormula = Just undatedF
          , varDated   = datedF
          }
  pure (ent : map fst members, subjectInputs <> memberInputs <> scalarInputs <> [computed])
 where
  fnName = pyIdent ef.exportName
  resultType ty
    = first (unrepresentable "its result") (ofTypeOf ctx ty)

-- | A decision's GIVENs, sorted into the subject (the first record-typed
-- GIVEN that is not the period), the conventional @period@, and the rest.
data Sig = Sig
  { sigSubject :: !(Maybe (OptionallyTypedName Resolved, RecordInfo))
  , sigPeriod  :: !(Maybe (OptionallyTypedName Resolved))
  , sigOthers  :: ![OptionallyTypedName Resolved]
  , sigRoles   :: ![(ParamRole, Text)]
  }

signatureOf :: Ctx -> [OptionallyTypedName Resolved] -> Sig
signatureOf ctx givens =
  let subj   = listToMaybe [ (g, ri) | g <- givens, not (isPeriodGiven g), Just ri <- [givenRecord ctx g] ]
      subjU  = (getUnique . givenName . fst) <$> subj
      roleOf g
        | Just (getUnique (givenName g)) == subjU = RoleSubject
        | isPeriodGiven g                         = RolePeriod
        | otherwise                               = RoleOther
  in Sig
       { sigSubject = subj
       , sigPeriod  = find isPeriodGiven givens
       , sigOthers  = [ g | g <- givens, roleOf g == RoleOther ]
       , sigRoles   = [ (roleOf g, givenText g) | g <- givens ]
       }

calleeOf :: Ctx -> ExportedFunction -> Callee
calleeOf ctx ef =
  let MkDecide _ (MkTypeSig _ (MkGivenSig _ givens) _) _ _ = ef.exportDecide
      sig = signatureOf ctx givens
  in Callee
       { calName   = pyIdent ef.exportName
       , calL4     = ef.exportName
       , calRoles  = sig.sigRoles
       }

-- | The entity a decision lives on, plus the member entities of a group
-- subject (each with the record whose fields become its inputs).
entitiesFor :: Ctx -> Sig -> (OFEntity, [(OFEntity, RecordInfo)])
entitiesFor ctx sig = case sig.sigSubject of
  Nothing      -> (defaultEntity, [])
  Just (_, ri) ->
    let members = mapMaybe (`Map.lookup` ctx.ctxRecords) (nubOrd (mapMaybe (.fiListElem) ri.riFields))
    in (recordEntity ri, [ (recordEntity m, m) | m <- members ])

-- ---------------------------------------------------------------------------
-- Expression lowering
-- ---------------------------------------------------------------------------

data LowerEnv = LowerEnv
  { envCtx        :: !Ctx
  , envEntity     :: !Text                 -- ^ the Python name of the entity the formula is on
  , envSubject    :: !(Maybe Unique)       -- ^ the subject (entity) parameter
  , envSubjectL4  :: !(Maybe Text)
  , envSubjectRi  :: !(Maybe RecordInfo)
  , envPeriod     :: !(Maybe Unique)       -- ^ the conventional period parameter
  , envMember     :: !(Maybe (Unique, RecordInfo, Text))
    -- ^ inside an aggregation: the lambda-bound member, its record, its entity
  , envScalars    :: !(Map Unique Text)    -- ^ free scalar params → input-variable names
  }

lowerExpr :: LowerEnv -> Expr Resolved -> Either Text OFExpr
lowerExpr env = go
 where
  ctx = env.envCtx

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
  -- aggregation lambda) → a member-array read; on the period → its start.
  lowerProj inner field = case inner of
    App _ s []
      | Just (getUnique s) == env.envSubject, Just ri <- env.envSubjectRi ->
          OFVarRef <$> fieldRead ri
      | Just (mu, mri, _) <- env.envMember, getUnique s == mu ->
          OFMembersVar <$> fieldRead mri
      | Just (getUnique s) == env.envPeriod -> case fieldText of
          "year"  -> Right (OFPeriodField "year")
          "month" -> Right (OFPeriodField "month")
          f       -> Left ("`period's " <> f <> "`: only `period's year` and `period's month` have an OpenFisca meaning (period.start.year / period.start.month)")
    _ -> Left "only a field of the subject, of a member, or of the period can be read; nested records and fields of other values are not supported"
   where
    fieldText = resolvedToText field
    fieldRead ri = case find (\fi -> fi.fiL4 == fieldText) ri.riFields of
      -- The desugarer strips computed (MEANS) fields from the record and
      -- turns each into a selector function, so a projection onto a name the
      -- record does not list is a computed field.
      Nothing -> Left computedMsg
      Just fi
        | isJust fi.fiListElem ->
            Left ("`" <> fieldText <> "` is a LIST OF members; it can be used only as the member list of sum, count, any or all")
        | not fi.fiStored -> Left computedMsg
        | Left _ <- fi.fiType -> Left (fieldTypeMsg ri fi (either id (const "") fi.fiType))
        | otherwise -> Right fi.fiName
     where
      computedMsg = "`" <> fieldText <> "` is a computed field (MEANS) of `" <> ri.riName
                    <> "`; the export does not compile computed fields (it does not inline helpers). Make it an @export decision instead."

  -- After resolution L4 desugars operators to builtin applications
  -- (@a * b@ → @App __TIMES__ [a, b]@), so arithmetic/boolean/comparison ops
  -- arrive here rather than as 'Times'/'And'/… constructors.
  lowerApp ref args
    | isBuiltinRef ref, Just mk <- builtinOp nm = traverse go args >>= mk
    | isBuiltinRef ref, u == trueUnique,  null args = Right (OFBoolLit True)
    | isBuiltinRef ref, u == falseUnique, null args = Right (OFBoolLit False)
    | nm `elem` preludeRecognised = preludeCall
    | nm `elem` conventionNames = conventionCall
    | Just p <- Map.lookup u ctx.ctxScalarParams = OFParamRef p.piPath <$ paramArgs p args
    | Just _ <- Map.lookup u ctx.ctxScaleParams =
        Left ("`" <> nm <> "` is a marginal-rate scale (@desc scale); it can be used only as the brackets argument of `scale tax`")
    | Just c <- Map.lookup u ctx.ctxCallees = exportedCall c args
    | Just u == env.envPeriod =
        Left "the period cannot be used as a value; pass it unchanged to another @export decision, or read `period's year` / `period's month`"
    | Just u == env.envSubject = Left "the subject entity cannot be used as a value; read one of its fields, or pass it unchanged to another @export decision"
    | Just (mu, _, _) <- env.envMember, u == mu =
        Left "the member cannot be used as a value; read one of its fields, or pass it unchanged to an @export decision"
    | Just name <- Map.lookup u env.envScalars, null args = Right (OFVarRef name)
    | not (null args) = Left ("cannot compile call to `" <> nm <> "` — OpenFisca formulas take no arguments; only references to other @export decisions are supported")
    | otherwise = Left ("unbound reference `" <> nm <> "` (recursion, prelude functions, and local bindings are not supported in v1)")
   where
    u  = getUnique ref
    nm = resolvedToText ref

    preludeCall = case nm of
      "max" | [_, _] <- args -> OFNpCall "maximum" <$> traverse go args
      "min" | [_, _] <- args -> OFNpCall "minimum" <$> traverse go args
      "sum"   | [x] <- args      -> aggSum x
      "count" | [x] <- args      -> aggCount x
      "any"   | [l, x] <- args   -> aggPred OFAny l x
      "all"   | [l, x] <- args   -> aggPred OFAll l x
      "map" -> Left "`map` is supported only inside `sum (map (GIVEN m YIELD …) (<members>))`"
      _ -> Left ("`" <> nm <> "` is called with an unsupported number of arguments")

    conventionCall = case nm of
      "scale tax" ->
        case args of
          [income, App _ sref sargs]
            | Just p <- Map.lookup (getUnique sref) ctx.ctxScaleParams -> do
                paramArgs p sargs
                OFScaleCalc p.piPath <$> go income
          _ -> Left "`scale tax` must be called as `scale tax OF <income>, <a @desc scale value>`"
      "members of" ->
        Left "`members of` is supported only as the member list of sum, count, any or all"
      _ ->  -- "period reaches"
        Left "`period reaches` is compiled only as the guard of EVERY arm of a decision's top-level BRANCH, where each arm becomes an OpenFisca dated formula (formula_YYYY_MM). Anywhere else, write the condition with `period's year` and `period's month` instead."

  -- A parameter call must read the parameter at the formula's own period.
  paramArgs p args = case args of
    [] | not p.piTakesYear -> Right ()
    [Proj _ (App _ x []) f]
      | p.piTakesYear
      , Just (getUnique x) == env.envPeriod
      , resolvedToText f == "year" -> Right ()
    _ -> Left ("`" <> p.piL4 <> "` is a legislation parameter (@desc " <> p.piKind <> " " <> p.piPath
               <> "). OpenFisca reads it at the formula's own period, so the only call the export can compile is `"
               <> p.piL4 <> (if p.piTakesYear then " OF period's year" else "")
               <> "`. Any other argument would be silently replaced by the current period's value, so it is refused.")

  -- A call to another @export decision reads that decision's OpenFisca
  -- variable at the same period. That is only the same thing as the L4 call
  -- when the call passes the subject (or, in an aggregation, the member) and
  -- the period through unchanged, so any other argument is refused.
  exportedCall c args = do
    when (length args /= length c.calRoles) $
      Left ("`" <> c.calL4 <> "` is called with " <> tshow (length args) <> " argument(s) but takes "
            <> tshow (length c.calRoles))
    viaMember <- or . catMaybes <$> zipWithM checkArg [1 :: Int ..] (zip c.calRoles args)
    pure (if viaMember then OFMembersVar c.calName else OFVarRef c.calName)
   where
    checkArg i ((role, pname), arg) = case (role, arg) of
      (RoleSubject, App _ x [])
        | Just (getUnique x) == env.envSubject -> Right (Just False)
        | Just (mu, _, _) <- env.envMember, getUnique x == mu -> Right (Just True)
      (RoleSubject, _) ->
        Left ("argument " <> tshow i <> " of `" <> c.calL4 <> "` is its subject `" <> pname
              <> "`. OpenFisca computes `" <> c.calL4 <> "` for the same entity, so the argument must be "
              <> maybe "the subject" backtick env.envSubjectL4
              <> " passed through unchanged (or, inside an aggregation, the member). Any other value would be silently replaced, so it is refused.")
      (RolePeriod, App _ x [])
        | Just (getUnique x) == env.envPeriod -> Right Nothing
      (RolePeriod, _) ->
        Left ("argument " <> tshow i <> " of `" <> c.calL4 <> "` is its period. OpenFisca computes every variable at the formula's own period, so the argument must be `period` passed through unchanged; a call at another period cannot be compiled.")
      (RoleOther, _) ->
        Left ("argument " <> tshow i <> " of `" <> c.calL4 <> "` supplies its input `" <> pname
              <> "`, which is an OpenFisca input variable of its own; a value passed here would be ignored. Only the subject and the period can be passed to another @export decision.")

  -- Group-entity aggregations over a member list:
  --   sum (map (GIVEN m YIELD <body>) <members>) → <group>.sum(<body>[, role=…])
  --   any (GIVEN m YIELD <pred>) <members>        → <group>.any(<pred>[, role=…])
  --   all (GIVEN m YIELD <pred>) <members>        → <group>.all(<pred>[, role=…])
  --   count <members>                             → <group>.nb_persons([role])
  -- where <members> is `h's <role>` (role-restricted) or `members of OF h` (all).
  aggSum = \case
    App _ mref [Lam _ (MkGivenSig _ [mp]) lbody, lst]
      | resolvedToText mref == "map" -> do
          (role, mri, ment) <- resolveMembers lst
          OFSum role <$> lowerMember mp mri ment lbody
    _ -> Left "`sum` is supported only as `sum (map (GIVEN m YIELD …) (<members>))`"

  aggCount lst = (\(role, _, _) -> OFNbPersons role) <$> resolveMembers lst

  aggPred mk lam lst = case lam of
    Lam _ (MkGivenSig _ [mp]) pbody -> do
      (role, mri, ment) <- resolveMembers lst
      mk role <$> lowerMember mp mri ment pbody
    _ -> Left "`any`/`all` are supported only as `any (GIVEN m YIELD <pred>) (<members>)`"

  lowerMember mp mri ment body =
    lowerExpr (env { envMember = Just (getUnique (givenName mp), mri, ment) }) body

  -- Resolve a member-list expression to (role selection, member record,
  -- member entity): a role of @Nothing@ means all members.
  resolveMembers lst = case (lst, env.envSubjectRi) of
        (Proj _ (App _ s []) fieldRes, Just ri)
          | Just (getUnique s) == env.envSubject ->
              case find (\fi -> fi.fiL4 == resolvedToText fieldRes) ri.riFields of
                Just fi | Just elemNm <- fi.fiListElem, Just mri <- Map.lookup elemNm ctx.ctxRecords ->
                  let listFields = filter (isJust . (.fiListElem)) ri.riFields
                      role = if length listFields <= 1 then Nothing else Just (singularize fi.fiName)
                  in Right (role, mri, mri.riPy)
                _ -> Left ("`" <> resolvedToText fieldRes <> "` is not a LIST OF members field of `" <> ri.riName <> "`")
        (App _ ref [App _ s []], Just ri)
          | resolvedToText ref == "members of"
          , Just (getUnique s) == env.envSubject ->
              case mapMaybe (\fi -> fi.fiListElem >>= (`Map.lookup` ctx.ctxRecords)) ri.riFields of
                (mri : _) -> Right (Nothing, mri, mri.riPy)
                []        -> Left ("`" <> ri.riName <> "` has no LIST OF members field")
        _ -> Left "expected a member list: `<the group>'s <members field>` or `members of OF <the group>`"

  -- @CONSIDER scrut WHEN C1 THEN v1 … OTHERWISE d@ over an enum becomes nested
  -- @np.where(scrut == Class.c1, v1, …, d)@. Every WHEN arm must be a bare
  -- constructor of an enum declared in this module, and the OTHERWISE must be
  -- the one last arm: an arm the export could not read used to be dropped.
  lowerConsider scrut branches = do
    scrutE <- go scrut
    (whens, dflt) <- splitArms branches
    def <- go dflt
    arms <- traverse (lowerArm scrutE) whens
    pure (foldr (\(c, v) acc -> OFCond c v acc) def arms)

  splitArms = \case
    [MkBranch _ (Otherwise _) d] -> Right ([], d)
    [] -> Left "CONSIDER without an OTHERWISE is not supported for OpenFisca; add `OTHERWISE <value>` as the last arm"
    (MkBranch _ (Otherwise _) _ : _) ->
      Left "CONSIDER: OTHERWISE must be the last arm (arms after it never apply in L4, but the export would have compiled them)"
    (MkBranch _ (When _ pat) body : rest) -> do
      con <- case pat of
        PatApp _ con []
          | Map.member (getUnique con) ctx.ctxEnumCons -> Right con
          | otherwise -> Left ("CONSIDER: `" <> resolvedToText con <> "` is not a constructor of an enum declared in this module; only CONSIDER over such an enum is supported")
        PatApp _ con _ ->
          Left ("CONSIDER: the arm `WHEN " <> resolvedToText con <> " …` binds the constructor's fields, which the export cannot compile (an OpenFisca Enum carries no fields). Only `WHEN <Constructor> THEN …` arms over an enum whose constructors have no fields are supported.")
        PatVar _ v ->
          Left ("CONSIDER: the arm `WHEN " <> resolvedToText v <> "` is a variable pattern; use OTHERWISE for the catch-all arm")
        PatCons{} -> Left "CONSIDER: list patterns (`FOLLOWED BY`) are not supported for OpenFisca"
        PatLit{}  -> Left "CONSIDER: literal patterns are not supported for OpenFisca; use BRANCH IF … EQUALS … instead"
        PatExpr{} -> Left "CONSIDER: expression patterns are not supported for OpenFisca"
      (ws, d) <- splitArms rest
      pure ((con, body) : ws, d)

  lowerArm scrutE (con, body) = case Map.lookup (getUnique con) ctx.ctxEnumCons of
    Just ec -> (\v -> (OFCmp OFEq scrutE (OFEnumLit ec.ecClass ec.ecMember), v)) <$> go body
    Nothing -> Left ("CONSIDER: `" <> resolvedToText con <> "` is not an enum constructor")

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

-- | Binary operators, in either representation: the surface constructor or
-- the builtin application it desugars to.
binView :: Expr Resolved -> Maybe (Text, Expr Resolved, Expr Resolved)
binView = \case
  And _ a b       -> Just ("__AND__", a, b)
  Or _ a b        -> Just ("__OR__", a, b)
  Equals _ a b    -> Just ("__EQUALS__", a, b)
  Leq _ a b       -> Just ("__LEQ__", a, b)
  Geq _ a b       -> Just ("__GEQ__", a, b)
  Lt _ a b        -> Just ("__LT__", a, b)
  Gt _ a b        -> Just ("__GT__", a, b)
  Plus _ a b      -> Just ("__PLUS__", a, b)
  Minus _ a b     -> Just ("__MINUS__", a, b)
  Times _ a b     -> Just ("__TIMES__", a, b)
  DividedBy _ a b -> Just ("__DIVIDE__", a, b)
  Modulo _ a b    -> Just ("__MODULO__", a, b)
  App _ r [a, b]
    | isBuiltinRef r, isJust (builtinOp (resolvedToText r)) -> Just (resolvedToText r, a, b)
  _ -> Nothing

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
  Consider{}   -> "CONSIDER / pattern match"
  MultiWayIf{} -> "multi-way IF"
  Where{}      -> "WHERE binding (local bindings are not supported)"
  LetIn{}      -> "LET binding (local bindings are not supported)"
  Lam{}        -> "lambda (only as the per-member function of sum/any/all)"
  List{}       -> "list literal (collections are not supported)"
  Cons{}       -> "list cons (collections are not supported)"
  Concat{}     -> "string concat"; AsString{} -> "string coercion"
  AppNamed{}   -> "named-argument application"
  Inert{}      -> "inert scaffolding"
  -- Explicit, ABOVE the wildcard: without this a refusal is rejected as a
  -- nameless "expression" and the author cannot tell what was refused.
  Refuse{}     -> "REFUSE (a refusal has no OpenFisca form: a variable always returns a value)"
  _            -> "expression"

-- ---------------------------------------------------------------------------
-- Names recognised by the export
-- ---------------------------------------------------------------------------

-- | Prelude functions the export compiles to OpenFisca's own operations.
preludeRecognised :: [Text]
preludeRecognised = ["sum", "map", "count", "any", "all", "max", "min"]

-- | Helpers the export recognises by name and compiles to an OpenFisca
-- construct, which the MODULE defines (the prelude has none of them).
conventionNames :: [Text]
conventionNames = ["period reaches", "scale tax", "members of"]

isBuiltinRef :: Resolved -> Bool
isBuiltinRef r = (getUnique r).moduleUri == builtinUri

-- ---------------------------------------------------------------------------
-- Module scanning helpers
-- ---------------------------------------------------------------------------

topDecls :: Module Resolved -> [TopDecl Resolved]
topDecls (MkModule _ _ section) = goSection section
 where
  goSection (MkSection _ _ _ _ decls) = decls >>= \case
    Section _ sub -> goSection sub
    d             -> [d]

collectSynonyms :: Module Resolved -> Map Text (Type' Resolved)
collectSynonyms m = Map.fromList
  [ (resolvedToText tyRes, ty)
  | Declare _ (MkDeclare _ _ (MkAppForm _ tyRes [] _) (SynonymDecl _ ty)) <- topDecls m ]

collectRecords :: Ctx -> Module Resolved -> Map Text RecordInfo
collectRecords ctx m = Map.fromList
  [ (nm, RecordInfo
       { riName   = nm
       , riKey    = Text.toLower (pyIdent nm)
       , riPlural = Text.toLower (pyIdent nm) <> "s"
       , riPy     = pyType nm
       , riFields =
           [ fieldInfo ctx fRes fTy mMeans
           | MkTypedName _ fRes fTy _ mMeans <- fields
           ]
       })
  | Declare _ (MkDeclare _ _ (MkAppForm _ recRes _ _) (RecordDecl _ _ fields)) <- topDecls m
  , let nm = resolvedToText recRes
  ]

fieldInfo :: Ctx -> Resolved -> Type' Resolved -> Maybe (Expr Resolved) -> FieldInfo
fieldInfo ctx fRes fTy mMeans =
  case listElemRecord ctx fTy of
    Just elemName -> FieldInfo nm l4 (Right OFFloat) stored (Just elemName)
    Nothing       -> FieldInfo nm l4 (ofTypeOf ctx fTy) stored Nothing
 where
  l4     = resolvedToText fRes
  nm     = pyIdent l4
  stored = isNothing mMeans

-- | If a type is @LIST OF <R>@, return the element type's name.
listElemRecord :: Ctx -> Type' Resolved -> Maybe Text
listElemRecord ctx ty = case expandSynonyms ctx ty of
  TyApp _ l [TyApp _ r _] | getUnique l == listUnique -> Just (resolvedToText r)
  _ -> Nothing

-- | Scan @DECLARE X IS ONE OF a, b, …@ enum declarations.
collectEnums :: Module Resolved -> (Map Text EnumInfo, Map Unique EnumCon)
collectEnums m =
  ( Map.fromList [ (ty, ei) | (ty, ei, _) <- defs ]
  , Map.fromList (concat [ cs | (_, _, cs) <- defs ])
  )
 where
  defs =
    [ ( ty
      , EnumInfo
          { eiDef = OFEnumDef
              { enName    = enPy
              , enMembers = [ (pyIdent (resolvedToText c), resolvedToText c) | MkConDecl _ c _ <- conDecls ]
              }
          , eiL4 = ty
          , eiWithFields = [ resolvedToText c | MkConDecl _ c (_ : _) <- conDecls ]
          }
      , [ (getUnique c, EnumCon enPy (pyIdent (resolvedToText c))) | MkConDecl _ c _ <- conDecls ]
      )
    | Declare _ (MkDeclare _ _ (MkAppForm _ tyRes _ _) (EnumDecl _ conDecls)) <- topDecls m
    , let ty   = resolvedToText tyRes
          enPy = pyType ty
    ]

-- ---------------------------------------------------------------------------
-- Legislation parameters
-- ---------------------------------------------------------------------------

-- | Scan values annotated @\@desc parameter <path>@ (a scalar parameter) or
-- @\@desc scale <path>@ (a marginal-rate scale). A value carrying either
-- annotation must be readable as that kind of parameter; one that is not is
-- an error naming the value, rather than a value the export quietly does not
-- register (its callers then failed with an unrelated message).
collectParams
  :: Module Resolved
  -> ( [LowerError]
     , Set Unique
     , Map Unique (ParamInfo, OFScalarParam)
     , Map Unique (ParamInfo, OFScaleParam) )
collectParams m =
  let results = mapMaybe one [ d | Decide _ d <- topDecls m ]
      scalarRs = [ r | Left r  <- results ]
      scaleRs  = [ r | Right r <- results ]
      (errsA, scalars) = partitionEithers scalarRs
      (errsB, scales)  = partitionEithers scaleRs
      paths = [ (pinfo.piL4, pinfo.piPath) | (_, (pinfo, _)) <- scalars ] <> [ (pinfo.piL4, pinfo.piPath) | (_, (pinfo, _)) <- scales ]
  in ( map snd (errsA <> errsB) <> pathConflicts paths
     , Set.fromList (map fst (errsA <> errsB))
     , Map.fromList scalars
     , Map.fromList scales )
 where
  one d@(MkDecide _ (MkTypeSig _ (MkGivenSig _ gs) _) (MkAppForm _ nameRes _ _) body) =
    let l4 = resolvedToText nameRes
        u  = getUnique nameRes
        err e = (u, LowerError l4 e)
        common kind ws = do
          path <- validatePath kind ws
          yU <- case gs of
            []  -> Right Nothing
            [g] -> Right (Just (getUnique (givenName g)))
            _   -> Left ("a @desc " <> kind <> " value takes at most one input, the year; `" <> l4 <> "` takes " <> tshow (length gs))
          pure (ParamInfo l4 kind path (isJust yU), yU)
    in case descWords d of
         ("parameter" : ws) -> Just $ Left $ first err $ do
           (pinfo, yU) <- common "parameter" ws
           vs <- readScalarParam yU body
           pure (u, (pinfo, OFScalarParam { spsPath = pinfo.piPath, spsValues = vs }))
         ("scale" : ws) -> Just $ Right $ first err $ do
           (pinfo, yU) <- common "scale" ws
           bs <- readScale yU body
           pure (u, (pinfo, OFScaleParam { spPath = pinfo.piPath, spBrackets = bs }))
         _ -> Nothing

-- | The words of a DECIDE's @\@desc@ annotation.
descWords :: Decide Resolved -> [Text]
descWords d = maybe [] (Text.words . getDesc) (getAnno d ^. annDesc)

-- | A parameter path is spliced into the emitted Python as
-- @parameters(period).<path>@, so every segment must be a plain identifier:
-- ASCII, starting with a letter (a leading underscore reaches OpenFisca's
-- internal attributes, e.g. @_name@; a dunder reaches Python's), not a Python
-- keyword, and not a key OpenFisca's parameter loader reserves.
validatePath :: Text -> [Text] -> Either Text Text
validatePath kind = \case
  [p] -> case filter (not . okSegment) (Text.splitOn "." p) of
    []        -> Right p
    (bad : _) -> Left ("the @desc " <> kind <> " path `" <> p <> "` is not a valid OpenFisca parameter path: the segment `" <> bad
                       <> "` must be an ASCII identifier that starts with a letter (letters, digits and `_`), must not be a Python keyword or a dunder, and must not be one of OpenFisca's reserved keys ("
                       <> Text.intercalate ", " (Set.toList openFiscaReservedKeys) <> ")")
  [] -> Left ("the @desc " <> kind <> " annotation needs a dotted path, e.g. `@desc " <> kind <> " taxes.rate`")
  ws -> Left ("the @desc " <> kind <> " annotation takes exactly one dotted path (e.g. `@desc " <> kind <> " taxes.rate`), but has " <> tshow (length ws) <> " words: `" <> Text.unwords ws <> "`")
 where
  okSegment s = case Text.uncons s of
    Just (h, rest) -> isAsciiLetter h
                      && Text.all (\c -> isAsciiLetter c || isDigit c || c == '_') rest
                      && not (s `Set.member` pythonKeywords)
                      && not (s `Set.member` openFiscaReservedKeys)
    Nothing -> False

-- | Keys OpenFisca's parameter loader treats specially: metadata keys, which
-- it skips as children, and the two keys that turn a node into a leaf.
openFiscaReservedKeys :: Set Text
openFiscaReservedKeys = Set.fromList
  ["brackets", "description", "documentation", "metadata", "reference", "unit", "values"]

-- | Two parameters at one path, or one parameter at a path inside another's,
-- would overwrite each other in the emitted parameter tree.
pathConflicts :: [(Text, Text)] -> [LowerError]
pathConflicts paths =
  [ LowerError a ("the @desc path `" <> pa <> "` of `" <> a <> "` "
                  <> (if pa == pb then "is also the path of `" else "contains the path of `")
                  <> b <> "` (`" <> pb <> "`); every legislation parameter needs its own path, and no path may lie inside another")
  | ((a, pa), i) <- zip paths [0 :: Int ..]
  , ((b, pb), j) <- zip paths [0 ..]
  , i /= j
  , (pa == pb && i < j) || (pa /= pb && (pa <> ".") `Text.isPrefixOf` pb)
  ]

-- | Read a scalar parameter body into a date-indexed value series. Supported:
-- a constant, @IF y AT LEAST <year> THEN v ELSE v0@, or a BRANCH of such arms
-- written newest first, where @y@ is the value's own year input.
readScalarParam :: Maybe Unique -> Expr Resolved -> Either Text [(Text, Rational)]
readScalarParam yU = \case
  Lit _ (NumericLit _ v) -> Right [(epochDate, v)]
  IfThenElse _ cond thenE elseE -> do
    y  <- guardYear yU cond
    tv <- litNum thenE
    ev <- litNum elseE
    pure [(epochDate, ev), (isoYM y 1, tv)]
  MultiWayIf _ guards oth -> do
    arms <- traverse scalarArm guards
    unless (strictlyDescDates (map fst arms)) $ Left newestFirstMsg
    ov   <- litNum oth
    pure ((epochDate, ov) : arms)
  _ -> Left parameterShapeMsg
 where
  scalarArm (MkGuardedExpr _ cond body) = do
    y <- guardYear yU cond
    v <- litNum body
    pure (isoYM y 1, v)
  litNum = \case
    Lit _ (NumericLit _ v) -> Right v
    _ -> Left ("each value of a @desc parameter must be a number literal. " <> parameterShapeMsg)

parameterShapeMsg :: Text
parameterShapeMsg =
  "A @desc parameter value must be a number literal, `IF y AT LEAST <year> THEN <number> ELSE <number>`, or `BRANCH IF y AT LEAST <year> THEN <number> … OTHERWISE <number>` with the arms newest first, where y is the value's own (only) input, the year."

newestFirstMsg :: Text
newestFirstMsg =
  "the year-guarded arms must be written newest first (strictly descending years): L4's BRANCH takes the first arm that holds, OpenFisca takes the latest date that has started, and the two agree only in that order"

-- | Read a scale body into dated brackets. Two shapes:
--
--   * @LIST (band OF t, r), …@                       — a single-period scale
--     (all values dated at a neutral epoch).
--   * @BRANCH IF y AT LEAST <year> THEN LIST … …@    — a time-varying scale; each
--     arm's @year@ becomes the effective date and brackets are aligned by index.
readScale :: Maybe Unique -> Expr Resolved -> Either Text [OFBracket]
readScale yU = \case
  List _ elems -> do
    rows <- readRows elems
    pure [ OFBracket [(epochDate, t)] [(epochDate, r)] | (t, r) <- rows ]
  MultiWayIf _ guards otherwise' -> do
    arms    <- traverse readArm guards
    othRows <- readOtherwiseRows otherwise'
    -- arms as written must be strictly descending by date: L4 BRANCH is
    -- first-match, OpenFisca resolves by latest date — they agree only so.
    unless (strictlyDescDates (map fst arms)) $ Left newestFirstMsg
    -- the OTHERWISE brackets apply before the earliest dated arm.
    let allArms = arms <> [(epochDate, othRows)]
    -- a bracket may appear over time but must not vanish (OpenFisca can't drop one).
    unless (nonShrinking allArms) $
      Left "a later arm of a @desc scale has fewer brackets than an earlier one; OpenFisca cannot remove a bracket over time, so every arm must have at least as many brackets as the arms before it"
    pure (alignByIndex allArms)
  _ -> Left scaleShapeMsg
 where
  readArm (MkGuardedExpr _ cond body) = do
    yr   <- guardYear yU cond
    rows <- case body of
      List _ es -> readRows es
      _         -> Left scaleShapeMsg
    pure (isoDate yr, rows)
  readOtherwiseRows = \case
    List _ es -> readRows es
    App _ e [] | getUnique e == emptyUnique -> Right []
    _ -> Left ("the OTHERWISE of a time-varying @desc scale must be a LIST of brackets or EMPTY. " <> scaleShapeMsg)
  readRows es = do
    rows <- traverse readRow es
    unless (and (zipWith (<) (map fst rows) (drop 1 (map fst rows)))) $
      Left "the brackets of a @desc scale must be listed with strictly increasing thresholds, as OpenFisca's marginal-rate scale requires"
    pure rows

scaleShapeMsg :: Text
scaleShapeMsg =
  "A @desc scale value must be a LIST of brackets `(band OF <threshold>, <rate>)`, or `BRANCH IF y AT LEAST <year> THEN LIST … OTHERWISE <LIST … or EMPTY>` with the arms newest first, where y is the value's own (only) input, the year."

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
readRow :: Expr Resolved -> Either Text (Rational, Rational)
readRow = \case
  App _ _ [Lit _ (NumericLit _ t), Lit _ (NumericLit _ r)] -> Right (t, r)
  _ -> Left ("each bracket of a @desc scale must be `(band OF <threshold literal>, <rate literal>)`. " <> scaleShapeMsg)

-- | A year guard in a parameter or scale body: @y AT LEAST <year>@, or
-- @y GREATER THAN <year>@ (which, for whole years, is @y AT LEAST <year> + 1@).
-- The left operand must be the value's own year input: anything else is not a
-- date, and was once read as one.
guardYear :: Maybe Unique -> Expr Resolved -> Either Text Integer
guardYear yU cond = case binView cond of
  Just (op, App _ v [], Lit _ (NumericLit _ n))
    | Just (getUnique v) == yU, op `elem` ["__GEQ__", "__GT__"] -> do
        unless (denominator n == 1) $
          Left ("a year guard compares the year with a whole number; `" <> tshow (fromRational n :: Double) <> "` is not one")
        let y = numerator n + (if op == "__GT__" then 1 else 0)
        unless (y > 1900 && y <= 9999) $
          Left ("a year guard's effective year must lie after 1900 and before 10000 (it is " <> tshow y <> ")")
        pure y
  _ -> Left ("a year guard must be `y AT LEAST <year>` or `y GREATER THAN <year>`, where y is the value's own year input and <year> a whole number. " <> parameterShapeMsg)

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

-- ---------------------------------------------------------------------------
-- Dated formulas
-- ---------------------------------------------------------------------------

-- | Lower a decision body, splitting a top-level @BRANCH IF period reaches …@
-- into an undated @formula@ (the OTHERWISE) plus dated @formula_YYYY_MM@ arms.
lowerBody :: LowerEnv -> Expr Resolved -> Either Text (OFExpr, [(Text, OFExpr)])
lowerBody env body = case body of
  MultiWayIf _ guards oth
    | any (\(MkGuardedExpr _ c _) -> isPeriodReachesCall c) guards -> do
        arms <- traverse datedArm guards
        unless (strictlyDescDates (map fst arms)) $
          Left "dated-formula BRANCH arms must be in strictly-descending date order \
               \(OpenFisca selects the latest formula by date, but L4 BRANCH is first-match)"
        (,) <$> lowerExpr env oth
            <*> traverse (\(d, b) -> (,) d <$> lowerExpr env b) arms
  _ -> (\b -> (b, [])) <$> lowerExpr env body
 where
  datedArm (MkGuardedExpr _ cond b) = case cond of
    App _ ref [App _ p [], Lit _ (NumericLit _ y), Lit _ (NumericLit _ mo)]
      | resolvedToText ref == "period reaches" -> do
          unless (Just (getUnique p) == env.envPeriod) $
            Left "the first argument of `period reaches` must be the decision's own `period`"
          unless (denominator y == 1 && denominator mo == 1 && mo >= 1 && mo <= 12 && y > 1900 && y <= 9999) $
            Left "`period reaches OF period, <year>, <month>` needs a whole-number year after 1900 and a month from 1 to 12"
          pure (isoYM (numerator y) (numerator mo), b)
    _ | isPeriodReachesCall cond ->
          Left "`period reaches` must be called as `period reaches OF period, <year>, <month>` with number literals for the year and month"
      | otherwise ->
          Left "this BRANCH mixes `period reaches` arms with other conditions; for OpenFisca's dated formulas every arm must be `IF period reaches OF period, <year>, <month> THEN …`"

isPeriodReachesCall :: Expr Resolved -> Bool
isPeriodReachesCall = \case
  App _ ref _ -> resolvedToText ref == "period reaches"
  _           -> False

isoYM :: Integer -> Integer -> Text
isoYM y m = tshow y <> "-" <> pad m <> "-01"
 where
  pad n = (if n < 10 then "0" else "") <> tshow n

-- ---------------------------------------------------------------------------
-- Entities
-- ---------------------------------------------------------------------------

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

isPeriodGiven :: OptionallyTypedName Resolved -> Bool
-- Detect the conventional period parameter by its raw L4 name (not the
-- keyword-safe pyIdent, which would rename @period@ → @period_@).
isPeriodGiven g = Text.toLower (Text.strip (givenText g)) == "period"

-- | If a GIVEN's type names a record declared in this module, return that
-- record (it is a subject).
givenRecord :: Ctx -> OptionallyTypedName Resolved -> Maybe RecordInfo
givenRecord ctx g = do
  ty <- givenType g
  TyApp _ name [] <- Just (expandSynonyms ctx ty)
  Map.lookup (resolvedToText name) ctx.ctxRecords

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | Expand a type synonym declared in this module (bounded, so a cycle the
-- typechecker let through cannot loop).
expandSynonyms :: Ctx -> Type' Resolved -> Type' Resolved
expandSynonyms ctx = go (10 :: Int)
 where
  go 0 t = t
  go n t = case t of
    TyApp _ name [] | Just t' <- Map.lookup (resolvedToText name) ctx.ctxSynonyms -> go (n - 1) t'
    _ -> t

enumOf :: Ctx -> Type' Resolved -> Maybe EnumInfo
enumOf ctx ty = case expandSynonyms ctx ty of
  TyApp _ name [] -> Map.lookup (resolvedToText name) ctx.ctxEnums
  _               -> Nothing

-- | The OpenFisca value type of an L4 type, or the printed type when there is
-- none. Only the builtin NUMBER, BOOLEAN and STRING (recognised by identity,
-- not name) and enums declared in this module whose constructors carry no
-- fields have one.
ofTypeOf :: Ctx -> Type' Resolved -> Either Text OFType
ofTypeOf ctx ty = case expandSynonyms ctx ty of
  TyApp _ name []
    | u == numberUnique  -> Right OFFloat
    | u == booleanUnique -> Right OFBool
    | u == stringUnique  -> Right OFStr
    | Just ei <- enumOf ctx ty ->
        case (ei.eiWithFields, ei.eiDef.enMembers) of
          ([], (m, _) : _) -> Right (OFEnum ei.eiDef.enName m)
          (c : _, _)       -> Left (typeText ty <> ", an enum whose constructor `" <> c <> "` carries fields (an OpenFisca Enum cannot)")
          (_, [])          -> Left (typeText ty <> ", an enum with no constructors")
    | Map.member (resolvedToText name) ctx.ctxRecords ->
        Left (typeText ty <> ", a record (nested records are not supported: put the fields you need on the entity's own record)")
    where u = getUnique name
  t -> Left (typeText t)

-- | Print an L4 type for a message.
typeText :: Type' Resolved -> Text
typeText = \case
  TyApp _ n []   -> resolvedToText n
  TyApp _ n args -> resolvedToText n <> " OF " <> Text.intercalate ", " (map arg args)
  Fun{}          -> "a function type"
  Forall{}       -> "a polymorphic type"
  _              -> "an unknown type"
 where
  arg t@(TyApp _ _ (_ : _)) = "(" <> typeText t <> ")"
  arg t                     = typeText t

unrepresentable :: Text -> Text -> Text
unrepresentable what ty =
  what <> " has type " <> ty <> ", which the OpenFisca export cannot represent. "
  <> "OpenFisca variables hold NUMBER, BOOLEAN, STRING, or an enum declared in this module (DECLARE … IS ONE OF, constructors without fields)."

fieldTypeMsg :: RecordInfo -> FieldInfo -> Text -> Text
fieldTypeMsg ri fi ty =
  "field `" <> fi.fiL4 <> "` of `" <> ri.riName <> "` has type " <> ty
  <> ", which the OpenFisca export cannot represent as an input variable (supported: NUMBER, BOOLEAN, STRING, an enum declared in this module, and LIST OF a record declared in this module, which makes a group entity). "
  <> "Give the OpenFisca-facing record a field of a supported type instead, e.g. a year as a NUMBER."

-- ---------------------------------------------------------------------------
-- Name helpers
-- ---------------------------------------------------------------------------

decideName :: Decide Resolved -> Resolved
decideName (MkDecide _ _ (MkAppForm _ r _ _) _) = r

resolvedToText :: Resolved -> Text
resolvedToText = rawNameToText . rawName . getActual

backtick :: Text -> Text
backtick t = "`" <> t <> "`"

-- | Sanitise an L4 name into a snake_case Python identifier. Must be a total,
-- deterministic function: the same L4 name always yields the same identifier so
-- variable definitions and references stay in sync. A name with non-ASCII
-- letters or digits keeps them here, and 'validateIdents' refuses the result.
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

-- | Lowercase names a variable must not take, which get a @_@ suffix: the
-- Python keywords (lowercased, since 'pyIdent' lowercases), the formula-local
-- names @period@ / @parameters@ / @entity@ / @formula@, and the lowercase
-- module-level names the emitted file binds (@np@, @build_entity@).
pyReserved :: Set Text
pyReserved = Set.fromList
  [ "and","as","assert","async","await","break","class","continue","def","del"
  , "elif","else","except","false","finally","for","from","global","if","import"
  , "in","is","lambda","nonlocal","none","not","or","pass","raise","return","true"
  , "try","while","with","yield","match","case"
  , "period","parameters","entity","formula"
  , "np","build_entity" ]

-- | The Python keywords, case-sensitively.
pythonKeywords :: Set Text
pythonKeywords = Set.fromList
  [ "False","None","True","and","as","assert","async","await","break","class"
  , "continue","def","del","elif","else","except","finally","for","from","global"
  , "if","import","in","is","lambda","nonlocal","not","or","pass","raise","return"
  , "try","while","with","yield" ]

-- | A Python class/variable name for a type, preserving case (e.g. @Person@).
-- Keyword-safe, and never one of the names the emitted module itself binds.
pyType :: Text -> Text
pyType raw =
  let cleaned = Text.map (\c -> if isAlphaNum c || c == '_' then c else '_') raw
      base = case Text.uncons cleaned of
        Just (h, _) | isDigit h -> "T_" <> cleaned
        Nothing                 -> "T"
        _                       -> cleaned
  in if base `Set.member` pyTypeReserved then base <> "_" else base

pyTypeReserved :: Set Text
pyTypeReserved = pythonKeywords <> Set.fromList
  [ "TaxBenefitSystem", "build_entity", "Variable", "MONTH", "YEAR", "ETERNITY"
  , "Enum", "ParameterNode", "np", "L4TaxBenefitSystem", "CountryTaxBenefitSystem"
  , "_PARAMETERS" ]

-- | Every name the emitted module uses must be a valid ASCII Python
-- identifier. 'pyIdent' and 'pyType' keep non-ASCII letters and digits (a
-- @²@ is 'isAlphaNum'), which Python may reject, so the result is refused
-- here, naming the L4 definition it came from.
validateIdents :: OFPackage -> [LowerError]
validateIdents pkg =
     [ badIdent ("the record `" <> e.entLabel <> "`") n | e <- pkg.pkgEntities, n <- [e.entPy, e.entKey, e.entPlural], not (validIdent n) ]
  <> [ badIdent ("the LIST OF field `" <> r.rolePlural <> "`") n | e <- pkg.pkgEntities, r <- e.entRoles, n <- [r.roleKey, r.rolePlural], not (validIdent n) ]
  <> [ badIdent ("the enum `" <> en.enName <> "`") en.enName | en <- pkg.pkgEnums, not (validIdent en.enName) ]
  <> [ badIdent ("the enum constructor `" <> l4 <> "`") mem | en <- pkg.pkgEnums, (mem, l4) <- en.enMembers, not (validIdent mem) ]
  <> [ badIdent ("`" <> v.varL4 <> "`") v.varName | v <- pkg.pkgVariables, not (validIdent v.varName) ]
 where
  badIdent what py = LowerError "" (what <> " becomes the Python identifier `" <> py
                            <> "`, which is not a valid ASCII Python identifier; OpenFisca names must be ASCII letters, digits and `_`. Rename it.")

validIdent :: Text -> Bool
validIdent t = case Text.uncons t of
  Just (h, rest) -> (isAsciiLetter h || h == '_')
                    && Text.all (\c -> isAsciiLetter c || isDigit c || c == '_') rest
                    && not (t `Set.member` pythonKeywords)
  Nothing -> False

isAsciiLetter :: Char -> Bool
isAsciiLetter c = isAsciiLower c || isAsciiUpper c

-- ---------------------------------------------------------------------------
-- Small utilities
-- ---------------------------------------------------------------------------

tshow :: Show a => a -> Text
tshow = Text.pack . show

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
checkCollisions :: [OFVariable] -> Either LowerError [OFVariable]
checkCollisions vs =
  case [ (nm, grp) | (nm, grp) <- Map.toList byName, length (nub grp) > 1 ] of
    ((nm, grp) : _) ->
      Left $ LowerError ""
        ( "name collision: distinct L4 definitions ("
        <> Text.intercalate ", " [ "`" <> v.varL4 <> "`" | v <- nub grp ]
        <> ") both compile to the OpenFisca variable `" <> nm
        <> "`. A decision, field, or parameter that shares a (sanitised) name "
        <> "with another is unsafe in OpenFisca — rename one." )
    [] -> Right (dedupOn (.varName) vs)
 where
  byName = Map.fromListWith (<>) [ (v.varName, [v]) | v <- vs ]
