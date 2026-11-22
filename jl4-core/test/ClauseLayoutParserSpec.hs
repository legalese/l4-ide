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
-- The printer brackets every nested rule ('L4.Print.prettyLayout'), so the
-- two parse to the same tree exactly when the two printed modules are equal.
-- The cases that changed would fail on the parser before the fix: the first
-- four printed a different module, and the same-line and chain cases did not
-- parse. The cases marked "unchanged" pass on both and guard the layouts the
-- fix must not move; the hanging ones are the layouts the first version of the
-- fix moved, with exit 0, and the three-deep one is the one it moved the right
-- way.
module ClauseLayoutParserSpec (spec) where

import Base
import qualified Data.Text as T
import L4.ExactPrint (exactprint)
import L4.Parser (PError (..), execProgramParserWithHintPass, execProgramParserWithHintPassUnmemoised)
import L4.Parser.SrcSpan (SrcPos (..), SrcSpan (..))
import L4.Print (prettyLayout)
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

  describe "a HENCE or LEST that is a rule's by its column, but whose slot is used, is refused by name" $ do
    it "a second LEST at the middle rule's clauses" $
      failsWith
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
        , "    LEST BREACH BY Seller"
        ]
        (bodyLine 12, 5)
        ("This LEST lines up with the clauses of " <> ruleAt 5 5 <> ". \
         \That rule already has a LEST, and a rule has one. \
         \To give it to the rule that one is nested in, write it at column 3, in line with that rule's clauses.\n")

    it "a second LEST between the outer and the middle rule's clauses (once silently the innermost rule's)" $
      failsWith
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
        , "   LEST BREACH BY Seller"
        ]
        (bodyLine 12, 4)
        ("This LEST is part of " <> ruleAt 5 5 <> ", \
         \because it is right of the clauses of the rule that one is nested in (column 3). \
         \That rule already has a LEST, and a rule has one. \
         \To give it to the rule that one is nested in, write it at column 3, in line with that rule's clauses.\n")

    it "a second LEST far right of a top-level rule's clauses: no rule to move it to" $
      failsWith
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  WITHIN 3"
        , "  LEST BREACH BY Seller"
        , "        LEST BREACH BY Buyer"
        ]
        (bodyLine 5, 9)
        ("This LEST is part of " <> ruleAt 1 3 <> ". That rule already has a LEST, and a rule has one.\n")

    it "a second LEST right of a nested rule's own clauses, left of the outer rule's hanging ones" $
      failsWith
        [ "  PARTY Seller"
        , "      MUST delivery"
        , "      WITHIN 3"
        , "      HENCE"
        , "    PARTY Buyer"
        , "    MUST payment 100"
        , "    LEST BREACH BY Buyer"
        , "     LEST BREACH BY Seller"
        ]
        (bodyLine 8, 6)
        ("This LEST is part of " <> ruleAt 5 5 <> ", because it is right of that rule's clauses. \
         \That rule already has a LEST, and a rule has one. \
         \To give it to the rule that one is nested in, write it at column 7, in line with that rule's clauses.\n")

    it "a second LEST where both rules' clauses are at one column: brackets say which" $
      failsWith
        [ "  PARTY Seller"
        , "    MUST delivery"
        , "    HENCE"
        , "    PARTY Buyer"
        , "    MUST payment 100"
        , "    LEST BREACH BY Buyer"
        , "    LEST BREACH BY Seller"
        ]
        (bodyLine 7, 5)
        ("This LEST lines up with the clauses of " <> ruleAt 4 5 <> ". \
         \That rule already has a LEST, and a rule has one. \
         \To give it to the rule that one is nested in, put the nested rule in brackets: \
         \their clauses are at the same column.\n")

    it "a second HENCE at the outer rule's clauses" $
      failsWith
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  WITHIN 3"
        , "  HENCE"
        , "    PARTY Buyer"
        , "    MUST payment 100"
        , "  HENCE FULFILLED"
        ]
        (bodyLine 7, 3)
        ("This HENCE lines up with the clauses of " <> ruleAt 1 3 <> ". \
         \That rule already has a HENCE, and a rule has one. \
         \To make it follow the rule in that one's HENCE, write it inside that rule, in line with its clauses.\n")

    it "a HENCE at the outer rule's clauses after its LEST (once silently the nested rule's)" $
      failsWith
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  WITHIN 3"
        , "  LEST"
        , "    PARTY Seller"
        , "    MUST delivery"
        , "    WITHIN 5"
        , "  HENCE FULFILLED"
        ]
        (bodyLine 8, 3)
        afterLest

    it "LEST written before HENCE (once a bare \"unexpected HENCE\")" $
      failsWith
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  WITHIN 3"
        , "  LEST BREACH BY Seller"
        , "  HENCE PARTY Buyer MUST payment 100 WITHIN 7"
        ]
        (bodyLine 5, 3)
        afterLest

    -- 'L4.Parser.cont' wraps an operator's right operand in @try@, so the
    -- named refusal inside it is backtracked and the parse fails further out,
    -- at the operator. Pinned so that a change to either is seen.
    it "inside an unbracketed right operand of ROR, the refusal surfaces as the operator" $
      failsWith
        [ "  (PARTY Seller MUST delivery WITHIN 3)"
        , "  ROR"
        , "  PARTY Buyer"
        , "    MUST payment 100"
        , "    WITHIN 7"
        , "    LEST BREACH BY Buyer"
        , "    LEST BREACH BY Seller"
        ]
        (bodyLine 2, 3)
        "unexpected ROR\nexpecting %, ;, WHERE, end of input, or space token\n"

  describe "the parser's memo changes nothing on these layouts" $
    for_ memoCases \ (name, body) ->
      it name $ memoChangesNothing (rule body)
  where
    afterLest =
      "This HENCE lines up with the clauses of " <> ruleAt 1 3 <> ". \
      \It comes after that rule's LEST. Write HENCE before LEST.\n"
    -- How a refusal names the rule whose head is on line @n@ of the body.
    ruleAt :: Int -> Int -> Text
    ruleAt n col =
      "the rule that starts with PARTY at line " <> T.pack (show (bodyLine n)) <> ", column " <> T.pack (show col)
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

