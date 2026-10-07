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

  it "does not check a group that matches numbers (no finite set of values)" $ do
    ws <- clauseWarnings $ Text.unlines
      [ "GIVEN n IS A NUMBER"
      , "GIVETH A STRING"
      , "DECIDE describe 0 IS \"zero\""
      , "DECIDE describe 1 IS \"one\""
      ]
    ws `shouldBe` []

  it "does not check a group that matches lists" $ do
    ws <- clauseWarnings $ Text.unlines
      [ "GIVEN xs IS A LIST OF BOOLEAN"
      , "GIVETH A NUMBER"
      , "DECIDE h EMPTY IS 0"
      , "DECIDE h (TRUE FOLLOWED BY rest) IS 1"
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

  it "keeps a one-clause group's CONSIDER warning, at the clause, where it cannot check the clause" $ do
    -- The literal stops the clause analysis; the warning for the CONSIDER the
    -- clause is compiled to is kept, moved from no location to the clause.
    allWs <- warnings $ Text.unlines
      [ "DECLARE Colour IS ONE OF Red, Green, Blue"
      , ""
      , "GIVEN c IS A Colour"
      , "      n IS A NUMBER"
      , "GIVETH A NUMBER"
      , "DECIDE f Red 1 IS 1"
      ]
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

  it "does not flag a repeated clause, or a clause after one that binds a new name" $ do
    -- Unstable flags both, from redundant rows its coverage analysis computes
    -- and main's does not; the reference page says so.
    ws <- warnings $ Text.unlines
      [ "DECLARE Colour IS ONE OF Red, Green, Blue"
      , ""
      , "GIVEN c IS A Colour"
      , "GIVETH A NUMBER"
      , "DECIDE r Red   IS 1"
      , "DECIDE r Red   IS 2"
      , "DECIDE r other IS 3"
      , "DECIDE r Blue  IS 4"
      ]
    ws `shouldBe` []

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
