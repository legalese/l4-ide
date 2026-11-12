-- | The check-time half of smucclaw/l4-ide#1069: a WARNING where two
-- operands of a compound can reach a read and a write of one ledger cell.
--
-- The machine runs a @RAND@ or @ROR@ one operand at a time, each over the
-- whole @#TRACE@, against one shared ledger, and an @EVERY@ that is not a
-- barrier (with @UPON EACH@ or none) runs its members as the operands of a
-- @RAND@. So an operand that @RECALL@s a cell
-- its sibling @RECORD@s or @COMMIT@s can see a record from its future, or miss
-- one from its past. The run-time check ('L4.EvaluateLazy.SiblingReads') stops
-- evaluation when that actually happens; this lint says beforehand where it
-- might.
--
-- It is a warning and not an error, as NORM-LOG-SPEC card N10 requires of a
-- static check ("a static check is only a lint"): reachability over-approximates,
-- and a writer-before-reader order is legitimate (one operand records a
-- notice at 10, the other reads it at 400), works, and must keep working.
--
-- What it compares:
--
-- * The operands of every @RAND@ and @ROR@, a chain of one operator taken as
--   one compound (@a RAND b RAND c@ has three operands), and the body of every
--   @EVERY@ against itself, since its members are copies of it, whether it
--   says @UPON EACH@ or nothing. A barrier (@ONCE ALL HAVE@) is skipped: its
--   members cannot write.
-- * What each operand reaches: its own sub-expressions, and the bodies of the
--   definitions it names, top-level and @WHERE@-local, to a fixpoint. Names
--   from other modules, and a @GIVEN … IS A DEONTIC@ parameter's argument, are
--   not followed: the run-time check covers them.
-- * Literal cell names only, matched by ledger kind: a @RECALL OFFICIAL's@
--   against a @COMMIT@ or @ATTEST@, and a @RECALL@ or @RECALL p's@ against a
--   @RECORD@ or @RECORD p's@ (@NOTIFY@), by cell name, since the party is a
--   run-time value. Under @EVERY d@, a read and a write of a party's own ledger
--   that are bare or qualified by @d@ itself are in each member's own ledger,
--   so they are not compared.
module L4.Lint.SiblingReads
  ( SiblingRead (..)
  , SiblingOperand (..)
  , siblingReads
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

-- | The reads and the writes something reaches, in that order.
data Reach = MkReach (Set Access) (Set Access)
  deriving stock Eq

instance Semigroup Reach where
  MkReach a b <> MkReach c d = MkReach (a <> c) (b <> d)

instance Monoid Reach where
  mempty = MkReach Set.empty Set.empty

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
          let known' = Map.map (\ body -> directly body <> foldMap (\ u -> Map.findWithDefault mempty u known) (namesIn body)) bodies
          in if known' == known then known else go known'

    reach :: Expr Resolved -> Reach
    reach e = directly e <> foldMap (\ u -> Map.findWithDefault mempty u reached) (namesIn e)

    -- walk down the module: a compound's operands are compared, then each is
    -- walked in turn; anything else, its children
    compounds :: Expr Resolved -> [SiblingRead]
    compounds e = case e of
      RAnd ann _ _ -> chain "RAND" ann (operandsOf isRAnd e)
      ROr  ann _ _ -> chain "ROR" ann (operandsOf isROr e)
      Regulative ann d | Just v <- forkVariable d ->
        selfPairs ann v (foldMap reach (forkBody d)) <> foldMap compounds (children e)
      _ -> foldMap compounds (children e)
      where
        chain o ann os = pairs o ann os <> foldMap compounds os

    children = Optics.toListOf (Optics.gplate @(Expr Resolved))

    isRAnd = \ case RAnd _ a b -> Just (a, b); _ -> Nothing
    isROr  = \ case ROr _ a b -> Just (a, b); _ -> Nothing
    operandsOf sel e = case sel e of
      Just (a, b) -> operandsOf sel a <> operandsOf sel b
      Nothing     -> [e]

    pairs :: Text -> Anno -> [Expr Resolved] -> [SiblingRead]
    pairs o ann os =
      [ warning o ann (operand ra) (operand wa) r w
      | (i, ra) <- indexed, (j, wa) <- indexed, i /= j
      , let MkReach rs _ = reach ra
            MkReach _ ws = reach wa
      , (r, w) <- firstPerCell [ (r, w) | r <- Set.toList rs, w <- Set.toList ws, matches r w ]
      ]
      where indexed = zip [0 :: Int ..] os

    selfPairs :: Anno -> Unique -> Reach -> [SiblingRead]
    selfPairs ann v (MkReach rs ws) =
      [ warning "EVERY" ann member member r w
      | (r, w) <- firstPerCell
          [ (r, w) | r <- Set.toList rs, w <- Set.toList ws, matches r w
          , not (perMember r && perMember w) ]
      ]
      where
        member = MkSiblingOperand Nothing (rangeOf ann)
        perMember a = not a.official && a.party `elem` [Nothing, Just (Just v)]

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

    warning o ann ro wo r w = MkSiblingRead
      { compound = rangeOf ann, op = o, readerSide = ro, writerSide = wo
      , official = r.official, cell = r.cell
      , readSite = r.site, readVerb = r.verb, writeSite = w.site, writeVerb = w.verb }

-- | The member variable of an @EVERY@ whose members run as the operands of a
-- @RAND@: a fork (@UPON EACH@) or the distributive form (no join line), both
-- folded by the machine's @runQuantifiedFold@, each member with the
-- continuations.
forkVariable :: Deonton Resolved -> Maybe Unique
forkVariable d = case (d.subject, d.join) of
  (Every _ _ v _ _, Just JoinUpon {}) -> Just (getUnique v)
  (Every _ _ v _ _, Nothing)          -> Just (getUnique v)
  _                                   -> Nothing

-- | What each member of a fork runs: the act's @PROVIDED@ and the
-- continuations. The roll and the filter are read once for the whole group.
forkBody :: Deonton Resolved -> [Expr Resolved]
forkBody d = maybeToList d.action.provided <> maybeToList d.hence <> maybeToList d.lest

-- | The literal reads and writes in an expression itself, not through names.
directly :: Expr Resolved -> Reach
directly e = MkReach
  (Set.fromList
    [ MkAccess isOfficial c (qualifier mParty) (rangeOf ann) (if mode == RecallAll then "RECALL ALL" else "RECALL")
    | ReadCell ann mParty isOfficial mode (Lit _ (StringLit _ c)) <- subs ])
  (Set.fromList
    [ MkAccess isOfficial c (qualifier mParty) (rangeOf ann) (writeVerbOf isOfficial mParty)
    | Record ann mParty (Lit _ (StringLit _ c)) _ isOfficial _ <- subs ])
  where
    subs = Optics.toListOf cosmosExpr e
    qualifier = fmap \ case
      App _ r [] -> Just (getUnique r)
      Var _ r    -> Just (getUnique r)
      _          -> Nothing
    writeVerbOf isOfficial mParty
      | isOfficial    = "COMMIT"
      | isJust mParty = "NOTIFY"
      | otherwise     = "RECORD"

-- | The definitions an expression names.
namesIn :: Expr Resolved -> Set Unique
namesIn e = Set.fromList (concatMap heads (Optics.toListOf cosmosExpr e))
  where
    heads = \ case
      Var _ r        -> [getUnique r]
      App _ r _      -> [getUnique r]
      AppNamed _ r _ _ -> [getUnique r]
      _              -> []
