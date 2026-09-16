{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | LTS-VISUALISER §2.4 / P2c: the enabled set in the REPLAY form.
--
-- Every verdict below is what the evaluator said when the hypothetical was
-- appended to the trace and the whole thing re-run. Nothing in
-- "L4.Lts.WhatIf" knows that a SHANT's act breaches or that a MAY's
-- expiry discharges; these tests pin that the replay reports it anyway.
--
--   1. MUST: the act discharges, the tick past the deadline breaches;
--   2. SHANT: the act breaches, the tick discharges — the polarity comes
--      from the machine;
--   3. MAY with a HENCE: the act advances to the HENCE, the tick discharges
--      (LEST defaulting to FULFILLED);
--   4. contracts.l4's aContract, one event in: the reparation shape binds
--      `price` and is listed Untried; the tick advances to the LEST;
--   5. a barrier of three: each member's act ADVANCES (the Awaiting counts
--      up) until the last, which discharges when the HENCE is FULFILLED;
--      the tick breaches;
--   6. a fork: each member's act advances its own continuation, and the
--      other members are untouched;
--   7. the partition helpers agree with the verdicts;
--   8. a tick that reveals no expiry is refused, not reported as an
--      advance: the deadline arithmetic is held to the machine's word;
--   9. a window with an opening edge (AFTER): the act "now" is passed over
--      as too early — the machine's word, read from its EarlyAct step —
--      and the tick past opening + WITHIN breaches, both before any event
--      (the WITHIN re-anchored on the opening) and after an early act (the
--      residual's due counted from the opening, not the clock).
module LtsWhatIfSpec (spec) where

import qualified Data.Text as Text

import L4.API.VirtualFS (vfsFromList, checkWithImports)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.EvaluateLazy (resolveEvalConfig)
import L4.EvaluateLazy.DeonticStep (Branch (..), DeonticStep (..), StepOutcome (..))
import L4.EvaluateLazy.Machine (emptyEnvironment)
import L4.Lts.Marking
import L4.Lts.WhatIf
import L4.Syntax (DeonticModal (..))
import L4.TracePolicy (apiDefaultPolicy)

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 0)

-- | A rig over a one-module source, and its traces in order.
rigOf :: Text.Text -> IO (Maybe (Rig, [Trace]))
rigOf src = do
  cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
  case checkWithImports (vfsFromList []) src of
    Left errs -> do
      expectationFailure ("typecheck failed: " <> show errs)
      pure Nothing
    Right r -> do
      let rig = MkRig {rigConfig = cfg, rigEntityInfo = r.tcdEntityInfo, rigEnv = emptyEnvironment, rigModule = r.tcdModule}
      pure (Just (rig, tracesOf r.tcdModule))

-- | The enabled set of the n-th trace.
enabledAt :: Int -> Text.Text -> IO EnabledSet
enabledAt n src = do
  mr <- rigOf src
  case mr of
    Nothing -> fail "no rig"
    Just (rig, traces) -> case drop n traces of
      (tr : _) -> enabledSet rig tr >>= maybe (fail "the position did not evaluate") pure
      []       -> fail ("no trace " <> show n)

-- | One row per outcome: what was tried, and what came of it.
data Row = Row Tried Said
  deriving stock (Eq, Show)

data Tried
  = ActOf Text.Text Text.Text Rational   -- ^ bearer, action, stamp
  | TickAt Rational [Text.Text]          -- ^ stamp, the bearers whose deadline it passes
  | CouldNot Text.Text Text.Text         -- ^ bearer, action: not instantiable
  deriving stock (Eq, Show)

data Said
  = Discharges
  | Breaches (Maybe Text.Text)
  | Advances [Text.Text]                  -- ^ the next marking, as placementText
  | Passed PassOver                       -- ^ nobody took it; why
  | Untriable
  deriving stock (Eq, Show)

