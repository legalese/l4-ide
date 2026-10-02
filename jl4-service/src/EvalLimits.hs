-- | The two limits every evaluation runs under, in one place: the data plane
-- (single and batch evaluation) and the MCP server both go through
-- 'withEvalLimits'.
module EvalLimits (
  LimitHit (..),
  withEvalLimits,
  limitHitMessage,
) where

import Control.Exception (catch, finally)
import Data.Int (Int64)
import Data.Text (Text)
import qualified Data.Text as Text
import GHC.Conc (setAllocationCounter, getAllocationCounter, enableAllocationLimit, disableAllocationLimit)
import GHC.IO.Exception (AllocationLimitExceeded (..))
import Options (Options (..))
import System.Timeout (timeout)

-- | Which of an evaluation's two limits stopped it.
data LimitHit = TimeLimitHit | AllocationLimitHit

-- | The message on a batch case that hit a limit. It keeps the prefix of the
-- 500 a single evaluation gets, and names the limit and the option that sets it.
limitHitMessage :: Options -> LimitHit -> Text
limitHitMessage cfg = \case
  TimeLimitHit ->
    "Evaluation resource limit exceeded: this case ran past the time limit of "
      <> Text.pack (show cfg.evalTimeout) <> " s (--eval-timeout)"
  AllocationLimitHit ->
    "Evaluation resource limit exceeded: this case allocated more than the limit of "
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
