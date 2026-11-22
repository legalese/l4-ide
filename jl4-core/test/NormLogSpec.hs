{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | NORM-LOG-SPEC (P1): the norm log writer.
--
-- Each test runs one @#TRACE@ with the writer on and pins the EXACT sequence
-- of norm entries the machine wrote into the directive's norm ledger,
-- projected onto what a reader uses: the fate, the modal, the bearer, the two
-- instants (N3) and the parent link (N8). The shapes:
--
--   1. a performance routed to HENCE, with its parent link;
--   2. a failure routed to a LEST obligation, whose instants are the missed
--      deadline and the revealing event's stamp;
--   3. a LEST that is a bare BREACH: the failure, then the breach, with the
--      failed party as the breach's bearer (N7 rule 2);
--   4. one named BREACH shared by two LESTs: one entry per reach (N7 rule 1);
--   5. a prohibition violated, and one kept;
--   6. a permission exercised, and one lapsed;
--   7. a party the machine never forced: the entry carries it as written;
--   8. the parent link through chained LESTs, a compound in a LEST, and an
--      EVERY barrier and fork (N8);
--   9. a bare BREACH on a HENCE path, after a lapsed MAY, under a barrier, and
--      a BREACH BY (N7 rule 2);
--  10. an obligation armed after its own deadline: effective floors at the
--      arming (N3's amendment).
--
-- plus the properties the spec's rulings require of every entry: effective
-- is never after observed (N3), each norm is armed exactly once, @RECALL@
-- cannot see a fate (N5), and the writer changes no answer (N6).
module NormLogSpec (spec) where

import qualified Data.Text as Text

import L4.API.VirtualFS (VFS, vfsFromList, checkWithImports)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.Evaluate.Ledger (LedgerEvent (..), LedgerStore (..))
import L4.Evaluate.NormLog
import L4.EvaluateLazy
  ( EvalConfig (..)
  , EvalDirectiveResult (..)
  , NormLogMutant (..)
  , execEvalModuleWithEnv
  , prettyEvalDirectiveResult
  , resolveEvalConfig
  )
import L4.EvaluateLazy.Machine (emptyEnvironment)
import L4.Syntax (DeonticModal (..))
import L4.TracePolicy (apiDefaultPolicy)

import qualified Data.Text.IO as TextIO
import Data.Foldable (for_, toList)
import Data.List (isSuffixOf, sort)
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import System.Directory (listDirectory)
import System.Environment (lookupEnv)
import System.FilePath (dropExtension, (</>))
import Test.Hspec

fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 0)

-- | Typecheck a one-module source and run its directives, the writer on or
-- off.
run :: Bool -> Text.Text -> IO [EvalDirectiveResult]
run writerOn = runWith (\ cfg -> cfg {normLog = writerOn})

runWith :: (EvalConfig -> EvalConfig) -> Text.Text -> IO [EvalDirectiveResult]
runWith = runIn (vfsFromList [])

runIn :: VFS -> (EvalConfig -> EvalConfig) -> Text.Text -> IO [EvalDirectiveResult]
runIn vfs tweak src = do
  cfg0 <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
  let cfg = tweak cfg0
  case checkWithImports vfs src of
    Left errs -> do
      expectationFailure ("typecheck failed: " <> show errs)
      pure []
    Right r -> do
      (_, results) <- execEvalModuleWithEnv cfg r.tcdEntityInfo emptyEnvironment r.tcdModule
      pure results

-- | The norm entries of the n-th directive, oldest first.
fatesOf :: Int -> [EvalDirectiveResult] -> [NormEntry]
fatesOf n rs = case drop n rs of
  (r : _) -> [ e | Fate e <- toList r.ledger.normLedger ]
  []      -> []

-- | What a test pins about one entry.
data Row = Row
  { fate      :: Fate
  , modal     :: Maybe DeonticModal
  , bearer    :: Maybe Text.Text
  , effective :: Maybe Rational
  , observed  :: Maybe Rational
  , origin    :: Maybe (OriginBranch, Int)  -- ^ how it was armed, and the parent's activation
  }
  deriving stock (Eq, Show)

row :: NormEntry -> Row
row e = Row
  { fate = e.neFate
  , modal = e.neModal
  , bearer = case e.neBearer of
      KnownBearer t   -> Just (keyPrefix t)
      WrittenBearer t -> Just (keyPrefix t)
      NobodyBearer    -> Just "(nobody)"
      UnknownBearer   -> Just "(unknown)"
  , effective = e.neEffective
  , observed = e.neObserved
  , origin = (\ o -> (o.noBranch, o.noParent.nrActivation)) <$> e.neOrigin
  }

isJoinFate :: Fate -> Bool
isJoinFate = \case
  FateJoinReleased -> True
  FateJoinExpired  -> True
  FateJoinFailed   -> True
  FateJoinStalled  -> True
  _                -> False

-- | The norm a fate is about, and the norm that armed it.
ownRef :: NormEntry -> Maybe NormRef
ownRef = (.neNorm)

parentOf :: NormEntry -> Maybe NormRef
parentOf e = (.noParent) <$> e.neOrigin

keyPrefix' :: NormBearer -> Text.Text
keyPrefix' = \case
  KnownBearer t   -> keyPrefix t
  WrittenBearer t -> keyPrefix t
  NobodyBearer    -> "(nobody)"
  UnknownBearer   -> "(unknown)"

-- | A constructor party's key prints unforced fields as heap addresses; keep
-- the text up to it.
-- | The result as it would print with the writer off: its norm ledger is the
-- one part of the output the writer is allowed to add.
withoutNormLog :: EvalDirectiveResult -> EvalDirectiveResult
withoutNormLog (MkEvalDirectiveResult a b c l d e) =
  MkEvalDirectiveResult a b c (l {normLedger = mempty}) d e

keyPrefix :: Text.Text -> Text.Text
keyPrefix = Text.takeWhile (/= '&')

prologue :: [Text.Text]
prologue =
  [ "DECLARE Person IS ONE OF Alice, Bob"
  , "DECLARE Action IS ONE OF"
  , "  deliver"
  , "  pay HAS amount IS A NUMBER"
  , ""
  ]

-- 1. a performance routed to HENCE
henceSrc :: Text.Text
henceSrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  PARTY Alice MUST deliver WITHIN 10"
  , "  HENCE PARTY Bob MUST pay 50 WITHIN 10"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Alice DOES deliver AT 2"
  , "  PARTY Bob DOES pay 50 AT 4"
  ]

