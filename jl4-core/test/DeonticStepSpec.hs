{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | LTS-VISUALISER §4.3 (P2b): the deontic step log.
--
-- Each test runs one @#TRACE@ through 'execEvalModuleWithDeonticLog' and
-- pins the EXACT step sequence the machine logged, projected onto the
-- fields a consumer reads: bearer, activation, outcome, scrutiny, the
-- event's stamp, the clock, and §4.9's join progress. Source ranges are not
-- pinned (they are a line/column pair that moves when a fixture is edited);
-- what is pinned about the key is that members of one @EVERY@ share a site
-- and differ in bearer and ordinal.
--
-- The shapes, in order:
--
--   1. a match routed to HENCE;
--   2. an expiry routed to LEST, with the revealing event re-offered;
--   3. a MAY that expires — routed to LEST, defaulting to FULFILLED;
--   4. a party mismatch and then a match;
--   5. an OR join where both sides breach at the same instant — the CSL
--      tie-break;
--   6. a barrier where member 1 satisfies its arm and is NOT released, and
--      member 2 releases the join;
--   7. a fork where each member's continuation runs on its own;
--   8. a barrier whose last completion comes after the ONCE … WITHIN, and
--      whose LEST is an explicit BREACH;
--   9. an OR whose LEFT side fulfils — the RBinOp1 short-circuit;
--  10. an obligation still pending when the events run out — Waiting;
--  11. a barrier with one member still pending when the events run out —
--      the member logs Waiting, the join logs nothing;
--  12. a prohibition violated, with a LEST and without one;
--  13. a PROVIDED that comes out false;
--  14. an action that does not match the pattern;
--  15. a barrier with a LEST whose member misses its own WITHIN — the
--      barrier's LEST runs once, via JoinFailed ToLest;
--  16. a barrier with no LEST whose MAY member lets its permission lapse —
--      JoinStalled;
--  17. a barrier with no LEST whose MUST member misses — JoinFailed ToBreach;
--
-- plus: the log-off path returns the same results as the log-on path, and
-- a directive with no regulative content logs nothing.
module DeonticStepSpec (spec) where

import qualified Data.Text as Text

import L4.API.VirtualFS (vfsFromList, checkWithImports)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.EvaluateLazy
  ( EvalDirectiveResult (..)
  , execEvalModuleWithDeonticLog
  , execEvalModuleWithEnv
  , prettyEvalDirectiveResult
  , resolveEvalConfig
  )
import L4.EvaluateLazy.DeonticStep
import L4.EvaluateLazy.Machine (emptyEnvironment)
import L4.Evaluate.ValueLazy (RBinOp (..))
import L4.Parser.SrcSpan (SrcRange)
import L4.Syntax (DeonticModal (..))
import L4.TracePolicy (apiDefaultPolicy)

import Data.Foldable (for_)
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 0)

-- | Typecheck a one-module source and run its directives with the log on.
runLogged :: Text.Text -> IO [(EvalDirectiveResult, [DeonticStep])]
runLogged src = do
  cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
  case checkWithImports (vfsFromList []) src of
    Left errs -> do
      expectationFailure ("typecheck failed: " <> show errs)
      pure []
    Right r -> do
      (_, results) <- execEvalModuleWithDeonticLog cfg r.tcdEntityInfo emptyEnvironment r.tcdModule
      pure results

-- | The same, log off.
runPlain :: Text.Text -> IO [EvalDirectiveResult]
runPlain src = do
  cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
  case checkWithImports (vfsFromList []) src of
    Left errs -> do
      expectationFailure ("typecheck failed: " <> show errs)
      pure []
    Right r -> do
      (_, results) <- execEvalModuleWithEnv cfg r.tcdEntityInfo emptyEnvironment r.tcdModule
      pure results

-- | What a test pins about one step.
data Row = Row
  { bearer     :: Maybe Text.Text
  , activation :: Int
  , modal      :: Maybe DeonticModal
  , outcome    :: StepOutcome
  , scrutiny   :: Scrutiny
  , stamp      :: Maybe Rational   -- ^ the event's
  , clock      :: Maybe Rational
  , join       :: Maybe JoinProgress
  }
  deriving stock (Eq, Show)

