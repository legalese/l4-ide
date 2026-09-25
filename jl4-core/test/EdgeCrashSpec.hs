{-# LANGUAGE OverloadedStrings #-}

-- | Regression coverage for the parser/exactprint edge-crash hardening in
-- compiler review target T9, plus the resolved-ditto diagnostic rendering.
--
-- T9a — 'displayTokenType' must be total for @TSymbols (TOtherSymbolic _)@.
-- Rendering such a token used to fall through to 'inverseCompleteLookup',
-- whose partial @error@ is a latent crash if that (currently shadowed) lexer
-- branch ever becomes reachable (e.g. via a future @try@ that un-shadows the
-- @operatorsPayload@ producer).
--
-- Resolved dittos — 'displayPosTokenDiag' names the token a caret resolved
-- to, so parse errors caused by the copied token stop reading "unexpected ^"
-- (which hid the infix-under-connective defect for three weeks); meanwhile
-- 'displayPosToken' must keep printing the caret the user wrote, because
-- exactprint byte-identity reconstructs source text through it.
module EdgeCrashSpec (spec) where

import Base (Uri (..), toNormalizedUri)
import L4.Lexer
  ( TIdentifiers (TQuoted)
  , TSymbols (TCopy, TOtherSymbolic)
  , TokenType (TIdentifiers, TSymbols)
  , displayPosToken
  , displayPosTokenDiag
  , displayTokenType
  , trivialToken
  )
import Test.Hspec

spec :: Spec
spec = do
  describe "displayTokenType is total for TOtherSymbolic (T9a)" $ do
    it "renders a single stray operator char verbatim without crashing" $
      displayTokenType (TSymbols (TOtherSymbolic "~")) `shouldBe` "~"
    it "renders a multi-character operator run verbatim" $
      displayTokenType (TSymbols (TOtherSymbolic "~&|")) `shouldBe` "~&|"
  describe "resolved-ditto rendering" $ do
    let tok = trivialToken (toNormalizedUri (Uri "file:///edge-crash-spec"))
        resolved = TSymbols (TCopy (Just (TIdentifiers (TQuoted "resides in"))))
    it "displayPosTokenDiag names the token a resolved ditto copied" $
      displayPosTokenDiag (tok resolved)
        `shouldBe` "^ (resolved to `resides in`)"
    it "displayPosTokenDiag keeps an unresolved ditto as a bare caret" $
      displayPosTokenDiag (tok (TSymbols (TCopy Nothing))) `shouldBe` "^"
    it "displayPosTokenDiag stays total when a ditto copied an unresolved ditto" $
      displayPosTokenDiag (tok (TSymbols (TCopy (Just (TSymbols (TCopy Nothing))))))
        `shouldBe` "^ (resolved to ^)"
    it "displayPosTokenDiag falls through to displayPosToken for ordinary tokens" $
      displayPosTokenDiag (tok (TIdentifiers (TQuoted "x"))) `shouldBe` "`x`"
    it "displayPosToken still prints a resolved ditto as the caret the user wrote (exactprint contract)" $
      displayPosToken (tok resolved) `shouldBe` "^"
