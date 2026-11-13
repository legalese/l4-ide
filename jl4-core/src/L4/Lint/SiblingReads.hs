-- | The check-time half of smucclaw/l4-ide#1069: a WARNING where two
-- operands of a compound can reach a read and a write of one ledger cell in
-- a way the machine cannot put in the order of the trace.
--
-- The machine runs an @ROR@ one operand at a time, each over the whole
-- @#TRACE@, against one shared ledger, and it never runs the right operand
-- once the left one is fulfilled. So an operand that @RECALL@s a cell its
-- sibling @RECORD@s or @COMMIT@s can see a record from its future, or miss one
-- from its past, or miss one the unrun alternative would have made. The
-- run-time check ('L4.EvaluateLazy.SiblingReads') stops evaluation when one
-- of these actually happens; this lint says beforehand where one might.
--
-- A @RAND@, and an @EVERY@ whose members are folded into one (@UPON EACH@, or
-- no join line), runs its operands in step, one event at a time (Note
-- [Operands in step] in "L4.EvaluateLazy.Machine"), so a read on one side
-- sees the other side's records from earlier events and none from later
-- ones, and a plain read and write on two sides are not compared here. What
-- is compared is a read on one side against a record the other side makes
-- in an alternative of an @ROR@ that comes after another, which is never run
-- once the earlier one is fulfilled, however the sides are scheduled.
--
-- It is a warning and not an error, as NORM-LOG-SPEC card N10 requires of a
-- static check ("a static check is only a lint"): reachability over-approximates,
-- and a writer-before-reader order is legitimate (one operand records a
-- notice at 10, the other reads it at 400), works, and must keep working.
--
-- What it compares:
--
-- * The operands of every @ROR@, a chain of one operator taken as one
--   compound (@a ROR b ROR c@ has three operands): every read against every
--   write.
-- * The operands of every @RAND@ chain, and the members of an @EVERY@ folded
--   into one: every read against the writes made in an @ROR@'s later
--   alternative.
-- * What each operand reaches: its own sub-expressions, and the bodies of the
--   definitions it names, top-level and @WHERE@-local, to a fixpoint. Names
--   from other modules, and a @GIVEN … IS A DEONTIC@ parameter's argument, are
--   not followed: the run-time check covers them.
-- * Literal cell names only, matched by ledger kind: a @RECALL OFFICIAL's@
--   against a @COMMIT@ or @ATTEST@, and a @RECALL@ or @RECALL p's@ against a
--   @RECORD@ or @RECORD p's@ (@NOTIFY@), by cell name, since the party is a
--   run-time value.
module L4.Lint.SiblingReads
  ( SiblingRead (..)
  , SiblingOperand (..)
  , siblingReads
    -- * For the run-time check's walk over an unrun @ROR@ alternative
  , writeSitesIn
  , namesIn
  , actionExprs
  , deontonExprs
  ) where

import Base
import qualified Base.Map as Map
import qualified Base.Set as Set
import qualified Optics

import L4.Annotation (HasSrcRange (..))
import L4.Parser.SrcSpan (SrcRange)
import L4.Syntax

