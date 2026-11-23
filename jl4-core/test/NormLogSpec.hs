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
import L4.Import.Resolution (ResolvedImport (..), TypeCheckWithDepsResult (..))
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
import L4.Syntax (DeonticModal (..))
import L4.TypeCheck.Types (CheckResult (..))
import L4.TracePolicy (apiDefaultPolicy)

import qualified Data.Text.IO as TextIO
import Control.Exception (evaluate)
import Control.Monad (forM, when)
import Data.Foldable (for_, toList)
import Data.List (findIndex, isSuffixOf, sort)
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import System.Directory (listDirectory)
import System.Environment (lookupEnv)
import System.Mem (getAllocationCounter)
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
      -- what @l4 run@ does: each import is evaluated first, and its
      -- environment is what the module's own definitions see. With an empty
      -- environment an imported definition is never evaluated, which is how
      -- the extra corpus once passed without running the writer over a
      -- single imported rule (review of P1, M1)
      importEnv <- mconcat <$> forM r.tcdResolvedImports \ ri ->
        fst <$> execEvalModuleWithEnv cfg ri.riTypeChecked.entityInfo mempty ri.riTypeChecked.program
      (_, results) <- execEvalModuleWithEnv cfg r.tcdEntityInfo importEnv r.tcdModule
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

-- | A fate of a norm instance in its own right: not its arming, not a join,
-- not a declared breach.
isNormFate :: Fate -> Bool
isNormFate = \case
  FatePerformed -> True
  FateFailed _  -> True
  FateViolated  -> True
  FateKept      -> True
  FateExercised -> True
  FateLapsed    -> True
  _             -> False

uniqueOf :: Eq a => [a] -> [a]
uniqueOf = foldr (\ x acc -> if x `elem` acc then acc else x : acc) []

isJoinFate :: Fate -> Bool
isJoinFate = \case
  FateJoinedFulfilled _ -> True
  FateJoinedBreached _  -> True
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

-- | A prologue with four parties, for the fixtures of the review of P1.
prologue4 :: [Text.Text]
prologue4 =
  [ "DECLARE Person IS ONE OF Alice, Bob, Carol, Dan"
  , "DECLARE Action IS ONE OF"
  , "  deliver"
  , "  pay HAS amount IS A NUMBER"
  , ""
  ]

-- review of P1, W4: a declared BREACH is reached while the clock of a norm
-- armed before it is still unforced; the norm's Armed entry must still come first
breachFirstSrc :: Text.Text
breachFirstSrc = Text.unlines $ prologue4 <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  (PARTY Alice MUST deliver WITHIN 3) RAND (BREACH BY Carol)"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Alice DOES deliver AT 1"
  ]

-- review of P1, W2: a LEST reached on an event long after the deadline; the
-- continuation's norm is armed at the missed deadline and SEEN on that event
lateRevealSrc :: Text.Text
lateRevealSrc = Text.unlines $ prologue4 <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  PARTY Alice MUST deliver WITHIN 3"
  , "  HENCE PARTY Bob MUST pay 50 WITHIN 10"
  , "  LEST PARTY Alice MUST pay 100 WITHIN 10"
  , "       LEST BREACH"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Bob DOES deliver AT 100"
  ]

-- review of P1, W3: compounds whose operands both miss, revealed by one event
randJoinSrc, rorJoinSrc, lestJoinSrc, nestedJoinSrc :: Text.Text
randJoinSrc = Text.unlines $ prologue4 <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  (PARTY Alice MUST deliver WITHIN 3) RAND (PARTY Bob MUST pay 1 WITHIN 5)"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Dan DOES deliver AT 10"
  ]
rorJoinSrc = Text.unlines $ prologue4 <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  (PARTY Alice MUST deliver WITHIN 3) ROR (PARTY Bob MUST pay 1 WITHIN 5)"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Dan DOES deliver AT 10"
  ]
