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
import Data.Graph (SCC (..), stronglyConnComp)

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

-- | An enum constructor: its Python class and member, and its enum's L4 name.
data EnumCon = EnumCon
  { ecClass  :: !Text
  , ecMember :: !Text
  , ecEnumL4 :: !Text
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
  , calEntity :: !Text           -- ^ the entity's Python name
  , calRoles  :: ![(ParamRole, Text)]  -- ^ each GIVEN, in order, with its L4 name
  }

data ParamRole = RoleSubject | RolePeriod | RoleOther
  deriving stock Eq

-- | Everything about the module that lowering a decision needs.
data Ctx = Ctx
  { ctxSelfUri      :: !NormalizedUri
  , ctxEnums        :: !(Map Text EnumInfo)
  , ctxEnumCons     :: !(Map Unique EnumCon)
  , ctxSynonyms     :: !(Map Text (Type' Resolved))
  , ctxRecords      :: !(Map Text RecordInfo)
  , ctxDecides      :: !(Map Unique (Decide Resolved))  -- ^ every top-level DECIDE in the module
  , ctxScalarParams :: !(Map Unique ParamInfo)
  , ctxScaleParams  :: !(Map Unique ParamInfo)
  , ctxCallees      :: !(Map Unique Callee)
  , ctxBadParams    :: !(Set Unique)  -- ^ @desc parameter/scale values refused (their own error says why)
  }

-- | The 'EntityInfo' supplies the inferred result type of a decision that has
-- no GIVETH.
lowerModule :: EntityInfo -> Module Resolved -> Either [LowerError] OFPackage
lowerModule entInfo mod'@(MkModule _ selfUri _) =
  case enrichReturnTypes entInfo (getExportedFunctions mod') of
    []  -> Left [LowerError "" "no @export-annotated DECIDE found to compile to OpenFisca"]
    efs ->
      let (enums, enumCons) = collectEnums mod'
          synonyms    = collectSynonyms mod'
          recordNames = collectRecordNames mod'
          ctx0 = Ctx
            { ctxSelfUri      = selfUri
            , ctxEnums        = enums
            , ctxEnumCons     = enumCons
            , ctxSynonyms     = synonyms
            , ctxRecords      = Map.empty
            , ctxDecides      = collectDecides mod'
            , ctxScalarParams = Map.empty
            , ctxScaleParams  = Map.empty
            , ctxCallees      = Map.empty
            , ctxBadParams    = Set.empty
            }
          records = collectRecords ctx0 recordNames mod'
          ctx1    = ctx0 { ctxRecords = records }
          (paramErrs, badParams, scalars, scales) = collectParams ctx1 mod'
          ctx = ctx1
            { ctxBadParams    = badParams
            , ctxScalarParams = Map.map fst scalars
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
               in case validateIdents pkg <> validatePackage (concatMap fst ok) pkg <> recursionErrors pkg of
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

  (ent, members) <- entitiesFor ctx sig

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

  -- An input and a stored field of the same name would both become the one
  -- OpenFisca input variable of that name, so two values L4 keeps apart
  -- would be read from one. (A LIST OF field is a role, which
  -- 'validatePackage' checks against the variables.)
  forM_ sig.sigOthers \g ->
    case [ (ri, fi) | ri <- Map.elems ctx.ctxRecords, fi <- ri.riFields
                    , fi.fiStored, isNothing fi.fiListElem  -- the fields that become input variables
                    , fi.fiName == pyIdent (givenText g) ] of
      ((ri, fi) : _) ->
        Left ("the input `" <> givenText g <> "` and the field `" <> fi.fiL4 <> "` of `" <> ri.riName
              <> "` both become the OpenFisca input variable `" <> fi.fiName
              <> "`, so a situation could not give them different values, and L4 can. Rename the input.")
      [] -> Right ()

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
    | Just ei <- enumOf ctx ty = Left (enumResultMsg ei.eiL4)
    | otherwise                = first (unrepresentable "its result") (ofTypeOf ctx ty)

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
       , calEntity = maybe defaultEntity.entPy ((.riPy) . snd) sig.sigSubject
       , calRoles  = sig.sigRoles
       }

-- | The entity a decision lives on, plus the member entities of a group
-- subject (each with the record whose fields become its inputs).
entitiesFor :: Ctx -> Sig -> Either Text (OFEntity, [(OFEntity, RecordInfo)])
entitiesFor ctx sig = case sig.sigSubject of
  Nothing      -> Right (defaultEntity, [])
  Just (_, ri) -> do
    let elemNames = nubOrd (mapMaybe (.fiListElem) ri.riFields)
    members <- case elemNames of
      []   -> Right []
      [nm] -> case Map.lookup nm ctx.ctxRecords of
        Nothing  -> Left ("internal: member record `" <> nm <> "` not found")
        Just mri
          | any (isJust . (.fiListElem)) mri.riFields ->
              Left ("the member record `" <> nm <> "` of the group `" <> ri.riName
                    <> "` itself has a LIST OF field; nested group entities are not supported. "
                    <> "Give `" <> nm <> "` scalar fields only.")
          | otherwise -> Right [(recordEntity mri, mri)]
      _ -> Left ("the group `" <> ri.riName <> "` has LIST OF fields of different record types ("
                 <> Text.intercalate ", " (map backtick elemNames)
                 <> "); an OpenFisca group entity has one member entity. Use one member record for every role.")
    pure (recordEntity ri, members)

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
  inMember = isJust env.envMember

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
          if inMember
            then Left (groupValueInMember ("`" <> fieldText <> "` of the subject"))
            else OFVarRef <$> fieldRead ri
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
    | Just ec <- Map.lookup u ctx.ctxEnumCons = Left (enumValueMsg nm ec.ecEnumL4)
    | nm `elem` preludeRecognised =
        if isPreludeRef ctx ref then preludeCall else Left (shadowedPreludeMsg ctx ref)
    | nm `elem` conventionNames = conventionCall
    | Just p <- Map.lookup u ctx.ctxScalarParams = OFParamRef p.piPath <$ paramArgs p args
    | u `Set.member` ctx.ctxBadParams =
        Left ("`" <> nm <> "` is a @desc parameter/scale value that the export refused (see its own error above), so calls to it cannot be compiled either")
    | Just _ <- Map.lookup u ctx.ctxScaleParams =
        Left ("`" <> nm <> "` is a marginal-rate scale (@desc scale); it can be used only as the brackets argument of `scale tax`")
    | Just c <- Map.lookup u ctx.ctxCallees = exportedCall c args
    | Just u == env.envPeriod =
        Left "the period cannot be used as a value; pass it unchanged to another @export decision, or read `period's year` / `period's month`"
    | Just u == env.envSubject = Left "the subject entity cannot be used as a value; read one of its fields, or pass it unchanged to another @export decision"
    | Just (mu, _, _) <- env.envMember, u == mu =
        Left "the member cannot be used as a value; read one of its fields, or pass it unchanged to an @export decision"
    | Just name <- Map.lookup u env.envScalars, null args =
        if inMember then Left (groupValueInMember ("the input `" <> nm <> "`")) else Right (OFVarRef name)
    | isBuiltinRef ref =
        Left ("`" <> nm <> "` is an L4 builtin that the OpenFisca export does not compile. It compiles arithmetic, comparisons, AND / OR / NOT / IMPLIES, IF, BRANCH and CONSIDER over an enum, and the prelude's sum, count, any, all, max and min; write the value without `" <> nm <> "`, or compute it outside OpenFisca.")
    | not (null args) = Left (helperCallMsg nm)
    | otherwise = Left ("unbound reference `" <> nm <> "` (recursion, prelude values, and local bindings are not supported)")
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
      "scale tax" -> do
        checkConvention ctx "scale tax" ref
        case args of
          [income, App _ sref sargs]
            | Just p <- Map.lookup (getUnique sref) ctx.ctxScaleParams -> do
                paramArgs p sargs
                OFScaleCalc p.piPath <$> go income
          [_, App _ sref _]
            | getUnique sref `Set.member` ctx.ctxBadParams ->
                Left ("`" <> resolvedToText sref <> "` is a @desc scale value that the export refused (see its own error above), so `scale tax` over it cannot be compiled either")
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
    when (not inMember && c.calEntity /= env.envEntity) $
      Left ("cross-entity call: `" <> c.calL4 <> "` is a variable of the entity `" <> c.calEntity
            <> "`, but this decision is computed on `" <> env.envEntity
            <> "`. OpenFisca reads a member entity's variable only through an aggregation over the members, e.g. "
            <> "sum (map (GIVEN m YIELD " <> backtickIfSpaced c.calL4 <> " OF m, period) (<the group>'s <members>)).")
    when (length args /= length c.calRoles) $
      Left ("`" <> c.calL4 <> "` is called with " <> tshow (length args) <> " argument(s) but takes "
            <> tshow (length c.calRoles))
    viaMember <- or . catMaybes <$> zipWithM checkArg [1 :: Int ..] (zip c.calRoles args)
    if viaMember
      then case env.envMember of
        Just (_, _, ment) | ment == c.calEntity -> Right (OFMembersVar c.calName)
        _ -> Left ("cross-entity call: `" <> c.calL4 <> "` is a variable of `" <> c.calEntity <> "`, not of the member entity")
      else if inMember
        then Left (groupValueInMember ("the decision `" <> c.calL4 <> "` of the group"))
        else Right (OFVarRef c.calName)
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
      | resolvedToText mref == "map", isPreludeRef ctx mref -> do
          (role, mri, ment) <- resolveMembers lst
          OFSum role <$> lowerMember mp mri ment lbody
    _ -> Left "`sum` is supported only as `sum (map (GIVEN m YIELD …) (<members>))`"

  aggCount lst = (\(role, _, _) -> OFNbPersons role) <$> resolveMembers lst

  aggPred mk lam lst = case lam of
    Lam _ (MkGivenSig _ [mp]) pbody -> do
      (role, mri, ment) <- resolveMembers lst
      mk role <$> lowerMember mp mri ment pbody
    _ -> Left "`any`/`all` are supported only as `any (GIVEN m YIELD <pred>) (<members>)`"

  lowerMember mp mri ment body = do
    e <- lowerExpr (env { envMember = Just (getUnique (givenName mp), mri, ment) }) body
    unless (mentionsMember e) $
      Left "the per-member expression inside the aggregation does not read the member; OpenFisca aggregates a per-member array, so read a field or @export decision of the member"
    pure e

  -- Resolve a member-list expression to (role selection, member record,
  -- member entity): a role of @Nothing@ means all members.
  resolveMembers lst
    | inMember = Left "nested aggregations are not supported"
    | otherwise = case (lst, env.envSubjectRi) of
        (Proj _ (App _ s []) fieldRes, Just ri)
          | Just (getUnique s) == env.envSubject ->
              case find (\fi -> fi.fiL4 == resolvedToText fieldRes) ri.riFields of
                Just fi | Just elemNm <- fi.fiListElem, Just mri <- Map.lookup elemNm ctx.ctxRecords ->
                  let listFields = filter (isJust . (.fiListElem)) ri.riFields
                      role = if length listFields <= 1 then Nothing else Just (roleKey fi.fiName)
                  in Right (role, mri, mri.riPy)
                _ -> Left ("`" <> resolvedToText fieldRes <> "` is not a LIST OF members field of `" <> ri.riName <> "`")
        (App _ ref [App _ s []], Just ri)
          | resolvedToText ref == "members of"
          , Just (getUnique s) == env.envSubject -> do
              checkMembersOf ctx ref ri
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

-- | Does the expression read the aggregation's member?
mentionsMember :: OFExpr -> Bool
mentionsMember = \case
  OFMembersVar _ -> True
  OFBin _ a b    -> mentionsMember a || mentionsMember b
  OFCmp _ a b    -> mentionsMember a || mentionsMember b
  OFAnd a b      -> mentionsMember a || mentionsMember b
  OFOr a b       -> mentionsMember a || mentionsMember b
  OFNot a        -> mentionsMember a
  OFNeg a        -> mentionsMember a
  OFCond a b c   -> mentionsMember a || mentionsMember b || mentionsMember c
  OFNpCall _ as  -> any mentionsMember as
  OFScaleCalc _ a -> mentionsMember a
  _              -> False

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
-- They are recognised only when the call resolves to the PRELUDE's
-- definition: a module that defines its own @sum@ gets a refusal, not
-- OpenFisca's aggregation.
preludeRecognised :: [Text]
preludeRecognised = ["sum", "map", "count", "any", "all", "max", "min"]

-- | Helpers the export recognises by name and compiles to an OpenFisca
-- construct, which the MODULE defines (the prelude has none of them). Each is
-- accepted only when its definition is the canonical one ('checkConvention',
-- 'checkMembersOf'); a module whose definition differs gets a refusal rather
-- than OpenFisca's semantics silently replacing its own.
conventionNames :: [Text]
conventionNames = ["period reaches", "scale tax", "members of"]

isBuiltinRef :: Resolved -> Bool
isBuiltinRef r = (getUnique r).moduleUri == builtinUri

-- | Does the name resolve to a definition in the L4 prelude? Tested by the
-- defining module's basename (the prelude reaches us as a @file:@ URI or as
-- @jl4-embedded:/prelude.l4@ depending on the resolver), and never this module.
isPreludeRef :: Ctx -> Resolved -> Bool
isPreludeRef ctx r =
  let uri = (getUnique r).moduleUri
  in uri /= ctx.ctxSelfUri && uriBasename uri == "prelude.l4"

uriBasename :: NormalizedUri -> Text
uriBasename uri = case reverse (Text.splitOn "/" (getUri (fromNormalizedUri uri))) of
  (b : _) -> b
  []      -> ""

-- | The canonical definitions of the name-recognised helpers, as L4 source.
canonicalSource :: Text -> Text
canonicalSource = \case
  "period reaches" -> Text.unlines
    [ "    GIVEN `the period` IS A Period, y IS A NUMBER, m IS A NUMBER"
    , "    GIVETH A BOOLEAN"
    , "    `period reaches` MEANS"
    , "        (`the period`'s year GREATER THAN y)"
    , "        OR (`the period`'s year EQUALS y AND `the period`'s month AT LEAST m)" ]
  "scale tax" -> Text.unlines
    [ "    GIVEN income IS A NUMBER, brackets IS A LIST OF Bracket"
    , "    GIVETH A NUMBER"
    , "    `scale tax` MEANS"
    , "        CONSIDER brackets"
    , "        WHEN EMPTY THEN 0"
    , "        WHEN b FOLLOWED BY rest THEN"
    , "            CONSIDER rest"
    , "            WHEN EMPTY THEN b's rate TIMES (max 0 (income MINUS b's threshold))"
    , "            WHEN nextB FOLLOWED BY anything THEN"
    , "                  (b's rate TIMES (max 0 ((min income (nextB's threshold)) MINUS b's threshold)))"
    , "                PLUS (`scale tax` OF income, rest)" ]
  _ -> ""

-- | The alpha-normalised shape ('shapeOf') of each canonical definition.
canonicalShape :: Text -> Text
canonicalShape = \case
  "period reaches" ->
    "(__OR__ (__GT__ (. $0 year) $1) (__AND__ (__EQUALS__ (. $0 year) $1) (__GEQ__ (. $0 month) $2)))"
  "scale tax" ->
    "(CONSIDER $1 (WHEN EMPTY 0) (WHEN (FOLLOWED_BY $2 $3) (CONSIDER $3 (WHEN EMPTY (__TIMES__ (. $2 rate) (@max 0 (__MINUS__ $0 (. $2 threshold))))) (WHEN (FOLLOWED_BY $4 $5) (__PLUS__ (__TIMES__ (. $2 rate) (@max 0 (__MINUS__ (@min $0 (. $4 threshold)) (. $2 threshold)))) (SELF $0 $3))))))"
  _ -> ""

-- | Accept a call to a name-recognised helper only when the module defines it
-- canonically.
checkConvention :: Ctx -> Text -> Resolved -> Either Text ()
checkConvention ctx nm ref = case Map.lookup (getUnique ref) ctx.ctxDecides of
  Just d | decideShape ctx d == canonicalShape nm -> Right ()
  found ->
    Left ("`" <> nm <> "` is recognised by name and compiled to "
          <> (if nm == "scale tax" then "OpenFisca's marginal-rate `.calc()`" else "OpenFisca's dated formulas (formula_YYYY_MM)")
          <> ", so the export accepts it only when this module defines it exactly as:\n"
          <> canonicalSource nm
          <> (if isJust found then "This module's definition differs (only the names of its inputs and local variables may change), so OpenFisca would compute something else; rename your helper."
                              else "Here it is not defined in this module; copy the definition above into it."))

-- | @members of@ must return every LIST OF members field of the group.
checkMembersOf :: Ctx -> Resolved -> RecordInfo -> Either Text ()
checkMembersOf ctx ref ri =
  let listFields = [ fi.fiL4 | fi <- ri.riFields, isJust fi.fiListElem ]
      canonical  = "`members of` MEANS concat (LIST " <> Text.intercalate ", " [ "h's " <> backtickIfSpaced f | f <- listFields ] <> ")"
      bad = Left ("`members of` is recognised by name and compiled to all of the group's members, so the export accepts it only when this module defines it as `GIVEN h IS A "
                  <> ri.riName <> "` and " <> canonical
                  <> " (every LIST OF field of `" <> ri.riName <> "`, in any order). This module's definition differs; rename your helper.")
  in case Map.lookup (getUnique ref) ctx.ctxDecides of
       Just (MkDecide _ (MkTypeSig _ (MkGivenSig _ [g]) _) _ body) ->
         let hU = getUnique (givenName g)
             projOf = \case
               Proj _ (App _ h []) f | getUnique h == hU -> Just (resolvedToText f)
               _ -> Nothing
             returned = case body of
               App _ c [List _ es] | resolvedToText c == "concat", isPreludeRef ctx c -> traverse projOf es
               e -> (: []) <$> projOf e
         in case returned of
              Just fs | sort fs == sort listFields -> Right ()
              _ -> bad
       _ -> bad

-- | A DECIDE's body, alpha-normalised: see 'shapeOf'.
decideShape :: Ctx -> Decide Resolved -> Text
decideShape ctx (MkDecide _ (MkTypeSig _ (MkGivenSig _ gs) _) (MkAppForm _ nameRes _ _) body) =
  shapeOf ctx (getUnique nameRes) (map (getUnique . givenName) gs) body

-- | Render an expression alpha-normalised, so that two definitions that differ
-- only in the names of their inputs and local variables render the same: the
-- inputs are @$0@, @$1@, …, names the body binds are numbered on from there,
-- the definition itself is @SELF@, builtins print bare, prelude names print
-- @\@name@ and anything else @#name@. A construct this does not know renders
-- as @?@, which matches no canonical shape.
shapeOf :: Ctx -> Unique -> [Unique] -> Expr Resolved -> Text
shapeOf ctx self params body = go body
 where
  binders = nubOrd (params <> [ u | Def u _ <- toList body ])
  idx     = Map.fromList (zip binders [0 :: Int ..])
  nameOf r =
    let u = getUnique r
    in case Map.lookup u idx of
         Just i -> "$" <> tshow i
         Nothing
           | u == self       -> "SELF"
           | isBuiltinRef r  -> resolvedToText r
           | isPreludeRef ctx r -> "@" <> resolvedToText r
           | otherwise       -> "#" <> resolvedToText r
  sx xs = "(" <> Text.unwords xs <> ")"
  go e = case binView e of
    Just (op, a, b) -> sx [op, go a, go b]
    Nothing -> case e of
      Not _ a            -> sx ["__NOT__", go a]
      Proj _ a f         -> sx [".", go a, resolvedToText f]
      App _ r []         -> nameOf r
      App _ r as         -> sx (nameOf r : map go as)
      AppNamed _ r nes _ -> sx ("WITH" : nameOf r : [ sx [resolvedToText f, go x] | MkNamedExpr _ f x <- nes ])
      Lit _ (NumericLit _ n) -> renderRat n
      Lit _ (StringLit _ t)  -> tshow t
      List _ es          -> sx ("LIST" : map go es)
      IfThenElse _ c t f -> sx ["IF", go c, go t, go f]
      MultiWayIf _ gs o  -> sx ("BRANCH" : [ sx [go c, go b] | MkGuardedExpr _ c b <- gs ] <> [go o])
      Consider _ s bs    -> sx ("CONSIDER" : go s : map branch bs)
      _                  -> "?"
  branch = \case
    MkBranch _ (When _ p) b    -> sx ["WHEN", pat p, go b]
    MkBranch _ (Otherwise _) b -> sx ["OTHERWISE", go b]
  pat = \case
    PatVar _ n      -> nameOf n
    PatApp _ c []   -> nameOf c
    PatApp _ c ps   -> sx (nameOf c : map pat ps)
    PatCons _ a b   -> sx ["FOLLOWED_BY", pat a, pat b]
    PatLit _ (NumericLit _ n) -> renderRat n
    PatLit _ (StringLit _ t)  -> tshow t
    PatExpr _ x     -> sx ["EXPR", go x]
  renderRat n
    | denominator n == 1 = tshow (numerator n)
    | otherwise          = tshow (numerator n) <> "/" <> tshow (denominator n)

-- ---------------------------------------------------------------------------
-- Module scanning helpers
-- ---------------------------------------------------------------------------

topDecls :: Module Resolved -> [TopDecl Resolved]
topDecls (MkModule _ _ section) = goSection section
 where
  goSection (MkSection _ _ _ _ decls) = decls >>= \case
    Section _ sub -> goSection sub
    d             -> [d]

collectDecides :: Module Resolved -> Map Unique (Decide Resolved)
collectDecides m = Map.fromList
  [ (getUnique (decideName d), d) | Decide _ d <- topDecls m ]

collectRecordNames :: Module Resolved -> Set Text
collectRecordNames m = Set.fromList
  [ resolvedToText recRes
  | Declare _ (MkDeclare _ _ (MkAppForm _ recRes _ _) (RecordDecl{})) <- topDecls m ]

collectSynonyms :: Module Resolved -> Map Text (Type' Resolved)
collectSynonyms m = Map.fromList
  [ (resolvedToText tyRes, ty)
  | Declare _ (MkDeclare _ _ (MkAppForm _ tyRes [] _) (SynonymDecl _ ty)) <- topDecls m ]

collectRecords :: Ctx -> Set Text -> Module Resolved -> Map Text RecordInfo
collectRecords ctx recordNames m = Map.fromList
  [ (nm, RecordInfo
       { riName   = nm
       , riKey    = Text.toLower (pyIdent nm)
       , riPlural = Text.toLower (pyIdent nm) <> "s"
       , riPy     = pyType nm
       , riFields =
           [ fieldInfo ctx recordNames fRes fTy mMeans
           | MkTypedName _ fRes fTy _ mMeans <- fields
           ]
       })
  | Declare _ (MkDeclare _ _ (MkAppForm _ recRes _ _) (RecordDecl _ _ fields)) <- topDecls m
  , let nm = resolvedToText recRes
  ]

fieldInfo :: Ctx -> Set Text -> Resolved -> Type' Resolved -> Maybe (Expr Resolved) -> FieldInfo
fieldInfo ctx recordNames fRes fTy mMeans =
  case listElemRecord ctx recordNames fTy of
    Just elemName -> FieldInfo nm l4 (Right OFFloat) stored (Just elemName)
    Nothing       -> FieldInfo nm l4 (ofTypeOf ctx fTy) stored Nothing
 where
  l4     = resolvedToText fRes
  nm     = pyIdent l4
  stored = isNothing mMeans

-- | If a type is @LIST OF <R>@ for a record @R@ declared in this module,
-- return @R@'s name. A list of anything else is not a member list.
listElemRecord :: Ctx -> Set Text -> Type' Resolved -> Maybe Text
listElemRecord ctx recordNames ty = case expandSynonyms ctx ty of
  TyApp _ l [inner]
    | getUnique l == listUnique
    , TyApp _ r [] <- expandSynonyms ctx inner
    , resolvedToText r `Set.member` recordNames -> Just (resolvedToText r)
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
      , [ (getUnique c, EnumCon enPy (pyIdent (resolvedToText c)) ty) | MkConDecl _ c _ <- conDecls ]
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
  :: Ctx -> Module Resolved
  -> ( [LowerError]
     , Set Unique
     , Map Unique (ParamInfo, OFScalarParam)
     , Map Unique (ParamInfo, OFScaleParam) )
collectParams ctx m =
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
           bs <- readScale ctx yU body
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

-- | Keys OpenFisca's parameter loader treats specially (metadata keys, which
-- it skips as children, and the two keys that turn a node into a leaf), and
-- the public attributes of its parameter objects, which a child of the same
-- name would overwrite or be hidden by. Measured against openfisca-core
-- 45.0.4: `children` and `get_at_instant` break the parameter tree, and the
-- rest are refused because they were not shown safe in every position.
openFiscaReservedKeys :: Set Text
openFiscaReservedKeys = Set.fromList
  [ "brackets", "description", "documentation", "metadata", "reference", "unit", "values"
  , "add_child", "children", "clone", "file_path", "get_at_instant", "get_descendants"
  , "merge", "name", "update", "validate", "values_history", "values_list" ]

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
readScale :: Ctx -> Maybe Unique -> Expr Resolved -> Either Text [OFBracket]
readScale ctx yU = \case
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
    rows <- traverse (readRow ctx) es
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

-- | @band OF threshold, rate@ → (threshold, rate). The bracket builder must be
-- a two-input helper of this module that builds a record with its first input
-- as @threshold@ and its second as @rate@: those are the two field names the
-- canonical @scale tax@ reads, so a builder that swapped them would swap
-- OpenFisca's thresholds and rates.
readRow :: Ctx -> Expr Resolved -> Either Text (Rational, Rational)
readRow ctx = \case
  App _ f [Lit _ (NumericLit _ t), Lit _ (NumericLit _ r)]
    | Just d <- Map.lookup (getUnique f) ctx.ctxDecides
    , isBracketBuilder d -> Right (t, r)
    | otherwise ->
        Left ("`" <> resolvedToText f <> "` is not a bracket builder the export recognises: it must be defined in this module as `GIVEN t IS A NUMBER, r IS A NUMBER` and `Bracket WITH threshold IS t, rate IS r` (any record and input names; these two field names)")
  _ -> Left ("each bracket of a @desc scale must be `(band OF <threshold literal>, <rate literal>)`. " <> scaleShapeMsg)
 where
  isBracketBuilder (MkDecide _ (MkTypeSig _ (MkGivenSig _ [g1, g2]) _) _ body) =
    let u1 = getUnique (givenName g1)
        u2 = getUnique (givenName g2)
        isVar v = \case App _ x [] -> getUnique x == v; _ -> False
    in case body of
         AppNamed _ _ nes _ ->
           let fs = [ (resolvedToText fld, x) | MkNamedExpr _ fld x <- nes ]
           in length fs == 2
              && maybe False (isVar u1) (lookup "threshold" fs)
              && maybe False (isVar u2) (lookup "rate" fs)
         _ -> False
  isBracketBuilder _ = False

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
          checkConvention env.envCtx "period reaches" ref
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
  { roleKey    = roleKey fi.fiName
  , rolePlural = fi.fiName
  , roleLabel  = fi.fiName
  }

-- | The role key of a LIST OF field: its singular, by stripping one trailing
-- @s@. Words ending in @ss@, @us@ or @is@ are not English plurals of that shape
-- (@status@, @class@, @basis@), so they keep their name rather than become
-- @statu@. This is still a heuristic, and the key is only a label: OpenFisca
-- situations name a role by its plural, which is the field name unchanged.
roleKey :: Text -> Text
roleKey t = case Text.unsnoc t of
  Just (pre, 's')
    | not (Text.null pre)
    , not (any (`Text.isSuffixOf` pre) ["s", "u", "i"]) -> pre
  _ -> t

-- ---------------------------------------------------------------------------
-- Checks over the whole package
-- ---------------------------------------------------------------------------

-- | What the emitted module needs to load in OpenFisca: one definition per
-- entity name and exactly one person entity; distinct roles; and every Python
-- name bound once ('validateIdents' checks that each is a valid identifier).
validatePackage :: [OFEntity] -> OFPackage -> [LowerError]
validatePackage allEnts pkg =
     entityConflicts
  <> personCount
  <> concatMap roleChecks pkg.pkgEntities
  <> topLevelClashes
  <> entityKeyClashes
  <> formulaLocalClashes
  <> concatMap enumMemberChecks pkg.pkgEnums
 where
  mkErr = LowerError ""

  entityConflicts =
    [ mkErr ("the record `" <> e.entPy <> "` would be both a group entity (it has a LIST OF field) and the person entity; OpenFisca needs one definition per entity")
    | e <- pkg.pkgEntities
    , any (\e' -> e'.entPy == e.entPy && e' /= e) allEnts
    ]

  persons = [ e.entPy | e <- pkg.pkgEntities, e.entIsPerson ]
  personCount = case persons of
    [_] -> []
    []  -> [mkErr "no person entity: OpenFisca needs exactly one entity whose members are individuals (a record without LIST OF fields)"]
    ps  -> [mkErr ("OpenFisca allows exactly one person entity, but this module would declare "
                   <> tshow (length ps) <> ": " <> Text.intercalate ", " (map backtick ps)
                   <> ". Export them from separate modules, or make one of them a group entity (a record with a LIST OF field of the other).")]

  roleChecks e =
    let keys    = map (.roleKey) e.entRoles
        plurals = map (.rolePlural) e.entRoles
        varsOnE = [ v.varName | v <- pkg.pkgVariables, v.varEntity == e.entPy ]
    in [ mkErr ("two roles of `" <> e.entPy <> "` share the key `" <> k <> "`; rename one of the LIST OF fields") | k <- dups keys ]
       <> [ mkErr ("the role `" <> p <> "` of `" <> e.entPy <> "` has the same name as a variable of that entity; an OpenFisca situation could not tell them apart, so rename one")
          | p <- plurals, p `elem` varsOnE ]

  topLevelClashes =
    [ mkErr ("two definitions would both be bound to the Python name `" <> n <> "` in the emitted module; rename one")
    | n <- dups (map (.entPy) pkg.pkgEntities <> map (.enName) pkg.pkgEnums <> map (.varName) pkg.pkgVariables)
    ]

  -- Two records whose names differ only in case (`household`, `Household`)
  -- get one entity key, and so one plural: a situation's `households` could
  -- not say which it means. (The plural is the key plus `s`, so distinct keys
  -- give distinct plurals.)
  entityKeyClashes =
    [ mkErr ("two entities would both have the OpenFisca key `" <> k <> "` (and the situation key `" <> k <> "s`); rename one of the records")
    | k <- dups (map (.entKey) pkg.pkgEntities) ]

  -- Inside a formula the entity's key, `period` and `parameters` are the
  -- formula's own arguments, so a module-level name spelled the same is
  -- hidden there: an enum class (read as `Class.member`) or a group entity
  -- (read for its role constants, `Entity.ROLE`).
  entKeys = map (.entKey) pkg.pkgEntities
  formulaLocals = entKeys <> ["period", "parameters"]
  formulaLocalClashes =
    [ mkErr ("the enum `" <> en.enName <> "` has the same Python name as " <> localName en.enName
             <> ", which a formula binds as its own argument, so the formula could not read the enum. Rename the enum (for instance, capitalise it).")
    | en <- pkg.pkgEnums, en.enName `elem` formulaLocals ]
    <> [ mkErr ("the group record `" <> e.entPy <> "` has the same Python name as " <> localName e.entPy
                <> ", which a formula binds as its own argument, so a formula could not read its roles. Rename the record (for instance, capitalise it).")
       | e <- pkg.pkgEntities, not e.entIsPerson, e.entPy `elem` formulaLocals ]
  localName n
    | n `elem` entKeys = "the key of an entity (`" <> n <> "`)"
    | otherwise     = "`" <> n <> "`"

  -- OpenFisca's Enum (a Python Enum) cannot hold two members of one name,
  -- rejects `mro`, lets a member hide its own `encode` classmethod, and sets
  -- `names`, `indices` and `enums` on the class after the members exist.
  -- A leading underscore reaches Python's own enum machinery.
  enumMemberChecks en =
    [ mkErr ("the constructors " <> Text.intercalate " and " (map backtick same)
             <> " of the enum `" <> en.enName <> "` " <> (if length same == 2 then "both" else "all")
             <> " become the Python name `" <> m <> "`; rename one")
    | m <- dups (map fst en.enMembers)
    , let same = [ l4 | (m', l4) <- en.enMembers, m' == m ] ]
    <> [ mkErr ("the constructor `" <> l4 <> "` of the enum `" <> en.enName <> "` becomes the Python name `" <> m
                <> "`, which OpenFisca's Enum reserves (" <> Text.intercalate ", " enumReserved
                <> ", or a leading underscore); rename it")
       | (m, l4) <- en.enMembers, m `elem` enumReserved || "_" `Text.isPrefixOf` m ]
  enumReserved = ["encode", "mro", "names", "indices", "enums"]

  dups xs = nubOrd [ x | (x, i) <- zip xs [0 :: Int ..], (y, j) <- zip xs [0 ..], x == y, i < j ]

-- | A formula that reads its own variable, directly or through other
-- decisions, is recursion. OpenFisca evaluates both branches of an IF, so such
-- a formula always fails with CycleError, even where L4 stops at a base case.
recursionErrors :: OFPackage -> [LowerError]
recursionErrors pkg =
  [ LowerError (varL4Of c) ("recursion: " <> Text.intercalate " -> " (map backtick (c : cs <> [c]))
      <> ". OpenFisca evaluates both branches of every IF, so a formula that reaches itself always fails with CycleError, even where L4 stops at a base case. The export does not compile recursion; write the decision without it.")
  | CyclicSCC (c : cs) <- stronglyConnComp graph ]
 where
  computed = [ v | v <- pkg.pkgVariables, isJust v.varFormula ]
  names    = Set.fromList (map (.varName) computed)
  graph    =
    [ (v.varName, v.varName, nubOrd [ r | r <- concatMap variableRefs (maybeToList v.varFormula <> map snd v.varDated), r `Set.member` names ])
    | v <- computed ]
  varL4Of n = maybe n (.varL4) (find (\v -> v.varName == n) computed)

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

enumResultMsg :: Text -> Text
enumResultMsg en =
  "the result type is the enum `" <> en <> "`: the OpenFisca export compiles enums only as inputs matched by CONSIDER, "
  <> "not as results. Return a BOOLEAN or a NUMBER instead, e.g. one BOOLEAN decision per constructor."

enumValueMsg :: Text -> Text -> Text
enumValueMsg con en =
  "`" <> con <> "` is a constructor of the enum `" <> en <> "`; the OpenFisca export compiles enum values only as the arms of a CONSIDER over an enum input "
  <> "(`CONSIDER p's status WHEN " <> con <> " THEN …`). Using one as a value, or returning one, is not supported."

helperCallMsg :: Text -> Text
helperCallMsg nm =
  "cannot compile the call to `" <> nm <> "`: it is not an @export decision, and the export does not inline helpers "
  <> "(an OpenFisca formula takes no arguments; it can only read other variables). Mark `" <> nm
  <> "` @export if it has the decision shape (a subject and a period), or write its body out here."

shadowedPreludeMsg :: Ctx -> Resolved -> Text
shadowedPreludeMsg ctx r =
  let nm = resolvedToText r
      u  = getUnique r
      wher | u.moduleUri == ctx.ctxSelfUri = "this module"
           | otherwise                     = "`" <> uriBasename u.moduleUri <> "`"
  in "`" <> nm <> "` here resolves to a definition in " <> wher <> ", not to the prelude's `" <> nm
     <> "`. The export recognises `" <> nm <> "` only as the prelude function (it compiles it to OpenFisca's own "
     <> (if nm `elem` ["max", "min"] then "np.maximum / np.minimum" else "aggregation")
     <> "), so it cannot compile this call. Rename your definition, or use the prelude's."

groupValueInMember :: Text -> Text
groupValueInMember what =
  "inside an aggregation over members, the per-member expression can read only the member's own fields and @export decisions, the period, parameters and constants; "
  <> what <> " is a value of the group, which OpenFisca would have to project onto the members (`project`), and the export does not compile that"

-- ---------------------------------------------------------------------------
-- Name helpers
-- ---------------------------------------------------------------------------

decideName :: Decide Resolved -> Resolved
decideName (MkDecide _ _ (MkAppForm _ r _ _) _) = r

resolvedToText :: Resolved -> Text
resolvedToText = rawNameToText . rawName . getActual

backtick :: Text -> Text
backtick t = "`" <> t <> "`"

backtickIfSpaced :: Text -> Text
backtickIfSpaced t = if Text.any (== ' ') t then backtick t else t

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
-- names @period@ / @parameters@ / @entity@ / @formula@, the lowercase
-- module-level names the emitted file binds (@np@, @build_entity@), and the
-- builtins it uses (@float@ etc. as value types, @super@ in the system class).
pyReserved :: Set Text
pyReserved = Set.fromList
  [ "and","as","assert","async","await","break","class","continue","def","del"
  , "elif","else","except","false","finally","for","from","global","if","import"
  , "in","is","lambda","nonlocal","none","not","or","pass","raise","return","true"
  , "try","while","with","yield","match","case"
  , "period","parameters","entity","formula"
  , "np","build_entity"
  , "float","bool","str","int","super" ]

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
  , "_PARAMETERS"
  -- builtins the emitted module uses
  , "float", "bool", "str", "int", "super"
  -- a formula's own arguments
  , "period", "parameters"
  -- names a Variable class body binds before it reads an entity or an enum
  , "value_type", "possible_values", "default_value", "entity", "definition_period", "label" ]

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
    ((nm, grp) : _) -> Left (LowerError "" (collisionMsg nm (nub grp)))
    [] -> Right (dedupOn (.varName) vs)
 where
  byName = Map.fromListWith (flip (<>)) [ (v.varName, [v]) | v <- vs ]

-- | Say what actually differs. The same L4 name read with two different
-- definition periods is not a naming problem, and used to be reported as one.
collisionMsg :: Text -> [OFVariable] -> Text
collisionMsg nm grp
  | [l4] <- nubOrd (map (.varL4) grp)
  , length (nubOrd (map (pyPeriodName . (.varPeriod)) grp)) > 1 =
      "the OpenFisca variable `" <> nm <> "` (from `" <> l4 <> "`) is needed with two definition periods: "
      <> Text.intercalate " and " (nubOrd (map (pyPeriodName . (.varPeriod)) grp))
      <> ". A decision with a `period` input is computed per MONTH, and one without is ETERNITY; "
      <> "every @export decision that reads `" <> l4 <> "` must agree. Give them all a `period` input, or none."
  | [l4] <- nubOrd (map (.varL4) grp) =
      "the OpenFisca variable `" <> nm <> "` (from `" <> l4 <> "`) would be defined twice, differently (on different entities or with different types); rename one"
  | otherwise =
      "name collision: distinct L4 definitions ("
      <> Text.intercalate ", " [ "`" <> l4 <> "`" | l4 <- nubOrd (map (.varL4) grp) ]
      <> ") both compile to the OpenFisca variable `" <> nm
      <> "`. A decision, field, or parameter that shares a (sanitised) name "
      <> "with another is unsafe in OpenFisca — rename one."
 where
  pyPeriodName = \case OFMonth -> "MONTH"; OFYear -> "YEAR"; OFEternity -> "ETERNITY"
