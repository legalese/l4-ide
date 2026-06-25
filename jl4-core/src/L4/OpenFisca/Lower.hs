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
import Data.Char (isAlphaNum, isDigit, toLower)
import Data.Either (partitionEithers)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text

import Optics ((^.))

import L4.Annotation (getAnno)
import L4.Export (ExportedFunction (..), getExportedFunctions)
import L4.OpenFisca.IR
import L4.Syntax

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
  , fiType     :: !OFType
  , fiStored   :: !Bool
  , fiListElem :: !(Maybe Text)
  }

lowerModule :: Module Resolved -> Either [LowerError] OFPackage
lowerModule mod' =
  case getExportedFunctions mod' of
    []  -> Left [LowerError "" "no @export-annotated DECIDE found to compile to OpenFisca"]
    efs ->
      let records     = collectRecords mod'
          scaleParams = collectScaleParams mod'
          scalePaths  = Map.map (.spPath) scaleParams
          exportedU   = Map.fromList
            [ (getUnique (decideName ef.exportDecide), pyIdent ef.exportName)
            | ef <- efs
            ]
          results    = map (lowerOne records exportedU scalePaths) efs
          (errs, ok) = partitionEithers results
      in if not (null errs)
           then Left errs
           else
             let ents  = dedupOn (.entPy)   (concatMap fst ok)
                 vars  = dedupOn (.varName) (concatMap snd ok)
             in Right OFPackage
                  { pkgSource     = moduleSource mod'
                  , pkgEntities   = ents
                  , pkgVariables  = vars
                  , pkgParameters = Map.elems scaleParams
                  }

-- | Lower a single exported decision into the entity it lives on plus the
-- variables it introduces (its inputs + the computed variable itself).
lowerOne
  :: Map Text RecordInfo
  -> Map Unique Text   -- ^ exported decisions: unique → variable name
  -> Map Unique Text   -- ^ scale parameters: unique → dotted path
  -> ExportedFunction
  -> Either LowerError ([OFEntity], [OFVariable])
lowerOne records exportedU scalePaths ef = do
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
        , envScalars    = Map.fromList [ (getUnique (givenName g), pyIdent (givenText g)) | g <- others ]
        , envExported   = exportedU
        , envListFields = subjListFields
        }
  formula <- mapLeft (LowerError fnName) (lowerExpr env body)

  -- Stored scalar (non-list) fields of an entity-record become input variables.
  let inputsFor e ri =
        [ OFVariable
            { varName    = fi.fiName
            , varType    = fi.fiType
            , varEntity  = e.entPy
            , varEntKey  = e.entKey
            , varPeriod  = ofPeriod
            , varLabel   = fi.fiName
            , varFormula = Nothing
            }
        | fi <- ri.riFields, fi.fiStored, isNothing fi.fiListElem
        ]
      subjectInputs = maybe [] (inputsFor ent) mSubjRi
      memberInputs  = concat (zipWith inputsFor memberEntities memberRecords)
      scalarInputs =
        [ OFVariable
            { varName    = pyIdent (givenText g)
            , varType    = maybe OFFloat ofTypeOfL4 (givenType g)
            , varEntity  = ent.entPy
            , varEntKey  = ent.entKey
            , varPeriod  = ofPeriod
            , varLabel   = givenText g
            , varFormula = Nothing
            }
        | g <- others
        ]
      computed =
        OFVariable
          { varName    = fnName
          , varType    = maybe OFFloat ofTypeFromGiveth mGiveth
          , varEntity  = ent.entPy
          , varEntKey  = ent.entKey
          , varPeriod  = ofPeriod
          , varLabel   = if Text.null ef.exportDescription
                           then resolvedToText fnRes
                           else ef.exportDescription
          , varFormula = Just formula
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
  , envScalars    :: !(Map Unique Text)  -- ^ free scalar params → input-variable names
  , envExported   :: !(Map Unique Text)  -- ^ exported decisions → variable names
  , envListFields :: ![Text]             -- ^ the subject's @LIST OF@ field names (roles)
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
    other -> Left (unsupported other)

  -- @p's field@: on the subject → a variable read; on a member (inside an
  -- aggregation lambda) → a member-array read.
  lowerProj inner field = case inner of
    App _ s [] | Just (getUnique s) == env.envSubject ->
      Right (OFVarRef (pyIdent (resolvedToText field)))
    App _ s [] | Just (getUnique s) == env.envMember ->
      Right (OFMembersVar (pyIdent (resolvedToText field)))
    _ -> Left "only projection off the subject (or a member, inside an aggregation) is supported (nested records are a later milestone)"

  -- After resolution L4 desugars operators to builtin applications
  -- (@a * b@ → @App __TIMES__ [a, b]@), so arithmetic/boolean/comparison ops
  -- arrive here rather than as 'Times'/'And'/… constructors.
  lowerApp ref args =
    let u = getUnique ref
        nm = resolvedToText ref
    in case scaleCall nm args of
     Just res -> res
     Nothing -> case aggregation nm args of
      Just res -> res
      Nothing -> case builtinOp nm of
       Just mk -> traverse go args >>= mk
       Nothing
        | Just b <- boolLit nm                      -> Right (OFBoolLit b)
        | Just name <- Map.lookup u env.envExported -> Right (OFVarRef name)  -- call another decision
        | not (null args)                           -> Left ("cannot compile call to `" <> nm <> "` — OpenFisca formulas take no arguments; only references to other @export decisions are supported")
        | Just name <- Map.lookup u env.envScalars  -> Right (OFVarRef name)
        | Just u == env.envPeriod                   -> Right (OFLocal "period")
        | Just u == env.envSubject                  -> Left "the subject entity cannot be used as a value"
        | otherwise                                 -> Left ("unbound reference `" <> nm <> "` (recursion, prelude functions, and local bindings are not supported in v1)")

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
  Exponent{}   -> "exponent (^)"
  AppNamed{}   -> "named-argument application"
  Inert{}      -> "inert scaffolding"
  _            -> "expression"

