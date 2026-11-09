-- | The @\@nonassertable@ annotation (specs/todo/presumption-assertion/CONTRACT.md §6):
-- its own token, read only from its own field, kept by the printer, and an
-- error above anything that is not a definition.
module NonassertableSpec (spec) where

import Data.Foldable (for_)
import Test.Hspec
import Data.Text (Text)
import qualified Data.Text as Text

import L4.API.VirtualFS (checkWithImports, emptyVFS)
import L4.Export (isNonassertableDecide)
import L4.Import.Resolution (TypeCheckWithDepsResult(..))
import L4.Print (prettyLayout)
import L4.Syntax
import qualified L4.TypeCheck as TC
import L4.TypeCheck.Types (CheckErrorWithContext(..), CheckError(..))

-- | Every definition of the module, with its name as written.
decides :: Module Resolved -> [(Text, Decide Resolved)]
decides (MkModule _ _ sect) = goSection sect
 where
  goSection (MkSection _ _ _ _ decls) = concatMap goDecl decls
  goDecl = \ case
    Decide _ d@(MkDecide _ _ (MkAppForm _ n _ _) _) -> [(rawNameToText (rawName (getActual n)), d)]
    Section _ s -> goSection s
    _ -> []

checked :: Text -> IO TypeCheckWithDepsResult
checked source =
  case checkWithImports emptyVFS source of
    Left errs -> fail (Text.unpack (Text.unlines errs))
    Right r -> pure r

marked :: Text
marked = Text.unlines
  [ "GIVEN a IS A BOOLEAN"
  , "      b IS A BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "`open step` MEANS a OR b"
  , ""
  , "@nonassertable"
  , "GIVEN a IS A BOOLEAN"
  , "      b IS A BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "`closed step` MEANS a AND b"
  , ""
  , "@desc nonassertable in the description only"
  , "GIVEN a IS A BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "`described step` MEANS a"
  ]

misplaced :: Text
misplaced = Text.unlines
  [ "@nonassertable"
  , "DECLARE Person HAS name IS A STRING"
  , ""
  , "@nonassertable"
  , "GIVEN a IS A BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "`fine` MEANS a"
  ]

-- A nullary step from section inputs; a mark directly above the name line
-- (below the GIVETH); a two-clause group; a mark above the heading of a
-- second section and one above that section's GIVEN.
placements :: Text
placements = Text.unlines
  [ "§ `One`"
  , "    GIVEN p IS A BOOLEAN"
  , "          q IS A BOOLEAN"
  , ""
  , "@nonassertable"
  , "`nullary` MEANS p AND q"
  , ""
  , "GIVEN a IS A BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "@nonassertable"
  , "`below giveth` MEANS a"
  , ""
  , "@nonassertable"
  , "GIVEN n IS A NUMBER"
  , "GIVETH A NUMBER"
  , "`clauses` 0 MEANS 1"
  , "`clauses` n MEANS n"
  , ""
  , "@nonassertable"
  , "§ `Two`"
  , "    GIVEN r IS A BOOLEAN"
  , ""
  , "`open` MEANS r"
  ]

withText :: Text
withText = Text.unlines
  [ "@nonassertable -- a comment is fine"
  , "`beta` MEANS TRUE"
  , ""
  , "GIVEN x IS A BOOLEAN @nonassertable"
  , "GIVETH A BOOLEAN"
  , "`gamma` MEANS x"
  , ""
  , "@nonassertable"
  , "GIVEN y IS A BOOLEAN @nonassertable"
  , "      z IS A BOOLEAN @nonassertable"
  , "GIVETH A BOOLEAN"
  , "`delta` MEANS y AND z"
  ]

spec :: Spec
spec = describe "@nonassertable" do
  it "marks the definition it sits above, and only that one" do
    r <- checked marked
    let ds = decides r.tcdModule
    map fst ds `shouldBe` ["open step", "closed step", "described step"]
    map (isNonassertableDecide . snd) ds `shouldBe` [False, True, False]
  it "is not read from a @desc whose first word happens to be the same" do
    r <- checked marked
    lookup "described step" (map (\ (n, d) -> (n, isNonassertableDecide d)) (decides r.tcdModule)) `shouldBe` Just False
  it "is re-emitted by the printer, so a re-printed module keeps the mark" do
    r <- checked marked
    let printed = prettyLayout r.tcdModule
    Text.count "@nonassertable" printed `shouldBe` 1
  it "is a check error above a DECLARE, naming what it sits on, and no error above the definition" do
    r <- checked misplaced
    let errs = Text.unlines (concatMap TC.prettyCheckErrorWithContext r.tcdErrors)
    errs `shouldSatisfy` Text.isInfixOf "a declaration, which cannot be asserted in any case"
    length [ () | MkCheckErrorWithContext{kind = NonassertableOnNonDefinition _ _ _} <- r.tcdErrors ] `shouldBe` 1
    map (isNonassertableDecide . snd) (decides r.tcdModule) `shouldBe` [True]
  it "honours a mark above a nullary step, directly below a GIVETH, and above a two-clause group" do
    r <- checked placements
    let ds = decides r.tcdModule
    lookup "nullary" (marks ds) `shouldBe` Just True
    lookup "below giveth" (marks ds) `shouldBe` Just True
    lookup "clauses" (marks ds) `shouldBe` Just True
    lookup "open" (marks ds) `shouldBe` Just False
  it "is an error above a section heading rather than passing to the first definition below" do
    r <- checked placements
    let errs = Text.unlines (concatMap TC.prettyCheckErrorWithContext r.tcdErrors)
    errs `shouldSatisfy` Text.isInfixOf "a section heading or its inputs"
    lookup "open" (marks (decides r.tcdModule)) `shouldBe` Just False
  it "names the construct it sits on" do
    r <- checked misplaced
    let errs = Text.unlines (concatMap TC.prettyCheckErrorWithContext r.tcdErrors)
    errs `shouldSatisfy` Text.isInfixOf "`Person`, a declaration"
  it "takes no words: a comment after it is fine; a mark on a GIVEN line is an error naming the input, one per mark, and leaves the mark above the definition alone" do
    r <- checked withText
    marks (decides r.tcdModule) `shouldBe` [("beta", True), ("gamma", False), ("delta", True)]
    let errs = Text.unlines (concatMap TC.prettyCheckErrorWithContext r.tcdErrors)
    for_ ["`x`, an input", "`y`, an input", "`z`, an input"] \ needle ->
      errs `shouldSatisfy` Text.isInfixOf needle
    length [ () | MkCheckErrorWithContext{kind = NonassertableOnNonDefinition _ _ _} <- r.tcdErrors ] `shouldBe` 3
  it "never swallows its line: prose after it is a parse error, and a definition on its line is read as source and not marked" do
    case checkWithImports emptyVFS "@nonassertable some words\n`a` MEANS TRUE\n" of
      Left _ -> pure ()
      Right _ -> expectationFailure "prose after the mark parsed"
    -- Whether the indented definition parses depends on what precedes it;
    -- either way it is not swallowed, and where it parses the mark, which
    -- precedes it, is its.
    case checkWithImports emptyVFS "@nonassertable `a` MEANS TRUE\n" of
      Left _ -> pure ()
      Right r -> marks (decides r.tcdModule) `shouldBe` [("a", True)]
  it "lands on the same definition after a re-print" do
    r <- checked placements
    r2 <- checked (prettyLayout r.tcdModule)
    marks (decides r2.tcdModule) `shouldBe` marks (decides r.tcdModule)
 where
  marks = map (\ (n, d) -> (n, isNonassertableDecide d))
