{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

-- | @\@nlg@ annotations survive 'L4.Print.prettyLayout' (smucclaw\/l4-ide#966).
--
-- 'prettyLayout' used to drop every annotation in the corpus. Nothing caught
-- it: the @.ep.golden@ files come from the OTHER printer
-- ('L4.Rules.ExactPrint', which is token-based and never lost them), the
-- @.nlg.golden@ files linearize @#EVAL@ directives only — so a file like
-- @ok\/nlg_decide2.l4@, whose five annotations are all on a @DECIDE@, has an
-- EMPTY one — and @jl4-test@'s round-trip property asks whether the printed
-- text re-parses, which a module missing all its annotations does perfectly.
--
-- So the property here is deliberately stronger than re-parsing: print,
-- re-parse, and assert the SAME annotations come back attached to the SAME
-- names. That is what a printer owes a module it claims to re-emit, and it is
-- the assertion the round-trip test cannot make, because it compares nothing
-- across the two sides.
module PrettyLayoutNlgSpec (spec) where

import Base
import qualified Data.Text as T

import L4.Annotation (getAnno)
import L4.Nlg (simpleLinearizer)
import L4.Parser (execProgramParserWithHintPass)
import L4.Print (prettyLayout)
import L4.Syntax (Module, Name, annNlg, nameToText)
import qualified Optics
import Test.Hspec

-- | Every name in the module that carries an annotation, in source order,
-- paired with what that annotation SAYS — the linearized form, which is the
-- decoded text a reader would see.
--
-- Decoded rather than verbatim on purpose: it is the level at which an
-- escaping mistake shows up as a changed sentence rather than as a changed
-- byte, and a changed byte that decodes the same is not a defect.
annotatedNames :: Module Name -> [(Text, Text)]
annotatedNames m =
  [ (nameToText n, simpleLinearizer nlg)
  | n <- Optics.toListOf (Optics.gplate @Name) m
  , Just nlg <- [view annNlg (getAnno n)]
  ]

-- | Parse, print, re-parse, and compare the annotation tables.
--
-- The @mustContain@ list pins the printed SPELLING, which the table cannot
-- see. Without it the whole test still bites — an empty printed table would
-- not equal a populated original one — but it would not say which form was
-- emitted, and the form is the part that was hard to get right.
survivesPrinting :: String -> [Text] -> Text -> Spec
survivesPrinting name mustContain src =
  it ("carries its @nlg annotations through prettyLayout: " <> name) $ do
    let uri = toNormalizedUri (Uri "file:///pretty-layout-nlg-spec")
    case execProgramParserWithHintPass uri src of
      Left errs -> expectationFailure ("fixture source failed to parse: " <> show errs)
      Right (modul, _hints, _warnings) -> do
        let original = annotatedNames modul
            printed = prettyLayout modul
        -- Guard the fixture itself. A fixture whose annotations silently
        -- failed to attach would make the comparison below [] == [], which
        -- passes while testing nothing.
        when (null original) $
          expectationFailure "fixture carries no @nlg annotations at all"
        for_ mustContain $ \ needle ->
          unless (needle `T.isInfixOf` printed) $
            expectationFailure $
              "printed output is missing " <> show needle <> ":\n" <> T.unpack printed
        case execProgramParserWithHintPass uri printed of
          Left errs ->
            expectationFailure $
              "prettyLayout output did NOT re-parse:\n--- printed ---\n"
                <> T.unpack printed
                <> "\n--- errors ---\n"
                <> show errs
          Right (modul', _, _) ->
            unless (annotatedNames modul' == original) $
              expectationFailure $
                "annotations changed across the round trip\n  before: "
                  <> show original
                  <> "\n  after:  "
                  <> show (annotatedNames modul')
                  <> "\n--- printed ---\n"
                  <> T.unpack printed

spec :: Spec
spec = describe "prettyLayout re-emits @nlg annotations (#966)" $ do
  -- The shape of @jl4/examples/ok/nlg_decide2.l4@, which is the corpus witness
  -- and whose @.nlg.golden@ is empty. Note the last one: @\@nlg Expression@ is
  -- written under the body and reads as though it annotated the expression,
  -- but it attaches to the USE occurrence of @c@ — measured, and the reason
  -- the hook is the name printer rather than the declaration printers.
  survivesPrinting "appform head, parameters, and a use occurrence"
    ["[Test]", "[A Comment]"]
    "DECIDE foo @nlg Test\n\
    \            a @nlg A Comment\n\
    \            b @nlg B Comment\n\
    \            c @nlg %b%'s favorite coffee flavour\n\
    \    IS\n\
    \        (a PLUS c)\n\
    \        @nlg Expression\n"

  -- A reference fragment abutting a text fragment with no space between them.
  -- This is why the printer does not reuse 'L4.Print.LayoutPrinter' 'Nlg':
  -- that instance separates a reference from its neighbour with @<+>@, which
  -- would print @%b% 's@ and add a space on every round trip.
  survivesPrinting "a reference abutting the next word, with no space added"
    ["[%b%'s share]"]
    "DECIDE split b @nlg %b%'s share\n  IS b\n"

  -- The annotation goes straight after the PARAMETER. Written after the type
  -- instead — `GIVEN amount IS A NUMBER @nlg the amount`, which reads as the
  -- natural spelling — it attaches to `NUMBER`, and a type carries no
  -- annotation into print, so nothing would come back. That trap is the
  -- subject of its own finding; here it just decides where the fixture puts
  -- the annotation.
  survivesPrinting "a GIVEN parameter and a percentage in the prose"
    ["[a 5% share of %amount%]"]
    "GIVEN amount [a 5% share of %amount%] IS A NUMBER\n\
    \GIVETH A NUMBER\n\
    \DECIDE levy IS amount TIMES 2\n"

  survivesPrinting "a record field and its declaration head"
    ["[a person]", "[the full name]"]
    "DECLARE Person @nlg a person\n\
    \  HAS name [the full name] IS A STRING\n"

  -- The one place the two annotation forms are not interchangeable. A LINE
  -- annotation runs to end of line, so it may contain a bare @]@; the bracket
  -- form ends at the first @]@, and this tree has no escape for it. Emitting it
  -- anyway would leave the rest of the line as stray source that does not
  -- re-parse, so that ONE annotation is left out: the module must still
  -- re-parse, and every other annotation must still come back.
  it "leaves out a line annotation containing a bare close bracket, and nothing else" $ do
    let uri = toNormalizedUri (Uri "file:///pretty-layout-nlg-spec")
        src =
          "GIVEN n [the count] IS A NUMBER\n\
          \GIVETH A NUMBER\n\
          \DECIDE foo @nlg see note [3] here\n\
          \  IS n\n"
    case execProgramParserWithHintPass uri src of
      Left errs -> expectationFailure ("fixture source failed to parse: " <> show errs)
      Right (modul, _, _) -> do
        -- Guard the fixture: both annotations really attached in the source.
        annotatedNames modul
          `shouldBe` [("n", "the count"), ("foo", "see note [3] here")]
        let printed = prettyLayout modul
        printed `shouldSatisfy` T.isInfixOf "[the count]"
        printed `shouldSatisfy` (not . T.isInfixOf "see note")
        case execProgramParserWithHintPass uri printed of
          Left errs ->
            expectationFailure $
              "prettyLayout output did NOT re-parse:\n" <> T.unpack printed <> "\n" <> show errs
          Right (modul', _, _) ->
            annotatedNames modul' `shouldBe` [("n", "the count")]

  -- A backslash is ordinary text in an annotation on this tree — there are no
  -- escapes — so it is copied through exactly as written, including at the
  -- very end, where it sits immediately before the @]@ the printer appends.
  survivesPrinting "a line annotation ending in a lone backslash"
    ["[a discount of 50\\]"]
    "GIVEN q IS A NUMBER\n\
    \GIVETH A NUMBER\n\
    \DECIDE discounted @nlg a discount of 50\\\n\
    \  IS q TIMES 0.5\n"

  survivesPrinting "a backslash mid-text stays as written"
    ["[see s.3\\q here]"]
    "GIVEN r IS A NUMBER\n\
    \GIVETH A NUMBER\n\
    \`note on` r [see s.3\\q here] MEANS r TIMES 1\n"