-- 2. a failure routed to a LEST obligation
lestSrc :: Text.Text
lestSrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  PARTY Alice MUST deliver WITHIN 3"
  , "  LEST PARTY Alice MUST pay 100 WITHIN 10"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Alice DOES pay 100 AT 5"
  ]

-- 3. a LEST that is a bare BREACH
lestBreachSrc :: Text.Text
lestBreachSrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  PARTY Alice MUST deliver WITHIN 3"
  , "  LEST BREACH"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Bob DOES deliver AT 5"
  ]

-- 4. one named BREACH shared by two LESTs, each side missing its deadline
sharedBreachSrc :: Text.Text
sharedBreachSrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "b MEANS BREACH"
  , ""
  , "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  (PARTY Alice MUST deliver WITHIN 3 LEST b)"
  , "  RAND"
  , "  (PARTY Bob MUST pay 50 WITHIN 3 LEST b)"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Alice DOES deliver AT 5"
  ]

-- 5a. a prohibition violated
violatedSrc :: Text.Text
violatedSrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  PARTY Alice SHANT deliver WITHIN 5"
  , "  LEST BREACH"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Alice DOES deliver AT 2"
  ]

-- 5b. a prohibition kept: its window closes with no forbidden act
keptSrc :: Text.Text
keptSrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  PARTY Alice SHANT deliver WITHIN 5"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Bob DOES pay 50 AT 7"
  ]

