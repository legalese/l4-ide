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
import Base (Uri (..), toNormalizedUri)

import L4.API.VirtualFS (VFS, vfsFromList, checkWithImports)
import L4.Import.Resolution (ResolvedImport (..), TypeCheckWithDepsResult (..))
import L4.Evaluate.Ledger (LedgerEvent (..), LedgerStore (..))
import L4.Evaluate.NormLog
import L4.Evaluate.NormLog.Read
  ( BearerPattern (..), BranchPattern (..), NormPattern (..), NormState (..), NormView (..), Refusal (..)
  , anyNorm, isCured, readNorms )
import L4.EvaluateLazy
  ( EvalConfig (..)
  , EvalDirectiveResult (..)
  , NormLogMutant (..)
  , execEvalModuleWithEnv
  , prettyEvalDirectiveResult
  , resolveEvalConfig
  )
import L4.Parser (execProgramParserWithHintPass)
import L4.Syntax (DeonticModal (..), RawName (..), moduleReadsNormLog)
import L4.TypeCheck.Types (AnchorRefusal (..), CheckResult (..), CheckErrorWithContext (..), CheckError (..), CheckWarning (..), ReadRefusal (..))
import L4.TracePolicy (apiDefaultPolicy)

import qualified Data.Text.IO as TextIO
import Control.Exception (evaluate)
import Control.DeepSeq (rnf)
import Control.Monad (forM, when)
import Data.Foldable (for_, toList)
import Data.Int (Int32)
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

-- review of P1, re-verification (np10): a residual that a hand-off armed is
-- armed again, in another trace. The hand-off's stamp belongs to the trace it
-- came from: in this one there is no event at 5, or at 1.
retraceSrc :: Text.Text
retraceSrc = Text.unlines $ prologue4 <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  PARTY Alice MUST deliver WITHIN 3"
  , "  LEST PARTY Bob MUST pay 2 WITHIN 10"
  , ""
  , "GIVETH DEONTIC Person Action"
  , "r MEANS EVALTRACE c 0 (LIST EVENT Carol deliver 5)"
  , ""
  , "#EVAL EVALTRACE r 9 (LIST EVENT Bob (pay 2) 12)"
  , ""
  , "GIVETH DEONTIC Person Action"
  , "h MEANS"
  , "  PARTY Alice MUST deliver WITHIN 3"
  , "  HENCE PARTY Bob MUST pay 2 WITHIN 10"
  , ""
  , "GIVETH DEONTIC Person Action"
  , "rh MEANS EVALTRACE h 0 (LIST EVENT Alice deliver 1)"
  , ""
  , "#EVAL EVALTRACE rh 9 (LIST EVENT Bob (pay 2) 12)"
  ]

-- the same residual, defined in an imported module and re-traced twice, and a
-- user whose only directive names it
retraceLibSrc, retraceUserSrc, holeUserSrc :: Text.Text
retraceLibSrc = Text.unlines $ prologue4 <>
  [ "GIVETH DEONTIC Person Action"
  , "c MEANS"
  , "  PARTY Alice MUST deliver WITHIN 3"
  , "  LEST PARTY Bob MUST pay 2 WITHIN 10"
  , ""
  , "GIVETH DEONTIC Person Action"
  , "r MEANS EVALTRACE c 0 (LIST EVENT Carol deliver 5)"
  ]
retraceUserSrc = Text.unlines
  [ "IMPORT rtlib"
  , ""
  , "#EVAL EVALTRACE r 0 (LIST EVENT Bob (pay 2) 7)"
  , "#EVAL EVALTRACE r 0 (LIST EVENT Bob (pay 2) 7)"
  ]
holeUserSrc = Text.unlines
  [ "IMPORT rtlib"
  , ""
  , "#EVAL r"
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
  , ("barrier expired", barrierExpiredSrc), ("retrace", retraceSrc) ]