row :: DeonticStep -> Row
row s = Row
  { bearer     = keyPrefix <$> ((.nkBearer) =<< s.dsNorm)
  , activation = maybe 0 (.nkActivation) s.dsNorm
  , modal      = (.nkModal) <$> s.dsNorm
  , outcome    = s.dsOutcome
  , scrutiny   = s.dsScrutiny
  , stamp      = (.ekStamp) <$> s.dsEvent
  , clock      = s.dsClock
  , join       = s.dsJoin
  }

-- | The bearer is keyed exactly as the ledger keys it ('partyKeyWHNF'), and
-- for a constructor party that is its pretty layout, whose unforced fields
-- print as heap addresses (@Tenant OF &161\@main.l4@). The address is
-- deterministic within a run but not something to pin, so the rows keep
-- the text up to it and the EVERY tests assert distinctness separately.
keyPrefix :: Text.Text -> Text.Text
keyPrefix = Text.takeWhile (/= '&')

rawBearer :: DeonticStep -> Maybe Text.Text
rawBearer s = (.nkBearer) =<< s.dsNorm

-- | The member's site and membership, for the EVERY shapes, so the tests can
-- say "one site, two bearers, two ordinals".
site :: DeonticStep -> Maybe SrcRange
site s = (.nkSite) =<< s.dsNorm

member :: DeonticStep -> Maybe MemberOf
member s = (.nkMember) =<< s.dsNorm

-- | Steps of the n-th directive.
stepsOf :: Int -> [(EvalDirectiveResult, [DeonticStep])] -> [DeonticStep]
stepsOf n rs = case drop n rs of
  ((_, ss) : _) -> ss
  []            -> []

-- Shared prologue: two parties, two actions.
prologue :: [Text.Text]
prologue =
  [ "DECLARE Person IS ONE OF Alice, Bob"
  , "DECLARE Action IS ONE OF"
  , "  deliver"
  , "  pay HAS amount IS A NUMBER"
  , ""
  ]

-- 1. match → HENCE
matchSrc :: Text.Text
matchSrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  PARTY Alice MUST deliver WITHIN 10"
  , "  HENCE PARTY Bob MUST pay 50 WITHIN 10"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Alice DOES deliver AT 2"
  , "  PARTY Bob DOES pay 50 AT 4"
  ]

-- 2. expiry → LEST, revealing event re-offered to the LEST and consumed there
expirySrc :: Text.Text
expirySrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  PARTY Alice MUST deliver WITHIN 3"
  , "  LEST PARTY Alice MUST pay 100 WITHIN 10"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Alice DOES pay 100 AT 5"
  ]

-- 3. a MAY that expires: routed to LEST, which defaults to FULFILLED
maySrc :: Text.Text
maySrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  PARTY Alice MAY deliver WITHIN 3"
  , "  HENCE PARTY Bob MUST pay 50 WITHIN 10"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Bob DOES pay 50 AT 5"
  ]

-- 4. party mismatch, then a match
mismatchSrc :: Text.Text
mismatchSrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  PARTY Alice MUST deliver WITHIN 10"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Bob DOES deliver AT 1"
  , "  PARTY Alice DOES deliver AT 2"
  ]

-- 5. an OR whose two sides both breach at the same instant: CSL's tie-break
--    picks the RIGHT operand for OR
orSrc :: Text.Text
orSrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  (PARTY Alice MUST deliver WITHIN 3)"
  , "  ROR (PARTY Bob MUST pay 50 WITHIN 3)"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Alice DOES pay 1 AT 5"
  ]

-- The EVERY shapes share a cast of two tenants.
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
  , "tenants     MEANS LIST alice, bob"
  , ""
  ]

-- 6. barrier: member 1 satisfies (NOT released), member 2 releases
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
  , "  PARTY bob   DOES Sign bob   AT 3"
  , "  PARTY theLandlord DOES Deliver theLandlord AT 6"
  ]

-- 7. fork: each member's continuation runs on its own
forkSrc :: Text.Text
forkSrc = Text.unlines $ everyPrologue <>
  [ "GIVETH A DEONTIC Actor Action"
  , "`receipts` MEANS"
  , "    EVERY Tenant t IN tenants"
  , "        MUST   Sign (EXACTLY t)"
  , "        WITHIN 7"
  , "        UPON   EACH"
  , "        HENCE  (PARTY theLandlord MUST Deliver (EXACTLY t) WITHIN 5)"
  , "        LEST   BREACH BY t"
  , ""
  , "#TRACE `receipts` AT 0 WITH"
  , "  PARTY alice DOES Sign alice AT 1"
  , "  PARTY theLandlord DOES Deliver alice AT 2"
  , "  PARTY bob   DOES Sign bob   AT 3"
  , "  PARTY theLandlord DOES Deliver bob AT 4"
  ]

