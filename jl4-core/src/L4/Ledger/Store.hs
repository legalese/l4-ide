-- | The synchronization store behind an instance ledger
-- (OPERATIONAL-LOWERING-SPEC §3.7): two operations and nothing else.
--
-- Correctness rests on 'appendRow' refusing a stale head. The ledger reads
-- the rows, evaluates with no lock held, and appends at head plus one; a
-- 'Left' means another appender won, and the ledger's step re-runs from
-- 'readRows'. So any store that can compare-and-append per instance will
-- do, and none ever holds a lock while L4 is evaluating.
--
-- Only the in-memory store is built here, and it is for tests: it is not
-- durable, and it serializes one process. The sqlite default, the Postgres
-- adapter and store selection are WPO2, in @jl4-service@.
module L4.Ledger.Store
  ( LedgerStore (..)
  , newMemoryStore
  ) where

import Base
import qualified Base.Map as Map
import Control.Concurrent.MVar (modifyMVar, newMVar, readMVar)
import qualified Data.Sequence as Seq

import L4.Ledger.Row (InstanceKey, Row, SeqNo)

data LedgerStore = MkLedgerStore
  { readRows  :: InstanceKey -> IO [Row]
    -- ^ the instance's history, in seq order; empty for an instance the
    -- store does not hold. Every created instance holds its opening, so
    -- empty means not found, never a fresh instance.
  , appendRow :: InstanceKey -> SeqNo -> Row -> IO (Either SeqNo ())
    -- ^ append as seq @n@ iff the current head is @n - 1@; 'Left' is the
    -- actual head. The row's own 'L4.Ledger.Row.seqNo' is the caller's to
    -- set to @n@.
  }

-- | A store in one process's memory: one 'Data.Sequence.Seq' of rows per
-- instance, behind one 'MVar', so a compare-and-append is one
-- 'modifyMVar'. Every instance is lost when the process ends.
newMemoryStore :: IO LedgerStore
newMemoryStore = do
  ref <- newMVar (Map.empty :: Map InstanceKey (Seq.Seq Row))
  pure MkLedgerStore
    { readRows = \ k -> maybe [] toList . Map.lookup k <$> readMVar ref
    , appendRow = \ k n row -> modifyMVar ref \ m ->
        let rows = Map.findWithDefault Seq.empty k m
            current = Seq.length rows
        in pure if current == n - 1
          then (Map.insert k (rows Seq.|> row) m, Right ())
          else (m, Left current)
    }
