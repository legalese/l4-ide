{-# LANGUAGE OverloadedStrings #-}

-- | Regression coverage for the parser/exactprint edge-crash hardening in
-- compiler review target T9.
--
-- T9a — 'displayTokenType' must be total for @TSymbols (TOtherSymbolic _)@.
-- Rendering such a token used to fall through to 'inverseCompleteLookup',
-- whose partial @error@ is a latent crash if that (currently shadowed) lexer
-- branch ever becomes reachable (e.g. via a future @try@ that un-shadows the
-- @operatorsPayload@ producer).
module EdgeCrashSpec (spec) where

import L4.Lexer (TSymbols (TOtherSymbolic), TokenType (TSymbols), displayTokenType)
import Test.Hspec

spec :: Spec
spec =
  describe "displayTokenType is total for TOtherSymbolic (T9a)" $ do
    it "renders a single stray operator char verbatim without crashing" $
      displayTokenType (TSymbols (TOtherSymbolic "~")) `shouldBe` "~"
    it "renders a multi-character operator run verbatim" $
      displayTokenType (TSymbols (TOtherSymbolic "~&|")) `shouldBe` "~&|"
