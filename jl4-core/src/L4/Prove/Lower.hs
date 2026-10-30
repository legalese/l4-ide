-- | Lower one @#ASSERT@ to an SMT-LIB2 proof obligation for @l4 prove@
-- (VERIFICATION-BACKEND-LOWERING-SPEC, Phase 1).
--
-- == The fragment (R-V7)
--
-- @BOOLEAN@ is @Bool@ and @NUMBER@ is @Real@, which is faithful rather than
-- approximate because an L4 number is an exact rational. A @DECLARE@d record or
-- enumeration (not parametric, not opaque) is an SMT datatype. A @DECIDE@ the
-- assertion reaches, in this module or an imported one, is a @define-fun@, so
-- the solver unfolds the call graph (R-V2). @MODULO@ is floor-modulo and
-- @ROUND@ is banker's rounding, both exact through @to_int@, because those are
-- the evaluator's conventions and SMT-LIB's own @mod@ and @to_int@ are neither.
-- Everything else is refused BY NAME ('Refusal'), and the refusal is the
-- @unknown (out of fragment: …)@ verdict R-V8 asks for: strings, dates, lists
-- and other parametric types, transcendental functions, recursion, lambdas,
-- local definitions with parameters, and anything regulative.
--
-- == Definedness
--
-- L4 raises where SMT-LIB is total (@x / 0@ is just some real to a solver), so
-- every lowered term carries a second, Boolean term saying whether evaluation
-- of it would raise. @AND@, @OR@ and @IMPLIES@ short-circuit left to right, and
-- the definedness of each follows that order. A call is call-by-name, which is
-- what L4's laziness amounts to for pure code: every @define-fun@ has a
-- companion over the same parameters plus one @Bool@ per parameter (that
-- argument's definedness), consulted only where the body reads the parameter.
-- The goal sent to the solver is @not (defined and holds)@, so a point at which
-- the assertion RAISES is a counterexample too, and the evaluator's replay of
-- it is expected to raise.
--
-- Constructor arguments are treated as strict: a record built from an argument
-- that raises is undefined here even when nothing reads that field. That can
-- only make the encoding report a counterexample the evaluator rejects, which
-- R-V5's replay reports loudly as an encoding defect; it cannot hide one.
module L4.Prove.Lower
  ( ProveEnv
  , mkProveEnv
  , Sort (..)
  , FreeVar (..)
  , CtorDef (..)
  , Obligation (..)
  , lowerObligation
  , AtomSpace (..)
  , lowerAtoms
  , assumesReadBy
  , liftModelValue
  , exactValue
  , sampleValues
  , goalSymbol
  , definedSymbol
  , sameSymbol
  ) where

import Base
import Control.Applicative ((<|>))
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Ratio (denominator, numerator)
import qualified Data.Text as Text

import L4.Prove.Smt
import L4.Syntax
import L4.TypeCheck.Types (CheckEntity (..), EntityInfo)
import qualified L4.TypeCheck.Environment as TC
import L4.Annotation (emptyAnno)

----------------------------------------------------------------------------
-- What the lowering can see
----------------------------------------------------------------------------

-- | The definitions an obligation may reach: the module's own and every
-- imported module's, keyed by 'Unique'.
data ProveEnv = ProveEnv
  { peDecides  :: !(Map Unique (Decide Resolved))
  , peAssumes  :: !(Map Unique (Assume Resolved))
  , peTypes    :: !(Map Unique (Declare Resolved))
  , peCtors    :: !(Map Unique (Unique, Resolved, [Type' Resolved]))
    -- ^ constructor → its type, itself, and its fields' types
  , peSels     :: !(Map Unique (Unique, Unique, Int))
    -- ^ field selector → its type, its constructor, and its position
  , peEntities :: !EntityInfo
  }

mkProveEnv :: [Module Resolved] -> EntityInfo -> ProveEnv
mkProveEnv mods entities = ProveEnv
  { peDecides = Map.fromList
      [ (getUnique r, d)
      | m <- mods
      , d@(MkDecide _ _ (MkAppForm _ r _ _) _) <- foldTopLevelDecides (: []) m
      ]
  , peAssumes = Map.fromList
      [ (getUnique r, a)
      | m <- mods
      , a@(MkAssume _ _ (MkAppForm _ r _ _) _ _) <- _foldNodeType (: []) m
      ]
  , peTypes = Map.fromList [ (getUnique r, d) | (r, d) <- declares ]
  , peCtors = Map.fromList
      [ (getUnique c, (getUnique t, c, [ ty | MkTypedName _ _ ty _ _ <- fs ]))
      | (t, c, fs) <- ctors
      ]
  , peSels = Map.fromList
      [ (getUnique f, (getUnique t, getUnique c, i))
      | (t, c, fs) <- ctors
      , (i, MkTypedName _ f _ _ Nothing) <- zip [0 ..] fs
      ]
  , peEntities = entities
  }
 where
  declares =
    [ (r, d)
    | m <- mods
    , d@(MkDeclare _ _ (MkAppForm _ r _ _) _) <- _foldNodeType (: []) m
    ]
  ctors =
    [ (t, c, fs)
    | (t, MkDeclare _ _ _ td) <- declares
    , (c, fs) <- case td of
        RecordDecl _ mc fs -> [(fromMaybe t mc, fs)]
        EnumDecl _ cds     -> [ (c, fs) | MkConDecl _ c fs <- cds ]
        _                  -> []
    ]

-- | The module-level @ASSUME@s (section @GIVEN@ binders among them) that an
-- expression reads, through every definition it reaches. This is R-V3's
-- syntactic handle: an @#ASSERT@ is a proof obligation because of what it
-- reads, not because evaluating it happened to get stuck.
assumesReadBy :: ProveEnv -> Expr Resolved -> [Unique]
assumesReadBy env e0 = go Set.empty Set.empty [e0] []
 where
  go _ _ [] acc = reverse acc
  go seenD seenA (e : es) acc =
    let refs = [ getUnique r | r <- toList e ]
        newA = [ u | u <- refs, Map.member u env.peAssumes, not (Set.member u seenA) ]
        newD = nubOrd [ u | u <- refs, Map.member u env.peDecides, not (Set.member u seenD) ]
        bodies = [ b | u <- newD, Just (MkDecide _ _ _ b) <- [Map.lookup u env.peDecides] ]
    in go (seenD <> Set.fromList newD) (seenA <> Set.fromList newA) (es <> bodies) (reverse (nubOrd newA) <> acc)

----------------------------------------------------------------------------
-- What an obligation is
----------------------------------------------------------------------------

data Sort = SBool | SReal | SData !Unique
  deriving stock (Eq, Ord, Show)

-- | A free variable of the obligation: one @ASSUME@ the assertion reads.
data FreeVar = FreeVar
  { fvUnique :: !Unique
  , fvName   :: !Text
  , fvSort   :: !Sort
  , fvSymbol :: !Text
  }
  deriving stock (Eq, Show)

data CtorDef = CtorDef
  { cdResolved  :: !Resolved
  , cdSymbol    :: !Text
  , cdFields    :: ![Sort]
  , cdSelectors :: ![Text]
  }
  deriving stock (Eq, Show)

data Obligation = Obligation
  { obCommands  :: ![SExpr]
    -- ^ the whole script, from @set-option@ to @get-value@
  , obFree      :: ![FreeVar]
  , obDatatypes :: !(Map Unique [CtorDef])
  , obNonLinear :: !(Maybe Text)
    -- ^ the first product of two non-constant terms, if any, so that a
    -- solver's @unknown@ can be reported with its likely reason
  , obLiterals  :: ![Rational]
    -- ^ every numeric literal reached, for R-V5's sample points
  , obReached   :: !(Set Unique)
    -- ^ every DECIDE the obligation unfolds
  }

-- | The symbols the script defines for the goal and its definedness, so the
-- caller can read them back from @get-value@. They start @l4.@, which no
-- user symbol does ('userSymbol' always puts @l4_@ or a longer prefix first).
goalSymbol, definedSymbol :: Text
goalSymbol    = "|l4.goal|"
definedSymbol = "|l4.defined|"

----------------------------------------------------------------------------
-- The lowering monad
----------------------------------------------------------------------------

data Term = Term { val :: !SExpr, def :: !SExpr, srt :: !Sort }

data LState = LState
  { lsSymbols   :: !(Map Unique Text)
  , lsSpellings :: !(Map Text Int)
  , lsTypeOrder :: ![Unique]                 -- registration order, newest first
  , lsTypes     :: !(Map Unique [CtorDef])
  , lsFuns      :: ![SExpr]                  -- define-funs, newest first
  , lsFunsDone  :: !(Map Unique (Text, Text, Int, Sort))  -- symbol, def symbol, arity, result
  , lsActive    :: ![Unique]                 -- the call path being lowered
  , lsFree      :: ![FreeVar]                -- newest first
  , lsNonLinear :: !(Maybe Text)
  , lsLiterals  :: !(Set Rational)
  }

type L = StateT LState (Either Text)

refuse :: Text -> L a
refuse = lift . Left

-- | What a name means inside the term being lowered.
data Local
  = LTerm !Term
  | LPending (Map Unique Local) !(Expr Resolved)   -- a 0-ary WHERE / LET binding
    -- The map is LAZY on purpose: it is the binding group itself, tied in a
    -- knot ('withLocals'), and a strict field forced the knot and looped
    -- (audit of #784, finding 2).

data Ctx = Ctx
  { cxLocals    :: !(Map Unique Local)
  , cxExpanding :: !(Set Unique)
  }

lowerObligation :: ProveEnv -> Expr Resolved -> Either Text Obligation
lowerObligation env goal = do
  (t, st) <- runStateT (lowerExpr env (Ctx Map.empty Set.empty) goal) emptyState
  when (t.srt /= SBool) $ Left "the assertion is not BOOLEAN"
  let free = reverse st.lsFree
      commands =
        preamble st
        <> [ SList [Atom "define-fun", Atom goalSymbol, SList [], Atom "Bool", t.val]
           , SList [Atom "define-fun", Atom definedSymbol, SList [], Atom "Bool", t.def]
           , SList [Atom "assert", SList [Atom "not", SList [Atom "and", Atom definedSymbol, Atom goalSymbol]]]
           , SList [Atom "check-sat"]
           , SList [Atom "get-value", SList (map (Atom . (.fvSymbol)) free <> [Atom definedSymbol, Atom goalSymbol])]
           ]
  pure Obligation
    { obCommands  = commands
    , obFree      = free
    , obDatatypes = st.lsTypes
    , obNonLinear = st.lsNonLinear
    , obLiterals  = Set.toList st.lsLiterals
    , obReached   = Map.keysSet st.lsFunsDone
    }

emptyState :: LState
emptyState = LState Map.empty Map.empty [] Map.empty [] Map.empty [] [] Nothing Set.empty

-- | Everything a script declares before its own assertions: options, logic,
-- datatypes, the free constants, and the unfolded definitions.
preamble :: LState -> [SExpr]
preamble st =
  [ SList [Atom "set-option", Atom ":produce-models", Atom "true"]
  , SList [Atom "set-logic", Atom "ALL"]
  ]
  <> datatypes
  <> [ SList [Atom "declare-const", Atom fv.fvSymbol, sortExpr st fv.fvSort] | fv <- reverse st.lsFree ]
  <> reverse st.lsFuns
 where
  datatypes = case reverse st.lsTypeOrder of
    [] -> []
    us ->
      [ SList
          [ Atom "declare-datatypes"
          , SList [ SList [Atom (st.lsSymbols Map.! u), Atom "0"] | u <- us ]
          , SList [ SList (map ctorDecl (Map.findWithDefault [] u st.lsTypes)) | u <- us ]
          ]
      ]
  ctorDecl cd = case cd.cdFields of
    [] -> SList [Atom cd.cdSymbol]
    _  -> SList (Atom cd.cdSymbol : [ SList [Atom s, sortExpr st srt'] | (s, srt') <- zip cd.cdSelectors cd.cdFields ])

-- | A ladder's atoms over a decision's parameters, for §8.4's witness search
-- (R-V10). The parameters are the free constants; everything else is
-- 'lowerObligation''s lowering.
data AtomSpace = AtomSpace
  { asSpace  :: !Obligation
    -- ^ 'obFree' holds the parameters, in order; the datatypes and literals
    -- are what 'sampleValues' draws candidates from. Its commands are unused.
  , asScript :: [Bool] -> Text
    -- ^ the script whose models realise this combination of the atoms'
    -- truth values, every atom defined: @unsat@ means no input does
  }

-- | Each parameter is given by its binding occurrences (a GIVEN name and an
-- app-form argument can be two 'Unique's for one parameter) and its type.
lowerAtoms :: ProveEnv -> [([Resolved], Type' Resolved)] -> [Expr Resolved] -> Either Text AtomSpace
lowerAtoms env params atoms = do
  (ts, st) <- runStateT go emptyState
  case duplicateDeclarations (preamble st) of
    [] -> pure ()
    ds -> Left ("encoding defect: the script would declare " <> Text.intercalate ", " ds <> " twice")
  let free = reverse st.lsFree
      script bs =
        renderScript $
          preamble st
          <> [ SList [Atom "assert", sAnd (map (.def) ts)] ]
          <> [ SList [Atom "assert", if b then t.val else SList [Atom "not", t.val]] | (t, b) <- zip ts bs ]
          <> [ SList [Atom "check-sat"]
             , SList [Atom "get-value", SList (map (Atom . (.fvSymbol)) free)] ]
  pure AtomSpace
    { asSpace = Obligation [] free st.lsTypes st.lsNonLinear (Set.toList st.lsLiterals) (Map.keysSet st.lsFunsDone)
    , asScript = script
    }
 where
  go = do
    bound <- for params \case
      ([], _) -> refuse "out of fragment: a parameter with no name"
      (rs@(r : _), ty) -> do
        srt' <- sortOf env ty
        sym <- symbolFor "l4_" r
        modify \st -> st { lsFree = FreeVar (getUnique r) (nameOf r) srt' sym : st.lsFree }
        pure [ (getUnique r', LTerm (Term (Atom sym) tru srt')) | r' <- rs ]
    ts <- for atoms (lowerExpr env (Ctx (Map.fromList (concat bound)) Set.empty))
    unless (all ((== SBool) . (.srt)) ts) $ refuse "out of fragment: a ladder condition that is not BOOLEAN"
    pure ts

sortExpr :: LState -> Sort -> SExpr
sortExpr st = \case
  SBool   -> Atom "Bool"
  SReal   -> Atom "Real"
  SData u -> Atom (st.lsSymbols Map.! u)

----------------------------------------------------------------------------
-- Symbols
----------------------------------------------------------------------------

nameOf :: Resolved -> Text
nameOf = nameToText . getOriginal

-- | The one symbol a 'Unique' has in this script. Two different uniques with
-- one spelling (a shadowed name, the same name in two modules) get @#2@, @#3@
-- … after the second, so the script never conflates them.
symbolFor :: Text -> Resolved -> L Text
symbolFor prefix r = do
  st <- get
  let u = getUnique r
  case Map.lookup u st.lsSymbols of
    Just s -> pure s
    Nothing -> do
      let spelling = prefix <> nameOf r
          n = Map.findWithDefault 0 spelling st.lsSpellings + 1
          -- '#' is escaped inside a name, so the suffix cannot collide with one
          s = "|" <> prefix <> escapeName (nameOf r) <> (if n == 1 then "" else "#" <> Text.pack (show n)) <> "|"
      put st { lsSymbols = Map.insert u s st.lsSymbols
             , lsSpellings = Map.insert spelling n st.lsSpellings }
      pure s

----------------------------------------------------------------------------
-- Sorts
----------------------------------------------------------------------------

sortOf :: ProveEnv -> Type' Resolved -> L Sort
sortOf env = \case
  TyApp _ r []
    | u == TC.booleanUnique -> pure SBool
    | u == TC.numberUnique  -> pure SReal
    | u == TC.stringUnique  -> refuse "out of fragment: STRING (ruled an uninterpreted sort by R-V7, not built in this version)"
    | u == TC.dateUnique    -> refuse "out of fragment: DATE"
    | Just d <- Map.lookup u env.peTypes -> datatypeSort env r d
    | otherwise -> refuse ("out of fragment: the type `" <> nameOf r <> "`")
    where u = getUnique r
  TyApp _ r _ -> refuse ("out of fragment: the parametric type `" <> nameOf r <> "`")
  Fun {}      -> refuse "out of fragment: a function-typed value"
  Forall {}   -> refuse "out of fragment: a polymorphic definition"
  InfVar {}   -> refuse "out of fragment: a type the checker left undetermined"
  Type {}     -> refuse "out of fragment: a type used as a value"

datatypeSort :: ProveEnv -> Resolved -> Declare Resolved -> L Sort
datatypeSort env r (MkDeclare _ (MkTypeSig _ (MkGivenSig _ tparams) _) _ td) = do
  let u = getUnique r
  done <- gets (Map.member u . (.lsTypes))
  if done then pure (SData u) else case td of
    _ | not (null tparams) -> refuse ("out of fragment: the parametric type `" <> nameOf r <> "`")
    SynonymDecl _ ty -> sortOf env ty
    OpaqueDecl _ -> refuse ("out of fragment: the opaque type `" <> nameOf r <> "` (no value of it can be replayed)")
    RecordDecl _ mc fs -> register u [(fromMaybe r mc, fs)]
    EnumDecl _ cds -> register u [ (c, fs) | MkConDecl _ c fs <- cds ]
 where
  register u cs = do
    _ <- symbolFor "l4T_" r
    -- registered before the fields are sorted, so a recursive type terminates
    modify \st -> st { lsTypes = Map.insert u [] st.lsTypes, lsTypeOrder = u : st.lsTypeOrder }
    defs <- for cs \(c, fs) -> do
      csym <- symbolFor "l4C_" c
      fsorts <- for fs \(MkTypedName _ f ty _ computed) -> do
        when (isJust computed) $
          refuse ("out of fragment: the computed field `" <> nameOf f <> "` of `" <> nameOf r <> "`")
        s <- sortOf env ty
        pure ("|l4F_" <> escapeName (nameOf r) <> "#" <> escapeName (nameOf f) <> "|", s)
      pure (CtorDef c csym (map snd fsorts) (map fst fsorts))
    modify \st -> st { lsTypes = Map.insert u defs st.lsTypes }
    pure (SData u)

----------------------------------------------------------------------------
-- Terms
----------------------------------------------------------------------------

tru, fls :: SExpr
tru = Atom "true"
fls = Atom "false"

-- | Smart constructors that keep the definedness terms readable: most of them
-- are @true@, and an @and@ of @true@s is noise in a golden.
sAnd :: [SExpr] -> SExpr
sAnd xs = case nubOrd (filter (/= tru) xs) of
  []  -> tru
  [x] -> x
  ys | fls `elem` ys -> fls
     | otherwise -> SList (Atom "and" : ys)

sImplies :: SExpr -> SExpr -> SExpr
sImplies a b
  | b == tru  = tru
  | a == tru  = b
  | otherwise = SList [Atom "=>", a, b]

sOr :: SExpr -> SExpr -> SExpr
sOr a b
  | a == tru || b == tru = tru
  | otherwise = SList [Atom "or", a, b]

sIte :: SExpr -> SExpr -> SExpr -> SExpr
sIte c t e
  | t == e    = t
  | otherwise = SList [Atom "ite", c, t, e]

sApp :: Text -> [SExpr] -> SExpr
sApp f [] = Atom f
sApp f xs = SList (Atom f : xs)

lowerExpr :: ProveEnv -> Ctx -> Expr Resolved -> L Term
lowerExpr env cx = \case
  And _ a b -> do
    ta <- bool a; tb <- bool b
    pure (Term (SList [Atom "and", ta.val, tb.val]) (sAnd [ta.def, sImplies ta.val tb.def]) SBool)
  Or _ a b -> do
    ta <- bool a; tb <- bool b
    pure (Term (SList [Atom "or", ta.val, tb.val]) (sAnd [ta.def, sOr ta.val tb.def]) SBool)
  Implies _ a b -> do
    ta <- bool a; tb <- bool b
    pure (Term (SList [Atom "=>", ta.val, tb.val]) (sAnd [ta.def, sImplies ta.val tb.def]) SBool)
  Not _ a -> do
    ta <- bool a
    pure (Term (SList [Atom "not", ta.val]) ta.def SBool)
  Equals _ a b -> do
    ta <- go a; tb <- go b
    when (ta.srt /= tb.srt) $ refuse "out of fragment: EQUALS between two different types"
    pure (Term (SList [Atom "=", ta.val, tb.val]) (sAnd [ta.def, tb.def]) SBool)
  Leq _ a b -> compareOp "<=" a b
  Geq _ a b -> compareOp ">=" a b
  Lt  _ a b -> compareOp "<" a b
  Gt  _ a b -> compareOp ">" a b
  Plus  _ a b -> arith "+" a b
  Minus _ a b -> arith "-" a b
  Times _ a b -> do
    ta <- real a; tb <- real b
    unless (isConstant ta.val || isConstant tb.val) $
      modify \st -> st { lsNonLinear = st.lsNonLinear <|> Just "a product of two non-constant terms" }
    pure (Term (SList [Atom "*", ta.val, tb.val]) (sAnd [ta.def, tb.def]) SReal)
  DividedBy _ a b -> do
    ta <- real a; tb <- real b
    unless (isConstant tb.val) $
      modify \st -> st { lsNonLinear = st.lsNonLinear <|> nonConstantDivisor ta }
    pure (Term (SList [Atom "/", ta.val, tb.val])
                (sAnd [ta.def, tb.def, nonZero tb.val]) SReal)
  Modulo _ a b -> do
    ta <- real a; tb <- real b
    -- floor-modulo, sign follows the divisor, as Haskell's 'mod' (R-V7)
    let q = SList [Atom "to_real", SList [Atom "to_int", SList [Atom "/", ta.val, tb.val]]]
    pure (Term (SList [Atom "-", ta.val, SList [Atom "*", tb.val, q]])
                (sAnd [ta.def, tb.def, isInt ta.val, isInt tb.val, nonZero tb.val]) SReal)
  Percent _ a -> do
    ta <- real a
    pure (Term (SList [Atom "/", ta.val, realLit 100]) ta.def SReal)
  Lit _ (NumericLit _ r) -> do
    modify \st -> st { lsLiterals = Set.insert r st.lsLiterals }
    pure (Term (realLit r) tru SReal)
  Lit _ (StringLit _ _) -> refuse "out of fragment: a STRING literal"
  -- statute text kept beside the logic: the identity of the connective it sits
  -- in, as the evaluator reads it
  Inert _ _ ctx -> pure (Term (case ctx of InertCtxOr -> fls; _ -> tru) tru SBool)
  IfThenElse _ c t e -> do
    tc <- bool c; tt <- go t; te <- go e
    when (tt.srt /= te.srt) $ refuse "out of fragment: IF arms of different types"
    pure (Term (sIte tc.val tt.val te.val) (sAnd [tc.def, sIte tc.val tt.def te.def]) tt.srt)
  MultiWayIf _ guards dflt -> do
    td <- go dflt
    foldrM (\(MkGuardedExpr _ c e) acc -> do
              tc <- bool c; te <- go e
              when (te.srt /= acc.srt) $ refuse "out of fragment: BRANCH arms of different types"
              pure (Term (sIte tc.val te.val acc.val) (sAnd [tc.def, sIte tc.val te.def acc.def]) te.srt))
           td guards
  Consider _ scrut branches -> lowerConsider env cx scrut branches
  Where _ body locals -> withLocals locals body
  LetIn _ locals body -> withLocals locals body
  Proj _ e f -> do
    te <- go e
    case Map.lookup (getUnique f) env.peSels of
      Just (tyU, ctorU, i) | te.srt == SData tyU -> do
        ctors <- gets (Map.findWithDefault [] tyU . (.lsTypes))
        case [ cd | cd <- ctors, getUnique cd.cdResolved == ctorU ] of
          [cd] | i < length cd.cdFields -> do
            -- a field read on the wrong constructor of a multi-constructor type raises
            let tester = case ctors of
                  [_] -> tru
                  _   -> SList [SList [Atom "_", Atom "is", Atom cd.cdSymbol], te.val]
            pure (Term (SList [Atom (cd.cdSelectors !! i), te.val]) (sAnd [te.def, tester]) (cd.cdFields !! i))
          _ -> refuse ("out of fragment: the field `" <> nameOf f <> "`")
      _ -> refuse ("out of fragment: the field `" <> nameOf f <> "`")
  App _ r args -> lowerApp env cx r args
  AppNamed _ r nargs (Just order)
    | all (>= 0) order, sort order == [0 .. length nargs - 1] ->
        lowerApp env cx r [ e | (_, MkNamedExpr _ _ e) <- sortOn fst (zip order nargs) ]
  AppNamed _ r _ _ -> refuse ("out of fragment: a named application of `" <> nameOf r <> "` that supplies a section GIVEN")
  Lam {}        -> refuse "out of fragment: a lambda (higher-order code)"
  List {}       -> refuse "out of fragment: LIST"
  Cons {}       -> refuse "out of fragment: LIST"
  RAnd {}       -> refuse "out of fragment: a regulative expression"
  ROr {}        -> refuse "out of fragment: a regulative expression"
  Regulative {} -> refuse "out of fragment: a regulative expression"
  Event {}      -> refuse "out of fragment: a regulative expression"
  Fetch {}      -> refuse "out of fragment: FETCH performs I/O"
  Env {}        -> refuse "out of fragment: ENV reads the environment"
  Post {}       -> refuse "out of fragment: POST performs I/O"
  Record {}     -> refuse "out of fragment: a ledger write"
  ReadCell {}   -> refuse "out of fragment: a ledger read"
  _             -> refuse "out of fragment: this kind of expression"
 where
  go = lowerExpr env cx
  bool e = do
    t <- go e
    if t.srt == SBool then pure t else refuse "out of fragment: a non-BOOLEAN condition"
  real e = do
    t <- go e
    if t.srt == SReal then pure t else refuse "out of fragment: arithmetic on a non-NUMBER"
  compareOp op a b = do
    ta <- real a; tb <- real b
    pure (Term (SList [Atom op, ta.val, tb.val]) (sAnd [ta.def, tb.def]) SBool)
  arith op a b = do
    ta <- real a; tb <- real b
    pure (Term (SList [Atom op, ta.val, tb.val]) (sAnd [ta.def, tb.def]) SReal)
  nonZero x = SList [Atom "not", SList [Atom "=", x, realLit 0]]
  isInt x = SList [Atom "is_int", x]
  nonConstantDivisor _ = Just "a division by a non-constant term"

  withLocals locals body = do
    let pending = Map.fromList
          [ (getUnique r, LPending locals' e)
          | LocalDecide _ (MkDecide _ _ (MkAppForm _ r [] _) e) <- locals
          ]
        locals' = pending <> cx.cxLocals
    for_ locals \case
      LocalDecide _ (MkDecide _ _ (MkAppForm _ r (_ : _) _) _) ->
        refuse ("out of fragment: the local definition `" <> nameOf r <> "` takes parameters")
      LocalAssume _ (MkAssume _ _ (MkAppForm _ r _ _) _ _) ->
        refuse ("out of fragment: the local ASSUME `" <> nameOf r <> "`")
      _ -> pure ()
    lowerExpr env cx { cxLocals = locals' } body


isConstant :: SExpr -> Bool
isConstant = isJust . readRational

lowerConsider :: ProveEnv -> Ctx -> Expr Resolved -> [Branch Resolved] -> L Term
lowerConsider env cx scrut branches = do
  ts <- lowerExpr env cx scrut
  arms <- for branches \(MkBranch _ lhs body) -> case lhs of
    Otherwise _ -> do
      tb <- lowerExpr env cx body
      pure (tru, tb)
    When _ pat -> do
      (test, binds) <- lowerPattern env ts.val ts.srt pat
      tb <- lowerExpr env cx { cxLocals = Map.fromList [ (u, LTerm t) | (u, t) <- binds ] <> cx.cxLocals } body
      pure (test, tb)
  case arms of
    [] -> refuse "out of fragment: a CONSIDER with no branches"
    ((_, t0) : _) -> do
      unless (all ((== t0.srt) . (.srt) . snd) arms) $ refuse "out of fragment: CONSIDER branches of different types"
      -- no branch matched: the value is immaterial, and evaluation raises
      let unmatched = Term t0.val fls t0.srt
          step (test, tb) acc = Term (sIte test tb.val acc.val) (sIte test tb.def acc.def) tb.srt
          folded = foldr step unmatched arms
      pure (Term folded.val (sAnd [ts.def, folded.def]) folded.srt)

-- | A pattern's test on the scrutinee, and what it binds.
lowerPattern :: ProveEnv -> SExpr -> Sort -> Pattern Resolved -> L (SExpr, [(Unique, Term)])
lowerPattern env s srt' = \case
  PatVar _ r -> pure (tru, [(getUnique r, Term s tru srt')])
  PatApp _ c []
    | getUnique c == TC.trueUnique, srt' == SBool -> pure (s, [])
    | getUnique c == TC.falseUnique, srt' == SBool -> pure (SList [Atom "not", s], [])
  PatApp _ c subs -> case Map.lookup (getUnique c) env.peCtors of
    Just (tyU, _, _) | srt' == SData tyU -> do
      ctors <- gets (Map.findWithDefault [] tyU . (.lsTypes))
      case [ cd | cd <- ctors, getUnique cd.cdResolved == getUnique c ] of
        [cd] -> do
          when (length subs /= length cd.cdFields) $ refuse "out of fragment: a constructor pattern of the wrong arity"
          let test = case ctors of
                [_] -> tru
                _   -> SList [SList [Atom "_", Atom "is", Atom cd.cdSymbol], s]
          inner <- for (zip3 subs cd.cdSelectors cd.cdFields) \(p, sel, fs) ->
            lowerPattern env (SList [Atom sel, s]) fs p
          pure (sAnd (test : map fst inner), concatMap snd inner)
        _ -> refuse ("out of fragment: the pattern `" <> nameOf c <> "`")
    _ -> refuse ("out of fragment: the pattern `" <> nameOf c <> "`")
  PatCons {} -> refuse "out of fragment: a LIST pattern"
  PatExpr {} -> refuse "out of fragment: an expression pattern"
  PatLit {}  -> refuse "out of fragment: a literal pattern"

lowerApp :: ProveEnv -> Ctx -> Resolved -> [Expr Resolved] -> L Term
lowerApp env cx r args
  | Just bound <- Map.lookup u cx.cxLocals, null args = case bound of
      LTerm t -> pure t
      LPending env' e
        | Set.member u cx.cxExpanding ->
            refuse ("out of fragment: the local definition `" <> nameOf r <> "` refers to itself")
        | otherwise ->
            lowerExpr env Ctx { cxLocals = env', cxExpanding = Set.insert u cx.cxExpanding } e
  | u == TC.trueUnique, null args = pure (Term tru tru SBool)
  | u == TC.falseUnique, null args = pure (Term fls tru SBool)
  | Just a <- Map.lookup u env.peAssumes = freeVar a
  | Just (tyU, c, _) <- Map.lookup u env.peCtors = construct tyU c
  | Just _ <- Map.lookup u env.peSels, [e] <- args = lowerExpr env cx (Proj emptyAnno e r)
  | Just d <- Map.lookup u env.peDecides = callDecide d
  | otherwise = builtin
 where
  u = getUnique r

  freeVar (MkAssume _ _ (MkAppForm _ ar ps _) mty _) = do
    unless (null ps && null args) $
      refuse ("out of fragment: the ASSUME `" <> nameOf ar <> "` takes parameters")
    ty <- maybe (refuse ("out of fragment: the ASSUME `" <> nameOf ar <> "` has no declared type")) pure mty
    s <- sortOf env ty
    sym <- symbolFor "l4_" ar
    known <- gets (any ((== u) . (.fvUnique)) . (.lsFree))
    unless known $
      modify \st -> st { lsFree = FreeVar u (nameOf ar) s sym : st.lsFree }
    pure (Term (Atom sym) tru s)

  construct tyU c = do
    srt' <- case Map.lookup tyU env.peTypes of
      Just d@(MkDeclare _ _ (MkAppForm _ tr _ _) _) -> datatypeSort env tr d
      Nothing -> refuse ("out of fragment: the constructor `" <> nameOf c <> "`")
    ctors <- gets (Map.findWithDefault [] tyU . (.lsTypes))
    case [ cd | cd <- ctors, getUnique cd.cdResolved == u ] of
      [cd] -> do
        when (length args /= length cd.cdFields) $
          refuse ("out of fragment: `" <> nameOf c <> "` applied to the wrong number of fields")
        ts <- traverse (lowerExpr env cx) args
        unless (map (.srt) ts == cd.cdFields) $
          refuse ("out of fragment: `" <> nameOf c <> "` applied to fields of the wrong type")
        pure (Term (sApp cd.cdSymbol (map (.val) ts)) (sAnd (map (.def) ts)) srt')
      _ -> refuse ("out of fragment: the constructor `" <> nameOf c <> "`")

  callDecide d@(MkDecide _ _ (MkAppForm _ dr params _) _) = do
    when (length params /= length args) $
      refuse ("out of fragment: `" <> nameOf dr <> "` applied to " <> Text.pack (show (length args))
              <> " of its " <> Text.pack (show (length params)) <> " parameters")
    (sym, dsym, _, resSort) <- defineDecide env d
    ts <- traverse (lowerExpr env cx) args
    pure (Term (sApp sym (map (.val) ts)) (sApp dsym (map (.val) ts <> map (.def) ts)) resSort)

  -- The checker resolves an infix operator to a call of its built-in; read it
  -- back as the operator, so there is one lowering of each.
  builtin
    | [a, b] <- args, Just op <- lookup u binaryOps = lowerExpr env cx (op emptyAnno a b)
    | [a] <- args, u == TC.notUnique = lowerExpr env cx (Not emptyAnno a)
    | u `elem` [TC.ltStringUnique, TC.leqStringUnique, TC.gtStringUnique, TC.geqStringUnique] =
        refuse "out of fragment: comparison of STRINGs"
    | u `elem` [TC.ltBoolUnique, TC.leqBoolUnique, TC.gtBoolUnique, TC.geqBoolUnique] =
        refuse "out of fragment: an ordering comparison of BOOLEANs"
    | [x] <- args, u == TC.floorUnique = unary x \v -> SList [Atom "to_real", SList [Atom "to_int", v]]
    | [x] <- args, u == TC.ceilingUnique = unary x \v ->
        SList [Atom "-", SList [Atom "to_real", SList [Atom "to_int", SList [Atom "-", v]]]]
    | [x] <- args, u == TC.roundUnique = unary x bankers
    | [x] <- args, u == TC.isIntegerUnique = do
        t <- lowerExpr env cx x
        unless (t.srt == SReal) $ refuse "out of fragment: IS INTEGER of a non-NUMBER"
        pure (Term (SList [Atom "is_int", t.val]) t.def SBool)
    | u `elem` transcendental =
        refuse ("out of fragment: the transcendental function `" <> nameOf r <> "` (R-V7 refuses it by name)")
    | otherwise = refuse ("out of fragment: a call to `" <> nameOf r <> "`")

  unary x f = do
    t <- lowerExpr env cx x
    unless (t.srt == SReal) $ refuse ("out of fragment: `" <> nameOf r <> "` of a non-NUMBER")
    pure (Term (f t.val) t.def SReal)

  -- Haskell 'round': half to even. f = floor (x + 1/2) is right except at an
  -- exact half whose upper neighbour is odd, where the even one is f - 1.
  bankers v =
    let h  = SList [Atom "+", v, realLit (1 / 2)]
        f  = SList [Atom "to_int", h]
        isHalf = SList [Atom "=", SList [Atom "to_real", f], h]
        odd' = SList [Atom "not", SList [Atom "=", SList [Atom "mod", f, Atom "2"], Atom "0"]]
    in SList [Atom "to_real", SList [Atom "ite", SList [Atom "and", isHalf, odd'], SList [Atom "-", f, Atom "1"], f]]

  binaryOps =
    [ (TC.andUnique, And), (TC.orUnique, Or), (TC.impliesUnique, Implies)
    , (TC.equalsUnique, Equals)
    , (TC.plusUnique, Plus), (TC.minusUnique, Minus), (TC.timesUnique, Times)
    , (TC.divideUnique, DividedBy), (TC.moduloUnique, Modulo)
    , (TC.ltNumberUnique, Lt), (TC.leqNumberUnique, Leq)
    , (TC.gtNumberUnique, Gt), (TC.geqNumberUnique, Geq)
    ]

  transcendental =
    [ TC.sqrtUnique, TC.lnUnique, TC.log10Unique, TC.sinUnique, TC.cosUnique, TC.tanUnique
    , TC.asinUnique, TC.acosUnique, TC.atanUnique, TC.exponentUnique ]

-- | Emit a DECIDE as a @define-fun@ and its definedness companion, once.
defineDecide :: ProveEnv -> Decide Resolved -> L (Text, Text, Int, Sort)
defineDecide env (MkDecide _ _ (MkAppForm _ dr params _) body) = do
  let u = getUnique dr
  st0 <- get
  case Map.lookup u st0.lsFunsDone of
    Just done -> pure done
    Nothing -> do
      when (u `elem` st0.lsActive) $
        refuse ("out of fragment: recursion in `" <> nameOf dr <> "` ("
                <> Text.intercalate " → " (map nameAt (reverse (u : takeWhile (/= u) st0.lsActive) <> [u])) <> ")")
      paramTys <- case Map.lookup u env.peEntities of
        Just (_, KnownTerm (Fun _ ps _) _) | length ps == length params ->
          pure [ ty | MkOptionallyNamedType _ _ ty <- ps ]
        Just (_, KnownTerm Forall {} _) -> refuse ("out of fragment: the polymorphic definition `" <> nameOf dr <> "`")
        Just (_, KnownTerm _ _) | null params -> pure []
        _ -> refuse ("out of fragment: the definition `" <> nameOf dr <> "` has no known type")
      sym <- symbolFor "l4_" dr
      -- the companion's name is the definition's own, under its own prefix
      let dsym = "|l4def_" <> fromMaybe sym (Text.stripPrefix "|l4_" sym)
      sorts <- traverse (sortOf env) paramTys
      let psyms = [ userSymbol "l4p_" (nameOf p) | p <- params ]
          pdsyms = [ userSymbol "l4pd_" (nameOf p) | p <- params ]
          locals = Map.fromList
            [ (getUnique p, LTerm (Term (Atom ps) (Atom pd) s))
            | (p, ps, pd, s) <- zip4 params psyms pdsyms sorts ]
      modify \st -> st { lsActive = u : st.lsActive }
      t <- lowerExpr env (Ctx locals Set.empty) body
      st1 <- get
      let decl = [ SList [Atom ps, sortExpr st1 s] | (ps, s) <- zip psyms sorts ]
          ddecl = decl <> [ SList [Atom pd, Atom "Bool"] | pd <- pdsyms ]
          funs = [ SList [Atom "define-fun", Atom dsym, SList ddecl, Atom "Bool", t.def]
                 , SList [Atom "define-fun", Atom sym, SList decl, sortExpr st1 t.srt, t.val] ]
          done = (sym, dsym, length params, t.srt)
      put st1 { lsActive = drop 1 st1.lsActive
              , lsFuns = funs <> st1.lsFuns
              , lsFunsDone = Map.insert u done st1.lsFunsDone }
      pure done
 where
  nameAt v = maybe "?" (\(MkDecide _ _ (MkAppForm _ r _ _) _) -> nameOf r) (Map.lookup v env.peDecides)

----------------------------------------------------------------------------
-- From solver values back to L4, and sample points (R-V5)
----------------------------------------------------------------------------

-- | Turn a @get-value@ value into an L4 expression the evaluator can be given.
liftModelValue :: Obligation -> Sort -> SExpr -> Either Text (Expr Resolved)
liftModelValue ob = goV
 where
  goV srt' v = case (srt', v) of
    (SBool, Atom "true")  -> Right (App emptyAnno TC.trueRef [])
    (SBool, Atom "false") -> Right (App emptyAnno TC.falseRef [])
    (SReal, _) -> case readRational v of
      Just r  -> Right (Lit emptyAnno (NumericLit emptyAnno r))
      Nothing -> Left ("model value not a rational: " <> renderSExpr v)
    (SData tyU, Atom c) -> ctor tyU c []
    (SData tyU, SList (Atom c : xs)) -> ctor tyU c xs
    _ -> Left ("cannot read the model value " <> renderSExpr v)
  -- A solver may print a symbol without the bars it was declared with; in
  -- SMT-LIB @|s|@ and @s@ are one symbol when @s@ needs no quoting.
  ctor tyU c xs = case [ cd | cd <- Map.findWithDefault [] tyU ob.obDatatypes, sameSymbol cd.cdSymbol c ] of
    [cd] | length xs == length cd.cdFields -> do
      args <- zipWithM goV cd.cdFields xs
      Right (App emptyAnno cd.cdResolved args)
    _ -> Left ("cannot read the model value " <> c)

sameSymbol :: Text -> Text -> Bool
sameSymbol a b = Text.dropAround (== '|') a == Text.dropAround (== '|') b

-- | A value with every number that has no short decimal form written as a
-- division, so that printing it with 'L4.Print.prettyLayout' gives L4 source
-- that means exactly this value (@4 DIVIDED BY 3@, not @1.3333333333333333@)
-- and a printed counterexample reproduces under @l4 run@ (audit of #784,
-- finding 4). A number with at most six decimal places prints exactly as it is.
exactValue :: Expr Resolved -> Expr Resolved
exactValue = \case
  Lit a (NumericLit b r)
    | not (shortDecimal r) ->
        DividedBy a (Lit a (NumericLit b (fromInteger (numerator r))))
                    (Lit a (NumericLit b (fromInteger (denominator r))))
  App a c args -> App a c (map exactValue args)
  e -> e
 where
  shortDecimal r = any (\k -> denominator (r * 10 ^ k) == 1) [0 .. 6 :: Int]

-- | A small, deterministic set of values of a sort: both Booleans; for a
-- number, each literal the obligation reaches, one either side of it, and 0;
-- for a datatype, every constructor over its fields' samples (to depth 2,
-- every combination of them while there are at most 256).
sampleValues :: Obligation -> Sort -> [Expr Resolved]
sampleValues ob = goS (2 :: Int)
 where
  goS depth = \case
    SBool -> [App emptyAnno TC.trueRef [], App emptyAnno TC.falseRef []]
    SReal -> [ Lit emptyAnno (NumericLit emptyAnno r) | r <- numbers ]
    SData u
      | depth <= 0 -> [ App emptyAnno cd.cdResolved [] | cd <- ctors u, null cd.cdFields ]
      | otherwise ->
          concat
            [ map (App emptyAnno cd.cdResolved) (diagonal (map (goS (depth - 1)) cd.cdFields))
            | cd <- ctors u ]
  ctors u = Map.findWithDefault [] u ob.obDatatypes
  -- every combination of the fields' samples while there are at most 256;
  -- past that, one per sample of the longest field, each field shifted by its
  -- position, so that every sample of every field still appears
  diagonal [] = [[]]
  diagonal fields
    | any null fields = []
    | product (map (toInteger . length) fields) <= 256 = sequence fields
    | otherwise =
        [ [ xs !! ((k + j) `mod` length xs) | (j, xs) <- zip [0 ..] fields ]
        | k <- [0 .. maximum (map length fields) - 1] ]
  numbers = nubOrd (0 : concat [ [r, r - 1, r + 1] | r <- ob.obLiterals ])