row :: Outcome -> Row
row o = Row tried said
  where
    tried = case (o.ocCandidate.cdKind, o.ocCandidate.cdHypothetical) of
      (ActBy n, Right h)      -> ActOf (bearer n) n.lnAction h.hyAt
      (ActBy n, Left _)       -> CouldNot (bearer n) n.lnAction
      (TickPast _ ns, Right h) -> TickAt h.hyAt (map bearer ns)
      (TickPast d ns, Left _)  -> TickAt d (map bearer ns)
      (NoTick n, _)            -> CouldNot (bearer n) "(tick)"
    said = case o.ocVerdict of
      Discharging  -> Discharges
      Breaching b  -> Breaches b.blParty
      Advancing m  -> Advances (map placementText m)
      PassedOver p -> Passed p
      Untried _    -> Untriable
    bearer n = case n.lnBearer of
      KnownParty t    -> t
      UnforcedParty t -> t

prologue :: [Text.Text]
prologue =
  [ "DECLARE Person IS ONE OF Alice, Bob"
  , "DECLARE Action IS ONE OF"
  , "  deliver"
  , "  pay HAS amount IS A NUMBER"
  , ""
  ]

-- 1. MUST
mustSrc :: Text.Text
mustSrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS PARTY Alice MUST deliver WITHIN 10 HENCE PARTY Bob MUST pay 50 WITHIN 5"
  , ""
  , "#TRACE c AT 0 WITH"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Alice DOES deliver AT 3"
  ]

-- 2. SHANT, no LEST: the act is a breach, the expiry is a discharge
shantSrc :: Text.Text
shantSrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS PARTY Alice SHANT deliver WITHIN 10"
  , ""
  , "#TRACE c AT 0 WITH"
  ]

-- 3. MAY with a HENCE and no LEST
maySrc :: Text.Text
maySrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS PARTY Alice MAY deliver WITHIN 10 HENCE PARTY Bob MUST pay 50 WITHIN 5"
  , ""
  , "#TRACE c AT 0 WITH"
  ]

-- 4. jl4/examples/ok/contracts.l4's aContract, verbatim, one event in
aContractSrc :: Text.Text
aContractSrc = Text.unlines
  [ "DECLARE Person IS ONE OF B, S"
  , "DECLARE Action IS ONE OF"
  , "  delivery"
  , "  payment HAS amount IS A NUMBER"
  , "  foo"
  , ""
  , "aContract MEANS"
  , "  PARTY S"
  , "  MUST delivery"
  , "  WITHIN 3"
  , "  HENCE"
  , "    PARTY B"
  , "    MUST payment price PROVIDED price >= 20"
  , "    WITHIN 3"
  , "    HENCE (IF price = 20 THEN FULFILLED ELSE PARTY B MUST return WITHIN 10)"
  , "    LEST"
  , "      PARTY B"
  , "      MUST EXACTLY payment fine"
  , "      WITHIN 3"
  , "  WHERE"
  , "  fine MEANS 10"
  , ""
  , "#TRACE aContract AT 0 WITH"
  , "  PARTY S DOES delivery AT 2"
  ]

-- 9. the window's opening edge: AFTER 5 WITHIN 10 is [5, 15]. Two
--    positions: before any event (the edges unforced, the WITHIN
--    re-anchored on the opening — R-X5 as amended) and after an early act
--    at 2 (the residual then holds the opening as 3-to-go and the due as
--    10-from-the-opening, EVERY-EACH-QUANTIFIER-SPEC §5.1.2).
afterSrc :: Text.Text
afterSrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS PARTY Alice MUST deliver AFTER 5 WITHIN 10"
  , ""
  , "#TRACE c AT 0 WITH"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Alice DOES deliver AT 2"
  ]

everyPrologue :: [Text.Text]
everyPrologue =
  [ "IMPORT prelude"
  , "DECLARE Actor IS ONE OF"
  , "    Landlord HAS name IS A STRING"
  , "    Tenant   HAS name IS A STRING"
  , ""
  , "DECLARE Action IS ONE OF"
  , "    Sign    HAS signer IS AN Actor"
  , "    Deliver HAS who    IS AN Actor"
  , ""
  , "theLandlord MEANS Landlord OF \"Ms Ng\""
  , "alice       MEANS Tenant OF \"Alice\""
  , "bob         MEANS Tenant OF \"Bob\""
  , "carol       MEANS Tenant OF \"Carol\""
  , "tenants     MEANS LIST alice, bob, carol"
  , ""
  ]

