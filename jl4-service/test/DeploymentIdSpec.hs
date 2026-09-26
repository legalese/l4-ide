{-# LANGUAGE OverloadedStrings #-}

-- | The deployment-id rules had NO tests at all, which is how a bound nobody
-- had a reason for survived long enough to refuse a healthy deployment.
module DeploymentIdSpec (spec) where

import ControlPlane (deploymentIdError, maxDeploymentIdLength)
import qualified Data.Text as Text
import Test.Hspec

spec :: Spec
spec = describe "deployment id validation" $ do
  describe "length" $ do
    it "accepts an id exactly at the maximum" $
      deploymentIdError (Text.replicate maxDeploymentIdLength "a") `shouldBe` Nothing

    it "refuses an id one character over the maximum, naming the limit" $
      deploymentIdError (Text.replicate (maxDeploymentIdLength + 1) "a")
        `shouldBe` Just ("Deployment ID exceeds maximum length of "
                          <> Text.pack (show maxDeploymentIdLength) <> " characters")

    -- The regression this bound actually caused: the `go` orchestrator names a
    -- deployment `<subject>-<run-id>`, and a run id is `<date>-<sha8>-<seq>`
    -- (23 characters). Subject `regcf` fits in the old 36; `sg-succession` does
    -- not, and a healthy service answered HTTP 400.
    it "accepts the orchestrator's <subject>-<run-id> for a long subject name" $
      deploymentIdError "sg-succession-2026-08-18-951d08d8-001" `shouldBe` Nothing

    it "still accepts the shape a UUID has, which the old bound was sized to" $
      deploymentIdError "550e8400-e29b-41d4-a716-446655440000" `shouldBe` Nothing

  describe "path safety, which is what the other rules are for" $ do
    it "refuses a leading dot, so .well-known and .mcp stay unreachable as ids" $
      deploymentIdError ".mcp" `shouldBe` Just "Deployment ID must not start with a dot"

    it "refuses a traversal sequence" $
      deploymentIdError "a..b" `shouldBe` Just "Deployment ID contains invalid sequence"

    it "refuses a path separator" $
      deploymentIdError "a/b"
        `shouldBe` Just "Deployment ID contains invalid characters (allowed: a-z, A-Z, 0-9, -, _)"

    it "refuses characters outside the allowed set even when short" $
      deploymentIdError "a b"
        `shouldBe` Just "Deployment ID contains invalid characters (allowed: a-z, A-Z, 0-9, -, _)"

  describe "reserved words, which shadow top-level routes" $ do
    it "refuses health" $
      deploymentIdError "health" `shouldBe` Just "Deployment ID is a reserved word"
    it "refuses deployments" $
      deploymentIdError "deployments" `shouldBe` Just "Deployment ID is a reserved word"
    it "refuses openapi.json" $
      deploymentIdError "openapi.json" `shouldBe` Just "Deployment ID is a reserved word"

  describe "ordinary ids" $ do
    it "accepts hyphens and underscores" $
      deploymentIdError "my_rules-v2" `shouldBe` Nothing
    it "accepts digits" $
      deploymentIdError "regcf2026" `shouldBe` Nothing
