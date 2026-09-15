{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | LTS-VISUALISER §1.1a / P2a′: the list baseline's own decisions, the
-- ones the corpus goldens in @jl4/tests/LtsList.hs@ do not exercise.
--
--   1. an act the @PROVIDED@ guard rejects is listed as passed over, not
--      as moving things along — the candidate set is read off the residual
--      before the guard is asked (G9), and the replay corrects it;
--   2. 'freshTrace' refuses a name the module does not define at the top
--      level with no inputs, loudly, and finds one it does;
--   3. a fresh position lists the same things as an authored empty
--      @#TRACE@ — it IS that directive, appended.
module LtsListSpec (spec) where

import qualified Data.Text as Text

import L4.API.VirtualFS (vfsFromList, checkWithImports)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.EvaluateLazy (resolveEvalConfig)
import L4.EvaluateLazy.Machine (emptyEnvironment)
import L4.Lts.List
import L4.Lts.WhatIf
import L4.TracePolicy (apiDefaultPolicy)

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 0)

rigOf :: Text.Text -> IO Rig
rigOf src = do
  cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
  case checkWithImports (vfsFromList []) src of
    Left errs -> fail ("typecheck failed: " <> show errs)
    Right r -> pure MkRig {rigConfig = cfg, rigEntityInfo = r.tcdEntityInfo, rigEnv = emptyEnvironment, rigModule = r.tcdModule}

prologue :: [Text.Text]
prologue =
  [ "DECLARE Person IS ONE OF B, S"
  , "DECLARE Action IS ONE OF"
  , "  payment HAS amount IS A NUMBER"
  , ""
  ]

-- 1. a guard that always fails: the act's own shape is listed, tried, and
-- passed over
guardedSrc :: Text.Text
guardedSrc = Text.unlines $ prologue <>
  [ "g MEANS PARTY B MUST payment EXACTLY 5 PROVIDED FALSE WITHIN 3"
  , ""
  , "#TRACE g AT 0 WITH"
  ]

-- 2./3. a rule with no trace, and one with inputs
untracedSrc :: Text.Text
untracedSrc = Text.unlines $ prologue <>
  [ "GIVETH A DEONTIC Person Action"
  , "`the sale` MEANS PARTY B MUST payment EXACTLY 5 WITHIN 3"
  , ""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A DEONTIC Person Action"
  , "priced MEANS PARTY B MUST payment EXACTLY n WITHIN 3"
  , ""
  , "#TRACE `the sale` AT 0 WITH"
  ]

spec :: Spec
spec = describe "LTS-VISUALISER §1.1a / P2a′: the list" $ do

  it "1. an act the PROVIDED rejects is passed over, not an advance" $ do
    rig <- rigOf guardedSrc
    tr <- case tracesOf rig.rigModule of
      (t : _) -> pure t
      []      -> fail "no trace"
    rp <- reportOf rig tr >>= maybe (fail "no report") pure
    let txt = renderReport False rp
    txt `shouldSatisfy` Text.isInfixOf "What the contract would pass over (nothing changes):"
    txt `shouldSatisfy` Text.isInfixOf "B does payment OF 5 now (at 0) — its condition (PROVIDED) does not hold"
    txt `shouldNotSatisfy` Text.isInfixOf "What would move things along"
    -- the tick still breaches: the guard does not save B from the deadline
    txt `shouldSatisfy` Text.isInfixOf "nothing happens by 3 (the clock reaches 4) → B is in breach"

  it "2. freshTrace refuses an unknown name and a rule with inputs, and finds a nullary one" $ do
    rig <- rigOf untracedSrc
    case freshTrace rig.rigModule "nope" of
      Left why -> why `shouldBe` "no top-level rule named `nope` that takes no inputs"
      Right _  -> expectationFailure "found a rule that does not exist"
    case freshTrace rig.rigModule "priced" of
      Left why -> why `shouldBe` "no top-level rule named `priced` that takes no inputs"
      Right _  -> expectationFailure "a rule with inputs cannot be traced without them"
    case freshTrace rig.rigModule "the sale" of
      Left why -> expectationFailure (Text.unpack why)
      Right (_, tr) -> tr.trEvents `shouldBe` []

  it "3. a fresh position reads exactly as the authored empty #TRACE does" $ do
    rig <- rigOf untracedSrc
    authored <- case tracesOf rig.rigModule of
      (t : _) -> reportOf rig t >>= maybe (fail "no report") pure
      []      -> fail "no trace"
    (m', tr) <- either (fail . Text.unpack) pure (freshTrace rig.rigModule "the sale")
    fresh <- reportOf rig {rigModule = m'} tr >>= maybe (fail "no report") pure
    -- the same list, less the line the authored directive has
    renderReport True fresh `shouldBe` Text.replace " (the #TRACE on line 12)" "" (renderReport True authored)
    fresh.rpLine `shouldBe` Nothing
    authored.rpLine `shouldBe` Just 12