lestJoinSrc = Text.unlines $ prologue4 <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  PARTY Carol MUST deliver WITHIN 3"
  , "  LEST ((PARTY Alice MUST pay 1 WITHIN 5) RAND (PARTY Bob MUST pay 2 WITHIN 5))"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Dan DOES deliver AT 20"
  ]
nestedJoinSrc = Text.unlines $ prologue4 <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  ((PARTY Alice MUST deliver WITHIN 3) RAND (PARTY Bob MUST pay 1 WITHIN 4))"
  , "  RAND ((PARTY Alice MUST pay 2 WITHIN 5) RAND (PARTY Bob MUST deliver WITHIN 6))"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY Dan DOES deliver AT 20"
  ]

-- review of P1, W3(e): an EVERY barrier met after its ONCE ... WITHIN deadline
barrierExpiredSrc :: Text.Text
barrierExpiredSrc = Text.unlines $ everyPrologue <>
  [ "GIVETH A DEONTIC Actor Action"
  , "c MEANS"
  , "    PARTY theLandlord MUST Deliver theLandlord WITHIN 1"
  , "    HENCE (EVERY Tenant t IN tenants"
  , "              MUST   Sign (EXACTLY t)"
  , "              WITHIN 14"
  , "              ONCE   ALL HAVE WITHIN 5"
  , "              HENCE  (PARTY theLandlord MUST Deliver theLandlord WITHIN 5)"
  , "              LEST   BREACH)"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY theLandlord DOES Deliver theLandlord AT 0"
  , "  PARTY alice DOES Sign alice AT 1"
  , "  PARTY bob DOES Sign bob AT 8"
  ]

-- review of P1, M1 and W1: a rule in an imported module, whose residual is
-- shared between directives
importLibSrc, importUserSrc :: Text.Text
importLibSrc = Text.unlines $ prologue4 <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  PARTY Alice MUST deliver WITHIN 3"
  , "  HENCE PARTY Bob MUST pay 50 WITHIN 10 LEST BREACH"
  , ""
  , "GIVETH DEONTIC Person Action"
  , "other MEANS"
  , "  PARTY Carol MUST deliver WITHIN 3"
  , "  LEST PARTY Dan MUST deliver WITHIN 30"
  , ""
  , "GIVETH DEONTIC Person Action"
  , "r MEANS EVALTRACE c 0 (LIST EVENT Alice deliver 1)"
  ]
importUserSrc = Text.unlines
  [ "IMPORT wlib"
  , ""
  , "#EVAL r"
  , "#EVAL EVALTRACE r 1 (LIST EVENT Bob (pay 50) 2)"
  , "#EVAL LIST (EVALTRACE other 0 (LIST EVENT Carol deliver 5)), (EVALTRACE r 1 (LIST EVENT Bob (pay 50) 2))"
  ]

-- review of P1, L1: a party that prints over more than one line
multilineSrc :: Text.Text
multilineSrc = Text.unlines
  [ "DECLARE Action IS ONE OF"
  , "  deliver"
  , "  pay HAS amount IS A NUMBER"
  , ""
  , "GIVETH DEONTIC STRING Action"
  , "c MEANS"
  , "  PARTY \"Alice\\n\" MUST deliver WITHIN 3"
  , ""
  , "#TRACE c AT 0 WITH"
  , "  PARTY \"Alice\\n\" DOES deliver AT 1"
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
  , ("every after hence (barrier)", everyAfterHenceBarrierSrc)
  , ("breach first", breachFirstSrc), ("late reveal", lateRevealSrc)
  , ("rand join", randJoinSrc), ("ror join", rorJoinSrc)
  , ("join in a lest", lestJoinSrc), ("nested joins", nestedJoinSrc)
  , ("barrier expired", barrierExpiredSrc) ]

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
      -- the positive control, one per file that runs a trace: a differential
      -- over a file that writes no fate would pass whatever the writer did,
      -- and a control for the directory as a whole is satisfied by one file
      -- and hides the others (review of P1, M1)
      for_ modules \ (name, src) -> when (any (\ l -> "#" `Text.isPrefixOf` l && "TRACE" `Text.isInfixOf` l) (Text.lines src)) do
        it (Text.unpack name <> ": it runs a trace, so the writer wrote fates there") do
          on <- runIn vfs (\ cfg -> cfg {normLog = True}) src
          length [ () | r <- on, Fate _ <- toList r.ledger.normLedger ] `shouldSatisfy` (> 0)

