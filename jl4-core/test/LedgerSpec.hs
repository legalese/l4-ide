-- | The instance ledger of OPERATIONAL-LOWERING-SPEC, work package WPO0:
-- the pure ledger (rows, the store interface and its in-memory store,
-- 'appendIf', the position query).
--
-- The conformance fixture is the brief's own
-- @jl4/examples/explore/brief/d3-atomic.l4@, read from the tree, and the
-- strict-mode pair is @jl4/examples/explore/ledger/d3-reopen.l4@. Every
-- verdict below is the evaluator's, read back through "L4.Lts.WhatIf"'s
-- classification; nothing here knows what the dinner rule says.
--
-- §8 acceptance items covered here: Sequence A, Sequence B (less its
-- @l4 run@ half, which is @l4-cli-test@'s "two oracles"), bitemporal,
-- idempotency before the guard. Concurrency against the in-memory store is
-- sampled, not the WPO2 item.
module LedgerSpec (spec) where

import Control.Concurrent (forkIO)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Monad (forM, forM_)
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.Ratio ((%))
import qualified Data.Text as Text
import qualified Data.Text.IO as Text
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import System.Directory (doesFileExist, getCurrentDirectory)
import System.FilePath (takeDirectory, (</>))
import Test.Hspec
import Test.Hspec.QuickCheck (modifyMaxSuccess, prop)
import Test.QuickCheck hiding (Result, replay)

import L4.EvaluateLazy (resolveEvalConfig)
import L4.Ledger.Append
import L4.Ledger.Replay
import L4.Ledger.Row
import L4.Ledger.Store
import L4.Lts.WhatIf (Candidate (..), CandidateKind (..), Outcome (..), discharging)
import L4.TracePolicy (apiDefaultPolicy)

spec :: Spec
spec = do
  deps <- runIO loadDeployments
  pureSpec
  storeSpec
  dinnerSpec deps
  strictSpec deps
  positionSpec deps

----------------------------------------------------------------------------
-- Fixtures
----------------------------------------------------------------------------

data Deps = MkDeps
  { dinner :: Deployment
    -- ^ d3-atomic.l4, versioned on the dinner status record
  , reopen :: Deployment
    -- ^ d3-reopen.l4, the same
  }

-- | The fixtures, read from the tree. `cabal test` runs in the package
-- directory, so the repository is found by walking up to it; a missing
-- fixture fails loudly rather than skipping.
loadDeployments :: IO Deps
loadDeployments = do
  root <- getCurrentDirectory >>= findRoot
  let read' rel = Text.readFile (root </> rel)
  d3 <- read' "jl4/examples/explore/brief/d3-atomic.l4"
  props <- read' "jl4/examples/explore/brief/properties.l4"
  re <- read' "jl4/examples/explore/ledger/d3-reopen.l4"
  let dep i src = MkDeployment
        { deploymentId = i
        , deploymentVersion = i <> "-v1"
        , deploymentSource = src
        , deploymentImports = [("properties", props)]
        , versionedCells = ["dinner status record"]
        }
  pure MkDeps {dinner = dep "d3-atomic" d3, reopen = dep "d3-reopen" re}
  where
    findRoot d = do
      found <- doesFileExist (d </> "jl4/examples/explore/brief/d3-atomic.l4")
      if found then pure d
      else if takeDirectory d == d then fail "LedgerSpec: the repository root (jl4/examples/explore/brief/d3-atomic.l4) was not found above the working directory"
      else findRoot (takeDirectory d)

-- | A ledger over a fresh in-memory store, with a clock the test sets.
data Env = MkEnv
  { ledgerOf :: Ledger
  , clockRef :: IORef Rational
  }

newEnv :: IO Env
newEnv = do
  st <- newMemoryStore
  ref <- newIORef 0
  cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
  pure MkEnv
    { ledgerOf = MkLedger {store = st, clock = readIORef ref, evalConfig = cfg, timeBound = 120000000, retryCap = 8}
    , clockRef = ref
    }

fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 10 25) (secondsToDiffTime 0)

-- | Set the clock, then do something.
atClock :: Env -> Rational -> IO a -> IO a
atClock env t act = writeIORef env.clockRef t >> act