-- 6a. a permission exercised
exercisedSrc :: Text.Text
exercisedSrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  PARTY Alice MAY deliver WITHIN 3"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Alice DOES deliver AT 2"
  ]

-- 6b. a permission that lapses
lapsedSrc :: Text.Text
lapsedSrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  PARTY Alice MAY deliver WITHIN 3"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Bob DOES pay 50 AT 5"
  ]

-- 7. a computed party that misses with no LEST: the machine never forces it
computedPartySrc :: Text.Text
computedPartySrc = Text.unlines $ everyPrologue <>
  [ "GIVETH A DEONTIC Actor Action"
  , "`deliver by day 5` MEANS"
  , "    PARTY theLandlord MUST Deliver theLandlord WITHIN 5"
  , ""
  , "#TRACE `deliver by day 5` AT 0 WITH"
  , "  PARTY alice DOES Sign alice AT 8"
  , ""
  , "#TRACE `deliver by day 5` AT 0 WITH"
  ]

-- 8a. chained LESTs: the third norm is armed by the second's failure, the
-- second by the first's
chainSrc :: Text.Text
chainSrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  PARTY Alice MUST deliver WITHIN 3"
  , "  LEST (PARTY Alice MUST pay 100 WITHIN 5"
  , "        LEST PARTY Alice MUST pay 200 WITHIN 5)"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Alice DOES pay 200 AT 10"
  ]

-- 8b. a compound inside a LEST: both operands are armed by the failure
compoundLestSrc :: Text.Text
compoundLestSrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  PARTY Alice MUST deliver WITHIN 3"
  , "  LEST ((PARTY Alice MUST pay 1 WITHIN 5) RAND (PARTY Bob MUST pay 2 WITHIN 5))"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Alice DOES pay 1 AT 4"
  ]

-- 8c. an EVERY barrier; a barrier whose second member never signs
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
  , ""
  , "#TRACE `the tenancy` AT 0 WITH"
  , "  PARTY alice DOES Sign alice AT 1"
  , "  PARTY theLandlord DOES Deliver theLandlord AT 20"
  ]

-- 8d. an EVERY fork: each member's HENCE runs on its own
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

-- 9a. a bare BREACH on a HENCE path
henceBreachSrc :: Text.Text
henceBreachSrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  PARTY Alice MAY deliver WITHIN 3"
  , "  HENCE BREACH"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Alice DOES deliver AT 2"
  ]

-- 9b. a bare BREACH after a lapsed MAY: a lapse is no failure
lapsedBreachSrc :: Text.Text
lapsedBreachSrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  PARTY Alice MAY deliver WITHIN 3"
  , "  LEST BREACH"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Bob DOES pay 50 AT 5"
  ]

-- 9c. BREACH BY keeps whom the drafter named, whoever failed
breachBySrc :: Text.Text
breachBySrc = Text.unlines $ prologue <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  PARTY Alice MUST deliver WITHIN 3"
  , "  LEST BREACH BY Bob"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Bob DOES pay 50 AT 5"
  ]

-- 10. an obligation armed after its own deadline (breach-clocks.l4 §4)
lateArmingSrc :: Text.Text
lateArmingSrc = Text.unlines
  [ "IMPORT prelude"
  , "DECLARE Actor IS ONE OF P, Q, R"
  , "DECLARE Action IS ONE OF x, y, z, w"
  , ""
  , "GIVETH A DEONTIC Actor Action"
  , "`late arming` MEANS"
  , "    PARTY P MUST x WITHIN 10"
  , "    HENCE (PARTY R MUST z WITHIN 3 OF THE ARMING)"
  , ""
  , "#TRACE `late arming` AT 0 WITH"
  , "  PARTY P DOES x AT 4"
  , "  (WAITUNTIL 5)"
  ]

