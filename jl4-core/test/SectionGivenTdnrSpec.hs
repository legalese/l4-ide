{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | A section @GIVEN@ may bind one name several times at different types, the
-- way module-level @ASSUME@s do (@jl4\/examples\/ok\/tdnr.l4@): type-directed
-- name resolution then picks the binding each occurrence's context demands.
--
-- 'L4.TypeCheck.resolveSectionGiven' used to pair each parameter with its
-- desugared @ASSUME@ elaboration by raw name (@List.lookup@), so every
-- repetition of a name collapsed onto the FIRST elaboration. Nothing counted
-- that: the elaborations stayed distinct and they are what evaluates, so
-- @l4 check@ reported no error, the golden files were unchanged, and an oracle
-- comparing error COUNTS saw nothing. The damage was confined to the
-- 'GivenSig' the checker returns — which is precisely the node
-- 'L4.Print.prettyLayout' re-emits (it suppresses the elaborations), so
-- @l4 batch@ and the REPL rebuilt a module whose section binder had lost every
-- binding after the first.
--
-- These assertions therefore name WHICH binder and WHICH type is expected at
-- each position, and name the diagnostics that must not appear; a test that
-- counted anything would have passed throughout.
module SectionGivenTdnrSpec (spec) where

import Test.Hspec

import Data.List (nub)
import Data.Text (Text)
import qualified Data.Text as Text

import L4.API.VirtualFS (checkWithImports, emptyVFS)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.Names (getName)
import L4.Print (prettyLayout)
import L4.Syntax
import L4.TypeCheck.Types (CheckError (..), CheckErrorWithContext (..))

-- ----------------------------------------------------------------------------
-- Fixtures
-- ----------------------------------------------------------------------------

-- | The section-binder spelling of @jl4\/examples\/ok\/tdnr.l4@: one name, three
-- types, each reached by the type its use site demands.
overloadedBinder :: Text
overloadedBinder = Text.unlines
  [ "§ `S`"
  , "    GIVEN foo IS A NUMBER"
  , "          foo IS A BOOLEAN"
  , "          foo IS A STRING"
  , ""
  , "DECIDE bar"
  , "  IS foo + 2"
  , ""
  , "DECIDE baz"
  , "  IS NOT foo"
  , ""
  , "DECIDE all"
  , "  IS IF foo THEN foo ELSE \"foo\""
  ]

-- | Control: the ordinary shape, where every parameter has a different name.
distinctBinders :: Text
distinctBinders = Text.unlines
  [ "§ `S`"
  , "    GIVEN n IS A NUMBER"
  , "          b IS A BOOLEAN"
  , ""
  , "DECIDE bar"
  , "  IS IF b THEN n ELSE 0"
  ]

-- | Control for the other direction: a section that binds @foo@ on its heading
-- AND writes its own @ASSUME foo@ at a different type. The parameter must take
-- the elaboration of the heading's binder, never the hand-written @ASSUME@ —
-- the two are separate bindings and the printed @GIVEN@ must say @NUMBER@.
binderBesideHandWrittenAssume :: Text
binderBesideHandWrittenAssume = Text.unlines
  [ "§ `S`"
  , "    GIVEN foo IS A NUMBER"
  , ""
  , "ASSUME foo IS A BOOLEAN"
  , ""
  , "DECIDE bar"
  , "  IS foo + 2"
  , ""
  , "DECIDE baz"
  , "  IS NOT foo"
  ]

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------

data Checked = Checked
  { module_ :: Module Resolved
  , errors  :: [CheckErrorWithContext]
  }

check :: Text -> IO Checked
check source =
  case checkWithImports emptyVFS source of
    Left errs -> fail ("fixture failed before type-checking: " <> show errs)
    Right r   -> pure (Checked r.tcdModule r.tcdErrors)

-- | Every section's own @GIVEN@, outermost first. The root section is anonymous
-- and cannot carry one, so for these fixtures this is the @§ \`S\`@ heading's.
sectionGivens :: Module Resolved -> [GivenSig Resolved]
sectionGivens (MkModule _ _ sect) = goSection sect
 where
  goSection (MkSection _ _ _ mgiven decls) =
    maybe [] pure mgiven <> concatMap goDecl decls
  goDecl (Section _ s) = goSection s
  goDecl _             = []

-- | One section binder as @(name, type)@, both as the printer spells them.
binders :: Module Resolved -> [(Text, Text)]
binders modul =
  [ (prettyLayout (getName rnm), maybe "<untyped>" prettyLayout mTy)
  | MkGivenSig _ otns <- sectionGivens modul
  , MkOptionallyTypedName _ rnm mTy _ <- otns
  ]

-- | The 'Unique' each section binder resolves to: the identity of the binding,
-- as the evaluator and every backend key it.
binderUniques :: Module Resolved -> [Unique]
binderUniques modul =
  [ getUnique rnm
  | MkGivenSig _ otns <- sectionGivens modul
  , MkOptionallyTypedName _ rnm _ _ <- otns
  ]

-- | Diagnostics rendered as text, so a failure names them instead of counting
-- them.
ambiguities :: [CheckErrorWithContext] -> [Text]
ambiguities errs =
  [ prettyLayout n
  | MkCheckErrorWithContext {kind = AmbiguousTermError n _} <- errs
  ]

-- ----------------------------------------------------------------------------
-- Spec
-- ----------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "a section GIVEN binding one name at several types" $ do
    it "gives each parameter its own binder, at the type the source wrote" $ do
      c <- check overloadedBinder
      binders c.module_
        `shouldBe` [("foo", "NUMBER"), ("foo", "BOOLEAN"), ("foo", "STRING")]

    it "resolves the three parameters to three DISTINCT binders" $ do
      c <- check overloadedBinder
      let us = binderUniques c.module_
      length (nub us) `shouldBe` length us
      -- (stated as a length comparison because 'Unique' has no readable
      -- rendering; the preceding example is the one that names what went wrong)

    it "type-checks the source with no ambiguity diagnostic" $ do
      c <- check overloadedBinder
      ambiguities c.errors `shouldBe` []

    it "prettyLayout re-emits all three bindings, not the first one thrice" $ do
      c <- check overloadedBinder
      let printed = prettyLayout c.module_
          givenLines =
            [ Text.strip l | l <- Text.lines printed, "foo IS " `Text.isInfixOf` l ]
      givenLines
        `shouldBe` ["GIVEN foo IS NUMBER", "foo IS BOOLEAN", "foo IS STRING"]

    it "the re-printed module still type-checks (l4 batch / REPL path, #932)" $ do
      c <- check overloadedBinder
      c' <- check (prettyLayout c.module_)
      ambiguities c'.errors `shouldBe` []
      binders c'.module_
        `shouldBe` [("foo", "NUMBER"), ("foo", "BOOLEAN"), ("foo", "STRING")]

  describe "controls: pairing must not change where it was already right" $ do
    it "distinct parameter names keep their own types" $ do
      c <- check distinctBinders
      binders c.module_ `shouldBe` [("n", "NUMBER"), ("b", "BOOLEAN")]
      ambiguities c.errors `shouldBe` []

    it "a hand-written ASSUME of the binder's name is not taken by the parameter" $ do
      c <- check binderBesideHandWrittenAssume
      binders c.module_ `shouldBe` [("foo", "NUMBER")]
      ambiguities c.errors `shouldBe` []