-- The evening's acts, as the fixtures spell them.
check, bobBuys, bobCancels, buy, buyUnanswered, deliver, done :: Text.Text
check = "`Alice checks whether dinner is bought`"
bobBuys = "`ledger records Bob's purchase`"
bobCancels = "`ledger records Bob's cancellation`"
buy = "`Alice buys dinner` TRUE"
buyUnanswered = "`Alice buys dinner` FALSE"
deliver = "`Messages delivers the message`"
done = "`Alice is done`"

-- | An act by World (every act's party, option C), keyed.
proposal :: Text.Text -> Text.Text -> Proposed
proposal key a = MkProposed
  { party = "World", action = a, claimedAt = Nothing, decidedAgainst = Nothing
  , idempotencyKey = key, strict = False }

claiming :: Rational -> Proposed -> Proposed
claiming t p = p {claimedAt = Just t}

-- | Decided against this head, strictly or not.
against :: SeqNo -> Bool -> Proposed -> Proposed
against seen s p = MkProposed
  { party = p.party, action = p.action, claimedAt = p.claimedAt, decidedAgainst = Just seen
  , idempotencyKey = p.idempotencyKey, strict = s }

-- | The result, which must be 'Appended'.
appended :: HasCallStack => Result -> IO Result
appended r = case r of
  Appended {} -> pure r
  other -> do
    expectationFailure ("expected Appended, got " <> show other)
    pure other

rowsOf :: Env -> Instance -> IO [Row]
rowsOf env inst = env.ledgerOf.store.readRows (instanceKey inst)

-- | Create the instance at 18:00 and propose each act at its time.
history :: Env -> Instance -> [(Rational, Proposed)] -> IO [Result]
history env inst acts = do
  _ <- atClock env 64800 (createInstance env.ledgerOf inst "`the arrangement`") >>= appended
  forM acts \ (t, p) -> atClock env t (appendIf env.ledgerOf inst p) >>= appended

commitsDinner :: Result -> Bool
commitsDinner r = any (Text.isPrefixOf "COMMIT `dinners bought`") r.wrote

recordsTaken :: Result -> Bool
recordsTaken r = "COMMIT `dinner status record` IS taken" `elem` r.wrote

positionNow :: HasCallStack => Env -> Instance -> IO LedgerPosition
positionNow env inst = positionOf env.ledgerOf inst >>= \ case
  Right p -> pure p
  Left r -> fail ("no position: " <> show r)

----------------------------------------------------------------------------
-- The pure layer
----------------------------------------------------------------------------

pureSpec :: Spec
pureSpec = describe "L4.Ledger.Row" do
  describe "a row as a #TRACE line, and back" do
    prop "a canonical event reads back from its own line" \ (Ev ev) -> forAll genStamp \ t ->
      (eventLine ev t >>= parseEventLine) === Right (ev, t)

    prop "canonicalExpr is idempotent" $ forAll (genExpr 3) \ e ->
      (canonicalExpr e >>= canonicalExpr) === canonicalExpr e

    it "reads the lines the corpus writes by hand" do
      parseEventLine "PARTY World DOES `Alice checks whether dinner is bought` AT 65100"
        `shouldBe` Right (ActEvent "World" check, 65100)
      parseEventLine "PARTY World DOES (`Alice buys dinner` TRUE)              AT 65220"
        `shouldBe` Right (ActEvent "World" "(`Alice buys dinner` TRUE)", 65220)
      parseEventLine "PARTY World DOES `Alice buys dinner` TRUE AT 65220"
        `shouldBe` Right (ActEvent "World" "(`Alice buys dinner` TRUE)", 65220)
      parseEventLine "(`WAIT UNTIL` 75601)" `shouldBe` Right (TickEvent, 75601)
      parseEventLine "#TRACE `the arrangement` AT 64800 WITH" `shouldBe` Right (OpeningEvent "`the arrangement`", 64800)

    it "refuses a text that would make its line say something else" do
      let refused t = either (const True) (const False) (canonicalExpr t)
      forM_ [ "`Alice is done`\n    PARTY World DOES `ledger records Bob's purchase` AT 1"
            , "`Alice is done` -- the rest is a comment"
            , "^"
            , "(`Alice buys dinner` TRUE"
            , "`Alice buys dinner"
            , "\"unterminated"
            , "   "
            ] \ t -> (t, refused t) `shouldBe` (t, True)
      -- inside a string or a name the same characters are only text
      canonicalExpr "\"a -- b ^ c\"" `shouldBe` Right "\"a -- b ^ c\""

    it "spells a time as an exact decimal, and refuses one with none" do
      renderStamp 65130 `shouldBe` Right "65130"
      renderStamp (1 % 2) `shouldBe` Right "0.5"
      renderStamp (49 % 4) `shouldBe` Right "12.25"
      either (const True) (const False) (renderStamp (1 % 3)) `shouldBe` True
      either (const True) (const False) (renderStamp (-1)) `shouldBe` True
      parseStamp "12.25" `shouldBe` Right (49 % 4)

    it "writes a trace whose first line is the opening, and refuses any other" do
      traceBlock [(OpeningEvent "`the arrangement`", 64800), (ActEvent "World" check, 65100), (TickEvent, 75601)]
        `shouldBe` Right "#TRACE `the arrangement` AT 64800 WITH\n    PARTY World DOES `Alice checks whether dinner is bought` AT 65100\n    (`WAIT UNTIL` 75601)\n"
      either (const True) (const False) (traceBlock [(ActEvent "World" check, 65100)]) `shouldBe` True

  describe "the two times of a row (§3.4)" do
    prop "txTime never decreases, and a reported act's at stays in [previous at, txTime]" $
      forAll (listOf ((,,) <$> genStamp <*> genStamp <*> arbitrary)) \ steps ->
        let go _ _ [] = property True
            go prevAt prevTx ((now, claimed, decides) : rest) =
              let tx = nextTxTime (Just prevTx) now
                  t = if decides then tx else clampReported prevAt tx claimed
              in counterexample (show (prevAt, prevTx, now, claimed, decides, tx, t))
                   (tx >= prevTx .&&. tx >= now .&&. t >= prevAt .&&. t <= tx .&&. go t tx rest)
        in go 0 0 steps

    it "clamps a claimed time to the previous row's at and to txTime" do
      clampReported 64800 65100 60000 `shouldBe` 64800
      clampReported 64800 65100 99999 `shouldBe` 65100
      clampReported 64800 65100 65000 `shouldBe` 65000
      nextTxTime (Just 65300) 65250 `shouldBe` 65300

-- | An event in canonical form, for the round trip.
newtype Ev = Ev RowEvent
  deriving stock Show

instance Arbitrary Ev where
  arbitrary = Ev <$> oneof
    [ OpeningEvent <$> canonical (genExpr 3)
    , ActEvent <$> canonical (genExpr 2) <*> canonical (genExpr 3)
    , pure TickEvent ]
    where
      canonical g = g >>= \ e -> either (const discard) pure (canonicalExpr e)

-- | L4-ish expressions, with the keywords a line splits on hidden where
-- the line must not see them: in names, in strings, in parentheses.
genExpr :: Int -> Gen Text.Text
genExpr 0 = genAtom
genExpr n = oneof
  [ genAtom
  , (\ a b -> a <> " " <> b) <$> genExpr (n - 1) <*> genAtom
  , (\ e -> "(" <> e <> ")") <$> genExpr (n - 1)
  , (\ e -> "(" <> e <> " AT 5)") <$> genExpr (n - 1)
  ]

genAtom :: Gen Text.Text
genAtom = oneof
  [ elements ["World", "Alice", "TRUE", "FALSE", "0", "42", "`Alice buys dinner`", "`a name with DOES and AT in it`", "`Bob's`"]
  , (\ s -> "\"" <> s <> "\"") . Text.concat <$> listOf (elements ["a", " ", "DOES", "AT", "\\\"", "\\\\", "(", ")", "`", "^", "--", "#TRACE"])
  , Text.pack <$> listOf1 (elements ['a' .. 'z'])
  ]

-- | Times with an exact decimal form, as the ledger clock gives.
genStamp :: Gen Rational
genStamp = do
  n <- chooseInteger (0, 10000000)
  a <- chooseInt (0, 3)
  b <- chooseInt (0, 3)
  pure (n % (2 ^ a * 5 ^ b))

----------------------------------------------------------------------------
-- The store
----------------------------------------------------------------------------

storeSpec :: Spec
storeSpec = describe "L4.Ledger.Store (in-memory)" do
  let k = MkInstanceKey {deployment = "d", instanceName = "i"}
      mkRow n tag = MkRow
        { seqNo = n, event = TickEvent, at = 0, txTime = 0, verdict = VAdvancing
        , decidedAgainst = Nothing, idempotencyKey = Just tag, ruleVersion = "t" }

  it "appends only at head plus one, and says the head when it refuses" do
    st <- newMemoryStore
    st.readRows k >>= (`shouldBe` [])
    st.appendRow k 1 (mkRow 1 "a") >>= (`shouldBe` Right ())
    st.appendRow k 1 (mkRow 1 "b") >>= (`shouldBe` Left 1)
    st.appendRow k 3 (mkRow 3 "c") >>= (`shouldBe` Left 1)
    st.appendRow k 2 (mkRow 2 "d") >>= (`shouldBe` Right ())
    map (.seqNo) <$> st.readRows k >>= (`shouldBe` [1, 2])
    st.readRows k {instanceName = "other"} >>= (`shouldBe` [])

  it "leaves a gapless history when appenders race" do
    st <- newMemoryStore
    let threads = 8
        each = 20
        appendOne tag = do
          rows <- st.readRows k
          let n = length rows + 1
          st.appendRow k n (mkRow n tag) >>= either (const (appendOne tag)) pure
    dones <- forM [1 .. threads :: Int] \ t -> do
      v <- newEmptyMVar
      _ <- forkIO (mapM_ (\ i -> appendOne (Text.pack (show (t, i)))) [1 .. each :: Int] >> putMVar v ())
      pure v
    mapM_ takeMVar dones
    rows <- st.readRows k
    map (.seqNo) rows `shouldBe` [1 .. threads * each]
    length (filter (\ r -> maybe False (Text.isPrefixOf "(3,") r.idempotencyKey) rows) `shouldBe` each

----------------------------------------------------------------------------
-- appendIf on the dinner fixture
----------------------------------------------------------------------------

dinnerSpec :: Deps -> Spec
dinnerSpec deps = describe "appendIf on d3-atomic.l4" do
  it "Sequence A (§6): four rows, the fourth row's step logs the block, and no dinner is committed" do
    env <- newEnv
    let inst = MkInstance deps.dinner "A"
    rs <- history env inst
      [ (65100, proposal "A2" check)
      , (65160, proposal "A3" bobBuys)
      , (65220, proposal "A4" buy) ]
    rows <- rowsOf env inst
    map (.seqNo) rows `shouldBe` [1 .. 4]
    map (.at) rows `shouldBe` [64800, 65100, 65160, 65220]
    map (.verdict) rows `shouldBe` replicate 4 VAdvancing
    case rs of
      [_, r3, r4] -> do
        recordsTaken r3 `shouldBe` True
        r4.row.event `shouldBe` ActEvent "World" "(`Alice buys dinner` TRUE)"
        r4.wrote `shouldBe` ["RECORD Alice's `belief` IS taken", "RECORD Alice's `plan` IS stopped"]
      _ -> expectationFailure "three appends"
    any commitsDinner rs `shouldBe` False
    pos <- positionNow env inst
    officialCount "dinners bought" pos.ledgerAtHead `shouldBe` 0

  it "Sequence B (§6): the buy is row 3 and commits the dinner, and Bob's purchase is row 4" do
    env <- newEnv
    let inst = MkInstance deps.dinner "B"
    rs <- history env inst
      [ (65100, proposal "B2" check)
      , (65130, proposal "B3" buy)
      , (65160, proposal "B4" bobBuys) ]
    case rs of
      [_, r3, r4] -> do
        r3.row.seqNo `shouldBe` 3
        r3.wrote `shouldContain` ["COMMIT `dinners bought` IS `dinner for two`", "COMMIT `open at acceptance` IS TRUE"]
        r4.row.seqNo `shouldBe` 4
        recordsTaken r4 `shouldBe` True
        commitsDinner r4 `shouldBe` False
      _ -> expectationFailure "three appends"
    pos <- positionNow env inst
    pos.terminal `shouldBe` False
    officialCount "dinners bought" pos.ledgerAtHead `shouldBe` 1

  it "is bitemporal (§3.4, R-O1): a reported act's claimed time is clamped, a committing act takes txTime, and txTime never decreases" do
    env <- newEnv
    let inst = MkInstance deps.dinner "bitemporal"
    _ <- history env inst
      [ (65100, claiming 60000 (proposal "t2" check))     -- before the previous row's at
      , (65160, claiming 65000 (proposal "t3" bobBuys))   -- COMMITs: the claim is ignored
      , (65300, claiming 65280 (proposal "t4" deliver))   -- inside the window: kept
      , (65250, claiming 99999 (proposal "t5" done)) ]    -- the clock stepped back; a claim past txTime
    rows <- rowsOf env inst
    map (.at) rows `shouldBe` [64800, 64800, 65160, 65280, 65300]
    map (.txTime) rows `shouldBe` [64800, 65100, 65160, 65300, 65300]
    map (.verdict) rows `shouldBe` replicate 5 VAdvancing

  it "looks the idempotency key up before the guard: a retry reads done, never forbidden" do
    env <- newEnv
    let inst = MkInstance deps.dinner "idempotent"
        l = env.ledgerOf
    _ <- history env inst [(65100, proposal "k" check), (65160, proposal "b" bobBuys)]
    -- the same proposal again
    r <- atClock env 65170 (appendIf l inst (proposal "k" check)) >>= appended
    r.row.seqNo `shouldBe` 2
    r.replayed `shouldBe` False
    -- the same key, sent strict against head 1: the guard would refuse it...
    atClock env 65180 (appendIf l inst (against 1 True (proposal "fresh" check))) >>= \ case
      Conflict {} -> pure ()
      other -> expectationFailure ("a fresh key is held to the guard: " <> show other)
    -- ...and the key is found first, so the original row is returned
    r' <- atClock env 65180 (appendIf l inst (against 1 True (proposal "k" check))) >>= appended
    r'.row.seqNo `shouldBe` 2
    -- a reused key with a different payload is not compared (D-O1, open)
    r'' <- atClock env 65190 (appendIf l inst (proposal "k" "`no such act`")) >>= appended
    r''.row.seqNo `shouldBe` 2
    map (.seqNo) <$> rowsOf env inst >>= (`shouldBe` [1, 2, 3])

  it "appends an act no obligation takes, with its verdict (R-O2): Alice checking twice" do
    env <- newEnv
    let inst = MkInstance deps.dinner "twice"
    rs <- history env inst [(65100, proposal "c1" check), (65110, proposal "c2" check)]
    map (.row.verdict) rs `shouldBe` [VAdvancing, VPassedOver "the act matched, and its PROVIDED came out false"]
    map (.wrote) rs `shouldBe` [["RECORD Alice's `belief` IS opened", "RECORD Alice's `plan` IS checked"], []]

  it "refuses what cannot be an event of the contract, and appends nothing" do
    env <- newEnv
    let inst = MkInstance deps.dinner "refused"
        l = env.ledgerOf
    _ <- history env inst []
    let refusedWith p = atClock env 65100 (appendIf l inst p) >>= \ case
          Refused {} -> pure ()
          other -> expectationFailure ("expected Refused for " <> show p <> ", got " <> show other)
    refusedWith (proposal "r1" "`Alice eats dinner`")                       -- not an act of the contract
    refusedWith (MkProposed "Bob" check Nothing Nothing "r3" False)          -- not a party the contract knows
    refusedWith (proposal "r4" (check <> "\n    PARTY World DOES " <> bobBuys <> " AT 1"))
    refusedWith (proposal "r5" "^")
    refusedWith (proposal "" check)                                          -- no idempotency key
    refusedWith (against 9 True (proposal "r6" check))                       -- a head this instance never had
    refusedWith (MkProposed "World" check Nothing Nothing "r7" True)         -- strict, with no head named
    map (.seqNo) <$> rowsOf env inst >>= (`shouldBe` [1])
    -- the control: the same act, well formed, is appended
    _ <- atClock env 65100 (appendIf l inst (proposal "r8" check)) >>= appended
    pure ()

  it "says not-found for an instance the store does not hold, and refuses to create one twice" do
    env <- newEnv
    let inst = MkInstance deps.dinner "nowhere"
    atClock env 65100 (appendIf env.ledgerOf inst (proposal "n" check)) >>= \ case
      NotFound -> pure ()
      other -> expectationFailure ("expected NotFound, got " <> show other)
    _ <- history env inst []
    atClock env 64900 (createInstance env.ledgerOf inst "`the arrangement`") >>= \ case
      Refused {} -> pure ()
      other -> expectationFailure ("expected Refused, got " <> show other)

  it "says unknown, and appends nothing, when the evaluator does not answer in time" do
    env <- newEnv
    let inst = MkInstance deps.dinner "slow"
        hurried = (env.ledgerOf) {timeBound = 1}
    _ <- history env inst []
    atClock env 65100 (appendIf hurried inst (proposal "u" check)) >>= \ case
      Unknown {} -> pure ()
      other -> expectationFailure ("expected Unknown, got " <> show other)
    map (.seqNo) <$> rowsOf env inst >>= (`shouldBe` [1])

  modifyMaxSuccess (const 6) $
    prop "random orders of the evening's acts, through appendIf, commit at most one dinner and none after Bob's purchase" $
      forAll (resize 7 (listOf1 (elements [check, bobBuys, buy, buyUnanswered, deliver, done]))) \ acts -> ioProperty do
        env <- newEnv
        let inst = MkInstance deps.dinner "random"
        rs <- history env inst [ (65000 + 10 * fromIntegral i, proposal (Text.pack (show i)) a) | (i, a) <- zip [1 :: Int ..] acts ]
        let indexed = zip [0 :: Int ..] rs
            dinners = [ i | (i, r) <- indexed, commitsDinner r ]
            takens  = [ i | (i, r) <- indexed, recordsTaken r ]
        pure $ counterexample (show (acts, map (.wrote) rs)) $
          length dinners <= 1 .&&. and [ d < t | d <- dinners, t <- takens ]

----------------------------------------------------------------------------
-- Strict mode: the per-cell version (§2, R-O4)
----------------------------------------------------------------------------

strictSpec :: Deps -> Spec
strictSpec deps = describe "strict mode on d3-reopen.l4: Bob's purchase recorded and cancelled between Alice's read and her buy" do
  let pairHistory env name = do
        let inst = MkInstance deps.reopen name
        _ <- history env inst
          [ (65100, proposal "p2" check)
          , (65160, proposal "p3" bobBuys)
          , (65190, proposal "p4" bobCancels) ]
        pure inst

  it "the default semantic guard lets Alice buy: dinner is unbought again" do
    env <- newEnv
    inst <- pairHistory env "default"
    r <- atClock env 65220 (appendIf env.ledgerOf inst (against 2 False (proposal "p5" buy))) >>= appended
    r.row.seqNo `shouldBe` 5
    commitsDinner r `shouldBe` True
    r.wrote `shouldContain` ["COMMIT `open at acceptance` IS TRUE"]

  it "strict = True refuses the same proposal with Conflict: the cell's version moved by two, and nothing is appended" do
    env <- newEnv
    inst <- pairHistory env "strict"
    atClock env 65220 (appendIf env.ledgerOf inst (against 2 True (proposal "p5" buy))) >>= \ case
      Conflict why h -> do
        h `shouldBe` 4
        why `shouldBe` "the version of `dinner status record` moved from 1 to 3"
      other -> expectationFailure ("expected Conflict, got " <> show other)
    map (.seqNo) <$> rowsOf env inst >>= (`shouldBe` [1 .. 4])
    -- read again, decide against the true head, and the strict buy goes through
    r <- atClock env 65230 (appendIf env.ledgerOf inst (against 4 True (proposal "p6" buy))) >>= appended
    commitsDinner r `shouldBe` True

  it "versions the cell, not the log: an append that leaves the record alone is no conflict, unless the whole head is versioned" do
    env <- newEnv
    let perCell = MkInstance deps.dinner "per cell"
        wholeHead = MkInstance ((deps.dinner) {versionedCells = []}) "whole head"
    forM_ [perCell, wholeHead] \ inst ->
      history env inst [(65100, proposal "w2" check), (65110, proposal "w3" buyUnanswered)]
    r <- atClock env 65120 (appendIf env.ledgerOf perCell (against 2 True (proposal "w4" buy))) >>= appended
    commitsDinner r `shouldBe` True
    atClock env 65120 (appendIf env.ledgerOf wholeHead (against 2 True (proposal "w4" buy))) >>= \ case
      Conflict why 3 -> why `shouldBe` "the head moved from 2 to 3"
      other -> expectationFailure ("expected Conflict at head 3, got " <> show other)

----------------------------------------------------------------------------
-- The position query (§3.3)
----------------------------------------------------------------------------

positionSpec :: Deps -> Spec
positionSpec deps = describe "the position query" do
  it "answers what may be done now (§3.3), stamped with its head" do
    env <- newEnv
    let inst = MkInstance deps.dinner "position"
    _ <- history env inst [(65100, proposal "q2" check)]
    pos <- positionNow env inst
    pos.headSeq `shouldBe` 2
    pos.nextDeadline `shouldBe` Just 75600
    pos.terminal `shouldBe` False
    [ () | o <- discharging pos.enabled, TickPast 75600 _ <- [o.ocCandidate.cdKind] ] `shouldBe` [()]
