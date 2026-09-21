{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}

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
--      residual's due counted from the opening, not the clock);
--  11. a pattern that BINDS describes a SET of acts, and the what-if
--      answers for the set by replaying one act drawn from it: a binder
--      that IS the whole action (any act by the bearer), one in an
--      argument with no guard (any value), and one a PROVIDED guard names
--      (any value the guard accepts). A witness the contract passes over,
--      and a set no witness could be built for, stay refused — and say so
--      in their own words, not in the unforced-local one.
--  10. an action that NAMES a local the residual holds unforced — a member's
--      pattern-bound `amount` read through a fork's HENCE; a rule GIVEN no
--      event has compared yet — is refused before any replay, with the
--      what-if's own wording, never the evaluator's "not in scope"; and one
--      the residual HAS forced (a GIVEN under a projection) is read through
--      and tried. A WHERE local under a section is refused the same way and
--      named as the rule wrote it, not section-qualified.
module LtsWhatIfSpec (spec) where

import Data.Foldable (for_)
import qualified Data.Text as Text

import L4.API.VirtualFS (vfsFromList, checkWithImports)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.Evaluate.ValueLazy (NF (..))
import L4.EvaluateLazy (EvalDirectiveResult (..), EvalDirectiveValue (..), ReductionOutcome (..), resolveEvalConfig)
import L4.EvaluateLazy.DeonticStep (Branch (..), DeonticStep (..), StepOutcome (..))
import L4.EvaluateLazy.Machine (emptyEnvironment, pattern ValFulfilled)
import L4.Lts.Marking
import L4.Lts.WhatIf
import L4.Print (prettyLayout)
import L4.Syntax (DeonticModal (..), getOriginal)
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

-- 11. the whole action is the binder: jl4/examples/ok/contracts.l4's
--     aContract at the file's own first #TRACE, where `return` names
--     nothing the file declares, so the pattern binds it and B doing
--     ANYTHING discharges the contract. No constructor wraps the binder, so
--     there is no declared type to read a value from; the witness is an act
--     the #TRACE itself writes ('authoredAct').
aReturnSrc :: Text.Text
aReturnSrc = Text.unlines
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
  , "  PARTY B DOES payment 21 AT 4"
  , "  (`WAIT UNTIL` 10)"
  ]

-- 11'. the same shape with nothing authored to draw a witness from: the set
--      is still named, and the refusal says plainly that nothing was tried.
aReturnFreshSrc :: Text.Text
aReturnFreshSrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS PARTY Alice MUST whatever WITHIN 10"
  , ""
  , "#TRACE c AT 0 WITH"
  ]

-- 12. an argument binder with no guard: `amount` is one of `pay`'s declared
--     fields, so its type is the type checker's own and the simplest value
--     of it is 0 — which the contract takes, because the rule binds the
--     amount and does not test it.
payAnySrc :: Text.Text
payAnySrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS PARTY Alice MUST pay amount WITHIN 10"
  , ""
  , "#TRACE c AT 0 WITH"
  ]

-- 12'. the same, with a guard the witness does NOT satisfy. The witness is
--      the guard's own other side (20), and 20 is not MORE than 20, so the
--      contract passes it over — which confirms nothing about the set, and
--      is reported as untried rather than as the contract's answer for
--      every amount.
payOverSrc :: Text.Text
payOverSrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS PARTY Alice MUST pay amount PROVIDED amount GREATER THAN 20 WITHIN 10"
  , ""
  , "#TRACE c AT 0 WITH"
  ]

-- 12''. the same shape under a PROHIBITION. Doing an act the condition
--       accepts is what BREACHES a SHANT, so the refusal's last clause
--       cannot be the MUST's ("what would discharge it"); it is the
--       obligation's own question, which the modal decides ('outcomeWord').
shantOverSrc :: Text.Text
shantOverSrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS PARTY Alice SHANT pay amount PROVIDED amount GREATER THAN 20 WITHIN 10"
  , ""
  , "#TRACE c AT 0 WITH"
  ]

