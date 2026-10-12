{-# LANGUAGE OverloadedStrings #-}

-- | Where a deployed bundle's @IMPORT@s may find their modules.
--
-- A bundle is closed: it gets its own files, then the standard library built
-- into the service binary, and nothing from the machine the service happens to
-- run on. These tests hold the host hostile on purpose. CI exports
-- @JL4_LIBRARY_PATH@ for the whole run, which switches the embedded tier off
-- for every other test, so none of them can see this: the cases here set the
-- environment and the working directory themselves.
--
-- They answer through the HTTP API, not just through 'compileBundle', because
-- a bundle whose @IMPORT prelude@ reached a stray file still compiles and
-- deploys ("applied"); the failure arrives at the first call, as a 422
-- @sum is not in scope@.
--
-- hspec runs the items sequentially, so changing the environment and the
-- working directory around each case does not race.
module StdlibResolutionSpec (spec) where

import Test.Hspec

import Backend.Api (FnLiteral (..), ResponseWithReason (..))
import Compiler (compileBundle)
import IntegrationSpec (assertSuccess, evalFunction, withServiceFromSources)
import Logging (newLoggerTo)

import Control.Exception (bracket)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Char8 as BS8
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text.Encoding
import qualified L4.API.EmbeddedLibraries as EmbeddedLibraries
import System.Directory
  ( createDirectoryIfMissing
  , getTemporaryDirectory
  , removePathForcibly
  , withCurrentDirectory
  )
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.FilePath ((</>))
import System.IO (hClose, openTempFile)

-- | A rule that is only in scope if @IMPORT prelude@ reached the real prelude.
usesSum :: Text
usesSum = Text.unlines
  [ "IMPORT prelude"
  , ""
  , "@export Sum of a list"
  , "GIVEN xs IS A LIST OF NUMBER"
  , "GIVETH A NUMBER"
  , "DECIDE total_of xs IS sum xs"
  ]

-- | What a stray file on the host says. It defines nothing the rule above uses,
-- so if it is the prelude the rule fails with @sum@ out of scope.
strayPrelude :: String
strayPrelude = "-- a stray file on the service host\n`hijacked` MEANS TRUE\n"

data Host = Host
  { root   :: FilePath  -- ^ everything this host is made of; removed afterwards
  , cwd    :: FilePath  -- ^ the service's working directory, holding a stray @prelude.l4@
  , envLib :: FilePath  -- ^ a library directory an operator might export, holding another
  }

-- | Run as a host with a stray @prelude.l4@ in its working directory and in a
-- library directory, from that working directory, with @JL4_LIBRARY_PATH@ set
-- to the given directory (or dropped). Everything is put back afterwards.
withHost :: (Host -> Maybe FilePath) -> (Host -> IO a) -> IO a
withHost libraryPath act = bracket acquire release body
  where
    acquire = do
      saved <- lookupEnv "JL4_LIBRARY_PATH"
      tmp <- getTemporaryDirectory
      let base = tmp </> "jl4-service-stdlib-resolution-spec"
          host = Host { root = base, cwd = base </> "cwd", envLib = base </> "envlib" }
      removePathForcibly base
      mapM_ (createDirectoryIfMissing True) [host.cwd, host.envLib]
      mapM_ (\d -> writeFile (d </> "prelude.l4") strayPrelude) [host.cwd, host.envLib]
      pure (saved, host)
    release (saved, host) = do
      maybe (unsetEnv "JL4_LIBRARY_PATH") (setEnv "JL4_LIBRARY_PATH") saved
      removePathForcibly host.root
    body (_, host) = do
      maybe (unsetEnv "JL4_LIBRARY_PATH") (setEnv "JL4_LIBRARY_PATH") (libraryPath host)
      withCurrentDirectory host.cwd (act host)

sumOf123 :: Aeson.Value
sumOf123 = Aeson.object ["arguments" Aeson..= Aeson.object ["xs" Aeson..= [1, 2, 3 :: Int]]]

-- | Compile a bundle and also return the service log it produced, one JSON
-- object per line.
compileLogged :: Map.Map FilePath Text -> IO (Either Text (), [BS8.ByteString])
compileLogged sources = do
  tmp <- getTemporaryDirectory
  (path, h) <- openTempFile tmp "jl4-service-stdlib-resolution.jsonl"
  logger <- newLoggerTo h False
  result <- compileBundle logger "spec" sources
  hClose h
  logLines <- BS8.lines <$> BS8.readFile path
  removePathForcibly path
  pure (() <$ result, logLines)

mentions :: Text -> [BS8.ByteString] -> [BS8.ByteString]
mentions needle = filter (BS8.isInfixOf (Text.Encoding.encodeUtf8 needle))

spec :: Spec
spec = describe "a bundle's IMPORTs resolve against the bundle and the built-in stdlib only" do
  describe "with JL4_LIBRARY_PATH unset and a stray prelude.l4 in the working directory" do
    it "serves the stdlib built into the binary" do
      withHost (const Nothing) \_ ->
        withServiceFromSources "stdlib-cwd" [("main.l4", usesSum)] \baseUrl mgr -> do
          resp <- evalFunction baseUrl mgr "stdlib-cwd" "total_of" sumOf123
          assertSuccess resp \r ->
            Map.lookup "value" r.fnResult `shouldBe` Just (FnLitInt 6)

  describe "with JL4_LIBRARY_PATH naming a directory that holds a stray prelude.l4" do
    it "serves the stdlib built into the binary" do
      withHost (Just . (.envLib)) \_ ->
        withServiceFromSources "stdlib-env" [("main.l4", usesSum)] \baseUrl mgr -> do
          resp <- evalFunction baseUrl mgr "stdlib-env" "total_of" sumOf123
          assertSuccess resp \r ->
            Map.lookup "value" r.fnResult `shouldBe` Just (FnLitInt 6)

  describe "when the bundle ships a prelude.l4 of its own" do
    -- The bundle's `sum` answers a STRING, and the rule below declares a
    -- STRING. It compiles and answers only if the bundle's file, and not the
    -- stdlib's NUMBER-valued `sum`, is what `IMPORT prelude` reached.
    let bundlePrelude = Text.unlines
          [ "GIVEN xs IS A LIST OF NUMBER"
          , "GIVETH A STRING"
          , "sum xs MEANS \"the bundle's own sum\""
          ]
        usesBundleSum = Text.unlines
          [ "IMPORT prelude"
          , ""
          , "@export Which sum"
          , "GIVEN xs IS A LIST OF NUMBER"
          , "GIVETH A STRING"
          , "DECIDE which_sum xs IS sum xs"
          ]
        bundle = Map.fromList [("main.l4", usesBundleSum), ("prelude.l4", bundlePrelude)]

    it "uses the bundle's file, whatever the host holds (positive control: passes on the unfixed tree too)" do
      withHost (Just . (.envLib)) \_ ->
        withServiceFromSources "stdlib-bundle" (Map.toList bundle) \baseUrl mgr -> do
          resp <- evalFunction baseUrl mgr "stdlib-bundle" "which_sum" sumOf123
          assertSuccess resp \r ->
            Map.lookup "value" r.fnResult `shouldBe` Just (FnLitString "the bundle's own sum")

    it "says at WARN that the bundle's file stands in for a stdlib module" do
      (result, logLines) <- withHost (const Nothing) \_ -> compileLogged bundle
      result `shouldBe` Right ()
      case mentions "standard library" logLines of
        [warned] -> do
          warned `shouldSatisfy` BS8.isInfixOf "\"level\":\"warn\""
          warned `shouldSatisfy` BS8.isInfixOf "\"module\":\"prelude\""
          warned `shouldSatisfy` BS8.isInfixOf "\"deploymentId\":\"spec\""
        other -> expectationFailure ("expected exactly one log line about a stdlib stand-in, got " <> show (length other))

    it "stays quiet about a copy that is byte-for-byte the stdlib's (positive control)" do
      case EmbeddedLibraries.lookupEmbeddedLibrary "prelude" of
        Nothing -> expectationFailure "the embedded stdlib has no prelude"
        Just stdlibPrelude -> do
          let copy = Map.fromList [("main.l4", usesSum), ("prelude.l4", stdlibPrelude)]
          (result, logLines) <- withHost (const Nothing) \_ -> compileLogged copy
          result `shouldBe` Right ()
          mentions "standard library" logLines `shouldBe` []
