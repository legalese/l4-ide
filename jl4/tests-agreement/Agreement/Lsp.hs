-- | A client of jl4-lsp that keeps every notification the server sends, so
-- that a test reads its diagnostics and its directive results as an editor
-- receives them.
module Agreement.Lsp
  ( LspSession (..)
  , withLspSession
  , awaitNotification
  , objField
  ) where

import Control.Concurrent (forkIO, threadDelay)
import Control.Concurrent.MVar
import Control.Exception (IOException, finally, try)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Char as Char
import Data.IORef
import qualified Data.Map.Strict as Map
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Language.LSP.Protocol.Types as LSP
import System.IO (Handle, hClose, hFlush, hSetBinaryMode)
import System.Process
import System.Timeout (timeout)

data LspSession = MkLspSession
  { uri :: T.Text
  , request :: T.Text -> Aeson.Value -> IO (Maybe Aeson.Value)
  -- ^ the answer, or Nothing if none came within two minutes
  , notifications :: IO [Aeson.Value]
  -- ^ every notification so far, the earliest first
  }

objField :: Aeson.Value -> T.Text -> Maybe Aeson.Value
objField v k = case v of
  Aeson.Object o -> KeyMap.lookup (Key.fromText k) o
  _ -> Nothing

-- | Start jl4-lsp, initialize it, open the file in it at version 1, and run
-- the action with the session.
withLspSession :: FilePath -> FilePath -> (LspSession -> IO a) -> IO a
withLspSession lsp absFile act = do
  src <- TE.decodeUtf8 <$> BS.readFile absFile
  let docUri = LSP.getUri (LSP.filePathToUri absFile)
  (Just hin, Just hout, Just herr, ph) <-
    createProcess (proc lsp []) {std_in = CreatePipe, std_out = CreatePipe, std_err = CreatePipe}
  mapM_ (`hSetBinaryMode` True) [hin, hout, herr]
  _ <- forkIO (void (BS.hGetContents herr))
  sendLock <- newMVar ()
  pending <- newIORef (Map.empty :: Map.Map Int (MVar Aeson.Value))
  notes <- newIORef ([] :: [Aeson.Value])
  nextId <- newIORef (1 :: Int)
  let send v = withMVar sendLock \_ -> do
        let body = LBS.toStrict (Aeson.encode v)
        BS.hPut hin (BS8.pack ("Content-Length: " ++ show (BS.length body) ++ "\r\n\r\n") <> body)
        hFlush hin
      reader = readLspMessage hout >>= \case
        Nothing -> pure ()
        Just msg -> do
          case Aeson.decodeStrict msg of
            Just v
              | Just _ <- objField v "method", Just rid <- objField v "id" ->
                  send (Aeson.object ["jsonrpc" Aeson..= ("2.0" :: T.Text), "id" Aeson..= rid, "result" Aeson..= Aeson.Null])
              | Just _ <- objField v "method" -> atomicModifyIORef' notes (\ns -> (v : ns, ()))
              | Just (Aeson.Number n) <- objField v "id" -> do
                  waiting <- readIORef pending
                  case Map.lookup (round n) waiting of
                    Just mv -> void (tryPutMVar mv v)
                    Nothing -> pure ()
            _ -> pure ()
          reader
      ask :: T.Text -> Aeson.Value -> IO (Maybe Aeson.Value)
      ask method params = do
        n <- atomicModifyIORef' nextId (\k -> (k + 1, k))
        mv <- newEmptyMVar
        atomicModifyIORef' pending (\m -> (Map.insert n mv m, ()))
        send (Aeson.object ["jsonrpc" Aeson..= ("2.0" :: T.Text), "id" Aeson..= n, "method" Aeson..= method, "params" Aeson..= params])
        timeout 120000000 (takeMVar mv)
      notify :: T.Text -> Aeson.Value -> IO ()
      notify method params =
        send (Aeson.object ["jsonrpc" Aeson..= ("2.0" :: T.Text), "method" Aeson..= method, "params" Aeson..= params])
      stop = do
        terminateProcess ph
        void (waitForProcess ph)
        void (try (hClose hin) :: IO (Either IOException ()))
  _ <- forkIO reader
  flip finally stop do
    _ <- ask "initialize" (Aeson.object ["processId" Aeson..= Aeson.Null, "rootUri" Aeson..= Aeson.Null, "capabilities" Aeson..= Aeson.object []])
    notify "initialized" (Aeson.object [])
    notify "textDocument/didOpen" (Aeson.object
      [ "textDocument" Aeson..= Aeson.object
          ["uri" Aeson..= docUri, "languageId" Aeson..= ("l4" :: T.Text), "version" Aeson..= (1 :: Int), "text" Aeson..= src]
      ])
    act MkLspSession {uri = docUri, request = ask, notifications = reverse <$> readIORef notes}

-- | The latest notification that satisfies the test, once one has come,
-- waiting up to two minutes.
awaitNotification :: LspSession -> (Aeson.Value -> Bool) -> IO (Maybe Aeson.Value)
awaitNotification s ok = go (1200 :: Int)
 where
  go k = do
    ns <- s.notifications
    case filter ok (reverse ns) of
      v : _ -> pure (Just v)
      []
        | k <= 0 -> pure Nothing
        | otherwise -> threadDelay 100000 >> go (k - 1)

-- | One Content-Length-framed message, or Nothing at the end of the input.
readLspMessage :: Handle -> IO (Maybe BS.ByteString)
readLspMessage h = go BS.empty
 where
  go acc
    | "\r\n\r\n" `BS.isSuffixOf` acc = body acc
    | otherwise = do
        c <- BS.hGet h 1
        if BS.null c then pure Nothing else go (acc <> c)
  body hdr =
    case [ BS8.readInt (BS8.dropWhile Char.isSpace (BS.drop 1 (BS8.dropWhile (/= ':') l)))
         | l <- BS8.lines hdr
         , "content-length" `BS.isPrefixOf` BS8.map Char.toLower l
         ] of
      Just (n, _) : _ -> Just <$> BS.hGet h n
      _ -> pure Nothing
