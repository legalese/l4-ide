{-# LANGUAGE OverloadedStrings #-}

-- | Which rule a @HENCE@ or @LEST@ belongs to (smucclaw/l4-ide#1068).
--
-- A rule has no closing token, so a rule nested in another's @HENCE@ or
-- @LEST@ is still open when the next @HENCE@ or @LEST@ arrives. The parser
-- once gave that keyword to the innermost open rule whatever its column,
-- checking only the first token of its body, so a @LEST@ written at the
-- outer rule's clauses changed meaning with exit 0 everywhere. Now clause
-- columns decide ('L4.Parser.obligation'): a nested rule keeps a @HENCE@ or
-- @LEST@ written at its own clauses, and ends at one written at the clauses
-- of the rule it is nested in.
--
-- 'sameTree' compares the unbracketed layout with the same rule written with
-- brackets, which say outright which rule each @HENCE@ and @LEST@ is on.
-- Brackets leave no node of their own, only tokens in the annotations, so the
-- two parse to the same tree exactly when the two modules are equal once
-- their annotations are cleared ('clearAnno'). (The printer is no help here:
-- 'L4.Print.prettyLayout' prints a nested rule without brackets, one clause
-- per line, so a @LEST@ on the nested rule and one on the outer rule can
-- print the same.)
-- The cases not marked "unchanged" fail on the parser before the fix (main at
-- e51181dc0): the same-line and chain cases did not parse, and the other five
-- parsed to a different tree. The cases marked "unchanged" pass on both and
-- guard the layouts the fix must not move; the hanging ones are the layouts
-- the first version of the fix moved, with exit 0, and the three-deep one is
-- the one it moved the right way.
module ClauseLayoutParserSpec (spec) where

import Base
import qualified Data.Text as T
import L4.ExactPrint (exactprint)
import L4.Parser (PError (..), execProgramParserWithHintPass, execProgramParserWithHintPassUnmemoised)
import L4.Syntax (clearAnno)
import Test.Hspec

spec :: Spec
spec = do
  describe "a HENCE or LEST at the column of a rule's clauses belongs to that rule" $ do
    it "the issue's repro: the outer LEST is the Seller's, the inner LEST the Buyer's" $
      sameTree
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  WITHIN 3"
        , "  HENCE"
        , "    PARTY Buyer"
        , "    MUST payment 100"
        , "    WITHIN 7"
        , "    LEST"
        , "      PARTY Buyer"
        , "      MUST payment 120"
        , "      WITHIN 14"
        , "  LEST BREACH BY Seller"
        ]
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  WITHIN 3"
        , "  HENCE (PARTY Buyer MUST payment 100 WITHIN 7"
        , "         LEST (PARTY Buyer MUST payment 120 WITHIN 14))"
        , "  LEST BREACH BY Seller"
        ]

    it "an inner rule with no LEST of its own does not take the outer LEST" $
      sameTree
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  WITHIN 3"
        , "  HENCE"
        , "    PARTY Buyer"
        , "    MAY cancel"
        , "    WITHIN 7"
        , "  LEST BREACH BY Seller"
        ]
        [ "  PARTY Seller MUST delivery WITHIN 3"
        , "  HENCE (PARTY Buyer MAY cancel WITHIN 7)"
        , "  LEST BREACH BY Seller"
        ]

    it "clauses indented under the head: the clause column, not the head's, decides" $
      sameTree
        [ "    PARTY Seller"
        , "        MUST delivery"
        , "        WITHIN 3"
        , "        HENCE"
        , "            PARTY Buyer"
        , "                MUST payment 100"
        , "                WITHIN 7"
        , "        LEST BREACH BY Seller"
        ]
        [ "  PARTY Seller MUST delivery WITHIN 3"
        , "  HENCE (PARTY Buyer MUST payment 100 WITHIN 7)"
        , "  LEST BREACH BY Seller"
        ]

    it "a rule written on its HENCE's line: the LEST on the next line is the outer rule's" $
      sameTree
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  WITHIN 3"
        , "  HENCE PARTY Buyer MUST payment 100 WITHIN 7"
        , "  LEST BREACH BY Seller"
        ]
        [ "  PARTY Seller MUST delivery WITHIN 3"
        , "  HENCE (PARTY Buyer MUST payment 100 WITHIN 7)"
        , "  LEST BREACH BY Seller"
        ]

    it "a HENCE at the nested rule's own clauses chains after the nested rule" $
      sameTree
        [ "  PARTY Seller MUST delivery WITHIN 3"
        , "  HENCE PARTY Buyer MUST payment 100 WITHIN 7"
        , "        HENCE PARTY Seller MUST delivery WITHIN 9"
        , "  LEST BREACH BY Seller"
        ]
        [ "  PARTY Seller MUST delivery WITHIN 3"
        , "  HENCE (PARTY Buyer MUST payment 100 WITHIN 7 HENCE (PARTY Seller MUST delivery WITHIN 9))"
        , "  LEST BREACH BY Seller"
        ]

    it "unchanged: on ONE line, a later LEST still belongs to the rule on that line" $
      sameTree
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  WITHIN 3"
        , "  HENCE PARTY Buyer MUST payment 100 WITHIN 7 LEST BREACH BY Buyer"
        , "  LEST BREACH BY Seller"
        ]
        [ "  PARTY Seller MUST delivery WITHIN 3"
        , "  HENCE (PARTY Buyer MUST payment 100 WITHIN 7 LEST BREACH BY Buyer)"
        , "  LEST BREACH BY Seller"
        ]

    it "unchanged: past the middle rule's clauses, at no rule's column, a LEST is the innermost rule's" $
      sameTree
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  WITHIN 3"
        , "  HENCE"
        , "    PARTY Buyer"
        , "    MUST payment 100"
        , "    WITHIN 7"
        , "    LEST"
        , "      PARTY Buyer"
        , "      MUST payment 120"
        , "      WITHIN 14"
        , "     LEST BREACH BY Seller"
        ]
        [ "  PARTY Seller MUST delivery WITHIN 3"
        , "  HENCE (PARTY Buyer MUST payment 100 WITHIN 7"
        , "         LEST (PARTY Buyer MUST payment 120 WITHIN 14 LEST BREACH BY Seller))"
        ]

    it "unchanged: brackets reset the columns, so a mid-line head may have its clauses to its left" $
      sameTree
        [ "    (PARTY Seller"
        , "        MUST delivery"
        , "        WITHIN 3"
        , "        HENCE (PARTY Buyer"
        , "            MUST payment 100"
        , "            WITHIN 7"
        , "            HENCE FULFILLED)"
        , "        LEST BREACH BY Seller)"
        ]
        [ "  PARTY Seller MUST delivery WITHIN 3"
        , "  HENCE (PARTY Buyer MUST payment 100 WITHIN 7 HENCE FULFILLED)"
        , "  LEST BREACH BY Seller"
        ]

  describe "a nested rule written left of the clauses of the rule it is nested in" $ do
    it "unchanged: keeps the LEST written at its own clauses" $
      sameTree
        [ "  PARTY Seller"
        , "      MUST delivery"
        , "      WITHIN 3"
        , "      HENCE"
        , "    PARTY Buyer"
        , "    MUST payment 100"
        , "    WITHIN 7"
        , "    LEST BREACH BY Buyer"
        ]
        [ "  PARTY Seller MUST delivery WITHIN 3"
        , "  HENCE (PARTY Buyer MUST payment 100 WITHIN 7 LEST BREACH BY Buyer)"
        ]

    it "unchanged: keeps the HENCE written at its own clauses" $
      sameTree
        [ "  PARTY Seller"
        , "      MUST delivery"
        , "      WITHIN 3"
        , "      LEST"
        , "    PARTY Buyer"
        , "    MUST payment 100"
        , "    WITHIN 7"
        , "    HENCE PARTY Seller MUST delivery WITHIN 9"
        ]
        [ "  PARTY Seller MUST delivery WITHIN 3"
        , "  LEST (PARTY Buyer MUST payment 100 WITHIN 7 HENCE PARTY Seller MUST delivery WITHIN 9)"
        ]

    it "unchanged: keeps a LEST between its clauses and the outer rule's" $
      sameTree
        [ "  PARTY Seller"
        , "      MUST delivery"
        , "      WITHIN 3"
        , "      HENCE"
        , "    PARTY Buyer"
        , "    MUST payment 100"
        , "    WITHIN 7"
        , "     LEST BREACH BY Buyer"
        ]
        [ "  PARTY Seller MUST delivery WITHIN 3"
        , "  HENCE (PARTY Buyer MUST payment 100 WITHIN 7 LEST BREACH BY Buyer)"
        ]

    it "unchanged: a LEST at the outer rule's clauses, after the nested rule's own, is the outer rule's" $
      sameTree
        [ "  PARTY Seller"
        , "      MUST delivery"
        , "      WITHIN 3"
        , "      HENCE"
        , "    PARTY Buyer"
        , "    MUST payment 100"
        , "    WITHIN 7"
        , "    LEST BREACH BY Buyer"
        , "      LEST BREACH BY Seller"
        ]
        [ "  PARTY Seller MUST delivery WITHIN 3"
        , "  HENCE (PARTY Buyer MUST payment 100 WITHIN 7 LEST BREACH BY Buyer)"
        , "  LEST BREACH BY Seller"
        ]

    it "a LEST left of both rules' clauses ends the nested rule" $
      sameTree
        [ "  PARTY Seller"
        , "      MUST delivery"
        , "      WITHIN 3"
        , "      HENCE"
        , "    PARTY Buyer"
        , "    MUST payment 100"
        , "    WITHIN 7"
        , "  LEST BREACH BY Seller"
        ]
        [ "  PARTY Seller MUST delivery WITHIN 3"
        , "  HENCE (PARTY Buyer MUST payment 100 WITHIN 7)"
        , "  LEST BREACH BY Seller"
        ]

    it "three deep, the middle rule's clauses hanging: each LEST goes to the rule whose clauses it lines up with" $
      sameTree
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  HENCE"
        , "    PARTY Buyer"
        , "        MUST payment 100"
        , "        WITHIN 4"
        , "        HENCE"
        , "      PARTY Seller"
        , "      MUST delivery"
        , "      WITHIN 5"
        , "      LEST BREACH BY Seller"
        , "  LEST BREACH BY Buyer"
        ]
        [ "  PARTY Seller MUST delivery"
        , "  HENCE (PARTY Buyer MUST payment 100 WITHIN 4"
        , "         HENCE (PARTY Seller MUST delivery WITHIN 5 LEST BREACH BY Seller))"
        , "  LEST BREACH BY Buyer"
        ]

  describe "a nested rule whose clauses are at the same column as the outer rule's" $
    it "unchanged: keeps a LEST at that column (the innermost rule wins a tie)" $
      sameTree
        [ "  PARTY Seller"
        , "    MUST delivery"
        , "    WITHIN 3"
        , "    HENCE"
        , "    PARTY Buyer"
        , "    MUST payment 100"
        , "    WITHIN 7"
        , "    LEST BREACH BY Buyer"
        ]
        [ "  PARTY Seller MUST delivery WITHIN 3"
        , "  HENCE (PARTY Buyer MUST payment 100 WITHIN 7 LEST BREACH BY Buyer)"
        ]

  describe "the parser's memo changes nothing on these layouts" $
    for_ memoCases \ (name, body) ->
      it name $ memoChangesNothing (rule body)
  where
    memoCases =
      [ ("the repro", ["  PARTY Seller", "  MUST delivery", "  HENCE", "    PARTY Buyer", "    MUST payment 100", "    LEST", "      PARTY Buyer", "      MUST payment 120", "  LEST BREACH BY Seller"])
      , ("the repro with the inner rule in brackets", ["  PARTY Seller", "  MUST delivery", "  HENCE", "    (PARTY Buyer", "     MUST payment 100", "     LEST", "       PARTY Buyer", "       MUST payment 120)", "  LEST BREACH BY Seller"])
      , ("a second LEST inside brackets", ["  PARTY Seller", "  MUST delivery", "  HENCE", "    (PARTY Buyer", "     MUST payment 100", "     LEST BREACH BY Buyer", "     LEST BREACH BY Seller)"])
      , ("a nested rule left of the outer rule's hanging clauses", ["  PARTY Seller", "      MUST delivery", "      HENCE", "    PARTY Buyer", "    MUST payment 100", "    LEST BREACH BY Buyer", "      LEST BREACH BY Seller"])
      ]