-- | The bytes this thread allocates evaluating a module's directives with the
-- writer off and on, from one type check, and the number of fates the writer
-- wrote.
evalAllocated :: Text.Text -> IO (Double, Double, Int)
evalAllocated src = do
  cfg0 <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
  case checkWithImports (vfsFromList []) src of
    Left errs -> fail ("the module failed to check: " <> show errs)
    Right r -> do
      let measure on = do
            a0 <- getAllocationCounter
            (_, results) <- execEvalModuleWithEnv (cfg0 {normLog = on}) r.tcdEntityInfo mempty r.tcdModule
            n <- evaluate (length (fatesOf 0 results))
            a1 <- getAllocationCounter
            pure (fromIntegral (a0 - a1) :: Double, n)
      -- the first evaluation of a type-checked module computes what its lazy
      -- parts hold once, so it is not the one that is counted
      _ <- measure False
      (off, _) <- measure False
      (on, n) <- measure True
      pure (off, on, n)

-- | An EVERY of @n@ tenants, each owing a payment with a HENCE and a LEST,
-- traced against no events: every member is armed with its clock still a
-- thunk, and logs a Waiting step.
everyEmptySrc :: Int -> Text.Text
everyEmptySrc n = Text.unlines $
  [ "DECLARE Actor IS ONE OF"
  , "    Landlord HAS name IS A STRING"
  , "    Tenant   HAS name IS A STRING"
  , "DECLARE Action IS ONE OF"
  , "    Pay     HAS payer  IS AN Actor"
  , "    Receipt HAS issuer IS AN Actor, to IS AN Actor"
  , ""
  , "ll MEANS Landlord OF \"L\""
  ]
  <> [ "t" <> i <> " MEANS Tenant OF \"T" <> i <> "\"" | k <- [0 .. n - 1], let i = Text.pack (show k) ]
  <> [ "tenants MEANS LIST " <> Text.intercalate ", " [ "t" <> Text.pack (show k) | k <- [0 .. n - 1] ]
     , ""
     , "GIVETH A DEONTIC Actor Action"
     , "receipts MEANS"
     , "    EVERY Tenant t IN tenants"
     , "        MUST   Pay t"
     , "        WITHIN 100000"
     , "        UPON   EACH"
     , "        HENCE  (PARTY ll MUST Receipt ll t WITHIN 5)"
     , "        LEST   BREACH BY t"
     , ""
     , "#TRACE receipts AT 0 WITH"
     ]

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
      , Row FateArmed (Just DMust) (Just "Alice") (Just 3) (Just 5) (Just (ViaLest, 1))
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

  describe "the review of P1 (2026-11-23)" do
    let importVfs = vfsFromList [("wlib", importLibSrc)]
        runImports = runIn importVfs (\ cfg -> cfg {normLog = True}) importUserSrc

    it "M1: an imported rule is evaluated, so the writer runs over it" do
      rs <- runImports
      length rs `shouldBe` 3
      length (fatesOf 0 rs) `shouldSatisfy` (> 0)

    it "W1: a residual defined in an imported module does not take a parent from another directive's hand-offs" do
      rs <- runImports
      -- the one LEST hand-off in the third directive is Carol's, and Dan's norm hangs from it
      [ o.noBranch | e <- fatesOf 2 rs, e.neFate == FateArmed, keyPrefix' e.neBearer == "Dan", Just o <- [e.neOrigin] ]
        `shouldBe` [ViaLest]
      -- Bob's norm was armed by Alice's HENCE when the residual was first made,
      -- in another evaluation; this directive must not read that hand-off as its own
      let bob = [ e.neOrigin | e <- fatesOf 2 rs, keyPrefix' e.neBearer == "Bob" ]
      length bob `shouldSatisfy` (> 0)
      bob `shouldBe` map (const Nothing) bob

    it "W4: a declared BREACH reached before a norm's clock is forced is written after that norm's Armed entry" do
      rs <- run True breachFirstSrc
      let fates = map (.neFate) (fatesOf 0 rs)
      length (filter (== FateBreached) fates) `shouldBe` 1
      findIndex (== FateArmed) fates `shouldSatisfy` (< findIndex (== FateBreached) fates)

    it "W2: a norm armed by a LEST is armed at the missed deadline and seen on the event that revealed the miss" do
      rs <- run True lateRevealSrc
      [ (e.neFate, e.neEffective, e.neObserved) | e <- fatesOf 0 rs ] `shouldBe`
        [ (FateArmed, Just 0, Just 0)
        , (FateFailed FailedToLest, Just 3, Just 100)
        , (FateArmed, Just 3, Just 100)
        , (FateFailed FailedToLest, Just 13, Just 100)
        , (FateBreached, Just 13, Just 100) ]

    it "W3a: a compound's breach is dated along its operands: RAND at the earlier effective instant, ROR at the later" do
      randRs <- run True randJoinSrc
      rorRs <- run True rorJoinSrc
      [ (e.neFate, e.neEffective, e.neObserved) | e <- fatesOf 0 randRs, isJoinFate e.neFate ]
        `shouldBe` [(FateJoinedBreached JoinAnd, Just 3, Just 10)]
      [ (e.neFate, e.neEffective, e.neObserved) | e <- fatesOf 0 rorRs, isJoinFate e.neFate ]
        `shouldBe` [(FateJoinedBreached JoinOr, Just 5, Just 10)]

    it "W3b: a compound armed by a LEST hangs from the norm whose LEST armed it, as its operands do" do
      rs <- run True lestJoinSrc
      let es = fatesOf 0 rs
          joins = [ e | e <- es, isJoinFate e.neFate ]
          operands = [ e | e <- es, e.neFate == FateArmed, e.neOrigin /= Nothing ]
      length joins `shouldBe` 1
      length operands `shouldBe` 2
      map (.neOrigin) joins `shouldBe` take 1 (map (.neOrigin) operands)
      map (.neOrigin) joins `shouldNotBe` [Nothing]

    it "W3c: two compounds in one trace are two joins, each with a site" do
      rs <- run True nestedJoinSrc
      let joins = [ e | e <- fatesOf 0 rs, isJoinFate e.neFate ]
      length joins `shouldBe` 3
      length (uniqueOf (map (.neNorm) joins)) `shouldBe` 3
      [ e.neNorm >>= (.nrSite) | e <- joins ] `shouldSatisfy` all (/= Nothing)

    it "W3d: a barrier's join names nobody as its bearer" do
      rs <- run True barrierSrc
      [ e.neBearer | d <- [0, 1], e <- fatesOf d rs, e.neFate `elem` [FateJoinReleased, FateJoinFailed] ]
        `shouldBe` [NobodyBearer, NobodyBearer]

    it "W3e: a barrier's failure has the instants of the member failure that caused it; an expiry is at the ONCE deadline and seen at the last completion" do
      rs <- run True barrierSrc
      let es = fatesOf 1 rs
      [ (e.neEffective, e.neObserved) | e <- es, e.neFate == FateJoinFailed ]
        `shouldBe` [ (e.neEffective, e.neObserved) | e <- es, e.neFate == FateFailed FailedToJoin ]
      [ (e.neEffective, e.neObserved) | e <- es, e.neFate == FateJoinFailed ] `shouldBe` [(Just 14, Just 20)]
      expired <- run True barrierExpiredSrc
      [ (e.neEffective, e.neObserved) | e <- fatesOf 0 expired, e.neFate == FateJoinExpired ]
        `shouldBe` [(Just 5, Just 8)]

    -- The writer's cost must be linear in the norms it writes. An EVERY of N
    -- members traced with no events logs one Waiting step per member, and each
    -- step walked the whole list of Armed rows still waiting on a clock (all N
    -- of them): +346 MB at 800 members and +3,903 MB at 3,200, 11.3 times the
    -- excess for a step of 4 in N (the reviewers' figures, on their build). A step
    -- that writes no fate has nothing to put the waiting rows before, so it
    -- no longer walks them.
    --
    -- Counted in the bytes this thread allocates, as ConsiderScaleSpec does:
    -- the writer's excess is the evaluation with the writer on less the same
    -- evaluation with it off, from one type check. Linear is 4 for a step of
    -- 4 in N, quadratic 16.
    it "S2/cost: the writer's allocation on an EVERY with no events grows linearly in its members" do
      _ <- evalAllocated (everyEmptySrc 1)
      (off1, on1, n1) <- evalAllocated (everyEmptySrc 400)
      (off2, on2, n2) <- evalAllocated (everyEmptySrc 1600)
      -- the writer wrote the Armed rows it is being measured for
      (n1 >= 400, n2 >= 1600) `shouldBe` (True, True)
      let excess1 = on1 - off1
          excess2 = on2 - off2
      excess1 `shouldSatisfy` (> 0)
      excess2 / excess1 `shouldSatisfy` (< 6)

    it "L1: a bearer that prints over several lines still prints one row per line" do
      rs <- run True multilineSrc
      let ls = Text.lines (prettyEvalDirectiveResult (rs !! 0))
          block = filter (not . Text.null . Text.strip) (drop 1 (dropWhile (\ l -> Text.strip l /= "Norm log:") ls))
      length block `shouldSatisfy` (> 0)
      for_ block \ l -> Text.strip l `shouldSatisfy` ("FATE " `Text.isPrefixOf`)

  describe "properties of every entry" do
    for_ allSources \ (name, src) -> do
      it (name <> ": effective is never after observed (N3)") do
        rs <- run True src
        for_ (fatesOf 0 rs) \ e ->
          case (e.neEffective, e.neObserved) of
            (Just a, Just b) -> a `shouldSatisfy` (<= b)
            _                -> pure ()

      it (name <> ": a norm's Armed entry comes before any other fate of it") do
        rs <- run True src
        let indexed = zip [0 :: Int ..] (fatesOf 0 rs)
        for_ indexed \ (i, e) ->
          for_ e.neNorm \ r -> when (e.neFate /= FateArmed && not (isJoinFate e.neFate)) do
            [ j | (j, a) <- indexed, a.neFate == FateArmed, a.neNorm == Just r ] `shouldSatisfy` any (< i)

      -- The fate of a norm (performed, failed, violated, kept, exercised,
      -- lapsed) is written where the machine sees it, so its observed stamp
      -- never goes backwards. The other rows are not so ordered, each for its
      -- own reason (see 'neObserved'): an Armed entry is written when the
      -- machine first forces the clock the norm was armed at, which can be
      -- after a fate of another norm with a later stamp; a compound's or a
      -- declared BREACH's instants are SEESAW's, the earliest moment the
      -- breach could be known, which can be earlier than the rows written
      -- before it. A reader that windows on time orders by (observed, log
      -- position).
      it (name <> ": the fates of norms never go backwards in observed time") do
        rs <- run True src
        let observed = [ o | e <- fatesOf 0 rs, isNormFate e.neFate, Just o <- [e.neObserved] ]
        observed `shouldBe` sort observed

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
