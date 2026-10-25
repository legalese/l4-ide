-- | The list of modules a module reaches through IMPORT holds each module once,
-- in the order the walk over the old list first met it (smucclaw/l4-ide#1008).
--
-- The CLI and the service read it to find every type and every rule an
-- importer can see, and a left-biased union over it keeps the first entry for a
-- name two modules declare, so the order is part of the answer.
module ImportClosureSpec (spec) where

import Data.List (nub)
import qualified Data.Text as T
import System.FilePath (takeBaseName)

import Language.LSP.Protocol.Types (NormalizedUri, Uri (..), fromNormalizedUri)

import L4.Syntax (Module (..))
import LSP.L4.Rules (TypeCheckResult (..), transitiveDependencies)

import ImportOnceSpec (Mode (..), diamond, fun, runTree, tour)

import Test.Hspec

moduleName :: TypeCheckResult -> String
moduleName tc = case tc.module' of
  MkModule _ u _ -> baseName u

baseName :: NormalizedUri -> String
baseName = takeBaseName . T.unpack . (.getUri) . fromNormalizedUri

spec :: Spec
spec = describe "the modules an importer reaches through IMPORT" $ do
  it "are listed with the direct imports first, then the rest" $ do
    -- top imports left and right; both import bottom.
    (_, mTc) <- runTree "deps-diamond" Check (diamond (fun "base" "x")) "top"
    fmap (map moduleName . (.dependencies)) mTc `shouldBe` Just ["left", "right", "bottom"]

  it "are walked depth first, each once" $ do
    (_, mTc) <- runTree "deps-diamond-walk" Check (diamond (fun "base" "x")) "top"
    fmap (map moduleName . transitiveDependencies) mTc `shouldBe` Just ["left", "bottom", "right"]

  it "are walked once each when 2^4 paths lead to the first" $ do
    -- m6 imports the prelude and m1 .. m5; each of those imports the ones before it.
    (_, mTc) <- runTree "deps-tour-walk" Check (tour 6 (fun "ok" "1")) "m6"
    case fmap (map moduleName . transitiveDependencies) mTc of
      Nothing -> expectationFailure "m6 did not type-check"
      Just names -> do
        names `shouldBe` nub names
        filter (`elem` ["m1", "m2", "m3", "m4", "m5"]) names `shouldBe` ["m1", "m2", "m3", "m4", "m5"]