-- 5. the barrier, HENCE FULFILLED, LEST BREACH
barrierSrc :: Text.Text
barrierSrc = Text.unlines $ everyPrologue <>
  [ "GIVETH A DEONTIC Actor Action"
  , "`the tenancy` MEANS"
  , "    EVERY Tenant t IN tenants"
  , "        MUST   Sign (EXACTLY t)"
  , "        WITHIN 14"
  , "        ONCE   ALL HAVE"
  , "        HENCE  FULFILLED"
  , "        LEST   BREACH"
  , ""
  , "#TRACE `the tenancy` AT 0 WITH"
  , ""
  , "#TRACE `the tenancy` AT 0 WITH"
  , "  PARTY alice DOES Sign alice AT 1"
  , "  PARTY bob   DOES Sign bob   AT 2"
  ]

-- 6. the fork
forkSrc :: Text.Text
forkSrc = Text.unlines $ everyPrologue <>
  [ "GIVETH A DEONTIC Actor Action"
  , "`receipts` MEANS"
  , "    EVERY Tenant t IN tenants"
  , "        MUST   Sign (EXACTLY t)"
  , "        WITHIN 7"
  , "        UPON   EACH"
  , "        HENCE  (PARTY theLandlord MUST Deliver (EXACTLY t) WITHIN 5)"
  , ""
  , "#TRACE `receipts` AT 0 WITH"
  ]

