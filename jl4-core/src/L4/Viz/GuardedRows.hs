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
-- scrutinee. Bails on patterns that BIND (@PatVar@, @PatApp@ with arguments,
-- @PatCons@): the body may reference the bound name, so the branch is not a closed
-- boolean expression and cannot be booleanised. Also bails if @OTHERWISE@ is not last.
considerRows :: Expr Resolved -> [Branch Resolved] -> Maybe GuardedRows
considerRows scrutinee = fmap assemble . walk
  where
    assemble (rows, oth, keys) = MkGuardedRows
      { grRows      = rows
      , grOtherwise = oth
        -- Distinct constructors / literals against ONE scrutinee cannot both hold.
        -- This is exact and free: the pattern match already says so.
      , grDisjoint  = allDistinctJust keys
      }

    walk :: [Branch Resolved]
         -> Maybe ([(Expr Resolved, Expr Resolved)], Maybe (Expr Resolved), [Maybe PatKey])
    walk [] = Just ([], Nothing, [])
    walk (MkBranch _ (Otherwise _) body : rest)
      | null rest = Just ([], Just body, [])
      | otherwise = Nothing
    walk (MkBranch _ (When _ pat) body : rest) = do
      (guard', mkey) <- patternGuard scrutinee pat
      (rows, oth, keys) <- walk rest
      pure ((guard', body) : rows, oth, mkey : keys)

-- | What makes two @CONSIDER@ patterns mutually exclusive: a distinct nullary
-- constructor, or a distinct literal. Anything else contributes no witness.
data PatKey = KeyCtor !Int | KeyNum !Rational | KeyStr !Text
  deriving stock (Eq)

-- | The equality guard a non-binding pattern denotes, plus its exclusivity witness.
patternGuard :: Expr Resolved -> Pattern Resolved -> Maybe (Expr Resolved, Maybe PatKey)
patternGuard scrutinee = \case
  PatApp _ ctor [] -> Just (eqTo (App emptyAnno ctor []), Just (KeyCtor (getUnique ctor).unique))
  PatLit _ lit     -> Just (eqTo (Lit emptyAnno lit), litKey lit)
  PatExpr _ ex     -> Just (eqTo ex, exprKey ex)
  _                -> Nothing   -- PatVar / PatApp with args / PatCons all bind
  where
    eqTo = Equals emptyAnno scrutinee

    litKey = \case
      NumericLit _ r -> Just (KeyNum r)
      StringLit _ t  -> Just (KeyStr t)

    exprKey = \case
      Lit _ lit  -> litKey lit
      App _ r [] -> Just (KeyCtor (getUnique r).unique)
      _          -> Nothing

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
  disjuncts <- catMaybes <$> sequence (zipWith mkRow [0 ..] rows.grRows <> [mkFallback])
  case disjuncts of
    []  -> mkLit False   -- nothing can conduct
    [d] -> pure d
    ds  -> do
      vid <- fresh
      pure (V.Or vid ds)
  where
    guards = map fst rows.grRows

    negated :: [Expr Resolved] -> m [IRExpr]
    negated = traverse $ \g -> do
      nid <- fresh
      V.Not nid <$> go g

    -- The prefix that says "no earlier guard fired".
    prefixFor :: Int -> m [IRExpr]
    prefixFor i
      | rows.grDisjoint = pure []
      | otherwise       = negated (take i guards)

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

    mkRow :: Int -> (Expr Resolved, Expr Resolved) -> m (Maybe IRExpr)
    mkRow i (g, b) = case literalBool b of
      Just False -> pure Nothing
      Just True  -> do
        pfx <- prefixFor i
        g'  <- go g
        Just <$> conj (pfx <> [g'])
      Nothing    -> do
        pfx <- prefixFor i
        g'  <- go g
        b'  <- go b
        Just <$> conj (pfx <> [g', b'])

    mkFallback :: m (Maybe IRExpr)
    mkFallback = case rows.grOtherwise of
      Nothing -> pure Nothing
      Just b0 -> case literalBool b0 of
        Just False -> pure Nothing
        Just True  -> do
          pfx <- negated guards
          if null pfx then Just <$> mkLit True else Just <$> conj pfx
        Nothing    -> do
          pfx <- negated guards
          b'  <- go b0
          Just <$> conj (pfx <> [b'])