-- ---------------------------------------------------------------------------
-- Module scanning helpers
-- ---------------------------------------------------------------------------

collectRecords :: Module Resolved -> Map Text RecordInfo
collectRecords (MkModule _ _ section) = Map.fromList (goSection section)
 where
  goSection (MkSection _ _ _ decls) = decls >>= goDecl
  goDecl = \case
    Declare _ (MkDeclare _ _ (MkAppForm _ recRes _ _) (RecordDecl _ _ fields)) ->
      let nm = resolvedToText recRes
      in [(nm, RecordInfo
              { riKey    = Text.toLower (pyIdent nm)
              , riPlural = Text.toLower (pyIdent nm) <> "s"
              , riPy     = pyType nm
              , riFields =
                  [ fieldInfo fRes fTy mMeans
                  | MkTypedName _ fRes fTy mMeans <- fields
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
  goSection (MkSection _ _ _ decls) = decls >>= goDecl
  goDecl = \case
    Decide _ d@(MkDecide _ _ (MkAppForm _ nameRes _ _) body)
      | Just path <- scaleAnnotation d
      , Just bs   <- readScale body ->
          [(getUnique nameRes, OFScaleParam { spPath = path, spBrackets = bs })]
    Section _ sub -> goSection sub
    _ -> []

-- | The dotted path from a @scale <path>@ description annotation, if present.
scaleAnnotation :: Decide Resolved -> Maybe Text
scaleAnnotation d = do
  desc <- getAnno d ^. annDesc
  case Text.words (getDesc desc) of
    ("scale" : rest) | not (null rest) -> Just (Text.intercalate "." rest)
    _                                  -> Nothing

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
  MultiWayIf _ guards _otherwise -> do
    arms <- traverse readArm guards
    pure (alignByIndex arms)
  _ -> Nothing

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

fieldInfo :: Resolved -> Type' Resolved -> Maybe (Expr Resolved) -> FieldInfo
fieldInfo fRes fTy mMeans =
  case listElemRecord fTy of
    Just elemName -> FieldInfo nm OFFloat        stored (Just elemName)
    Nothing       -> FieldInfo nm (ofTypeOfL4 fTy) stored Nothing
 where
  nm     = pyIdent (resolvedToText fRes)
  stored = isNothing mMeans

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
givenName (MkOptionallyTypedName _ r _) = r

givenType :: OptionallyTypedName Resolved -> Maybe (Type' Resolved)
givenType (MkOptionallyTypedName _ _ ty) = ty

givenText :: OptionallyTypedName Resolved -> Text
givenText = resolvedToText . givenName

isPeriodGiven :: OptionallyTypedName Resolved -> Bool
isPeriodGiven g = pyIdent (givenText g) == "period"

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
-- Types
-- ---------------------------------------------------------------------------

ofTypeFromGiveth :: GivethSig Resolved -> OFType
ofTypeFromGiveth (MkGivethSig _ ty) = ofTypeOfL4 ty

ofTypeOfL4 :: Type' Resolved -> OFType
ofTypeOfL4 = \case
  TyApp _ name _ -> case Text.toLower (resolvedToText name) of
    t | t `elem` ["number", "float", "double", "money", "decimal"] -> OFFloat
      | t `elem` ["int", "integer"]                                -> OFInt
      | t `elem` ["boolean", "bool"]                               -> OFBool
      | t `elem` ["string", "text"]                                -> OFStr
    _ -> OFFloat
  _ -> OFFloat

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
  in ensureNonDigit (if Text.null joined then "v" else joined)
 where
  isIdentChar c = isAlphaNum c || c == '_'
  ensureNonDigit t = case Text.uncons t of
    Just (h, _) | isDigit h -> "v_" <> t
    _                       -> t

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
