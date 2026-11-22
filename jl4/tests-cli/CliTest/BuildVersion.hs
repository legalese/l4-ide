-- | Black-box tests for the line that names a build ("LSP.L4.BuildInfo"):
-- @l4 --version@, @jl4-lsp --version@, the language server's @serverInfo@ and
-- and its start-up log line. ("CliTest.BuildIdentity" tests the script that sets
-- the variables the line is baked from in the release workflow.)
--
-- What a binary prints is fixed when it is compiled, so these tests cannot set
-- it. They compare it with the variables that are in the environment of the
-- test run. The release workflow (@main-tag.yml@) writes the variables for the
-- build step and the test step alike, so there the test fails if the bake did
-- not take: a release binary that says @dev@, or says the wrong release. Without
-- the variables the binary must say @dev@.
module CliTest.BuildVersion (spec) where

import Control.Concurrent (forkIO)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Exception (IOException, catch)
import Control.Monad (void)
import Data.Char (isSpace)
import Data.List (intercalate, isInfixOf)
import Data.Maybe (fromMaybe)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Lazy as BSL
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import System.Directory (doesFileExist, makeAbsolute)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..))
import System.IO (Handle, hClose, hFlush, hSetBinaryMode)
import System.Process
  ( CreateProcess (..)
  , StdStream (..)
  , createProcess
  , proc
  , readCreateProcessWithExitCode
  , terminateProcess
  , waitForProcess
  )
import System.Timeout (timeout)
import Test.Hspec

import CliTest.Common

trim :: String -> String
trim = reverse . dropWhile isSpace . reverse . dropWhile isSpace

-- | No white space at either end, and any run of it inside a single space: how
-- the renderer treats each part, so a value with a line break in it still gives
-- one line.
oneLine :: String -> String
oneLine = unwords . words

-- | The line this build should print, when the variables it was built with are
-- in the environment of the test run: the release, then the branch (@unknown@
-- if none), the first seven characters of the commit and the date in brackets,
-- with the commit and the date left out when empty. 'Nothing' when there is no
-- release, and the build is a @dev@ build. Each variable is read as the
-- renderer reads it: no white space at either end, and a run of it inside a
-- part becomes one space.
--
-- This restates the format of 'LSP.L4.BuildInfo.renderBuildInfo' on purpose, so
-- that the test does not use the code it checks.
expectedFromEnvironment :: IO (Maybe String)
expectedFromEnvironment = do
  release <- oneLine . fromMaybe "" <$> lookupEnv "L4_BUILD_RELEASE"
  branch <- oneLine . fromMaybe "" <$> lookupEnv "L4_BUILD_BRANCH"
  commit <- oneLine . fromMaybe "" <$> lookupEnv "L4_BUILD_COMMIT"
  date <- oneLine . fromMaybe "" <$> lookupEnv "L4_BUILD_DATE"
  let details = (if null branch then "unknown" else branch) : filter (not . null) [take 7 commit, date]
  pure $
    if null release
      then Nothing
      else Just (release ++ " (" ++ intercalate ", " details ++ ")")

-- | Find the @jl4-lsp@ binary: @JL4_LSP_BIN@, else the one Cabal built for this
-- test suite (@build-tool-depends@ makes sure it is built).
locateLspBinary :: IO (Maybe FilePath)
locateLspBinary = do
  fromEnv <- lookupEnv "JL4_LSP_BIN"
  case fromEnv of
    Just p -> do
      ok <- doesFileExist p
      if ok then Just <$> makeAbsolute p else pure Nothing
    Nothing -> do
      (code, out, _err) <- readCreateProcessWithExitCode (proc "cabal" ["list-bin", "exe:jl4-lsp"]) ""
      let path = trim out
      ok <- if code == ExitSuccess then doesFileExist path else pure False
      if ok then Just <$> makeAbsolute path else pure Nothing

-- | The line a binary must print for @--version@: exactly what
-- 'expectedFromEnvironment' says, or @dev@ when the environment names no
-- release. Windows ends a line with carriage return and line feed, so the
-- carriage returns are dropped first.
checkVersionLine :: Maybe String -> String -> Expectation
checkVersionLine expected sout =
  filter (/= '\r') sout `shouldBe` fromMaybe "dev" expected ++ "\n"

