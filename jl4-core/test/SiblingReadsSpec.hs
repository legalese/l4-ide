{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
-- | smucclaw/l4-ide#1069: a compound whose operands read each other's records
-- is refused, at run time, naming the record and both operands; and the
-- checker warns, beforehand, where a compound's operands can reach a read and
-- a write of one cell.
--
-- Every refusal case is written both ways round. The machine runs the left
-- operand over the whole trace before the right one, so one of the two orders
-- gave the time-ordered answer by luck, and the other gave a wrong one with no
-- error. The check refuses the wrong one, and lets the lucky one run only when
-- no read in it could have depended on the order. A file in which a read and
-- a sibling's write fall at the same instant is refused either way round
-- (assumed, not ruled: the check has no event identity to order them by).
--
-- The operands that do NOT read each other's records, for which nothing may
-- change, are "BreachClocksSpec"'s C1.
module SiblingReadsSpec (spec) where

import Data.Foldable (for_)
import qualified Data.Text as Text
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

import L4.API.VirtualFS (vfsFromList, checkWithImports)
import L4.EvaluateLazy
import L4.EvaluateLazy.Machine (emptyEnvironment)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.Lint.SiblingReads (SiblingOperand (..), SiblingRead (..))
import L4.Print (prettyLayout)
import L4.TracePolicy (apiDefaultPolicy)
import L4.TypeCheck (prettyCheckError)
import L4.TypeCheck.Types (CheckError (..), CheckErrorWithContext (..), CheckWarning (..))

-- | What one directive did: refused (the message), or ran (its value, printed).
data Outcome = Stopped Text.Text | Ran Text.Text
  deriving stock (Eq, Show)

isRefused :: Outcome -> Bool
isRefused = \ case
  Stopped _ -> True
  Ran _     -> False

fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 0)

checked :: Text.Text -> IO TypeCheckWithDepsResult
checked src = case checkWithImports (vfsFromList []) src of
  Left errs -> fail ("typecheck failed: " <> show errs)
  Right r   -> pure r

run :: Text.Text -> IO [Outcome]
run src = do
  r <- checked src
  cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
  (_, results) <- execEvalModuleWithEnv cfg r.tcdEntityInfo emptyEnvironment r.tcdModule
  pure (map outcomeOf results)
  where
    outcomeOf res = case res.result of
      Reduction (ReducedErrored e) -> Stopped (Text.unwords (Text.words (Text.unlines (prettyEvalException e))))
      Reduction (Reduced nf)       -> Ran (prettyLayout nf)
      other                        -> Ran (Text.pack (show other))

warnings :: Text.Text -> IO [SiblingRead]
warnings src = do
  r <- checked src
  pure [ w | MkCheckErrorWithContext {kind = CheckWarning (SiblingLedgerRead w)} <- r.tcdErrors ]

warningTexts :: Text.Text -> IO [Text.Text]
warningTexts src = do
  r <- checked src
  pure [ Text.unlines (prettyCheckError k) | MkCheckErrorWithContext {kind = k@(CheckWarning (SiblingLedgerRead _))} <- r.tcdErrors ]

shouldMention :: Outcome -> [Text.Text] -> Expectation
shouldMention o ws = case o of
  Stopped msg -> for_ ws \ w -> (w, w `Text.isInfixOf` msg, msg) `shouldBe` (w, True, msg)
  Ran v       -> expectationFailure ("expected a refusal, but it ran: " <> Text.unpack v)

-- ---------------------------------------------------------------------------
-- Alice and Bob, the issue's own file

