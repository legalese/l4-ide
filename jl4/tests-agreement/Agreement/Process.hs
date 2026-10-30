-- | Finding the binaries the test runs, and running them.
module Agreement.Process
  ( locateBinary
  , runIn
  , replReplies
  ) where

import Control.Concurrent (forkIO)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Exception (evaluate)
import Control.Monad (void)
import qualified Data.ByteString as BS
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import System.Directory (doesFileExist, makeAbsolute)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..))
import System.IO (hClose, hSetBinaryMode)
import System.Process

-- | A binary named by an environment variable, else the one Cabal built for
-- the target.
locateBinary :: String -> String -> IO (Maybe FilePath)
locateBinary var target = do
  fromEnv <- lookupEnv var
  case fromEnv of
    Just p -> do
      ok <- doesFileExist p
      if ok then Just <$> makeAbsolute p else pure Nothing
    Nothing -> do
      (code, out, _) <- readCreateProcessWithExitCode (proc "cabal" ["list-bin", "-v0", target]) ""
      let path = takeWhile (`notElem` ("\r\n" :: String)) out
      ok <- if code == ExitSuccess then doesFileExist path else pure False
      if ok then Just <$> makeAbsolute path else pure Nothing

-- | Run a binary in a directory with the given text on its standard input,
-- reading both of its outputs as UTF-8 while it runs.
runIn :: FilePath -> FilePath -> [String] -> T.Text -> IO (ExitCode, T.Text, T.Text)
runIn dir bin args input = do
  (Just hin, Just hout, Just herr, ph) <-
    createProcess (proc bin args) {std_in = CreatePipe, std_out = CreatePipe, std_err = CreatePipe, cwd = Just dir}
  mapM_ (`hSetBinaryMode` True) [hin, hout, herr]
  errVar <- newEmptyMVar
  _ <- forkIO (BS.hGetContents herr >>= evaluate >>= putMVar errVar)
  _ <- forkIO (BS.hPut hin (TE.encodeUtf8 input) >> hClose hin)
  out <- BS.hGetContents hout
  err <- takeMVar errVar
  code <- waitForProcess ph
  pure (code, TE.decodeUtf8Lenient out, TE.decodeUtf8Lenient err)

-- | The REPL's reply to each query, with the file loaded, run in the
-- directory the REPL keeps its history file in.
replReplies :: FilePath -> FilePath -> FilePath -> [T.Text] -> IO [T.Text]
replReplies dir repl file queries = do
  (_, out, _) <- runIn dir repl [file] (T.unlines (queries <> [":quit"]))
  let replies = map T.strip (drop 1 (T.splitOn "jl4> " (T.filter (/= '\r') out)))
  void (evaluate (length replies))
  pure (take (length queries) replies)
