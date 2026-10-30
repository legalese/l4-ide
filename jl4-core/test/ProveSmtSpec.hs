{-# LANGUAGE OverloadedStrings #-}
-- | The SMT-LIB2 text @l4 prove@ emits: names escape injectively, and a script
-- that declares a symbol twice is caught before any solver sees it (audit of
-- legalese/l4-ide#784, finding 1: @a|b@ and @a_b@ became one parameter symbol,
-- z3 accepted the duplicate binder, and a FALSE assertion was "proved").
module ProveSmtSpec (spec) where

import Data.List (nub)
import qualified Data.Text as Text
import Test.Hspec

import L4.Prove.Smt

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