-- 11. a ledger listing whose party key names a heap address (an unforced
-- field of a record party): the writer must not move the addresses, which it
-- did when its parent-link carrier took one from the supply (found by running
-- jl4-test with the writer on, on ok/every/run-lifecycle-values.l4)
recordSrc :: Text.Text
recordSrc = Text.unlines
  [ "IMPORT prelude"
  , "DECLARE Actor IS ONE OF"
  , "    Landlord HAS name IS A STRING"
  , "    Tenant   HAS name IS A STRING"
  , ""
  , "DECLARE Action IS ONE OF"
  , "    Sign    HAS signer IS AN Actor"
  , "    Refund  HAS who    IS AN Actor"
  , ""
  , "theLandlord MEANS Landlord OF \"Ms Ng\""
  , "alice       MEANS Tenant OF \"Alice\""
  , ""
  , "GIVETH A DEONTIC Actor Action"
  , "`record the receipt` MEANS"
  , "    PARTY alice MUST Sign alice WITHIN 10"
  , "    HENCE RECORD `receipt` IS THE JOIN"
  , "    HENCE (PARTY theLandlord MUST Refund theLandlord WITHIN 30 OF (fromMaybe 0 (RECALL `receipt`)))"
  , ""
  , "#TRACE `record the receipt` AT 0 WITH"
  , "  PARTY alice DOES Sign alice AT 4"
  , "  PARTY theLandlord DOES Refund theLandlord AT 35"
  ]

-- 8e. an EVERY armed by a HENCE (N8: a member's parent, and a barrier join's
-- parent, is whatever armed the EVERY)
everyAfterHenceForkSrc, everyAfterHenceBarrierSrc :: Text.Text
everyAfterHenceForkSrc = Text.unlines $ everyPrologue <>
  [ "GIVETH A DEONTIC Actor Action"
  , "`handover, then receipts` MEANS"
  , "    PARTY theLandlord MUST Deliver theLandlord WITHIN 5"
  , "    HENCE (EVERY Tenant t IN tenants"
  , "              MUST   Sign (EXACTLY t)"
  , "              WITHIN 7"
  , "              UPON   EACH"
  , "              LEST   BREACH BY t)"
  , ""
  , "#TRACE `handover, then receipts` AT 0 WITH"
  , "  PARTY theLandlord DOES Deliver theLandlord AT 1"
  , "  PARTY alice DOES Sign alice AT 2"
  , "  PARTY bob   DOES Sign bob   AT 3"
  ]
everyAfterHenceBarrierSrc = Text.unlines $ everyPrologue <>
  [ "GIVETH A DEONTIC Actor Action"
  , "`handover, then tenancy` MEANS"
  , "    PARTY theLandlord MUST Deliver theLandlord WITHIN 5"
  , "    HENCE (EVERY Tenant t IN tenants"
  , "              MUST   Sign (EXACTLY t)"
  , "              WITHIN 14"
  , "              ONCE   ALL HAVE"
  , "              LEST   BREACH)"
  , ""
  , "#TRACE `handover, then tenancy` AT 0 WITH"
  , "  PARTY theLandlord DOES Deliver theLandlord AT 1"
  , "  PARTY alice DOES Sign alice AT 2"
  , "  PARTY bob   DOES Sign bob   AT 3"
  ]

