{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | LTS-VISUALISER §4.2a (P2c): 'markingOf', the norm-plane marking.
--
-- Each test runs one directive through 'execEvalModuleWithDeonticLog' and
-- reads the marking off the residual it returned, with the context read
-- off the steps. The cases, in the spec's order:
--
--   1. FULFILLED marks nothing;
--   2. a breach marks Violated, with its blame;
--   3. an obligation marks InEffect, its countdown decremented;
--   4. an RAND of two live obligations marks both;
--   5. the ROr counterexample: a breached alternative is Lapsed, not Violated;
--   6. an unentered operand is Created (fact 4);
--   7. an unarmed EVERY is Created;
--   8. a non-regulative value marks nothing;
--
-- the four facts §4.2a rests on, each as a run:
--
--   F1. an RAND never holds a breach — it reduces to the breach;
--   F2. an ROR never holds a fulfilled operand — it reduces to FULFILLED;
--   F3. a compound with both operands breached does not survive;
--   F4. a Left operand is Created (case 6);
--
-- and the two families §4.9 adds:
--
--   B. a barrier with members pending marks each member InEffect and ONE
--      Awaiting, whose progress the context supplies and 'noContext' cannot;
--   K. a fork marks each member and each running continuation, and no
--      Awaiting;
--
-- and two ways the barrier's reading could lie, pinned not to:
--
--   R. a HENCE that re-enters its own barrier: the Awaiting reports the
--      second activation's count, not the first's final one;
--   S. a drafter's own `the join` written as a HENCE is not the sentinel.
module LtsMarkingSpec (spec) where

import qualified Data.Text as Text

import L4.API.VirtualFS (vfsFromList, checkWithImports)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.EvaluateLazy
  ( EvalDirectiveResult (..)
  , EvalDirectiveValue (..)
  , ReductionOutcome (..)
  , execEvalModuleWithDeonticLog
  , resolveEvalConfig
  )
import L4.Evaluate.ValueLazy (NF (..), Value (..))
import L4.EvaluateLazy.DeonticStep
import L4.EvaluateLazy.Machine (emptyEnvironment)
import L4.Lts.Marking
import L4.Syntax (DeonticModal (..), Threshold (..))
import L4.TracePolicy (apiDefaultPolicy)

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 0)

-- | Run a one-module source with the log on; return each directive's
-- residual (when it reduced) and its context.
runMarked :: Text.Text -> IO [(Maybe (Value NF), MarkingContext, [NormPlacement])]
runMarked src = do
  cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
  case checkWithImports (vfsFromList []) src of
    Left errs -> do
      expectationFailure ("typecheck failed: " <> show errs)
      pure []
    Right r -> do
      (_, results) <- execEvalModuleWithDeonticLog cfg r.tcdEntityInfo emptyEnvironment r.tcdModule
      pure
        [ (residual, ctx, maybe [] (markingOf ctx) residual)
        | (res, steps) <- results
        , let ctx = contextOf steps
        , let residual = case res.result of
                Reduction (Reduced (MkNF v)) -> Just v
                _                            -> Nothing
        ]

-- | The n-th directive's marking.
markingAt :: Int -> [(a, b, [NormPlacement])] -> [NormPlacement]
markingAt n rs = case drop n rs of
  ((_, _, m) : _) -> m
  []              -> []

-- | A compact view of a placement, for pinning.
data P
  = PCreated Text.Text
  | PInEffect Text.Text DeonticModal Text.Text Countdown Text.Text (Maybe Fam)
  | PViolated (Maybe Text.Text) (Maybe Rational)
  | PLapsed (Maybe Text.Text) (Maybe Rational)
  | PAwaiting (Maybe (Int, Int, Bool))
  deriving stock (Eq, Show)

data Fam = FBarrier Int | FFork Int | FDistributive Int
  deriving stock (Eq, Show)

view :: NormPlacement -> P
view = \ case
  Created {crSource} -> PCreated crSource
  InEffect n -> PInEffect (bearer n.lnBearer) n.lnModal n.lnAction n.lnDue n.lnHence (family <$> n.lnMember)
  Violated b -> PViolated b.blParty b.blDeadline
  Lapsed b -> PLapsed b.blParty b.blDeadline
  Awaiting {awProgress} -> PAwaiting ((\ p -> (p.prDone, p.prTotal, thresholdMet p)) <$> awProgress)
  where
    bearer = \ case
      KnownParty t    -> t
      UnforcedParty t -> t
    family f = case f.faJoin of
      Barrier _    -> FBarrier f.faTotal
      Fork         -> FFork f.faTotal
      Distributive -> FDistributive f.faTotal

