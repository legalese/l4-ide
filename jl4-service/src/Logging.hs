module Logging (
  Logger,
  LogLevel (..),
  newLogger,
  newLoggerTo,
  logDebug,
  logInfo,
  logWarn,
  logError,
) where

import Control.Concurrent.MVar (MVar, newMVar, withMVar)
import Control.Exception (evaluate)
import Data.Aeson (Value, encode, object, (.=))
import qualified Data.Aeson.Key as Key
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy.Char8 as LBS
import Data.Text (Text)
import Data.Time (getCurrentTime)
import System.IO (Handle, hFlush, stdout)

-- | Log severity levels.
data LogLevel = LevelDebug | LevelInfo | LevelWarn | LevelError
  deriving stock (Eq, Ord, Show)

-- | Structured JSON logger, one object per line.
-- Thread-safe: a line is written whole, under 'logLock'.
data Logger = Logger
  { logMinLevel :: !LogLevel
  , logLock     :: !(MVar ())
  , logHandle   :: !Handle
  }

-- | Create a logger on stdout. Debug mode enables DEBUG level; otherwise INFO and above.
newLogger :: Bool -> IO Logger
newLogger = newLoggerTo stdout

-- | Create a logger writing to the given handle.
newLoggerTo :: Handle -> Bool -> IO Logger
newLoggerTo h debugMode = do
  lock <- newMVar ()
  pure Logger
    { logMinLevel = if debugMode then LevelDebug else LevelInfo
    , logLock = lock
    , logHandle = h
    }

-- | Log at DEBUG level.
logDebug :: Logger -> Text -> [(Text, Value)] -> IO ()
logDebug = logMsg LevelDebug

-- | Log at INFO level.
logInfo :: Logger -> Text -> [(Text, Value)] -> IO ()
logInfo = logMsg LevelInfo

-- | Log at WARN level.
logWarn :: Logger -> Text -> [(Text, Value)] -> IO ()
logWarn = logMsg LevelWarn

-- | Log at ERROR level.
logError :: Logger -> Text -> [(Text, Value)] -> IO ()
logError = logMsg LevelError

-- | Core logging function. Writes a single JSON line to stdout.
logMsg :: LogLevel -> Logger -> Text -> [(Text, Value)] -> IO ()
logMsg level logger msg fields
  | level < logger.logMinLevel = pure ()
  | otherwise = do
      now <- getCurrentTime
      let entry = object $
            [ "time" .= show now
            , "level" .= levelText level
            , "msg" .= msg
            ] <> [(Key.fromText k, v) | (k, v) <- fields]
      -- Encode before taking the lock, so that threads encode in parallel and
      -- only the write is one at a time. A strict ByteString in WHNF is the
      -- whole line.
      line <- evaluate (LBS.toStrict (encode entry <> "\n"))
      -- One write per line, under the lock. A lazy 'LBS.hPut' writes each
      -- chunk separately, and the newline is a chunk of its own, so on more
      -- than one core two threads' lines came out joined as @}{@ (144 of the
      -- 1,103 lines of one run on -N10, 2026-10-02). The lock used to be an
      -- 'atomicModifyIORef'' on a unit, which serialised nothing.
      withMVar logger.logLock $ \() -> do
        BS.hPut logger.logHandle line
        hFlush logger.logHandle

-- | Convert log level to text label.
levelText :: LogLevel -> Text
levelText = \case
  LevelDebug -> "debug"
  LevelInfo  -> "info"
  LevelWarn  -> "warn"
  LevelError -> "error"
