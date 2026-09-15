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
--      obligation is named as one whose deadline is not known;
--   6. under an @EVERY@ the pass-over reason is the candidate's own
--      member's, found by BEARER: the members share a site, and the step
--      log's rendered bearer name is what the candidate's 'lnBearer' is
--      compared with — and the step log prints record-shaped parties by
--      name;
--   7. the limit of 6, measured on a two-field party: the equality stops
--      at the first field that differs, so a member whose party differs
--      from the actor's in an EARLIER field is logged with no name (and
--      printed elided) on that step and on the 'Waiting' after it — and
--      'confirmAct' still finds the candidate's own step, because the
--      candidate's own comparison matched and a match forces every field.
module LtsListSpec (spec) where

import Data.Foldable (for_)
import Data.Traversable (for)
import qualified Data.Text as Text

import L4.API.VirtualFS (vfsFromList, checkWithImports)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.EvaluateLazy (resolveEvalConfig)
import L4.EvaluateLazy.Machine (emptyEnvironment)
import L4.Lts.List
import L4.EvaluateLazy.DeonticStep (DeonticStep (..), NormKey (..), StepOutcome (..))
import L4.Lts.Marking (Bearer (..), LiveNorm (..))
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

-- 6. a barrier of two record-shaped parties whose PROVIDED holds for one
--    member only, and the same barrier with one event
everySrc :: [Text.Text] -> Text.Text
everySrc = everySrcWith
  [ "    Tenant   HAS name IS A STRING"
  , "alice       MEANS Tenant OF \"Alice\""
  , "bob         MEANS Tenant OF \"Bob\""
  ]

-- 7. the same barrier, but Tenant has TWO fields and the one that differs
--    between the members comes FIRST, so the party equality stops before
--    the second field is forced
everyTwoFieldSrc :: [Text.Text] -> Text.Text
everyTwoFieldSrc = everySrcWith
  [ "    Tenant   HAS name IS A STRING, age IS A NUMBER"
  , "alice       MEANS Tenant OF \"Alice\", 30"
  , "bob         MEANS Tenant OF \"Bob\", 40"
  ]

everySrcWith :: [Text.Text] -> [Text.Text] -> Text.Text
everySrcWith (tenantDecl : members) events = Text.unlines $
  [ "IMPORT prelude"
  , "DECLARE Actor IS ONE OF"
  , "    Landlord HAS name IS A STRING"
  , tenantDecl
  , "DECLARE Action IS ONE OF"
  , "    Sign    HAS signer IS AN Actor"
  , "    Deliver HAS who    IS AN Actor"
  , "theLandlord MEANS Landlord OF \"Ms Ng\""
  ] <> members <>
  [ "tenants     MEANS LIST alice, bob"
  , "GIVETH A DEONTIC Actor Action"
  , "`the tenancy` MEANS"
  , "    EVERY Tenant t IN tenants"
  , "        MUST   Sign (EXACTLY t)"
  , "        PROVIDED t EQUALS bob"
  , "        WITHIN 14"
  , "        ONCE   ALL HAVE"
  , "        HENCE  (PARTY theLandlord MUST Deliver (EXACTLY theLandlord) WITHIN 5)"
  , "        LEST   BREACH"
  , ""
  , "#TRACE `the tenancy` AT 0 WITH"
  ] <> map ("  " <>) events