dinner :: Text.Text -> Text.Text
dinner compound = Text.unlines
  [ "DECLARE Party IS ONE OF Alice, Bob"
  , "DECLARE Act IS ONE OF"
  , "    `checks whether dinner is bought`"
  , "    `buys dinner`"
  , "DECLARE Status IS ONE OF opened, taken"
  , "DECLARE Dinner IS ONE OF `dinner for two`"
  , "`closing` MEANS 100"
  , "GIVEN xs IS A LIST OF Status"
  , "GIVETH A BOOLEAN"
  , "`has taken` MEANS"
  , "    CONSIDER xs"
  , "    WHEN EMPTY THEN FALSE"
  , "    WHEN x FOLLOWED BY rest THEN x EQUALS taken OR `has taken` rest"
  , "GIVEN `dinner status record` IS A LIST OF Status"
  , "GIVETH A BOOLEAN"
  , "`the ledger is open` MEANS NOT (`has taken` `dinner status record`)"
  , "GIVEN `dinner status record` IS A LIST OF Status"
  , "GIVETH A Status"
  , "`the ledger's status` MEANS"
  , "    IF `has taken` `dinner status record` THEN taken ELSE opened"
  , "GIVETH A DEONTIC Party Act"
  , "`the arrangement` MEANS"
  , "    COMMIT `dinner status record` IS opened"
  , "    HENCE " <> compound
  , "GIVETH A DEONTIC Party Act"
  , "`Alice's evening` MEANS"
  , "    PARTY Alice"
  , "    MAY   `checks whether dinner is bought`"
  , "    WITHIN 0 OF closing"
  , "    HENCE RECORD Alice's `belief` IS `the ledger's status` (RECALL ALL OFFICIAL's `dinner status record`)"
  , "          HENCE `Alice decides`"
  , "    LEST  FULFILLED"
  , "GIVETH A DEONTIC Party Act"
  , "`Alice decides` MEANS"
  , "    PARTY Alice"
  , "    MAY   `buys dinner` PROVIDED (RECALL Alice's `belief`) EQUALS JUST opened"
  , "    WITHIN 0 OF closing"
  , "    HENCE COMMIT `dinners bought` IS `dinner for two`"
  , "          HENCE COMMIT `open at acceptance` IS `the ledger is open` (RECALL ALL OFFICIAL's `dinner status record`)"
  , "          HENCE FULFILLED"
  , "    LEST  FULFILLED"
  , "GIVETH A DEONTIC Party Act"
  , "`Bob's evening` MEANS"
  , "    PARTY Bob"
  , "    MAY   `buys dinner` PROVIDED `the ledger is open` (RECALL ALL OFFICIAL's `dinner status record`)"
  , "    WITHIN 0 OF closing"
  , "    HENCE COMMIT `dinner status record` IS taken"
  , "          HENCE FULFILLED"
  , "    LEST  FULFILLED"
  , "#TRACE `the arrangement` AT 0 WITH"
  , "    PARTY Alice DOES `checks whether dinner is bought` AT 10"
  , "    PARTY Bob   DOES `buys dinner`                     AT 11"
  , "    PARTY Alice DOES `buys dinner`                     AT 12"
  ]

-- ---------------------------------------------------------------------------
-- A notice and the possession claim that relies on it: the writer-before-reader
-- shape NORM-LOG-SPEC N10 says must keep working

notice :: Text.Text -> Text.Text -> [Text.Text] -> Text.Text
notice op order evs = Text.unlines $
  [ "DECLARE Party IS ONE OF Landlord"
  , "DECLARE Act IS ONE OF `gives notice`, `seeks possession`"
  , "GIVETH A DEONTIC Party Act"
  , "`notice` MEANS"
  , "    PARTY Landlord"
  , "    MAY `gives notice`"
  , "    WITHIN 100"
  , "    HENCE COMMIT `notice given` IS TRUE HENCE FULFILLED"
  , "    LEST FULFILLED"
  , "GIVETH A DEONTIC Party Act"
  , "`possession` MEANS"
  , "    PARTY Landlord"
  , "    MAY `seeks possession` PROVIDED (RECALL OFFICIAL's `notice given`) EQUALS JUST TRUE"
  , "    WITHIN 1000"
  , "    HENCE COMMIT `possession sought` IS TRUE HENCE FULFILLED"
  , "    LEST FULFILLED"
  , "GIVETH A DEONTIC Party Act"
  , "`the tenancy` MEANS " <> Text.replace " OP " (" " <> op <> " ") order
  , "#TRACE `the tenancy` AT 0 WITH"
  ] <> map ("    " <>) evs

noticeThenClaim :: [Text.Text]
noticeThenClaim =
  [ "PARTY Landlord DOES `gives notice` AT 10"
  , "PARTY Landlord DOES `seeks possession` AT 400" ]

-- ---------------------------------------------------------------------------
-- The fork version (EVERY … UPON EACH), GM's probe of 2026-10-26