-- 12'''. a guard whose comparison is an APPLICATION rather than an
--        operator, and whose two argument places are DIFFERENT types. The
--        operand beside the binder is a STRING; `amount` is a NUMBER. The
--        guard route must not hand that back ('fitsType'), because the
--        replay does not type-check a hypothetical: an unchecked witness
--        surfaces either as the evaluator's internal error in the reader's
--        list or, silently, as the contract's answer for a value the
--        contract could never have been given. The fallback (0) is a
--        NUMBER, `sized OF 0, "big"` is true, and the act discharges.
payMistypedSrc :: Text.Text
payMistypedSrc = Text.unlines $ prologue <>
  [ "GIVEN n IS A NUMBER"
  , "      s IS A STRING"
  , "GIVETH A BOOLEAN"
  , "sized MEANS s EQUALS \"big\""
  , ""
  , "GIVETH DEONTIC Person Action"
  , "c MEANS PARTY Alice MUST pay amount PROVIDED sized OF amount, \"big\" WITHIN 10"
  , ""
  , "#TRACE c AT 0 WITH"
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

-- 10. jl4/examples/ok/every/run-fork.l4's `receipts`, verbatim, at its
--     second trace: Alice paid at 1 and was not receipted; Bob paid at 3 and
--     was receipted at 4. Alice's receipt is still owed. Its `amount` is the
--     one her Pay bound — closed over by the HENCE, never compared (Bob's
--     receipt stopped at `t`), so unforced in the residual — and the replay
--     evaluates a hypothetical in the module's scope, where no `amount`
--     exists. Until 2026-09-19 that surfaced as "Internal error: amount is
--     not in scope" under "What could not be tried" (every-each round 2,
--     O2; the reader proxy's one actionable finding).
runForkSrc :: Text.Text
runForkSrc = Text.unlines
  [ "IMPORT prelude"
  , "DECLARE Actor IS ONE OF"
  , "    Landlord HAS name IS A STRING"
  , "    Tenant   HAS name IS A STRING"
  , "DECLARE Action IS ONE OF"
  , "    Pay     HAS payer  IS AN Actor, payee IS AN Actor, amount IS A NUMBER"
  , "    Receipt HAS issuer IS AN Actor, to    IS AN Actor, amount IS A NUMBER"
  , "theLandlord MEANS Landlord OF \"Ms Ng\""
  , "alice       MEANS Tenant OF \"Alice\""
  , "bob         MEANS Tenant OF \"Bob\""
  , "everyone MEANS LIST alice, bob, theLandlord"
  , "GIVETH A DEONTIC Actor Action"
  , "`receipts` MEANS"
  , "    EVERY Tenant t IN everyone"
  , "        MUST   Pay t theLandlord amount"
  , "        WITHIN 7"
  , "        UPON   EACH"
  , "        HENCE  (PARTY theLandlord"
  , "                    MUST   Receipt theLandlord t amount"
  , "                    WITHIN 5)"
  , "        LEST   BREACH BY t"
  , ""
  , "#TRACE `receipts` AT 0 WITH"
  , "  PARTY alice DOES Pay alice theLandlord 100 AT 1"
  , "  PARTY bob   DOES Pay bob   theLandlord 200 AT 3"
  , "  PARTY theLandlord DOES Receipt theLandlord bob 200 AT 4"
  ]

-- 10'. jl4/examples/ok/regulative-reference-expressions.l4's cases (1) and
--      (2), verbatim. A rule GIVEN is a local the obligation closed over,
--      like a pattern's binding; whether the what-if can read it is whether
--      the residual has forced it. `price` at the outset: no event has
--      compared `price PLUS 50`, so it is unforced and the act is refused.
--      `p` one mismatched event in: the comparison forced `p's landlord`,
--      so `p` is read through as `Person OF Tenant, Landlord` — under the
--      projection, which the first cut of `reifyExpr` did not look under —
--      and the act is tried and discharges.
givenSrc :: Text.Text
givenSrc = Text.unlines
  [ "DECLARE Thing IS ONE OF Widget, Gadget"
  , "DECLARE Actor IS ONE OF Landlord, Tenant"
  , "DECLARE Person HAS who IS AN Actor"
  , "                   landlord IS AN Actor"
  , "DECLARE Action IS ONE OF"
  , "    pay HAS `how much` IS A NUMBER"
  , "    Deliver HAS sender IS AN Actor"
  , "                recipient IS AN Actor"
  , "                what IS A Thing"
  , ""
  , "GIVEN price IS A NUMBER"
  , "GIVETH A DEONTIC Actor Action"
  , "`arithmetic operand` MEANS"
  , "    PARTY Tenant MUST pay (price PLUS 50) WITHIN 10 HENCE FULFILLED LEST BREACH"
  , ""
  , "GIVEN p IS A Person"
  , "      what IS A Thing"
  , "GIVETH A DEONTIC Actor Action"
  , "`projection operand` MEANS"
  , "    PARTY Tenant MUST Deliver Tenant (p's landlord) what WITHIN 10 HENCE FULFILLED LEST BREACH"
  , ""
  , "#TRACE `arithmetic operand` 100 AT 0 WITH"
  , ""
  , "#TRACE `projection operand` (Person Tenant Landlord) Widget AT 0 WITH"
  , "    PARTY Tenant DOES Deliver Tenant Tenant Widget AT 1"
  ]

-- 10''. A WHERE local under a section. `y` is fixed by the rule, not by
--       the event, but the residual holds it unforced at the outset, so the
--       what-if cannot supply it either and refuses as it does a GIVEN. The
--       resolver spells a local declared under `§ inner` as `inner.y`; the
--       refusal must spell it as the action beside it does.
whereSrc :: Text.Text
whereSrc = Text.unlines
  [ "DECLARE Actor IS ONE OF Alice, Bob"
  , "DECLARE Action IS ONE OF pay HAS amt IS A NUMBER"
  , ""
  , "§ inner"
  , ""
  , "GIVETH A DEONTIC Actor Action"
  , "c1 MEANS"
  , "  PARTY Alice"
  , "  MUST pay (y PLUS 1)"
  , "  WITHIN 10"
  , "  WHERE y MEANS 41"
  , ""
  , "#TRACE c1 AT 0 WITH"
  , ""
  , "#TRACE c1 AT 0 WITH"
  , "  PARTY Alice DOES pay OF 42 AT 1"
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

  it "4/13. aContract one event in: `payment price PROVIDED price >= 20` is tried with the guard's own threshold and DISCHARGES; the tick advances to the LEST" $ do
    -- Until 2026-09-21 the first row was `CouldNot "B" "payment price"`,
    -- Untriable, "the action binds `price`, which the what-if cannot
    -- choose" — the tier-3 half of LTS-VISUALISER §7.7 point 2. The
    -- witness is the guard's other side, 20; the HENCE is
    -- `IF price = 20 THEN FULFILLED`, so it discharges.
    es <- enabledAt 0 aContractSrc
    es.esPosition.posClock `shouldBe` 2
    map row es.esOutcomes `shouldBe`
      [ Row (ActOf "B" "payment price" 2) Discharges
      -- the source writes EXACTLY, so the deontic printer keeps it, in its own
      -- bracketed form — the same form `l4 run`'s DEONTIC print uses. The
      -- LEST's WITHIN 3 counts from the missed deadline (5), not from the
      -- tick that revealed the miss (6): EVERY-EACH-QUANTIFIER-SPEC §5.2,
      -- 2026-09-16, so one unit has run by the time it is listed. Pinned
      -- from the runtime on 2026-09-17, when that change was rebased over
      -- this module; it read WITHIN 3 before it.
      , Row (TickAt 6 ["B"]) (Advances ["in effect: B MUST (EXACTLY (payment OF fine)) WITHIN 2"]) ]
    case es.esOutcomes of
      (o : _) -> case o.ocCandidate.cdBound of
        Just b -> do
          b.baScope `shouldBe` BoundArgument
          map (prettyLayout . getOriginal) b.baBinders `shouldBe` ["price"]
          -- the guard is printed as the rule wrote it, and it is what
          -- narrows the set
          b.baGuard `shouldBe` Just "price AT LEAST 20"
          -- the witness is the guard's own other side, not a value invented here
          fmap (map (prettyLayout . snd)) b.baWitness `shouldBe` Right ["20"]
          -- and the act that was replayed carries it
          fmap (prettyLayout . (.hyAction)) o.ocCandidate.cdHypothetical `shouldBe` Right "payment OF 20"
        Nothing -> expectationFailure "expected a bound act"
      []      -> expectationFailure "no outcomes"

  it "11. the whole action is the binder: B does ANYTHING and the contract is fulfilled, checked on an act the #TRACE itself writes" $ do
    es <- enabledAt 0 aReturnSrc
    es.esPosition.posClock `shouldBe` 10
    map row es.esOutcomes `shouldBe`
      [ Row (ActOf "B" "return" 10) Discharges
      , Row (TickAt 15 ["B"]) (Breaches (Just "B")) ]
    case es.esOutcomes of
      (o : _) -> case o.ocCandidate.cdBound of
        Just b -> do
          b.baScope `shouldBe` BoundWholeAction
          b.baGuard `shouldBe` Nothing
          map (prettyLayout . getOriginal) b.baBinders `shouldBe` ["return"]
          -- `delivery` is the first act the #TRACE writes; the what-if did
          -- not invent it, and the replay is what says it discharges
          fmap (map (prettyLayout . snd)) b.baWitness `shouldBe` Right ["delivery"]
        Nothing -> expectationFailure "expected a bound act"
      []      -> expectationFailure "no outcomes"

  it "11'. a whole-action binder with nothing authored to try: the set is named, the refusal says nothing was replayed, and it is not the unforced-local sentence" $ do
    es <- enabledAt 0 aReturnFreshSrc
    map row es.esOutcomes `shouldBe`
      [ Row (CouldNot "Alice" "whatever") Untriable
      , Row (TickAt 11 ["Alice"]) (Breaches (Just "Alice")) ]
    case es.esOutcomes of
      (o : _) -> do
        o.ocCandidate.cdHypothetical `shouldBe`
          Left "the rule binds `whatever`, so any act by this party would match this obligation; no witness could be built to check that (this #TRACE writes no act of its own to try), so nothing was replayed"
        o.ocSteps `shouldBe` []
      [] -> expectationFailure "no outcomes"

  it "12. an argument binder with no guard: any amount counts, checked with the simplest value of its declared type" $ do
    es <- enabledAt 0 payAnySrc
    map row es.esOutcomes `shouldBe`
      [ Row (ActOf "Alice" "pay amount" 0) Discharges
      , Row (TickAt 11 ["Alice"]) (Breaches (Just "Alice")) ]
    case es.esOutcomes of
      (o : _) -> case o.ocCandidate.cdBound of
        Just b -> do
          b.baScope `shouldBe` BoundArgument
          b.baGuard `shouldBe` Nothing
          fmap (map (prettyLayout . snd)) b.baWitness `shouldBe` Right ["0"]
        Nothing -> expectationFailure "expected a bound act"
      [] -> expectationFailure "no outcomes"

  it "12'. a guard the witness does not satisfy: the pass-over is reported as untried, not as the contract's answer for every amount" $ do
    es <- enabledAt 0 payOverSrc
    map row es.esOutcomes `shouldBe`
      [ Row (ActOf "Alice" "pay amount" 0) Untriable
      , Row (TickAt 11 ["Alice"]) (Breaches (Just "Alice")) ]
    case es.esOutcomes of
      (o : _) -> do
        -- the bare replay still says what the machine said; only the
        -- verdict is held back, because one value proves nothing about the rest
        o.ocVerdict `shouldBe`
          Untried "the rule binds `amount`, which the condition amount GREATER THAN 20 tests; the one value tried, `amount` = 20, was passed over, so what would discharge it is not confirmed here"
      [] -> expectationFailure "no outcomes"

  it "12''. the same guard under a SHANT: the refusal asks what would BREACH it, not what would discharge it" $ do
    -- Until 2026-09-21 this sentence was the MUST's for every modal, so a
    -- prohibition's reader was told the opposite of what the rule does:
    -- an act clearing the threshold breaches this rule, it does not
    -- discharge it. Live on doc/reference/regulative/shant-example.l4's
    -- own `debt restriction` when it was found.
    es <- enabledAt 0 shantOverSrc
    case es.esOutcomes of
      (o : _) ->
        o.ocVerdict `shouldBe`
          Untried "the rule binds `amount`, which the condition amount GREATER THAN 20 tests; the one value tried, `amount` = 20, was passed over, so what would breach it is not confirmed here"
      [] -> expectationFailure "no outcomes"

  it "12'''. a guard application whose other argument is a different type: the witness falls to the declared type, not to the guard's string" $ do
    es <- enabledAt 0 payMistypedSrc
    map row es.esOutcomes `shouldBe`
      [ Row (ActOf "Alice" "pay amount" 0) Discharges
      , Row (TickAt 11 ["Alice"]) (Breaches (Just "Alice")) ]
    case es.esOutcomes of
      (o : _) -> case o.ocCandidate.cdBound of
        Just b -> do
          -- NOT "big": route 1 read the guard's shape, route 1's value did
          -- not fit `amount`'s declared NUMBER, so route 2 supplied 0
          fmap (map (prettyLayout . snd)) b.baWitness `shouldBe` Right ["0"]
          fmap (prettyLayout . (.hyAction)) o.ocCandidate.cdHypothetical `shouldBe` Right "pay OF 0"
        Nothing -> expectationFailure "expected a bound act"
      [] -> expectationFailure "no outcomes"

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
    cands <- candidatesOf rig tr pos
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

  it "10. a fork's HENCE naming the member's open `amount`: refused before the replay, in the what-if's words, never the evaluator's" $ do
    es <- enabledAt 0 runForkSrc
    es.esPosition.posClock `shouldBe` 4
    map row es.esOutcomes `shouldBe`
      [ Row (CouldNot "Landlord OF \"Ms Ng\"" "Receipt theLandlord t amount") Untriable
      , Row (TickAt 7 ["Landlord OF \"Ms Ng\""]) (Breaches (Just "Landlord OF \"Ms Ng\"")) ]
    case es.esOutcomes of
      (o : _) -> do
        o.ocCandidate.cdHypothetical `shouldBe` Left "the action binds `amount`, which the what-if cannot choose"
        -- the refusal is the candidate's, so no replay ran and no steps came of it
        o.ocSteps `shouldBe` []
        -- and the shape is still named as far as the residual could read it:
        -- the member `t` is Alice, only `amount` is open
        fmap prettyLayout o.ocCandidate.cdShape `shouldBe` Just "Receipt OF (Landlord OF \"Ms Ng\"), (Tenant OF \"Alice\"), amount"
      [] -> expectationFailure "no outcomes"
    -- nothing anywhere says "not in scope"
    for_ es.esOutcomes \ o -> case o.ocVerdict of
      Untried why -> why `shouldNotSatisfy` Text.isInfixOf "not in scope"
      _           -> pure ()

  it "10'. a rule GIVEN: unforced at the outset it is refused the same way; forced by a comparison it is read through a projection and tried" $ do
    outset <- enabledAt 0 givenSrc
    map row outset.esOutcomes `shouldBe`
      [ Row (CouldNot "Tenant" "pay (price PLUS 50)") Untriable
      , Row (TickAt 11 ["Tenant"]) (Breaches Nothing) ]
    case outset.esOutcomes of
      (o : _) -> o.ocCandidate.cdHypothetical `shouldBe` Left "the action binds `price`, which the what-if cannot choose"
      []      -> expectationFailure "no outcomes"
    forced <- enabledAt 1 givenSrc
    map row forced.esOutcomes `shouldBe`
      [ Row (ActOf "Tenant" "Deliver Tenant (p's landlord) what" 1) Discharges
      , Row (TickAt 11 ["Tenant"]) (Breaches Nothing) ]
    case forced.esOutcomes of
      (o : _) -> fmap prettyLayout o.ocCandidate.cdShape `shouldBe` Just "Deliver OF Tenant, ((Person OF Tenant, Landlord)'s landlord), Widget"
      []      -> expectationFailure "no outcomes"

  it "10''. a WHERE local under a section: refused by its unqualified name, the one the action beside it prints" $ do
    -- Pinned from the runtime on 2026-09-19: before it the line read
    -- `pay OF (y PLUS 1) — the action binds `inner.y``, one name two ways.
    outset <- enabledAt 0 whereSrc
    map row outset.esOutcomes `shouldBe`
      [ Row (CouldNot "Alice" "pay (y PLUS 1)") Untriable
      , Row (TickAt 11 ["Alice"]) (Breaches (Just "Alice")) ]
    case outset.esOutcomes of
      (o : _) -> do
        o.ocCandidate.cdHypothetical `shouldBe` Left "the action binds `y`, which the what-if cannot choose"
        fmap prettyLayout o.ocCandidate.cdShape `shouldBe` Just "pay OF (y PLUS 1)"
      [] -> expectationFailure "no outcomes"
    -- the rule fixes y at 41, so the act with 42 is the one the contract
    -- takes: the position after it is fulfilled, nothing owed, nothing to try
    done <- enabledAt 1 whereSrc
    done.esPosition.posClock `shouldBe` 1
    done.esPosition.posResult.result `shouldSatisfy` \ case
      Reduction (Reduced (MkNF ValFulfilled)) -> True
      _                                       -> False
    done.esPosition.posMarking `shouldBe` []
    map row done.esOutcomes `shouldBe` []

  it "tickPast lands one unit past a lone deadline, and half-way to a nearer next one" $ do
    tickPast [10] 10 `shouldBe` 11
    tickPast [10, 20] 10 `shouldBe` 11
    tickPast [10, 10.5] 10 `shouldBe` 10.25
    tickPast [10, 11] 11 `shouldBe` 12

  it "the modal is read from the residual, not decided here" $ do
    es <- enabledAt 0 shantSrc
    [ n.lnModal | InEffect n <- es.esPosition.posMarking ] `shouldBe` [DMustNot]
