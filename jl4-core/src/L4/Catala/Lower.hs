-- | Lower a typechecked L4 module to the Catala surface IR.
--
-- v1 scope (spec §6): @DECLARE@ records and enums; first-order, non-recursive
-- @GIVEN@\/@GIVETH@\/@MEANS@\/@DECIDE@ functions over
-- @BOOLEAN@\/@NUMBER@\/@DATE@\/records\/enums\/@MAYBE@\/lists; @IF@, the boolean
-- and arithmetic builtins, projection, record construction, and calls to other
-- @\@export@ decisions. Everything else is rejected with a 'LowerError' naming
-- the construct — in one batch, all errors at once, following the OpenFisca
-- backend's presentation.
--
-- Emission split (R1, §8.1): every @\@export@ decision becomes a Catala
-- /scope/ whose inputs are its @GIVEN@ parameters and whose single @output@
-- carries the result; helpers become toplevel declarations.
--
-- __This module is the scaffold's minimal lowering.__ It covers the constructs
-- above and rejects the rest; @CONSIDER@\/@BRANCH@, list combinators, dates,
-- the Mode B exception ladders (R4) and the @#EVAL@-derived test scopes (R7)
-- are the next milestone. Every rule it produces is therefore emitted in Mode
-- A with a recorded fallback reason, so no Mode B claim is made that has not
-- been checked.
module L4.Catala.Lower
  ( lowerModule
  , LowerError (..)
  , renderLowerError
  ) where

import Base
import Data.Either (partitionEithers)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text

import Optics ((^.))

import L4.Annotation (getAnno)
import L4.Catala.IR
import L4.Export (ExportedFunction (..), ParsedDesc (..), getExportedFunctions, parseDescText)
import L4.Syntax

-- | A reason a definition could not be compiled to Catala.
data LowerError = LowerError
  { errFn  :: !Text   -- ^ the offending definition (empty = module-level)
  , errMsg :: !Text
  }
  deriving stock (Eq, Show)

renderLowerError :: LowerError -> Text
renderLowerError e
  | Text.null e.errFn = e.errMsg
  | otherwise         = "in `" <> e.errFn <> "`: " <> e.errMsg

-- ---------------------------------------------------------------------------
-- Module-level scan results
-- ---------------------------------------------------------------------------

