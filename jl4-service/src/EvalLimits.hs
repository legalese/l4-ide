-- | The two limits an evaluation runs under, in one place: the data plane
-- (single and batch evaluation) and the MCP server both go through
-- 'withEvalLimits'.
--
-- What they cover: the evaluation itself, on the direct path (the calling
-- thread) and on the generated-wrapper path (a Shake rule on another thread,
-- see 'currentAllocationLimit'). Arithmetic the evaluator leaves unfinished is
-- finished while the response is encoded, outside both (measured 2026-10-03;
-- the jl4-service README, "What the limits do not cover yet").
module EvalLimits (
  LimitHit (..),
  withEvalLimits,
  currentAllocationLimit,
  limitHitMessage,
) where

import Backend.Api (LimitHit (..))
import Control.Exception (catch, finally)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import System.IO.Unsafe (unsafePerformIO)
import Data.Int (Int64)
import Data.Text (Text)
import qualified Data.Text as Text
import GHC.Conc (setAllocationCounter, getAllocationCounter, enableAllocationLimit, disableAllocationLimit)
import GHC.IO.Exception (AllocationLimitExceeded (..))
import Options (Options (..))
import System.Timeout (timeout)

-- | The message on a batch case that hit a limit. It keeps the prefix of the
-- 500 a single evaluation gets, and names the limit and the option that sets
-- it. It does not say why the case took that long or that much: the case's
-- own work and a busy service look the same from here.
limitHitMessage :: Options -> LimitHit -> Text
limitHitMessage cfg = \case
  TimeLimitHit ->
    "Evaluation resource limit exceeded: this case did not finish within the time limit of "
      <> Text.pack (show cfg.evalTimeout) <> " s (--eval-timeout)"
  AllocationLimitHit ->
    "Evaluation resource limit exceeded: this case allocated more than the memory limit of "
      <> Text.pack (show cfg.maxEvalMemoryMb) <> " MB (--max-eval-memory-mb)"

-- | Run an evaluation under the configured time and allocation limits.
--
-- Returns the result and the GHC allocation bytes it consumed, or which limit
-- stopped it and the bytes allocated up to then (for the allocation limit, the
-- limit itself). The allocation counter belongs to the calling thread, so it
-- counts only this evaluation; the time limit is wall-clock, so it counts
-- whatever else shares the core meanwhile. That is why the batch endpoint
-- bounds how many of its cases run at once.
--
-- The allocation limit is switched off again on the way out. Left on, it goes
-- on counting down whatever the thread does next, such as encoding a single
-- evaluation's response, and can raise 'AllocationLimitExceeded' there,
-- outside this handler; once it has been hit, the RTS re-arms it with a grace
-- allowance of only 100K (@+RTS -xq@) before raising it again. On a kept-alive
-- connection the next request runs on the same thread, so before the MCP
-- server came through here, 5 of 40 kept-alive calls near the limit dropped
-- their connection (measured 2026-10-02).
withEvalLimits :: Options -> IO b -> IO (Either (LimitHit, Int64) (b, Int64))
withEvalLimits cfg act =
  ( do
      writeIORef allocationLimitRef (Just memLimitBytes)
      setAllocationCounter memLimitBytes
      enableAllocationLimit
      result <- timeout timeoutMicros act
      allocBytes <- (memLimitBytes -) <$> getAllocationCounter
      pure $ maybe (Left (TimeLimitHit, allocBytes)) (\r -> Right (r, allocBytes)) result
  ) `catch` (\AllocationLimitExceeded -> pure (Left (AllocationLimitHit, memLimitBytes)))
    `finally` disableAllocationLimit
 where
  timeoutMicros = cfg.evalTimeout * 1_000_000
  memLimitBytes = fromIntegral cfg.maxEvalMemoryMb * 1024 * 1024 :: Int64

-- | The allocation limit, in bytes, that the service's evaluations run under;
-- 'Nothing' until the first 'withEvalLimits'.
--
-- GHC's allocation counter belongs to one thread. The wrapper path evaluates
-- as a Shake rule, which runs on a thread of its own, so the limit
-- 'withEvalLimits' sets on the calling thread never sees it
-- (smucclaw/l4-ide#1018). The evaluator therefore sets the limit itself, on
-- its own thread ('L4.EvaluateLazy.allocationLimit'), and reads the number
-- from here. It is published rather than passed because it is a property of
-- the process (@--max-eval-memory-mb@), not of a request, and passing it would
-- add an argument to every function between the request and the evaluator.
--
-- Each Shake rule thread, the module's and each import's, gets the whole
-- limit, so a call that imports modules can allocate the limit once per
-- module.
currentAllocationLimit :: IO (Maybe Int64)
currentAllocationLimit = readIORef allocationLimitRef

allocationLimitRef :: IORef (Maybe Int64)
allocationLimitRef = unsafePerformIO (newIORef Nothing)
{-# NOINLINE allocationLimitRef #-}
