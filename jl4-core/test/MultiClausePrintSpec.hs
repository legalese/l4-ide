{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | A multi-clause group printed back as source ('L4.Print.prettyLayout') is
-- its clauses as the drafter wrote them, printed from the AST
-- ('L4.Print.writtenClauses'). @l4 batch@ and the REPL run the printed module,
-- so each fixture here is checked, printed, checked again and run again, and
-- must give the same answers both ways.
--
-- The fixtures are the shapes that broke an earlier printer: names the
-- desugarer makes up, which printed as text could be captured by a drafter's
-- definition of the same text; and clauses copied out of the source text,
-- whose dittos then resolved against the printer's lines, whose infix
-- operators lost their brackets, and whose tab indentation did not re-parse.
-- And every kind of pattern a clause head can hold, which must print as one
-- the parser reads back the same.
module MultiClausePrintSpec (spec) where

import Data.Foldable (for_)
import qualified Data.Text as Text
import Test.Hspec

import L4.API.VirtualFS (checkWithImports, vfsFromList)
import L4.EvaluateLazy (EvalDirectiveResult (..), execEvalModuleWithEnv, prettyEvalDirectiveResult, resolveEvalConfig)
import L4.EvaluateLazy.Machine (emptyEnvironment)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.Print (prettyLayout)
import L4.TracePolicy (apiDefaultPolicy)

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)

-- | Check and run a module; its printed text and its answers.
checkAndRun :: Text.Text -> IO (Text.Text, [Text.Text])
checkAndRun src = do
  cfg <- resolveEvalConfig (Just (UTCTime (fromGregorian 2025 1 1) (secondsToDiffTime 0))) apiDefaultPolicy
  case checkWithImports (vfsFromList []) src of
    Left errs -> do
      expectationFailure ("typecheck failed: " <> show errs <> "\n--- source ---\n" <> Text.unpack src)
      pure ("", [])
    Right r -> do
      (_, results) <- execEvalModuleWithEnv cfg r.tcdEntityInfo emptyEnvironment r.tcdModule
      pure (prettyLayout r.tcdModule, map answer results)
  where
    answer (MkEvalDirectiveResult _ v _ l n p) = prettyEvalDirectiveResult (MkEvalDirectiveResult Nothing v Nothing l n p)

answersAgain :: Text.Text -> Spec
answersAgain src = do
  it "answers the same printed as from source" $ do
    (printed, fromSource) <- checkAndRun src
    (_, fromPrinted) <- checkAndRun printed
    length fromSource `shouldSatisfy` (> 0)
    fromPrinted `shouldBe` fromSource
  -- A drafter may write the same text; it may appear as often as they did.
  it "prints no name the desugarer made up" $ do
    (printed, _) <- checkAndRun src
    for_ ["the result of clause", "input 1"] \ made ->
      Text.count made printed `shouldSatisfy` (<= Text.count made src)