-- | A record declaration, as seen by the lowering.
data RecordInfo = RecordInfo
  { riName   :: !Text                 -- ^ mangled structure name
  , riL4     :: !Text
  , riFields :: ![(Text, Type' Resolved)]  -- ^ mangled field name, L4 field type
  }

-- | An exported decision's Catala calling convention: the scope it became, the
-- input variables it expects, and the output variable holding its result.
data ScopeSig = ScopeSig
  { ssScope  :: !Text
  , ssInputs :: ![Text]
  , ssOutput :: !Text
  }

-- | Everything the expression lowering needs to resolve a name.
data LowerCtx = LowerCtx
  { ctxVars    :: !(Map Unique Text)          -- ^ in-scope value names (scope inputs, binders)
  , ctxCons    :: !(Map Unique Text)          -- ^ enum constructors → mangled case name
  , ctxRecords :: !(Map Unique RecordInfo)    -- ^ record type /and/ constructor uniques
  , ctxScopes  :: !(Map Unique ScopeSig)      -- ^ other @\@export@ decisions
  }

-- ---------------------------------------------------------------------------
-- Entry point
-- ---------------------------------------------------------------------------

lowerModule :: Module Resolved -> Either [LowerError] CatModule
lowerModule mod' =
  case getExportedFunctions mod' of
    []  -> Left [LowerError "" "no @export-annotated DECIDE found to compile to Catala"]
    efs ->
      let (enumErrs, enums) = partitionEithers (collectEnums mod')
          records           = collectRecords mod'
          conMap            = enumConstructors mod'
          scopeSigs         = Map.fromList (mapMaybe (scopeSigOf records) efs)
          ctx0 = LowerCtx
            { ctxVars    = Map.empty
            , ctxCons    = conMap
            , ctxRecords = records
            , ctxScopes  = scopeSigs
            }
          (fnErrs, lowered) = partitionEithers (map (lowerExport ctx0 records) efs)
          structs           = dedupOn (.stName) (Map.elems (Map.map structOf records))
          errs              = enumErrs <> fnErrs <> collisionErrors structs enums lowered
      in if not (null errs)
           then Left errs
           else Right CatModule
             { modName     = catUpper (dropExt (moduleSource mod'))
             , modSource   = moduleSource mod'
             , modWarnings = mapMaybe (\(_, _, w) -> w) lowered
             , modSegments =
                 [ SegMetadata
                     (  map DStruct structs
                     <> map DEnum enums
                     <> [ DScope d | (d, _, _) <- lowered ]
                     )
                 , SegCode [ ItemScope b | (_, b, _) <- lowered ]
                 ]
             }
 where
  structOf ri = CatStruct
    { stName   = ri.riName
    , stL4     = ri.riL4
    , stDesc   = Nothing
    , stFields =
        [ CatField { fdName = f, fdL4 = f, fdType = ty, fdDesc = Nothing }
        | (f, ty) <- mapMaybe (\(f, t) -> (f,) <$> eitherToMaybe (lowerType t)) ri.riFields
        ]
    }

-- | Distinct L4 names that mangle to one Catala name would silently conflate
-- in Catala's flat namespace; reject that, as the OpenFisca backend does.
collisionErrors
  :: [CatStruct] -> [CatEnum] -> [(CatScopeDecl, CatScopeBody, Maybe Text)] -> [LowerError]
collisionErrors structs enums lowered =
  [ LowerError ""
      ( "name collision: distinct L4 definitions ("
      <> Text.intercalate ", " [ "`" <> o <> "`" | o <- origs ]
      <> ") both compile to the Catala name `" <> mangled <> "` — rename one." )
  | (mangled, origs) <- nameCollisions pairs
  ]
 where
  pairs =
       [ (s.stName, s.stL4) | s <- structs ]
    <> [ (e.enName, e.enL4) | e <- enums ]
    <> [ (d.sdName, d.sdL4) | (d, _, _) <- lowered ]

-- ---------------------------------------------------------------------------
-- Exported decisions → scopes
-- ---------------------------------------------------------------------------

-- | The calling convention an exported decision presents to its callers.
scopeSigOf :: Map Unique RecordInfo -> ExportedFunction -> Maybe (Unique, ScopeSig)
scopeSigOf _records ef =
  let MkDecide _ (MkTypeSig _ (MkGivenSig _ givens) _) (MkAppForm _ fnRes _ _) _ = ef.exportDecide
  in Just
       ( getUnique fnRes
       , ScopeSig
           { ssScope  = catUpper ef.exportName
           , ssInputs = map (catIdent . resolvedToText . givenName) givens
           , ssOutput = catIdent ef.exportName
           }
       )

lowerExport
  :: LowerCtx
  -> Map Unique RecordInfo
  -> ExportedFunction
  -> Either LowerError (CatScopeDecl, CatScopeBody, Maybe Text)
lowerExport ctx0 _records ef = do
  let MkDecide _ (MkTypeSig _ (MkGivenSig _ givens) mGiveth) _ body = ef.exportDecide
      fnName   = ef.exportName
      scopeNm  = catUpper fnName
      outName  = catIdent fnName
      ctx      = ctx0
        { ctxVars = Map.fromList
            [ (getUnique (givenName g), catIdent (resolvedToText (givenName g))) | g <- givens ]
        }
      -- re-attribute a module-level error to this decision
      inScope le = LowerError fnName le.errMsg
  -- inputs
  inputs <- for givens \g -> do
    ty <- case givenType g of
      Nothing -> Left (LowerError fnName
                        ("parameter `" <> resolvedToText (givenName g)
                          <> "` has no declared type; Catala scope inputs must be typed"))
      Just t  -> mapLeft inScope (lowerType t)
    pure CatScopeVar
      { svName  = catIdent (resolvedToText (givenName g))
      , svL4    = resolvedToText (givenName g)
      , svKind  = if isJust (givenTypically g) then VarContext else VarInput
      , svShape = ShContent ty
      , svDesc  = Nothing
      }
  -- the single output: a `condition` when the decision is boolean, else `content T`
  retTy <- case mGiveth of
    Nothing -> Left (LowerError fnName
                      "no GIVETH: Catala needs the result type of an exported decision")
    Just (MkGivethSig _ t) -> mapLeft inScope (lowerType t)
  let outShape = case retTy of TBool -> ShCondition; t -> ShContent t
  bodyE <- mapLeft inScope (lowerExpr ctx body)
  -- TYPICALLY defaults become in-scope definitions of the `context` variables (R10).
  defaults <- for [ (g, d) | g <- givens, Just d <- [givenTypically g] ] \(g, d) -> do
    e <- mapLeft inScope (lowerExpr ctx d)
    pure CatRuleDef
      { rdVar      = catIdent (resolvedToText (givenName g))
      , rdModeA    = [ CatClause ClPlain Nothing (ConsEquals e) ]
      , rdModeB    = Nothing
      , rdEmitted  = ModeA
      , rdFallback = Nothing
      }
  let mainRule = CatRuleDef
        { rdVar   = outName
        , rdModeA =
            [ case outShape of
                ShCondition -> CatClause ClPlain (Just bodyE) ConsFulfilled
                ShContent _ -> CatClause ClPlain Nothing (ConsEquals bodyE)
            ]
        , rdModeB    = Nothing
        , rdEmitted  = ModeA
        , rdFallback = Just "no equivalence-checked exception ladder was derived for this rule"
        }
      decl = CatScopeDecl
        { sdName   = scopeNm
        , sdL4     = fnName
        , sdDesc   = if Text.null ef.exportDescription then Nothing else Just ef.exportDescription
        , sdIsTest = False
        , sdVars   =
            inputs
              <> [ CatScopeVar
                     { svName = outName, svL4 = fnName
                     , svKind = VarOutput, svShape = outShape, svDesc = Nothing }
                 ]
        }
      bdy = CatScopeBody { sbName = scopeNm, sbRules = defaults <> [mainRule] }
  pure ( decl
       , bdy
       , Just ("`" <> fnName <> "` was emitted in Mode A (boolean reference rendering); "
                <> "the Mode B exception ladder is not yet derived for it")
       )

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

-- | Lower an L4 type. @NUMBER@ becomes @decimal@ uniformly and @money@ is never
-- inferred (R2, §8.2); @STRING@ has no Catala counterpart at all (R11, §8.11).
lowerType :: Type' Resolved -> Either LowerError CatType
lowerType = \case
  TyApp _ name args ->
    let nm = resolvedToText name
    in case (Text.toLower nm, args) of
      (t, [inner]) | t `elem` ["list", "list of", "listof"] -> TList <$> lowerType inner
      (t, [inner]) | t `elem` ["maybe", "maybe of"]         -> TOption <$> lowerType inner
      (t, []) | t `elem` ["number", "decimal", "float", "double"] -> Right TDecimal
              | t `elem` ["integer", "int"]                       -> Right TInteger
              | t `elem` ["boolean", "bool"]                      -> Right TBool
              | t `elem` ["date"]                                 -> Right TDate
              | t `elem` ["string", "text"] ->
                  Left (LowerError "" ("`STRING` has no Catala counterpart; a string that is "
                                       <> "never inspected may be elided (R11), but it cannot be a type here"))
      (_, []) -> Right (TNamed (catUpper nm))
      _ -> Left (LowerError "" ("unsupported type application `" <> nm <> "`"))
  Fun {}    -> Left (LowerError "" "function-typed values are not expressible in Catala (R5)")
  Forall {} -> Left (LowerError "" "polymorphic types are not lowered in v1 (monomorphise the helper)")
  InfVar {} -> Left (LowerError "" "unresolved type: the typechecker did not pin this type down")
  Type {}   -> Left (LowerError "" "the type of types is not a Catala type")

-- ---------------------------------------------------------------------------
-- Expressions
-- ---------------------------------------------------------------------------

lowerExpr :: LowerCtx -> Expr Resolved -> Either LowerError CatExpr
lowerExpr ctx = go
 where
  err m = Left (LowerError "" m)

  go = \case
    Lit _ (NumericLit _ v)   -> Right (ELit (LDec v))
    Lit _ (StringLit _ _)    -> err "string literals have no Catala counterpart (§4.8)"
    Percent _ e -> case e of
      Lit _ (NumericLit _ v) -> Right (ELit (LDec (v / 100)))
      _                      -> EBin BDiv <$> go e <*> pure (ELit (LDec 100))
    IfThenElse _ c t e       -> EIf <$> go c <*> go t <*> go e
    Proj _ e field           -> (\e' -> EProj e' (catIdent (resolvedToText field))) <$> go e
    App _ ref args           -> lowerApp ref args
    AppNamed _ ref named _   -> lowerNamed ref named
    other                    -> err (unsupported other)

  -- After name resolution L4 desugars its operators into applications of
  -- builtins (@a * b@ becomes @App __TIMES__ [a, b]@), so arithmetic, boolean
  -- and comparison operators arrive here, not as 'Times'/'And'/… nodes.
  lowerApp ref args =
    let u  = getUnique ref
        nm = resolvedToText ref
    in case builtinOp nm of
      Just mk -> traverse go args >>= mapLeft (LowerError "") . mk
      Nothing
        | Just b <- boolLit nm                  -> Right (ELit (LBool b))
        | Just v <- Map.lookup u ctx.ctxVars, null args -> Right (EVar v)
        | Just c <- Map.lookup u ctx.ctxCons ->
            case args of
              []  -> Right (ECon c Nothing)
              [a] -> ECon c . Just <$> go a
              _   -> err ("enum constructor `" <> nm <> "` carries more than one payload, "
                          <> "which Catala's `content` cannot express")
        | Just ri <- Map.lookup u ctx.ctxRecords ->
            if length args == length ri.riFields
              then EStruct ri.riName . zip (map fst ri.riFields) <$> traverse go args
              else err ("record `" <> nm <> "` applied to " <> tshow (length args)
                        <> " argument(s) but has " <> tshow (length ri.riFields) <> " field(s)")
        | Just sig <- Map.lookup u ctx.ctxScopes ->
            if length args == length sig.ssInputs
              then (\as -> EScopeOut sig.ssScope (zip sig.ssInputs as) sig.ssOutput)
                     <$> traverse go args
              else err ("call to `" <> nm <> "` has " <> tshow (length args)
                        <> " argument(s) but its scope declares " <> tshow (length sig.ssInputs))
        | otherwise -> err ("unbound reference `" <> nm
                            <> "` (helper toplevels, prelude combinators, recursion and local "
                            <> "bindings are a later milestone)")

  -- `Applicant WITH age IS 70, …` — a record built with named fields.
  lowerNamed ref named = case Map.lookup (getUnique ref) ctx.ctxRecords of
    Nothing -> err ("named-argument application of `" <> resolvedToText ref
                    <> "` is only supported for record construction")
    Just ri -> do
      fs <- for named \(MkNamedExpr _ fld e) ->
              (catIdent (resolvedToText fld),) <$> go e
      -- emit in declaration order so output is stable regardless of source order
      let byName = Map.fromList fs
      vals <- for ri.riFields \(f, _) -> case Map.lookup f byName of
        Just v  -> Right (f, v)
        Nothing -> err ("record `" <> ri.riL4 <> "` is missing field `" <> f <> "`")
      Right (EStruct ri.riName vals)

  boolLit t = case Text.toLower t of
    "true"  -> Just True
    "false" -> Just False
    _       -> Nothing

-- | The builtins L4 desugars its infix operators into.
builtinOp :: Text -> Maybe ([CatExpr] -> Either Text CatExpr)
builtinOp nm = case nm of
  "__PLUS__"    -> Just (bin BAdd)
  "__MINUS__"   -> Just (bin BSub)
  "__TIMES__"   -> Just (bin BMul)
  "__DIVIDE__"  -> Just (bin BDiv)
  "__MODULO__"  -> Just (const (Left "Catala has no modulo operator on decimals"))
  "__EQUALS__"  -> Just (bin BEq)
  "__LEQ__"     -> Just (bin BLeq)
  "__GEQ__"     -> Just (bin BGeq)
  "__LT__"      -> Just (bin BLt)
  "__GT__"      -> Just (bin BGt)
  "__AND__"     -> Just (bin BAnd)
  "__OR__"      -> Just (bin BOr)
  "__NOT__"     -> Just (\case [a] -> Right (EUn UNot a); xs -> arity 1 xs)
  -- Catala has no `implies`; `a => b` is `(not a) or b` (§4.3).
  "__IMPLIES__" -> Just (\case [a, b] -> Right (EBin BOr (EUn UNot a) b); xs -> arity 2 xs)
  _             -> Nothing
 where
  bin op = \case [a, b] -> Right (EBin op a b); xs -> arity 2 xs
  arity :: Int -> [CatExpr] -> Either Text CatExpr
  arity n xs = Left ("operator `" <> nm <> "` expected " <> tshow n
                     <> " argument(s), got " <> tshow (length xs))

-- | A short human label for a rejected node, so the diagnostic names the
-- construct rather than the pass that tripped over it.
unsupported :: Expr Resolved -> Text
unsupported e = "unsupported construct for Catala: " <> case e of
  Regulative{} -> "deontic/regulative rule (PARTY/MUST/MAY) — out of Catala's domain (§5.1)"
  Event{}      -> "EVENT — out of Catala's domain (§5.1)"
  Fetch{}      -> "FETCH — Catala output is self-contained (§5.1)"
  Post{}       -> "POST — Catala output is self-contained (§5.1)"
  Env{}        -> "environment lookup — Catala output is self-contained (§5.1)"
  Breach{}     -> "BREACH — out of Catala's domain (§5.1)"
  RAnd{}       -> "regulative AND — out of Catala's domain (§5.1)"
  ROr{}        -> "regulative OR — out of Catala's domain (§5.1)"
  Record{}     -> "ledger RECORD — out of Catala's domain (§5.1)"
  ReadCell{}   -> "ledger RECALL — out of Catala's domain (§5.1)"
  Consider{}   -> "CONSIDER / pattern match (later milestone)"
  MultiWayIf{} -> "BRANCH cascade (later milestone)"
  Where{}      -> "WHERE binding (later milestone)"
  LetIn{}      -> "LET binding (later milestone)"
  Lam{}        -> "lambda — only combinator arguments survive (R5)"
  List{}       -> "list literal (later milestone)"
  Cons{}       -> "list cons (later milestone)"
  Concat{}     -> "string concatenation — Catala has no string type (§4.8)"
  AsString{}   -> "string coercion — Catala has no string type (§4.8)"
  Inert{}      -> "inert scaffolding used as a value"
  _            -> "expression"

-- ---------------------------------------------------------------------------
-- Module scanning
-- ---------------------------------------------------------------------------

-- | Record declarations, keyed by /both/ the type's unique and its
-- constructor's, so a construction site resolves whichever the parser produced.
collectRecords :: Module Resolved -> Map Unique RecordInfo
collectRecords (MkModule _ _ section) = Map.fromList (goSection section)
 where
  goSection (MkSection _ _ _ decls) = decls >>= goDecl
  goDecl = \case
    Declare _ (MkDeclare _ _ (MkAppForm _ tyRes _ _) (RecordDecl _ mCon fields)) ->
      let nm = resolvedToText tyRes
          ri = RecordInfo
                 { riName   = catUpper nm
                 , riL4     = nm
                 , riFields = [ (catIdent (resolvedToText f), ty)
                              | MkTypedName _ f ty _ _ <- fields ]
                 }
      in (getUnique tyRes, ri) : [ (getUnique c, ri) | c <- maybeToList mCon ]
    Section _ sub -> goSection sub
    _ -> []

-- | Enumeration declarations. A constructor carrying more than one payload has
-- no Catala shape (`content` takes exactly one type), so it is an error.
collectEnums :: Module Resolved -> [Either LowerError CatEnum]
collectEnums (MkModule _ _ section) = goSection section
 where
  goSection (MkSection _ _ _ decls) = decls >>= goDecl
  goDecl = \case
    Declare _ d@(MkDeclare _ _ (MkAppForm _ tyRes _ _) (EnumDecl _ cons)) ->
      let nm = resolvedToText tyRes
      in [ do cases <- traverse (conCase nm) cons
              pure CatEnum
                { enName  = catUpper nm
                , enL4    = nm
                , enDesc  = descOf d
                , enCases = cases
                }
         ]
    Section _ sub -> goSection sub
    _ -> []

  conCase tyNm (MkConDecl _ c payload) =
    let cn = resolvedToText c
    in case payload of
      []                        -> Right (CatCase (catUpper cn) cn Nothing)
      [MkTypedName _ _ ty _ _]  -> (\t -> CatCase (catUpper cn) cn (Just t)) <$> lowerType ty
      _ -> Left (LowerError tyNm
                   ("constructor `" <> cn <> "` carries " <> tshow (length payload)
                    <> " payload fields; Catala's `content` takes exactly one type "
                    <> "(declare a structure and carry that instead)"))

-- | Enum constructors, keyed by unique, mapped to their mangled case names.
enumConstructors :: Module Resolved -> Map Unique Text
enumConstructors (MkModule _ _ section) = Map.fromList (goSection section)
 where
  goSection (MkSection _ _ _ decls) = decls >>= goDecl
  goDecl = \case
    Declare _ (MkDeclare _ _ _ (EnumDecl _ cons)) ->
      [ (getUnique c, catUpper (resolvedToText c)) | MkConDecl _ c _ <- cons ]
    Section _ sub -> goSection sub
    _ -> []

-- | The @\@desc@ text of a declaration, with the leading flag keywords stripped.
descOf :: Declare Resolved -> Maybe Text
descOf d = do
  desc <- getAnno d ^. annDesc
  let ParsedDesc _ t = parseDescText (getDesc desc)
  if Text.null t then Nothing else Just t

-- | A stable provenance string: the source file's basename, so emitted output
-- does not depend on the invocation path.
moduleSource :: Module Resolved -> Text
moduleSource (MkModule _ uri _) =
  let t = getUri (fromNormalizedUri uri)
  in case reverse (Text.splitOn "/" t) of
       (base : _) | not (Text.null base) -> base
       _                                 -> t

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

givenName :: OptionallyTypedName Resolved -> Resolved
givenName (MkOptionallyTypedName _ n _ _) = n

givenType :: OptionallyTypedName Resolved -> Maybe (Type' Resolved)
givenType (MkOptionallyTypedName _ _ t _) = t

givenTypically :: OptionallyTypedName Resolved -> Maybe (Expr Resolved)
givenTypically (MkOptionallyTypedName _ _ _ d) = d

resolvedToText :: Resolved -> Text
resolvedToText = rawNameToText . rawName . getActual

dropExt :: Text -> Text
dropExt t = case Text.breakOnEnd "." t of
  (before, _) | not (Text.null before) -> Text.dropEnd 1 before
  _                                    -> t

eitherToMaybe :: Either e a -> Maybe a
eitherToMaybe = either (const Nothing) Just

mapLeft :: (e -> e') -> Either e a -> Either e' a
mapLeft f = either (Left . f) Right

dedupOn :: Eq k => (a -> k) -> [a] -> [a]
dedupOn key = go mempty
 where
  go _ [] = []
  go seen (x : xs)
    | k `elem` seen = go seen xs
    | otherwise     = x : go (k : seen) xs
    where k = key x

tshow :: Show a => a -> Text
tshow = Text.pack . show
