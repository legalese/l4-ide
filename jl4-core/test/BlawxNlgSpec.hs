{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | Declaration NLG: what @\@nlg@ becomes in a Blawx declaration block, and
-- what is synthesised when no @\@nlg@ is written (BLAWX-EXPORT-SPEC §11 W4,
-- amending R10 and §4.9).
--
-- __Why here and not in a @.blawx@ golden.__ Same reason 'BlawxAssumeSpec'
-- gives: the two seeds under @jl4\/examples\/blawx\/@ pin what a whole
-- realistic module emits, but a default and its four refusals need a battery of
-- modules differing in ONE annotation each, and a golden per refusal would be a
-- golden per line. Every source below runs the real pipeline (type check →
-- 'lowerModule' → 'lowerBlawx' → 'renderBlawxYaml') and asserts on emitted
-- text, so nothing here can drift from what @l4 blawx@ writes.
--
-- __Where the expected strings come from.__ Not from this file's taste: the
-- verb-infix and the transcribed sentences are Jason Morris's own hand NLG,
-- read out of @blawx\/static\/blawx\/examples\/{rps,beard_tax}.yaml@ at
-- checkout @6a717b1@ — @blawx_attribute_nlg(beats,ov,"","beats","")@ and
-- @blawx_attribute_nlg(bearded,not_applicable,"",not_applicable,"is bearded")@.
module BlawxNlgSpec (spec) where

import Test.Hspec

import Data.Text (Text)
import qualified Data.Text as Text

import L4.API.VirtualFS (TypeCheckWithDepsResult (..), checkWithImports, emptyVFS)
import L4.Blawx.Emit (renderBlawxYaml)
import L4.Blawx.Lower (lowerBlawx)
import L4.Relational.IR (renderLowerError)
import L4.Relational.Lower (defaultLowerOptions, lowerModule)
import qualified L4.TypeCheck as TC
import L4.TypeCheck.Types (Severity (..))

-- | Source → the @.blawx@ YAML, or the failing stage's diagnostics as text.
-- Type-check errors surface as a 'Left' for the reason 'BlawxAssumeSpec'
-- records: asserting on a module L4 rejects pins the exporter's treatment of a
-- broken module rather than of the spelling under test.
blawxYaml :: Text -> Either Text Text
blawxYaml src = case checkWithImports emptyVFS src of
  Left errs -> Left ("parse/import: " <> Text.unlines errs)
  Right r
    | errs@(_ : _) <- filter ((== SError) . TC.severity) r.tcdErrors ->
        Left ("typecheck: " <> Text.unlines (concatMap TC.prettyCheckErrorWithContext errs))
    | otherwise -> case lowerModule defaultLowerOptions r.tcdEntityInfo r.tcdModule of
        Left es -> Left ("lowering: " <> Text.unlines (map renderLowerError es))
        Right prog -> case lowerBlawx prog of
          Left es -> Left ("blawx: " <> Text.unlines (map renderLowerError es))
          Right doc -> Right (renderBlawxYaml doc)

emitted :: Text -> IO Text
emitted src = case blawxYaml src of
  Left err  -> do expectationFailure (Text.unpack err); pure ""
  Right out -> pure out

-- | Assert that the module is refused, and that the refusal names the slot
-- structure and carries the given explanation fragment. A refusal that reached
-- the type checker instead would pass a bare @isLeft@, so both halves matter.
refusedFor :: Text -> Text -> Expectation
refusedFor needle src = case blawxYaml src of
  Right _  -> expectationFailure "expected a refusal, got emitted YAML"
  Left err -> do
    (("names the diagnostic", "@nlg slot structure (Blawx)" `Text.isInfixOf` err)
       :: (Text, Bool))
      `shouldBe` ("names the diagnostic", True)
    (needle, needle `Text.isInfixOf` err) `shouldBe` (needle, True)

hasLine :: Text -> Text -> Expectation
hasLine out needle = (needle, needle `Text.isInfixOf` out) `shouldBe` (needle, True)

-- | An RPS-shaped module. @throws@ is object-valued and verb-shaped;
-- @favourite@ is object-valued and noun-shaped; @rounds@ is a NUMBER whose name
-- ends in @s@, which is the control for "object-valued only".
signModule :: Text -> Text -> Text
signModule fieldAnno decideAnno = Text.unlines
  [ "DECLARE Sign IS ONE OF Rock, Paper"
  , ""
  , "DECLARE Player HAS"
  , "    throws IS A Sign" <> fieldAnno
  , "    favourite IS A Sign"
  , "    rounds IS A NUMBER"
  , ""
  , "@export"
  , "GIVEN p IS A Player"
  , "GIVETH A BOOLEAN"
  , "DECIDE `wins`"
  , decideAnno
  , "  IF p's throws EQUALS Rock"
  ]

plain :: Text
plain = signModule "" ""

spec :: Spec
spec = do
  describe "synthesised NLG (no @nlg written)" $ do
    it "reads a one-word object-valued attribute as a verb and makes it the infix" $ do
      out <- emitted plain
      hasLine out "blawx_attribute_nlg(throws,ov,\"\",\"throws\",\"\")."
      hasLine out "#pred throws(X,Y) :: '@(X) throws @(Y)'."

    it "leaves a noun-shaped object-valued attribute on the possessive default" $ do
      out <- emitted plain
      hasLine out "blawx_attribute_nlg(favourite,ov,\"\",\"has favourite of\",\"\")."

    it "does not read a NUMBER-valued attribute as a verb, however it is spelled" $ do
      out <- emitted plain
      hasLine out "blawx_attribute_nlg(rounds,ov,\"\",\"has rounds of\",\"\")."

    it "keeps the boolean postfix and the category sentence" $ do
      out <- emitted plain
      hasLine out "blawx_attribute_nlg(wins,not_applicable,\"\",not_applicable,\"wins\")."
      hasLine out "blawx_category_nlg(player,\"\",\"is a player\")."

  describe "@nlg becomes the declaration's slots" $ do
    it "cuts a two-slot field sentence written in Blawx's own placeholders" $ do
      out <- emitted (signModule " @nlg the sign thrown by @(X) is @(Y)" "")
      hasLine out "blawx_attribute_nlg(throws,ov,\"the sign thrown by\",\"is\",\"\")."
      hasLine out "#pred throws(X,Y) :: 'the sign thrown by @(X) is @(Y)'."

    it "cuts a one-slot decision sentence written as an L4 parameter reference" $ do
      out <- emitted (signModule "" "@nlg %p% is the winner")
      hasLine out "blawx_attribute_nlg(wins,not_applicable,\"\",not_applicable,\"is the winner\")."
      hasLine out "#pred wins(X) :: '@(X) is the winner'."

    it "keeps a prefix before the subject slot" $ do
      out <- emitted (signModule "" "@nlg the round is won by %p%")
      hasLine out "blawx_attribute_nlg(wins,not_applicable,\"the round is won by\",not_applicable,\"\")."

    -- Jason Morris's own s.1 postfix begins with an apostrophe, which the
    -- #pred string (single-quoted) escapes and the *_nlg fact (double-quoted)
    -- does not. Both spellings appear in one emission, so this pins the pair.
    it "escapes an apostrophe in the #pred string only" $ do
      out <- emitted (signModule "" "@nlg %p% 's round is won")
      hasLine out "blawx_attribute_nlg(wins,not_applicable,\"\",not_applicable,\"'s round is won\")."
      hasLine out "#pred wins(X) :: '@(X) \\'s round is won'."

  describe "@nlg refusals are loud" $ do
    it "refuses a sentence with the wrong number of slots" $
      refusedFor "has 2 slot(s), but its Blawx declaration block has 1"
        (signModule "" "@nlg %p% beats @(Y)")

    it "refuses a sentence with no slots at all" $
      refusedFor "has 0 slot(s), but its Blawx declaration block has 2"
        (signModule " @nlg the sign thrown" "")

    it "refuses Blawx placeholders written out of the block's argument order" $
      refusedFor "writes @(Y) where its Blawx declaration block's argument 1 is @(X)"
        (signModule " @nlg @(Y) is thrown by @(X)" "")

    it "refuses two adjacent slots, which would emit a double space" $
      refusedFor "leaves no words between two slots"
        (signModule " @nlg @(X)@(Y)" "")

    it "refuses a double quote, which the *_nlg facts carry unescaped" $
      refusedFor "contains a double quote"
        (signModule " @nlg @(X) throws the \"sign\" @(Y)" "")