fork :: Text.Text -> Text.Text
fork roll = Text.unlines
  [ "DECLARE Party IS ONE OF Alice, Bob"
  , "DECLARE Status IS ONE OF opened, taken"
  , "DECLARE Act IS ONE OF `reads the ledger`, `buys dinner`"
  , "diners MEANS LIST " <> roll
  , "closing MEANS 75600"
  , "GIVEN xs IS A LIST OF Status"
  , "GIVETH A NUMBER"
  , "`entries in` MEANS"
  , "    CONSIDER xs"
  , "    WHEN EMPTY THEN 0"
  , "    WHEN x FOLLOWED BY rest THEN 1 PLUS `entries in` rest"
  , "GIVEN d IS A Party"
  , "      act IS AN Act"
  , "GIVETH A DEONTIC Party Act"
  , "`after` MEANS"
  , "    CONSIDER act"
  , "    WHEN `reads the ledger` THEN"
  , "        RECORD d's `entries read` IS `entries in` (RECALL ALL OFFICIAL's `dinner status record`)"
  , "        `evening of` d"
  , "    WHEN `buys dinner` THEN"
  , "        COMMIT `dinner status record` IS taken"
  , "        `evening of` d"
  , "GIVEN d IS A Party"
  , "GIVETH A DEONTIC Party Act"
  , "`evening of` MEANS"
  , "    PARTY d"
  , "    MAY    act"
  , "    WITHIN 0 OF closing"
  , "    HENCE  `after` d act"
  , "GIVETH A DEONTIC Party Act"
  , "`the evening` MEANS"
  , "    EVERY d IN diners"
  , "        MAY    act"
  , "        WITHIN 0 OF closing"
  , "        UPON   EACH"
  , "        HENCE  `after` d act"
  , "GIVETH A DEONTIC Party Act"
  , "`the arrangement` MEANS"
  , "    COMMIT `dinner status record` IS opened"
  , "    HENCE `the evening`"
  -- X0: Alice reads twice, nobody buys
  , "#TRACE `the arrangement` AT 64800 WITH"
  , "    PARTY Alice DOES `reads the ledger` AT 65100"
  , "    PARTY Alice DOES `reads the ledger` AT 65220"
  -- X1: Alice reads; Bob buys later
  , "#TRACE `the arrangement` AT 64800 WITH"
  , "    PARTY Alice DOES `reads the ledger` AT 65100"
  , "    PARTY Bob   DOES `buys dinner`      AT 70000"
  -- X2: Alice reads, Bob buys, Alice reads
  , "#TRACE `the arrangement` AT 64800 WITH"
  , "    PARTY Alice DOES `reads the ledger` AT 65100"
  , "    PARTY Bob   DOES `buys dinner`      AT 65160"
  , "    PARTY Alice DOES `reads the ledger` AT 65220"
  -- X3: Alice alone
  , "#TRACE `the arrangement` AT 64800 WITH"
  , "    PARTY Alice DOES `reads the ledger` AT 65100"
  , "    PARTY Alice DOES `buys dinner`      AT 65160"
  , "    PARTY Alice DOES `reads the ledger` AT 65220"
  -- X4: Bob reads, Alice buys, Bob reads
  , "#TRACE `the arrangement` AT 64800 WITH"
  , "    PARTY Bob   DOES `reads the ledger` AT 65100"
  , "    PARTY Alice DOES `buys dinner`      AT 65160"
  , "    PARTY Bob   DOES `reads the ledger` AT 65220"
  ]

-- | The same, as the distributive form: no join line, and every member still
-- carries the HENCE.
distributive :: Text.Text -> Text.Text
distributive = Text.unlines . filter (/= "        UPON   EACH") . Text.lines . fork

-- ---------------------------------------------------------------------------
-- NORM-LOG-SPEC N12's last-write probe: two writes the ledger holds out of
-- time order, and a third operand that reads the latest

lastWrite :: Text.Text -> Text.Text
lastWrite compound = Text.unlines
  [ "DECLARE Party IS ONE OF P, Q, R"
  , "DECLARE Act IS ONE OF go"
  , "GIVETH A DEONTIC Party Act"
  , "`a` MEANS PARTY P MAY go WITHIN 100 HENCE COMMIT `x` IS 1 HENCE FULFILLED LEST FULFILLED"
  , "GIVETH A DEONTIC Party Act"
  , "`b` MEANS PARTY Q MAY go WITHIN 100 HENCE COMMIT `x` IS 2 HENCE FULFILLED LEST FULFILLED"
  , "GIVETH A DEONTIC Party Act"
  , "`c` MEANS PARTY R MAY go WITHIN 100 HENCE COMMIT `saw 1` IS ((RECALL OFFICIAL's `x`) EQUALS JUST 1) HENCE FULFILLED LEST FULFILLED"
  , "GIVETH A DEONTIC Party Act"
  , "`all three` MEANS " <> compound
  , "#TRACE `all three` AT 0 WITH"
  , "    PARTY Q DOES go AT 3"
  , "    PARTY P DOES go AT 20"
  , "    PARTY R DOES go AT 25"
  ]

