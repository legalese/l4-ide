{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Pure unit tests for the bitemporal ledger fold (smucclaw/l4-ide#914 §2B).
--
-- These exercise 'readCellBitemporal' / 'readCellAllBitemporal' directly on
-- hand-built ledgers — no 'Eval' monad, no machine. The machine-level wiring
-- (stamping at RECORD, ambient bounds at RECALL) is covered by
-- 'BitemporalRecallSpec' and the @jl4/examples/ok/ledger/bitemporal-*@
-- goldens.
--
-- The load-bearing invariants locked here:
--
--   * COMPAT: with both bounds unset the fold IS the historical
--     last-write-wins projection — checked differentially against the
--     pre-bitemporal implementation (@Map.lookup path . snapshot@), not just
--     against 'readCell' (which is nowadays /defined/ as the unbounded
--     instantiation).
--   * tx cutoff: entries appended after an AS-OF bound are invisible.
--   * vt intervals are POSITIONAL: an entry's interval is closed by the next
--     visible same-cell entry with a later effective valid-from; entries for
--     OTHER cells close nothing; append order does not matter for distinct
--     valid times (backdating works).
--   * same-vt correction: the later append wins — by LOG POSITION, never by
--     'txTime' comparison ('txTime' is a per-run constant, so all real
--     entries in one run share it).
--   * an \"as of before the facts\" valid-time read is a principled miss.
module BitemporalSubstrateSpec (spec) where

import qualified Data.Map.Strict as Map

import L4.Evaluate.Ledger
  ( Ledger
  , LedgerEvent (..)
  , Provenance (..)
  , effectiveVt
  , emptyStore
  , readCell
  , readCellAll
  , readCellAllBitemporal
  , readCellBitemporal
  , snapshot
  , storeAppendOwn
  , storeOwnLedger
  )
import L4.Evaluate.ValueLazy (Value (..), WHNF)

import Data.Text (Text)
import Data.Time (Day, UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

-- Build a ledger from a list of events using only the exported append API
-- (oldest-first input, exactly the order the machine would append in).
mkLedger :: [LedgerEvent] -> Ledger
mkLedger evs =
  storeOwnLedger "t" (foldl' (\s e -> storeAppendOwn "t" e s) emptyStore evs)

-- Two distinct transaction instants (across-run scale); within one run all
-- entries share one instant, which is why the same-tx cases below matter.
tx1, tx2 :: UTCTime
tx1 = UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 0)
tx2 = UTCTime (fromGregorian 2026 6 1) (secondsToDiffTime 0)

d :: Integer -> Int -> Int -> Day
d = fromGregorian

entry :: Text -> Rational -> UTCTime -> Maybe Day -> LedgerEvent
entry cell n tx vt =
  Assign [cell] (ValNumber n)
    MkProvenance { party = "t", source = "RECORD", txTime = tx, vtFrom = vt }

-- 'WHNF' has no 'Eq' (it can contain 'Reference's); the literal numbers we
-- store contain none, so their 'Show' is total and stable.
sv :: Maybe WHNF -> Maybe String
sv = fmap show

svs :: [WHNF] -> [String]
svs = map show

num :: Rational -> Maybe String
num = Just . show . (ValNumber :: Rational -> WHNF)

spec :: Spec
spec = describe "bitemporal ledger fold (#914 §2B)" $ do

  describe "COMPAT: both bounds unset == historical last-write-wins" $ do
    let led = mkLedger
          [ entry "a" 1 tx1 Nothing
          , entry "b" 5 tx1 (Just (d 2020 1 1))
          , entry "a" 2 tx2 (Just (d 2019 6 1))   -- backdated vt must NOT affect the unbounded read
          , entry "a" 3 tx2 Nothing
          ]
    it "matches the pre-bitemporal snapshot projection for every cell" $ do
      sv (readCellBitemporal Nothing Nothing ["a"] led) `shouldBe` sv (Map.lookup ["a"] (snapshot led))
      sv (readCellBitemporal Nothing Nothing ["b"] led) `shouldBe` sv (Map.lookup ["b"] (snapshot led))
      sv (readCellBitemporal Nothing Nothing ["c"] led) `shouldBe` sv (Map.lookup ["c"] (snapshot led))
    it "readCell is the unbounded instantiation (last write wins, vt ignored)" $ do
      sv (readCell ["a"] led) `shouldBe` num 3
      sv (readCell ["b"] led) `shouldBe` num 5
      sv (readCell ["nope"] led) `shouldBe` Nothing
    it "readCellAll is the unbounded instantiation (all writes, append order)" $
      svs (readCellAll ["a"] led) `shouldBe` svs [ValNumber 1, ValNumber 2, ValNumber 3]

  describe "tx cutoff (EVAL AS OF SYSTEM TIME)" $ do
    let led = mkLedger
          [ entry "a" 1 tx1 Nothing
          , entry "a" 2 tx2 Nothing
          ]
    it "a bound between the two appends hides the later one" $
      sv (readCellBitemporal (Just tx1) Nothing ["a"] led) `shouldBe` num 1
    it "a bound before every append hides everything" $ do
      let early = UTCTime (fromGregorian 2020 1 1) (secondsToDiffTime 0)
      sv (readCellBitemporal (Just early) Nothing ["a"] led) `shouldBe` Nothing
    it "the bound is inclusive (tx == bound is visible)" $
      sv (readCellBitemporal (Just tx2) Nothing ["a"] led) `shouldBe` num 2
    it "readCellAllBitemporal applies the same cutoff, order preserved" $ do
      svs (readCellAllBitemporal (Just tx1) ["a"] led) `shouldBe` svs [ValNumber 1]
      svs (readCellAllBitemporal Nothing ["a"] led) `shouldBe` svs [ValNumber 1, ValNumber 2]

  describe "vt interval selection (EVAL UNDER VALID TIME)" $ do
    -- GST-style regime history: 7 from 2023-01-01, 9 from 2024-01-01.
    let led = mkLedger
          [ entry "rate" 7 tx1 (Just (d 2023 1 1))
          , entry "rate" 9 tx1 (Just (d 2024 1 1))
          ]
    it "a point inside the earlier interval selects the earlier entry" $
      sv (readCellBitemporal Nothing (Just (d 2023 6 1)) ["rate"] led) `shouldBe` num 7
    it "a point in the (open) latest interval selects the latest entry" $
      sv (readCellBitemporal Nothing (Just (d 2024 6 1)) ["rate"] led) `shouldBe` num 9
    it "the interval start is inclusive (vt == effectiveVt selects it)" $
      sv (readCellBitemporal Nothing (Just (d 2024 1 1)) ["rate"] led) `shouldBe` num 9
    it "a point before every entry's valid-from is a principled miss" $
      sv (readCellBitemporal Nothing (Just (d 2022 6 1)) ["rate"] led) `shouldBe` Nothing
    it "append order does not matter for distinct valid times (backdating)" $ do
      let led' = mkLedger
            [ entry "rate" 9 tx1 (Just (d 2024 1 1))
            , entry "rate" 7 tx1 (Just (d 2023 1 1))   -- backdated append, later position
            ]
      sv (readCellBitemporal Nothing (Just (d 2023 6 1)) ["rate"] led') `shouldBe` num 7
      sv (readCellBitemporal Nothing (Just (d 2024 6 1)) ["rate"] led') `shouldBe` num 9
    it "entries for OTHER cells do not close an interval" $ do
      let led' = mkLedger
            [ entry "rate"  7 tx1 (Just (d 2023 1 1))
            , entry "other" 0 tx1 (Just (d 2023 6 1))
            ]
      sv (readCellBitemporal Nothing (Just (d 2024 1 1)) ["rate"] led') `shouldBe` num 7

  describe "same-vt correction (later transaction wins, positionally)" $ do
    it "two entries at one valid time: the later append wins" $ do
      let led = mkLedger
            [ entry "x" 1 tx1 (Just (d 2024 1 1))
            , entry "x" 2 tx2 (Just (d 2024 1 1))
            ]
      sv (readCellBitemporal Nothing (Just (d 2024 2 1)) ["x"] led) `shouldBe` num 2
    it "IDENTICAL txTime (the within-one-run case): log position breaks the tie" $ do
      let led = mkLedger
            [ entry "x" 1 tx1 (Just (d 2024 1 1))
            , entry "x" 2 tx1 (Just (d 2024 1 1))   -- same vt, same tx: correction
            ]
      sv (readCellBitemporal Nothing (Just (d 2024 2 1)) ["x"] led) `shouldBe` num 2
    it "a correction hidden by the tx cutoff does not win" $ do
      let led = mkLedger
            [ entry "x" 1 tx1 (Just (d 2024 1 1))
            , entry "x" 2 tx2 (Just (d 2024 1 1))   -- the correction, appended later
            ]
      sv (readCellBitemporal (Just tx1) (Just (d 2024 2 1)) ["x"] led) `shouldBe` num 1

  describe "combined bounds (bitemporal point queries)" $ do
    -- John Doe in miniature: an entry whose correction arrives later in
    -- transaction time with an earlier valid time.
    let led = mkLedger
          [ entry "addr" 1 tx1 (Just (d 2023 1 1))   -- believed history
          , entry "addr" 2 tx2 (Just (d 2022 6 1))   -- late-arriving backdated correction
          ]
    it "as-of the early system time, the old belief answers" $
      sv (readCellBitemporal (Just tx1) (Just (d 2023 6 1)) ["addr"] led) `shouldBe` num 1
    it "with current knowledge, the backdated correction answers for later vt too" $
      -- both visible; max effectiveVt <= 2023-06-01 is the 2023-01-01 entry
      sv (readCellBitemporal Nothing (Just (d 2023 6 1)) ["addr"] led) `shouldBe` num 1
    it "with current knowledge, a vt before the believed entry finds the correction" $
      sv (readCellBitemporal Nothing (Just (d 2022 8 1)) ["addr"] led) `shouldBe` num 2

  describe "effectiveVt" $ do
    it "an explicit valid-from wins" $
      effectiveVt MkProvenance { party = "t", source = "RECORD", txTime = tx1, vtFrom = Just (d 2020 5 5) }
        `shouldBe` d 2020 5 5
    it "a contemporaneous write is valid from its (UTC) transaction day" $
      effectiveVt MkProvenance { party = "t", source = "RECORD", txTime = tx2, vtFrom = Nothing }
        `shouldBe` d 2026 6 1