spec :: Spec
spec = describe "LTS-VISUALISER §2.4 / P2c: the enabled set by replay" $ do

  it "1. MUST at the start: the act discharges into the HENCE, the tick past 10 breaches" $ do
    es <- enabledAt 0 mustSrc
    es.esPosition.posClock `shouldBe` 0
    map row es.esOutcomes `shouldBe`
      [ Row (ActOf "Alice" "deliver" 0) (Advances ["in effect: Bob MUST pay 50 WITHIN 5"])
      , Row (TickAt 11 ["Alice"]) (Breaches (Just "Alice")) ]

  it "1'. MUST one event in: the clock is the last stamp, Bob's act discharges, the tick past 3+5 breaches" $ do
    es <- enabledAt 1 mustSrc
    es.esPosition.posClock `shouldBe` 3
    map row es.esOutcomes `shouldBe`
      [ Row (ActOf "Bob" "pay 50" 3) Discharges
      , Row (TickAt 9 ["Bob"]) (Breaches (Just "Bob")) ]

  it "2. SHANT: the act BREACHES and the tick DISCHARGES — the machine's routing, not this module's" $ do
    es <- enabledAt 0 shantSrc
    map row es.esOutcomes `shouldBe`
      [ Row (ActOf "Alice" "deliver" 0) (Breaches (Just "Alice"))
      , Row (TickAt 11 ["Alice"]) Discharges ]

  it "3. MAY: the act advances into the HENCE, the tick discharges (LEST defaults to FULFILLED)" $ do
    es <- enabledAt 0 maySrc
    map row es.esOutcomes `shouldBe`
      [ Row (ActOf "Alice" "deliver" 0) (Advances ["in effect: Bob MUST pay 50 WITHIN 5"])
      , Row (TickAt 11 ["Alice"]) Discharges ]

  it "4. aContract one event in: `payment price` binds and is listed Untried; the tick advances to the LEST" $ do
    es <- enabledAt 0 aContractSrc
    es.esPosition.posClock `shouldBe` 2
    map row es.esOutcomes `shouldBe`
      [ Row (CouldNot "B" "payment price") Untriable
      -- the source writes EXACTLY, so the deontic printer keeps it, in its own
      -- bracketed form — the same form `l4 run`'s DEONTIC print uses. The
      -- LEST's WITHIN 3 counts from the missed deadline (5), not from the
      -- tick that revealed the miss (6): EVERY-EACH-QUANTIFIER-SPEC §5.2,
      -- 2026-09-16, so one unit has run by the time it is listed. Pinned
      -- from the runtime on 2026-09-17, when that change was rebased over
      -- this module; it read WITHIN 3 before it.
      , Row (TickAt 6 ["B"]) (Advances ["in effect: B MUST (EXACTLY (payment OF fine)) WITHIN 2"]) ]
    -- and the reason names the binder
    case es.esOutcomes of
      (o : _) -> o.ocCandidate.cdHypothetical `shouldBe` Left "the action binds `price`, which the what-if cannot choose"
      []      -> expectationFailure "no outcomes"

  it "5. a barrier of three, nobody acted: each member's act ADVANCES to 1 of 3; the tick breaches" $ do
    es <- enabledAt 0 barrierSrc
    let blocked n = "continuation blocked: " <> n <> " of 3 have acted (ONCE ALL HAVE)"
        member who = "in effect: Tenant OF \"" <> who <> "\" MUST Sign (EXACTLY t) WITHIN 14 (member of a barrier of 3)"
    map row es.esOutcomes `shouldBe`
      [ Row (ActOf "Tenant OF \"Alice\"" "Sign (EXACTLY t)" 0) (Advances [member "Bob", member "Carol", blocked "1"])
      , Row (ActOf "Tenant OF \"Bob\"" "Sign (EXACTLY t)" 0) (Advances [member "Alice", member "Carol", blocked "1"])
      , Row (ActOf "Tenant OF \"Carol\"" "Sign (EXACTLY t)" 0) (Advances [member "Alice", member "Bob", blocked "1"])
      , Row (TickAt 15 ["Tenant OF \"Alice\"", "Tenant OF \"Bob\"", "Tenant OF \"Carol\""]) (Breaches Nothing) ]

  it "5'. a barrier of three, two acted: the last member's act DISCHARGES; the tick breaches" $ do
    es <- enabledAt 1 barrierSrc
    es.esPosition.posClock `shouldBe` 2
    map placementText es.esPosition.posMarking `shouldBe`
      [ "in effect: Tenant OF \"Carol\" MUST Sign (EXACTLY t) WITHIN 12 (member of a barrier of 3)"
      , "continuation blocked: 2 of 3 have acted (ONCE ALL HAVE)" ]
    map row es.esOutcomes `shouldBe`
      [ Row (ActOf "Tenant OF \"Carol\"" "Sign (EXACTLY t)" 2) Discharges
      , Row (TickAt 15 ["Tenant OF \"Carol\""]) (Breaches Nothing) ]

  it "6. a fork: each member's act advances its OWN continuation and leaves the others waiting" $ do
    es <- enabledAt 0 forkSrc
    let waiting who n = "in effect: Tenant OF \"" <> who <> "\" MUST Sign (EXACTLY t) WITHIN " <> n <> " (member of a fork of 3)"
        delivery = "in effect: theLandlord MUST Deliver (EXACTLY t) WITHIN 5"
    map row es.esOutcomes `shouldBe`
      [ Row (ActOf "Tenant OF \"Alice\"" "Sign (EXACTLY t)" 0) (Advances [delivery, waiting "Bob" "7", waiting "Carol" "7"])
      , Row (ActOf "Tenant OF \"Bob\"" "Sign (EXACTLY t)" 0) (Advances [waiting "Alice" "7", delivery, waiting "Carol" "7"])
      , Row (ActOf "Tenant OF \"Carol\"" "Sign (EXACTLY t)" 0) (Advances [waiting "Alice" "7", waiting "Bob" "7", delivery])
      , Row (TickAt 8 ["Tenant OF \"Alice\"", "Tenant OF \"Bob\"", "Tenant OF \"Carol\""]) (Breaches (Just "Tenant OF \"Alice\"")) ]

  it "7. the partition helpers agree with the verdicts" $ do
    es <- enabledAt 0 barrierSrc
    length (discharging es) `shouldBe` 0
    length (breaching es) `shouldBe` 1
    length (advancing es) `shouldBe` 3
    length (untried es) `shouldBe` 0
    es' <- enabledAt 1 barrierSrc
    length (discharging es') `shouldBe` 1
    length (breaching es') `shouldBe` 1

  it "the steps an outcome carries are the hypothetical's own, past the position's" $ do
    es <- enabledAt 1 mustSrc
    case es.esOutcomes of
      (o : _) -> do
        length es.esPosition.posSteps `shouldBe` 2   -- Alice matched, Bob waiting
        map (.dsOutcome) o.ocSteps `shouldBe` [Matched ToHence]
      [] -> expectationFailure "no outcomes"

  it "8. a tick landing ON the deadline (what an anchor one unit low would produce) is Untried, naming deadlineOf; one past it breaches" $ do
    mr <- rigOf mustSrc
    (rig, tr) <- case mr of
      Just (rig, tr : _) -> pure (rig, tr)
      _ -> fail "no rig"
    pos <- position rig tr >>= maybe (fail "no position") pure
    cands <- candidatesOf pos
    tick <- case [ c | c@MkCandidate {cdKind = TickPast 10 _} <- cands ] of
      (c : _) -> pure c
      []      -> fail "no tick candidate at 10"
    -- as computed: one past the deadline, and the machine expires it
    good <- tryCandidate rig tr pos tick
    row good `shouldBe` Row (TickAt 11 ["Alice"]) (Breaches (Just "Alice"))
    -- forced one unit short: the machine treats a stamp AT the deadline as
    -- timely, so nothing expires, and the guard says so instead of Advancing
    bad <- tryCandidate rig tr pos tick {cdHypothetical = Right (Tick 10)}
    case bad.ocVerdict of
      Untried why -> why `shouldBe` "the tick to 10 past the deadline computed as 10 revealed no expiry: deadlineOf's arithmetic did not agree with the machine"
      other -> expectationFailure ("expected Untried, got " <> show other)
    -- and without the guard it would have read as a plain advance
    (raw, _) <- whatIf rig tr pos (Tick 10)
    case raw of
      Advancing m -> map placementText m `shouldBe` ["in effect: Alice MUST deliver WITHIN 0"]
      other -> expectationFailure ("expected Advancing, got " <> show other)

  it "9. AFTER: the act now is passed over as too early, and the tick past opening + WITHIN breaches — before any event and after an early act" $ do
    -- Pinned from the runtime on 2026-09-17 (adversarial round 1 of the
    -- wave's third rebase, F1/S1/S2). Before it: the act read as taken by
    -- nobody (NoTaker — the early act logged no step), and the tick was
    -- computed at clock + 10 (10, then 12), landed short of the real
    -- deadline 15, revealed no expiry and was reported Untried.
    es <- enabledAt 0 afterSrc
    es.esPosition.posClock `shouldBe` 0
    map placementText es.esPosition.posMarking `shouldBe` ["in effect: Alice MUST deliver AFTER 5 WITHIN 10"]
    map row es.esOutcomes `shouldBe`
      [ Row (ActOf "Alice" "deliver" 0) (Passed (TooEarly 5))
      , Row (TickAt 16 ["Alice"]) (Breaches (Just "Alice")) ]
    es' <- enabledAt 1 afterSrc
    es'.esPosition.posClock `shouldBe` 2
    -- the residual: 3 to the opening, 10 from the opening to the close
    map placementText es'.esPosition.posMarking `shouldBe` ["in effect: Alice MUST deliver AFTER 3 WITHIN 10"]
    map row es'.esOutcomes `shouldBe`
      [ Row (ActOf "Alice" "deliver" 2) (Passed (TooEarly 5))
      , Row (TickAt 16 ["Alice"]) (Breaches (Just "Alice")) ]

  it "tickPast lands one unit past a lone deadline, and half-way to a nearer next one" $ do
    tickPast [10] 10 `shouldBe` 11
    tickPast [10, 20] 10 `shouldBe` 11
    tickPast [10, 10.5] 10 `shouldBe` 10.25
    tickPast [10, 11] 11 `shouldBe` 12

  it "the modal is read from the residual, not decided here" $ do
    es <- enabledAt 0 shantSrc
    [ n.lnModal | InEffect n <- es.esPosition.posMarking ] `shouldBe` [DMustNot]
