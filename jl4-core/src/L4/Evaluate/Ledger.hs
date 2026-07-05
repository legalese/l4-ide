-- | Event-sourced ledger substrate (MILESTONE 0 of STATE-AS-LEDGER-SPEC).
--
-- This is the /substrate only/: a pure data model plus the helpers needed
-- to fold it. There is no surface syntax, no new builtins, and no parser or
-- typechecker involvement at this stage — those arrive in later milestones.
--
-- The load-bearing decision (D2 / Rung-3): a ledger write APPENDS an event;
-- it is not a mutable store. The current projection of a cell is recovered by
-- folding the event log ('snapshot' / 'readCell'), exactly as a System of
-- Record reconstructs state from its journal.
--
-- We deliberately reuse the evaluator's own 'WHNF' value type (from
-- "L4.Evaluate.ValueLazy") so that later milestones — where
-- @RECORD \<cell\> IS \<expr\>@ compiles to @tellEvent (Assign …)@ — can store
-- the value the evaluator actually produces, with no lossy wrapper. This does
-- not create an import cycle: 'L4.Evaluate.ValueLazy' depends only on 'Base',
-- 'L4.Syntax', and 'L4.Evaluate.Operators', none of which depend on this
-- module.
module L4.Evaluate.Ledger
  ( Path
  , Provenance (..)
  , LedgerEvent (..)
  , Ledger
  , emptyLedger
  , snapshot
  , readCell
    -- * Per-party store (M4)
  , LedgerStore (..)
  , emptyStore
  , anonymousParty
  , EventRoute (..)
  , storeAppendOwn
  , storeAppendOfficial
  , storeOwnLedger
  ) where

import Base
import qualified Base.DList as DList
import qualified Base.Map as Map

import L4.Evaluate.ValueLazy (WHNF)

-- | The address of a cell in the ledger. A list of path segments, e.g.
-- @["account", "balance"]@. Kept structural (rather than a single 'Text')
-- so that later milestones can address nested cells.
type Path = [Text]

-- | Where an event came from. This is a substrate, so the fields are simple
-- 'Text'/'Maybe Text' — richer provenance (resolved parties, source ranges,
-- real timestamps) is a later-milestone concern.
data Provenance =
  MkProvenance
    { party    :: !Text         -- ^ the acting party that caused the write
    , source   :: !Text         -- ^ where the write originated (e.g. a rule name)
    , position :: !(Maybe Text) -- ^ a position/timestamp, free-form for now
    }
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | A single entry in the event log.
--
-- Only 'Assign' exists at M0. The type is intentionally a sum so that later
-- milestones can add @Obliged@, @Breach@, etc. without disturbing callers.
data LedgerEvent =
    Assign !Path !WHNF !Provenance
  deriving stock (Show, Generic)
  deriving anyclass NFData

-- | The event log itself.
--
-- We mirror the representation used by 'L4.EvaluateLazy.evalTrace', namely a
-- 'DList' appended to with 'snoc' so that the log is /newest-last/. 'DList'
-- gives O(1) append, which matters because every ledger write happens on the
-- hot evaluation path; reconstructing a snapshot is comparatively rare.
type Ledger = DList LedgerEvent

-- | The empty ledger.
emptyLedger :: Ledger
emptyLedger = mempty

-- | Project the event log to the current value of every cell.
--
-- LAST write wins. Because the log is newest-last, we fold from oldest to
-- newest ('toList' on a 'DList' yields oldest-first) and 'Map.insert' each
-- 'Assign'; later inserts overwrite earlier ones, so the newest 'Assign' for
-- a 'Path' is what remains. Getting this fold order right is the whole point:
-- folding the other way would give first-write-wins.
snapshot :: Ledger -> Map Path WHNF
snapshot =
  foldl' (\acc ev -> case ev of Assign p v _ -> Map.insert p v acc) Map.empty . toList

-- | Read the current (latest) value of a single cell, or 'Nothing' if the
-- cell has never been assigned.
readCell :: Path -> Ledger -> Maybe WHNF
readCell p = Map.lookup p . snapshot

-----------------------------------------------------------------------------
-- M4: per-party store + a shared official record (R1)
-----------------------------------------------------------------------------

-- | The whole event-sourced state for one directive (STATE-AS-LEDGER M4, R1).
--
-- R1 ratified the per-party model: each acting party accumulates its /own/
-- private append-only ledger (keyed by the party's rendered text), and a single
-- distinguished /official/ ledger holds the shared record that @COMMIT@/@ATTEST@
-- promote values into. This is what keeps the deontic-race-becomes-data-race
-- surface small and named: two parties' @RECORD@s touch different own ledgers
-- and cannot race; the only shared write is the official @COMMIT@.
--
-- A @RECORD@ fired with no enclosing party (a top-level @#EVAL RECORD@) routes
-- to the own ledger keyed by 'anonymousParty' (the empty string).
data LedgerStore =
  MkLedgerStore
    { ownLedgers     :: !(Map Text Ledger)
      -- ^ per-party private ledgers, keyed by the rendered acting party
    , officialLedger :: !Ledger
      -- ^ the single shared record (COMMIT/ATTEST target)
    }
  deriving stock (Show, Generic)
  deriving anyclass NFData

-- | The empty store: no party has recorded anything, and the official record
-- is empty.
emptyStore :: LedgerStore
emptyStore = MkLedgerStore Map.empty emptyLedger

-- | The key used for an own write that has no enclosing acting party (a
-- top-level @#EVAL RECORD@). Kept as the empty string so it is visually
-- distinct from any real party name and renders as the anonymous block.
anonymousParty :: Text
anonymousParty = ""

-- | M4: how a ledger write is routed. 'RouteOwn' appends to the acting party's
-- own ledger (a @RECORD@); 'RouteOfficial' appends to the shared official
-- record (a @COMMIT@/@ATTEST@).
data EventRoute = RouteOwn | RouteOfficial
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | Append an 'Assign' (or any 'LedgerEvent') to a party's own ledger, keyed by
-- the (already rendered) acting party. Creates the party's ledger on first use.
storeAppendOwn :: Text -> LedgerEvent -> LedgerStore -> LedgerStore
storeAppendOwn party ev store =
  store { ownLedgers = Map.insertWith (\new old -> old <> new) party (DList.singleton ev) store.ownLedgers }

-- | Append an event to the shared official ledger.
storeAppendOfficial :: LedgerEvent -> LedgerStore -> LedgerStore
storeAppendOfficial ev store =
  store { officialLedger = store.officialLedger `DList.snoc` ev }

-- | Read one party's own ledger (empty if that party has recorded nothing).
storeOwnLedger :: Text -> LedgerStore -> Ledger
storeOwnLedger party store = Map.findWithDefault emptyLedger party store.ownLedgers
