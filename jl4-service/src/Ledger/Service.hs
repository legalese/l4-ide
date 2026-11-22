-- | The instance ledger as the service holds it (OPERATIONAL-LOWERING-SPEC
-- §3.7, §9 WPO3, R-O5): the store it was configured with, opened on first
-- use; the ledger clock; the evaluator's configuration and limits; the
-- ledger's own slot pool. "Ledger" serves the routes over it; this module
-- is what 'Types.AppEnv' carries, and imports nothing of the handlers.
--
-- The store is opened by the first request that needs it, not at start.
-- Opening the sqlite default creates @ledger.sqlite3@ under the store path,
-- and a service that never serves an instance route has no reason to put a
-- database file there, a hosted store path on a network filesystem
-- included (D-O12). A store that cannot be opened is said so on every
-- request that needs it, and the decision routes and the decision tools
-- never ask for it.
module Ledger.Service
  ( LedgerService (..)
  , newLedgerService
  , posixClock
  , withOpenedStore
  , instancesHeld
  , withLedgerSlot
  , offersOfDeployment
  ) where

import Control.Concurrent (getNumCapabilities)
import Control.Concurrent.MVar (MVar, modifyMVar, modifyMVar_, newMVar, readMVar)
import Control.Concurrent.STM (TVar, atomically, modifyTVar', newTVarIO, readTVar, writeTVar)
import Control.Exception (SomeAsyncException, SomeException, displayException, finally, fromException, mask, throwIO, try)
import Data.Text (Text)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Time.Clock.POSIX (getPOSIXTime)
import System.Directory (doesFileExist)
import System.FilePath ((</>))

import qualified L4.EvaluateLazy as Eval
import L4.EvaluateLazy (EvalConfig)
import L4.Ledger.Offer (Offers, offersFor)
import L4.Ledger.Replay (Deployment (..))
import L4.TracePolicy (apiDefaultPolicy)
import EvalLimits (LimitHit (..), withThreadLimits)
import Ledger.Store.Config (OpenedStore (..), ResolvedStore (..), openLedgerStore)
import Ledger.Store.Sqlite (ledgerFileName)
import Options (Options (..))

data LedgerService = MkLedgerService
  { resolved     :: !ResolvedStore
  , opened       :: !(MVar (Maybe OpenedStore))
    -- ^ 'Nothing' until the first request that needs the store opens it
  , clock        :: !(IO Rational)
    -- ^ the ledger clock (§3.4); see 'posixClock' for the service's own
  , evalConfig   :: !EvalConfig
  , timeoutSec   :: !Int
    -- ^ one ledger request's time limit, @--eval-timeout@
  , memoryMb     :: !Int
    -- ^ one ledger request's allocation limit, @--ledger-max-eval-memory-mb@
  , retryCap     :: !Int
    -- ^ lost compare-and-append races before an append is 'Unknown'
  , slotCount    :: !Int
  , slotsFree    :: !(TVar Int)
    -- ^ the ledger's own slot pool ('withLedgerSlot')
  , creationLock :: !(MVar ())
    -- ^ held while an instance is created, and while a deployment is
    -- checked for instances and deleted, so that neither can slip between
    -- the other's check and its act within this process
  , offerCache   :: !(MVar (Map.Map Text OfferEntry))
    -- ^ the acts each deployment's source offers (WPO6), by deployment; see
    -- 'offersOfDeployment'
  }

-- | A deployment's offers, with the source they were worked out from.
data OfferEntry = MkOfferEntry
  { source  :: !Text
  , imports :: ![(Text, Text)]
  , offers  :: !(Either Text Offers)
  }

-- | The ledger for a service with these options, its store resolved but not
-- opened, and this clock.
newLedgerService :: Options -> ResolvedStore -> IO Rational -> IO LedgerService
newLedgerService opts store clk = do
  fixedNow <- Eval.readFixedNowEnv
  cfg <- Eval.resolveEvalConfig fixedNow apiDefaultPolicy
  caps <- getNumCapabilities
  let slots = ledgerSlots caps opts.maxConcurrentRequests
  free <- newTVarIO slots
  openedVar <- newMVar Nothing
  lock <- newMVar ()
  offerVar <- newMVar Map.empty
  pure MkLedgerService
    { resolved = store
    , opened = openedVar
    , clock = clk
    , evalConfig = cfg
    , timeoutSec = opts.evalTimeout
    , memoryMb = opts.ledgerMaxEvalMemoryMb
    , retryCap = 8
    , slotCount = slots
    , slotsFree = free
    , creationLock = lock
    , offerCache = offerVar
    }

-- | How many ledger requests evaluate at once: one per capability, and
-- never more than half the app-wide request limit, so that ledger requests
-- cannot hold every request slot between them; at least one. Assumed, not
-- ruled (D-O10: sized by the first deployment).
ledgerSlots :: Int -> Int -> Int
ledgerSlots caps maxRequests = max 1 (min caps (maxRequests `div` 2))

-- | The service's ledger clock: whole seconds since the Unix epoch, UTC.
--
-- Assumed, not ruled: what one unit of a contract's time is, and where an
-- instance's @AT@ start sits against wall time, is D-O8, open. A contract
-- written against another unit or epoch (the dinner fixture counts seconds
-- from midnight) runs on this clock with every deadline shifted, and
-- nothing says so; the fixture's own times are reached only by a clock a
-- test sets. Discrete, as the contract clock is (T2).
posixClock :: IO Rational
posixClock = toRational . (floor :: Rational -> Integer) . toRational <$> getPOSIXTime

-- | Run with the store, opening it first if no request has yet. 'Left' says
-- why it could not be opened; the next request tries again.
withOpenedStore :: LedgerService -> (OpenedStore -> IO a) -> IO (Either Text a)
withOpenedStore ldg act = openOnce ldg >>= \ case
  Left why -> pure (Left why)
  Right o -> Right <$> act o

openOnce :: LedgerService -> IO (Either Text OpenedStore)
openOnce ldg = modifyMVar ldg.opened \ case
  Just o -> pure (Just o, Right o)
  Nothing -> do
    r <- trySync (openLedgerStore ldg.resolved)
    pure case r of
      Right (Right o) -> (Just o, Right o)
      Right (Left why) -> (Nothing, Left ("the ledger store could not be opened: " <> why))
      Left e -> (Nothing, Left ("the ledger store could not be opened: " <> Text.pack (displayException e)))

-- | The instances the store holds for a deployment, asked before the
-- deployment is deleted or overwritten (R-O5). A sqlite store that has never
-- been opened and has no file holds none, and is not created to say so; any
-- other store is opened. 'Left' when the store cannot be read: the caller
-- then cannot know, and must not act as if it held none.
instancesHeld :: LedgerService -> Text -> IO (Either Text [Text])
instancesHeld ldg deployment = do
  current <- readMVar ldg.opened
  case (current, ldg.resolved) of
    (Nothing, SqliteAt dir) -> do
      present <- doesFileExist (dir </> ledgerFileName)
      if present then ask else pure (Right [])
    (Nothing, MemoryForTests) -> pure (Right [])
    _ -> ask
  where
    ask = withOpenedStore ldg (\ o -> trySync (o.instancesOf deployment)) >>= \ case
      Left why -> pure (Left why)
      Right (Left e) -> pure (Left ("the ledger store could not list its instances: " <> Text.pack (displayException e)))
      Right (Right names) -> pure (Right names)

-- | Run in one of the ledger's slots, or say at once that none is free.
--
-- The app-wide limiter answers a request with a plain 503 before any
-- handler runs once its slots are taken, and a ledger request holds one of
-- them for as long as it evaluates. So ledger requests do not queue for a
-- slot of their own, holding an app-wide slot while they wait: one that
-- finds every ledger slot taken is answered at once ('Nothing'), and the
-- caller says, as for that 503, that nothing was applied.
withLedgerSlot :: LedgerService -> IO a -> IO (Maybe a)
withLedgerSlot ldg act = mask \ restore -> do
  got <- atomically do
    n <- readTVar ldg.slotsFree
    if n > 0 then writeTVar ldg.slotsFree (n - 1) >> pure True else pure False
  if got
    then (Just <$> restore act) `finally` atomically (modifyTVar' ldg.slotsFree (+ 1))
    else pure Nothing

-- | The acts a deployment's source offers to each party (WPO6, D-O13).
--
-- Reading them type-checks the source, which is as dear as the type check
-- of an append, so it is done once per source and kept, one entry per
-- deployment, replaced when the deployment's files change (the entry holds
-- the source it was read from and is compared with it, so a redeploy under
-- the same version name cannot leave a stale one). It runs in one of the
-- ledger's slots, under its time and allocation limits. A source that
-- does not type-check is cached and is a 'Left'; a slot that is not free or
-- a limit that was hit is a 'Left' that is not cached.
offersOfDeployment :: LedgerService -> Deployment -> IO (Either Text Offers)
offersOfDeployment ldg dep = do
  cache <- readMVar ldg.offerCache
  case Map.lookup dep.deploymentId cache of
    Just e | e.source == dep.deploymentSource && e.imports == dep.deploymentImports -> pure e.offers
    _ -> withLedgerSlot ldg (withThreadLimits ldg.timeoutSec ldg.memoryMb (pure (offersFor dep))) >>= \ case
      Nothing -> pure (Left ("all " <> Text.pack (show ldg.slotCount) <> " of the ledger's evaluation slots are taken; ask again"))
      Just (Left (TimeLimitHit, _)) -> pure (Left ("reading the deployment's acts did not finish within the ledger's time limit of " <> Text.pack (show ldg.timeoutSec) <> " s"))
      Just (Left (AllocationLimitHit, _)) -> pure (Left ("reading the deployment's acts allocated more than the ledger's limit of " <> Text.pack (show ldg.memoryMb) <> " MB"))
      Just (Right (r, _)) -> do
        modifyMVar_ ldg.offerCache (pure . Map.insert dep.deploymentId (MkOfferEntry dep.deploymentSource dep.deploymentImports r))
        pure r

-- | 'try' for the exceptions an action raises itself: an asynchronous one,
-- a time limit or a kill aimed at the thread, goes on up, so that catching
-- a store's failure never swallows the limit that was stopping it.
trySync :: IO a -> IO (Either SomeException a)
trySync act = try act >>= \ case
  Left e | Just (_ :: SomeAsyncException) <- fromException e -> throwIO e
  r -> pure r