-- ---------------------------------------------------------------------------
-- SEESAW's own example (EVERY-EACH-QUANTIFIER-SPEC §6.1.2, "What it does not
-- promise"): P waives at 4, and the other operand reads the waiver when it
-- starts, at 0

waiver :: Text.Text -> Text.Text
waiver compound = Text.unlines
  [ "DECLARE Party IS ONE OF P, Q"
  , "DECLARE Act IS ONE OF x, y"
  , "GIVETH A DEONTIC Party Act"
  , "`a` MEANS PARTY P MUST x WITHIN 5 HENCE RECORD `waived` IS TRUE HENCE FULFILLED"
  , "GIVETH A DEONTIC Party Act"
  , "`b` MEANS IF (RECALL P's `waived`) EQUALS JUST TRUE THEN FULFILLED ELSE PARTY Q MUST y WITHIN 3"
  , "GIVETH A DEONTIC Party Act"
  , "`both` MEANS " <> compound
  , "#TRACE `both` AT 0 WITH"
  , "    PARTY P DOES x AT 4"
  ]

-- ---------------------------------------------------------------------------
-- Two operands, no shared cell, and a fork whose members keep their records
-- in their own ledgers: nothing to warn about

noShared :: Text.Text
noShared = Text.unlines
  [ "DECLARE Party IS ONE OF P, Q"
  , "DECLARE Act IS ONE OF go"
  , "GIVETH A DEONTIC Party Act"
  , "`both` MEANS"
  , "    (PARTY P MAY go WITHIN 10 HENCE COMMIT `p went` IS TRUE HENCE COMMIT `p saw` IS ((RECALL OFFICIAL's `p went`) EQUALS JUST TRUE) HENCE FULFILLED LEST FULFILLED)"
  , "    RAND"
  , "    (PARTY Q MAY go WITHIN 10 HENCE COMMIT `q went` IS TRUE HENCE COMMIT `q saw` IS ((RECALL OFFICIAL's `q went`) EQUALS JUST TRUE) HENCE FULFILLED LEST FULFILLED)"
  , "#TRACE `both` AT 0 WITH"
  , "    PARTY P DOES go AT 1"
  , "    PARTY Q DOES go AT 1"
  ]

ownLedgers :: Text.Text
ownLedgers = Text.unlines
  [ "DECLARE Party IS ONE OF P, Q"
  , "DECLARE Act IS ONE OF go"
  , "GIVETH A DEONTIC Party Act"
  , "`each` MEANS"
  , "    EVERY d IN LIST P, Q"
  , "        MAY go"
  , "        WITHIN 10"
  , "        UPON EACH"
  , "        HENCE RECORD `went` IS TRUE HENCE RECORD `checked` IS ((RECALL `went`) EQUALS JUST TRUE) HENCE FULFILLED"
  , "#TRACE `each` AT 0 WITH"
  , "    PARTY P DOES go AT 1"
  , "    PARTY Q DOES go AT 1"
  ]