everySrcWith [] _ = error "everySrcWith: the tenant declaration comes first"

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

  it "6. under an EVERY the pass-over reason is the candidate's own member's, found by bearer; the steps name record-shaped parties" $ do
    rig <- rigOf (everySrc [])
    tr <- case tracesOf rig.rigModule of
      (t : _) -> pure t
      []      -> fail "no trace"
    es <- enabledSet rig tr >>= maybe (fail "no enabled set") pure
    -- Alice's act meets her own obligation (GuardFailed: the PROVIDED names
    -- Bob) and Bob's (PartyMismatch); Bob's act meets his own (Matched)
    -- and Alice's (PartyMismatch). The members share one site; only the
    -- bearer tells the steps apart.
    [ (bearerText n, o.ocVerdict) | o <- passedOver es, ActBy n <- [o.ocCandidate.cdKind] ]
      `shouldBe` [("Tenant OF \"Alice\"", PassedOver GuardFalse)]
    [ bearerText n | o <- advancing es, ActBy n <- [o.ocCandidate.cdKind] ]
      `shouldBe` ["Tenant OF \"Bob\""]
    -- the step that carried the reason is keyed by the candidate's own
    -- bearer, in the rendering 'lnBearer' uses
    for_ (passedOver es) \ o -> case o.ocCandidate.cdKind of
      ActBy n -> do
        let own = [ s | s <- o.ocSteps, Just k <- [s.dsNorm], k.nkBearerName == Just (bearerText n) ]
        -- (the Waiting that follows the pass-over keeps the name: once
        -- the fields have been forced, every later step of the scrutiny
        -- knows them)
        map (.dsOutcome) own `shouldBe` [GuardFailed, Waiting]
        -- and the other member's look at the same event is a different bearer
        [ k.nkBearerName | s <- o.ocSteps, Just k <- [s.dsNorm], s.dsOutcome == PartyMismatch ]
          `shouldBe` [Just "Tenant OF \"Bob\""]
      _ -> expectationFailure "a pass-over that is not an act"
    -- with an event, --steps prints the parties by name on both halves of
    -- the line, and the ledger key's heap address reaches nobody
    rig' <- rigOf (everySrc ["PARTY bob DOES Sign bob AT 1"])
    tr' <- case tracesOf rig'.rigModule of
      (t : _) -> pure t
      []      -> fail "no trace"
    rp <- reportOf rig' tr' >>= maybe (fail "no report") pure
    let steps = renderReport True rp
    -- (Alice's obligation never looked at the act — the party mismatched
    -- first — so the act is "something"; the party it did look at is named)
    steps `shouldSatisfy` Text.isInfixOf "at 1: Tenant OF \"Bob\" does something at 1; Tenant OF \"Alice\" MUST (member 1 of 2) — not this party's event; passed over"
    steps `shouldSatisfy` Text.isInfixOf "at 1: Tenant OF \"Bob\" does Sign OF … at 1; Tenant OF \"Bob\" MUST (member 2 of 2) — done; on to what follows (1 of 2 have acted; the shared next step waits for the rest)"
    steps `shouldNotSatisfy` Text.isInfixOf "Tenant OF …"

  it "7. a two-field party: a member that differs in an earlier field is logged without a name, and confirmAct still finds the candidate's own step" $ do
    rig <- rigOf (everyTwoFieldSrc [])
    tr <- case tracesOf rig.rigModule of
      (t : _) -> pure t
      []      -> fail "no trace"
    es <- enabledSet rig tr >>= maybe (fail "no enabled set") pure
    -- the verdicts are case 6's: the candidate's own obligation matched
    -- the candidate's own act, which forced both fields, so its step is
    -- named and found
    [ (bearerText n, o.ocVerdict) | o <- passedOver es, ActBy n <- [o.ocCandidate.cdKind] ]
      `shouldBe` [("Tenant OF \"Alice\", 30", PassedOver GuardFalse)]
    [ bearerText n | o <- advancing es, ActBy n <- [o.ocCandidate.cdKind] ]
      `shouldBe` ["Tenant OF \"Bob\", 40"]
    for_ (passedOver es) \ o -> case o.ocCandidate.cdKind of
      ActBy n -> do
        let own = [ s | s <- o.ocSteps, Just k <- [s.dsNorm], k.nkBearerName == Just (bearerText n) ]
        map (.dsOutcome) own `shouldBe` [GuardFailed, Waiting]
        -- the OTHER member's look at Alice's act stopped at the first
        -- field ("Bob" /= "Alice"), so its age was never forced and the
        -- step carries no name — the limit case 6's one-field parties
        -- cannot show
        [ k.nkBearerName | s <- o.ocSteps, Just k <- [s.dsNorm], s.dsOutcome == PartyMismatch ]
          `shouldBe` [Nothing]
      _ -> expectationFailure "a pass-over that is not an act"
    -- and --steps prints that member elided, on the pass-over and on the
    -- Waiting after it, while the member that matched is named in full
    rig' <- rigOf (everyTwoFieldSrc ["PARTY alice DOES Sign alice AT 1"])
    tr' <- case tracesOf rig'.rigModule of
      (t : _) -> pure t
      []      -> fail "no trace"
    rp <- reportOf rig' tr' >>= maybe (fail "no report") pure
    let steps = renderReport True rp
    steps `shouldSatisfy` Text.isInfixOf "at 1: Tenant OF \"Alice\", 30 does Sign OF … at 1; Tenant OF \"Alice\", 30 MUST (member 1 of 2) — the act matched but its condition did not hold; passed over"
    steps `shouldSatisfy` Text.isInfixOf "at 1: Tenant OF \"Alice\", 30 does Sign OF … at 1; Tenant OF …, … MUST (member 2 of 2) — not this party's event; passed over"
    steps `shouldSatisfy` Text.isInfixOf "at 1: Tenant OF …, … MUST (member 2 of 2) — no more events; still waiting"
  where
    bearerText :: LiveNorm -> Text.Text
    bearerText n = case n.lnBearer of
      KnownParty t    -> t
      UnforcedParty t -> t