prologue :: [Text.Text]
prologue =
  [ "DECLARE Person IS ONE OF Alice, Bob"
  , "DECLARE Action IS ONE OF"
  , "  deliver"
  , "  pay HAS amount IS A NUMBER"
  , ""
  , "GIVETH DEONTIC Person Action"
  , "obl MEANS PARTY Alice MUST deliver WITHIN 10 HENCE PARTY Bob MUST pay 50 WITHIN 5"
  , ""
  ]

-- 1–3: fulfilled, breached, in effect
singleSrc :: Text.Text
singleSrc = Text.unlines $ prologue <>
  [ "#TRACE obl AT 0 WITH"
  , "  PARTY Alice DOES deliver AT 2"
  , "  PARTY Bob DOES pay 50 AT 4"
  , ""
  , "#TRACE obl AT 0 WITH"
  , "  PARTY Bob DOES pay 1 AT 12"
  , ""
  , "#TRACE obl AT 0 WITH"
  , "  PARTY Bob DOES pay 1 AT 3"
  , ""
  , "#EVAL 5"
  ]

-- 4, F1: RAND
randSrc :: Text.Text
randSrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "both MEANS (PARTY Alice MUST deliver WITHIN 10) RAND (PARTY Bob MUST pay 50 WITHIN 20)"
  , ""
  , "#TRACE both AT 0 WITH"
  , "  PARTY Bob DOES pay 1 AT 3"
  , ""
  , "#TRACE both AT 0 WITH"
  , "  PARTY Bob DOES pay 1 AT 12"
  ]

-- 5, F2, F3, 6: ROR
rorSrc :: Text.Text
rorSrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "either MEANS (PARTY Alice MUST deliver WITHIN 10) ROR (PARTY Bob MUST pay 50 WITHIN 2)"
  , ""
  , "#TRACE either AT 0 WITH"
  , "  PARTY Alice DOES pay 1 AT 5"
  , ""
  , "#TRACE either AT 0 WITH"
  , "  PARTY Bob DOES pay 50 AT 1"
  , ""
  , "#TRACE either AT 0 WITH"
  , "  PARTY Bob DOES pay 1 AT 12"
  , ""
  , "#EVAL either"
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

-- 7, B: the barrier
barrierSrc :: Text.Text
barrierSrc = Text.unlines $ everyPrologue <>
  [ "GIVETH A DEONTIC Actor Action"
  , "`the tenancy` MEANS"
  , "    EVERY Tenant t IN tenants"
  , "        MUST   Sign (EXACTLY t)"
  , "        WITHIN 14"
  , "        ONCE   ALL HAVE"
  , "        HENCE  (PARTY theLandlord MUST Deliver (EXACTLY theLandlord) WITHIN 5)"
  , "        LEST   BREACH"
  , ""
  , "#TRACE `the tenancy` AT 0 WITH"
  , "  PARTY alice DOES Sign alice AT 1"
  , ""
  , "#EVAL `the tenancy`"
  , ""
  , "#TRACE `the tenancy` AT 0 WITH"
  ]

-- R: a barrier whose HENCE is itself. The machine re-registers the cast on
-- re-entry and zeroes its arm counter; the context must do the same.
reentrantSrc :: Text.Text
reentrantSrc = Text.unlines $ everyPrologue <>
  [ "GIVETH A DEONTIC Actor Action"
  , "`the tenancy` MEANS"
  , "    EVERY Tenant t IN tenants"
  , "        MUST   Sign (EXACTLY t)"
  , "        WITHIN 14"
  , "        ONCE   ALL HAVE"
  , "        HENCE  `the tenancy`"
  , "        LEST   BREACH"
  , ""
  , "#TRACE `the tenancy` AT 0 WITH"
  , "  PARTY alice DOES Sign alice AT 1"
  , "  PARTY bob   DOES Sign bob   AT 2"
  , "  PARTY carol DOES Sign carol AT 3"
  , "  PARTY alice DOES Sign alice AT 4"
  ]

-- S: a drafter's own `the join`, as a HENCE. Same name as the machine's
-- sentinel; not a barrier.
homonymSrc :: Text.Text
homonymSrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "`the join` MEANS PARTY Bob MUST pay 50 WITHIN 5"
  , ""
  , "GIVETH DEONTIC Person Action"
  , "c MEANS PARTY Alice MUST deliver WITHIN 10 HENCE `the join`"
  , ""
  , "#TRACE c AT 0 WITH"
  ]

-- K: the fork
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
  , "  PARTY alice DOES Sign alice AT 1"
  ]

