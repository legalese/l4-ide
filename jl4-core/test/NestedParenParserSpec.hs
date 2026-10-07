{-# LANGUAGE OverloadedStrings #-}

-- | The parser once took time exponential in how deeply parentheses nest:
-- @#EVAL ((1 PLUS 1) PLUS 1)@ nested 16 levels took 15 s, nested 18 took more
-- than a minute, and every further level doubled it.
--
-- Three shapes did it, and each parsed the same bracketed group more than once:
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
-- Each case in 'depthSpec' nests one construct 40 levels deep. Once parsing
-- is polynomial in depth, that takes milliseconds. The exponential parser
-- (21467cd84 on @unstable@) cannot finish thirteen of its fifteen cases in a
-- lifetime. The other two, a genitive projection on a bracketed head and
-- brackets that are patterns, did not double per level there and pass on it
-- too; they guard against a change that would make them double. The time
-- budget is therefore deliberately generous: a slow CI machine cannot make a
-- correct parser fail it, and no machine can make the exponential parser
-- pass the other thirteen.
--
-- Each 'depthSpec' case also exact-prints the parsed module back to its
-- source, which fails if the deep parse dropped or reordered a token.
-- 'errorSpec' nests only three or four brackets: it checks that a broken
-- nest reports the error the parser always reported. 'memoSpec' parses
-- nests like it with the parser's memo on and off, and requires the same
-- answer.
module NestedParenParserSpec (spec) where

import Base
import Control.Exception (evaluate)
import qualified Data.Text as T
import L4.ExactPrint (exactprint)
import L4.Parser (PError (..), execProgramParserWithHintPass, execProgramParserWithHintPassUnmemoised)
import L4.Parser.SrcSpan (SrcPos (..), SrcSpan (..))
import System.Timeout (timeout)
import Test.Hspec

-- | How deep every construct is nested.
depth :: Int
depth = 40

-- | Seconds allowed per case.
budgetSeconds :: Int
budgetSeconds = 30

spec :: Spec
spec = do
  depthSpec
  errorSpec
  memoSpec

depthSpec :: Spec
depthSpec =
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

-- | Speeding the parser up must not move its errors. A bracket in pattern
-- position that is neither a pattern nor an expression fails both readings,
-- and megaparsec reports whichever got further; when such brackets nest, the
-- error depends on both readings of every level. An earlier version of the
-- fix (badea173a) got all six cases below wrong. In five it reported an
-- outer bracket or keyword instead, in the last of them in place of the
-- indentation diagnostic. In the third it reported the same token, but left
-- @EXACTLY@ out of what it expected.
--
-- Each expected position and message is copied from what the parser reported
-- before MATRYOSHKA was fixed: @l4 ast@ at 21467cd84 on @unstable@.
errorSpec :: Spec
errorSpec =
  describe "a nest of brackets in pattern position that fail both readings reports the error the parser always reported" $
    for_ brokenNests \ (name, src, at, expected) ->
      it name $ failsWith src at expected

-- | The cases of 'errorSpec': a name, the module, and where its one error
-- starts and how its message ends.
brokenNests :: [(String, Text, (Int, Int), Text)]
brokenNests =
  [ ( "MUST pay ( total ( base ( price PLUS tax 's ) TIMES rate ) PLUS fee )"
    , T.unlines
        [ "DECLARE Person IS ONE OF alice, bob"
        , "DECLARE Act IS ONE OF"
        , "  pay HAS amount IS A NUMBER"
        , "  Deliver HAS who IS A NUMBER, what IS A NUMBER"
        , ""
        , "GIVETH A DEONTIC Person Act"
        , "probe MEANS"
        , "  PARTY alice"
        , "  MUST pay ( total ( base ( price PLUS tax 's ) TIMES rate ) PLUS fee )"
        , "  WITHIN 3"
        , ""
        , "GIVETH A NUMBER"
        , "other MEANS 1"
        ]
    , (9, 44)
    , "unexpected 's\n"
        <> "expecting %, &&, (, ), *, +, -, .., ..., /, <, <=, =, =>, >, >=, ABOVE, AND, AT, BELOW, DIVIDED, EQUALS, FOLLOWED, Float Literal, GREATER, IMPLIES, LESS, MINUS, MODULO, Numeric Literal, OF, OR, PLUS, RAND, ROR, String Literal, TIMES, UNLESS, WHERE, identifier, infix identifier, mixfix keyword, space token, ||, or \8226\n"
    )
  , ("WHEN (((EXACTLY 1 PLUS) z PLUS) w PLUS)", inWhen "(((EXACTLY 1 PLUS) z PLUS) w PLUS)", (3, 32), closeBracketExpected)
  , ( "WHEN (((x ,) z PLUS) w PLUS)"
    , inWhen "(((x ,) z PLUS) w PLUS)"
    , (3, 24)
    , "unexpected ,\n"
        <> "expecting %, &&, (, ), *, +, -, .., ..., /, <, <=, =, =>, >, >=, ABOVE, AND, AT, BELOW, DIVIDED, EQUALS, EXACTLY, FOLLOWED, Float Literal, GREATER, IMPLIES, LESS, MINUS, MODULO, Numeric Literal, OF, OR, PLUS, RAND, ROR, String Literal, TIMES, UNLESS, WHERE, identifier, infix identifier, mixfix keyword, space token, ||, or \8226\n"
    )
  , ("WHEN (f ((g (1 PLUS) y PLUS)) x PLUS)", inWhen "(f ((g (1 PLUS) y PLUS)) x PLUS)", (3, 29), closeBracketExpected)
  , ("WHEN (f (g (h (1 PLUS) a PLUS) b PLUS) c PLUS)", inWhen "(f (g (h (1 PLUS) a PLUS) b PLUS) c PLUS)", (3, 31), closeBracketExpected)
  , ( "a DECIDE argument whose IF ... ELSE runs onto a line indented too little"
    , T.unlines
        [ "GIVEN n IS A NUMBER"
        , "GIVETH A NUMBER"
        , "DECIDE probe n IS 0"
        , "DECIDE probe ((Foo OF (EXACTLY IF 3.5 THEN f ELSE "
        , "  TRUE), \"s\") TIMES \"a(b\") IS 1"
        ]
    , (5, 3)
    , "incorrect indentation (got 3, should be greater than 32)\n"
    )
  ]
  where
    closeBracketExpected =
      "unexpected PLUS\n"
        <> "expecting %, ), FOLLOWED, WHERE, infix identifier, mixfix keyword, or space token\n"

-- | The parser's memo ('L4.Parser.memoGroup') replays a bracketed group's
-- first parse wherever the group is reached again. That is exact only while
-- the invariants documented at 'L4.Parser.memoGroup' hold, and if one breaks,
-- the memo replays a wrong syntax tree or a wrong error with no other
-- symptom. So each module here is parsed with the memo on and off, which
-- must give the same answer to the token: the same tree, hints and warnings,
-- or the same errors, message and position.
--
-- jl4-test does the same on its whole corpus ("parser memo changes
-- nothing"). The corpus has few nests and fewer broken ones, so the cases
-- here are nests in pattern position, where a failed pattern reading leaves
-- inner groups for the expression reading to replay: 'errorSpec''s six, and
-- the nests of PATTERN-REFERENCE-RULE-SPEC A.7 three or four levels deep,
-- broken and whole, with mixfix keywords and inline annotations inside the
-- groups replayed, and with an error already pending when they are parsed.
-- Without the memo the parser is exponential in depth, which is why these
-- stay shallow.
memoSpec :: Spec
memoSpec =
  describe "the parser's memo changes nothing: memo on and off agree" $ do
    for_ brokenNests \ (name, src, _, _) ->
      it name $ memoChangesNothing src
    it "a CONSIDER in pattern position whose WHEN holds the next bracket, four deep" $
      memoChangesNothing (inWhen (nestedTo 4 "((CONSIDER 1 WHEN " " THEN 1, OTHERWISE 2) PLUS 1)" "1"))
    it "the same nest as a deontic action's argument, four deep" $
      memoChangesNothing
        ( T.unlines
            [ "DECLARE Person IS ONE OF alice, bob"
            , "DECLARE Act IS ONE OF"
            , "  pay HAS amount IS A NUMBER"
            , ""
            , "GIVETH A DEONTIC Person Act"
            , "probe MEANS"
            , "  PARTY alice"
            , "  MUST pay " <> nestedTo 4 "((CONSIDER 1 WHEN " " THEN 1, OTHERWISE 2) PLUS 1)" "1"
            , "  WITHIN 3"
            ]
        )
    it "a broken chain, four deep: (f (CONSIDER 1 WHEN … THEN 1, OTHERWISE 2) x PLUS) around (1 PLUS)" $
      memoChangesNothing (inWhen (nestedTo 4 "(f (CONSIDER 1 WHEN " " THEN 1, OTHERWISE 2) x PLUS)" "(1 PLUS)"))
    it "a broken, alternating nest, three deep: (f (g (CONSIDER … ) b PLUS) a PLUS)" $
      memoChangesNothing (inWhen (nestedTo 3 "(f (g (CONSIDER 1 WHEN " " THEN 1, OTHERWISE 2) b PLUS) a PLUS)" "(1 PLUS)"))
    it "an unclosed nest, four deep: ((CONSIDER 1 WHEN ((CONSIDER 1 WHEN …" $
      memoChangesNothing (inWhen (nestedTo 4 "((CONSIDER 1 WHEN " "" "1"))
    it "brackets that ARE patterns, each holding a CONSIDER, four deep" $
      memoChangesNothing (inWhen (nestedTo 4 "((CONSIDER 1 WHEN " " THEN 1, OTHERWISE 2) FOLLOWED BY x)" "x"))
    -- @f 1 plus 1@ is @f@ of three arguments in the first pass, which has no
    -- mixfix hints, and @plus@ of @f 1@ and @1@ in the second.
    it "user-defined mixfix keywords, bare and backticked, in a nest in pattern position" $
      memoChangesNothing
        ( plusPrologue
            <> inWhen (nestedTo 4 "((CONSIDER 1 WHEN " " THEN f 1 plus 1, OTHERWISE 2) `plus` 1)" "(1 `plus` 1)")
        )
    it "inline annotations inside a nest in pattern position" $
      memoChangesNothing
        ( T.unlines
            [ "GIVEN walks IS A BOOLEAN, eats IS A BOOLEAN"
            , "GIVETH A NUMBER"
            , "probe walks eats MEANS"
            , "  CONSIDER TRUE WHEN "
                <> nestedTo 3 "((CONSIDER walks [it walks] WHEN " " THEN eats [it eats], OTHERWISE FALSE) AND eats [it eats])" "(walks [it walks])"
                <> " THEN 1, OTHERWISE 2"
            ]
        )
    -- The parser recovers from the broken declaration and reports its error
    -- at the end (megaparsec's delayed errors), so the error is pending while
    -- the nest is parsed.
    it "a broken declaration before a nest in pattern position" $
      memoChangesNothing
        ( T.unlines
            [ "GIVETH A NUMBER"
            , "broken MEANS"
            , ""
            , "GIVETH A NUMBER"
            , "probe MEANS"
            , "  CONSIDER 3 WHEN " <> nestedTo 4 "((CONSIDER 1 WHEN " " THEN 1, OTHERWISE 2) PLUS 1)" "1" <> " THEN 1, OTHERWISE 2"
            ]
        )

-- | Parse the module (both passes, as the tools do) and expect exactly one
-- error, starting at @(line, column)@ (both from 1), whose message ends with
-- @expected@. (The message starts with the offending source line.)
failsWith :: Text -> (Int, Int) -> Text -> Expectation
failsWith src at expected =
  case execProgramParserWithHintPass uri src of
    Right _ -> expectationFailure "parsed, but should have failed"
    Left errs -> do
      [(e.range.start.line, e.range.start.column) | e <- toList errs] `shouldBe` [at]
      [T.takeEnd (T.length expected) e.message | e <- toList errs] `shouldBe` [expected]
  where
    uri = toNormalizedUri (Uri "file:///nested-paren-parser-spec")

-- | Parse the module (both passes, as the tools do) with the memo on and off,
-- and expect the same answer.
memoChangesNothing :: Text -> Expectation
memoChangesNothing src =
  execProgramParserWithHintPass uri src `shouldBe` execProgramParserWithHintPassUnmemoised uri src
  where
    uri = toNormalizedUri (Uri "file:///nested-paren-parser-spec")

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
nestedIn = nestedTo depth

-- | Wrap @core@ in @n@ copies of @open@ … @close@.
nestedTo :: Int -> Text -> Text -> Text -> Text
nestedTo n open close core = iterate (\ e -> open <> e <> close) core !! n

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