-- | The declarations every case shares; a case's body starts on the line
-- after them.
prologue :: [Text]
prologue =
  [ "DECLARE Person IS ONE OF Seller, Buyer"
  , "DECLARE Action IS ONE OF"
  , "  delivery"
  , "  cancel"
  , "  payment HAS amount IS A NUMBER"
  , ""
  , "GIVETH A DEONTIC Person Action"
  , "c MEANS"
  ]

rule :: [Text] -> Text
rule body = T.unlines (prologue <> body)

uri :: NormalizedUri
uri = toNormalizedUri (Uri "file:///clause-layout-parser-spec")

-- | Both bodies parse, the first exact-prints back to its source, and the two
-- are the same module once their annotations are cleared.
sameTree :: [Text] -> [Text] -> Expectation
sameTree unbracketed bracketed =
  case (execProgramParserWithHintPass uri (rule unbracketed), execProgramParserWithHintPass uri (rule bracketed)) of
    (Left errs, _) -> expectationFailure ("the unbracketed layout did not parse: " <> errors errs)
    (_, Left errs) -> expectationFailure ("the bracketed layout did not parse: " <> errors errs)
    (Right (m1, _, _), Right (m2, _, _)) -> do
      case exactprint m1 of
        Left err -> expectationFailure ("exactprint failed: " <> show err)
        Right printed -> printed `shouldBe` rule unbracketed
      clearAnno m1 `shouldBe` clearAnno m2

-- | Parse with the memo on and off ('L4.Parser.clauseThreshold' says why the
-- memo need not key on the threshold); both must give the same answer.
memoChangesNothing :: Text -> Expectation
memoChangesNothing src =
  (execProgramParserWithHintPass uri src == execProgramParserWithHintPassUnmemoised uri src) `shouldBe` True

errors :: (Foldable f) => f PError -> String
errors errs = unlines [show e.range <> "\n" <> T.unpack e.message | e <- toList errs]
