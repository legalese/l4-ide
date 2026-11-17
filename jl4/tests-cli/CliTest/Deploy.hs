{-# LANGUAGE OverloadedStrings #-}

-- | Black-box tests for what @l4 deploy@ and @l4 redeploy@ print about a
-- changed default (U2 option B of the TYPICALLY wave, bench ruling
-- 2026-11-17: a redeploy that changes a published default is applied and
-- reported, never blocked).
--
-- The service's own behaviour is tested in @jl4-service@. These tests put a
-- stub in its place, answering the calls the command makes in the order it
-- makes them, so that what the command does with the @notices@ of a job is
-- the only thing under test: lines on stdout when the update is applied, lines
-- on stderr beside the error when it is rejected, the same list as JSON under
-- @--json@, and nothing extra when the service sends none (an older service).
module CliTest.Deploy (spec) where

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString.Lazy.Char8 as BSL8
import Data.List (isInfixOf)
import System.Exit (ExitCode (..))
import Test.Hspec

import Network.HTTP.Types (hContentType, status200, status202, status404)
import Network.Wai (Application, pathInfo, requestMethod, responseLBS)
import Network.Wai.Handler.Warp (testWithApplication)

import CliTest.Common

-- | One changed default, as the service writes it.
fee :: Aeson.Value
fee = Aeson.object
  [ "kind" Aeson..= ("default-changed" :: String)
  , "function" Aeson..= ("fee" :: String)
  , "input" Aeson..= ("grace days" :: String)
  , "old" Aeson..= (5 :: Int)
  , "new" Aeson..= (7 :: Int)
  ]

-- | A record field's default, which is a dotted path, and a text value.
colour :: Aeson.Value
colour = Aeson.object
  [ "kind" Aeson..= ("default-changed" :: String)
  , "function" Aeson..= ("pick colour" :: String)
  , "input" Aeson..= ("cfg.shade" :: String)
  , "old" Aeson..= ("Green" :: String)
  , "new" Aeson..= ("Red" :: String)
  ]

-- | A service that has a deployment called @late-fee@ and answers a @PUT@ with
-- one job whose terminal answer is the given object.
stub :: Aeson.Value -> Application
stub job req respond = respond $ case (requestMethod req, pathInfo req) of
  ("GET", ["deployments", "late-fee"]) -> json status200 ready
  ("PUT", ["deployments", "late-fee"]) ->
    json status202 (Aeson.object ["id" Aeson..= ("late-fee" :: String), "status" Aeson..= ("compiling" :: String), "updateId" Aeson..= ("job-1" :: String)])
  ("GET", ["deployments", "late-fee", "updates", "job-1"]) -> json status200 job
  _ -> json status404 (Aeson.object ["error" Aeson..= ("not found" :: String)])
 where
  json st v = responseLBS st [(hContentType, "application/json")] (Aeson.encode v)
  ready = Aeson.object
    [ "id" Aeson..= ("late-fee" :: String)
    , "status" Aeson..= ("ready" :: String)
    , "metadata" Aeson..= Aeson.object
        [ "deploymentVersion" Aeson..= ("1.0.1" :: String)
        , "functions" Aeson..= [Aeson.object ["name" Aeson..= ("fee" :: String)]]
        ]
    ]

applied :: [Aeson.Value] -> Aeson.Value
applied ns = Aeson.object
  [ "updateId" Aeson..= ("job-1" :: String), "deploymentId" Aeson..= ("late-fee" :: String)
  , "status" Aeson..= ("applied" :: String), "notices" Aeson..= ns ]

rejected :: [Aeson.Value] -> Aeson.Value
rejected ns = Aeson.object
  [ "updateId" Aeson..= ("job-1" :: String), "deploymentId" Aeson..= ("late-fee" :: String)
  , "status" Aeson..= ("rejected" :: String), "notices" Aeson..= ns
  , "error" Aeson..= ("Update rejected \8212 it would break existing integrations: fee parameter late days removed" :: String) ]

-- | An older service: the job has no @notices@ at all.
appliedOld :: Aeson.Value
appliedOld = Aeson.object
  [ "updateId" Aeson..= ("job-1" :: String), "deploymentId" Aeson..= ("late-fee" :: String)
  , "status" Aeson..= ("applied" :: String) ]

spec :: FilePath -> Spec
spec bin = describe "l4 redeploy, a changed default (stub service)" $ do
  let redeploy port extra = runL4 bin
        ([ "redeploy", cleanFixture, "--name", "late-fee", "--server", "http://127.0.0.1:" <> show port ] <> extra)
      against job act = testWithApplication (pure (stub job)) act

  it "applies the update and lists each changed default on stdout" $
    against (applied [fee, colour]) $ \port -> do
      Output code sout serr <- redeploy port []
      (code, serr) `shouldBe` (ExitSuccess, serr)
      sout `shouldSatisfy` ("Deployed 'late-fee'" `isInfixOf`)
      sout `shouldSatisfy` ("Changed defaults (reported, not blocking)" `isInfixOf`)
      sout `shouldSatisfy` ("fee, input grace days: 5 -> 7" `isInfixOf`)
      sout `shouldSatisfy` ("pick colour, input cfg.shade: \"Green\" -> \"Red\"" `isInfixOf`)

  it "says one changed default in the singular" $
    against (applied [fee]) $ \port -> do
      Output _ sout _ <- redeploy port []
      sout `shouldSatisfy` ("Changed default (reported, not blocking)" `isInfixOf`)

  it "carries the same list under --json" $
    against (applied [fee]) $ \port -> do
      Output code sout _ <- redeploy port ["--json"]
      code `shouldBe` ExitSuccess
      case Aeson.decode (BSL8.pack sout) of
        Just (Aeson.Object o) -> KeyMap.lookup "notices" o `shouldBe` Just (Aeson.toJSON [fee])
        other -> expectationFailure ("not a JSON object: " <> show other)

  it "prints nothing extra when there is no changed default" $
    against (applied []) $ \port -> do
      Output code sout _ <- redeploy port []
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` ("Deployed 'late-fee'" `isInfixOf`)
      sout `shouldSatisfy` (not . ("Changed default" `isInfixOf`))

  it "reads a job with no notices at all (an older service) as none" $
    against appliedOld $ \port -> do
      Output code sout _ <- redeploy port []
      code `shouldBe` ExitSuccess
      sout `shouldSatisfy` (not . ("Changed default" `isInfixOf`))

  it "lists the changed defaults beside the error when the update is rejected, and still fails" $
    against (rejected [fee]) $ \port -> do
      Output code _ serr <- redeploy port []
      code `shouldNotBe` ExitSuccess
      serr `shouldSatisfy` ("would break existing integrations" `isInfixOf`)
      serr `shouldSatisfy` ("The upload also changes 1 default (reported, not a reason for the rejection)" `isInfixOf`)
      serr `shouldSatisfy` ("fee, input grace days: 5 -> 7" `isInfixOf`)
