-- | Event-sourced ledger substrate (MILESTONE 0 of STATE-AS-LEDGER-SPEC,
-- bitemporally stamped per smucclaw/l4-ide#914 Phase 1).
--
-- This is the /substrate only/: a pure data model plus the helpers needed
-- to fold it. The surface syntax (@RECORD@/@COMMIT@/@RECALL@) lives in the
-- parser and the machine; this module stays pure.
--
-- The load-bearing decision (D2 / Rung-3): a ledger write APPENDS an event;
-- it is not a mutable store. The current projection of a cell is recovered by
-- folding the event log ('snapshot' / 'readCell'), exactly as a System of
-- Record reconstructs state from its journal.
--
-- Every entry carries a bitemporal stamp ('Provenance'): a /transaction/
-- time ('txTime', when the entry was appended — the root eval clock, immune
-- to @EVAL AS OF SYSTEM TIME@) and a /valid-from/ time ('vtFrom', when the
-- recorded fact is asserted to hold — the ambient fact-time axis, or the
-- transaction day by default). 'readCellBitemporal' reads the log through
-- both lenses; 'readCell' is its unbounded instantiation.
--
-- We deliberately reuse the evaluator's own 'WHNF' value type (from
-- "L4.Evaluate.ValueLazy") so that @RECORD \<cell\> IS \<expr\>@ can store
-- the value the evaluator actually produces, with no lossy wrapper. This
-- does not create an import cycle: 'L4.Evaluate.ValueLazy' does not depend
-- on this module (and 'Data.Time' is an external package).
module L4.Evaluate.Ledger
  ( Path
  , Provenance (..)
  , effectiveVt
  , LedgerEvent (..)
  , Ledger
  , emptyLedger
  , snapshot
  , readCell
  , readCellAll
    -- * Bitemporal projections (#914 §2B)
  , readCellBitemporal
  , readCellAllBitemporal
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

import Data.Time (Day, UTCTime, utctDay)

import L4.Evaluate.ValueLazy (WHNF)

-- | The address of a cell in the ledger. A list of path segments, e.g.
-- @["account", "balance"]@. Kept structural (rather than a single 'Text')
-- so that later milestones can address nested cells.
type Path = [Text]

-- | Where an event came from, and when. The party\/source fields are simple
-- 'Text' — richer provenance (resolved parties, source ranges) remains a
-- later-milestone concern — but the timestamps are now real: every append is
-- bitemporally stamped (smucclaw/l4-ide#914 §2A).
data Provenance =
  MkProvenance
    { party  :: !Text  -- ^ the acting party that caused the write
    , source :: !Text  -- ^ where the write originated (e.g. RECORD\/COMMIT\/NOTIFY)
    , txTime :: !UTCTime
      -- ^ /transaction time/: when this entry was appended. Stamped from the
      -- ROOT eval clock ('getEvalTime'), which @EVAL AS OF SYSTEM TIME@
      -- never touches — that clause scopes reads, never writes (the audit
      -- invariant). NOTE the root clock is resolved once per run, so all
      -- entries within one run share one 'txTime'; transaction ORDER within
      -- a run is the log position (the 'Ledger' is append-only, newest-last).
    , vtFrom :: !(Maybe Day)
      -- ^ /valid-from/: when the recorded fact is asserted to hold. @Just d@
      -- when a fact time was explicitly in scope at the write (an enclosing
      -- @EVAL UNDER VALID TIME@) — a backdated\/dated assertion; 'Nothing'
      -- for a contemporaneous write, whose effective valid-from defaults to
      -- the 'txTime' day (see 'effectiveVt').
    }
  deriving stock (Eq, Show, Generic)
  deriving anyclass NFData

-- | The effective valid-from day of an entry: the explicitly asserted fact
-- time when present, otherwise the (UTC) day of the transaction stamp — a
-- contemporaneous write is valid from when it was written.
effectiveVt :: Provenance -> Day
effectiveVt prov = fromMaybe (utctDay prov.txTime) prov.vtFrom

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
--
-- Defined as the unbounded instantiation of 'readCellBitemporal' — no
-- system-time cutoff, no valid-time point — so the bare-@RECALL@
-- last-write-wins semantics and the bitemporal fold can never drift apart.
readCell :: Path -> Ledger -> Maybe WHNF
readCell = readCellBitemporal Nothing Nothing

-- | STATE-AS-LEDGER approach B: read /every/ value ever assigned to a single
-- cell, oldest-first, as a list (empty if the cell has never been assigned).
--
-- This is the collect-all dual of 'readCell'. Where 'readCell' collapses the
-- append log to last-write-wins (the latest 'Assign' for the 'Path'),
-- 'readCellAll' exposes the full accumulation the append-only log already
-- retains: it filters every 'Assign' to this 'Path' and keeps them ALL. No
-- write-side change is needed — each write is already its own event — so this
-- is a pure read-time projection over the same 'Ledger'.
--
-- Order: append/evaluation order ('toList' on a 'DList' yields oldest-first).
-- This equals @AT@ order ONLY for literal-AT @#TRACE@ events (those are stably
-- sorted by 'sortByStablePinned'/'eventAtKey' at build time); runtime-AT events
-- such as @WAIT UNTIL@ stay pinned in authored order.
readCellAll :: Path -> Ledger -> [WHNF]
readCellAll = readCellAllBitemporal Nothing

-----------------------------------------------------------------------------
-- Bitemporal projections (smucclaw/l4-ide#914 §2B)
-----------------------------------------------------------------------------

-- | Read one cell through a bitemporal lens.
--
-- @'readCellBitemporal' txBound vtBound path ledger@:
--
--   * @txBound@ — the @EVAL AS OF SYSTEM TIME@ cutoff: entries appended
--     after the bound ('txTime' > bound) are INVISIBLE (\"what did we know
--     at /t/?\"). 'Nothing' = no cutoff.
--   * @vtBound@ — the @EVAL UNDER VALID TIME@ point: among visible entries,
--     select the one whose valid interval covers the point (\"what held at
--     /t/?\"). 'Nothing' = plain last-write-wins over the visible entries.
--
-- Valid intervals are POSITIONAL, as in a bitemporal table: an entry's
-- interval starts at its 'effectiveVt' and is closed by the next visible
-- entry for the same cell with a later 'effectiveVt'. Concretely the winner
-- is the visible entry with the lexicographically greatest
-- ('effectiveVt', log position) among those with @'effectiveVt' <= vtBound@.
-- Two entries at the SAME valid time are a correction: the later append
-- (the later transaction) wins. Note transaction order within one run IS
-- log order — 'txTime' is a per-run constant (see 'Provenance') — so the
-- tie-break must be positional, never a 'txTime' comparison.
--
-- A @vtBound@ earlier than every visible entry's 'effectiveVt' yields
-- 'Nothing': an \"as of before the facts\" read is a principled miss.
--
-- With both bounds 'Nothing' this is exactly the historical last-write-wins
-- projection; 'readCell' is defined as that instantiation.
readCellBitemporal :: Maybe UTCTime -> Maybe Day -> Path -> Ledger -> Maybe WHNF
readCellBitemporal txBound vtBound p l =
  case vtBound of
    Nothing -> foldl' (\_ (_, v) -> Just v) Nothing visible  -- last visible write wins
    Just vt -> snd <$> foldl' (step vt) Nothing visible
  where
    -- log order (oldest-first), tx-filtered; each entry paired with its
    -- effective valid-from day
    visible =
      [ (effectiveVt prov, v)
      | Assign c v prov <- toList l
      , c == p
      , maybe True (prov.txTime <=) txBound
      ]

    -- keep the entry with the greatest effectiveVt <= vt; on EQUAL
    -- effectiveVt the later log position wins (we fold oldest->newest and
    -- replace on >=) — the same-vt correction rule.
    step vt acc (eVt, v)
      | eVt > vt  = acc
      | otherwise = case acc of
          Just (bestVt, _) | bestVt > eVt -> acc
          _                               -> Just (eVt, v)

-- | Read EVERY visible assignment to a cell, oldest-first — 'readCellAll'
-- through the transaction-time lens only. An @EVAL AS OF SYSTEM TIME@ bound
-- hides later appends exactly as in 'readCellBitemporal'. A valid-time bound
-- is deliberately NOT applied: @RECALL ALL@ is a whole-history projection,
-- and filtering history by a valid-time /point/ is a category error
-- (smucclaw/l4-ide#914 §2B). 'Nothing' = no cutoff = the historical
-- 'readCellAll'.
readCellAllBitemporal :: Maybe UTCTime -> Path -> Ledger -> [WHNF]
readCellAllBitemporal txBound p l =
  [ v
  | Assign c v prov <- toList l
  , c == p
  , maybe True (prov.txTime <=) txBound
  ]

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
-- own ledger (a bare @RECORD@); 'RouteOfficial' appends to the shared official
-- record (a @COMMIT@/@ATTEST@); 'RouteNotify' (NOTIFY v1) appends to a NAMED
-- /recipient/ party's own ledger — the acting party performs the write but it
-- lands in @ownLedgers[recipientKey]@, the exact map @RECALL <party>'s@ reads.
-- The 'Text' is the recipient key, computed via the SAME @partyKeyWHNF@ that a
-- cross-party @RECALL@ uses, so write-key ≡ read-key by construction.
data EventRoute = RouteOwn | RouteOfficial | RouteNotify !Text
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