spec :: Spec
spec = describe "operands that read each other's records (smucclaw/l4-ide#1069)" do
  describe "the run-time refusal" do
    it "refuses the issue's file, naming the record, both operands and both instants" do
      outs <- run (dinner "`Alice's evening` RAND `Bob's evening`")
      case outs of
        [o] -> o `shouldMention`
          [ "read each other's records", "OFFICIAL's `dinner status record`"
          , "`Alice's evening`", "`Bob's evening`", "at 12", "at 11", "a RAND" ]
        _ -> expectationFailure ("expected one directive, got " <> show outs)

    it "refuses it the other way round too, where the read saw a record from its future" do
      outs <- run (dinner "`Bob's evening` RAND `Alice's evening`")
      case outs of
        [o] -> o `shouldMention` ["read each other's records", "at 10", "at 11", "future"]
        _ -> expectationFailure ("expected one directive, got " <> show outs)

    it "lets a record made on the left, earlier than the right side reads it, run (N10: writer before reader)" do
      outs <- run (notice "RAND" "`notice` OP `possession`" noticeThenClaim)
      outs `shouldSatisfy` (not . any isRefused)

    it "refuses the reader-first order of the same file, where the read missed a record from its past" do
      outs <- run (notice "RAND" "`possession` OP `notice`" noticeThenClaim)
      case outs of
        [o] -> o `shouldMention` ["read each other's records", "`possession` read", "but `notice`, on the other side", "at 400", "at 10", "should have seen"]
        _ -> expectationFailure ("expected one directive, got " <> show outs)

    it "refuses a read and a sibling's write at the same instant, either way round (assumed, not ruled)" do
      let sameInstant = [ "PARTY Landlord DOES `gives notice` AT 10", "PARTY Landlord DOES `seeks possession` AT 10" ]
      left <- run (notice "RAND" "`notice` OP `possession`" sameInstant)
      right <- run (notice "RAND" "`possession` OP `notice`" sameInstant)
      left `shouldSatisfy` all isRefused
      right `shouldSatisfy` all isRefused

    it "refuses an ROR whose left side read a record its right side makes earlier" do
      outs <- run (notice "ROR" "`possession` OP `notice`" noticeThenClaim)
      case outs of
        [o] -> o `shouldMention` ["read each other's records", "an ROR"]
        _ -> expectationFailure ("expected one directive, got " <> show outs)

    it "refuses an EVERY … UPON EACH whose members read each other's records, only where the order mattered" do
      ab <- run (fork "Alice, Bob")
      ba <- run (fork "Bob, Alice")
      -- X0 nobody buys; X1 Bob buys after Alice's only read; X2 and X4 a
      -- purchase between two reads; X3 one diner alone
      (map isRefused ab, ab) `shouldBe` ([False, False, True, False, True], ab)
      (map isRefused ba, ba) `shouldBe` ([False, True, True, False, True], ba)

    it "refuses the distributive EVERY (no UPON EACH line) the same way, since it folds its members the same way" do
      ab <- run (distributive "Alice, Bob")
      (map isRefused ab, ab) `shouldBe` ([False, False, True, False, True], ab)

    it "refuses records seen out of order (N12's probe), and runs the order in which the latest write is last" do
      wrong <- run (lastWrite "`a` RAND `b` RAND `c`")
      right <- run (lastWrite "`b` RAND `a` RAND `c`")
      case wrong of
        [o] -> o `shouldMention` ["read each other's records", "not the order they were made in"]
        _ -> expectationFailure ("expected one directive, got " <> show wrong)
      right `shouldSatisfy` (not . any isRefused)

    it "refuses SEESAW's example where it was FULFILLED by a record from the future, and keeps BREACHED the other way round" do
      wrong <- run (waiver "`a` RAND `b`")
      right <- run (waiver "`b` RAND `a`")
      case wrong of
        [o] -> o `shouldMention` ["read each other's records", "P's `waived`", "at 0", "at 4"]
        _ -> expectationFailure ("expected one directive, got " <> show wrong)
      case right of
        [Ran v] -> v `shouldSatisfy` ("BREACH" `Text.isInfixOf`) . Text.toUpper
        _ -> expectationFailure ("expected one breached directive, got " <> show right)

    it "lets operands with no shared cell, and fork members with their own ledgers, run" do
      a <- run noShared
      b <- run ownLedgers
      (a <> b) `shouldSatisfy` (not . any isRefused)

  describe "the check-time warning" do
    it "warns on the issue's file, naming the cell and both operands" do
      ws <- warnings (dinner "`Alice's evening` RAND `Bob's evening`")
      [ (w.cell, w.official, prettyLayout <$> w.readerSide.rule, prettyLayout <$> w.writerSide.rule) | w <- ws ]
        `shouldBe` [("dinner status record", True, Just "`Alice's evening`", Just "`Bob's evening`")]
      ts <- warningTexts (dinner "`Alice's evening` RAND `Bob's evening`")
      ts `shouldSatisfy` all ("may read each other's records" `Text.isInfixOf`)

    it "warns on a fork whose members read and write one official cell" do
      ws <- warnings (fork "Alice, Bob")
      [ (w.op, w.cell) | w <- ws ] `shouldBe` [("EVERY", "dinner status record")]

    it "warns on a distributive EVERY too" do
      ws <- warnings (distributive "Alice, Bob")
      [ (w.op, w.cell) | w <- ws ] `shouldBe` [("EVERY", "dinner status record")]

    it "warns on a writer-before-reader file too, since reachability cannot see time (a warning, never an error)" do
      ws <- warnings (notice "RAND" "`notice` OP `possession`" noticeThenClaim)
      [ w.cell | w <- ws ] `shouldBe` ["notice given"]

    it "does not warn where no operand reads what another writes" do
      a <- warnings noShared
      b <- warnings ownLedgers
      (a <> b) `shouldBe` []
