module SearchPatternSpec (spec) where

import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import FileBrowser (SearchMatch (..), searchIdentifier, searchText)
import SearchPattern
import Test.Hspec

-- | Does the query find the line?
finds :: Text -> Text -> Bool
finds query = matchesAny (compilePatterns query)

spec :: Spec
spec = describe "search_text patterns" do
  it "splits on spaces outside groups, classes, backticks and quotes" do
    splitPatterns "sum  max\tmin" `shouldBe` ["sum", "max", "min"]
    splitPatterns "^(GIVEN|DECIDE|@export)?.*(sum|max|min|map|`greater of`|maximum|minimum|fold)"
      `shouldBe` ["^(GIVEN|DECIDE|@export)?.*(sum|max|min|map|`greater of`|maximum|minimum|fold)"]
    splitPatterns "`the greater of` b" `shouldBe` ["`the greater of`", "b"]
    splitPatterns "[ (] x{1, 2} y" `shouldBe` ["[ (]", "x{1, 2}", "y"]
    splitPatterns "\"net income\" tax" `shouldBe` ["net income", "tax"]
    splitPatterns "a\\ b \\( c" `shouldBe` ["a\\ b", "\\(", "c"]
    splitPatterns "   " `shouldBe` []

  it "matches a regex with spaces in a group, case-insensitively" do
    let q = "^(GIVEN|DECIDE|@export)?.*(sum|max|min|map|`the greater of`|maximum|minimum|fold)"
    finds q "DECIDE `the greater of` a AND b" `shouldBe` True
    finds q "total MEANS SUM OF prices" `shouldBe` True
    finds q "GIVEN x IS A NUMBER" `shouldBe` False

  it "reads Perl classes, non-capturing groups and lazy quantifiers" do
    toPosix "a\\sb\\d[\\w-]" `shouldBe` "a[[:space:]]b[0-9][[:alnum:]_-]"
    toPosix "(?:a|b)x*?y+?" `shouldBe` "(a|b)x*y+"
    finds "net\\sincome" "NET income" `shouldBe` True
    finds "\\d{4}" "in 2024" `shouldBe` True
    finds "\\bsum\\b" "the sum of" `shouldBe` True
    finds "\\bsum\\b" "summary" `shouldBe` False
    finds "(?:sum|total).*?of" "total of" `shouldBe` True

  it "matches an invalid regex as plain text, and says so" do
    let pats = compilePatterns "f(x"
    finds "f(x" "call f(x)" `shouldBe` True
    finds "f(x" "fx" `shouldBe` False
    fmap (Text.isPrefixOf "Note: \"f(x\" is not a valid regular expression (unexpected end of input")
      (invalidPatternNote pats) `shouldBe` Just True
    invalidPatternNote (compilePatterns "fine") `shouldBe` Nothing

  it "a blank query finds nothing" do
    null (compilePatterns "") `shouldBe` True
    null (searchText "  " (Map.fromList [("a.l4", "anything\n")])) `shouldBe` True

  it "explains the syntax when nothing matched" do
    noMatchHint "drop `file`" `shouldSatisfy` Text.isPrefixOf "No matches. Each space-separated pattern"
    noMatchHint "drop `file`" `shouldSatisfy` Text.isSuffixOf "or drop `file`."

  it "searchText returns the matching lines of each file" do
    let sources = Map.fromList
          [ ("rules.l4", "DECIDE `the greater of` a AND b\nother\n")
          , ("more.l4", "x MEANS sum OF y\n")
          ]
    map (.smFile) (searchText "(sum|`the greater of`)" sources) `shouldBe` ["more.l4", "rules.l4"]

  it "search_identifier takes the name with or without backticks" do
    let sources = Map.fromList [("rules.l4", "DECIDE `the greater of` a AND b\n")]
    length (searchIdentifier "`the greater of`" sources) `shouldBe` 1
    length (searchIdentifier "the greater of" sources) `shouldBe` 1
