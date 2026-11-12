-- | The check-time half of smucclaw/l4-ide#1069: a WARNING where two
-- operands of an @ROR@ can reach a read and a write of one ledger cell.
--
-- The machine runs an @ROR@ one operand at a time, each over the whole
-- @#TRACE@, against one shared ledger, and it never runs the right operand
-- once the left one is fulfilled. So an operand that @RECALL@s a cell its
-- sibling @RECORD@s or @COMMIT@s can see a record from its future, or miss one
-- from its past, or miss one the unrun alternative would have made. The
-- run-time check ('L4.EvaluateLazy.SiblingReads') stops evaluation when one
-- of the first two actually happens; this lint says beforehand where any of
-- the three might, and is the only notice of the third.
--
-- A @RAND@, and an @EVERY@ whose members are folded into one (@UPON EACH@, or
-- no join line), runs its operands in step, one event at a time (Note
-- [Operands in step] in "L4.EvaluateLazy.Machine"), so a read on one side
-- sees the other side's records from earlier events and none from later
-- ones; they are not compared here. Before 2026-11-13 they were, and so were
-- the members of such an @EVERY@ against each other.
--
-- It is a warning and not an error, as NORM-LOG-SPEC card N10 requires of a
-- static check ("a static check is only a lint"): reachability over-approximates,
-- and a writer-before-reader order is legitimate (one operand records a
-- notice at 10, the other reads it at 400), works, and must keep working.
--
-- What it compares:
--
-- * The operands of every @ROR@, a chain of one operator taken as one
--   compound (@a ROR b ROR c@ has three operands).
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
    --
    -- A @RAND@, and an @EVERY@ whose members are folded into one, runs its
    -- operands in step, one event at a time, so a read on one side sees the
    -- other side's records from earlier events and none from later ones:
    -- those are not compared. The run-time check still stops the few orders
    -- in step cannot settle (two accesses while the sides take the same
    -- event), and needs no warning to do it.
    compounds :: Expr Resolved -> [SiblingRead]
    compounds e = case e of
      ROr  ann _ _ -> chain "ROR" ann (operandsOf isROr e)
      _ -> foldMap compounds (children e)
      where
        chain o ann os = pairs o ann os <> foldMap compounds os

    children = Optics.toListOf (Optics.gplate @(Expr Resolved))

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
