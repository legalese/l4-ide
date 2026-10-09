{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | The compile-time warning for a multi-clause DECIDE group that does not
-- cover every case ('L4.TypeCheck.checkClauseMatrix'). Warnings are matched
-- by severity and rendered text, the way a user meets them.
module PatternClausesMissingSpec (spec) where

import Data.Text (Text)
import qualified Data.Text as Text
import Test.Hspec

import L4.API.VirtualFS (VFS, checkWithImports, emptyVFS, vfsFromList)
import L4.Annotation (HasSrcRange (..))
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.Parser.SrcSpan (SrcPos (..), SrcRange (..))
import L4.TypeCheck (prettyCheckErrorWithContext, severity)
import L4.TypeCheck.Types (CheckErrorWithContext, Severity (..))

spec :: Spec
spec = describe "Multi-clause DECIDE: missing-case warning" $ do
  it "warns when an enumeration value has no clause, naming the missing clause" $ do
    ws <- clauseWarnings $ Text.unlines
      [ "DECLARE Colour IS ONE OF Red, Green, Blue"
      , ""
      , "GIVEN c IS A Colour"
      , "GIVETH A NUMBER"
      , "DECIDE `two clause partial` Red   IS 1"
      , "DECIDE `two clause partial` Green IS 2"
      ]
    map snd ws `shouldBe`
      [ [ "I found a problem while checking the definition of `two clause partial`:"
        , "  This multi-clause definition does not cover all cases. The following clauses are still needed:"
        , "  "
        , "    DECIDE `two clause partial` Blue IS"
        , "  "
        ]
      ]
    -- Anchored at the clause heads: from the first head (line 5, column 8)
    -- to the last head (line 6).
    map fst ws `shouldBe` [Just (5, 8, 6)]

  it "names both columns of the one missing row of a two-input table" $ do
    ws <- clauseWarnings $ Text.unlines
      [ "DECLARE Colour IS ONE OF Red, Green, Blue"
      , ""
      , "GIVEN c IS A Colour"
      , "      b IS A BOOLEAN"
      , "GIVETH A NUMBER"
      , "DECIDE f Red   TRUE  IS 1"
      , "DECIDE f Red   FALSE IS 2"
      , "DECIDE f Green TRUE  IS 3"
      , "DECIDE f Green FALSE IS 4"
      , "DECIDE f Blue  TRUE  IS 5"
      ]
    missingClauses ws `shouldBe` ["DECIDE `f` Blue FALSE IS"]

  it "writes a column that every missing value leaves open as its GIVEN name" $ do
    ws <- clauseWarnings $ Text.unlines
      [ "DECLARE Colour IS ONE OF Red, Green, Blue"
      , ""
      , "GIVEN c IS A Colour"
      , "      b IS A BOOLEAN"
      , "GIVETH A NUMBER"
      , "DECIDE f Red   b IS 1"
      , "DECIDE f Green b IS 2"
      ]
    missingClauses ws `shouldBe` ["DECIDE `f` Blue b IS"]

  it "writes an open column that has no GIVEN name as `_`, not as an internal name" $ do
    ws <- clauseWarnings $ Text.unlines
      [ "DECLARE Colour IS ONE OF Red, Green, Blue"
      , ""
      , "DECIDE f Red   b IS 1"
      , "DECIDE f Green b IS 2"
      ]
    missingClauses ws `shouldBe` ["DECIDE `f` Blue `_` IS"]

  it "parenthesises a missing value that carries a field" $ do
    ws <- clauseWarnings $ Text.unlines
      [ "DECLARE Colour IS ONE OF Red, Green, Blue"
      , "DECLARE Shape IS ONE OF"
      , "  Circle HAS colour IS A Colour"
      , "  Square"
      , ""
      , "GIVEN s IS A Shape"
      , "GIVETH A NUMBER"
      , "DECIDE area (Circle Red)   IS 1"
      , "DECIDE area (Circle Green) IS 2"
      , "DECIDE area Square         IS 3"
      ]
    missingClauses ws `shouldBe` ["DECIDE `area` (Circle Blue) IS"]

  it "does not warn when every enumeration value has a clause" $ do
    ws <- clauseWarnings $ Text.unlines
      [ "DECLARE Peril IS ONE OF Water, Fire, Cosmetic"
      , ""
      , "GIVEN p IS A Peril"
      , "GIVETH A BOOLEAN"
      , "DECIDE covered Water    IS TRUE"
      , "DECIDE covered Fire     IS TRUE"
      , "DECIDE covered Cosmetic IS FALSE"
      ]
    ws `shouldBe` []

  it "does not warn when the group ends with a clause that matches anything" $ do
    ws <- clauseWarnings $ Text.unlines
      [ "DECLARE Peril IS ONE OF Water, Fire, Cosmetic"
      , ""
      , "GIVEN p IS A Peril"
      , "GIVETH A NUMBER"
      , "DECIDE premium Water IS 100"
      , "DECIDE premium Fire  IS 200"
      , "DECIDE premium other IS 0"
      ]
    ws `shouldBe` []

  it "reads a clause that names its column's GIVEN as matching anything, even when a value has that name" $ do
    -- `active` in the first column is the GIVEN, so it matches any number;
    -- resolving it as the Status value `active` would fail and hide the
    -- missing Blue.
    ws <- clauseWarnings $ Text.unlines
      [ "DECLARE Status IS ONE OF active, inactive"
      , "DECLARE Colour IS ONE OF Red, Green, Blue"
      , ""
      , "GIVEN active IS A NUMBER"
      , "      c IS A Colour"
      , "GIVETH A NUMBER"
      , "DECIDE f active Red   IS 1"
      , "DECIDE f active Green IS 2"
      ]
    missingClauses ws `shouldBe` ["DECIDE `f` active Blue IS"]

  it "adds no missing-case warning when a clause reuses a GIVEN name that is also a value of its type" $ do
    -- A clause naming its column's GIVEN matches anything ('patIsColumnWildcard'),
    -- even when that name is also a value of the type: without that, the
    -- second clause is read as the value `active` and `suspended` is
    -- reported missing. (On this tree the module is rejected anyway, with
    -- "There are multiple definitions for the identifier active", so only
    -- the absence of a clause warning is pinned.)
    ws <- filter isClauseWarning . map render <$> diagnostics (Text.unlines
      [ "DECLARE Status IS ONE OF active, inactive, suspended"
      , ""
      , "GIVEN active IS A Status"
      , "GIVETH A NUMBER"
      , "DECIDE f inactive IS 1"
      , "DECIDE f active   IS 2"
      ])
    ws `shouldBe` []

  -- Review of legalese/l4-ide#545, round 2, item 4: a number or a piece of
  -- text in a clause matches one value of its input, and the input has no
  -- end of other values, so a group of such clauses is complete only with a
  -- clause written with the input's name, and the warning suggests it.
  it "suggests the clause with the input's name for a group that matches numbers" $ do
    ws <- clauseWarnings $ Text.unlines
      [ "GIVEN n IS A NUMBER"
      , "GIVETH A STRING"
      , "DECIDE describe 0 IS \"zero\""
      , "DECIDE describe 1 IS \"one\""
      ]
    map snd ws `shouldBe`
      [ [ "I found a problem while checking the definition of `describe`:"
        , "  This multi-clause definition does not cover all cases. The following clauses are still needed:"
        , "  "
        , "    DECIDE `describe` n IS"
        , "  "
        ]
      ]
    map fst ws `shouldBe` [Just (3, 8, 4)]

  it "is silent when a group that matches numbers ends with the input's name" $ do
    ws <- clauseWarnings $ Text.unlines
      [ "GIVEN n IS A NUMBER"
      , "GIVETH A STRING"
      , "DECIDE describe 0 IS \"zero\""
      , "DECIDE describe 1 IS \"one\""
      , "DECIDE describe n IS \"many\""
      ]
    ws `shouldBe` []

  it "suggests the clause with the input's name for a group that matches text, and is silent with it" $ do
    let code cls = Text.unlines $ [ "GIVEN s IS A STRING", "GIVETH A NUMBER" ] <> cls
    partial <- clauseWarnings $ code
      [ "DECIDE code \"red\"   IS 1"
      , "DECIDE code \"green\" IS 2"
      ]
    missingClauses partial `shouldBe` ["DECIDE `code` s IS"]
    total <- clauseWarnings $ code
      [ "DECIDE code \"red\"   IS 1"
      , "DECIDE code \"green\" IS 2"
      , "DECIDE code s         IS 0"
      ]
    total `shouldBe` []

  it "suggests the input's name for a negative number and for a decimal" $ do
    sign <- clauseWarnings $ Text.unlines
      [ "GIVEN n IS A NUMBER"
      , "GIVETH A NUMBER"
      , "DECIDE sign -1 IS 0"
      , "DECIDE sign 0  IS 1"
      ]
    missingClauses sign `shouldBe` ["DECIDE `sign` n IS"]
    half <- clauseWarnings $ Text.unlines
      [ "GIVEN n IS A NUMBER"
      , "GIVETH A NUMBER"
      , "DECIDE half 0.5 IS 0"
      , "DECIDE half 1   IS 1"
      ]
    missingClauses half `shouldBe` ["DECIDE `half` n IS"]

  it "reads EXACTLY of a number as that number" $ do
    let ex cls = Text.unlines $ [ "GIVEN n IS A NUMBER", "GIVETH A STRING" ] <> cls
    partial <- clauseWarnings $ ex
      [ "DECIDE ex (EXACTLY 0) IS \"zero\""
      , "DECIDE ex (EXACTLY 1) IS \"one\""
      ]
    missingClauses partial `shouldBe` ["DECIDE `ex` n IS"]
    total <- clauseWarnings $ ex
      [ "DECIDE ex (EXACTLY 0) IS \"zero\""
      , "DECIDE ex n           IS \"other\""
      ]
    total `shouldBe` []

  it "reads EXACTLY of a value of the input's type as that value" $ do
    ws <- clauseWarnings $ Text.unlines
      [ "DECLARE Colour IS ONE OF Red, Green, Blue"
      , ""
      , "GIVEN c IS A Colour"
      , "GIVETH A NUMBER"
      , "DECIDE price (EXACTLY Red) IS 1"
      , "DECIDE price Green         IS 2"
      ]
    missingClauses ws `shouldBe` ["DECIDE `price` Blue IS"]

  it "stands down for an EXACTLY of a constant on an enumeration input" $ do
    -- The constant is one of three values, and the check cannot tell which:
    -- reading it either way could mis-report, so the group gets no warning.
    ws <- clauseWarnings $ Text.unlines
      [ "DECLARE Colour IS ONE OF Red, Green, Blue"
      , ""
      , "someColour MEANS Red"
      , ""
      , "GIVEN c IS A Colour"
      , "GIVETH A NUMBER"
      , "DECIDE price (EXACTLY someColour) IS 1"
      , "DECIDE price Green               IS 2"
      ]
    ws `shouldBe` []

  it "reads an input declared under another name for a number as a number input" $ do
    let age cls = Text.unlines $
          [ "DECLARE Age IS A NUMBER"
          , ""
          , "zero MEANS 0"
          , ""
          , "GIVEN a IS AN Age"
          , "GIVETH A STRING"
          ] <> cls
    plain <- clauseWarnings $ age
      [ "DECIDE g 0 IS \"zero\""
      , "DECIDE g 1 IS \"one\""
      ]
    missingClauses plain `shouldBe` ["DECIDE `g` a IS"]
    -- An EXACTLY of a constant counts for nothing on it, as on an input
    -- written NUMBER, rather than stopping the group.
    exactly <- clauseWarnings $ age
      [ "DECIDE f (EXACTLY zero) IS \"zero\""
      , "DECIDE f 1              IS \"one\""
      ]
    missingClauses exactly `shouldBe` ["DECIDE `f` a IS"]

  it "leaves out a clause with an EXACTLY of a constant under a record's field" $ do
    -- The field's type is read off the pattern's annotation, resolved
    -- through the substitution of the re-resolution, so the EXACTLY is one
    -- of a number's endless values there, as at the top level: the clause
    -- counts for nothing, and every box is still open for Premium.
    ws <- clauseWarnings $ Text.unlines
      [ "DECLARE Tier IS ONE OF Basic, Premium"
      , "DECLARE Box HAS n IS A NUMBER"
      , ""
      , "zero MEANS 0"
      , ""
      , "GIVEN b IS A Box"
      , "      t IS A Tier"
      , "GIVETH A NUMBER"
      , "DECIDE f (Box (EXACTLY zero)) Premium IS 1"
      , "DECIDE f (Box n)              Basic   IS 2"
      ]
    missingClauses ws `shouldBe` ["DECIDE `f` (Box `_`) Premium IS"]

  it "stands down for EXACTLY over an enumeration declared in another file" $ do
    ws <- filter isClauseWarning <$> warningsWith
      (vfsFromList [("colours", "DECLARE Colour IS ONE OF Red, Green, Blue\n")])
      (Text.unlines
        [ "IMPORT colours"
        , ""
        , "GIVEN c IS A Colour"
        , "GIVETH A NUMBER"
        , "DECIDE price (EXACTLY Red)   IS 1"
        , "DECIDE price (EXACTLY Green) IS 2"
        , "DECIDE price (EXACTLY Blue)  IS 3"
        ])
    ws `shouldBe` []

  it "stands down for EXACTLY over a MAYBE value" $ do
    ws <- clauseWarnings $ Text.unlines
      [ "IMPORT prelude"
      , ""
      , "GIVEN m IS A MAYBE BOOLEAN"
      , "GIVETH A STRING"
      , "DECIDE f (EXACTLY NOTHING)      IS \"none\""
      , "DECIDE f (EXACTLY (JUST TRUE))  IS \"t\""
      , "DECIDE f (EXACTLY (JUST FALSE)) IS \"f\""
      ]
    ws `shouldBe` []

  it "suggests the inputs' names for a table keyed by a number and an enumeration, and is silent with a catch-all per value" $ do
    let charge cls = Text.unlines $
          [ "DECLARE Tier IS ONE OF Basic, Premium"
          , ""
          , "GIVEN level IS A NUMBER"
          , "      tier IS A Tier"
          , "GIVETH A NUMBER"
          ] <> cls
    partial <- clauseWarnings $ charge
      [ "DECIDE charge 1 Basic   IS 10"
      , "DECIDE charge 1 Premium IS 20"
      , "DECIDE charge 2 Basic   IS 30"
      , "DECIDE charge 2 Premium IS 40"
      ]
    missingClauses partial `shouldBe` ["DECIDE `charge` level tier IS"]
    total <- clauseWarnings $ charge
      [ "DECIDE charge 1 Basic       IS 10"
      , "DECIDE charge 1 Premium     IS 20"
      , "DECIDE charge level Basic   IS 30"
      , "DECIDE charge level Premium IS 40"
      ]
    total `shouldBe` []

  it "suggests the inputs' names for a table keyed by text" $ do
    ws <- clauseWarnings $ Text.unlines
      [ "DECLARE Tier IS ONE OF Basic, Premium"
      , ""
      , "GIVEN region IS A STRING"
      , "      tier IS A Tier"
      , "GIVETH A NUMBER"
      , "DECIDE charge \"SG\" Basic   IS 10"
      , "DECIDE charge \"SG\" Premium IS 20"
      , "DECIDE charge \"MY\" Basic   IS 30"
      , "DECIDE charge \"MY\" Premium IS 40"
      ]
    missingClauses ws `shouldBe` ["DECIDE `charge` region tier IS"]

  it "still analyses the enumeration input beside a number: the gap under a key first, then under every other number" $ do
    ws <- clauseWarnings $ Text.unlines
      [ "DECLARE Tier IS ONE OF Basic, Premium, Gold"
      , ""
      , "GIVEN level IS A NUMBER"
      , "      tier IS A Tier"
      , "GIVETH A NUMBER"
      , "DECIDE charge 1 Basic       IS 10"
      , "DECIDE charge level Basic   IS 30"
      , "DECIDE charge level Premium IS 40"
      ]
    missingClauses ws `shouldBe` ["DECIDE `charge` 1 Gold IS", "DECIDE `charge` level Gold IS"]

  it "lists a gap inside the table before the clause for every other number" $ do
    ws <- clauseWarnings $ Text.unlines
      [ "DECLARE Tier IS ONE OF Basic, Premium"
      , ""
      , "GIVEN level IS A NUMBER"
      , "      tier IS A Tier"
      , "GIVETH A NUMBER"
      , "DECIDE charge 1 Basic   IS 10"
      , "DECIDE charge 1 Premium IS 20"
      , "DECIDE charge 2 Basic   IS 30"
      ]
    missingClauses ws `shouldBe` ["DECIDE `charge` 2 Premium IS", "DECIDE `charge` level tier IS"]

  it "analyses the enumeration input of a group with a number in another input" $ do
    -- The reference page's former example of a group that was not checked
    -- because of the number: now the number's clause is read as one value,
    -- the clause below it covers the rest of Red, and Blue is reported.
    ws <- clauseWarnings $ Text.unlines
      [ "DECLARE Colour IS ONE OF Red, Green, Blue"
      , ""
      , "GIVEN c IS A Colour"
      , "      n IS A NUMBER"
      , "GIVETH A NUMBER"
      , "DECIDE charge Red   0 IS 0"
      , "DECIDE charge Red   n IS n"
      , "DECIDE charge Green n IS n TIMES 2"
      ]
    missingClauses ws `shouldBe` ["DECIDE `charge` Blue n IS"]

  it "writes a number input left open as its name beside each missing enumeration value" $ do
    ws <- clauseWarnings $ Text.unlines
      [ "DECLARE Colour IS ONE OF Red, Green, Blue"
      , ""
      , "GIVEN c IS A Colour"
      , "      n IS A NUMBER"
      , "GIVETH A NUMBER"
      , "DECIDE p Red   0 IS 1"
      , "DECIDE p Green n IS 2"
      ]
    missingClauses ws `shouldBe` ["DECIDE `p` Red n IS", "DECIDE `p` Blue n IS"]

  it "writes a text input left open as its name beside a BOOLEAN, and is silent with a catch-all" $ do
    let fee cls = Text.unlines $
          [ "GIVEN weekend IS A BOOLEAN"
          , "      day IS A STRING"
          , "GIVETH A NUMBER"
          ] <> cls
    partial <- clauseWarnings $ fee
      [ "DECIDE fee TRUE  day        IS 0"
      , "DECIDE fee FALSE \"Saturday\" IS 5"
      ]
    missingClauses partial `shouldBe` ["DECIDE `fee` FALSE day IS"]
    total <- clauseWarnings $ fee
      [ "DECIDE fee TRUE  day        IS 0"
      , "DECIDE fee FALSE \"Saturday\" IS 5"
      , "DECIDE fee FALSE day        IS 10"
      ]
    total `shouldBe` []

  it "suggests the inputs' names for two number inputs keyed on the first, and is silent with a catch-all" $ do
    let f cls = Text.unlines $
          [ "GIVEN n IS A NUMBER"
          , "      k IS A NUMBER"
          , "GIVETH A NUMBER"
          ] <> cls
    partial <- clauseWarnings $ f
      [ "DECIDE f 0 k IS 1"
      , "DECIDE f 1 k IS 2"
      ]
    missingClauses partial `shouldBe` ["DECIDE `f` n k IS"]
    total <- clauseWarnings $ f
      [ "DECIDE f 0 k IS 1"
      , "DECIDE f n 0 IS 2"
      , "DECIDE f n k IS 3"
      ]
    total `shouldBe` []

  it "lists the gap under one key of two number inputs, then the rest" $ do
    ws <- clauseWarnings $ Text.unlines
      [ "GIVEN n IS A NUMBER"
      , "      k IS A NUMBER"
      , "GIVETH A NUMBER"
      , "DECIDE f 0 k IS 1"
      , "DECIDE f 1 0 IS 2"
      ]
    missingClauses ws `shouldBe` ["DECIDE `f` 1 k IS", "DECIDE `f` n k IS"]

  it "checks a one-clause group with a number as a clause, and says so" $ do
    allWs <- warnings $ Text.unlines
      [ "GIVEN n IS A NUMBER"
      , "GIVETH A NUMBER"
      , "DECIDE only 0 IS 1"
      ]
    map snd allWs `shouldBe`
      [ [ "I found a problem while checking the definition of `only`:"
        , "  This clause does not cover all cases. The following clauses are still needed:"
        , "  "
        , "    DECIDE `only` n IS"
        , "  "
        ]
      ]
    map fst allWs `shouldBe` [Just (3, 8, 3)]

  it "checks a one-clause group with a number and an enumeration, and withdraws its CONSIDER warning" $ do
    -- One warning, at the clause, in clause terms: the keyed gaps under 1,
    -- then every other number. The CONSIDER the clause is compiled to no
    -- longer reports `WHEN Green THEN` for the second input.
    allWs <- warnings $ Text.unlines
      [ "DECLARE Colour IS ONE OF Red, Green, Blue"
      , ""
      , "GIVEN n IS A NUMBER"
      , "      c IS A Colour"
      , "GIVETH A NUMBER"
      , "DECIDE f 1 Red IS 1"
      ]
    map snd allWs `shouldBe`
      [ [ "I found a problem while checking the definition of `f`:"
        , "  This clause does not cover all cases. The following clauses are still needed:"
        , "  "
        , "    DECIDE `f` 1 Green IS"
        , "    DECIDE `f` 1 Blue IS"
        , "    DECIDE `f` n c IS"
        , "  "
        ]
      ]
    map fst allWs `shouldBe` [Just (6, 8, 6)]

  it "keeps a one-clause group's CONSIDER warning, at the clause, where it cannot check the clause" $ do
    -- The MAYBE value stops the clause analysis (main's constructor lookup
    -- does not know MAYBE's values); the warning for the CONSIDER the clause
    -- is compiled to is kept, moved from no location to the clause.
    allWs <- filter (\ w -> mentions "still need to be considered" w || isClauseWarning w) <$> warnings (Text.unlines
      [ "DECLARE Colour IS ONE OF Red, Green, Blue"
      , ""
      , "GIVEN c IS A Colour"
      , "      m IS A MAYBE NUMBER"
      , "GIVETH A NUMBER"
      , "DECIDE f Red (JUST x) IS x"
      ])
    allWs `shouldBe`
      [ ( Just (6, 8, 6)
        , [ "I found a problem while checking the definition of `f`:"
          , "  The following branches still need to be considered:"
          , "  "
          , "    WHEN Green THEN"
          , "    WHEN Blue THEN"
          , "  "
          ]
        )
      ]

  it "lists a record whose number field is left open with `_` in its place, and is silent with a name there" $ do
    let f cls = Text.unlines $
          [ "DECLARE Box HAS n IS A NUMBER"
          , ""
          , "GIVEN b IS A Box"
          , "GIVETH A STRING"
          ] <> cls
    partial <- clauseWarnings $ f
      [ "DECIDE f (Box 0) IS \"zero\""
      , "DECIDE f (Box 1) IS \"one\""
      ]
    missingClauses partial `shouldBe` ["DECIDE `f` (Box `_`) IS"]
    total <- clauseWarnings $ f
      [ "DECIDE f (Box 0) IS \"zero\""
      , "DECIDE f (Box m) IS \"other\""
      ]
    total `shouldBe` []

  it "does not check a group that matches lists" $ do
    ws <- clauseWarnings $ Text.unlines
      [ "GIVEN xs IS A LIST OF BOOLEAN"
      , "GIVETH A NUMBER"
      , "DECIDE h EMPTY IS 0"
      , "DECIDE h (TRUE FOLLOWED BY rest) IS 1"
      ]
    ws `shouldBe` []

  it "does not check a group that matches lists, even with a number at the head" $ do
    ws <- clauseWarnings $ Text.unlines
      [ "GIVEN xs IS A LIST OF NUMBER"
      , "GIVETH A NUMBER"
      , "DECIDE t EMPTY IS 0"
      , "DECIDE t (0 FOLLOWED BY rest) IS 1"
      ]
    ws `shouldBe` []

  it "does not check a group that matches MAYBE values" $ do
    ws <- clauseWarnings $ Text.unlines
      [ "IMPORT prelude"
      , ""
      , "GIVEN m IS A MAYBE BOOLEAN"
      , "GIVETH A NUMBER"
      , "DECIDE g NOTHING IS 0"
      , "DECIDE g (JUST TRUE) IS 1"
      ]
    ws `shouldBe` []

  it "does not check a group that matches MAYBE values, even with a number inside" $ do
    ws <- clauseWarnings $ Text.unlines
      [ "IMPORT prelude"
      , ""
      , "GIVEN m IS A MAYBE NUMBER"
      , "GIVETH A STRING"
      , "DECIDE show NOTHING  IS \"none\""
      , "DECIDE show (JUST 0) IS \"zero\""
      ]
    ws `shouldBe` []

  it "suggests the one clause with every input's name where every clause has a number inside a MAYBE" $ do
    -- The exact analysis cannot read JUST; the coarse tier, over the
    -- clauses without a number, has no clause left, so everything is open:
    -- one row, the input's name. Unstable lists NOTHING and (JUST `_`).
    ws <- clauseWarnings $ Text.unlines
      [ "IMPORT prelude"
      , ""
      , "GIVEN m IS A MAYBE NUMBER"
      , "GIVETH A STRING"
      , "DECIDE f (JUST 0) IS \"zero\""
      ]
    missingClauses ws `shouldBe` ["DECIDE `f` m IS"]

  it "answers complete where the exact analysis cannot read a MAYBE below a number" $ do
    -- Under the key 0 the row `f n m` has only wildcards left, which ends
    -- the search before the JUST is read, so the exact tier answers.
    ws <- clauseWarnings $ Text.unlines
      [ "IMPORT prelude"
      , ""
      , "GIVEN n IS A NUMBER"
      , "      m IS A MAYBE NUMBER"
      , "GIVETH A NUMBER"
      , "DECIDE f 0 (JUST x) IS x"
      , "DECIDE f n m        IS 0"
      ]
    ws `shouldBe` []

  it "falls back to the clauses without a number where the exact analysis meets a MAYBE below a key" $ do
    -- Under the key 0 the exact tier meets JUST, which it cannot
    -- enumerate, and no row of wildcards ends the search first; the coarse
    -- tier has no clause without a number, so everything is open.
    ws <- clauseWarnings $ Text.unlines
      [ "IMPORT prelude"
      , ""
      , "GIVEN n IS A NUMBER"
      , "      m IS A MAYBE NUMBER"
      , "GIVETH A NUMBER"
      , "DECIDE f 0 (JUST x) IS x"
      , "DECIDE f 1 m        IS 0"
      ]
    missingClauses ws `shouldBe` ["DECIDE `f` n m IS"]

  it "does not check a group over an enumeration declared in another file" $ do
    ws <- filter isClauseWarning <$> warningsWith
      (vfsFromList [("colours", "DECLARE Colour IS ONE OF Red, Green, Blue\n")])
      (Text.unlines
        [ "IMPORT colours"
        , ""
        , "GIVEN c IS A Colour"
        , "GIVETH A NUMBER"
        , "DECIDE price Red   IS 1"
        , "DECIDE price Green IS 2"
        ])
    ws `shouldBe` []

  it "still finds a gap beside a list, a MAYBE value or another file's enumeration where it need not tell them apart" $ do
    -- The check cannot tell such values apart, so it gives up only where a
    -- missing case could be found no other way; here the other input
    -- settles the question before any such value is read.
    list <- clauseWarnings $ Text.unlines
      [ "DECLARE Colour IS ONE OF Red, Green, Blue"
      , ""
      , "GIVEN c IS A Colour"
      , "      xs IS A LIST OF NUMBER"
      , "GIVETH A NUMBER"
      , "DECIDE t Red   EMPTY IS 0"
      , "DECIDE t Red   xs    IS 1"
      , "DECIDE t Green xs    IS 2"
      ]
    missingClauses list `shouldBe` ["DECIDE `t` Blue xs IS"]
    -- A MAYBE value in a clause with a number: that clause is left out, and
    -- the ones without a number leave Red and Blue open.
    maybeKeyed <- clauseWarnings $ Text.unlines
      [ "IMPORT prelude"
      , ""
      , "DECLARE Colour IS ONE OF Red, Green, Blue"
      , ""
      , "GIVEN c IS A Colour"
      , "      m IS A MAYBE NUMBER"
      , "GIVETH A NUMBER"
      , "DECIDE f Red   (JUST 0) IS 0"
      , "DECIDE f Green m        IS 1"
      ]
    missingClauses maybeKeyed `shouldBe` ["DECIDE `f` Red m IS", "DECIDE `f` Blue m IS"]
    imported <- filter isClauseWarning <$> warningsWith
      (vfsFromList [("colours", "DECLARE Colour IS ONE OF Red, Green, Blue\n")])
      (Text.unlines
        [ "IMPORT colours"
        , ""
        , "DECLARE Tier IS ONE OF Basic, Premium, Gold"
        , ""
        , "GIVEN t IS A Tier"
        , "      c IS A Colour"
        , "GIVETH A NUMBER"
        , "DECIDE f Basic   Red IS 0"
        , "DECIDE f Basic   c   IS 1"
        , "DECIDE f Premium c   IS 2"
        ])
    missingClauses imported `shouldBe` ["DECIDE `f` Gold c IS"]

  it "does not flag a repeated number, nor 1 after 1.0" $ do
    -- Unstable flags these as never used, from redundant rows its coverage
    -- analysis computes and main's does not (ruling M1's condition); the
    -- reference page says so. `1` and `1.0` are one number, and so are
    -- `0.10` and `0.1`, so nothing is missing either.
    h <- warnings $ Text.unlines
      [ "GIVEN n IS A NUMBER"
      , "GIVETH A STRING"
      , "DECIDE h 1    IS \"one\""
      , "DECIDE h 1.0  IS \"one point zero\""
      , "DECIDE h 0.10 IS \"tenth\""
      , "DECIDE h 0.1  IS \"tenth again\""
      , "DECIDE h n    IS \"other\""
      ]
    h `shouldBe` []
    g <- warnings $ Text.unlines
      [ "GIVEN n IS A NUMBER"
      , "GIVETH A STRING"
      , "DECIDE g 0 IS \"zero\""
      , "DECIDE g 0 IS \"zero again\""
      , "DECIDE g n IS \"other\""
      ]
    g `shouldBe` []

  it "names a key by the first spelling the clauses give it" $ do
    ws <- clauseWarnings $ Text.unlines
      [ "DECLARE Tier IS ONE OF Basic, Premium, Gold"
      , ""
      , "GIVEN n IS A NUMBER"
      , "      t IS A Tier"
      , "GIVETH A NUMBER"
      , "DECIDE f 1   Basic   IS 1"
      , "DECIDE f 1.0 Premium IS 2"
      ]
    missingClauses ws `shouldBe` ["DECIDE `f` 1 Gold IS", "DECIDE `f` n t IS"]

  it "names a number with every digit the clause gives it, as the clause spelled it" $ do
    -- Not rounded through a double, which would print 0.12345678901234568;
    -- and as written, so `1.50` stays `1.50`, a negative number keeps its
    -- sign, and a number under EXACTLY prints as the number alone.
    let long cls = Text.unlines $
          [ "DECLARE Tier IS ONE OF Basic, Premium"
          , ""
          , "GIVEN n IS A NUMBER"
          , "      t IS A Tier"
          , "GIVETH A NUMBER"
          ] <> cls
    alone <- clauseWarnings $ long [ "DECIDE f 0.1234567890123456789 Basic IS 1" ]
    missingClauses alone `shouldBe` ["DECIDE `f` 0.1234567890123456789 Premium IS", "DECIDE `f` n t IS"]
    withRest <- clauseWarnings $ long
      [ "DECIDE f 0.1234567890123456789 Basic IS 1"
      , "DECIDE f n Premium IS 2"
      ]
    missingClauses withRest `shouldBe` ["DECIDE `f` n Basic IS"]
    spelled <- clauseWarnings $ long [ "DECIDE f 1.50 Basic IS 1" ]
    missingClauses spelled `shouldBe` ["DECIDE `f` 1.50 Premium IS", "DECIDE `f` n t IS"]
    negative <- clauseWarnings $ long [ "DECIDE f -1 Basic IS 1" ]
    missingClauses negative `shouldBe` ["DECIDE `f` -1 Premium IS", "DECIDE `f` n t IS"]
    exactly <- clauseWarnings $ long
      [ "DECIDE f (EXACTLY 1.50)  Basic IS 1"
      , "DECIDE f (EXACTLY -0.10) Basic IS 2"
      ]
    missingClauses exactly `shouldBe` ["DECIDE `f` 1.50 Premium IS", "DECIDE `f` -0.10 Premium IS", "DECIDE `f` n t IS"]

  it "writes a text key as L4 writes it, every printable character as it is" $ do
    -- Not with the lexer token's Haskell-style escapes, which would write
    -- "S\227o Paulo"; those are kept only for a character that does not
    -- print, such as a tab. Every form pastes back.
    ws <- clauseWarnings $ Text.unlines
      [ "DECLARE Tier IS ONE OF Basic, Premium"
      , ""
      , "GIVEN city IS A STRING"
      , "      t IS A Tier"
      , "GIVETH A NUMBER"
      , "DECIDE f \"S\227o Paulo\"  Basic IS 1"
      , "DECIDE f \"\1513\1500\1493\1501\"        Basic IS 2"
      , "DECIDE f \"a\\\"b\\\\c\"     Basic IS 3"
      , "DECIDE f \"tab\\there\"    Basic IS 4"
      ]
    missingClauses ws `shouldBe`
      [ "DECIDE `f` \"S\227o Paulo\" Premium IS"
      , "DECIDE `f` \"\1513\1500\1493\1501\" Premium IS"
      , "DECIDE `f` \"a\\\"b\\\\c\" Premium IS"
      , "DECIDE `f` \"tab\\there\" Premium IS"
      , "DECIDE `f` city t IS"
      ]

  it "reads EXACTLY of the input's own name as matching every input" $ do
    total <- warnings $ Text.unlines
      [ "GIVEN n IS A NUMBER"
      , "GIVETH A STRING"
      , "DECIDE f 0           IS \"zero\""
      , "DECIDE f (EXACTLY n) IS \"self\""
      ]
    total `shouldBe` []
    -- A clause after it is never used; unstable says so, from the redundant
    -- rows its analysis computes, and main does not (ruling M1's condition).
    dead <- warnings $ Text.unlines
      [ "GIVEN n IS A NUMBER"
      , "GIVETH A STRING"
      , "DECIDE f 0           IS \"zero\""
      , "DECIDE f (EXACTLY n) IS \"self\""
      , "DECIDE f 1           IS \"one\""
      ]
    dead `shouldBe` []

  it "reads EXACTLY of the input's own name as matching every input beside an enumeration" $ do
    -- Read as a clause that counts for nothing instead, only the keyed
    -- clause would be left and the warning would suggest the one clause
    -- with both inputs' names.
    ws <- clauseWarnings $ Text.unlines
      [ "DECLARE Colour IS ONE OF Red, Green, Blue"
      , ""
      , "GIVEN n IS A NUMBER"
      , "      c IS A Colour"
      , "GIVETH A NUMBER"
      , "DECIDE f 0           Red   IS 1"
      , "DECIDE f (EXACTLY n) Green IS 2"
      ]
    missingClauses ws `shouldBe` ["DECIDE `f` 0 Blue IS", "DECIDE `f` n Red IS", "DECIDE `f` n Blue IS"]

  it "leaves out a clause with EXACTLY of a constant on a number input, which only the input's name can cover" $ do
    ws <- clauseWarnings $ Text.unlines
      [ "DECLARE Tier IS ONE OF Basic, Premium"
      , ""
      , "zero MEANS 0"
      , ""
      , "GIVEN n IS A NUMBER"
      , "      t IS A Tier"
      , "GIVETH A NUMBER"
      , "DECIDE f (EXACTLY zero) Basic   IS 1"
      , "DECIDE f n              Premium IS 2"
      ]
    missingClauses ws `shouldBe` ["DECIDE `f` n Basic IS"]

  it "suggests the input's name where every clause is EXACTLY of a constant" $ do
    ws <- clauseWarnings $ Text.unlines
      [ "zero MEANS 0"
      , "one MEANS 1"
      , ""
      , "GIVEN n IS A NUMBER"
      , "GIVETH A NUMBER"
      , "DECIDE f (EXACTLY zero) IS 1"
      , "DECIDE f (EXACTLY one)  IS 2"
      ]
    missingClauses ws `shouldBe` ["DECIDE `f` n IS"]

  it "stands down for an EXACTLY whose expression mentions the input itself, and not for one that mentions another input" $ do
    -- `n PLUS 0` is every number, so the group is complete and a clause
    -- suggested for every other number would never be used; `n TIMES 0` is
    -- only 0. Neither reading of such a clause is safe, so the check gives
    -- up on the group.
    ws <- warnings $ Text.unlines
      [ "GIVEN n IS A NUMBER"
      , "GIVETH A STRING"
      , "DECIDE f (EXACTLY (n PLUS 0)) IS \"any\""
      , "DECIDE f 0                    IS \"zero\""
      ]
    ws `shouldBe` []
    -- `m PLUS 1` is one value of n for each m, so that clause counts for
    -- nothing and the rest of the numbers are still open: `f 5 0` has no
    -- clause.
    other <- clauseWarnings $ Text.unlines
      [ "GIVEN n IS A NUMBER"
      , "      m IS A NUMBER"
      , "GIVETH A STRING"
      , "DECIDE f (EXACTLY (m PLUS 1)) m IS \"next\""
      , "DECIDE f 0                    m IS \"zero\""
      ]
    missingClauses other `shouldBe` ["DECIDE `f` n m IS"]

  it "suggests the clause with both inputs' names for a cross table of a hundred keys" $ do
    let tshow = Text.pack . show
        cross = Text.unlines $
          [ "GIVEN n IS A NUMBER"
          , "      k IS A NUMBER"
          , "GIVETH A NUMBER"
          ]
          <> [ "DECIDE f " <> tshow i <> " k IS " <> tshow i | i <- [1 .. 100 :: Int] ]
          <> [ "DECIDE f n " <> tshow j <> " IS " <> tshow j | j <- [1 .. 100 :: Int] ]
    ws <- clauseWarnings cross
    missingClauses ws `shouldBe` ["DECIDE `f` n k IS"]

  it "lists sixty-three keyed gaps, and for sixty-four keys only the clause for every other number" $ do
    -- Sixty-four keys and the clause for the rest would be sixty-five
    -- clauses, over the cap; the warning then lists what the clauses
    -- without a number leave open, which here is everything.
    let tshow = Text.pack . show
        keyed :: Int -> Text
        keyed k = Text.unlines $
          [ "DECLARE Tier IS ONE OF Basic, Premium"
          , ""
          , "GIVEN n IS A NUMBER"
          , "      t IS A Tier"
          , "GIVETH A NUMBER"
          ]
          <> [ "DECIDE f " <> tshow i <> " Basic IS " <> tshow i | i <- [1 .. k] ]
    sixtyThree <- clauseWarnings (keyed 63)
    missingClauses sixtyThree `shouldBe`
      [ "DECIDE `f` " <> tshow i <> " Premium IS" | i <- [1 .. 63 :: Int] ] <> ["DECIDE `f` n t IS"]
    sixtyFour <- clauseWarnings (keyed 64)
    missingClauses sixtyFour `shouldBe` ["DECIDE `f` n t IS"]

  it "still lists sixty-four missing enumeration values, and none for sixty-five" $ do
    -- The enumeration control: no number, so no coarse tier to fall back
    -- on, and the cap silences the group as before.
    let tshow = Text.pack . show
        big :: Int -> Text
        big k = Text.unlines $
          [ "DECLARE Big IS ONE OF " <> Text.intercalate ", " [ "E" <> tshow i | i <- [1 .. k] ]
          , "DECLARE Tier IS ONE OF Basic, Premium"
          , ""
          , "GIVEN e IS A Big"
          , "      t IS A Tier"
          , "GIVETH A NUMBER"
          ]
          <> [ "DECIDE f E" <> tshow i <> " Basic IS " <> tshow i | i <- [1 .. k] ]
    sixtyFour <- clauseWarnings (big 64)
    missingClauses sixtyFour `shouldBe` [ "DECIDE `f` E" <> tshow i <> " Premium IS" | i <- [1 .. 64 :: Int] ]
    sixtyFive <- clauseWarnings (big 65)
    sixtyFive `shouldBe` []

  it "stays silent rather than list more than 64 missing clauses" $ do
    ws <- clauseWarnings $ Text.unlines
      [ "DECLARE Alpha IS ONE OF A1, A2, A3, A4, A5, A6, A7, A8, A9"
      , "DECLARE Beta  IS ONE OF B1, B2, B3, B4, B5, B6, B7, B8, B9"
      , ""
      , "GIVEN a IS AN Alpha"
      , "      b IS A Beta"
      , "GIVETH A NUMBER"
      , "DECIDE g A1 B1 IS 1"
      , "DECIDE g A2 B1 IS 2"
      , "DECIDE g A3 B1 IS 3"
      , "DECIDE g A4 B1 IS 4"
      , "DECIDE g A5 B1 IS 5"
      , "DECIDE g A6 B1 IS 6"
      , "DECIDE g A7 B1 IS 7"
      , "DECIDE g A8 B1 IS 8"
      , "DECIDE g A9 B1 IS 9"
      ]
    ws `shouldBe` []

  it "finds the one clause missing from a group keyed on each enumeration input in turn, however many inputs" $ do
    -- k inputs, each tested for Red in one clause and for Green in another:
    -- the one clause missing is all Blue. Under each key the clause that
    -- tested it has only its inputs' names left, which match everything, so
    -- the search ends there and grows with the inputs, not with their
    -- powers: nine inputs used to run out of steps, and now do not.
    let tshow = Text.pack . show
        pick :: Int -> Text
        pick k = Text.unlines $
          [ "DECLARE Colour IS ONE OF Red, Green, Blue", "" ]
          <> [ (if i == 1 then "GIVEN " else "      ") <> "c" <> tshow i <> " IS A Colour" | i <- [1 .. k] ]
          <> [ "GIVETH A NUMBER" ]
          <> [ "DECIDE pick "
                 <> Text.unwords [ if j == i then v else "c" <> tshow j | j <- [1 .. k] ]
                 <> " IS " <> tshow i
             | v <- ["Red", "Green"], i <- [1 .. k] ]
    eight <- clauseWarnings (pick 8)
    missingClauses eight `shouldBe` ["DECIDE `pick` " <> Text.unwords (replicate 8 "Blue") <> " IS"]
    nine <- clauseWarnings (pick 9)
    missingClauses nine `shouldBe` ["DECIDE `pick` " <> Text.unwords (replicate 9 "Blue") <> " IS"]

  it "suggests the one clause with every input's name for a group keyed on each number input in turn" $ do
    -- The same table over numbers: under each key the rest is covered, and
    -- the clause for every other number of every input is the one missing.
    let tshow = Text.pack . show
        pick :: Int -> Text
        pick k = Text.unlines $
          [ (if i == 1 then "GIVEN " else "      ") <> "n" <> tshow i <> " IS A NUMBER" | i <- [1 .. k] ]
          <> [ "GIVETH A NUMBER" ]
          <> [ "DECIDE pick "
                 <> Text.unwords [ if j == i then v else "n" <> tshow j | j <- [1 .. k] ]
                 <> " IS " <> tshow i
             | v <- ["0", "1"], i <- [1 .. k] ]
    eight <- clauseWarnings (pick 8)
    missingClauses eight `shouldBe` ["DECIDE `pick` " <> Text.unwords [ "n" <> tshow i | i <- [1 .. 8 :: Int] ] <> " IS"]
    nine <- clauseWarnings (pick 9)
    missingClauses nine `shouldBe` ["DECIDE `pick` " <> Text.unwords [ "n" <> tshow i | i <- [1 .. 9 :: Int] ] <> " IS"]

  it "writes an open column that has no GIVEN as `_` for a one-clause group with a number" $ do
    ws <- clauseWarnings $ Text.unlines
      [ "DECIDE describe 0 IS \"zero\""
      ]
    missingClauses ws `shouldBe` ["DECIDE `describe` `_` IS"]

  it "checks a one-clause group as a clause, and says so" $ do
    allWs <- warnings $ Text.unlines
      [ "DECLARE Colour IS ONE OF Red, Green, Blue"
      , ""
      , "DECLARE Shape IS ONE OF"
      , "  Circle HAS colour IS A Colour"
      , "  Square"
      , ""
      , "GIVEN s IS A Shape"
      , "GIVETH A NUMBER"
      , "DECIDE area (Circle Red) IS 1"
      ]
    -- One warning, at the clause, in clause terms; the CONSIDER it is
    -- compiled to does not warn as well.
    map snd allWs `shouldBe`
      [ [ "I found a problem while checking the definition of `area`:"
        , "  This clause does not cover all cases. The following clauses are still needed:"
        , "  "
        , "    DECIDE `area` (Circle Green) IS"
        , "    DECIDE `area` (Circle Blue) IS"
        , "    DECIDE `area` Square IS"
        , "  "
        ]
      ]
    map fst allWs `shouldBe` [Just (9, 8, 9)]

  it "warns once about the clauses after a clause that matches every input" $ do
    ws <- filter (mentions "is never used") <$> warnings (Text.unlines
      [ "DECLARE Colour IS ONE OF Red, Green, Blue"
      , ""
      , "GIVEN c IS A Colour"
      , "GIVETH A NUMBER"
      , "DECIDE `matches anything first` c     IS 0"
      , "DECIDE `matches anything first` Red   IS 1"
      , "DECIDE `matches anything first` Green IS 2"
      ])
    ws `shouldBe`
      [ ( Just (6, 8, 6)
        , [ "I found a problem while checking the definition of `matches anything first`:"
          , "  This clause of `matches anything first` is never used, and neither is the clause after it."
          , "  The clause above it matches every input, so `matches anything first` never gets this far."
          , "  Move these clauses above that one, or remove them."
          ]
        )
      ]

  it "type-checks the clauses after a clause that matches every input" $ do
    ds <- diagnostics $ Text.unlines
      [ "GIVEN n IS A NUMBER"
      , "GIVETH A NUMBER"
      , "DECIDE f n IS 7"
      , "DECIDE f 0 IS \"oops\" PLUS TRUE"
      ]
    -- Before, the second clause was dropped unchecked and the module checked
    -- clean; now its type errors are reported, at its body.
    [ r | e <- ds, severity e == SError, Just r <- [fst (render e)] ] `shouldSatisfy` all (\ (l, _, _) -> l == 4)
    length [ () | e <- ds, severity e == SError ] `shouldSatisfy` (> 0)

  it "does not flag a repeated clause" $ do
    -- Unstable flags it, from redundant rows its coverage analysis computes
    -- and main's does not; the reference page says so.
    ws <- warnings $ Text.unlines
      [ "DECLARE Colour IS ONE OF Red, Green, Blue"
      , ""
      , "GIVEN c IS A Colour"
      , "GIVETH A NUMBER"
      , "DECIDE r Red   IS 1"
      , "DECIDE r Red   IS 2"
      , "DECIDE r Green IS 3"
      , "DECIDE r Blue  IS 4"
      ]
    ws `shouldBe` []

  -- Review of legalese/l4-ide#545, round 2, item 3: a new name, such as a
  -- misspelt value, matches every input, so the clauses after it are never
  -- used, and the warning says which name it is.
  it "warns once about the clauses after a clause whose pattern is a new name, naming it" $ do
    ws <- filter (mentions "never used") <$> warnings (Text.unlines
      [ "DECLARE Colour IS ONE OF Red, Green, Blue"
      , ""
      , "GIVEN c IS A Colour"
      , "      n IS A NUMBER"
      , "GIVETH A NUMBER"
      , "DECIDE price Green n IS 1"
      , "DECIDE price Gren  n IS 2"
      , "DECIDE price Red   n IS 3"
      , "DECIDE price Blue  n IS 4"
      ])
    map fst ws `shouldBe` [Just (8, 8, 8)]
    map Text.strip (concatMap snd ws) `shouldBe`
      [ "I found a problem while checking the definition of `price`:"
      , "This clause of `price` is never used, and neither is the clause after it, because the clause above it with the new name `Gren` matches every input."
      , "`Gren` is not a value of its input's type, so it is a new name, and a new name matches anything."
      , "If you meant a value, correct the spelling; if you meant to match anything, move that clause below the others."
      ]

  it "warns about the clauses after a new name in a group that matches numbers, and about nothing missing" $ do
    ws <- warnings $ Text.unlines
      [ "GIVEN n IS A NUMBER"
      , "GIVETH A NUMBER"
      , "DECIDE size 0     IS 1"
      , "DECIDE size other IS 2"
      , "DECIDE size 1     IS 3"
      ]
    map fst (filter (mentions "never used") ws) `shouldBe` [Just (5, 8, 5)]
    filter isClauseWarning ws `shouldBe` []

  it "still warns about a CONSIDER written inside a later clause" $ do
    ws <- filter (mentions "still need to be considered") <$> warnings (Text.unlines
      [ "DECLARE Colour IS ONE OF Red, Green, Blue"
      , ""
      , "GIVEN c IS A Colour"
      , "GIVETH A NUMBER"
      , "DECIDE k Red   IS 1"
      , "DECIDE k Green IS"
      , "  CONSIDER c"
      , "  WHEN Red THEN 2"
      , "DECIDE k Blue  IS 3"
      ])
    map fst ws `shouldBe` [Just (7, 3, 8)]

  it "still warns about a CONSIDER in a definition whose name looks generated" $ do
    ws <- filter (mentions "still need to be considered") <$> warnings (Text.unlines
      [ "DECLARE Colour IS ONE OF Red, Green, Blue"
      , ""
      , "GIVEN c IS A Colour"
      , "GIVETH A NUMBER"
      , "`__pm_fallthrough_0` c MEANS"
      , "  CONSIDER c"
      , "  WHEN Red THEN 1"
      ])
    map fst ws `shouldBe` [Just (6, 3, 7)]

  it "does not report the compiled form of a clause that binds a new name as redundant" $ do
    ws <- warnings $ Text.unlines
      [ "DECLARE Colour IS ONE OF Red, Green, Blue"
      , ""
      , "DECIDE f Red   b IS 1"
      , "DECIDE f Green b IS 2"
      ]
    filter (mentions "redundant") ws `shouldBe` []

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------

-- | Every warning of a module, as (range, rendered lines), the range as
-- (start line, start column, end line). Fails the test on an error, so a
-- typo in a source above cannot pass as "no warning".
warnings :: Text -> IO [(Maybe (Int, Int, Int), [Text])]
warnings = warningsWith emptyVFS

warningsWith :: VFS -> Text -> IO [(Maybe (Int, Int, Int), [Text])]
warningsWith vfs src = do
  ds <- diagnosticsWith vfs src
  let errs = [ e | e <- ds, severity e == SError ]
  case errs of
    [] -> pure [ render e | e <- ds, severity e == SWarn ]
    _ -> fail ("type errors: " <> show (map render errs))

-- | Every diagnostic of a module; fails the test if it does not parse.
diagnostics :: Text -> IO [CheckErrorWithContext]
diagnostics = diagnosticsWith emptyVFS

diagnosticsWith :: VFS -> Text -> IO [CheckErrorWithContext]
diagnosticsWith vfs src =
  case checkWithImports vfs src of
    Left errs -> fail ("import or parse failure: " <> show errs)
    Right r -> pure r.tcdErrors

render :: CheckErrorWithContext -> (Maybe (Int, Int, Int), [Text])
render e =
  ( fmap (\ r -> (r.start.line, r.start.column, r.end.line)) (rangeOf e)
  , prettyCheckErrorWithContext e
  )

-- | The warnings about a clause group's missing cases.
clauseWarnings :: Text -> IO [(Maybe (Int, Int, Int), [Text])]
clauseWarnings src = filter isClauseWarning <$> warnings src

isClauseWarning :: (Maybe (Int, Int, Int), [Text]) -> Bool
isClauseWarning = any ("does not cover all cases" `Text.isInfixOf`) . snd

mentions :: Text -> (Maybe (Int, Int, Int), [Text]) -> Bool
mentions t = any (t `Text.isInfixOf`) . snd

-- | The suggested clauses of the clause-group warnings, trimmed.
missingClauses :: [(Maybe (Int, Int, Int), [Text])] -> [Text]
missingClauses ws =
  [ Text.strip l | (_, ls) <- ws, l <- ls, "DECIDE " `Text.isPrefixOf` Text.strip l ]