-- 8. the join-line deadline: everyone signs, the last one after day 5
joinDeadlineSrc :: Text.Text
joinDeadlineSrc = Text.unlines $ everyPrologue <>
  [ "GIVETH A DEONTIC Actor Action"
  , "`sign by day 5` MEANS"
  , "    EVERY Tenant t IN tenants"
  , "        MUST   Sign (EXACTLY t)"
  , "        WITHIN 14"
  , "        ONCE   ALL HAVE WITHIN 5"
  , "        HENCE  FULFILLED"
  , "        LEST   BREACH"
  , ""
  , "#TRACE `sign by day 5` AT 0 WITH"
  , "  PARTY alice DOES Sign alice AT 1"
  , "  PARTY bob   DOES Sign bob   AT 9"
  ]

-- 9. an OR whose LEFT side fulfils: the RBinOp1 short-circuit, the right
--    side never runs
orLeftSrc :: Text.Text
orLeftSrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  (PARTY Alice MUST deliver WITHIN 3)"
  , "  ROR (PARTY Bob MUST pay 50 WITHIN 3)"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Alice DOES deliver AT 1"
  ]

-- 10. the events run out with the obligation still pending
waitingSrc :: Text.Text
waitingSrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  PARTY Alice MUST deliver WITHIN 10"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Bob DOES deliver AT 1"
  ]

-- 11. a barrier with one member still pending when the events run out
barrierWaitingSrc :: Text.Text
barrierWaitingSrc = Text.unlines $ everyPrologue <>
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
  , "  PARTY alice DOES Sign alice AT 1"
  ]

-- 12. a prohibition violated: routed to LEST when there is one, else a breach
prohibitionSrc :: Text.Text
prohibitionSrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  PARTY Alice MUST NOT deliver WITHIN 10"
  , "  LEST PARTY Alice MUST pay 100 WITHIN 10"
  , ""
  , "GIVETH DEONTIC Person Action"
  , "d MEANS"
  , "  PARTY Alice MUST NOT deliver WITHIN 10"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Alice DOES deliver AT 2"
  , "  PARTY Alice DOES pay 100 AT 3"
  , ""
  , "#TRACE d AT 0 WITH"
  , "  PARTY Alice DOES deliver AT 2"
  ]

-- 13. a PROVIDED that comes out false: the event is witnessed, the next matches
guardSrc :: Text.Text
guardSrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  PARTY Alice MUST pay n PROVIDED n >= 50 WITHIN 10"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Alice DOES pay 10 AT 1"
  , "  PARTY Alice DOES pay 60 AT 2"
  ]

-- 14. the right party, the wrong action
actionMismatchSrc :: Text.Text
actionMismatchSrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  PARTY Alice MUST deliver WITHIN 10"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Alice DOES pay 5 AT 1"
  , "  PARTY Alice DOES deliver AT 2"
  ]

-- 15. a barrier with a LEST: bob never signs, the landlord's event at 20
--     reveals his expiry; the barrier's LEST (an explicit BREACH) runs once
barrierFailSrc :: Text.Text
barrierFailSrc = Text.unlines $ everyPrologue <>
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
  , "  PARTY alice DOES Sign alice AT 1"
  , "  PARTY theLandlord DOES Deliver theLandlord AT 20"
  ]

-- 16. a barrier with no LEST whose MAY member lets its permission lapse:
--     nothing was owed, the join can never fire
barrierStallSrc :: Text.Text
barrierStallSrc = Text.unlines $ everyPrologue <>
  [ "GIVETH A DEONTIC Actor Action"
  , "`the resolution` MEANS"
  , "    EVERY Tenant t IN tenants"
  , "        MAY    Sign (EXACTLY t)"
  , "        WITHIN 14"
  , "        ONCE   ALL HAVE"
  , "        HENCE  FULFILLED"
  , ""
  , "#TRACE `the resolution` AT 0 WITH"
  , "  PARTY alice DOES Sign alice AT 1"
  , "  PARTY theLandlord DOES Deliver theLandlord AT 20"
  ]

