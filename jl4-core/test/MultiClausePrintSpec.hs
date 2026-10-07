{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | A multi-clause group printed back as source ('L4.Print.prettyLayout') is
-- its clauses as the drafter wrote them, printed from the AST
-- ('L4.Print.writtenClauses'), or, when one clause that matches anything is
-- all that is left, a plain definition. @l4 batch@ and the REPL run the
-- printed module, so each fixture here is checked, printed as the REPL prints
-- it, checked again and run again, and must give the same answers both ways.
--
-- What is printed is the REPL's pipeline (jl4-repl/app/Main.hs): mixfix
-- patterns restored, directives filtered out, then 'prettyLayout'. The
-- fixture's own @#EVAL@ lines are appended to the printed text to ask it the
-- same questions. @l4 batch@ additionally rewrites the ASSUMEs its export
-- reads ('L4.Export.rewriteModuleAssumes'), which none of these fixtures has;
-- the @l4 batch@ cases in tests-cli are the end-to-end guard on that path.
--
-- The fixtures are the shapes that broke an earlier printer: names the
-- desugarer makes up, which printed as text could be captured by a drafter's
-- definition of the same text; and clauses copied out of the source text,
-- whose dittos then resolved against the printer's lines, whose infix
-- operators lost their brackets, and whose tab indentation did not re-parse.
-- And every kind of pattern a clause head can hold, which must print as one
-- the parser reads back the same.
module MultiClausePrintSpec (spec) where

import Data.Char (isDigit)
import Data.List (partition)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Test.Hspec

import L4.API.VirtualFS (checkWithImports, vfsFromList)
import L4.DirectiveFilter (filterIdeDirectives)
import L4.EvaluateLazy (EvalDirectiveResult (..), execEvalModuleWithEnv, prettyEvalDirectiveResult, resolveEvalConfig)
import L4.EvaluateLazy.Machine (emptyEnvironment)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.Print (prettyLayout, restoreMixfixPatterns)
import L4.TracePolicy (apiDefaultPolicy)

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)

-- | Check and run a module; the module as the REPL prints it, and its answers.
checkAndRun :: Text.Text -> IO (Text.Text, [Text.Text])
checkAndRun src = do
  cfg <- resolveEvalConfig (Just (UTCTime (fromGregorian 2025 1 1) (secondsToDiffTime 0))) apiDefaultPolicy
  case checkWithImports (vfsFromList []) src of
    Left errs -> do
      expectationFailure ("typecheck failed: " <> show errs <> "\n--- source ---\n" <> Text.unpack src)
      pure ("", [])
    Right r -> do
      (_, results) <- execEvalModuleWithEnv cfg r.tcdEntityInfo emptyEnvironment r.tcdModule
      let printed = prettyLayout (filterIdeDirectives (restoreMixfixPatterns r.tcdMixfixRegistry r.tcdModule))
      pure (printed, map answer results)
  where
    answer (MkEvalDirectiveResult _ v _ l n p) = prettyEvalDirectiveResult (MkEvalDirectiveResult Nothing v Nothing l n p)

-- | The source without its @#EVAL@ lines, and those lines.
splitEvals :: Text.Text -> (Text.Text, Text.Text)
splitEvals src =
  let (evals, rest) = partition ("#EVAL" `Text.isPrefixOf`) (Text.lines src)
  in (Text.unlines rest, Text.unlines evals)

-- | Every spelling of a name the desugarer makes up (@input 1@, @the result
-- of clauses 2 to 3@), with how often it occurs.
madeUpNames :: Text.Text -> Map.Map Text.Text Int
madeUpNames t = Map.fromListWith (+) [ (n, 1 :: Int) | n <- inputs <> laters ]
  where
    inputs =
      [ "input " <> d
      | (_, rest) <- Text.breakOnAll "input " t
      , let d = Text.takeWhile isDigit (Text.drop 6 rest)
      , not (Text.null d)
      ]
    laters = [ Text.takeWhile (/= '`') rest | (_, rest) <- Text.breakOnAll "the result of clause" t ]

answersAgain :: Text.Text -> Spec
answersAgain src = do
  it "answers the same printed as from source" $ do
    (printed, fromSource) <- checkAndRun src
    (_, fromPrinted) <- checkAndRun (printed <> "\n" <> snd (splitEvals src))
    length fromSource `shouldSatisfy` (> 0)
    fromPrinted `shouldBe` fromSource
  -- A drafter may write the same text, so each spelling must occur exactly as
  -- often as in the source (without its #EVAL lines, which are not printed).
  -- That holds only if no omitted clause names one: the fixtures keep it so.
  it "prints no name the desugarer made up" $ do
    (printed, _) <- checkAndRun src
    madeUpNames printed `shouldBe` madeUpNames (fst (splitEvals src))

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
  -- One clause left, matching anything: it prints as a plain definition,
  -- whose inputs must not take a name the body reads.
  describe "with no GIVEN, a first clause that matches anything, beside `input 1`" $ answersAgain $ Text.unlines
    [ "DECLARE Colour IS ONE OF Red, Green, Blue"
    , "`input 1` MEANS Blue"
    , "`_1` MEANS Green"
    , "DECIDE h `_` IS `input 1`"
    , "DECIDE h Red IS Green"
    , "DECIDE h2 `_` `_` IS `_1`"
    , "DECIDE h2 Red Red IS Blue"
    , "#EVAL h Red"
    , "#EVAL h2 Red Green"
    ]
  describe "with a GIVEN, a first clause that matches anything, beside a definition named like its input" $ answersAgain $ Text.unlines
    [ "DECLARE Colour IS ONE OF Red, Green, Blue"
    , "c MEANS Blue"
    , "GIVEN c IS A Colour"
    , "GIVETH A Colour"
    , "DECIDE k `_` IS c"
    , "DECIDE k Red IS Green"
    , "#EVAL k Red"
    , "#EVAL k Green"
    ]
  -- A clause after one that matches anything is never tried; the checker
  -- drops it, and the printed group omits it ('L4.Print.writtenClauses').
  describe "with clauses after one that matches anything" $ do
    let src = Text.unlines
          [ "DECLARE Colour IS ONE OF Red, Green, Blue"
          , "GIVEN c IS A Colour"
          , "GIVETH A NUMBER"
          , "DECIDE f Red   IS 1"
          , "DECIDE f c     IS 2"
          , "DECIDE f Green IS 3"
          , "DECIDE g Red   Red IS 1"
          , "DECIDE g `_`   `_` IS 2"
          , "DECIDE g Blue  Red IS 3"
          , "#EVAL f Red"
          , "#EVAL f Green"
          , "#EVAL g Red Red"
          , "#EVAL g Blue Red"
          ]
    answersAgain src
    it "omits them" $ do
      (printed, _) <- checkAndRun src
      printed `shouldSatisfy` Text.isInfixOf "DECIDE f Red IS"
      printed `shouldNotSatisfy` Text.isInfixOf "DECIDE f Green IS"
      printed `shouldNotSatisfy` Text.isInfixOf "DECIDE g Blue Red IS"
  -- On unstable this source does not check (the generated test of `b` was
  -- ambiguous with the pattern variable), so there it fails before printing.
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