-- | The line number, in the whole module, of line @n@ (from 1) of a body.
bodyLine :: Int -> Int
bodyLine n = length prologue + n

rule :: [Text] -> Text
rule body = T.unlines (prologue <> body)

uri :: NormalizedUri
uri = toNormalizedUri (Uri "file:///clause-layout-parser-spec")

-- | Both bodies parse, the first exact-prints back to its source, and the two
-- print to the same module.
sameTree :: [Text] -> [Text] -> Expectation
sameTree unbracketed bracketed =
  case (execProgramParserWithHintPass uri (rule unbracketed), execProgramParserWithHintPass uri (rule bracketed)) of
    (Left errs, _) -> expectationFailure ("the unbracketed layout did not parse: " <> errors errs)
    (_, Left errs) -> expectationFailure ("the bracketed layout did not parse: " <> errors errs)
    (Right (m1, _, _), Right (m2, _, _)) -> do
      case exactprint m1 of
        Left err -> expectationFailure ("exactprint failed: " <> show err)
        Right printed -> printed `shouldBe` rule unbracketed
      prettyLayout m1 `shouldBe` prettyLayout m2

-- | Exactly one error, starting at @(line, column)@ (both from 1), whose
-- message ends with @expected@. (The message starts with the source line.)
failsWith :: [Text] -> (Int, Int) -> Text -> Expectation
failsWith body at expected =
  case execProgramParserWithHintPass uri (rule body) of
    Right _ -> expectationFailure "parsed, but should have failed"
    Left errs -> do
      [(e.range.start.line, e.range.start.column) | e <- toList errs] `shouldBe` [at]
      [T.takeEnd (T.length expected) e.message | e <- toList errs] `shouldBe` [expected]

-- | Parse with the memo on and off ('L4.Parser.clauseCtx' says why the memo
-- need not key on it); both must give the same answer.
memoChangesNothing :: Text -> Expectation
memoChangesNothing src =
  (execProgramParserWithHintPass uri src == execProgramParserWithHintPassUnmemoised uri src) `shouldBe` True

errors :: (Foldable f) => f PError -> String
errors errs = unlines [show e.range <> "\n" <> T.unpack e.message | e <- toList errs]
