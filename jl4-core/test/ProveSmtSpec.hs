{-# LANGUAGE OverloadedStrings #-}
-- | The SMT-LIB2 text @l4 prove@ emits: names escape injectively, and a script
-- that declares a symbol twice is caught before any solver sees it (audit of
-- legalese/l4-ide#784, finding 1: @a|b@ and @a_b@ became one parameter symbol,
-- z3 accepted the duplicate binder, and a FALSE assertion was "proved").
module ProveSmtSpec (spec) where

import Data.List (nub)
import qualified Data.Text as Text
import Test.Hspec

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import L4.Prove.Lower (Obligation (..), Sort (..), proofSampleValues, sampleValues)
import L4.Prove.Smt
import L4.Syntax (Expr (..), Lit (..))

spec :: Spec
spec = describe "L4.Prove.Smt" $ do
  it "escapes the names a lossy sanitiser merged into distinct symbol bodies" $ do
    let names = ["a|b", "a_b", "a\\b", "a__b", "a_pb", "x#2", "x", "pi", "a b"]
        escaped = map escapeName names
    length (nub escaped) `shouldBe` length names
    escapeName "pi" `shouldBe` "pi"
    userSymbol "l4_" "a|b" `shouldBe` "|l4_a_pb|"
    -- nothing a quoted symbol cannot hold survives
    escaped `shouldSatisfy` all (Text.all (`notElem` ['|', '\\']))

  it "names a symbol a script declares twice, at top level or in one binder list" $ do
    let fun ps = SList [Atom "define-fun", Atom "|l4_f|", SList [ SList [Atom p, Atom "Real"] | p <- ps ], Atom "Real", Atom "0.0"]
        const' n = SList [Atom "declare-const", Atom n, Atom "Real"]
    duplicateDeclarations [const' "|l4_x|", fun ["|l4p_a|", "|l4p_b|"]] `shouldBe` []
    duplicateDeclarations [fun ["|l4p_a_b|", "|l4p_a_b|"]] `shouldBe` ["|l4p_a_b|"]
    duplicateDeclarations [const' "|l4_x|", const' "|l4_x|"] `shouldBe` ["|l4_x|"]

  -- Audit of #784: the unsat-side spot check sampled 0 and +-1 only, all
  -- whole, so an encoding defect behind an ISINTEGER guard passed it.
  it "samples fractions for the proof check, and keeps the Catala candidates whole" $ do
    let ob = Obligation [] [] Map.empty Nothing [0, 10] Set.empty
        nums xs = [ r | Lit _ (NumericLit _ r) <- xs ]
        proofNums = nums (proofSampleValues ob SReal)
    proofNums `shouldSatisfy` (\ns -> all (`elem` ns) [1 / 2, -1 / 2, 21 / 2, 19 / 2, 5, 0, 10, 9, 11, -1, 1])
    -- fractions first, so a capped product keeps them
    take 9 proofNums `shouldBe` [1 / 2, -1 / 2, 1 / 3, -1 / 3, 1 / 7, -1 / 7, 10 + 1 / 2, 10 - 1 / 2, 5]
    nums (sampleValues ob SReal) `shouldBe` [0, -1, 1, 10, 9, 11]

  -- smucclaw/l4-ide#1098: cvc5's model values are read by the reader z3's are.
  -- A negative fraction may come as `(/ (- 1) 3)` or as `(- (/ 1 3))`, and a
  -- whole number with or without a decimal point; each must read as the same
  -- rational.
  it "reads a Real model value in each spelling a solver may print" $ do
    let readOne t = case parseSExprs t of
          Right [e] -> readRational e
          _ -> Nothing
    readOne "(/ 4 3)" `shouldBe` Just (4 / 3)
    readOne "(/ 4.0 3.0)" `shouldBe` Just (4 / 3)
    readOne "(/ (- 1) 3)" `shouldBe` Just (-1 / 3)
    readOne "(- (/ 1 3))" `shouldBe` Just (-1 / 3)
    readOne "(- (/ 1.0 3.0))" `shouldBe` Just (-1 / 3)
    readOne "(- 5.0)" `shouldBe` Just (-5)
    readOne "(- 5)" `shouldBe` Just (-5)
    readOne "7" `shouldBe` Just 7
    readOne "7.0" `shouldBe` Just 7
    readOne "0.25" `shouldBe` Just (1 / 4)
    -- an algebraic number is not a rational, and is not guessed at
    readOne "(root-obj (+ (^ x 2) (- 2)) 2)" `shouldBe` Nothing

  -- A solver's output after `unsat` is an error for the script's get-value,
  -- which the reader need not understand: the answer is the first expression.
  it "reads the expressions before the first one it cannot parse, and says why it stopped" $ do
    parseSExprsPrefix "unsat\n(error \"cannot get a value\")\n"
      `shouldBe` ([Atom "unsat", SList [Atom "error", Atom "\"cannot get a value\""]], Nothing)
    case parseSExprsPrefix "unsat\n(error \"cut off" of
      ([Atom "unsat"], Just _) -> pure ()
      other -> expectationFailure ("expected [unsat] and a reason, got " <> show other)
    case parseSExprsPrefix ")" of
      ([], Just _) -> pure ()
      other -> expectationFailure ("expected nothing and a reason, got " <> show other)
    -- parseSExprs reads the whole output, so it fails where the prefix stops
    parseSExprs "unsat\n(error \"cut off" `shouldSatisfy` either (const True) (const False)
    parseSExprs "sat\n((l4_x (/ (- 1) 3)) (|l4.goal| false))"
      `shouldBe` Right [ Atom "sat"
                       , SList [ SList [Atom "l4_x", SList [Atom "/", SList [Atom "-", Atom "1"], Atom "3"]]
                               , SList [Atom "|l4.goal|", Atom "false"] ] ]
