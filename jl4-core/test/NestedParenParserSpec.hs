{-# LANGUAGE OverloadedStrings #-}

-- | The parser once took time exponential in how deeply parentheses nest:
-- @#EVAL ((1 PLUS 1) PLUS 1)@ nested 16 levels took 15 s, nested 18 took more
-- than a minute, and every further level doubled it.
--
-- Two shapes did it, and both parsed the same bracketed group more than once:
--
--   * __a @try@ whose branch parses the whole group and then fails.__
--     'L4.Parser.baseExpr'' tried a genitive projection (@(e)'s field@) first;
--     with no @'s@ after the group the branch failed and the plain @(e)@
--     alternative parsed the group again, once per level.
--
--   * __a look-ahead that parses the group to decide what a keyword is.__
--     After @1@ in @1 \`plus\` (…)@, the postfix reading of @\`plus\`@ looked
--     ahead to see whether an expression followed it, by parsing that
--     expression, which the infix reading then parsed again.
--
--   * __a bracket in pattern position, read as a pattern first.__
--     'L4.Parser.parenPatternOrExpr' tried @(…)@ as a pattern and, when it was
--     not one, read it again as an expression. When the bracket holds a
--     @CONSIDER@ (or a @MUST@) whose own pattern slot holds the next bracket,
--     the failed pattern attempt had already parsed that inner @CONSIDER@,
--     and the expression reading parsed it again: twice per level.
--
-- Each case here nests one construct 40 levels deep. Once parsing is
-- polynomial in depth, that takes milliseconds; the exponential parser could
-- not finish any of them in a lifetime. The time budget is therefore
-- deliberately generous: a slow CI machine cannot make a correct parser fail
-- it, and no machine can make the exponential parser pass it.
--
-- Each case also exact-prints the parsed module back to its source, which
-- fails if the deep parse dropped or reordered a token.
module NestedParenParserSpec (spec) where

import Base
import Control.Exception (evaluate)
import qualified Data.Text as T
import L4.ExactPrint (exactprint)
import L4.Parser (execProgramParserWithHintPass)
import System.Timeout (timeout)
import Test.Hspec

-- | How deep every construct is nested.
depth :: Int
depth = 40

-- | Seconds allowed per case.
budgetSeconds :: Int
budgetSeconds = 30

spec :: Spec
spec =
  describe ("parsing a construct nested " <> show depth <> " levels deep finishes within " <> show budgetSeconds <> " s") $ do
    it "a left-nested arithmetic expression: ((1 PLUS 1) PLUS 1)" $
      parsesWithin ("#EVAL " <> leftNested "PLUS" <> "\n")

    it "a right-nested arithmetic expression: (1 PLUS (1 PLUS 1))" $
      parsesWithin ("#EVAL " <> rightNested "PLUS" <> "\n")

    it "nothing but parentheses: ((1))" $
      parsesWithin ("#EVAL " <> nestedIn "(" ")" "1" <> "\n")

    it "a user-defined infix operator, left-nested: ((1 `plus` 1) `plus` 1)" $
      parsesWithin (plusPrologue <> "#EVAL " <> leftNested "`plus`" <> "\n")

    it "a user-defined infix operator with a bracketed right operand: 1 `plus` (1 `plus` 1)" $
      parsesWithin (plusPrologue <> "#EVAL " <> unwrap (rightNested "`plus`") <> "\n")

    it "a prefix application whose argument after the head is a name: f x (f x x)" $
      parsesWithin
        ( T.unlines
            [ "GIVEN a IS A NUMBER, b IS A NUMBER"
            , "GIVETH A NUMBER"
            , "f a b MEANS a PLUS b"
            , ""
            , "GIVEN x IS A NUMBER"
            , "GIVETH A NUMBER"
            , "probe x MEANS " <> unwrap (nestedIn "(f x " ")" "x")
            ]
        )

    it "a genitive projection on a bracketed head: ((r's next)'s next)" $
      parsesWithin
        ( T.unlines
            [ "DECLARE Node HAS next IS A Node"
            , ""
            , "GIVEN r IS A Node"
            , "GIVETH A Node"
            , "probe r MEANS"
            , "  " <> nestedIn "(" "'s next)" "r"
            ]
        )

    it "a bracketed expression in pattern position: WHEN ((1 PLUS 1) PLUS 1) THEN" $
      parsesWithin
        ( T.unlines
            [ "GIVETH A BOOLEAN"
            , "probe MEANS"
            , "  CONSIDER 3"
            , "  WHEN " <> leftNested "PLUS" <> " THEN TRUE"
            , "  OTHERWISE FALSE"
            ]
        )

    it "a bracketed expression as a deontic action's argument: MUST pay ((1 PLUS 1) PLUS 1)" $
      parsesWithin
        ( T.unlines
            [ "DECLARE Person IS ONE OF alice, bob"
            , "DECLARE Act IS ONE OF"
            , "  pay HAS amount IS A NUMBER"
            , ""
            , "GIVETH A DEONTIC Person Act"
            , "probe MEANS"
            , "  PARTY alice"
            , "  MUST pay " <> leftNested "PLUS"
            , "  WITHIN 3"
            ]
        )

    it "a bracket in pattern position holding a CONSIDER whose WHEN holds the next bracket" $
      parsesWithin (inWhen (nestedIn "((CONSIDER 1 WHEN " " THEN 1, OTHERWISE 2) PLUS 1)" "1"))

    it "the same nest as a deontic action's argument: MUST pay ((CONSIDER 1 WHEN … ) PLUS 1)" $
      parsesWithin
        ( T.unlines
            [ "DECLARE Person IS ONE OF alice, bob"
            , "DECLARE Act IS ONE OF"
            , "  pay HAS amount IS A NUMBER"
            , ""
            , "GIVETH A DEONTIC Person Act"
            , "probe MEANS"
            , "  PARTY alice"
            , "  MUST pay " <> nestedIn "((CONSIDER 1 WHEN " " THEN 1, OTHERWISE 2) PLUS 1)" "1"
            , "  WITHIN 3"
            ]
        )

    it "the same nest as a DECIDE clause's argument" $
      parsesWithin
        ( T.unlines
            [ "GIVEN n IS A NUMBER"
            , "GIVETH A NUMBER"
            , "DECIDE probe n IS 0"
            , "DECIDE probe " <> nestedIn "((CONSIDER 1 WHEN " " THEN 1, OTHERWISE 2) PLUS 1)" "1" <> " IS 1"
            ]
        )

    it "a pattern-shaped head, then the bracket, then an operator: (f (CONSIDER … ) PLUS 1)" $
      parsesWithin (inWhen (nestedIn "(f (CONSIDER 1 WHEN " " THEN 1, OTHERWISE 2) PLUS 1)" "1"))

    it "a pattern operator before the bracket, then an operator: (x FOLLOWED BY (CONSIDER … ) PLUS 1)" $
      parsesWithin (inWhen (nestedIn "(x FOLLOWED BY (CONSIDER 1 WHEN " " THEN 1, OTHERWISE 2) PLUS 1)" "x"))

    it "brackets that ARE patterns, each holding a CONSIDER: ((CONSIDER … ) FOLLOWED BY x)" $
      parsesWithin (inWhen (nestedIn "((CONSIDER 1 WHEN " " THEN 1, OTHERWISE 2) FOLLOWED BY x)" "x"))

-- | Parse the module (both passes, as the tools do), force the whole syntax
-- tree, and exact-print it back, all within the budget.
parsesWithin :: Text -> Expectation
parsesWithin src = do
  outcome <- timeout (budgetSeconds * 1000000) $ evaluate $ force $
    case execProgramParserWithHintPass uri src of
      Left errs -> Left ("parse failed: " <> show errs)
      Right (moduleAst, _hints, _warnings) ->
        case exactprint moduleAst of
          Left err -> Left ("exactprint failed: " <> show err)
          Right printed
            | printed == src -> Right ()
            | otherwise -> Left ("exactprint is not the identity:\n" <> T.unpack printed)
  case outcome of
    Nothing -> expectationFailure ("did not finish within " <> show budgetSeconds <> " s")
    Just (Left msg) -> expectationFailure msg
    Just (Right ()) -> pure ()
  where
    uri = toNormalizedUri (Uri "file:///nested-paren-parser-spec")

-- | @leftNested op@ is @((1 op 1) op 1)@, 'depth' levels deep.
leftNested :: Text -> Text
leftNested op = nestedIn "(" (" " <> op <> " 1)") "1"

-- | @rightNested op@ is @(1 op (1 op 1))@, 'depth' levels deep.
rightNested :: Text -> Text
rightNested op = nestedIn ("(1 " <> op <> " ") ")" "1"

-- | Wrap @core@ in 'depth' copies of @open@ … @close@.
nestedIn :: Text -> Text -> Text -> Text
nestedIn open close core = iterate (\ e -> open <> e <> close) core !! depth

-- | @inWhen g@ is a rule that puts @g@ in the pattern slot of a @WHEN@.
inWhen :: Text -> Text
inWhen g =
  T.unlines
    [ "GIVETH A NUMBER"
    , "probe MEANS"
    , "  CONSIDER 3 WHEN " <> g <> " THEN 1, OTHERWISE 2"
    ]

-- | Drop the outermost pair of parentheses.
unwrap :: Text -> Text
unwrap = T.drop 1 . T.dropEnd 1

plusPrologue :: Text
plusPrologue =
  T.unlines
    [ "GIVEN a IS A NUMBER, b IS A NUMBER"
    , "GIVETH A NUMBER"
    , "a `plus` b MEANS a + b"
    , ""
    ]
