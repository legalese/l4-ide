{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | The parts of @l4 explore --emit@ (REGULATIVE-LOWERING-SPEC.md §6.1,
-- WP3) that the dinner-race fixtures cannot reach, because no label of
-- theirs has the character or the name that triggers them. The emitted
-- files of the fixtures are pinned in @jl4/tests/LtsExplore.hs@.
--
--   1. the @.aut@ is one line per edge, in order, under a @des@ header of
--      the counts; a double quote in a label is written as a single quote,
--      since mCRL2's reader cannot escape one; a file in which that would
--      merge two labels, or turn one into @tau@, mCRL2's silent action, is
--      refused by name, not written;
--   2. an identifier is ASCII letters, digits and underscores, starting with
--      a letter, whatever the name it came from.
module LtsEmitSpec (spec) where

import qualified Data.Text as Text
import Test.Hspec

import L4.Lts.Explore (EdgeKind (..), Transition (..))
import L4.Lts.Explore.Emit.Aut (emitAut)
import L4.Lts.Explore.Emit.Model (identifier)

edge :: Int -> Text.Text -> Int -> Transition
edge i l j = MkTransition {tnFrom = i, tnLabel = l, tnTo = j, tnKind = EdgeAct}

spec :: Spec
spec = describe "l4 explore --emit" $ do
  describe "the .aut" $ do
    it "is a des header of the counts and one line per edge, in order" $
      emitAut 2 [edge 0 "PARTY World DOES `Bob's act`" 1, edge 1 "terminal" 1]
        `shouldBe` Right (Text.unlines
          [ "des (0,2,2)"
          , "(0,\"PARTY World DOES `Bob's act`\",1)"
          , "(1,\"terminal\",1)" ])

    it "writes a double quote in a label as a single quote, and a label over two lines on one" $
      emitAut 2 [edge 0 "PARTY World DOES pay \"rent\"" 1, edge 1 "time passes\n  the deadline" 1]
        `shouldBe` Right (Text.unlines
          [ "des (0,2,2)"
          , "(0,\"PARTY World DOES pay 'rent'\",1)"
          , "(1,\"time passes the deadline\",1)" ])

    it "refuses, naming both, two labels that would be written the same" $
      case emitAut 2 [edge 0 "pay \"rent\"" 1, edge 0 "pay 'rent'" 1] of
        Left why -> do
          why `shouldSatisfy` Text.isInfixOf "pay \"rent\""
          why `shouldSatisfy` Text.isInfixOf "pay 'rent'"
          why `shouldSatisfy` Text.isInfixOf "would merge them"
        Right t -> expectationFailure ("expected a refusal, got " <> show t)

    it "refuses a label that would be mCRL2's silent action" $
      case emitAut 1 [edge 0 "tau" 0] of
        Left why -> why `shouldSatisfy` Text.isInfixOf "silent action"
        Right t -> expectationFailure ("expected a refusal, got " <> show t)

  describe "identifiers" $
    it "are ASCII letters, digits and underscores, starting with a letter" $
      map identifier ["Alice's belief is stale", "`ledger records Bob's purchase`", "1st act", "été", "--"]
        `shouldBe` ["Alice_s_belief_is_stale", "ledger_records_Bob_s_purchase", "x_1st_act", "t", "x"]