-- | One operand of a compound, as a warning names it.
data SiblingOperand = MkSiblingOperand
  { rule  :: Maybe Resolved
    -- ^ the rule the operand names, when it is one (@`Alice's evening`@)
  , range :: Maybe SrcRange
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass NFData

-- | One pair of operands of one compound that can reach a read and a write of
-- one cell.
data SiblingRead = MkSiblingRead
  { compound   :: Maybe SrcRange
  , op         :: Text
    -- ^ @RAND@, @ROR@, or @EVERY@ for the members of an @EVERY@
  , readerSide :: SiblingOperand
  , writerSide :: SiblingOperand
  , official   :: Bool
  , cell       :: Text
  , readSite   :: Maybe SrcRange
  , readVerb   :: Text
  , writeSite  :: Maybe SrcRange
  , writeVerb  :: Text
  , unrunRor   :: Maybe (Maybe SrcRange)
    -- ^ @Just@ the @ROR@'s range when the write is made in an alternative of
    -- an @ROR@ that comes after another, which L4 does not run once the
    -- earlier one is fulfilled; 'Nothing' for a plain pair of an @ROR@'s
    -- operands
  }
  deriving stock (Eq, Generic, Show)
  deriving anyclass NFData

-- | A literal read or write of a cell.
data Access = MkAccess
  { official :: Bool
  , cell     :: Text
  , party    :: Maybe (Maybe Unique)
    -- ^ 'Nothing' for a bare @RECORD@\/@RECALL@ (the acting party's own
    -- ledger); @Just (Just u)@ for one qualified by the name @u@; @Just
    -- Nothing@ for one qualified by any other expression
  , site     :: Maybe SrcRange
  , verb     :: Text
  }
  deriving stock (Eq, Ord, Show)

-- | The reads and the writes something reaches, in that order, and the
-- writes it reaches in an @ROR@'s later alternative, each with that @ROR@'s
-- range.
data Reach = MkReach (Set Access) (Set Access) (Set (Access, Maybe SrcRange))
  deriving stock Eq

instance Semigroup Reach where
  MkReach a b c <> MkReach d e f = MkReach (a <> d) (b <> e) (c <> f)

instance Monoid Reach where
  mempty = MkReach Set.empty Set.empty Set.empty

-- | Every pair of sibling operands of the module's compounds that can reach a
-- read and a write of one cell, one warning per compound, pair of operands
-- and cell.
siblingReads :: Module Resolved -> [SiblingRead]
siblingReads m
  | null [ () | ReadCell {} <- everyExpr ] || null [ () | Record {} <- everyExpr ] = []
  | otherwise = nub (concatMap compounds everyTop)
  where
    everyExpr = Optics.toListOf (Optics.gplate @(Expr Resolved) Optics.% cosmosExpr) m
    -- the outermost expressions of the module, which 'compounds' walks down from
    everyTop = Optics.toListOf (Optics.gplate @(Expr Resolved)) m

    bodies :: Map Unique (Expr Resolved)
    bodies =
      Map.fromList
        [ (getUnique n, body)
        | MkDecide _ _ (MkAppForm _ n _ _) body <- foldTopLevelDecides (foldDecides pure) m
        ]

    -- what each definition reaches, to a fixpoint over the names it uses
    reached :: Map Unique Reach
    reached = go (Map.map (const mempty) bodies)
      where
        go known =
          let known' = Map.map (reachWith known) bodies
          in if known' == known then known else go known'

    -- what an expression reaches, given what each definition is known to
    -- reach: a name used in an ROR's later alternative contributes all its
    -- writes as writes made there
    reachWith :: Map Unique Reach -> Expr Resolved -> Reach
    reachWith known e =
      directly e
        <> foldMap look (namesIn e)
        <> MkReach Set.empty Set.empty
             (Set.fromList [ (w, rng) | (rng, alt) <- laterAlternatives e, u <- Set.toList (namesIn alt), let MkReach _ ws _ = look u, w <- Set.toList ws ])
      where look u = Map.findWithDefault mempty u known

    reach :: Expr Resolved -> Reach
    reach = reachWith reached

    -- walk down the module: a compound's operands are compared, then each is
    -- walked in turn; anything else, its children
    --
    -- A @RAND@, and an @EVERY@ whose members are folded into one, runs its
    -- operands in step, one event at a time, so a read on one side sees the
    -- other side's records from earlier events and none from later ones:
    -- those are not compared. The run-time check still stops the few orders
    -- in step cannot settle (two accesses while the sides take the same
    -- event), and needs no warning to do it.
    compounds :: Expr Resolved -> [SiblingRead]
    compounds e = case e of
      ROr  ann _ _ -> pairs "ROR" ann os <> foldMap compounds os
        where os = operandsOf isROr e
      RAnd ann _ _ -> unrunPairs ann os <> foldMap compounds os
        where os = operandsOf isRAnd e
      Regulative ann d | Just v <- forkVariable d ->
        unrunSelfPairs ann v (foldMap reach (forkBody d)) <> foldMap compounds (children e)
      _ -> foldMap compounds (children e)

    children = Optics.toListOf (Optics.gplate @(Expr Resolved))

    isROr  = \ case ROr _ a b -> Just (a, b); _ -> Nothing
    isRAnd = \ case RAnd _ a b -> Just (a, b); _ -> Nothing
    operandsOf sel e = case sel e of
      Just (a, b) -> operandsOf sel a <> operandsOf sel b
      Nothing     -> [e]

    pairs :: Text -> Anno -> [Expr Resolved] -> [SiblingRead]
    pairs o ann os =
      [ warning o ann (operand ra) (operand wa) r w Nothing
      | (i, ra) <- indexed, (j, wa) <- indexed, i /= j
      , let MkReach rs _ _ = reach ra
            MkReach _ ws _ = reach wa
      , (r, w) <- firstPerCell [ (r, w) | r <- Set.toList rs, w <- Set.toList ws, matches r w ]
      ]
      where indexed = zip [0 :: Int ..] os

    -- the sides of a RAND chain: a read on one against a record the other
    -- makes in an ROR's later alternative
    unrunPairs :: Anno -> [Expr Resolved] -> [SiblingRead]
    unrunPairs ann os =
      [ warning "RAND" ann (operand ra) (operand wa) r w (Just rng)
      | (i, ra) <- indexed, (j, wa) <- indexed, i /= j
      , let MkReach rs _ _ = reach ra
            MkReach _ _ us = reach wa
      , ((r, w), rng) <- firstPerCellU [ ((r, w), rng) | r <- Set.toList rs, (w, rng) <- Set.toList us, matches r w ]
      ]
      where indexed = zip [0 :: Int ..] os

    -- the members of a folded EVERY, each against the others; a read and a
    -- record both in the member's own ledger are not shared
    unrunSelfPairs :: Anno -> Unique -> Reach -> [SiblingRead]
    unrunSelfPairs ann v (MkReach rs _ us) =
      [ warning "EVERY" ann member member r w (Just rng)
      | ((r, w), rng) <- firstPerCellU
          [ ((r, w), rng) | r <- Set.toList rs, (w, rng) <- Set.toList us, matches r w
          , not (perMember r && perMember w) ]
      ]
      where
        member = MkSiblingOperand Nothing (rangeOf ann)
        perMember a = not a.official && a.party `elem` [Nothing, Just (Just v)]

    firstPerCellU ps = Map.elems (Map.fromListWith (\ _ old -> old) [ ((r.official, r.cell), p) | p@((r, _), _) <- sortOn (\ ((r, w), _) -> (r.site, w.site)) ps ])

    matches r w = r.official == w.official && r.cell == w.cell

    -- one pair of sites per cell, the first in source order
    firstPerCell ps = Map.elems (Map.fromListWith (\ _ old -> old) [ ((r.official, r.cell), p) | p@(r, _) <- sortOn (\ (r, w) -> (r.site, w.site)) ps ])

    operand e = MkSiblingOperand
      { rule = case e of
          App _ r [] -> Just r
          Var _ r    -> Just r
          _          -> Nothing
      , range = rangeOf e
      }

    warning o ann ro wo r w u = MkSiblingRead
      { compound = rangeOf ann, op = o, readerSide = ro, writerSide = wo
      , official = r.official, cell = r.cell
      , readSite = r.site, readVerb = r.verb, writeSite = w.site, writeVerb = w.verb
      , unrunRor = u }

-- | The member variable of an @EVERY@ whose members run as the operands of a
-- @RAND@: a fork (@UPON EACH@) or the distributive form (no join line), both
-- folded by the machine's @runQuantifiedFold@.
forkVariable :: Deonton Resolved -> Maybe Unique
forkVariable d = case (d.subject, d.join) of
  (Every _ _ v _ _, Just JoinUpon {}) -> Just (getUnique v)
  (Every _ _ v _ _, Nothing)          -> Just (getUnique v)
  _                                   -> Nothing

-- | What each member of a fork runs: the act's @PROVIDED@ and the
-- continuations. The roll and the filter are read once for the whole group.
forkBody :: Deonton Resolved -> [Expr Resolved]
forkBody d = maybeToList d.action.provided <> maybeToList d.hence <> maybeToList d.lest

-- | The later alternatives of every @ROR@ in an expression, each with the
-- @ROR@'s range: the right operand of each @ROR@ node, which the machine does
-- not run once the left one is fulfilled.
laterAlternatives :: Expr Resolved -> [(Maybe SrcRange, Expr Resolved)]
laterAlternatives e = [ (rangeOf ann, r) | ROr ann _ r <- Optics.toListOf cosmosExpr e ]

-- | The literal reads and writes in an expression itself, not through names,
-- and the writes made in an @ROR@'s later alternative inside it.
directly :: Expr Resolved -> Reach
directly e = MkReach (readsOf subs) (literalWrites subs) unrun
  where
    subs = Optics.toListOf cosmosExpr e
    unrun = Set.fromList
      [ (w, rng) | (rng, alt) <- laterAlternatives e, w <- Set.toList (literalWrites (Optics.toListOf cosmosExpr alt)) ]

readsOf :: [Expr Resolved] -> Set Access
readsOf subs = Set.fromList
  [ MkAccess isOfficial c (qualifierOf mParty) (rangeOf ann) (if mode == RecallAll then "RECALL ALL" else "RECALL")
  | ReadCell ann mParty isOfficial mode (Lit _ (StringLit _ c)) <- subs ]

literalWrites :: [Expr Resolved] -> Set Access
literalWrites subs = Set.fromList
  [ MkAccess isOfficial c (qualifierOf mParty) (rangeOf ann) (writeVerbOf isOfficial mParty)
  | Record ann mParty (Lit _ (StringLit _ c)) _ isOfficial _ <- subs ]

qualifierOf :: Maybe (Expr Resolved) -> Maybe (Maybe Unique)
qualifierOf = fmap \ case
  App _ r [] -> Just (getUnique r)
  Var _ r    -> Just (getUnique r)
  _          -> Nothing

writeVerbOf :: Bool -> Maybe (Expr Resolved) -> Text
writeVerbOf isOfficial mParty
  | isOfficial    = "COMMIT"
  | isJust mParty = "NOTIFY"
  | otherwise     = "RECORD"

-- | Every write an expression makes itself, literal cell or not, for the
-- run-time check's walk over an @ROR@ alternative the machine did not run
-- ("L4.EvaluateLazy.Machine"): whether it is official, the cell when it is a
-- literal ('Nothing' when it is computed), its site and its verb.
writeSitesIn :: Expr Resolved -> [(Bool, Maybe Text, Maybe SrcRange, Text)]
writeSitesIn e =
  [ (isOfficial, cellName, rangeOf ann, writeVerbOf isOfficial mParty)
  | Record ann mParty cellE _ isOfficial _ <- Optics.toListOf cosmosExpr e
  , let cellName = case cellE of
          Lit _ (StringLit _ c) -> Just c
          _                     -> Nothing ]

-- | The expressions an act holds (its @PROVIDED@, its arguments), for the
-- same walk.
actionExprs :: RAction Resolved -> [Expr Resolved]
actionExprs = Optics.toListOf (Optics.gplate @(Expr Resolved))

-- | The expressions a deonton holds, for the same walk.
deontonExprs :: Deonton Resolved -> [Expr Resolved]
deontonExprs = Optics.toListOf (Optics.gplate @(Expr Resolved))

-- | The definitions an expression names.
namesIn :: Expr Resolved -> Set Unique
namesIn e = Set.fromList (concatMap heads (Optics.toListOf cosmosExpr e))
  where
    heads = \ case
      Var _ r        -> [getUnique r]
      App _ r _      -> [getUnique r]
      AppNamed _ r _ _ -> [getUnique r]
      _              -> []
