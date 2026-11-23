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

  describe "on a rule's first line, a HENCE after its slots is that rule's, and refused by it (#1074 F2)" $ do
    it "a HENCE after a LEST on a nested rule's line names the nested rule (once the outer one)" $
      failsWith
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  HENCE PARTY Buyer MUST payment 100 LEST BREACH BY Buyer HENCE FULFILLED"
        , "  LEST BREACH BY Seller"
        ]
        (bodyLine 3, 59)
        ("This HENCE is part of " <> ruleAt 3 9 <> ", because it is on that rule's first line. \
         \It comes after that rule's LEST. Write HENCE before LEST." <> ifRuleAfter)

    it "a second HENCE on a nested rule's line names the nested rule (once the outer one)" $
      failsWith
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  HENCE PARTY Buyer MUST payment 100 HENCE FULFILLED HENCE PARTY Seller MUST delivery"
        ]
        (bodyLine 3, 54)
        ("This HENCE is part of " <> ruleAt 3 9 <> ", because it is on that rule's first line. \
         \That rule already has a HENCE, and a rule has one.\n")

    -- A refusal inside an operator's right operand would be backtracked and
    -- surface as a bare "unexpected RAND" ('L4.Parser.standAside'), so there
    -- the HENCE is left to the rule outside, which refuses it by name, as
    -- before #1074. Pinned so that a change to either is seen.
    it "in an unbracketed right operand of RAND, the HENCE is left to the rule outside, as before" $
      failsWith
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  HENCE (PARTY Buyer MUST payment 100) RAND PARTY Seller MUST delivery LEST BREACH BY Seller HENCE FULFILLED"
        ]
        (bodyLine 3, 94)
        ("This HENCE is part of " <> ruleAt 1 3 <> ". That rule already has a HENCE, and a rule has one.\n")

    it "a HENCE after a LEST on a one-line rule (once a bare \"unexpected HENCE\")" $
      failsWith
        [ "  PARTY Seller MUST delivery LEST BREACH BY Seller HENCE FULFILLED"
        ]
        (bodyLine 1, 52)
        ("This HENCE is part of " <> ruleAt 1 3 <> ", because it is on that rule's first line. \
         \It comes after that rule's LEST. Write HENCE before LEST." <> ifRuleAfter)

  describe "on a rule's first line, a second LEST is that rule's, and refused by it (#1074 F1, ruled by Meng 2026-11-22: Clause Layout Rulings F1 A)" $ do
    it "the issue's repro: a second LEST on a nested rule's line (once the outer rule's, exit 0)" $
      failsWith
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  HENCE PARTY Buyer MUST payment 100 LEST BREACH BY Buyer LEST BREACH BY Seller"
        ]
        (bodyLine 3, 59)
        ("This LEST is part of " <> ruleAt 3 9 <> ", because it is on that rule's first line. \
         \That rule already has a LEST, and a rule has one. \
         \To give it to the rule that one is nested in, write it on a line of its own at column 3, \
         \in line with that rule's clauses.\n")

    it "a second LEST on the line of a rule nested in a LEST: no advice, the outer LEST is used" $
      failsWith
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  LEST PARTY Buyer MUST payment 100 LEST BREACH BY Buyer LEST BREACH BY Seller"
        ]
        (bodyLine 3, 58)
        ("This LEST is part of " <> ruleAt 3 8 <> ", because it is on that rule's first line. \
         \That rule already has a LEST, and a rule has one.\n")

    -- Unlike a HENCE, the LEST is not left to the rule outside the operand,
    -- which would take it silently; the refusal is backtracked by 'cont'
    -- and the parse fails at the operator. Loud, but naming nothing.
    it "in an unbracketed right operand of RAND, the refusal surfaces as the operator" $
      failsWith
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  HENCE (PARTY Buyer MUST payment 100) RAND PARTY Seller MUST delivery LEST BREACH BY Seller LEST BREACH BY Buyer"
        ]
        (bodyLine 3, 40)
        "unexpected RAND\nexpecting %, ;, LEST, WHERE, end of input, infix identifier, mixfix keyword, or space token\n"

    -- 'L4.Parser.inBranch' drops only that first-line advice: a refusal on
    -- a later line keeps the advice it had before.
    it "on a later line in a CONSIDER's WHEN: the advice is kept" $
      failsWith
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  HENCE CONSIDER x"
        , "        WHEN cancel THEN PARTY Buyer"
        , "                         MUST payment 100"
        , "                         LEST BREACH BY Buyer"
        , "                         LEST BREACH BY Seller"
        ]
        (bodyLine 7, 26)
        ("This LEST lines up with the clauses of " <> ruleAt 4 26 <> ". \
         \That rule already has a LEST, and a rule has one. \
         \To give it to the rule that one is nested in, write it at column 3, in line with that rule's clauses.\n")

    it "on a later line in a CONSIDER's WHEN, the advice followed: the LEST is the outer rule's" $
      sameTree
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  HENCE CONSIDER x"
        , "        WHEN cancel THEN PARTY Buyer"
        , "                         MUST payment 100"
        , "                         LEST BREACH BY Buyer"
        , "  LEST BREACH BY Seller"
        ]
        ["  PARTY Seller MUST delivery HENCE (CONSIDER x WHEN cancel THEN (PARTY Buyer MUST payment 100 LEST BREACH BY Buyer)) LEST BREACH BY Seller"]

    -- 'L4.Parser.inBranch': before the ELSE, the outer rule cannot take the
    -- LEST, so a line of its own at its clauses would not give it to it.
    it "in an IF's THEN branch: no advice, since the outer rule cannot take it before the ELSE" $
      failsWith
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  HENCE IF TRUE THEN PARTY Buyer MUST payment 100 LEST BREACH BY Buyer LEST BREACH BY Seller ELSE FULFILLED"
        ]
        (bodyLine 3, 72)
        ("This LEST is part of " <> ruleAt 3 22 <> ", because it is on that rule's first line. \
         \That rule already has a LEST, and a rule has one.\n")

    it "the advice, followed: on a line of its own at the outer rule's clauses, the LEST is the outer rule's" $
      sameTree
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  HENCE PARTY Buyer MUST payment 100 LEST BREACH BY Buyer"
        , "  LEST BREACH BY Seller"
        ]
        ["  PARTY Seller MUST delivery HENCE (PARTY Buyer MUST payment 100 LEST BREACH BY Buyer) LEST BREACH BY Seller"]

    it "the advice, followed in an IF's ELSE branch, the last: the LEST is the outer rule's" $
      sameTree
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  HENCE IF TRUE THEN FULFILLED ELSE PARTY Buyer MUST payment 100 LEST BREACH BY Buyer"
        , "  LEST BREACH BY Seller"
        ]
        ["  PARTY Seller MUST delivery HENCE (IF TRUE THEN FULFILLED ELSE (PARTY Buyer MUST payment 100 LEST BREACH BY Buyer)) LEST BREACH BY Seller"]

  describe "the advice for a second HENCE after a rule in the HENCE says only what can be done (#1074 F4)" $ do
    it "the rule in the HENCE is in brackets: write it before the )" $
      failsWith
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  HENCE"
        , "    ( PARTY Buyer"
        , "      MUST payment 100 )"
        , "  HENCE FULFILLED"
        ]
        (bodyLine 6, 3)
        ("This HENCE lines up with the clauses of " <> ruleAt 1 3 <> ". \
         \That rule already has a HENCE, and a rule has one. \
         \To make it follow the rule in that one's HENCE, write it inside the innermost brackets around that rule, \
         \before their ), in line with its clauses.\n")

    it "the rule in the HENCE has a HENCE of its own: no advice" $
      failsWith
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  HENCE"
        , "    PARTY Buyer"
        , "    MUST payment 100"
        , "    HENCE FULFILLED"
        , "  HENCE FULFILLED"
        ]
        (bodyLine 7, 3)
        ("This HENCE lines up with the clauses of " <> ruleAt 1 3 <> ". \
         \That rule already has a HENCE, and a rule has one.\n")

    it "the rule in the HENCE has a LEST: write it before that LEST" $
      failsWith
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  HENCE"
        , "    PARTY Buyer"
        , "    MUST payment 100"
        , "    LEST BREACH BY Buyer"
        , "  HENCE FULFILLED"
        ]
        (bodyLine 7, 3)
        ("This HENCE lines up with the clauses of " <> ruleAt 1 3 <> ". \
         \That rule already has a HENCE, and a rule has one. \
         \To make it follow the rule in that one's HENCE, write it inside that rule, \
         \in line with its clauses, and before its LEST.\n")

  -- 'L4.Parser.standAside': where something outside can still take the
  -- HENCE, or a try would backtrack the refusal, the rule leaves the HENCE
  -- on its first line outward, as every rule did before #1074. Each of
  -- these was accepted, or named by the rule outside, before #1074, and
  -- the first version of F2 refused it or failed at the operator.
  describe "where something outside can still take a HENCE on a rule's first line, the rule leaves it there (#1074)" $ do
    it "a RECORD's value: the second HENCE is the RECORD's" $
      sameTree
        ["  RECORD `x` IS PARTY Seller MUST delivery HENCE FULFILLED HENCE FULFILLED"]
        ["  RECORD `x` IS (PARTY Seller MUST delivery HENCE FULFILLED) HENCE FULFILLED"]

    it "an ATTEST's value: a HENCE after the rule's LEST is the ATTEST's" $
      sameTree
        ["  ATTEST `x` IS PARTY Seller MUST delivery LEST FULFILLED HENCE FULFILLED"]
        ["  ATTEST `x` IS (PARTY Seller MUST delivery LEST FULFILLED) HENCE FULFILLED"]

    it "a WHERE inside a RECORD's value is still inside it" $
      sameTree
        ["  RECORD `x` IS y WHERE y MEANS PARTY Seller MUST delivery HENCE FULFILLED HENCE FULFILLED"]
        ["  RECORD `x` IS y WHERE y MEANS (PARTY Seller MUST delivery HENCE FULFILLED) HENCE FULFILLED"]

    it "a rule in another rule's WITHIN: the second HENCE is the outer rule's" $
      sameTree
        ["  PARTY Seller MUST delivery WITHIN PARTY Buyer MUST payment 100 HENCE FULFILLED HENCE FULFILLED"]
        ["  PARTY Seller MUST delivery WITHIN (PARTY Buyer MUST payment 100 HENCE FULFILLED) HENCE FULFILLED"]

    it "a rule in a user-defined infix operand in a WITHIN: the second HENCE is the outer rule's" $
      sameTree
        ("  PARTY Seller MUST delivery WITHIN 3 `days for` PARTY Buyer MUST payment 100 HENCE FULFILLED HENCE FULFILLED" : daysFor)
        ("  PARTY Seller MUST delivery WITHIN 3 `days for` (PARTY Buyer MUST payment 100 HENCE FULFILLED) HENCE FULFILLED" : daysFor)

    it "a rule in a user-defined infix operand in a HENCE: the rule outside names it, not a bare error at the operator" $
      failsWith
        ("  PARTY Seller MUST delivery HENCE 3 `days for` PARTY Buyer MUST payment 100 HENCE FULFILLED HENCE FULFILLED" : daysFor)
        (bodyLine 1, 94)
        ("This HENCE is part of " <> ruleAt 1 3 <> ", because it is on that rule's first line. \
         \That rule already has a HENCE, and a rule has one.\n")

    it "a rule in an operand of a directive: the error is at the HENCE, not at the operator" $
      failsWithContaining
        [ "  FULFILLED"
        , ""
        , "#EVAL FULFILLED RAND PARTY Seller MUST delivery HENCE FULFILLED HENCE FULFILLED"
        ]
        (bodyLine 3, 65)
        "unexpected HENCE\n"

  describe "the advice, followed, gives the keyword to the rule it names (#1074)" $ do
    it "a HENCE after the LEST, moved before it with what follows in brackets: the LEST stays the outer rule's" $
      sameTree
        ["  PARTY Seller MUST delivery HENCE (PARTY Buyer MUST payment 100) LEST BREACH BY Seller"]
        [ "  PARTY Seller MUST delivery"
        , "  HENCE PARTY Buyer MUST payment 100"
        , "  LEST BREACH BY Seller"
        ]

    it "a second HENCE moved inside the brackets around the rule in the HENCE: it follows that rule" $
      sameTree
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  HENCE"
        , "    ( PARTY Buyer"
        , "      MUST payment 100"
        , "      HENCE FULFILLED )"
        ]
        ["  PARTY Seller MUST delivery HENCE (PARTY Buyer MUST payment 100 HENCE FULFILLED)"]

    it "inside the innermost of two pairs of brackets: it follows that rule" $
      sameTree
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  HENCE"
        , "    (( PARTY Buyer"
        , "       MUST payment 100"
        , "       HENCE FULFILLED ))"
        ]
        ["  PARTY Seller MUST delivery HENCE (PARTY Buyer MUST payment 100 HENCE FULFILLED)"]

    it "a second HENCE moved inside the rule in the HENCE, before its LEST: it follows that rule" $
      sameTree
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  HENCE"
        , "    PARTY Buyer"
        , "    MUST payment 100"
        , "    HENCE FULFILLED"
        , "    LEST BREACH BY Buyer"
        ]
        ["  PARTY Seller MUST delivery HENCE (PARTY Buyer MUST payment 100 HENCE FULFILLED LEST BREACH BY Buyer)"]

  -- One test per try in L4.Parser that can parse a rule as the last thing
  -- it parses ('L4.Parser.standAside' lists them). A refusal under a try is
  -- backtracked; where what follows the try can then succeed, the run used to
  -- fail later at a token that is fine (WITH, a bullet), naming nothing.
  describe "every try that can end in a rule leaves a first-line HENCE where it can be refused by name (#1074)" $ do
    let leftover = "PARTY Buyer MUST payment 100 HENCE FULFILLED HENCE FULFILLED"
        outerHas = "This HENCE is part of " <> ruleAt 1 3 <> ". That rule already has a HENCE, and a rule has one.\n"
        firstLine n col = "This HENCE is part of " <> ruleAt n col <> ", because it is on that rule's first line. \
                          \That rule already has a HENCE, and a rule has one.\n"
    -- Stands aside: the rule outside refuses it, as before #1074.
    it "an operator's right operand ('cont')" $
      failsWith ["  PARTY Seller", "  MUST delivery", "  HENCE FULFILLED RAND " <> leftover] (bodyLine 3, 69) outerHas
    it "a directive's operand ('singleLineExpressionCont'): as before, bare at the HENCE" $
      failsWithContaining ["  FULFILLED", "", "#EVAL FULFILLED RAND " <> leftover] (bodyLine 3, 67) "unexpected HENCE\n"
    it "a user-defined infix operand ('infixAhead')" $
      failsWith (["  PARTY Seller", "  MUST delivery", "  HENCE 3 `days for` " <> leftover] <> daysFor) (bodyLine 3, 67) outerHas
    it "a mixfix operand ('mixfixChainExprNextLine')" $
      failsWith
        ( ["  PARTY Seller", "  MUST delivery", "  HENCE 3 `split` (PARTY Buyer MUST payment 100) `and` " <> leftover]
            <> ["", "GIVEN n IS A NUMBER", "      d IS A DEONTIC Person Action", "      e IS A DEONTIC Person Action", "GIVETH A NUMBER", "n `split` d `and` e MEANS n"] )
        (bodyLine 3, 101) outerHas
    it "a named argument's value ('namedApp'; once a bare \"unexpected WITH\")" $
      failsWith ["  PARTY Seller", "  MUST delivery", "  HENCE pick WITH y IS " <> leftover] (bodyLine 3, 69) outerHas
    it "a named argument's value with no rule outside: as before, bare at the HENCE (once at WITH)" $
      failsWithContaining ["  pick WITH y IS " <> leftover] (bodyLine 1, 63) "unexpected HENCE\n"
    it "a bullet block as a function's argument ('parseAppArgs'; once a bare \"unexpected \8226\")" $
      failsWith ["  PARTY Seller", "  MUST delivery", "  HENCE firstOf", "          \8226 " <> leftover] (bodyLine 4, 58) outerHas
    -- Needs nothing: every alternative after the try fails too, so the
    -- refusal is the error furthest on. The rule names it.
    it "an event's operand ('event')" $
      failsWith ["  FULFILLED", "", "#TRACE c AT 0 WITH", "  PARTY Seller DOES delivery AT " <> leftover] (bodyLine 4, 78) (firstLine 4 33)
    it "a bullet block ('bulletBlock')" $
      failsWith ["  \8226 " <> leftover] (bodyLine 1, 50) (firstLine 1 5)
    it "the first of several pattern clauses ('decidePatternMatch')" $
      failsWith
        ["  FULFILLED", "", "GIVEN x IS A Person", "GIVETH A DEONTIC Person Action", "DECIDE f Seller IS " <> leftover, "DECIDE f Buyer IS FULFILLED"]
        (bodyLine 5, 65) (firstLine 5 20)
    it "a later pattern clause ('decidePatternMatch')" $
      failsWith
        ["  FULFILLED", "", "GIVEN x IS A Person", "GIVETH A DEONTIC Person Action", "DECIDE f Seller IS FULFILLED", "DECIDE f Buyer IS " <> leftover]
        (bodyLine 6, 64) (firstLine 6 19)
    it "a one-line LET definition ('singleInlineLetDeclRelaxed')" $
      failsWith ["  PARTY Seller", "  MUST delivery", "  HENCE LET z MEANS " <> leftover <> " IN z"] (bodyLine 3, 66) (firstLine 3 21)
    it "TIMEZONE IS ('topdecl')" $
      failsWith ["  FULFILLED", "", "TIMEZONE IS " <> leftover] (bodyLine 3, 58) (firstLine 3 13)

  describe "a HENCE or LEST at or left of its definition's column is refused by name (#1074 F3, ruled by Meng 2026-11-22: Clause Layout Rulings F3 A)" $ do
    it "the issue's first repro: a LEST at column 1 (once a bare \"unexpected LEST\")" $
      failsWith
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "LEST BREACH BY Seller"
        ]
        (bodyLine 3, 1)
        ("This LEST is at column 1, so it is not part of " <> ruleAt 1 3 <> ": on a later line, a LEST at column 1, \
         \where its definition starts (or column 1 inside brackets), or left of both that column and that rule's clauses, ends the rule. \
         \To make it that rule's LEST, write it at column 3, in line with that rule's clauses.\n")

    it "the issue's second repro: a HENCE at a WHERE definition's column (once a bare \"unexpected HENCE\")" $
      failsWith
        [ "  inner"
        , "  WHERE"
        , "    inner MEANS"
        , "      PARTY Seller"
        , "      MUST delivery"
        , "    HENCE FULFILLED"
        ]
        (bodyLine 6, 5)
        ("This HENCE is at column 5, so it is not part of " <> ruleAt 4 7 <> ": on a later line, a HENCE at column 5, \
         \where its definition starts (or column 1 inside brackets), or left of both that column and that rule's clauses, ends the rule. \
         \To make it that rule's HENCE, write it at column 7, in line with that rule's clauses.\n")

    it "after a nested rule, the outermost rule is the one named" $
      failsWith
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  HENCE"
        , "    PARTY Buyer"
        , "    MUST payment 100"
        , "LEST BREACH BY Seller"
        ]
        (bodyLine 6, 1)
        ("This LEST is at column 1, so it is not part of " <> ruleAt 1 3 <> ": on a later line, a LEST at column 1, \
         \where its definition starts (or column 1 inside brackets), or left of both that column and that rule's clauses, ends the rule. \
         \To make it that rule's LEST, put what follows its HENCE in brackets, \
         \and write the LEST at column 3, in line with that rule's clauses.\n")

    it "a rule whose LEST is used: no column to suggest" $
      failsWith
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  LEST BREACH BY Seller"
        , "LEST BREACH BY Buyer"
        ]
        (bodyLine 4, 1)
        ("This LEST is at column 1, so it is not part of " <> ruleAt 1 3 <> ": on a later line, a LEST at column 1, \
         \where its definition starts (or column 1 inside brackets), or left of both that column and that rule's clauses, ends the rule. \
         \That rule already has a LEST, and a rule has one.\n")

    -- 'L4.Parser.standAside', set by 'clauseBody' inside a rule's body: the
    -- rule outside is still open, so the end of a WHERE definition is not
    -- the end of the search. Accepted before #1074, and refused by the first
    -- version of this commit; so was the RECORD case.
    it "a rule in a WHERE definition inside a HENCE: the LEST after it is the outer rule's, as before" $
      sameTree
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  WITHIN 3"
        , "  HENCE `pay`"
        , "    WHERE"
        , "      `pay` MEANS"
        , "        PARTY Buyer"
        , "        MUST payment 100"
        , "        WITHIN 7"
        , "  LEST BREACH BY Seller"
        ]
        [ "  PARTY Seller MUST delivery WITHIN 3"
        , "  HENCE (`pay` WHERE `pay` MEANS (PARTY Buyer MUST payment 100 WITHIN 7))"
        , "  LEST BREACH BY Seller"
        ]

    it "a rule in a RECORD's value: a HENCE at column 1 is the RECORD's, as before" $
      sameTree
        [ "  RECORD `x` IS PARTY Seller MUST delivery"
        , "HENCE BREACH BY Seller"
        ]
        ["  RECORD `x` IS (PARTY Seller MUST delivery) HENCE BREACH BY Seller"]

    it "inside brackets, the column it must be right of is 1" $
      failsWith
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  HENCE (PARTY Buyer"
        , "         MUST payment 100"
        , "LEST BREACH BY Buyer)"
        ]
        (bodyLine 5, 1)
        ("This LEST is at column 1, so it is not part of " <> ruleAt 3 10 <> ": on a later line, a LEST at column 1, \
         \where its definition starts (or column 1 inside brackets), or left of both that column and that rule's clauses, ends the rule. \
         \To make it that rule's LEST, write it at column 10, in line with that rule's clauses.\n")

    it "inside brackets, the advice followed: the LEST is that rule's" $
      sameTree
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  HENCE (PARTY Buyer"
        , "         MUST payment 100"
        , "         LEST BREACH BY Buyer)"
        ]
        ["  PARTY Seller MUST delivery HENCE (PARTY Buyer MUST payment 100 LEST BREACH BY Buyer)"]

    it "the advice followed: at the clauses, the LEST is the named rule's" $
      sameTree
        [ "  PARTY Seller"
        , "  MUST delivery"
        , "  LEST BREACH BY Seller"
        ]
        ["  PARTY Seller MUST delivery LEST BREACH BY Seller"]

    -- A tie (the nested rule's clauses at the outer rule's) keeps the LEST
    -- with the nested rule, so a column alone would give it to the wrong
    -- rule; brackets end the nested rule.
    it "after a nested rule whose clauses are at the outer rule's: the advice adds brackets" $
      failsWith
        [ "  PARTY Seller"
        , "      MUST delivery"
        , "      HENCE"
        , "    PARTY Buyer"
        , "      MUST payment 100"
        , "LEST BREACH BY Seller"
        ]
        (bodyLine 6, 1)
        ("This LEST is at column 1, so it is not part of " <> ruleAt 1 3 <> ": on a later line, a LEST at column 1, \
         \where its definition starts (or column 1 inside brackets), or left of both that column and that rule's clauses, ends the rule. \
         \To make it that rule's LEST, put what follows its HENCE in brackets, \
         \and write the LEST at column 7, in line with that rule's clauses.\n")

    it "after that tie, the advice followed: the LEST is the outer rule's" $
      sameTree
        [ "  PARTY Seller"
        , "      MUST delivery"
        , "      HENCE"
        , "    (PARTY Buyer"
        , "      MUST payment 100)"
        , "      LEST BREACH BY Seller"
        ]
        ["  PARTY Seller MUST delivery HENCE (PARTY Buyer MUST payment 100) LEST BREACH BY Seller"]

    -- A second review: the bracket advice must also follow a WHERE, whose
    -- definitions come after its expression ('L4.Parser.openRuleAtEnd').
    it "after a WHERE whose definition ends in a rule: the advice adds brackets" $
      failsWith
        ["  PARTY Seller", "    MUST delivery", "    HENCE i", "   WHERE", "   i MEANS", "     PARTY Buyer", "     MUST payment 100", "LEST BREACH BY Seller"]
        (bodyLine 8, 1)
        ("This LEST is at column 1, so it is not part of " <> ruleAt 1 3 <> ": on a later line, a LEST at column 1, \
         \where its definition starts (or column 1 inside brackets), or left of both that column and that rule's clauses, ends the rule. \
         \To make it that rule's LEST, put what follows its HENCE in brackets, \
         \and write the LEST at column 5, in line with that rule's clauses.\n")

    it "after that WHERE, the advice followed: the LEST is the outer rule's" $
      sameTree
        ["  PARTY Seller", "    MUST delivery", "    HENCE (i", "   WHERE", "   i MEANS", "     PARTY Buyer", "     MUST payment 100)", "    LEST BREACH BY Seller"]
        ["  PARTY Seller MUST delivery HENCE (i WHERE i MEANS PARTY Buyer MUST payment 100) LEST BREACH BY Seller"]

    -- Moved before the LEST, a rule after the HENCE could take the LEST, so
    -- the advice carries the same caution as the refusal of a HENCE after
    -- the LEST.
    it "a HENCE after the rule's LEST, followed by a rule not in brackets: the advice adds the caution" $
      failsWith
        ["  PARTY Seller", "      MUST delivery", "      LEST BREACH BY Seller", "HENCE", "    PARTY Buyer", "      MUST payment 100"]
        (bodyLine 4, 1)
        ("This HENCE is at column 1, so it is not part of " <> ruleAt 1 3 <> ": on a later line, a HENCE at column 1, \
         \where its definition starts (or column 1 inside brackets), or left of both that column and that rule's clauses, ends the rule. \
         \To make it that rule's HENCE, write it before that rule's LEST, in line with its clauses. \
         \If what follows HENCE is a rule, or ends with one, put it in brackets, or that rule can take the LEST.\n")

    -- The first sentence must hold when a rule's clauses are left of its
    -- definition's column: there the keyword is the rule's between the two.
    it "a rule whose clauses are left of its definition's column: at that column, refused" $
      failsWith
        ["  inner", "  WHERE", "    inner MEANS", "      PARTY Buyer", "  MUST payment 100", "    LEST BREACH BY Buyer"]
        (bodyLine 6, 5)
        ("This LEST is at column 5, so it is not part of " <> ruleAt 4 7 <> ": on a later line, a LEST at column 5, \
         \where its definition starts (or column 1 inside brackets), or left of both that column and that rule's clauses, ends the rule. \
         \To make it that rule's LEST, write it at column 3, in line with that rule's clauses.\n")

    it "a rule whose clauses are left of its definition's column: between the two, still the rule's" $
      sameTree
        ["  inner", "  WHERE", "    inner MEANS", "      PARTY Buyer", "  MUST payment 100", "   LEST BREACH BY Buyer"]
        ["  inner", "  WHERE", "    inner MEANS PARTY Buyer MUST payment 100 LEST BREACH BY Buyer"]

    it "unchanged: right of the definition's column, left of the clauses, it is still the rule's" $
      sameTree
        [ "  PARTY Seller"
        , "    MUST delivery"
        , " LEST BREACH BY Seller"
        ]
        [ "  PARTY Seller MUST delivery LEST BREACH BY Seller"
        ]

  describe "the parser's memo changes nothing on these layouts" $
    for_ memoCases \ (name, body) ->
      it name $ memoChangesNothing (rule body)
  where
    afterLest =
      "This HENCE lines up with the clauses of " <> ruleAt 1 3 <> ". \
      \It comes after that rule's LEST. Write HENCE before LEST." <> ifRuleAfter
    -- The advice on a HENCE after the LEST when what follows the HENCE is
    -- not in brackets: moved before the LEST, a rule there would take it.
    ifRuleAfter =
      " If what follows HENCE is a rule, or ends with one, put it in brackets, \
      \or that rule can take the LEST.\n"
    -- A user-defined infix operator, after the definition under test.
    daysFor =
      [ ""
      , "GIVEN n IS A NUMBER"
      , "      d IS A DEONTIC Person Action"
      , "GIVETH A NUMBER"
      , "n `days for` d MEANS n"
      ]
    -- How a refusal names the rule whose head is on line @n@ of the body.
    ruleAt :: Int -> Int -> Text
    ruleAt n col =
      "the rule that starts with PARTY at line " <> T.pack (show (bodyLine n)) <> ", column " <> T.pack (show col)
    memoCases =
      [ ("the repro", ["  PARTY Seller", "  MUST delivery", "  HENCE", "    PARTY Buyer", "    MUST payment 100", "    LEST", "      PARTY Buyer", "      MUST payment 120", "  LEST BREACH BY Seller"])
      , ("the repro with the inner rule in brackets", ["  PARTY Seller", "  MUST delivery", "  HENCE", "    (PARTY Buyer", "     MUST payment 100", "     LEST", "       PARTY Buyer", "       MUST payment 120)", "  LEST BREACH BY Seller"])
      , ("a second LEST inside brackets", ["  PARTY Seller", "  MUST delivery", "  HENCE", "    (PARTY Buyer", "     MUST payment 100", "     LEST BREACH BY Buyer", "     LEST BREACH BY Seller)"])
      , ("a nested rule left of the outer rule's hanging clauses", ["  PARTY Seller", "      MUST delivery", "      HENCE", "    PARTY Buyer", "    MUST payment 100", "    LEST BREACH BY Buyer", "      LEST BREACH BY Seller"])
      , ("a WHERE inside a RECORD's value", ["  RECORD `x` IS y WHERE y MEANS PARTY Seller MUST delivery HENCE FULFILLED HENCE FULFILLED"])
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

-- | Like 'failsWith', for a bare error whose list of expected tokens is
-- long: the message contains @expected@.
failsWithContaining :: [Text] -> (Int, Int) -> Text -> Expectation
failsWithContaining body at expected =
  case execProgramParserWithHintPass uri (rule body) of
    Right _ -> expectationFailure "parsed, but should have failed"
    Left errs -> do
      [(e.range.start.line, e.range.start.column) | e <- toList errs] `shouldBe` [at]
      [expected `T.isInfixOf` e.message | e <- toList errs] `shouldBe` [True]

-- | Parse with the memo on and off ('L4.Parser.clauseCtx' says why the memo
-- need not key on it); both must give the same answer.
memoChangesNothing :: Text -> Expectation
memoChangesNothing src =
  (execProgramParserWithHintPass uri src == execProgramParserWithHintPassUnmemoised uri src) `shouldBe` True

errors :: (Foldable f) => f PError -> String
errors errs = unlines [show e.range <> "\n" <> T.unpack e.message | e <- toList errs]