spec :: Spec
spec = describe "a multi-clause group, printed and run again" $ do
  describe "with a drafter's names like the desugarer's" $ answersAgain $ Text.unlines
    [ "DECLARE Colour IS ONE OF Red, Green, Blue"
    , "`the result of clauses 2 to 3` MEANS 7"
    , "`the result of clause 3` MEANS 100"
    , "GIVEN c IS A Colour"
    , "GIVETH A NUMBER"
    , "DECIDE u Red   IS `the result of clauses 2 to 3`"
    , "DECIDE u Green IS `the result of clause 3` + 1"
    , "DECIDE u c     IS 3"
    , "#EVAL u Red"
    , "#EVAL u Green"
    , "#EVAL u Blue"
    ]
  describe "with no GIVEN, beside a drafter's `input 1`" $ answersAgain $ Text.unlines
    [ "DECLARE Colour IS ONE OF Red, Green, Blue"
    , "`input 1` MEANS Blue"
    , "DECIDE h Red   IS `input 1`"
    , "DECIDE h Green IS Red"
    , "DECIDE h Blue  IS Green"
    , "#EVAL h Red"
    ]
  describe "with a pattern variable named like a later input" $ answersAgain $ Text.unlines
    [ "GIVEN a IS A BOOLEAN"
    , "      b IS A BOOLEAN"
    , "GIVETH A NUMBER"
    , "DECIDE f b TRUE  IS 1"
    , "DECIDE f a FALSE IS 2"
    , "#EVAL f TRUE TRUE"
    , "#EVAL f TRUE FALSE"
    , "#EVAL f FALSE TRUE"
    ]
  describe "with dittos in the clauses" $ answersAgain $ Text.unlines
    [ "DECLARE Colour IS ONE OF Red, Green, Blue"
    , "`b`MEANS IF TRUE THEN 1 ELSE 2"
    , "`fee` Red       MEANS ^"
    , "`fee` c         MEANS 0"
    , "GIVETH A BOOLEAN"
    , "k MEANS FALSE OR"
    , "  TRUE"
    , "f ^    MEANS 1"
    , "f b    MEANS 2"
    , "#EVAL `fee` Red"
    , "#EVAL f TRUE"
    , "#EVAL f FALSE"
    ]
  describe "with infix operators of declared precedence" $ answersAgain $ Text.unlines
    [ "@infixl 6"
    , "GIVEN p IS A NUMBER"
    , "      q IS A NUMBER"
    , "GIVETH A NUMBER"
    , "p UNIONN q MEANS p + q"
    , "@infixl 7"
    , "GIVEN p IS A NUMBER"
    , "      q IS A NUMBER"
    , "GIVETH A NUMBER"
    , "p INTERSECTN q MEANS p * q"
    , "DECLARE Colour IS ONE OF Red, Green, Blue"
    , "GIVEN c IS A Colour"
    , "GIVETH A NUMBER"
    , "DECIDE calc Red   IS 1 UNIONN 2 INTERSECTN 3"
    , "DECIDE calc Green IS 2 INTERSECTN 3 UNIONN 1"
    , "DECIDE calc c     IS 0"
    , "#EVAL calc Red"
    , "#EVAL calc Green"
    ]
  describe "indented with tabs" $ answersAgain $ Text.unlines
    [ "DECLARE Colour IS ONE OF Red, Green, Blue"
    , "GIVEN c IS A Colour"
    , "GIVETH A NUMBER"
    , "\tDECIDE fee Red   IS 1"
    , "\tDECIDE fee Green IS"
    , "\t\t2 + 1"
    , "\tDECIDE fee c     IS 3"
    , "#EVAL fee Red"
    , "#EVAL fee Green"
    , "#EVAL fee Blue"
    ]
  describe "with every kind of pattern a clause head holds" $ answersAgain $ Text.unlines
    [ "DECLARE Colour IS ONE OF Red, Green, Blue"
    , "DECLARE Shape IS ONE OF"
    , "  Circle HAS colour IS A Colour"
    , "  Box    HAS inner IS A MAYBE Colour"
    , "  Square"
    , "limit MEANS 3"
    , "GIVEN n IS A NUMBER"
    , "GIVETH A STRING"
    , "DECIDE sign -1  IS \"minus one\""
    , "DECIDE sign 0.5 IS \"half\""
    , "DECIDE sign (EXACTLY limit) IS \"the limit\""
    , "DECIDE sign n   IS \"other\""
    , "GIVEN s IS A STRING"
    , "GIVETH A NUMBER"
    , "DECIDE code \"a\"   IS 1"
    , "DECIDE code \"b c\" IS 2"
    , "DECIDE code s     IS 0"
    , "GIVEN sh IS A Shape"
    , "GIVETH A STRING"
    , "DECIDE shape (Circle Red)      IS \"red circle\""
    , "DECIDE shape (Box (JUST Blue)) IS \"box of blue\""
    , "DECIDE shape (Box NOTHING)     IS \"empty box\""
    , "DECIDE shape (Circle c)        IS \"some circle\""
    , "DECIDE shape sh                IS \"something\""
    , "GIVEN xs IS A LIST OF NUMBER"
    , "GIVETH A NUMBER"
    , "DECIDE hd (x FOLLOWED BY rest) IS x"
    , "DECIDE hd xs                   IS 0"
    , "#EVAL sign -1"
    , "#EVAL sign 0.5"
    , "#EVAL sign 3"
    , "#EVAL sign 7"
    , "#EVAL code \"a\""
    , "#EVAL code \"b c\""
    , "#EVAL code \"z\""
    , "#EVAL shape (Circle Red)"
    , "#EVAL shape (Box (JUST Blue))"
    , "#EVAL shape (Box NOTHING)"
    , "#EVAL shape (Circle Green)"
    , "#EVAL shape Square"
    , "#EVAL hd (LIST 4, 5)"
    , "#EVAL hd EMPTY"
    ]
