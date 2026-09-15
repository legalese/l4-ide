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
--      @#TRACE@ — it IS that directive, appended;
--   4. under an @RAND@\/@ROR@ the pass-over reason is the candidate's own
--      obligation's, not the other side's (which scrutinises the event
--      first and logs a wrong-party first); and the compound's own
--      "still open" step does not promote the act to an advance;
--   5. a tick the machine refused ('confirmTick') is not the next
--      deadline: the number 'deadlineOf' computed and the machine did not
--      bear out is exactly the one §2.4 forbids printing, and the
--      obligation is named as one whose deadline is not known.
module LtsListSpec (spec) where

import Data.Foldable (for_)
import Data.Traversable (for)
import qualified Data.Text as Text

import L4.API.VirtualFS (vfsFromList, checkWithImports)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.EvaluateLazy (resolveEvalConfig)
import L4.EvaluateLazy.Machine (emptyEnvironment)
import L4.Lts.List
import L4.Lts.Marking (LiveNorm (..))
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

-- 4. the guard-rejected act beside a live obligation of the other side
compoundSrc :: Text.Text -> Text.Text
compoundSrc op = Text.unlines $ prologue <>
  [ "DECLARE Delivery IS ONE OF delivery"
  , "GIVETH A DEONTIC Person Action"
  , "both MEANS (PARTY S MUST payment EXACTLY 1 WITHIN 3) " <> op <> " (PARTY B MUST payment EXACTLY 5 PROVIDED FALSE WITHIN 3)"
  , ""
  , "#TRACE both AT 0 WITH"
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

  it "4. under RAND and ROR the pass-over reason is the candidate's own obligation's" $
    for_ ["RAND", "ROR"] \ op -> do
      rig <- rigOf (compoundSrc op)
      tr <- case tracesOf rig.rigModule of
        (t : _) -> pure t
        []      -> fail "no trace"
      es <- enabledSet rig tr >>= maybe (fail "no enabled set") pure
      -- S's own act is the left side's; B's act meets S's obligation first
      -- (PartyMismatch, in the machine's order) and then its own (GuardFailed)
      [ o.ocVerdict | o <- passedOver es ] `shouldBe` [PassedOver GuardFalse]
      [ o.ocVerdict | o <- advancing es ] `shouldSatisfy` all (\ case Advancing _ -> True; _ -> False)
      length (advancing es) `shouldBe` (if op == "RAND" then 1 else 0)   -- under ROR, S's act discharges
      let txt = renderReport False (reportFrom tr es)
      txt `shouldSatisfy` Text.isInfixOf "B does payment OF 5 now (at 0) — its condition (PROVIDED) does not hold"
      txt `shouldNotSatisfy` Text.isInfixOf "it is not this party's to do"

  it "5. a tick the machine refused is not the next deadline, and the obligation is named as unknown" $ do
    rig <- rigOf guardedSrc
    tr <- case tracesOf rig.rigModule of
      (t : _) -> pure t
      []      -> fail "no trace"
    es <- enabledSet rig tr >>= maybe (fail "no enabled set") pure
    -- as computed, the tick is confirmed and dates the obligation
    let asIs = reportFrom tr es
    fmap fst asIs.rpNext `shouldBe` Just 3
    asIs.rpUnknown `shouldBe` []
    renderReport False asIs `shouldSatisfy` Text.isInfixOf "Next deadline: 3 (B: payment OF 5)"
    renderReport False asIs `shouldSatisfy` Text.isInfixOf "B MUST payment OF 5 — due by 3 (3 from now)"
    -- the same tick forced to land ON the deadline (LtsWhatIfSpec case 8):
    -- the machine reveals no expiry, confirmTick refuses it
    forced <- for es.esOutcomes \ o -> case o.ocCandidate.cdKind of
      TickPast d _ -> tryCandidate rig tr es.esPosition o.ocCandidate {cdHypothetical = Right (Tick d)}
      _            -> pure o
    let refused = reportFrom tr es {esOutcomes = forced}
        txt = renderReport False refused
    [ () | o <- forced, Untried _ <- [o.ocVerdict] ] `shouldBe` [()]
    refused.rpNext `shouldBe` Nothing
    map (.lnAction) refused.rpUnknown `shouldBe` ["payment (EXACTLY 5)" :: Text.Text]
    txt `shouldSatisfy` Text.isInfixOf "Next deadline: not known here — B: payment OF 5 has a deadline this list could not work out"
    txt `shouldNotSatisfy` Text.isInfixOf "Next deadline: 3"
    -- and the owed line falls back to "due within", not the refuted number
    txt `shouldSatisfy` Text.isInfixOf "B MUST payment OF 5 — due within 3 from now"