-- 17. a barrier with no LEST whose MUST member misses: the member's own
--     breach stands as the barrier's
barrierBreachSrc :: Text.Text
barrierBreachSrc = Text.unlines $ everyPrologue <>
  [ "GIVETH A DEONTIC Actor Action"
  , "`the tenancy` MEANS"
  , "    EVERY Tenant t IN tenants"
  , "        MUST   Sign (EXACTLY t)"
  , "        WITHIN 14"
  , "        ONCE   ALL HAVE"
  , "        HENCE  FULFILLED"
  , ""
  , "#TRACE `the tenancy` AT 0 WITH"
  , "  PARTY alice DOES Sign alice AT 1"
  , "  PARTY theLandlord DOES Deliver theLandlord AT 20"
  ]

-- Off-path proof: every fixture, both ways, same rendered result.
allSrcs :: [(String, Text.Text)]
allSrcs =
  [ ("match", matchSrc), ("expiry", expirySrc), ("may", maySrc), ("mismatch", mismatchSrc)
  , ("or", orSrc), ("barrier", barrierSrc), ("fork", forkSrc), ("join-deadline", joinDeadlineSrc)
  , ("or-left", orLeftSrc), ("waiting", waitingSrc), ("barrier-waiting", barrierWaitingSrc)
  , ("prohibition", prohibitionSrc), ("guard", guardSrc), ("action-mismatch", actionMismatchSrc)
  , ("barrier-fail", barrierFailSrc), ("barrier-stall", barrierStallSrc), ("barrier-breach", barrierBreachSrc) ]

-- | The 'Breached' step an explicit @BREACH@ with no @BY@ logs.
bareBreach :: Row
bareBreach = Row Nothing 0 Nothing
  (Breached MkBreachSummary {bsBlame = Nothing, bsStamp = Nothing, bsDeadline = Nothing})
  NoEvent Nothing Nothing Nothing