spec :: Spec
spec = describe "LTS-VISUALISER §4.2a: markingOf" $ do

  it "1. FULFILLED marks nothing" $ do
    rs <- runMarked singleSrc
    markingAt 0 rs `shouldBe` []

  it "2. a breach marks Violated, with the party and the deadline it carries" $ do
    rs <- runMarked singleSrc
    map view (markingAt 1 rs) `shouldBe` [PViolated (Just "Alice") (Just 10)]

  it "3. an obligation in force marks InEffect, its countdown decremented by the event it saw" $ do
    rs <- runMarked singleSrc
    map view (markingAt 2 rs) `shouldBe`
      [PInEffect "Alice" DMust "deliver" (Remaining 7) "PARTY Bob MUST pay 50 WITHIN 5" Nothing]

  it "8. a non-regulative value marks nothing" $ do
    rs <- runMarked singleSrc
    markingAt 3 rs `shouldBe` []

  it "4. an RAND of two live obligations marks both, in operand order" $ do
    rs <- runMarked randSrc
    map view (markingAt 0 rs) `shouldBe`
      [ PInEffect "Alice" DMust "deliver" (Remaining 7) "FULFILLED" Nothing
      , PInEffect "Bob" DMust "pay 50" (Remaining 17) "FULFILLED" Nothing ]

  it "F1. an RAND never holds a breach: one operand's breach is the compound's, and nothing is Lapsed" $ do
    rs <- runMarked randSrc
    map view (markingAt 1 rs) `shouldBe` [PViolated (Just "Alice") (Just 10)]

  it "5. the ROr counterexample: the breached alternative is Lapsed, the live one InEffect, nothing Violated" $ do
    rs <- runMarked rorSrc
    map view (markingAt 0 rs) `shouldBe`
      [ PInEffect "Alice" DMust "deliver" (Remaining 5) "FULFILLED" Nothing
      , PLapsed (Just "Bob") (Just 2) ]

  it "F2. an ROR never holds a fulfilled operand: it reduces to FULFILLED" $ do
    rs <- runMarked rorSrc
    markingAt 1 rs `shouldBe` []

  it "F3. both operands breached does not survive: one Violated, no Lapsed" $ do
    rs <- runMarked rorSrc
    map view (markingAt 2 rs) `shouldBe` [PViolated (Just "Bob") (Just 2)]

  it "6 / F4. an unentered operand is Created, from the runtime's own Left" $ do
    rs <- runMarked rorSrc
    map view (markingAt 3 rs) `shouldBe`
      [ PCreated "PARTY Alice MUST deliver WITHIN 10"
      , PCreated "PARTY Bob MUST pay 50 WITHIN 2" ]

  it "7. an EVERY that has not met its events is Created, whole" $ do
    rs <- runMarked barrierSrc
    map view (markingAt 1 rs) `shouldBe`
      [PCreated "EVERY Tenant t IN tenants MUST Sign (EXACTLY t) WITHIN 14 ONCE ALL HAVE HENCE (PARTY theLandlord MUST Deliver (EXACTLY theLandlord) WITHIN 5) LEST BREACH"]

  it "B. a barrier with two of three pending: two members InEffect, one Awaiting at 1 of 3, not met" $ do
    rs <- runMarked barrierSrc
    map view (markingAt 0 rs) `shouldBe`
      [ PInEffect "Tenant OF \"Bob\"" DMust "Sign (EXACTLY t)" (Remaining 13) "`the join`" (Just (FBarrier 3))
      , PInEffect "Tenant OF \"Carol\"" DMust "Sign (EXACTLY t)" (Remaining 13) "`the join`" (Just (FBarrier 3))
      , PAwaiting (Just (1, 3, False)) ]
    -- the threshold the Awaiting carries is the ONCE line's
    case markingAt 0 rs of
      [_, _, Awaiting {awProgress = Just p}] -> case p.prThreshold of
        AllHave _ -> pure ()
      other -> expectationFailure ("expected two members and an Awaiting, got " <> show other)

  it "B'. the same residual read with no context: the Awaiting is still there, its progress unknown" $ do
    rs <- runMarked barrierSrc
    case rs of
      ((Just v, _, _) : _) ->
        map view (markingOf noContext v) `shouldBe`
          [ PInEffect "Tenant OF \"Bob\"" DMust "Sign (EXACTLY t)" (Remaining 13) "`the join`" Nothing
          , PInEffect "Tenant OF \"Carol\"" DMust "Sign (EXACTLY t)" (Remaining 13) "`the join`" Nothing
          , PAwaiting Nothing ]
      _ -> expectationFailure "no residual"

  it "B''. a barrier nobody has acted on: three members with their WITHIN still unforced, Awaiting at 0 of 3" $ do
    rs <- runMarked barrierSrc
    map view (markingAt 2 rs) `shouldBe`
      [ PInEffect "Tenant OF \"Alice\"" DMust "Sign (EXACTLY t)" (UnforcedDeadline "14" Nothing) "`the join`" (Just (FBarrier 3))
      , PInEffect "Tenant OF \"Bob\"" DMust "Sign (EXACTLY t)" (UnforcedDeadline "14" Nothing) "`the join`" (Just (FBarrier 3))
      , PInEffect "Tenant OF \"Carol\"" DMust "Sign (EXACTLY t)" (UnforcedDeadline "14" Nothing) "`the join`" (Just (FBarrier 3))
      , PAwaiting (Just (0, 3, False)) ]

  it "K. a fork with one member done: her continuation runs (its WITHIN unforced, no event seen), the others carry the drafter's HENCE and wait, and there is no Awaiting" $ do
    rs <- runMarked forkSrc
    map view (markingAt 0 rs) `shouldBe`
      [ PInEffect "theLandlord" DMust "Deliver (EXACTLY t)" (UnforcedDeadline "5" Nothing) "FULFILLED" Nothing
      , PInEffect "Tenant OF \"Bob\"" DMust "Sign (EXACTLY t)" (Remaining 6) "PARTY theLandlord MUST Deliver (EXACTLY t) WITHIN 5" (Just (FFork 3))
      , PInEffect "Tenant OF \"Carol\"" DMust "Sign (EXACTLY t)" (Remaining 6) "PARTY theLandlord MUST Deliver (EXACTLY t) WITHIN 5" (Just (FFork 3)) ]

  it "the raw walk yields exactly the InEffect places, in order: same sites, same bearers, same text" $ do
    rs <- runMarked forkSrc
    case rs of
      ((Just v, ctx, m) : _) -> do
        let raws  = liveObligations v
            lives = [ n | InEffect n <- m ]
        length raws `shouldBe` 3
        map (renderLive ctx) raws `shouldBe` lives
      _ -> expectationFailure "no residual"

  it "R. a HENCE that re-enters its own barrier: the Awaiting counts the second activation, 1 of 3, not the first's 3 of 3" $ do
    rs <- runMarked reentrantSrc
    map view (markingAt 0 rs) `shouldBe`
      [ PInEffect "Tenant OF \"Bob\"" DMust "Sign (EXACTLY t)" (Remaining 13) "`the join`" (Just (FBarrier 3))
      , PInEffect "Tenant OF \"Carol\"" DMust "Sign (EXACTLY t)" (Remaining 13) "`the join`" (Just (FBarrier 3))
      , PAwaiting (Just (1, 3, False)) ]

  it "R'. the steps behind R: three arms, a release, then one arm again" $ do
    cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
    case checkWithImports (vfsFromList []) reentrantSrc of
      Left errs -> expectationFailure ("typecheck failed: " <> show errs)
      Right r -> do
        (_, results) <- execEvalModuleWithDeonticLog cfg r.tcdEntityInfo emptyEnvironment r.tcdModule
        case results of
          ((_, steps) : _) ->
            [ (n, o) | s <- steps, let o = s.dsOutcome
                     , n <- case s.dsJoin of
                         Just (MemberSatisfied k _) -> [Just k]
                         _ | o == JoinReleased -> [Nothing]
                         _ -> [] ]
              `shouldBe` [ (Just 1, Matched ToHence), (Just 2, Matched ToHence), (Just 3, Matched ToHence)
                         , (Nothing, JoinReleased), (Just 1, Matched ToHence) ]
          [] -> expectationFailure "no results"

  it "S. a drafter's own `the join` as a HENCE is not the sentinel: no Awaiting, with or without a context" $ do
    rs <- runMarked homonymSrc
    map view (markingAt 0 rs) `shouldBe`
      [PInEffect "Alice" DMust "deliver" (UnforcedDeadline "10" Nothing) "`the join`" Nothing]
    case rs of
      ((Just v, _, _) : _) -> map view (markingOf noContext v) `shouldBe`
        [PInEffect "Alice" DMust "deliver" (UnforcedDeadline "10" Nothing) "`the join`" Nothing]
      _ -> expectationFailure "no residual"

  it "placementText says what a list needs to say about a blocked continuation" $ do
    rs <- runMarked barrierSrc
    map placementText (drop 2 (markingAt 0 rs)) `shouldBe`
      ["continuation blocked: 1 of 3 have acted (ONCE ALL HAVE)"]
