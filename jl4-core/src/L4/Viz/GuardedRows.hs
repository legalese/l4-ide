{-# LANGUAGE LambdaCase #-}

-- | Guarded chains — @IF-THEN-ELSE@, @BRANCH@, @CONSIDER@ — as ladder structure.
--
-- Both visualisers used to send these three constructs to their @leafFromExpr@
-- fallback, which labels ONE box with 'prettyLayout' of the whole expression. The R1
-- corpus spike measured the cost: 17 of the 22 widest diagrams in the corpus were
-- single leaves, the worst 4372px wide holding 247 characters of raw L4, its newlines
-- collapsed to spaces by SVG @\<text\>@. A whole decision table rendered as an
-- unreadable ribbon.
--
-- Neither of the fixes first proposed for that (wrap the label; draw a structured
-- table-leaf) asked the prior question: /why is a @CONSIDER@ a leaf at all?/ For the
-- boolean-returning case it need not be. A first-match guarded chain over boolean
-- bodies has an exact And\/Or reading, so it can be expanded into ordinary ladder
-- structure and every downstream consumer inherits the result.
--
-- __This module is deliberately a shared front end, not a ladder patch.__ It is
-- consumed twice today (the core and LSP visualisers, which carry near-identical
-- copies of @translateExpr@ over two different @Viz@ monads) and is designed to be
-- consumed a third time by the DMN exporter, which wants 'grRows' as decision-table
-- rules rather than as a boolean tree. That is why 'GuardedRows' carries /rows/.
--
-- Design: @specs\/todo\/lexipedia-superset\/GUARDED-ROWS.md@.
module L4.Viz.GuardedRows
  ( GuardedRows(..)
  , normaliseGuarded
  , guardedToLadder
  , hasEffectfulNode
  , literalBool
  ) where

import Base
import qualified Data.List as List
import Optics

import L4.Annotation (emptyAnno)
import L4.Syntax
import qualified L4.TypeCheck as TC
import L4.Viz.VizExpr (ID (..), IRExpr)
import qualified L4.Viz.VizExpr as V

------------------------------------------------------
-- The normalised form
------------------------------------------------------

-- | A first-match guarded chain, normalised.
data GuardedRows = MkGuardedRows
  { grRows      :: [(Expr Resolved, Expr Resolved)]
    -- ^ @(guard, body)@ in SOURCE order. The order is load-bearing: first match wins.
  , grOtherwise :: Maybe (Expr Resolved)
  , grDisjoint  :: Bool
    -- ^ Are the guards provably pairwise exclusive? When they are, a row need not
    -- restate that no earlier guard fired. Conservative: 'False' is always sound,
    -- merely verbose.
  }

-- | Recognise the three guarded-chain constructs. Pure and total; every 'Nothing'
-- means "leave the caller's existing leaf behaviour alone".
normaliseGuarded :: Expr Resolved -> Maybe GuardedRows
normaliseGuarded = \case
  IfThenElse _ c t e ->
    Just (MkGuardedRows [(c, t)] (Just e) True)   -- one row: vacuously disjoint
  MultiWayIf _ guardeds fallback ->
    let rows = [(g, b) | MkGuardedExpr _ g b <- guardeds]
    in Just (MkGuardedRows rows (Just fallback) (guardsDisjoint (map fst rows)))
  Consider _ scrutinee branches -> considerRows scrutinee branches
  _ -> Nothing

-- | @CONSIDER@ rows. Each @WHEN@ pattern becomes an equality guard against the
-- scrutinee.
--
-- A pattern that BINDS (@PatVar@, @PatApp@ with arguments, @PatCons@) has no such
-- guard: the body may reference the bound name, so the branch is not a closed boolean
-- expression. Such a row is __unexpressible__, and there are two dispositions.
--
-- Normally it forces the whole chain back to a leaf. But an unexpressible row whose
-- body is literally @FALSE@ contributes nothing to the disjunction, and can simply be
-- __dropped__ — provided nothing else needed its guard. Two things could:
--
--   * a LATER row's negated prefix, which is absent exactly when the guards are
--     disjoint; and
--   * the @OTHERWISE@ branch's @⋀ ¬gⱼ@, which is absent exactly when there is no
--     @OTHERWISE@ or its body is itself @FALSE@.
--
-- This is not a corner case. The two widest single-leaf diagrams in the corpus (3494px
-- and 3212px, both @the purpose is charitable@) are enum matches whose only offending
-- row is a @WHEN \`other purpose\` description THEN FALSE@ catch-all. Bailing on them
-- would have left the two biggest ribbons in place for a row that draws nothing.
--
-- Note that a constructor pattern is exclusive by its CONSTRUCTOR, whatever its arity,
-- so an unexpressible row still contributes its disjointness witness.
--
-- Also bails if @OTHERWISE@ is not last.
considerRows :: Expr Resolved -> [Branch Resolved] -> Maybe GuardedRows
considerRows scrutinee branches = do
  (infos, oth) <- walk branches
  let disjoint      = allDistinctJust (map (.biKey) infos)
      unexpressible = [i | i <- infos, isNothing i.biRow]
      -- Could the fallback have needed the dropped guards?
      fallbackHarmless = case oth of
        Nothing -> True
        Just b0 -> literalBool b0 == Just False
  -- Every dropped row must be inert, and nothing may have needed its guard.
  guard (all (\i -> literalBool i.biBody == Just False) unexpressible)
  guard (null unexpressible || (disjoint && fallbackHarmless))
  pure MkGuardedRows
    { grRows      = mapMaybe (.biRow) infos
    , grOtherwise = oth
      -- Distinct constructors / literals against ONE scrutinee cannot both hold.
      -- This is exact and free: the pattern match already says so.
    , grDisjoint  = disjoint
    }
  where
    walk :: [Branch Resolved] -> Maybe ([BranchInfo], Maybe (Expr Resolved))
    walk [] = Just ([], Nothing)
    walk (MkBranch _ (Otherwise _) body : rest)
      | null rest = Just ([], Just body)
      | otherwise = Nothing
    walk (MkBranch _ (When _ pat) body : rest) = do
      let (mguard, mkey) = patternGuard scrutinee pat
      (infos, oth) <- walk rest
      pure (MkBranchInfo mkey ((,body) <$> mguard) body : infos, oth)

-- | One @WHEN@ row, as far as it can be understood.
data BranchInfo = MkBranchInfo
  { biKey  :: Maybe PatKey
    -- ^ its exclusivity witness, if it has one
  , biRow  :: Maybe (Expr Resolved, Expr Resolved)
    -- ^ 'Nothing' when the pattern binds, so no guard can be written
  , biBody :: Expr Resolved
  }

-- | What makes two @CONSIDER@ patterns mutually exclusive: a distinct constructor, or
-- a distinct literal. Anything else contributes no witness.
data PatKey = KeyCtor !Int | KeyNum !Rational | KeyStr !Text
  deriving stock (Eq)

-- | The equality guard a pattern denotes (when it binds nothing), and its exclusivity
-- witness (which survives binding, since exclusivity is a property of the constructor
-- and not of its arguments).
patternGuard :: Expr Resolved -> Pattern Resolved -> (Maybe (Expr Resolved), Maybe PatKey)
patternGuard scrutinee = \case
  PatApp _ ctor []   -> (Just (eqTo (App emptyAnno ctor [])), Just (ctorKey ctor))
  PatApp _ ctor _    -> (Nothing, Just (ctorKey ctor))   -- binds, but still exclusive
  PatLit _ lit       -> (Just (eqTo (Lit emptyAnno lit)), litKey lit)
  PatExpr _ ex       -> (Just (eqTo ex), exprKey ex)
  _                  -> (Nothing, Nothing)               -- PatVar / PatCons
  where
    eqTo = Equals emptyAnno scrutinee

    ctorKey r = KeyCtor (getUnique r).unique

    litKey = \case
      NumericLit _ r -> Just (KeyNum r)
      StringLit _ t  -> Just (KeyStr t)

    -- ONLY literals. It is tempting to add @App _ r [] -> Just (ctorKey r)@ here on
    -- the grounds that a nullary application is a nullary constructor. It is not:
    -- 'L4.Syntax.Var' is a pattern synonym for @App ann n []@, so that case also
    -- matches every reference to a GIVEN parameter, a local binding, and every
    -- zero-argument DECIDE. @WHEN EXACTLY lo@ / @WHEN EXACTLY hi@ over two NUMBER
    -- parameters would then be declared mutually exclusive, the negated prefixes
    -- would be dropped, and the diagram would answer TRUE where the rule answers
    -- FALSE whenever @lo == hi@. Unlike 'PatApp', which the typechecker only produces
    -- once 'resolveConstructor' has succeeded, a 'PatExpr' carries no such guarantee:
    -- @inferPattern@ types it with a plain @inferExpr@.
    exprKey = \case
      Lit _ lit -> litKey lit
      _         -> Nothing

allDistinctJust :: Eq a => [Maybe a] -> Bool
allDistinctJust ms = case sequence ms of
  Nothing -> False
  Just xs -> and [x /= y | (x : rest) <- List.tails xs, y <- rest]

------------------------------------------------------
-- Disjointness
------------------------------------------------------

-- | Tier-2 disjointness for @BRANCH@: pairwise syntactic exclusivity.
guardsDisjoint :: [Expr Resolved] -> Bool
guardsDisjoint gs = and [exclusive a b | (a : rest) <- List.tails gs, b <- rest]

-- | Two guards that cannot both hold, by syntax alone. Conservative by design — a
-- 'False' here costs verbosity, never correctness. Tier 4 (interval\/SMT reasoning,
-- which is what DMN's consistency checkers have done since Montalbano 1962) is
-- deliberately out of scope.
exclusive :: Expr Resolved -> Expr Resolved -> Bool
exclusive a b = case (a, b) of
  (Not _ x,   y)         -> same x y
  (x,         Not _ y)   -> same x y
  (Lt  _ p q, Geq _ r s) -> same p r && same q s
  (Geq _ p q, Lt  _ r s) -> same p r && same q s
  (Gt  _ p q, Leq _ r s) -> same p r && same q s
  (Leq _ p q, Gt  _ r s) -> same p r && same q s
  _                      -> False
  where
    same x y = clearAnno x == clearAnno y

------------------------------------------------------
-- Bail-outs
------------------------------------------------------

-- | @BRANCH@ short-circuits; the And\/Or expansion does not. Expanding a chain whose
-- guards perform I\/O would therefore change how often the effect runs, so bail.
hasEffectfulNode :: Expr Resolved -> Bool
hasEffectfulNode = anyOf (cosmosOf (gplate @(Expr Resolved))) $ \case
  Fetch {} -> True
  Post {}  -> True
  _        -> False

-- | Is this body a literal @TRUE@ \/ @FALSE@? Drives the two collapses that make the
-- common case small: a @TRUE@ body drops out of its conjunction, and a @FALSE@ body
-- deletes its whole disjunct, because that row can never conduct.
literalBool :: Expr Resolved -> Maybe Bool
literalBool = \case
  App _ resolved [] ->
    let u = getUnique resolved
    in if u == TC.trueUnique then Just True
       else if u == TC.falseUnique then Just False
       else Nothing
  _ -> Nothing

------------------------------------------------------
-- The ladder consumer
------------------------------------------------------

-- | The rows, as a ladder.
--
-- Row @i@ fires iff @gᵢ@ holds and no earlier guard did, so the chain is exactly
--
-- > ⋁ᵢ ( ⋀_{j<i} ¬gⱼ ∧ gᵢ ∧ bᵢ )  ⋁  ( ⋀_{j≤n} ¬gⱼ ∧ b₀ )
--
-- Note the asymmetry: 'grDisjoint' removes the negated PREFIX from a row (an
-- exclusive @gᵢ@ already implies that no earlier guard fired) but NEVER the
-- @OTHERWISE@ branch's negations, which must say that /every/ guard failed
-- regardless of whether the guards exclude one another.
--
-- Parameterised over the caller's fresh-id supply and its own translation function,
-- because the two visualisers run in two different @Viz@ monads.
guardedToLadder
  :: forall m. Monad m
  => m ID                             -- ^ fresh id supply
  -> (Expr Resolved -> m IRExpr)      -- ^ the caller's expression translator
  -> GuardedRows
  -> m IRExpr
guardedToLadder fresh go rows = do
  -- Translate each guard EXACTLY ONCE and copy the result at every later occurrence.
  --
  -- This is not an optimisation, it is a correctness requirement. A guard appears once
  -- positively and again under a negation in every later prefix and in the OTHERWISE
  -- branch. Translating it afresh each time routes it through @leafFromExpr@, which
  -- mints a fresh @Unique@ per call (@tempUniqueTODO <- getFresh@) for any COMPOUND
  -- expression -- so @income LESS THAN 107000@ and its negated twin would become two
  -- unrelated atoms. @submitNewBinding@ on the TypeScript side binds exactly one
  -- 'Unique' and does NOT fan out, so a user could set one copy TRUE and the other
  -- FALSE, and the diagram would assert a proposition and its negation at once.
  --
  -- (Bare variables are safe on their own: @varLeaf@ keys off the resolved name's
  -- unique, which is stable across occurrences. It is only compound guards that need
  -- this -- which is exactly the interesting case, e.g. every numeric threshold.)
  --
  -- 'copyOf' gives each occurrence fresh node IDs -- the ladder's ViewSpec is keyed by
  -- node, so those must stay distinct -- while preserving every 'V.Name' (hence every
  -- 'Unique') and every atomId.
  canonical <- traverse go guards
  let guardAt i = copyOf (canonical !! i)

      prefixFor :: Int -> m [IRExpr]
      prefixFor i
        | rows.grDisjoint = pure []
        | otherwise       = traverse negatedAt [0 .. i - 1]

      negatedAt :: Int -> m IRExpr
      negatedAt j = do
        nid <- fresh
        V.Not nid <$> guardAt j

      allNegated :: m [IRExpr]
      allNegated = traverse negatedAt [0 .. length guards - 1]

      mkRow :: Int -> (Expr Resolved, Expr Resolved) -> m (Maybe IRExpr)
      mkRow i (_, b) = case literalBool b of
        Just False -> pure Nothing
        Just True  -> do
          pfx <- prefixFor i
          g'  <- guardAt i
          Just <$> conj (pfx <> [g'])
        Nothing    -> do
          pfx <- prefixFor i
          g'  <- guardAt i
          b'  <- go b
          Just <$> conj (pfx <> [g', b'])

      mkFallback :: m (Maybe IRExpr)
      mkFallback = case rows.grOtherwise of
        Nothing -> pure Nothing
        Just b0 -> case literalBool b0 of
          Just False -> pure Nothing
          Just True  -> do
            pfx <- allNegated
            if null pfx then Just <$> mkLit True else Just <$> conj pfx
          Nothing    -> do
            pfx <- allNegated
            b'  <- go b0
            Just <$> conj (pfx <> [b'])

  disjuncts <- catMaybes <$> sequence (zipWith mkRow [0 ..] rows.grRows <> [mkFallback])
  case disjuncts of
    []  -> mkLit False   -- nothing can conduct
    [d] -> pure d
    ds  -> do
      vid <- fresh
      pure (V.Or vid ds)
  where
    guards = map fst rows.grRows

    -- Fresh node IDs, identical atom identity.
    copyOf :: IRExpr -> m IRExpr
    copyOf = \case
      V.And _ xs                -> V.And <$> fresh <*> traverse copyOf xs
      V.Or _ xs                 -> V.Or <$> fresh <*> traverse copyOf xs
      V.Not _ x                 -> V.Not <$> fresh <*> copyOf x
      V.Implies _ p q seam      -> (\i p' q' -> V.Implies i p' q' seam) <$> fresh <*> copyOf p <*> copyOf q
      V.UBoolVar _ nm v ci a ty -> (\i -> V.UBoolVar i nm v ci a ty) <$> fresh
      V.App _ nm xs a           -> (\i xs' -> V.App i nm xs' a) <$> fresh <*> traverse copyOf xs
      V.TrueE _ nm              -> (`V.TrueE` nm) <$> fresh
      V.FalseE _ nm             -> (`V.FalseE` nm) <$> fresh
      V.InertE _ t c            -> (\i -> V.InertE i t c) <$> fresh

    conj :: [IRExpr] -> m IRExpr
    conj []  = mkLit True
    conj [x] = pure x
    conj xs  = do
      vid <- fresh
      pure (V.And vid xs)

    mkLit :: Bool -> m IRExpr
    mkLit b = do
      vid <- fresh
      nid <- fresh
      let name = V.MkName nid.id (if b then "TRUE" else "FALSE")
      pure (if b then V.TrueE vid name else V.FalseE vid name)