spec :: Spec
spec = describe "the deontic step log (LTS-VISUALISER §4.3, P2b)" $ do

  it "1. a match is Consumed and routed to HENCE; the continuation is its own activation" $ do
    rs <- runLogged matchSrc
    map row (stepsOf 0 rs) `shouldBe`
      [ Row (Just "Alice") 1 (Just DMust) (Matched ToHence) Consumed (Just 2) (Just 2) Nothing
      , Row (Just "Bob")   1 (Just DMust) (Matched ToHence) Consumed (Just 4) (Just 4) Nothing
      ]
    -- two sites: the outer obligation and the HENCE are different clauses
    length (nubOrd (map site (stepsOf 0 rs))) `shouldBe` 2

  it "2. an expiry is WitnessedOnly, routed to LEST with the deadline; the LEST sees the event Reoffered" $ do
    rs <- runLogged expirySrc
    map row (stepsOf 0 rs) `shouldBe`
      [ Row (Just "Alice") 1 (Just DMust) (Expired ToLest 3) WitnessedOnly (Just 5) (Just 0) Nothing
      , Row (Just "Alice") 1 (Just DMust) (Matched ToHence) Reoffered     (Just 5) (Just 5) Nothing
      ]

  it "3. a MAY that expires routes to LEST (defaulting to FULFILLED); its HENCE never runs" $ do
    rs <- runLogged maySrc
    map row (stepsOf 0 rs) `shouldBe`
      [ Row (Just "Alice") 1 (Just DMay) (Expired ToLest 3) WitnessedOnly (Just 5) (Just 0) Nothing ]

  it "4. a party mismatch is WitnessedOnly and advances the clock; then the match" $ do
    rs <- runLogged mismatchSrc
    map row (stepsOf 0 rs) `shouldBe`
      [ Row (Just "Alice") 1 (Just DMust) PartyMismatch     WitnessedOnly (Just 1) (Just 1) Nothing
      , Row (Just "Alice") 1 (Just DMust) (Matched ToHence) Consumed      (Just 2) (Just 2) Nothing
      ]
    -- the mismatching event's party is reported
    map (\s -> (.ekParty) =<< s.dsEvent) (stepsOf 0 rs) `shouldBe` [Just "Bob", Just "Alice"]

  it "5. an OR whose sides breach at the same instant is Joined by the CSL tie-break (right for OR)" $ do
    rs <- runLogged orSrc
    let ss = stepsOf 0 rs
    -- With no LEST there is no continuation to force the party in, so the
    -- bearer is whatever the breach's own party cell holds; a nullary
    -- constructor is allocated as a value, so here it is known. (A computed
    -- party would report Nothing: the log peeks, it never forces.)
    map row ss `shouldBe`
      [ Row (Just "Alice") 1 (Just DMust) (Expired ToBreach 3) WitnessedOnly (Just 5) (Just 0) Nothing
      , Row (Just "Bob")   1 (Just DMust) (Expired ToBreach 3) WitnessedOnly (Just 5) (Just 0) Nothing
      , Row Nothing 0 Nothing
          (Joined ValROr MkJoinNote
            { jnResult   = JoinBreached MkBreachSummary {bsBlame = Just "Bob", bsStamp = Just 5, bsDeadline = Just 3}
            , jnWinner   = Just RightSide
            , jnTieBreak = True })
          NoEvent Nothing Nothing Nothing
      ]
    -- the two expiries are two different sites, one activation each
    length (nubOrd (map site (take 2 ss))) `shouldBe` 2

  it "6. a barrier: member 1 satisfies one arm and is NOT released; member 2 satisfies the last and the join releases" $ do
    rs <- runLogged barrierSrc
    let ss = stepsOf 0 rs
    -- A member's match hands control to the join's checkpoint sentinel, so
    -- a member that COMPLETES never logs a Waiting step of its own. (A
    -- member still pending when the stream runs out does — see 11.)
    map row ss `shouldBe`
      [ Row (Just "Tenant OF ") 1 (Just DMust) (Matched ToHence) Consumed (Just 1) (Just 1) (Just (MemberSatisfied 1 2))
      , Row (Just "Tenant OF ") 2 (Just DMust) PartyMismatch WitnessedOnly (Just 1) (Just 1) Nothing
      , Row (Just "Tenant OF ") 2 (Just DMust) (Matched ToHence) Consumed (Just 3) (Just 3) (Just (MemberSatisfied 2 2))
      , Row Nothing 1 (Just DMust) JoinReleased NoEvent Nothing (Just 3) Nothing
      , Row (Just "Landlord OF ") 1 (Just DMust) (Matched ToHence) Consumed (Just 6) (Just 6) Nothing
      ]
    -- the two members share one site, are two bearers, and two activations of it
    let members' = [ s | s <- ss, Just m <- [member s], m.moJoin == Barrier ]
    length (nubOrd (map site members')) `shouldBe` 1
    length (nubOrd (map rawBearer members')) `shouldBe` 2
    map (\s -> fmap (.moIndex) (member s)) members' `shouldBe` [Just 1, Just 2, Just 2]
    -- and the join's own step is keyed by a different site from the members'
    map site [ s | s <- ss, s.dsOutcome == JoinReleased ] `shouldNotBe` take 1 (map site members')

  it "7. a fork: each member's own continuation runs, independently" $ do
    rs <- runLogged forkSrc
    let ss = stepsOf 0 rs
    -- Alice's continuation (the landlord's first obligation) runs to
    -- completion before Bob's scan begins — that is what "on its own" means
    -- — and the landlord's second obligation is a second activation of the
    -- same continuation site.
    map row ss `shouldBe`
      [ Row (Just "Tenant OF ") 1 (Just DMust) (Matched ToHence) Consumed (Just 1) (Just 1) (Just (ForkContinued 1 2))
      , Row (Just "Landlord OF ") 1 (Just DMust) (Matched ToHence) Consumed (Just 2) (Just 2) Nothing
      , Row (Just "Tenant OF ") 2 (Just DMust) PartyMismatch WitnessedOnly (Just 1) (Just 1) Nothing
      , Row (Just "Tenant OF ") 2 (Just DMust) PartyMismatch WitnessedOnly (Just 2) (Just 2) Nothing
      , Row (Just "Tenant OF ") 2 (Just DMust) (Matched ToHence) Consumed (Just 3) (Just 3) (Just (ForkContinued 2 2))
      , Row (Just "Landlord OF ") 2 (Just DMust) (Matched ToHence) Consumed (Just 4) (Just 4) Nothing
      , Row Nothing 0 Nothing (Joined ValRAnd MkJoinNote {jnResult = JoinFulfilled, jnWinner = Just BothSides, jnTieBreak = False}) NoEvent Nothing Nothing Nothing
      ]
    let members' = [ s | s <- ss, Just m <- [member s], m.moJoin == Fork ]
    length (nubOrd (map rawBearer members')) `shouldBe` 2
    -- a fork has no join step: nothing carries the join's site
    [ s | s <- ss, s.dsOutcome `elem` [JoinReleased, JoinFailed ToLest, JoinStalled] ] `shouldBe` []

  it "8. a join-line deadline: every arm satisfied, the last too late; JoinExpired to LEST, whose BREACH is logged" $ do
    rs <- runLogged joinDeadlineSrc
    let ss = stepsOf 0 rs
    -- Bob's step says MemberSatisfied 2 2 and NOT released: the release is
    -- the join's decision, and here the join decides the other way. The
    -- LEST is an explicit BREACH, and the log says so: without the last
    -- row, "JoinExpired ToLest" could as well have been a reparation.
    map row ss `shouldBe`
      [ Row (Just "Tenant OF ") 1 (Just DMust) (Matched ToHence) Consumed (Just 1) (Just 1) (Just (MemberSatisfied 1 2))
      , Row (Just "Tenant OF ") 2 (Just DMust) PartyMismatch WitnessedOnly (Just 1) (Just 1) Nothing
      , Row (Just "Tenant OF ") 2 (Just DMust) (Matched ToHence) Consumed (Just 9) (Just 9) (Just (MemberSatisfied 2 2))
      , Row Nothing 1 (Just DMust) (JoinExpired ToLest 5) NoEvent Nothing (Just 9) Nothing
      , bareBreach
      ]

  it "9. an OR whose LEFT side fulfils is Joined at the RBinOp1 short-circuit; the right side never runs" $ do
    rs <- runLogged orLeftSrc
    map row (stepsOf 0 rs) `shouldBe`
      [ Row (Just "Alice") 1 (Just DMust) (Matched ToHence) Consumed (Just 1) (Just 1) Nothing
      , Row Nothing 0 Nothing (Joined ValROr MkJoinNote {jnResult = JoinFulfilled, jnWinner = Just LeftSide, jnTieBreak = False}) NoEvent Nothing Nothing Nothing
      ]

  it "10. the events run out with the obligation pending: Waiting, at the clock the last event advanced it to" $ do
    rs <- runLogged waitingSrc
    map row (stepsOf 0 rs) `shouldBe`
      [ Row (Just "Alice") 1 (Just DMust) PartyMismatch WitnessedOnly (Just 1) (Just 1) Nothing
      , Row (Just "Alice") 1 (Just DMust) Waiting NoEvent Nothing (Just 1) Nothing
      ]

  it "11. a barrier with a member still pending when the events run out: the member logs Waiting, the join logs nothing" $ do
    rs <- runLogged barrierWaitingSrc
    let ss = stepsOf 0 rs
    map row ss `shouldBe`
      [ Row (Just "Tenant OF ") 1 (Just DMust) (Matched ToHence) Consumed (Just 1) (Just 1) (Just (MemberSatisfied 1 2))
      , Row (Just "Tenant OF ") 2 (Just DMust) PartyMismatch WitnessedOnly (Just 1) (Just 1) Nothing
      , Row (Just "Tenant OF ") 2 (Just DMust) Waiting NoEvent Nothing (Just 1) Nothing
      ]
    -- the Waiting step is the member's, and says so
    fmap (.moJoin) (member (ss !! 2)) `shouldBe` Just Barrier

  it "12. a prohibition violated is Consumed and routed to LEST, or to a breach when it has none" $ do
    rs <- runLogged prohibitionSrc
    map row (stepsOf 0 rs) `shouldBe`
      [ Row (Just "Alice") 1 (Just DMustNot) (Matched ToLest)  Consumed (Just 2) (Just 2) Nothing
      , Row (Just "Alice") 1 (Just DMust)    (Matched ToHence) Consumed (Just 3) (Just 3) Nothing
      ]
    map row (stepsOf 1 rs) `shouldBe`
      [ Row (Just "Alice") 1 (Just DMustNot) (Matched ToBreach) Consumed (Just 2) (Just 2) Nothing ]

  it "13. a PROVIDED that comes out false is WitnessedOnly and advances the clock; then the match" $ do
    rs <- runLogged guardSrc
    map row (stepsOf 0 rs) `shouldBe`
      [ Row (Just "Alice") 1 (Just DMust) GuardFailed       WitnessedOnly (Just 1) (Just 1) Nothing
      , Row (Just "Alice") 1 (Just DMust) (Matched ToHence) Consumed      (Just 2) (Just 2) Nothing
      ]

  it "14. an action that does not match the pattern is WitnessedOnly and advances the clock; then the match" $ do
    rs <- runLogged actionMismatchSrc
    map row (stepsOf 0 rs) `shouldBe`
      [ Row (Just "Alice") 1 (Just DMust) ActionMismatch    WitnessedOnly (Just 1) (Just 1) Nothing
      , Row (Just "Alice") 1 (Just DMust) (Matched ToHence) Consumed      (Just 2) (Just 2) Nothing
      ]
    -- the mismatching action is reported; its unforced field prints as a
    -- heap address, pinned by prefix as the bearer is
    map (\s -> keyPrefix <$> ((.ekAction) =<< s.dsEvent)) (stepsOf 0 rs) `shouldBe` [Just "pay OF ", Just "deliver"]

  it "15. a barrier with a LEST whose member misses: Expired ToLest reports the failure, JoinFailed ToLest runs the LEST once, and its BREACH is logged" $ do
    rs <- runLogged barrierFailSrc
    let ss = stepsOf 0 rs
    map row ss `shouldBe`
      [ Row (Just "Tenant OF ") 1 (Just DMust) (Matched ToHence) Consumed (Just 1) (Just 1) (Just (MemberSatisfied 1 2))
      , Row (Just "Tenant OF ") 2 (Just DMust) PartyMismatch WitnessedOnly (Just 1) (Just 1) Nothing
      , Row (Just "Tenant OF ") 2 (Just DMust) (Expired ToLest 14) WitnessedOnly (Just 20) (Just 1) Nothing
      , Row Nothing 1 (Just DMust) (JoinFailed ToLest) NoEvent Nothing (Just 20) Nothing
      , bareBreach
      ]

  it "16. a barrier with no LEST whose MAY member lapses: Expired ToLest (defaulting to FULFILLED), then JoinStalled" $ do
    rs <- runLogged barrierStallSrc
    let ss = stepsOf 0 rs
    map row ss `shouldBe`
      [ Row (Just "Tenant OF ") 1 (Just DMay) (Matched ToHence) Consumed (Just 1) (Just 1) (Just (MemberSatisfied 1 2))
      , Row (Just "Tenant OF ") 2 (Just DMay) PartyMismatch WitnessedOnly (Just 1) (Just 1) Nothing
      , Row (Just "Tenant OF ") 2 (Just DMay) (Expired ToLest 14) WitnessedOnly (Just 20) (Just 1) Nothing
      , Row Nothing 1 (Just DMay) JoinStalled NoEvent Nothing Nothing Nothing
      ]

  it "17. a barrier with no LEST whose MUST member misses: Expired ToBreach, then JoinFailed ToBreach" $ do
    rs <- runLogged barrierBreachSrc
    let ss = stepsOf 0 rs
    map row ss `shouldBe`
      [ Row (Just "Tenant OF ") 1 (Just DMust) (Matched ToHence) Consumed (Just 1) (Just 1) (Just (MemberSatisfied 1 2))
      , Row (Just "Tenant OF ") 2 (Just DMust) PartyMismatch WitnessedOnly (Just 1) (Just 1) Nothing
      , Row (Just "Tenant OF ") 2 (Just DMust) (Expired ToBreach 14) WitnessedOnly (Just 20) (Just 1) Nothing
      , Row Nothing 1 (Just DMust) (JoinFailed ToBreach) NoEvent Nothing Nothing Nothing
      ]

  it "the log-off path is unchanged: every fixture renders the same result both ways" $
    for_ allSrcs \(name, src) -> do
      logged <- runLogged src
      plain  <- runPlain src
      (name, map (prettyEvalDirectiveResult . fst) logged) `shouldBe` (name, map prettyEvalDirectiveResult plain)

  it "a directive with nothing regulative logs nothing" $ do
    rs <- runLogged (Text.unlines ["#EVAL 1 PLUS 2"])
    map snd rs `shouldBe` [[]]
  where
    nubOrd :: Ord a => [a] -> [a]
    nubOrd = foldr (\x acc -> if x `elem` acc then acc else x : acc) []