-- | Whether a file of the corpus runs a trace, so that the writer should write
-- a fate there: it has a directive, and a trace is run in it or in a module it
-- imports, however far back. A file whose only directive is @#EVAL r@, with
-- @r@ an @EVALTRACE@ in an imported module, writes fates, and had no control
-- (re-verification of P1). The test is on the text, so it can be wrong in the
-- other direction: a file that imports a module with a trace and never forces
-- it is called a trace here, and its control fails; that is a file to look at.
runsATrace :: [(Text.Text, Text.Text)] -> (Text.Text, Text.Text) -> Bool
runsATrace modules (_, src) =
  any ("#" `Text.isPrefixOf`) (Text.lines src)
    && any (Text.isInfixOf "TRACE") (src : [ t | m <- closure, Just t <- [lookup m modules] ])
  where
    importsIn t = [ Text.strip rest | l <- Text.lines t, Just rest <- [Text.stripPrefix "IMPORT " (Text.strip l)] ]
    closure = go [] (importsIn src)
    go seen [] = seen
    go seen (m : todo)
      | m `elem` seen = go seen todo
      | otherwise = go (m : seen) (todo <> maybe [] importsIn (lookup m modules))

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
      for_ modules \ (name, src) -> when (runsATrace modules (name, src)) do
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

    -- the Armed entries of Bob's norm in the n-th directive: when it took
    -- effect, when it was seen, and how it was armed
    let bobArmed d rs =
          [ (e.neEffective, e.neObserved, (.noBranch) <$> e.neOrigin)
          | e <- fatesOf d rs, e.neFate == FateArmed, keyPrefix' e.neBearer == "Bob" ]

    it "W2b: a residual armed by a hand-off is armed again at its new clock, and the hand-off's stamp is not carried into the new trace" do
      rs <- run True retraceSrc
      length rs `shouldBe` 2
      for_ [0, 1] \ d -> for_ (fatesOf d rs) \ e -> case (e.neEffective, e.neObserved) of
        (Just a, Just b) -> a `shouldSatisfy` (<= b)
        _                -> pure ()
      -- armed by a LEST at the missed deadline 3, seen at 5; armed again at 9
      bobArmed 0 rs `shouldBe` [(Just 3, Just 5, Just ViaLest), (Just 9, Just 9, Just ViaLest)]
      -- armed by a HENCE at 1; armed again at 9
      bobArmed 1 rs `shouldBe` [(Just 1, Just 1, Just ViaHence), (Just 9, Just 9, Just ViaHence)]

    it "W2c: an imported residual re-traced in two identical directives is armed at the same instants in both" do
      rs <- runIn (vfsFromList [("rtlib", retraceLibSrc)]) (\ cfg -> cfg {normLog = True}) retraceUserSrc
      length rs `shouldBe` 2
      let instants d = [ (a, b) | (a, b, _) <- bobArmed d rs ]
      -- the first directive makes the residual, then re-traces it; the second
      -- only re-traces it, and its parent link is another evaluation's (W1)
      instants 0 `shouldBe` [(Just 3, Just 5), (Just 0, Just 0)]
      instants 1 `shouldBe` [(Just 0, Just 0)]

    it "M1b: the extra corpus's control reaches a file whose only trace is an imported EVALTRACE" do
      let modules = [("rtlib", retraceLibSrc), ("rtuser", holeUserSrc)]
      runsATrace modules ("rtuser", holeUserSrc) `shouldBe` True
      runsATrace modules ("rtlib", retraceLibSrc) `shouldBe` False
      -- and the file does write fates, which is what the control asks of it
      rs <- runIn (vfsFromList modules) (\ cfg -> cfg {normLog = True}) holeUserSrc
      length (fatesOf 0 rs) `shouldSatisfy` (> 0)

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

    -- NORM-LOG-SPEC P2: two things a read of the log needs and P1 did not write

    it "R1: an operand's entry names the compound it is armed inside, and a compound's names the one it sits in (N13)" do
      rs <- run True nestedJoinSrc
      let es = fatesOf 0 rs
          joins = [ e | e <- es, isJoinFate e.neFate ]
          armed = [ e | e <- es, e.neFate == FateArmed ]
          outers = [ e | e <- joins, null e.neEnclosing ]
          inners = [ e | e <- joins, not (null e.neEnclosing) ]
      length outers `shouldBe` 1
      length inners `shouldBe` 2
      -- the two inner compounds sit in the one outer
      let outerRefs = [ r | o <- outers, Just r <- [o.neNorm] ]
      length outerRefs `shouldBe` 1
      map (.neEnclosing) inners `shouldBe` [outerRefs, outerRefs]
      -- each of the four operands is armed inside the inner compound it belongs
      -- to, two to each, and inside the outer one: innermost first
      length armed `shouldBe` 4
      [ length [ a | a <- armed, Just r <- [i.neNorm], a.neEnclosing == r : outerRefs ] | i <- inners ] `shouldBe` [2, 2]

    it "R2: a norm outside every compound has no enclosing compound, and a compound in a LEST names none either" do
      hs <- run True henceSrc
      map (.neEnclosing) (fatesOf 0 hs) `shouldSatisfy` all null
      rs <- run True lestJoinSrc
      let es = fatesOf 0 rs
          joins = [ e | e <- es, isJoinFate e.neFate ]
          operands = [ e | e <- es, e.neFate == FateArmed, e.neOrigin /= Nothing ]
          carol = [ e | e <- es, e.neFate == FateArmed, e.neOrigin == Nothing ]
      map (.neEnclosing) joins `shouldBe` [[]]
      map (.neEnclosing) carol `shouldBe` [[]]
      let joinRefs = [ r | j <- joins, Just r <- [j.neNorm] ]
      length joinRefs `shouldBe` 1
      map (.neEnclosing) operands `shouldBe` [joinRefs, joinRefs]

    it "R3: an entry carries the constructor of its action, from the syntax (N2)" do
      rs <- run True randJoinSrc
      let es = fatesOf 0 rs
      sort [ e.neActionHead | e <- es, e.neFate == FateArmed ] `shouldBe` [Just "deliver", Just "pay"]
      [ e.neActionHead | e <- es, isJoinFate e.neFate ] `shouldBe` [Nothing]
      [ e.neActionHead | e <- es, e.neFate == FateBreached ] `shouldBe` []

    -- NORM-LOG-SPEC N4 (P2): THE INSTANT, the contract clock inside a guard

    it "I1: THE INSTANT in a PROVIDED guard is the stamp of the event being matched, not the arming" do
      let src = Text.unlines $ prologue4 <>
            [ "GIVETH DEONTIC Person Action"
            , "c MEANS"
            , "  PARTY Alice MUST pay n PROVIDED n = THE INSTANT"
            , "  WITHIN 10"
            , ""
            , "#TRACE c AT 0 WITH"
            , "  PARTY Alice DOES pay 3 AT 3"
            , ""
            , "#TRACE c AT 0 WITH"
            , "  PARTY Alice DOES pay 5 AT 3"
            , ""
            , "#TRACE c AT 0 WITH"
            , "  PARTY Alice DOES pay 0 AT 3"
            ]
      rs <- run True src
      -- armed at 0, the act is seen at 3: the guard holds only for 3
      [ (e.neFate, e.neObserved) | e <- fatesOf 0 rs, isNormFate e.neFate ] `shouldBe` [(FatePerformed, Just 3)]
      [ e.neFate | e <- fatesOf 1 rs, isNormFate e.neFate ] `shouldBe` []
      -- and 0, the arming instant, is not it
      [ e.neFate | e <- fatesOf 2 rs, isNormFate e.neFate ] `shouldBe` []

    it "I2: THE INSTANT reads the same with the writer off" do
      let src = Text.unlines $ prologue4 <>
            [ "GIVETH DEONTIC Person Action"
            , "c MEANS"
            , "  PARTY Alice MUST pay n PROVIDED n = THE INSTANT"
            , "  WITHIN 10"
            , ""
            , "#TRACE c AT 0 WITH"
            , "  PARTY Alice DOES pay 3 AT 3"
            ]
      on <- run True src
      off <- run False src
      map prettyEvalDirectiveResult off `shouldBe` map (prettyEvalDirectiveResult . withoutNormLog) on

    it "I3: THE INSTANT is refused outside a guard, as a value and as an anchor" do
      let refused body = case checkWithImports (vfsFromList []) (Text.unlines (prologue4 <> body)) of
            Left _  -> False
            Right r -> not (null [ () | e <- r.tcdErrors, LifecycleUnavailable _ _ InstantOutsideGuard <- [e.kind] ])
      refused [ "GIVETH A NUMBER", "t MEANS THE INSTANT" ] `shouldBe` True
      refused [ "GIVETH DEONTIC Person Action", "c MEANS PARTY Alice MUST deliver WITHIN 5 OF THE INSTANT" ] `shouldBe` True
      -- the body of a function is not a guard, even when a guard calls it
      refused [ "GIVEN n IS A NUMBER", "GIVETH A BOOLEAN", "late n MEANS n > THE INSTANT" ] `shouldBe` True
      -- and the one place it is allowed is accepted
      case checkWithImports (vfsFromList [])
             (Text.unlines (prologue4 <>
               [ "GIVETH DEONTIC Person Action"
               , "c MEANS"
               , "  PARTY Alice MUST pay n PROVIDED n = THE INSTANT"
               , "  WITHIN 10"
               ])) of
        Left errs -> expectationFailure ("a guard may read THE INSTANT: " <> show errs)
        Right r   -> r.tcdSuccess `shouldBe` True

    it "I4: NOW in a PROVIDED draws a warning that it is the wall clock, and THE INSTANT draws none (N4)" do
      let guarded g = Text.unlines $ prologue4 <>
            [ "GIVETH DEONTIC Person Action"
            , "c MEANS"
            , "  PARTY Alice MUST pay n PROVIDED " <> g
            , "  WITHIN 10"
            ]
          nowWarnings src = case checkWithImports (vfsFromList []) src of
            Left errs -> error ("typecheck failed: " <> show errs)
            Right r   -> length [ () | e <- r.tcdErrors, CheckWarning (NowInGuard _ _) <- [e.kind] ]
      nowWarnings (guarded "n > NOW") `shouldBe` 1
      -- TODAY and CURRENTTIME read the same clock
      nowWarnings (guarded "TODAY = TODAY") `shouldBe` 2
      nowWarnings (guarded "CURRENTTIME = CURRENTTIME") `shouldBe` 2
      nowWarnings (guarded "n = THE INSTANT") `shouldBe` 0

    -- NORM-LOG-SPEC P2, the review of the first half (2026-11-24): the reader on
    -- real traces, with the writer on. The reviewer's probes, as fixtures.

    describe "carrier addresses fit a 32-bit Int (the WASM target)" do
      -- CI's WASM job found `negate (2^40 + h)` in the first half of P2: an Int
      -- is 32 bits there, and neither the native build nor the gate builds it
      let lo = toInteger (minBound :: Int32)
          hi = toInteger (maxBound :: Int32)
          fits a = lo <= toInteger a && toInteger a <= hi
          originEdges  = [0, 1, 2, 1000, 1000000, originCarrierLimit - 2, originCarrierLimit - 1]
          instantEdges = [0, 1, 2, 1000, 1000000, instantCarrierLimit - 2, instantCarrierLimit - 1]
      it "every carrier address is a negative number inside an Int32" do
        for_ originEdges \ n -> case originCarrierAddress n of
          Just a  -> (n, fits a, a < 0) `shouldBe` (n, True, True)
          Nothing -> expectationFailure ("no address for origin carrier " <> show n)
        for_ instantEdges \ k -> case instantCarrierAddress k of
          Just a  -> (k, fits a, a < 0) `shouldBe` (k, True, True)
          Nothing -> expectationFailure ("no address for instant carrier " <> show k)
      it "no instant carrier's address is an origin carrier's, and neither is a supply address" do
        for_ originEdges \ n -> for_ instantEdges \ k ->
          (originCarrierAddress n, instantCarrierAddress k) `shouldSatisfy` \ case
            (Just o, Just i) -> i < o && o < 0
            _                -> False
      it "within one half, each index has its own address" do
        [ originCarrierAddress n | n <- [0 .. 5] ] `shouldBe` map Just [-1, -2, -3, -4, -5, -6]
        [ instantCarrierAddress k | k <- [0 .. 2] ] `shouldBe` map Just [-1073741824, -1073741825, -1073741826]
      it "running out of a half is a refusal, never a wrap into the other half" do
        originCarrierAddress originCarrierLimit `shouldBe` Nothing
        originCarrierAddress (-1) `shouldBe` Nothing
        instantCarrierAddress instantCarrierLimit `shouldBe` Nothing
        instantCarrierAddress (-1) `shouldBe` Nothing
        -- the last of each is the edge of its half
        originCarrierAddress (originCarrierLimit - 1) `shouldBe` Just (-1073741823)
        instantCarrierAddress (instantCarrierLimit - 1) `shouldBe` Just (-2147483647)

    -- NORM-LOG-SPEC N4b: the read as written. Built by Claude 2026-11-24 as the
    -- fallback of the card's option A, decided pending Meng's review.
    describe "N4b: the read as written (the fallback spelling)" do
      let tracePrologue = prologue4 <> ["GIVETH DEONTIC Person Action"]
          src body = Text.unlines (tracePrologue <> body)
          errorsOf body = case checkWithImports (vfsFromList []) (src body) of
            Left _  -> Nothing
            Right r -> Just r.tcdErrors
          checked body = fmap null (errorsOf body) == Just True
          refusals body = case errorsOf body of
            Just es -> [ r | e <- es, ReadNormRefused r _ <- [e.kind] ]
            Nothing -> []
          performed rs i = not (null [ () | e <- fatesOf i rs, e.neFate == FatePerformed, e.neActionHead == Just "pay" ])
          -- does the guard hold at the event of trace 0?
          holds body = do { rs <- run False (src body); pure (performed rs 0) }
          lestPay g =
            [ "c MEANS"
            , "  PARTY Alice MUST deliver WITHIN 3"
            , "  LEST (PARTY Alice MUST pay n PROVIDED " <> g <> " WITHIN 10)"
            , "#TRACE c AT 0 WITH"
            , "  PARTY Alice DOES pay 1 AT 5"
            ]

      it "R1: EVER FAILED, read in a guard, is true once the norm failed, and the guard decides the event" do
        checked (lestPay "EVER FAILED (PARTY Alice MUST deliver)") `shouldBe` True
        holds (lestPay "EVER FAILED (PARTY Alice MUST deliver)") `shouldReturn` True
        holds (lestPay "NOT EVER FAILED (PARTY Alice MUST deliver)") `shouldReturn` False

      it "R2: PARTY _ matches any party, a named party only its own norms, and UNDER LEST narrows to the reparation's branch" do
        holds (lestPay "EVER FAILED (PARTY _ MUST deliver)") `shouldReturn` True
        holds (lestPay "EVER FAILED (PARTY Bob MUST deliver)") `shouldReturn` False
        -- deliver was armed from the top level, so under LEST there is none
        holds (lestPay "EVER FAILED (PARTY Alice MUST deliver UNDER LEST)") `shouldReturn` False
        holds (lestPay "EVER FAILED (PARTY Alice MAY deliver)") `shouldReturn` False

      it "R3: AS OF reads the past: a norm performed at 4 was still outstanding as of 2, and not as of 5" do
        let asOf t =
              [ "c MEANS"
              , "  PARTY Alice MUST deliver WITHIN 10"
              , "  HENCE (PARTY Alice MUST pay n PROVIDED OUTSTANDING (PARTY Alice MUST deliver) AS OF " <> t <> " WITHIN 10)"
              , "#TRACE c AT 0 WITH"
              , "  PARTY Alice DOES deliver AT 4"
              , "  PARTY Alice DOES pay 1 AT 6"
              ]
        holds (asOf "2") `shouldReturn` True
        holds (asOf "5") `shouldReturn` False

      it "R4: from inside a reparation's own continuation a failure is not yet cured, because the continuation includes the rule asking" do
        let inside w =
              [ "c MEANS"
              , "  PARTY Alice MUST deliver WITHIN 3"
              , "  LEST (PARTY Alice MUST pay n WITHIN 10"
              , "        HENCE (PARTY Alice MUST pay m PROVIDED " <> w <> " (PARTY Alice MUST deliver) WITHIN 10))"
              , "#TRACE c AT 0 WITH"
              , "  PARTY Alice DOES pay 1 AT 5"
              , "  PARTY Alice DOES pay 2 AT 6"
              ]
            both rs = (length [ () | e <- fatesOf 0 rs, e.neFate == FatePerformed ])
        rsA <- run False (src (inside "FAILED AND NOT CURED"))
        rsB <- run False (src (inside "CURED BY REPARATION"))
        -- the first pay is performed in either; the second only where the read holds
        both rsA `shouldBe` 2
        both rsB `shouldBe` 1

      it "R5: a read where it has no answer is a check error that says why" do
        refusals (lestPay "TRUE") `shouldBe` []
        -- outside a guard, with no AS OF
        let aSite = "c MEANS PARTY Alice MUST deliver WITHIN 3"
        refusals [ aSite, "x MEANS OUTSTANDING (PARTY Alice MUST deliver)" ] `shouldBe` [ReadNoInstant]
        -- with AS OF it has an instant
        refusals [ aSite, "x MEANS OUTSTANDING (PARTY Alice MUST deliver) AS OF 3" ] `shouldBe` []
        -- inside a RAND operand
        refusals
          [ "c MEANS"
          , "  (PARTY Alice MUST deliver WITHIN 3)"
          , "  RAND (PARTY Bob MUST pay n PROVIDED OUTSTANDING (PARTY Alice MUST deliver) WITHIN 10)"
          ] `shouldBe` [ReadInOperand]
        -- the wrong number of _ for the constructor's fields
        refusals (lestPay "OUTSTANDING (PARTY Alice MUST pay _ _)") `shouldBe` [ReadArity (NormalName "pay") 1 2]
        refusals (lestPay "OUTSTANDING (PARTY Alice MUST pay)") `shouldBe` [ReadArity (NormalName "pay") 1 0]

      it "R7: a wildcard outside a read is refused by name, not left to a bare 'unexpected'" do
        let wild = src [ "x MEANS _" ]
        case checkWithImports (vfsFromList []) wild of
          Left msgs -> Text.unlines msgs `shouldSatisfy` Text.isInfixOf "wildcard of a norm-log read pattern"
          Right _   -> expectationFailure "a lone _ was accepted"

      it "R9: a read whose pattern matches no norm of the module is a check error, and one that might match is not" do
        let site = [ "c MEANS PARTY Alice MUST deliver WITHIN 3"
                   , "d MEANS PARTY Alice MUST pay n PROVIDED OUTSTANDING (PARTY Alice MAY deliver) AS OF 1 WITHIN 3"
                   ]
        -- the modal differs: deliver is only ever MUST
        refusals site `shouldBe` [ReadMatchesNoSite (NormalName "deliver")]
        -- the same modal matches
        refusals [ "c MEANS PARTY Alice MUST deliver WITHIN 3"
                 , "d MEANS PARTY Alice MUST pay n PROVIDED OUTSTANDING (PARTY Alice MUST deliver) AS OF 1 WITHIN 3" ] `shouldBe` []
        -- a norm armed in a continuation is a site too
        refusals [ "c MEANS PARTY Alice MUST pay n WITHIN 3 HENCE (PARTY Bob MAY deliver)"
                 , "d MEANS PARTY Alice MUST pay n PROVIDED OUTSTANDING (PARTY Bob MAY deliver) AS OF 1 WITHIN 3" ] `shouldBe` []
        -- a norm whose action is not a constructor is taken to match any pattern
        refusals [ "GIVEN a IS AN Action"
                 , "c MEANS PARTY Alice MAY a WITHIN 3"
                 , "d MEANS PARTY Alice MUST pay n PROVIDED OUTSTANDING (PARTY Alice MAY deliver) AS OF 1 WITHIN 3" ] `shouldBe` []

      it "R10: a read in an imported module does not switch the record on, and stops with a named error, not an answer from an empty log" do
        let lib = Text.unlines $ prologue4 <>
              [ "GIVETH DEONTIC Person Action"
              , "c MEANS PARTY Alice MUST deliver WITHIN 3"
              , ""
              , "GIVETH A BOOLEAN"
              , "failedAlready MEANS EVER FAILED (PARTY Alice MUST deliver) AS OF 10"
              ]
            user = Text.unlines
              [ "IMPORT rlib"
              , "GIVETH DEONTIC Person Action"
              , "d MEANS"
              , "  PARTY Alice MUST deliver WITHIN 3"
              , "  LEST (PARTY Alice MUST pay n PROVIDED failedAlready WITHIN 10)"
              , "#TRACE d AT 0 WITH"
              , "  PARTY Alice DOES pay 1 AT 5"
              ]
        rs <- runIn (vfsFromList [("rlib", lib)]) id user
        Text.pack (show (map (.result) rs)) `shouldSatisfy` Text.isInfixOf "switched off"

      it "R11: a phrase applied to a bracketed event is still an application; applied to a bracketed regulative it is a read" do
        let parsed body = case execProgramParserWithHintPass uri (Text.unlines body) of
              Left errs -> error ("the module did not parse: " <> show errs)
              Right (m, _, _) -> m
            uri = toNormalizedUri (Uri "file:///norm-log-r11")
            isRead m = "ReadNorm" `Text.isInfixOf` Text.pack (show m)
            -- an event has a party and an action, and no modal
            event w = [ "x MEANS " <> w <> " (PARTY Tenant DOES pay AT 30)" ]
        for_ [ "OUTSTANDING", "EVER FAILED", "FAILED AND NOT CURED", "CURED BY REPARATION" ] \ w ->
          isRead (parsed (event w)) `shouldBe` False
        -- the control: with a modal in the same place the text is a read
        isRead (parsed [ "x MEANS OUTSTANDING (PARTY Tenant MUST pay)" ]) `shouldBe` True

      it "R8: a module's reads are found from its names, and the pass costs a fraction of one evaluation" do
        let readsLog body = case checkWithImports (vfsFromList []) (src body) of
              Right r -> moduleReadsNormLog r.tcdModule
              Left es -> error ("the module failed to check: " <> show es)
        readsLog (lestPay "OUTSTANDING (PARTY Alice MUST deliver)") `shouldBe` True
        readsLog (lestPay "TRUE") `shouldBe` False
        -- measured with the module forced: a walk over every expression
        -- allocated 12.0 MB for the module below and its evaluation 10.7 MB,
        -- a names walk through gplate 0.6 MB, and this question 24 bytes
        case checkWithImports (vfsFromList []) (everyEmptySrc 400) of
          Left es -> expectationFailure ("the module failed to check: " <> show es)
          Right r -> do
            (off, _, _) <- evalAllocated (everyEmptySrc 400)
            -- what the checked module holds lazily is computed once, and not by the question
            _ <- evaluate (rnf r.tcdModule)
            a0 <- getAllocationCounter
            found <- evaluate (moduleReadsNormLog r.tcdModule)
            a1 <- getAllocationCounter
            found `shouldBe` False
            (fromIntegral (a0 - a1) :: Double) `shouldSatisfy` (< off / 20)

      it "R6: the phrases are not reserved: a program may still name a value OUTSTANDING" do
        -- no prologue: its dangling GIVETH would swallow the first line
        let named = Text.unlines
              [ "GIVETH A NUMBER"
              , "OUTSTANDING MEANS 3"
              , "#EVAL OUTSTANDING PLUS 1"
              ]
        either (const Nothing) (Just . (.tcdErrors)) (checkWithImports (vfsFromList []) named)
          `shouldSatisfy` maybe False null

    describe "the reader on real traces (review of P2, first half)" do
      let tracePrologue = prologue4 <> ["GIVETH DEONTIC Person Action"]
          src body = Text.unlines (tracePrologue <> body)
          -- each norm by the constructor of its action, with its state
          readAt d es = [ (v.nvArmed.neActionHead, v.nvState) | v <- vs ]
            where vs = either (const []) id (readNorms d anyNorm es)
          readEither d es = fmap (map (\ v -> (v.nvArmed.neActionHead, v.nvState))) (readNorms d anyNorm es)
          noInstant = \case { Left (CompoundNoInstant _) -> True; _ -> False }
          noInstant' = \case { Left (CompoundNoInstant _) -> True; _ -> False :: Bool }
          -- is the failure of the first failed norm named so cured, as at d?
          curedAs d name es = case readNorms d anyNorm {npAction = Just name, npBranch = TopLevel} es of
            Left r -> Left r
            Right vs -> case [ v | v <- vs, isFailure v.nvState ] of
              v : _ -> Just <$> isCured d es v
              []    -> Right Nothing
          isFailure = \case { Failed _ -> True; Violated -> True; _ -> False }

      it "S0: an EVERY barrier member left armed when the barrier failed is decided without, not outstanding for ever" do
        let barrier = Text.unlines $ everyPrologue <>
              [ "GIVETH A DEONTIC Actor Action"
              , "`the tenancy` MEANS"
              , "    EVERY Tenant t IN tenants"
              , "        MUST   Sign (EXACTLY t)"
              , "        WITHIN (IF t EQUALS alice THEN 5 ELSE 20)"
              , "        ONCE   ALL HAVE"
              , "        HENCE  (PARTY theLandlord MUST Deliver (EXACTLY theLandlord) WITHIN 5)"
              , "        LEST   BREACH"
              , ""
              , "#TRACE `the tenancy` AT 0 WITH"
              , "  PARTY theLandlord DOES Sign theLandlord AT 10"
              ]
        rs <- run True barrier
        let es = fatesOf 0 rs
            members = [ e | e <- es, e.neFate == FateArmed, e.neMember /= Nothing ]
        length members `shouldBe` 2
        -- both members name the barrier they are in
        [ length e.neEnclosing | e <- members ] `shouldBe` [1, 1]
        readAt 6 es `shouldBe` [(Just "Sign", Outstanding), (Just "Sign", Outstanding)]
        readAt 10 es `shouldBe` [(Just "Sign", Failed FailedToJoin), (Just "Sign", DecidedWithout)]
        readAt 30 es `shouldBe` [(Just "Sign", Failed FailedToJoin), (Just "Sign", DecidedWithout)]

      it "S1: an ROR operand that fails after the other alternative settled the choice is not read as a failure, nor as anything the reader cannot place" do
        let k = src
              [ "c MEANS (PARTY Alice MUST deliver WITHIN 5) ROR (PARTY Bob MUST pay 1 WITHIN 20)"
              , "#TRACE c AT 0 WITH"
              , "  PARTY Bob DOES pay 1 AT 3"
              , "  PARTY Dan DOES deliver AT 6"
              , ""
              , "#TRACE c AT 0 WITH"
              , "  PARTY Bob DOES pay 1 AT 3"
              , "  PARTY Dan DOES deliver AT 10"
              ]
        rs <- run True k
        for_ [0, 1] \ i -> do
          let es = fatesOf i rs
          -- the ROR was fulfilled, and the machine ran its left operand over
          -- the whole trace, so the log holds a failure the contract never had
          [ e.neFate | e <- es, isJoinFate e.neFate ] `shouldBe` [FateJoinedFulfilled JoinOr]
          [ e.neFate | e <- es, e.neFate == FateFailed FailedToBreach ] `shouldSatisfy` (not . null)
          for_ [11, 30] \ d -> readEither d es `shouldSatisfy` noInstant

      it "D2: a real miss inside the alternative that settled an ROR makes a read that matches it refuse, which is the stated cost of N17 and N18 not being built" do
        let w1 = src
              [ "c MEANS"
              , "  (PARTY Alice MUST deliver WITHIN 3 LEST PARTY Alice MUST pay 1 WITHIN 5)"
              , "  ROR (PARTY Bob MUST pay 2 WITHIN 20)"
              , "#TRACE c AT 0 WITH"
              , "  PARTY Alice DOES pay 1 AT 4"
              ]
        rs <- run True w1
        let es = fatesOf 0 rs
        -- the left alternative failed, was repaired, and settled the ROR
        [ e.neFate | e <- es, isJoinFate e.neFate ] `shouldBe` [FateJoinedFulfilled JoinOr]
        [ e.neFate | e <- es, e.neFate == FateFailed FailedToLest ] `shouldSatisfy` (not . null)
        -- every read that matches the miss refuses, from the instant it is armed
        for_ [0, 3, 4, 30] \ d -> do
          readEither d es `shouldSatisfy` noInstant
          readNorms d anyNorm {npAction = Just "deliver"} es `shouldSatisfy` noInstant'
          readNorms d anyNorm {npBranch = TopLevel} es `shouldSatisfy` noInstant'
        -- a read that leaves the miss out answers (the claim of the spec's N13 note)
        readNorms 30 anyNorm {npAction = Just "pay"} es `shouldSatisfy` either (const False) (const True)

      it "S2: a failure cured through an ROR reparation is cured when the alternative that settled the choice was the failing party's" do
        let c1 = src
              [ "c MEANS"
              , "  PARTY Alice MUST deliver WITHIN 3"
              , "  LEST ((PARTY Alice MUST pay 1 WITHIN 5) ROR (PARTY Alice MUST pay 2 WITHIN 20))"
              , "#TRACE c AT 0 WITH"
              , "  PARTY Dan DOES deliver AT 4"
              , "  PARTY Dan DOES deliver AT 9"
              , "  PARTY Alice DOES pay 2 AT 12"
              , ""
              , "#TRACE c AT 0 WITH"
              , "  PARTY Dan DOES deliver AT 4"
              , "  PARTY Alice DOES pay 2 AT 12"
              , ""
              , "#TRACE c AT 0 WITH"
              , "  PARTY Dan DOES deliver AT 4"
              , "  PARTY Bob DOES pay 2 AT 12"
              ]
        rs <- run True c1
        -- the losing alternative failed first, then the other was performed
        curedAs 12 "deliver" (fatesOf 0 rs) `shouldBe` Right (Just True)
        curedAs 30 "deliver" (fatesOf 0 rs) `shouldBe` Right (Just True)
        -- not yet, as at 11
        curedAs 11 "deliver" (fatesOf 0 rs) `shouldBe` Right (Just False)
        -- the losing alternative still armed when the other was performed
        curedAs 12 "deliver" (fatesOf 1 rs) `shouldBe` Right (Just True)
        -- and when the other party performed it, it is not a cure
        curedAs 12 "deliver" (fatesOf 2 rs) `shouldBe` Right (Just False)

      it "D1: an ROR alternative whose first norm was performed, but whose HENCE reached a BREACH, did not settle the choice" do
        let t7 = src
              [ "t7 MEANS"
              , "  PARTY Alice MUST deliver WITHIN 3"
              , "  LEST ((PARTY Alice MUST pay 1 WITHIN 10 HENCE BREACH) ROR (PARTY Alice MUST pay 2 WITHIN 20))"
              , "#TRACE t7 AT 0 WITH"
              , "  PARTY Dan DOES deliver AT 4"
              , "  PARTY Alice DOES pay 1 AT 5"
              , "  PARTY Alice DOES pay 2 AT 9"
              ]
            t8 = src
              [ "t8 MEANS"
              , "  PARTY Alice MUST deliver WITHIN 3"
              , "  LEST ((PARTY Bob MUST pay 1 WITHIN 10 HENCE PARTY Bob SHANT deliver WITHIN 10) ROR (PARTY Alice MUST pay 2 WITHIN 20))"
              , "#TRACE t8 AT 0 WITH"
              , "  PARTY Dan DOES deliver AT 4"
              , "  PARTY Bob DOES pay 1 AT 5"
              , "  PARTY Bob DOES deliver AT 6"
              , "  PARTY Alice DOES pay 2 AT 9"
              ]
            -- the left alternative's HENCE is a norm that fails (t1) or is still owed (t2)
            t1 = src
              [ "t1 MEANS"
              , "  PARTY Alice MUST deliver WITHIN 3"
              , "  LEST ((PARTY Alice MUST pay 1 WITHIN 10 HENCE PARTY Alice MUST pay 3 WITHIN 2) ROR (PARTY Alice MUST pay 2 WITHIN 20))"
              , "#TRACE t1 AT 0 WITH"
              , "  PARTY Dan DOES deliver AT 4"
              , "  PARTY Alice DOES pay 1 AT 5"
              , "  PARTY Alice DOES pay 2 AT 9"
              , ""
              , "t2 MEANS"
              , "  PARTY Alice MUST deliver WITHIN 3"
              , "  LEST ((PARTY Alice MUST pay 1 WITHIN 10 HENCE PARTY Alice MUST pay 3 WITHIN 100) ROR (PARTY Alice MUST pay 2 WITHIN 20))"
              , "#TRACE t2 AT 0 WITH"
              , "  PARTY Dan DOES deliver AT 4"
              , "  PARTY Alice DOES pay 1 AT 5"
              , "  PARTY Alice DOES pay 2 AT 9"
              ]
        rs7 <- run True t7
        -- the machine says FULFILLED: the ROR was settled by pay 2, by the party that failed
        [ e.neFate | e <- fatesOf 0 rs7, isJoinFate e.neFate ] `shouldBe` [FateJoinedFulfilled JoinOr]
        curedAs 5 "deliver" (fatesOf 0 rs7) `shouldBe` Right (Just False)
        curedAs 9 "deliver" (fatesOf 0 rs7) `shouldBe` Right (Just True)
        curedAs 30 "deliver" (fatesOf 0 rs7) `shouldBe` Right (Just True)
        rs8 <- run True t8
        [ e.neFate | e <- fatesOf 0 rs8, isJoinFate e.neFate ] `shouldBe` [FateJoinedFulfilled JoinOr]
        curedAs 9 "deliver" (fatesOf 0 rs8) `shouldBe` Right (Just True)
        rs1 <- run True t1
        for_ [0, 1] \ i -> do
          [ e.neFate | e <- fatesOf i rs1, isJoinFate e.neFate ] `shouldBe` [FateJoinedFulfilled JoinOr]
          curedAs 9 "deliver" (fatesOf i rs1) `shouldBe` Right (Just True)
          curedAs 30 "deliver" (fatesOf i rs1) `shouldBe` Right (Just True)

      it "S3: a violated SHANT whose own LEST was then performed by the failing party is cured; a violation with nothing armed after it is not" do
        let d = src
              [ "c MEANS"
              , "  PARTY Alice MUST deliver WITHIN 3"
              , "  LEST (PARTY Alice SHANT pay 1 WITHIN 5 LEST PARTY Alice MUST pay 2 WITHIN 5)"
              , "#TRACE c AT 0 WITH"
              , "  PARTY Alice DOES pay 1 AT 4"
              , "  PARTY Alice DOES pay 2 AT 6"
              , ""
              , "#TRACE c AT 0 WITH"
              , "  PARTY Alice DOES pay 1 AT 4"
              , ""
              , "#TRACE c AT 0 WITH"
              , "  PARTY Alice DOES pay 1 AT 4"
              , "  PARTY Bob DOES pay 2 AT 6"
              ]
            noLest = src
              [ "c MEANS"
              , "  PARTY Alice MUST deliver WITHIN 3"
              , "  LEST (PARTY Alice SHANT pay 1 WITHIN 5)"
              , "#TRACE c AT 0 WITH"
              , "  PARTY Alice DOES pay 1 AT 4"
              ]
        rs <- run True d
        curedAs 7 "deliver" (fatesOf 0 rs) `shouldBe` Right (Just True)
        curedAs 7 "deliver" (fatesOf 1 rs) `shouldBe` Right (Just False)
        curedAs 7 "deliver" (fatesOf 2 rs) `shouldBe` Right (Just False)
        rs' <- run True noLest
        curedAs 7 "deliver" (fatesOf 0 rs') `shouldBe` Right (Just False)

      it "J: a lapsed MAY in a reparation whose own LEST is a BREACH is not a cure" do
        let j = src
              [ "c MEANS"
              , "  PARTY Alice MUST deliver WITHIN 3"
              , "  LEST (PARTY Alice MAY pay 1 WITHIN 5 LEST BREACH)"
              , "#TRACE c AT 0 WITH"
              , "  PARTY Alice DOES deliver AT 4"
              , "  PARTY Dan DOES deliver AT 20"
              ]
        rs <- run True j
        curedAs 30 "deliver" (fatesOf 0 rs) `shouldBe` Right (Just False)

      it "L2: a RAND that ends fulfilled does not make every earlier read refuse: an operand whose fate comes later is not yet decided" do
        let h = src
              [ "c MEANS"
              , "  PARTY Alice MUST deliver WITHIN 3"
              , "  LEST ((PARTY Alice MUST pay 1 WITHIN 5) RAND (PARTY Bob MUST pay 2 WITHIN 5))"
              , "#TRACE c AT 0 WITH"
              , "  PARTY Alice DOES pay 1 AT 4"
              , "  PARTY Bob DOES pay 2 AT 5"
              ]
        rs <- run True h
        readEither 4 (fatesOf 0 rs)
          `shouldBe` Right [(Just "deliver", Failed FailedToLest), (Just "pay", Performed), (Just "pay", Outstanding)]
        readEither 5 (fatesOf 0 rs)
          `shouldBe` Right [(Just "deliver", Failed FailedToLest), (Just "pay", Performed), (Just "pay", Performed)]

      it "Q: a bearer filter refuses on an ordinary outstanding norm, whoever it is for: the party was never forced (N7 rule 3 is not built)" do
        let q = src
              [ "c MEANS"
              , "  PARTY Alice MUST deliver WITHIN 3"
              , "  HENCE PARTY Bob MUST pay 1 WITHIN 10"
              , "#TRACE c AT 0 WITH"
              , "  PARTY Alice DOES deliver AT 1"
              ]
        rs <- run True q
        let es = fatesOf 0 rs
            refused who = case readNorms 5 anyNorm {npBearer = BearerIs who} es of
              Left (BearerNotKnown _ (WrittenBearer _)) -> True
              _ -> False
        refused "Bob" `shouldBe` True
        refused "Alice" `shouldBe` True

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
      it (name <> ": effective is never after observed (N3), in every directive") do
        rs <- run True src
        for_ [ e | d <- [0 .. length rs - 1], e <- fatesOf d rs ] \ e ->
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
