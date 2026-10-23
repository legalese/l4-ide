{-# LANGUAGE OverloadedStrings #-}
-- | The TypeScript highlighter keeps its own copy of the lexer's keyword and
-- directive lists, in @ts-shared/l4-highlight/src/tokens.ts@. That file names
-- @jl4-core/src/L4/Lexer.hs@ as its canonical source, and this compares the
-- two: a keyword added to the lexer and not to the highlighter (or the other
-- way round) fails here, with the words that differ.
module KeywordList (keywordListTests) where

import Data.List (nub)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import System.FilePath ((</>))
import Test.Hspec

import qualified L4.Lexer as Lexer

-- | @dataDir@ is the @jl4@ package directory; @tokens.ts@ sits beside it in
-- the repository. A missing file fails the test: it is never skipped.
keywordListTests :: FilePath -> Spec
keywordListTests dataDir =
  describe "the TypeScript keyword lists match the lexer" $ do
    let tokensTs = dataDir </> ".." </> "ts-shared" </> "l4-highlight" </> "src" </> "tokens.ts"
    it "L4_KEYWORDS holds exactly the lexer's keywords" $ do
      src <- TextIO.readFile tokensTs
      sameWords "L4_KEYWORDS" src (Map.keys Lexer.keywords)
    it "L4_DIRECTIVES holds exactly the lexer's directives" $ do
      src <- TextIO.readFile tokensTs
      sameWords "L4_DIRECTIVES" src (Map.keys Lexer.directives)

-- | The quoted words of the @new Set([...])@ that follows
-- @export const <name>:@, one per line, as @tokens.ts@ writes them.
setLiteral :: Text -> Text -> Maybe [Text]
setLiteral name src =
  case dropWhile (not . (("export const " <> name <> ":") `Text.isPrefixOf`)) (Text.lines src) of
    [] -> Nothing
    _ : rest ->
      Just
        [ Text.takeWhile (/= '\'') (Text.drop 1 l)
        | l <- map Text.strip (takeWhile (not . ("])" `Text.isPrefixOf`) . Text.strip) rest)
        , "'" `Text.isPrefixOf` l
        ]

sameWords :: Text -> Text -> [Text] -> Expectation
sameWords name src lexerWords =
  case setLiteral name src of
    Nothing -> expectationFailure ("tokens.ts has no `export const " <> Text.unpack name <> ":`")
    Just tsWords -> do
      -- A positive control on the reader: an empty or duplicated list means
      -- it read the file wrongly, and the comparison below would mean nothing.
      tsWords `shouldSatisfy` (not . null)
      tsWords `shouldBe` nub tsWords
      let ts = Set.fromList tsWords
          hs = Set.fromList lexerWords
          onlyTs = Set.toList (ts `Set.difference` hs)
          onlyHs = Set.toList (hs `Set.difference` ts)
      (("only in tokens.ts" :: Text, onlyTs), ("only in Lexer.hs" :: Text, onlyHs))
        `shouldBe` (("only in tokens.ts", []), ("only in Lexer.hs", []))