-- 12. a party that cannot be evaluated, which the run never needs: a trace
-- with no events never compares it, and the residual obligation prints the
-- party as written. (With an event past the deadline the BREACH result prints
-- the party, which evaluates it whatever the writer does: a first version of
-- this fixture had that event and was no test of anything.) A writer that evaluated the party at arming (the MutantForce
-- of the observer test) would fail this run with a division by zero; the
-- real writer only peeks, so the run is unchanged. This is the fixture that
-- shows the observer test is sensitive to a writer that forces a thunk.
unforcedPartySrc :: Text.Text
unforcedPartySrc = Text.unlines $ everyPrologue <>
  [ "`a party nobody should evaluate` MEANS"
  , "    IF (1 DIVIDED BY 0) EQUALS 0 THEN alice ELSE bob"
  , ""
  , "GIVETH A DEONTIC Actor Action"
  , "`deliver by day 5` MEANS"
  , "    PARTY `a party nobody should evaluate` MUST Deliver theLandlord WITHIN 5"
  , ""
  , "#TRACE `deliver by day 5` AT 0 WITH"
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

allSources :: [(String, Text.Text)]
allSources =
  [ ("hence", henceSrc), ("lest", lestSrc), ("lest breach", lestBreachSrc)
  , ("shared breach", sharedBreachSrc), ("violated", violatedSrc), ("kept", keptSrc)
  , ("exercised", exercisedSrc), ("lapsed", lapsedSrc)
  , ("chain", chainSrc), ("compound in a lest", compoundLestSrc)
  , ("barrier", barrierSrc), ("fork", forkSrc), ("hence breach", henceBreachSrc)
  , ("lapsed breach", lapsedBreachSrc), ("breach by", breachBySrc)
  , ("late arming", lateArmingSrc), ("computed party", computedPartySrc)
  , ("record in a hence", recordSrc)
  , ("unforced party", unforcedPartySrc)
  , ("every after hence (fork)", everyAfterHenceForkSrc)
  , ("every after hence (barrier)", everyAfterHenceBarrierSrc) ]

-- | An opt-in extra corpus: when @NORMLOG_EXTRA_DIR@ names a directory, every
-- @.l4@ file in it is run with the writer on and off, and the printed results
-- must agree. The modules in the directory may import each other by file name.
-- This is how a corpus that does not live in this repository (the
-- agent-shopping files in @legalese/solutions@) is held to the same test.
extraCorpus :: Spec
extraCorpus = do
  mdir <- runIO (lookupEnv "NORMLOG_EXTRA_DIR")
  for_ mdir \ dir -> do
    files <- runIO (sort . filter (".l4" `isSuffixOf`) <$> listDirectory dir)
    modules <- runIO (mapM (\ f -> (\ t -> (Text.pack (dropExtension f), t)) <$> TextIO.readFile (dir </> f)) files)
    let vfs = vfsFromList modules
    describe ("the extra corpus " <> dir) do
      for_ modules \ (name, src) ->
        it (Text.unpack name <> ": the writer changes no answer") do
          on <- runIn vfs (\ cfg -> cfg {normLog = True}) src
          off <- runIn vfs (\ cfg -> cfg {normLog = False}) src
          map (prettyEvalDirectiveResult . withoutNormLog) on `shouldBe` map prettyEvalDirectiveResult off
      -- the positive control: a differential over files that write no fate
      -- would pass whatever the writer did
      it "the writer wrote fates somewhere in it, so the comparison above is not vacuous" do
        counts <- mapM (\ (_, src) -> length . concatMap (\ r -> [ () | Fate _ <- toList r.ledger.normLedger ]) <$>
                          runIn vfs (\ cfg -> cfg {normLog = True}) src) modules
        sum counts `shouldSatisfy` (> 0)

spec :: Spec
spec = describe "the norm log writer (NORM-LOG-SPEC, P1)" do
  extraCorpus
  it "1. a performance: armed, performed; the HENCE norm is armed with its parent" do
    rs <- run True henceSrc
    map row (fatesOf 0 rs) `shouldBe`
      [ Row FateArmed (Just DMust) (Just "Alice") (Just 0) (Just 0) Nothing
      , Row FatePerformed (Just DMust) (Just "Alice") (Just 2) (Just 2) Nothing
      , Row FateArmed (Just DMust) (Just "Bob") (Just 2) (Just 2) (Just (ViaHence, 1))
      , Row FatePerformed (Just DMust) (Just "Bob") (Just 4) (Just 4) (Just (ViaHence, 1))
      ]

  it "2. a failure: effective is the missed deadline, observed is the revealing event; the LEST norm names its parent" do
    rs <- run True lestSrc
    map row (fatesOf 0 rs) `shouldBe`
      [ Row FateArmed (Just DMust) (Just "Alice") (Just 0) (Just 0) Nothing
      , Row (FateFailed FailedToLest) (Just DMust) (Just "Alice") (Just 3) (Just 5) Nothing
      , Row FateArmed (Just DMust) (Just "Alice") (Just 3) (Just 3) (Just (ViaLest, 1))
      , Row FatePerformed (Just DMust) (Just "Alice") (Just 5) (Just 5) (Just (ViaLest, 1))
      ]

  it "3. a bare LEST BREACH: the failure, then the breach, which takes the failed party (N7 rule 2)" do
    rs <- run True lestBreachSrc
    map row (fatesOf 0 rs) `shouldBe`
      [ Row FateArmed (Just DMust) (Just "Alice") (Just 0) (Just 0) Nothing
      , Row (FateFailed FailedToLest) (Just DMust) (Just "Alice") (Just 3) (Just 5) Nothing
      , Row FateBreached Nothing (Just "Alice") (Just 3) (Just 5) (Just (ViaLest, 1))
      ]

  it "4. one BREACH shared by two LESTs is logged once per reach, each with its own failed party (N7 rule 1)" do
    rs <- run True sharedBreachSrc
    let breaches = [ row e | e <- fatesOf 0 rs, e.neFate == FateBreached ]
    length breaches `shouldBe` 2
    map (.bearer) breaches `shouldMatchList` [Just "Alice", Just "Bob"]

  it "5a. a prohibition violated" do
    rs <- run True violatedSrc
    map ((.fate) . row) (fatesOf 0 rs) `shouldBe` [FateArmed, FateViolated, FateBreached]
    map ((.observed) . row) (fatesOf 0 rs) `shouldBe` [Just 0, Just 2, Just 2]

  it "5b. a prohibition kept: effective is the window's end, observed the event that showed it" do
    rs <- run True keptSrc
    map row (fatesOf 0 rs) `shouldBe`
      [ Row FateArmed (Just DMustNot) (Just "Alice") (Just 0) (Just 0) Nothing
      , Row FateKept (Just DMustNot) (Just "Alice") (Just 5) (Just 7) Nothing
      ]

  it "6a. a permission exercised" do
    rs <- run True exercisedSrc
    map ((.fate) . row) (fatesOf 0 rs) `shouldBe` [FateArmed, FateExercised]

  it "6b. a permission lapsed is not a failure" do
    rs <- run True lapsedSrc
    map ((.fate) . row) (fatesOf 0 rs) `shouldBe` [FateArmed, FateLapsed]

  it "7. a party the machine never forced is carried as written, not as nobody and not as unknown" do
    rs <- run True computedPartySrc
    -- the expiry is found from the event's stamp alone and, with no LEST, the
    -- party is never forced: every entry says so, and the clock of an entry
    -- armed on a trace with no events stays unknown
    map (.neBearer) (fatesOf 0 rs) `shouldBe` replicate 2 (WrittenBearer "theLandlord")
    map ((.effective) . row) (fatesOf 0 rs) `shouldBe` [Just 0, Just 5]
    map (.neFate) (fatesOf 0 rs) `shouldBe` [FateArmed, FateFailed FailedToBreach]
    map (.neBearer) (fatesOf 1 rs) `shouldBe` [WrittenBearer "theLandlord"]
    map (\ e -> (e.neEffective, e.neObserved)) (fatesOf 1 rs) `shouldBe` [(Nothing, Nothing)]

  it "8a. chained LESTs: each norm's parent is the norm whose LEST armed it" do
    rs <- run True chainSrc
    let es = fatesOf 0 rs
    map (.neFate) es `shouldBe`
      [ FateArmed, FateFailed FailedToLest, FateArmed, FateFailed FailedToLest, FateArmed, FatePerformed ]
    map parentOf es `shouldBe`
      [Nothing, Nothing, ownRef (es !! 0), ownRef (es !! 0), ownRef (es !! 2), ownRef (es !! 2)]
    map ((.origin) . row) (drop 2 es) `shouldBe`
      [ Just (ViaLest, 1), Just (ViaLest, 1), Just (ViaLest, 1), Just (ViaLest, 1) ]

  it "8b. a compound in a LEST: both operands are armed by the failed norm" do
    rs <- run True compoundLestSrc
    let es = fatesOf 0 rs
        armed = [ e | e <- es, e.neFate == FateArmed ]
    length armed `shouldBe` 3
    map parentOf armed `shouldBe` [Nothing, ownRef (es !! 0), ownRef (es !! 0)]
    map (fmap (.noBranch) . (.neOrigin)) (drop 1 armed) `shouldBe` [Just ViaLest, Just ViaLest]

  it "8c. a barrier: the shared HENCE hangs from the join's entry, which hangs from nothing; members are roots" do
    rs <- run True barrierSrc
    let es = fatesOf 0 rs
        join = [ e | e <- es, e.neFate == FateJoinReleased ]
        landlord = [ e | e <- es, e.neFate == FateArmed, e.neModal == Just DMust, e.neOrigin /= Nothing ]
    length join `shouldBe` 1
    length landlord `shouldBe` 1
    map parentOf landlord `shouldBe` map ownRef join
    map (fmap (.noBranch) . (.neOrigin)) landlord `shouldBe` [Just ViaHence]
    -- the members are roots, and each is armed once
    [ e.neOrigin | e <- es, e.neFate == FateArmed, e.neMember /= Nothing ] `shouldBe` [Nothing, Nothing]
    map (fmap (.nmIndex) . (.neMember)) [ e | e <- es, e.neFate == FatePerformed, e.neMember /= Nothing ]
      `shouldBe` [Just 1, Just 2]

  it "8d. a fork: each member's HENCE hangs from that member" do
    rs <- run True forkSrc
    let es = fatesOf 0 rs
        members = [ e | e <- es, e.neFate == FatePerformed, e.neMember /= Nothing ]
        children = [ e | e <- es, e.neFate == FateArmed, e.neOrigin /= Nothing ]
    length members `shouldBe` 2
    length children `shouldBe` 2
    map parentOf children `shouldBe` map ownRef members

  it "8e. an EVERY armed by a HENCE: its members, and a barrier's join, hang from the norm whose HENCE armed it" do
    forkRs <- run True everyAfterHenceForkSrc
    let fes = fatesOf 0 forkRs
        landlord = [ e | e <- fes, e.neFate == FatePerformed, e.neMember == Nothing ]
        members = [ e | e <- fes, e.neFate == FateArmed, e.neMember /= Nothing ]
    length landlord `shouldBe` 1
    length members `shouldBe` 2
    map parentOf members `shouldBe` map ownRef (landlord <> landlord)
    map (fmap (.noBranch) . (.neOrigin)) members `shouldBe` [Just ViaHence, Just ViaHence]
    barrierRs <- run True everyAfterHenceBarrierSrc
    let bes = fatesOf 0 barrierRs
        landlordB = [ e | e <- bes, e.neFate == FatePerformed, e.neMember == Nothing ]
        join = [ e | e <- bes, e.neFate == FateJoinReleased ]
    length join `shouldBe` 1
    map parentOf join `shouldBe` map ownRef landlordB

  it "9a. a bare BREACH on a HENCE path names nobody" do
    rs <- run True henceBreachSrc
    [ e.neBearer | e <- fatesOf 0 rs, e.neFate == FateBreached ] `shouldBe` [NobodyBearer]

  it "9b. a bare BREACH after a lapsed MAY names nobody: a lapse is no failure" do
    rs <- run True lapsedBreachSrc
    [ e.neBearer | e <- fatesOf 0 rs, e.neFate == FateBreached ] `shouldBe` [NobodyBearer]

  it "9c. BREACH BY keeps whom the drafter named, not the party that failed" do
    rs <- run True breachBySrc
    [ keyPrefix' e.neBearer | e <- fatesOf 0 rs, e.neFate == FateBreached ] `shouldBe` ["Bob"]

  it "9d. a bare BREACH under a barrier names nobody and hangs from the join's failure" do
    rs <- run True barrierSrc
    let es = fatesOf 1 rs
        join = [ e | e <- es, e.neFate == FateJoinFailed ]
        breaches = [ e | e <- es, e.neFate == FateBreached ]
    length join `shouldBe` 1
    map (.neBearer) breaches `shouldBe` [NobodyBearer]
    map parentOf breaches `shouldBe` map ownRef join
    -- the member that missed reports its failure to the join
    [ e.neFate | e <- es, e.neMember /= Nothing, e.neFate /= FateArmed, e.neFate /= FatePerformed ]
      `shouldBe` [FateFailed FailedToJoin]

  it "10. an obligation armed after its own deadline fails at its arming, not at the deadline it could not meet" do
    rs <- run True lateArmingSrc
    let es = fatesOf 0 rs
    [ (e.neEffective, e.neObserved) | e <- es, e.neFate == FateFailed FailedToBreach ]
      `shouldBe` [(Just 4, Just 5)]

  describe "properties of every entry" do
    for_ allSources \ (name, src) -> do
      it (name <> ": effective is never after observed (N3)") do
        rs <- run True src
        for_ (fatesOf 0 rs) \ e ->
          case (e.neEffective, e.neObserved) of
            (Just a, Just b) -> a `shouldSatisfy` (<= b)
            _                -> pure ()

      it (name <> ": every norm is armed exactly once and has at most one fate of its own") do
        rs <- run True src
        -- a join (an EVERY's own key) is not a norm that is armed, so it has
        -- no Armed entry; only its outcome
        let norms = [ (e.neNorm, e.neFate) | e <- fatesOf 0 rs, Just _ <- [e.neNorm], not (isJoinFate e.neFate) ]
            armedCount = length [ () | (_, FateArmed) <- norms ]
            normCount = length (uniq (map fst norms))
        armedCount `shouldBe` normCount

  describe "the writer is an observer (N6) and the log is separate (N5)" do
    for_ allSources \ (name, src) -> do
      it (name <> ": the writer changes no answer") do
        on <- run True src
        off <- run False src
        map (prettyEvalDirectiveResult . withoutNormLog) on `shouldBe` map prettyEvalDirectiveResult off

      it (name <> ": the writer leaves every party's ledger and the official record with no fate") do
        on <- run True src
        for_ on \ r -> do
          let own = concatMap toList (toList r.ledger.ownLedgers)
              official = toList r.ledger.officialLedger
          [ () | Fate _ <- own <> official ] `shouldBe` []

    it "mutant: a writer that also writes the official record turns the observer test red" do
      -- the proof that the test above can fail: with the deliberately wrong
      -- writer, the printed result is NOT the one the writer-off run prints
      on <- runWith (\ cfg -> cfg {normLog = True, normLogMutant = MutantOfficial}) henceSrc
      off <- run False henceSrc
      map (prettyEvalDirectiveResult . withoutNormLog) on `shouldNotBe` map prettyEvalDirectiveResult off

    it "mutant: a writer that evaluates a party nothing has asked for turns the observer test red" do
      -- GM's requirement for P1: the differential must fail on a writer that
      -- forces a thunk, not only on one that writes the wrong ledger
      on <- runWith (\ cfg -> cfg {normLog = True, normLogMutant = MutantForce}) unforcedPartySrc
      off <- run False unforcedPartySrc
      map (prettyEvalDirectiveResult . withoutNormLog) on `shouldNotBe` map prettyEvalDirectiveResult off
      -- and the real writer does not: the same run is unchanged
      real <- run True unforcedPartySrc
      map (prettyEvalDirectiveResult . withoutNormLog) real `shouldBe` map prettyEvalDirectiveResult off

    it "control: with the writer off, the norm ledger is empty" do
      rs <- run False henceSrc
      fatesOf 0 rs `shouldBe` []
  where
    uniq = foldr (\ x acc -> if x `elem` acc then acc else x : acc) []