-- | One @Content-Length@-framed LSP message from a handle, or 'Nothing' at end
-- of input.
readMessage :: Handle -> IO (Maybe BS.ByteString)
readMessage h = go BS.empty
  where
    go acc
      | "\r\n\r\n" `BS.isSuffixOf` acc = body acc
      | otherwise = do
          c <- BS.hGet h 1
          if BS.null c then pure Nothing else go (acc <> c)
    body header =
      case [ BS8.readInt (BS8.dropWhile isSpace (BS.drop 1 (BS8.dropWhile (/= ':') l)))
           | l <- BS8.lines header, "content-length" `BS.isPrefixOf` BS8.map toLowerAscii l ] of
        Just (n, _) : _ -> Just <$> BS.hGet h n
        _ -> pure Nothing
    toLowerAscii c = if c >= 'A' && c <= 'Z' then toEnum (fromEnum c + 32) else c

-- | Start @jl4-lsp@, send it @initialize@, and give back its answer and
-- everything it wrote to stderr up to being stopped. 'Nothing' for the answer if
-- none came within a minute.
initializeServer :: FilePath -> IO (Maybe Aeson.Value, String)
initializeServer lsp = do
  (Just hin, Just hout, Just herr, ph) <-
    createProcess (proc lsp []) {std_in = CreatePipe, std_out = CreatePipe, std_err = CreatePipe}
  mapM_ (`hSetBinaryMode` True) [hin, hout, herr]
  errVar <- newEmptyMVar
  _ <- forkIO (BS.hGetContents herr >>= putMVar errVar)
  let request = BS8.pack "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"processId\":null,\"rootUri\":null,\"capabilities\":{}}}"
  BS.hPut hin (BS8.pack ("Content-Length: " ++ show (BS.length request) ++ "\r\n\r\n") <> request)
  hFlush hin
  answered <- timeout 60000000 (readMessage hout)
  terminateProcess ph
  void (waitForProcess ph)
  hClose hin `catch` \(_ :: IOException) -> pure ()
  errBytes <- takeMVar errVar
  pure
    ( case answered of
        Just (Just msg) -> Aeson.decode (BSL.fromStrict msg)
        _ -> Nothing
    , T.unpack (TE.decodeUtf8Lenient errBytes)
    )

spec :: FilePath -> Spec
spec bin = describe "the line that names a build" $ do
  mLsp <- runIO locateLspBinary
  let withLsp act = maybe (pendingWith "no jl4-lsp binary (set JL4_LSP_BIN, or run under cabal test)") act mLsp

  describe "l4 --version" $ do
    it "prints one line naming the build, and nothing else, and succeeds" $ do
      expected <- expectedFromEnvironment
      Output code sout serr <- runL4 bin ["--version"]
      code `shouldBe` ExitSuccess
      filter (/= '\r') serr `shouldBe` ""
      checkVersionLine expected sout

    it "is listed in l4 --help" $ do
      Output _ sout _ <- runL4 bin ["--help"]
      sout `shouldSatisfy` ("--version" `isInfixOf`)

  describe "jl4-lsp --version" $ do
    it "prints the line l4 --version prints" $ withLsp \lsp -> do
      expected <- expectedFromEnvironment
      Output code sout serr <- runL4 lsp ["--version"]
      code `shouldBe` ExitSuccess
      filter (/= '\r') serr `shouldBe` ""
      checkVersionLine expected sout
      Output _ l4Out _ <- runL4 bin ["--version"]
      sout `shouldBe` l4Out

  describe "the language server" $ do
    it "reports the line as serverInfo, and logs it when it starts" $ withLsp \lsp -> do
      expected <- expectedFromEnvironment
      (answer, stderrText) <- initializeServer lsp
      let line = fromMaybe "dev" expected
          serverInfo = answer >>= (`objField` "result") >>= (`objField` "serverInfo")
      fmap (`objField` "name") serverInfo `shouldBe` Just (Just (Aeson.String "jl4-lsp"))
      fmap (`objField` "version") serverInfo `shouldBe` Just (Just (Aeson.String (T.pack line)))
      stderrText `shouldSatisfy` (("| Info | jl4-lsp " ++ line) `isInfixOf`)
