{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
-- | smucclaw/l4-ide#1069: operands that read each other's records.
--
-- A @RAND@, and an @EVERY@ whose members are folded into one, runs its
-- operands in step (NORM-LOG-SPEC N10's option A; Note [Operands in step] in
-- "L4.EvaluateLazy.Machine"): every operand takes event n of the trace before
-- any takes event n+1, so a read on one side sees the other side's records
-- from earlier events, and none from later ones. Every case below is written
-- both ways round, and both orders must give the same, time-ordered answer.
--
-- What in step cannot order is still refused, by the run-time check
-- ("L4.EvaluateLazy.SiblingReads"): a read and a record made while the two
-- sides take the SAME event, where the left side's turn comes before the
-- right's and that is not the order of their instants, or at one instant,
-- where the trace gives them no order (assumed, not ruled). An @ROR@ still
-- runs its operands one after the other, so it is still refused where a read
-- depended on that order, and it is the only compound the checker still
-- warns about.
--
-- The operands that do NOT read each other's records, for which nothing may
-- change, are "BreachClocksSpec"'s C1, which also runs each tree in step and
-- one operand after the other and compares the two.
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

-- | What one directive did: refused (the message), or ran (its value and its
-- ledgers, printed).
data Outcome = Stopped Text.Text | Ran Text.Text Text.Text
  deriving stock (Eq, Show)

isRefused :: Outcome -> Bool
isRefused = \ case
  Stopped _ -> True
  Ran _ _   -> False

-- | The ledgers of a directive that ran, as @l4 run@ prints them.
ledgerOf :: Outcome -> Text.Text
ledgerOf = \ case
  Ran _ l   -> l
  Stopped m -> "refused: " <> m

-- | The lines of a directive's ledgers that mention a cell, in order.
entriesOf :: Text.Text -> Outcome -> [Text.Text]
entriesOf cell o = [ Text.strip l | l <- Text.lines (ledgerOf o), ("`" <> cell <> "`") `Text.isInfixOf` l ]

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
      Reduction (Reduced nf)       -> Ran (prettyLayout nf) (prettyLedger res.ledger)
      other                        -> Ran (Text.pack (show other)) (prettyLedger res.ledger)

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
  Ran v _     -> expectationFailure ("expected a refusal, but it ran: " <> Text.unpack v)

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

-- ---------------------------------------------------------------------------
-- Two sides that take ONE event: one makes a record at the event's stamp,
-- the other reads it at the same stamp. The trace gives no order between
-- them, so neither order of the operands may answer.

oneEvent :: Text.Text -> Text.Text
oneEvent compound = Text.unlines
  [ "DECLARE Party IS ONE OF P"
  , "DECLARE Act IS ONE OF go"
  , "GIVETH A DEONTIC Party Act"
  , "`writer` MEANS PARTY P MAY go WITHIN 10 HENCE COMMIT `x` IS TRUE HENCE FULFILLED LEST FULFILLED"
  , "GIVETH A DEONTIC Party Act"
  , "`reader` MEANS PARTY P MAY go PROVIDED (RECALL OFFICIAL's `x`) EQUALS NOTHING WITHIN 10 HENCE COMMIT `first` IS TRUE HENCE FULFILLED LEST FULFILLED"
  , "GIVETH A DEONTIC Party Act"
  , "`both` MEANS " <> compound
  , "#TRACE `both` AT 0 WITH"
  , "    PARTY P DOES go AT 1"
  ]

-- ---------------------------------------------------------------------------
-- One event, two instants: the event at 9 reveals that P missed a deadline
-- at 5, and P's LEST records the lapse at 5; Q's act at 9 relies on the lapse.
-- In time order Q sees it. With the lapse on the left, the left side takes
-- the event first and Q does see it; with it on the right, Q has read before
-- the lapse was recorded, and that order is refused, not answered.

lapse :: Text.Text -> Text.Text
lapse compound = Text.unlines
  [ "DECLARE Party IS ONE OF P, Q"
  , "DECLARE Act IS ONE OF a, b"
  , "GIVETH A DEONTIC Party Act"
  , "`lapse` MEANS PARTY P MUST a WITHIN 5 HENCE FULFILLED LEST COMMIT `lapsed` IS TRUE HENCE FULFILLED"
  , "GIVETH A DEONTIC Party Act"
  , "`relies` MEANS PARTY Q MAY b PROVIDED (RECALL OFFICIAL's `lapsed`) EQUALS JUST TRUE WITHIN 100 HENCE COMMIT `relied` IS TRUE HENCE FULFILLED LEST FULFILLED"
  , "GIVETH A DEONTIC Party Act"
  , "`both` MEANS " <> compound
  , "#TRACE `both` AT 0 WITH"
  , "    PARTY Q DOES b AT 9"
  ]

spec :: Spec
spec = describe "operands that read each other's records (smucclaw/l4-ide#1069)" do
  describe "a RAND's operands in step" do
    it "answers the issue's file in time order: Bob's purchase at 11 is seen by Alice at 12" do
      for_ ["`Alice's evening` RAND `Bob's evening`", "`Bob's evening` RAND `Alice's evening`"] \ compound -> do
        outs <- run (dinner compound)
        case outs of
          [o] -> do
            (compound, isRefused o) `shouldBe` (compound, False)
            (compound, entriesOf "open at acceptance" o) `shouldBe` (compound, ["COMMIT `open at acceptance` IS FALSE   [party=Alice, source=COMMIT, at=2026-01-01T00:00:00Z]"])
          _ -> expectationFailure ("expected one directive, got " <> show outs)

    it "keeps the official record in the order of the events, whichever side is written first" do
      [ab] <- run (dinner "`Alice's evening` RAND `Bob's evening`")
      [ba] <- run (dinner "`Bob's evening` RAND `Alice's evening`")
      ledgerOf ab `shouldBe` ledgerOf ba
      map (Text.takeWhile (/= '[')) (entriesOf "dinner status record" ab <> entriesOf "dinners bought" ab)
        `shouldBe` [ "COMMIT `dinner status record` IS opened   ", "COMMIT `dinner status record` IS taken   ", "COMMIT `dinners bought` IS `dinner for two`   " ]

    it "lets a record made on either side be read on the other from the next event on (N10: writer before reader)" do
      for_ ["`notice` OP `possession`", "`possession` OP `notice`"] \ order -> do
        outs <- run (notice "RAND" order noticeThenClaim)
        (order, map isRefused outs) `shouldBe` (order, [False])
        (order, concatMap (entriesOf "possession sought") outs) `shouldBe` (order, ["COMMIT `possession sought` IS TRUE   [party=Landlord, source=COMMIT, at=2026-01-01T00:00:00Z]"])

    it "orders a read and a sibling's record at one instant by the trace's order of their two events" do
      let noticeFirst = [ "PARTY Landlord DOES `gives notice` AT 10", "PARTY Landlord DOES `seeks possession` AT 10" ]
          claimFirst  = [ "PARTY Landlord DOES `seeks possession` AT 10", "PARTY Landlord DOES `gives notice` AT 10" ]
      for_ ["`notice` OP `possession`", "`possession` OP `notice`"] \ order -> do
        seen <- run (notice "RAND" order noticeFirst)
        unseen <- run (notice "RAND" order claimFirst)
        (order, map isRefused (seen <> unseen)) `shouldBe` (order, [False, False])
        (order, length (concatMap (entriesOf "possession sought") seen)) `shouldBe` (order, 1)
        (order, concatMap (entriesOf "possession sought") unseen) `shouldBe` (order, [])

    it "refuses a read and a sibling's record made at one instant while both sides take the same event, either way round (assumed, not ruled)" do
      left <- run (oneEvent "`writer` RAND `reader`")
      right <- run (oneEvent "`reader` RAND `writer`")
      case (left, right) of
        ([l], [r]) -> do
          l `shouldMention` ["read each other's records", "OFFICIAL's `x`", "at 1", "own instant", "in step"]
          r `shouldMention` ["read each other's records", "OFFICIAL's `x`", "at 1", "at the same instant", "in step"]
        _ -> expectationFailure ("expected one directive each, got " <> show (left, right))

    it "within one event, answers when the left side's record is the earlier, and refuses the other order" do
      seen <- run (lapse "`lapse` RAND `relies`")
      refused <- run (lapse "`relies` RAND `lapse`")
      case (seen, refused) of
        ([s'], [r]) -> do
          entriesOf "relied" s' `shouldBe` ["COMMIT `relied` IS TRUE   [party=Q, source=COMMIT, at=2026-01-01T00:00:00Z]"]
          r `shouldMention` ["read each other's records", "`relies` read", "at 9", "at 5", "should have seen", "in step"]
        _ -> expectationFailure ("expected one directive each, got " <> show (seen, refused))

    it "runs an EVERY … UPON EACH in step: each member's read sees the purchases made before it, in either roll order" do
      ab <- run (fork "Alice, Bob")
      ba <- run (fork "Bob, Alice")
      (map isRefused ab, map isRefused ba) `shouldBe` (replicate 5 False, replicate 5 False)
      -- X2: Alice reads at 65100, Bob buys at 65160, Alice reads at 65220
      for_ [("Alice, Bob" :: Text.Text, ab), ("Bob, Alice", ba)] \ (roll, outs) ->
        (roll, map (Text.takeWhile (/= '[')) (entriesOf "entries read" (outs !! 2)))
          `shouldBe` (roll, ["RECORD `entries read` IS 1   ", "RECORD `entries read` IS 2   "])
      map ledgerOf ab `shouldBe` map ledgerOf ba

    it "runs the distributive EVERY (no UPON EACH line) the same way, since it folds its members the same way" do
      ab <- run (distributive "Alice, Bob")
      ba <- run (distributive "Bob, Alice")
      (map isRefused ab, map isRefused ba) `shouldBe` (replicate 5 False, replicate 5 False)
      map (Text.takeWhile (/= '[')) (entriesOf "entries read" (ab !! 2))
        `shouldBe` ["RECORD `entries read` IS 1   ", "RECORD `entries read` IS 2   "]
      map ledgerOf ab `shouldBe` map ledgerOf ba

    it "reads the latest of two records made out of operand order (N12's probe), in either order" do
      for_ ["`a` RAND `b` RAND `c`", "`b` RAND `a` RAND `c`", "`c` RAND `b` RAND `a`"] \ compound -> do
        outs <- run (lastWrite compound)
        (compound, concatMap (entriesOf "saw 1") outs) `shouldBe` (compound, ["COMMIT `saw 1` IS TRUE   [party=R, source=COMMIT, at=2026-01-01T00:00:00Z]"])

    it "keeps SEESAW's example BREACHED either way round: the waiver at 4 comes after the read at 0" do
      for_ ["`a` RAND `b`", "`b` RAND `a`"] \ compound -> do
        outs <- run (waiver compound)
        case outs of
          [Ran v _] -> (compound, "BREACH" `Text.isInfixOf` Text.toUpper v) `shouldBe` (compound, True)
          _ -> expectationFailure ("expected one breached directive, got " <> show outs)

    it "lets operands with no shared cell, and fork members with their own ledgers, run" do
      a <- run noShared
      b <- run ownLedgers
      (a <> b) `shouldSatisfy` (not . any isRefused)

  describe "an ROR, still run one operand after the other" do
    it "refuses an ROR whose left side read a record its right side makes earlier" do
      outs <- run (notice "ROR" "`possession` OP `notice`" noticeThenClaim)
      case outs of
        [o] -> o `shouldMention` ["read each other's records", "an ROR", "over the whole trace"]
        _ -> expectationFailure ("expected one directive, got " <> show outs)

  describe "the check-time warning" do
    it "warns on an ROR whose operands can reach a read and a write of one cell" do
      ws <- warnings (notice "ROR" "`possession` OP `notice`" noticeThenClaim)
      [ (w.op, w.cell, prettyLayout <$> w.readerSide.rule, prettyLayout <$> w.writerSide.rule) | w <- ws ]
        `shouldBe` [("ROR", "notice given", Just "possession", Just "notice")]
      ts <- warningTexts (notice "ROR" "`possession` OP `notice`" noticeThenClaim)
      ts `shouldSatisfy` all ("may read each other's records" `Text.isInfixOf`)

    it "no longer warns on a RAND or an EVERY, whose operands run in step" do
      a <- warnings (dinner "`Alice's evening` RAND `Bob's evening`")
      b <- warnings (fork "Alice, Bob")
      c <- warnings (distributive "Alice, Bob")
      d <- warnings (notice "RAND" "`notice` OP `possession`" noticeThenClaim)
      (a <> b <> c <> d) `shouldBe` []

    it "does not warn where no operand reads what another writes" do
      a <- warnings noShared
      b <- warnings ownLedgers
      (a <> b) `shouldBe` []
