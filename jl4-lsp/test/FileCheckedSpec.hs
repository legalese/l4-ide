{-# LANGUAGE ExplicitNamespaces #-}
-- | @l4/fileChecked@, from the client's side.
--
-- What is under test is the order and the content of what a running server
-- says after an edit, so these examples start the real @jl4-lsp@ and speak the
-- protocol to it over its stdio. This repository has no LSP test library, and a
-- few lines of JSON-RPC are all that is needed.
module FileCheckedSpec (spec) where

import Control.Concurrent (forkIO, threadDelay)
import Control.Concurrent.Chan (Chan, newChan, readChan, writeChan)
import Control.Exception (IOException, try)
import Control.Monad (forM_, forever, void)
import Data.Aeson (FromJSON, Value (..), object, (.:), (.=))
import qualified Data.Aeson as Aeson
import Data.Aeson.Types (Parser, parseMaybe)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Lazy as LBS
import Data.Maybe (isJust, mapMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import System.Directory (findExecutable)
import System.FilePath ((<.>), (</>))
import System.IO (Handle, hFlush, hGetContents')
import System.Process (CreateProcess (..), StdStream (..), proc, withCreateProcess)
import System.Timeout (timeout)

import Language.LSP.Protocol.Types (Diagnostic (..), Uri (..), filePathToUri, toNormalizedUri, type (|?) (..))

import LSP.L4.Inspector (DirectiveResultsUpdatedParams (..), DirectiveUpdateItem (..), FileCheckedParams (..))

import ImportOnceSpec (withTree)

import Test.Hspec

data Server = Server
  { input :: Handle
  , inbox :: Chan Value
  , root :: FilePath
  }

withServer :: (Server -> IO a) -> IO a
withServer = withClient (object [])

-- | The capabilities of a client that watches files, as VS Code does. It makes
-- the server dirty only what changed, instead of revisiting everything.
watchingFiles :: Value
watchingFiles = object
  ["workspace" .= object ["didChangeWatchedFiles" .= object ["dynamicRegistration" .= True]]]

-- | Start a server in a fresh directory and take it through the handshake, as a
-- client with these capabilities.
withClient :: Value -> (Server -> IO a) -> IO a
withClient capabilities act = withTree "file-checked" [] \dir -> do
  exe <- findExecutable "jl4-lsp" >>= maybe (fail "jl4-lsp is not on the PATH: run this with cabal test") pure
  let process = (proc exe []) {cwd = Just dir, std_in = CreatePipe, std_out = CreatePipe, std_err = CreatePipe}
  withCreateProcess process \mIn mOut mErr _ -> case (mIn, mOut, mErr) of
    (Just input, Just output, Just errors) -> do
      inbox <- newChan
      void $ forkIO $ void $ try @IOException $ forever (readMessage output >>= writeChan inbox)
      void $ forkIO $ void $ try @IOException $ void (hGetContents' errors)
      let server = Server {input, inbox, root = dir}
      send server $ object
        [ "jsonrpc" .= ("2.0" :: Text)
        , "id" .= (1 :: Int)
        , "method" .= ("initialize" :: Text)
        , "params" .= object
            [ "processId" .= Null
            , "rootUri" .= filePathToUri dir
            , "capabilities" .= capabilities
            ]
        ]
      void $ await server (isJust . parseMaybe (Aeson.withObject "response" (\o -> o .: "result" :: Parser Value)))
      notify server "initialized" (object [])
      act server
    _ -> fail "jl4-lsp started without pipes"

readMessage :: Handle -> IO Value
readMessage h = do
  size <- headers Nothing
  body <- BS.hGet h size
  either fail pure (Aeson.eitherDecodeStrict body)
 where
  headers size = do
    header <- BS8.filter (/= '\r') <$> BS8.hGetLine h
    case BS8.stripPrefix "Content-Length: " header of
      _ | BS8.null header -> maybe (fail "a message with no Content-Length") pure size
      Just n -> headers (fst <$> BS8.readInt n)
      Nothing -> headers size

send :: Server -> Value -> IO ()
send server message = do
  let body = LBS.toStrict (Aeson.encode message)
  BS.hPut server.input (BS8.pack ("Content-Length: " <> show (BS.length body) <> "\r\n\r\n") <> body)
  hFlush server.input

notify :: Server -> Text -> Value -> IO ()
notify server method params =
  send server $ object ["jsonrpc" .= ("2.0" :: Text), "method" .= method, "params" .= params]

-- | Everything the server says, in order, up to and including the first
-- message that satisfies the predicate.
await :: Server -> (Value -> Bool) -> IO [Value]
await server done = go []
 where
  go seen = do
    next <- timeout 60_000_000 (readChan server.inbox)
    case next of
      Nothing -> fail ("timed out waiting; the server said: " <> show (reverse seen))
      Just message
        | done message -> pure (reverse (message : seen))
        | otherwise -> go (message : seen)

docUri :: Server -> String -> Uri
docUri server name = filePathToUri (server.root </> name <.> "l4")

open :: Server -> String -> Int -> Text -> IO ()
open server name version text = notify server "textDocument/didOpen" $ object
  [ "textDocument" .= object
      [ "uri" .= docUri server name
      , "languageId" .= ("l4" :: Text)
      , "version" .= version
      , "text" .= text
      ]
  ]

change :: Server -> String -> Int -> Text -> IO ()
change server name version text = notify server "textDocument/didChange" $ object
  [ "textDocument" .= object ["uri" .= docUri server name, "version" .= version]
  , "contentChanges" .= [object ["text" .= text]]
  ]

save :: Server -> String -> IO ()
save server name = notify server "textDocument/didSave" $ object
  ["textDocument" .= object ["uri" .= docUri server name]]

paramsOf :: FromJSON a => Text -> Value -> Maybe a
paramsOf method = parseMaybe $ Aeson.withObject "message" \o -> do
  actual <- o .: "method"
  if actual == method then o .: "params" else fail "another method"

fileChecked :: Value -> Maybe FileCheckedParams
fileChecked = paramsOf "l4/fileChecked"

directiveResults :: Value -> Maybe DirectiveResultsUpdatedParams
directiveResults = paramsOf "l4/directiveResultsUpdated"

isFor :: Server -> String -> Text -> Bool
isFor server name uri = toNormalizedUri (Uri uri) == toNormalizedUri (docUri server name)

-- | Wait for the first @l4/fileChecked@ of a document that satisfies the
-- predicate. Returns it, with everything said before it.
awaitChecked :: Server -> String -> (FileCheckedParams -> Bool) -> IO ([Value], FileCheckedParams)
awaitChecked server name wanted = do
  said <- await server (\m -> maybe False (\p -> isFor server name p.uri && wanted p) (fileChecked m))
  case fileChecked (last said) of
    Just checked -> pure (init said, checked)
    Nothing -> fail "not a l4/fileChecked"

ofVersion :: Int -> FileCheckedParams -> Bool
ofVersion version p = p.version == Just (fromIntegral version)

codes :: FileCheckedParams -> [Text]
codes p = mapMaybe code p.diagnostics
 where
  code d = case d._code of
    Just (InR c) -> Just c
    _ -> Nothing

messages :: FileCheckedParams -> [Text]
messages p = map (\d -> T.strip d._message) p.diagnostics

clean, illTyped, unparsable :: Text
clean = "DECIDE `the answer` IS 42\n\n#EVAL `the answer`\n"
illTyped = "DECIDE `the answer` IS `not defined anywhere`\n\n#EVAL `the answer`\n"
unparsable = "DECLARE Foo HAS\n  x WITH\n"

spec :: Spec
spec = describe "l4/fileChecked" do
  it "is sent after an edit that changes nothing, which no publish announces" do
    withServer \server -> do
      open server "doc" 1 clean
      (_, first) <- awaitChecked server "doc" (ofVersion 1)
      codes first `shouldBe` ["eval/result"]
      change server "doc" 2 clean
      (_, second) <- awaitChecked server "doc" (ofVersion 2)
      second.diagnostics `shouldBe` first.diagnostics

  it "is sent after a save" do
    withServer \server -> do
      open server "doc" 1 clean
      _ <- awaitChecked server "doc" (ofVersion 1)
      save server "doc"
      (_, saved) <- awaitChecked server "doc" (ofVersion 1)
      codes saved `shouldBe` ["eval/result"]

  it "is sent for a file that does not type-check, with no directive results" do
    withServer \server -> do
      open server "doc" 1 illTyped
      (earlier, checked) <- awaitChecked server "doc" (ofVersion 1)
      codes checked `shouldContain` ["check/unknown-identifier"]
      mapMaybe directiveResults earlier `shouldBe` []

  it "is sent again when that file changes in no way that matters" do
    withServer \server -> do
      open server "doc" 1 illTyped
      (_, first) <- awaitChecked server "doc" (ofVersion 1)
      change server "doc" 2 illTyped
      (_, second) <- awaitChecked server "doc" (ofVersion 2)
      second.diagnostics `shouldBe` first.diagnostics

  it "is sent for a file that does not parse" do
    withServer \server -> do
      open server "doc" 1 unparsable
      (_, checked) <- awaitChecked server "doc" (ofVersion 1)
      codes checked `shouldBe` ["parse/unexpected-WITH"]

  it "comes after the directive results of the same check" do
    withServer \server -> do
      open server "doc" 1 clean
      (earlier, checked) <- awaitChecked server "doc" (ofVersion 1)
      let results = filter (isFor server "doc" . (.uri)) (mapMaybe directiveResults earlier)
      results `shouldSatisfy` (not . null)
      codes checked `shouldBe` ["eval/result"]

  -- Edits closer together than a check takes supersede each other; edits
  -- further apart are reported one by one. Either way a report must not pair one
  -- version with the diagnostics of another, or with only some of them. The
  -- second #EVAL is the document's version, so it shows. Under heavy load this
  -- found rules that outlive their session ('LSP.Core.Shake.stillInSession').
  forM_ [("", object []), (", watching files", watchingFiles)] \(client, capabilities) ->
    forM_ [("close together", 0), ("spaced out", 15_000)] \(spacing, delay) ->
      it ("reports the version of what it reports, through edits " <> spacing <> client) do
        withClient capabilities \server -> do
          let doc v = T.unlines
                [ "GIVEN n IS A NUMBER"
                , "GIVETH A NUMBER"
                , "countdown n MEANS IF n <= 0 THEN 0 ELSE countdown (n - 1)"
                , ""
                , "#EVAL countdown 20000"
                , "#EVAL " <> T.pack (show v)
                ]
              lastVersion = 20 :: Int
          open server "doc" 1 (doc (1 :: Int))
          _ <- awaitChecked server "doc" (ofVersion 1)
          forM_ [2 .. lastVersion] \v -> do
            change server "doc" v (doc v)
            threadDelay delay
          said <- await server (\m -> maybe False (\p -> isFor server "doc" p.uri && ofVersion lastVersion p) (fileChecked m))
          let checks = filter (isFor server "doc" . (.uri)) (mapMaybe fileChecked said)
              versions = map (.version) checks
          forM_ checks \p -> messages p `shouldBe` ["0", maybe "no version" (T.pack . show) p.version]
          and (zipWith (<=) versions (drop 1 versions)) `shouldBe` True

  -- Two threads enter the ring at different files here, as they do in a server
  -- with both open. That used to hang the session, so that nothing was reported.
  it "is sent for both files of a ring of imports" do
    withServer \server -> do
      open server "left" 1 "IMPORT right\n\nDECIDE x IS 1\n"
      _ <- awaitChecked server "left" (ofVersion 1)
      open server "right" 1 "IMPORT left\n\nDECIDE y IS 2\n"
      (_, right) <- awaitChecked server "right" (ofVersion 1)
      codes right `shouldBe` ["import/cycle"]
      (_, left) <- awaitChecked server "left" (\p -> "import/cycle" `elem` codes p)
      left.version `shouldBe` Just 1

  it "is sent for open files that import the edited one, directly or not" do
    withServer \server -> do
      let base rate = "DECIDE `the rate` IS " <> rate <> "\n"
      open server "base" 1 (base "1")
      _ <- awaitChecked server "base" (ofVersion 1)
      open server "middle" 1 "IMPORT base\n\nDECIDE `the double rate` IS `the rate` * 2\n"
      _ <- awaitChecked server "middle" (ofVersion 1)
      open server "top" 1 "IMPORT middle\n\n#EVAL `the double rate`\n"
      (_, top) <- awaitChecked server "top" (ofVersion 1)
      messages top `shouldBe` ["2"]

      -- The directive results come first here too, and are of the same check.
      change server "base" 2 (base "5")
      (earlier, updated) <- awaitChecked server "top" (\p -> messages p == ["10"])
      updated.version `shouldBe` Just 1
      let results = filter (isFor server "top" . (.uri)) (mapMaybe directiveResults earlier)
      map (.prettyText) (concatMap (.results) (take 1 (reverse results))) `shouldBe` ["10"]

      change server "base" 3 (base "`nothing by that name`")
      (_, broken) <- awaitChecked server "top" (\p -> "import/module-has-errors" `elem` codes p)
      broken.version `shouldBe` Just 1

      -- An edit says nothing about the files the edited file imports.
      change server "top" 2 "IMPORT middle\n\n#EVAL 0\n"
      (said, _) <- awaitChecked server "top" (ofVersion 2)
      filter (isFor server "base" . (.uri)) (mapMaybe fileChecked said) `shouldBe` []
