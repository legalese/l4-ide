module LoggingSpec (spec) where

import Logging (logInfo, newLoggerTo)

import Control.Concurrent (getNumCapabilities, setNumCapabilities)
import Control.Concurrent.Async (forConcurrently_)
import Control.Exception (bracket)
import Control.Monad (forM_)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Char8 as BS8
import qualified Data.Maybe as Maybe
import qualified Data.Text as Text
import System.Directory (getTemporaryDirectory, removeFile)
import System.IO (hClose, openTempFile)
import Test.Hspec

spec :: Spec
spec = describe "Logging" do
  -- A line used to be written in pieces, and the lock around it serialised
  -- nothing, so on the multi-core runtime two threads' lines came out joined
  -- as @}{@. It takes two threads writing at the same moment, hence the four
  -- capabilities.
  it "writes every line whole when many threads log at once" do
    written <- withCapabilities 4 do
      tmp <- getTemporaryDirectory
      (path, h) <- openTempFile tmp "jl4-service-log.jsonl"
      logger <- newLoggerTo h False
      forConcurrently_ [1 .. 16 :: Int] \t ->
        forM_ [1 .. 200 :: Int] \i ->
          logInfo logger "concurrent"
            [ ("thread", Aeson.toJSON t)
            , ("i", Aeson.toJSON i)
            , ("pad", Aeson.toJSON (Text.replicate 50 "x"))
            ]
      hClose h
      ls <- BS8.lines <$> BS8.readFile path
      removeFile path
      pure ls
    filter (Maybe.isNothing . (Aeson.decodeStrict :: BS8.ByteString -> Maybe Aeson.Value)) written
      `shouldBe` []
    length written `shouldBe` 16 * 200

-- | Run with this many capabilities, then put the count back.
withCapabilities :: Int -> IO a -> IO a
withCapabilities n act =
  bracket (getNumCapabilities <* setNumCapabilities n) setNumCapabilities (const act)
