{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | A warning raised while a name is being resolved must not decide what the
-- name resolves to.
--
-- A name with two meanings (an input named like a record field, two
-- definitions told apart by their types, names in sections, an imported
-- definition against a field) is resolved by trying each meaning and keeping
-- the ones that check. A CONSIDER that misses a case, or repeats one, raises
-- a warning in the course of that check, and a meaning that carried any
-- diagnostic at all was dropped: the module then failed with "multiple
-- definitions for the identifier ...", and the warning was never shown.
-- Only a diagnostic of error severity may drop a meaning
-- ('L4.TypeCheck.Types.viableCandidate').
--
-- Each shape below is checked in three variants, which differ only in the
-- arms of its one CONSIDER: complete (no diagnostic), missing a case (one
-- warning, naming it) and repeating a case (one warning, naming that).
module DisambiguationWarningsSpec (spec) where

import Data.Text (Text)
import qualified Data.Text as Text
import Test.Hspec

import L4.API.VirtualFS (VFS, checkWithImports, emptyVFS, vfsFromList)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.TypeCheck (prettyCheckErrorWithContext, severity)
import L4.TypeCheck.Types (CheckErrorWithContext, Severity (..))

data Variant = Complete | Missing | Repeated
  deriving stock (Eq, Show, Bounded, Enum)

-- | A shape: the files it imports, and its source for each variant.
data Shape = MkShape
  { name    :: Text
  , imports :: [(Text, Text)]
  , source  :: Variant -> Text
  }

-- | A CONSIDER over an enumeration declared in another file is not checked
-- for the cases it misses, so that variant has no warning to look for.
variantsOf :: Shape -> [Variant]
variantsOf shape
  | null shape.imports = [minBound .. maxBound]
  | otherwise          = [Complete, Repeated]

spec :: Spec
spec = describe "a warning does not decide what a name resolves to" $ do
  mapM_ shapeSpec shapes

  it "still reaches the user once when the module has no other meaning to choose from" $ do
    -- The control: nothing to resolve, so this is the warning as it always was.
    (errors, warns) <- diagnostics emptyVFS $ Text.unlines $
      colour <> ["", "GIVEN c IS A Colour", "GIVETH A BOOLEAN", "DECIDE likes c IS"] <> consider "c" Missing
    errors `shouldBe` []
    map (mentions "WHEN Blue") warns `shouldBe` [True]

  it "still reports a name that two definitions both fit as ambiguous, once at each site, beside each site's warning" $ do
    -- Two definitions of `thing` that both check are an error in any version,
    -- and a warning at the site must change neither which error is reported
    -- nor how many. Three sites, each a CONSIDER that misses a case. This is
    -- about the diagnostics only: how long they take to produce is not
    -- measured here. The same file gives the same diagnostics on main, where
    -- the meaning that carries a warning is dropped, and on unstable.
    (errors, warns) <- diagnostics emptyVFS $ Text.unlines
      [ "DECLARE Colour IS ONE OF Red, Green"
      , "DECLARE Light IS ONE OF Red, Green"
      , ""
      , "GIVETH A Colour"
      , "DECIDE thing IS Red"
      , ""
      , "GIVETH A Light"
      , "DECIDE thing IS Green"
      , ""
      , "GIVETH A NUMBER"
      , "DECIDE score IS"
      , "       (CONSIDER thing"
      , "          WHEN Red THEN 1)"
      , "  PLUS (CONSIDER thing"
      , "          WHEN Red THEN 2)"
      , "  PLUS (CONSIDER thing"
      , "          WHEN Red THEN 3)"
      ]
    length errors `shouldBe` 3
    map (mentions "There are multiple definitions for the identifier") errors `shouldBe` [True, True, True]
    map (\ e -> mentions "of type Colour" e && mentions "of type Light" e) errors `shouldBe` [True, True, True]
    length warns `shouldBe` 3
    map (mentions "WHEN Green THEN") warns `shouldBe` [True, True, True]

  it "reports two meanings as ambiguous when only one of them carries a warning" $ do
    -- `thing` at Colour (Red, Green) and at Light (Red). The CONSIDER covers
    -- Red only: for the Colour meaning that misses Green, a warning; for the
    -- Light meaning it is complete. Both meanings check, so the name is
    -- ambiguous. Main dropped the meaning that carried the warning, took the
    -- other without a word and accepted the module, which is the rule this
    -- change removes (a warning must not decide what a name resolves to). It
    -- is the one place the verdict on a module changes: the error is the one
    -- unstable gives, and the warning is shown beside it.
    (errors, warns) <- diagnostics emptyVFS $ Text.unlines
      [ "DECLARE Colour IS ONE OF Red, Green"
      , "DECLARE Light IS ONE OF Red"
      , ""
      , "GIVETH A Colour"
      , "DECIDE thing IS Red"
      , ""
      , "GIVETH A Light"
      , "DECIDE thing IS Red"
      , ""
      , "GIVETH A NUMBER"
      , "DECIDE score IS"
      , "  CONSIDER thing"
      , "    WHEN Red THEN 1"
      ]
    length errors `shouldBe` 1
    map (mentions "There are multiple definitions for the identifier") errors `shouldBe` [True]
    map (\ e -> mentions "of type Colour" e && mentions "of type Light" e) errors `shouldBe` [True]
    length warns `shouldBe` 1
    map (mentions "WHEN Green THEN") warns `shouldBe` [True]

shapeSpec :: Shape -> Spec
shapeSpec shape = describe (Text.unpack shape.name) $ do
  when' Complete $
    it "checks a CONSIDER that covers every case without a diagnostic" $ do
      (errors, warns) <- run Complete
      errors `shouldBe` []
      warns `shouldBe` []

  when' Missing $
    it "reports the case a CONSIDER misses, once, and no error" $ do
      (errors, warns) <- run Missing
      errors `shouldBe` []
      length warns `shouldBe` 1
      map (mentions "still need to be considered") warns `shouldBe` [True]
      map (mentions "WHEN Blue") warns `shouldBe` [True]

  when' Repeated $
    it "reports the case a CONSIDER repeats, once, and no error" $ do
      (errors, warns) <- run Repeated
      errors `shouldBe` []
      length warns `shouldBe` 1
      map (mentions "redundant") warns `shouldBe` [True]
  where
    run variant = diagnostics (vfsFromList shape.imports) (shape.source variant)
    when' variant check
      | variant `elem` variantsOf shape = check
      | otherwise                       = pure ()

-- ----------------------------------------------------------------------------
-- The shapes
-- ----------------------------------------------------------------------------

colour :: [Text]
colour = ["DECLARE Colour IS ONE OF Red, Green, Blue"]

-- | The CONSIDER over @scrutinee@, in the three variants.
consider :: Text -> Variant -> [Text]
consider scrutinee variant =
  [ "  CONSIDER " <> scrutinee ]
    <> [ "    " <> arm | arm <- arms ]
  where
    arms = case variant of
      Complete -> ["WHEN Red THEN TRUE", "WHEN Green THEN FALSE", "WHEN Blue THEN FALSE"]
      Missing  -> ["WHEN Red THEN TRUE", "WHEN Green THEN FALSE"]
      Repeated -> ["WHEN Red THEN TRUE", "WHEN Green THEN FALSE", "WHEN Blue THEN FALSE", "WHEN Red THEN FALSE"]

-- | The CONSIDER as an argument of a call, in the three variants: the arms
-- answer with colours.
considerAsArgument :: Text -> Text -> Text -> Variant -> Text
considerAsArgument scrutinee red green variant =
  "(CONSIDER " <> scrutinee <> " " <> Text.intercalate ", " arms <> ")"
  where
    arm c r = "WHEN " <> c <> " THEN " <> r
    arms = case variant of
      Complete -> [arm "Red" red, arm "Green" green, arm "Blue" green]
      Missing  -> [arm "Red" red, arm "Green" green]
      Repeated -> [arm "Red" red, arm "Green" green, arm "Blue" green, arm "Red" green]

shapes :: [Shape]
shapes =
  [ -- An input named like a field of a record, with a rule over the input.
    -- The house style: a rule's input and a record's field are both `favourite`.
    MkShape "an input named like a record field" []
      \ v -> Text.unlines $
        colour <>
        [ "DECLARE Person HAS"
        , "  favourite IS A Colour"
        , ""
        , "GIVEN favourite IS A Colour"
        , "GIVETH A BOOLEAN"
        , "DECIDE likes favourite IS"
        ] <> consider "favourite" v

  , -- A definition and a field of one name, no input anywhere.
    MkShape "a definition and a record field of one name" []
      \ v -> Text.unlines $
        colour <>
        [ "DECLARE Person HAS fav IS A Colour"
        , ""
        , "GIVETH A Colour"
        , "DECIDE fav IS Red"
        , ""
        , "GIVETH A BOOLEAN"
        , "DECIDE likes IS"
        ] <> consider "fav" v

  , -- The same, the definition coming after its use.
    MkShape "the same, the definition coming after its use" []
      \ v -> Text.unlines $
        colour <>
        [ "DECLARE Person HAS fav IS A Colour"
        , ""
        , "GIVETH A BOOLEAN"
        , "DECIDE likes IS"
        ] <> consider "fav" v <>
        [ ""
        , "GIVETH A Colour"
        , "DECIDE fav IS Red"
        ]

  , -- An imported definition against a field of the importing file.
    MkShape "an imported definition and a record field of one name"
      [("colours", Text.unlines (colour <> ["", "GIVETH A Colour", "DECIDE fav IS Red"]))]
      \ v -> Text.unlines $
        [ "IMPORT colours"
        , ""
        , "DECLARE Person HAS fav IS A Colour"
        , ""
        , "GIVETH A BOOLEAN"
        , "DECIDE likes IS"
        ] <> consider "fav" v

  , -- Two definitions of one name, told apart by their types.
    MkShape "two definitions told apart by their types" []
      \ v -> Text.unlines $
        colour <>
        [ ""
        , "GIVETH A Colour"
        , "DECIDE tone IS Red"
        , ""
        , "GIVETH A NUMBER"
        , "DECIDE tone IS 5"
        , ""
        , "GIVETH A BOOLEAN"
        , "DECIDE likes IS"
        ] <> consider "tone" v

  , -- The same two definitions, each in a section of its own, used from a third.
    MkShape "two definitions in sibling sections" []
      \ v -> Text.unlines $
        colour <>
        [ ""
        , "§ one"
        , "GIVETH A Colour"
        , "DECIDE tone IS Red"
        , ""
        , "§ two"
        , "GIVETH A NUMBER"
        , "DECIDE tone IS 5"
        , ""
        , "§ three"
        , "GIVETH A BOOLEAN"
        , "DECIDE likes IS"
        ] <> consider "tone" v

  , -- A definition and a field of one name, used from inside a section.
    MkShape "a definition and a record field, used in a section" []
      \ v -> Text.unlines $
        colour <>
        [ "DECLARE Person HAS fav IS A Colour"
        , ""
        , "GIVETH A Colour"
        , "DECIDE fav IS Red"
        , ""
        , "§ inner"
        , "GIVETH A BOOLEAN"
        , "DECIDE likes IS"
        ] <> consider "fav" v

  , -- A CONSIDER written in the body of a clause, over a name with two meanings.
    MkShape "a CONSIDER in the body of a clause" []
      \ v -> Text.unlines $
        colour <>
        [ "DECLARE Person HAS fav IS A Colour"
        , ""
        , "GIVETH A Colour"
        , "DECIDE fav IS Red"
        , ""
        , "GIVEN n IS A NUMBER"
        , "GIVETH A BOOLEAN"
        , "DECIDE likes 0 IS"
        ] <> consider "fav" v <>
        [ "DECIDE likes n IS FALSE"
        ]

  , -- An overloaded function applied to two arguments, one of them a CONSIDER.
    MkShape "an overloaded function applied to a CONSIDER" []
      \ v -> Text.unlines $
        colour <>
        [ ""
        , "GIVEN a IS A Colour"
        , "      b IS A Colour"
        , "GIVETH A BOOLEAN"
        , "DECIDE same a b IS a EQUALS b"
        , ""
        , "GIVEN a IS A NUMBER"
        , "      b IS A NUMBER"
        , "GIVETH A BOOLEAN"
        , "DECIDE same a b IS a EQUALS b"
        , ""
        , "GIVEN c IS A Colour"
        , "GIVETH A BOOLEAN"
        , "DECIDE test c IS same " <> considerAsArgument "c" "Red" "Green" v <> " Green"
        ]

  , -- A function named like a record constructor that has one field, a list.
    MkShape "a function named like a record constructor, applied to a CONSIDER" []
      \ v -> Text.unlines $
        colour <>
        [ ""
        , "DECLARE Bag HAS items IS A LIST OF NUMBER"
        , ""
        , "GIVEN a IS A NUMBER"
        , "      b IS A NUMBER"
        , "GIVETH A NUMBER"
        , "DECIDE Bag a b IS a PLUS b"
        , ""
        , "GIVEN c IS A Colour"
        , "GIVETH A NUMBER"
        , "DECIDE test c IS Bag " <> considerAsArgument "c" "1" "2" v <> " 3"
        ]
  ]

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------

-- | The module's error diagnostics and its warnings, each as the text a user
-- reads. Fails the test if the module does not parse or its imports do not
-- resolve.
diagnostics :: VFS -> Text -> IO ([Text], [Text])
diagnostics vfs src =
  case checkWithImports vfs src of
    Left errs -> fail ("import or parse failure: " <> show errs)
    Right r ->
      pure
        ( [ render e | e <- r.tcdErrors, severity e == SError ]
        , [ render e | e <- r.tcdErrors, severity e == SWarn ]
        )

render :: CheckErrorWithContext -> Text
render = Text.unlines . prettyCheckErrorWithContext

mentions :: Text -> Text -> Bool
mentions = Text.isInfixOf
