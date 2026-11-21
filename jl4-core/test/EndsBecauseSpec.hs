-- | The @\@ends-because <reason>@ annotation: its own token, read only from its
-- own field, kept by the printer, an error above anything that is not a
-- definition and when it has no reason, and reaching the definitions in a
-- WHERE or LET. This is the syntax alone; what the mark changes is in
-- "CyclesSpec". The one thing of that shown here: each mark the checker
-- accepts leaves an information-level note carrying its reason (ruling L4), so
-- the "no diagnostics" checks below leave those notes out and name them.
module EndsBecauseSpec (spec) where

import Data.Foldable (for_, toList)
import Test.Hspec
import Data.Text (Text)
import qualified Data.Text as Text
import Optics (toListOf, (^.))

import Base (Uri (..), toNormalizedUri)
import L4.API.VirtualFS (checkWithImports, emptyVFS)
import L4.Lexer (PError (..))
import L4.Parser (execProgramParser)
import qualified L4.Parser.ResolveAnnotation as Resolve
import L4.Annotation (getAnno)
import L4.Import.Resolution (TypeCheckWithDepsResult(..))
import L4.Print (prettyLayout)
import L4.Syntax
import qualified L4.TypeCheck as TC
import L4.Cycles.Warning (MarkNote (..))
import L4.TypeCheck.Types (CheckErrorWithContext(..), CheckError(..))

-- | Every definition of the module, with its name as written: the top-level
-- and section-level ones, then those in a WHERE or LET, at any depth.
decides :: Module Resolved -> [(Text, Decide Resolved)]
decides (MkModule _ _ sect) = concatMap withLocals (goSection sect)
 where
  goSection (MkSection _ _ _ _ decls) = concatMap goDecl decls
  goDecl = \ case
    Decide _ d -> [d]
    Section _ s -> goSection s
    _ -> []
  withLocals d@(MkDecide _ _ _ body) =
    named d : map named (localsOf body)
  localsOf body =
    [ l | e <- toListOf cosmosExpr body, l <- case e of
            Where _ _ ds -> [ l' | LocalDecide _ l' <- ds ]
            LetIn _ ds _ -> [ l' | LocalDecide _ l' <- ds ]
            _ -> [] ]
  named d@(MkDecide _ _ (MkAppForm _ n _ _) _) = (rawNameToText (rawName (getActual n)), d)

reasons :: [(Text, Decide Resolved)] -> [(Text, Maybe Text)]
reasons = map (\ (n, d) -> (n, getEndsBecauseReason <$> (getAnno d ^. annEndsBecause)))

checked :: Text -> IO TypeCheckWithDepsResult
checked source =
  case checkWithImports emptyVFS source of
    Left errs -> fail (Text.unpack (Text.unlines errs))
    Right r -> pure r

errorTexts :: TypeCheckWithDepsResult -> Text
errorTexts r = Text.unlines (concatMap TC.prettyCheckErrorWithContext r.tcdErrors)

-- | The rules the checker's notes on accepted marks are about, in order.
notedRules :: TypeCheckWithDepsResult -> [Text]
notedRules r = [ n.rule | MkCheckErrorWithContext{kind = EndsBecauseNoted n} <- r.tcdErrors ]

-- | Every diagnostic but those notes.
otherThanNotes :: TypeCheckWithDepsResult -> [CheckErrorWithContext]
otherThanNotes r = [ e | e <- r.tcdErrors, not (isNote e.kind) ]
 where
  isNote = \ case
    EndsBecauseNoted _ -> True
    _ -> False

countOfKind :: (CheckError -> Bool) -> TypeCheckWithDepsResult -> Int
countOfKind p r = length [ () | MkCheckErrorWithContext{kind = k} <- r.tcdErrors, p k ]

-- | The parser warnings about @\@ends-because@, and nothing else.
endsBecauseWarnings :: Text -> IO [Resolve.Warning]
endsBecauseWarnings source =
  case execProgramParser (toNormalizedUri (Uri "file:///ends-because-spec.l4")) source of
    Left errs -> fail (unlines (map (Text.unpack . (.message)) (toList errs)))
    Right (_, ws) -> pure (filter ours ws)
 where
  ours = \ case
    Resolve.EndsBecauseAnnotationMisplaced {} -> True
    Resolve.EndsBecauseAnnotationSameLine {} -> True
    Resolve.EndsBecauseAnnotationSuperseded {} -> True
    Resolve.EndsBecauseAnnotationNoLocation {} -> True
    _ -> False

isMisplaced, isSameLine, isSuperseded :: Resolve.Warning -> Bool
isMisplaced = \ case Resolve.EndsBecauseAnnotationMisplaced {} -> True; _ -> False
isSameLine = \ case Resolve.EndsBecauseAnnotationSameLine {} -> True; _ -> False
isSuperseded = \ case Resolve.EndsBecauseAnnotationSuperseded {} -> True; _ -> False

isNonDefinition, isNeedsReason :: CheckError -> Bool
isNonDefinition = \ case EndsBecauseOnNonDefinition {} -> True; _ -> False
isNeedsReason = \ case EndsBecauseNeedsReason {} -> True; _ -> False

marked :: Text
marked = Text.unlines
  [ "GIVEN a IS A BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "`plain step` MEANS a"
  , ""
  , "@ends-because each step is nearer the end"
  , "GIVEN a IS A BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "`vouched step` MEANS a"
  , ""
  , "@desc ends-because in the description only"
  , "GIVEN a IS A BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "`described step` MEANS a"
  ]

misplaced :: Text
misplaced = Text.unlines
  [ "@ends-because it ends"
  , "DECLARE Person HAS name IS A STRING"
  , ""
  , "@ends-because it ends"
  , "ASSUME `a thing` IS A BOOLEAN"
  , ""
  , "@ends-because it ends"
  , "#EVAL TRUE"
  , ""
  , "@ends-because it ends"
  , "GIVEN a IS A BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "`fine` MEANS a"
  ]

placements :: Text
placements = Text.unlines
  [ "§ `One`"
  , "    GIVEN p IS A BOOLEAN"
  , "          q IS A BOOLEAN"
  , ""
  , "@ends-because nullary reason"
  , "`nullary` MEANS p AND q"
  , ""
  , "GIVEN a IS A BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "@ends-because below giveth reason"
  , "`below giveth` MEANS a"
  , ""
  , "@ends-because above a heading"
  , "§ `Two`"
  , "    GIVEN r IS A BOOLEAN"
  , ""
  , "`open` MEANS r"
  ]

-- A definition with a WHERE local, one with a LET, and a nested WHERE: the
-- marks above locals attach to them and to nothing else.
locals :: Text
locals = Text.unlines
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A NUMBER"
  , "`outer` n MEANS"
  , "  `inner` n"
  , "  WHERE"
  , "    @ends-because the local one"
  , "    GIVEN k IS A NUMBER"
  , "    GIVETH A NUMBER"
  , "    `inner` k MEANS k PLUS 1"
  , "    `plain local` MEANS 2"
  , ""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A NUMBER"
  , "`with let` n MEANS"
  , "  LET"
  , "    @ends-because the let one"
  , "    `bound` MEANS n PLUS 1"
  , "  IN bound"
  ]

-- Marks that are not above a local: inside a body, and at the end of a line.
inBody :: Text
inBody = Text.unlines
  [ "GIVEN n IS A NUMBER"
  , "GIVETH A NUMBER"
  , "`body` n MEANS"
  , "  @ends-because inside the body"
  , "  n PLUS 1"
  , ""
  , "`after` MEANS 1"
  ]

withText :: Text
withText = Text.unlines
  [ "@ends-because -- a comment is part of the reason"
  , "`beta` MEANS TRUE"
  , ""
  , "GIVEN x IS A BOOLEAN @ends-because on an input"
  , "GIVETH A BOOLEAN"
  , "`gamma` MEANS x"
  , ""
  , "@ends-because above the definition"
  , "GIVEN y IS A BOOLEAN @ends-because on another input"
  , "      z IS A BOOLEAN @ends-because on a third"
  , "GIVETH A BOOLEAN"
  , "`delta` MEANS y AND z"
  ]

-- A marked clause group at the top level, and a WHERE under a later clause of
-- one: recursion is usually written as clauses. (A group cannot be a WHERE
-- local: its clauses do not parse there.)
groups :: Text
groups = Text.unlines
  [ "@ends-because the number drops by one and stops at zero"
  , "GIVEN n IS A NUMBER"
  , "GIVETH A NUMBER"
  , "`fact` 0 MEANS 1"
  , "`fact` n MEANS n TIMES `fact` (n MINUS 1)"
  , ""
  , "GIVEN n IS A NUMBER"
  , "GIVETH A NUMBER"
  , "`later` 0 MEANS 1"
  , "`later` n MEANS"
  , "  `inside` n"
  , "  WHERE"
  , "    @ends-because under a later clause"
  , "    GIVEN k IS A NUMBER"
  , "    GIVETH A NUMBER"
  , "    `inside` k MEANS k"
  ]

emptyReasons :: Text
emptyReasons = Text.unlines
  [ "@ends-because"
  , "`bare` MEANS TRUE"
  , ""
  , "@ends-because   "
  , "`spaces` MEANS TRUE"
  , ""
  , "@ends-because has one"
  , "`reasoned` MEANS TRUE"
  ]

spec :: Spec
spec = describe "@ends-because" do
  it "marks the definition it sits above, and only that one, keeping the reason" do
    r <- checked marked
    reasons (decides r.tcdModule) `shouldBe`
      [ ("plain step", Nothing)
      , ("vouched step", Just "each step is nearer the end")
      , ("described step", Nothing)
      ]
    otherThanNotes r `shouldBe` []
    notedRules r `shouldBe` ["vouched step"]
  it "is not read from a @desc whose first word happens to be the same" do
    r <- checked marked
    lookup "described step" (reasons (decides r.tcdModule)) `shouldBe` Just Nothing
  it "is re-emitted by the printer, reason and all, so a re-printed module keeps the mark" do
    r <- checked marked
    let printed = prettyLayout r.tcdModule
    Text.count "@ends-because each step is nearer the end" printed `shouldBe` 1
    Text.count "@ends-because" printed `shouldBe` 1
    r2 <- checked printed
    reasons (decides r2.tcdModule) `shouldBe` reasons (decides r.tcdModule)
  it "is a check error above a DECLARE, an ASSUME and a directive, naming what it sits on, and no error above the definition" do
    r <- checked misplaced
    let errs = errorTexts r
    for_ ["`Person`, a declaration", "`a thing`, an assumption", "a directive, which is not a definition"] \ needle ->
      errs `shouldSatisfy` Text.isInfixOf needle
    countOfKind isNonDefinition r `shouldBe` 3
    reasons (decides r.tcdModule) `shouldBe` [("fine", Just "it ends")]
  it "honours a mark above a nullary step, and directly below a GIVETH" do
    r <- checked placements
    let rs = reasons (decides r.tcdModule)
    lookup "nullary" rs `shouldBe` Just (Just "nullary reason")
    lookup "below giveth" rs `shouldBe` Just (Just "below giveth reason")
    lookup "open" rs `shouldBe` Just Nothing
  it "is an error above a section heading rather than passing to the first definition below" do
    r <- checked placements
    errorTexts r `shouldSatisfy` Text.isInfixOf "a section heading or its inputs"
    lookup "open" (reasons (decides r.tcdModule)) `shouldBe` Just Nothing
  it "reaches a definition in a WHERE and one in a LET, and no other" do
    r <- checked locals
    reasons (decides r.tcdModule) `shouldBe`
      [ ("outer", Nothing)
      , ("inner", Just "the local one")
      , ("plain local", Nothing)
      , ("with let", Nothing)
      , ("bound", Just "the let one")
      ]
    otherThanNotes r `shouldBe` []
    notedRules r `shouldBe` ["inner", "bound"]
  it "keeps a mark on a WHERE or LET local through a re-print" do
    r <- checked locals
    r2 <- checked (prettyLayout r.tcdModule)
    reasons (decides r2.tcdModule) `shouldBe` reasons (decides r.tcdModule)
  it "is read as a comment-bearing reason; a mark on a GIVEN line is an error naming the input, one per mark, and leaves the mark above the definition alone" do
    r <- checked withText
    reasons (decides r.tcdModule) `shouldBe`
      [ ("beta", Just "-- a comment is part of the reason")
      , ("gamma", Nothing)
      , ("delta", Just "above the definition")
      ]
    let errs = errorTexts r
    for_ ["`x`, an input", "`y`, an input", "`z`, an input"] \ needle ->
      errs `shouldSatisfy` Text.isInfixOf needle
    countOfKind isNonDefinition r `shouldBe` 3
  it "needs a reason: none, or only spaces, is an error naming the definition and saying why" do
    r <- checked emptyReasons
    countOfKind isNeedsReason r `shouldBe` 2
    let errs = errorTexts r
    errs `shouldSatisfy` Text.isInfixOf "@ends-because needs a reason after it"
    errs `shouldSatisfy` Text.isInfixOf "above `bare`"
    errs `shouldSatisfy` Text.isInfixOf "above `spaces`"
    errs `shouldSatisfy` Text.isInfixOf "The reason is what a reader checks"
    reasons (decides r.tcdModule) `shouldBe`
      [ ("bare", Just ""), ("spaces", Just ""), ("reasoned", Just "has one") ]
  it "is carried by no definition when it sits inside a body and not above a local" do
    r <- checked inBody
    reasons (decides r.tcdModule) `shouldBe` [("body", Nothing), ("after", Nothing)]
    r.tcdErrors `shouldBe` []
  describe "parser warnings" do
    it "a mark inside a body that is not above a local is a warning, one" do
      ws <- endsBecauseWarnings inBody
      length ws `shouldBe` 1
      all isMisplaced ws `shouldBe` True
    it "a mark after the last construct is a warning, and carries nothing" do
      let src = "`a` MEANS TRUE\n@ends-because trailing\n"
      ws <- endsBecauseWarnings src
      map isMisplaced ws `shouldBe` [True]
    it "a mark at the end of the line before a definition is a warning, and the next definition is not marked" do
      let src = Text.unlines ["`a` MEANS TRUE @ends-because late", "`b` MEANS TRUE"]
      ws <- endsBecauseWarnings src
      map isSameLine ws `shouldBe` [True]
      r <- checked src
      reasons (decides r.tcdModule) `shouldBe` [("a", Nothing), ("b", Nothing)]
    it "two marks above one definition are one mark and a warning: the closest counts" do
      let src = Text.unlines ["@ends-because first", "@ends-because second", "`a` MEANS TRUE"]
      ws <- endsBecauseWarnings src
      map isSuperseded ws `shouldBe` [True]
      r <- checked src
      reasons (decides r.tcdModule) `shouldBe` [("a", Just "second")]
    it "a mark inside a WHERE body, above the body and not above the local, is a warning" do
      let src = Text.unlines
            [ "GIVEN n IS A NUMBER"
            , "GIVETH A NUMBER"
            , "`f` n MEANS"
            , "  @ends-because above the body, not above a local"
            , "  `g` n"
            , "  WHERE"
            , "    GIVEN k IS A NUMBER"
            , "    GIVETH A NUMBER"
            , "    `g` k MEANS k"
            ]
      ws <- endsBecauseWarnings src
      map isMisplaced ws `shouldBe` [True]
      r <- checked src
      reasons (decides r.tcdModule) `shouldBe` [("f", Nothing), ("g", Nothing)]
    it "a well-placed mark, at any depth, is no warning" do
      for_ [marked, locals, placements] \ src -> do
        ws <- endsBecauseWarnings src
        ws `shouldBe` []
  describe "clause groups" do
    it "a mark above a group, and one in a WHERE under a later clause, lands on that definition" do
      r <- checked groups
      let rs = reasons (decides r.tcdModule)
      lookup "fact" rs `shouldBe` Just (Just "the number drops by one and stops at zero")
      lookup "inside" rs `shouldBe` Just (Just "under a later clause")
      lookup "later" rs `shouldBe` Just Nothing
      otherThanNotes r `shouldBe` []
      notedRules r `shouldBe` ["fact", "inside"]
      ws <- endsBecauseWarnings groups
      ws `shouldBe` []
    it "keeps each of them through a re-print" do
      r <- checked groups
      r2 <- checked (prettyLayout r.tcdModule)
      let named rr = [ x | x@(n, _) <- reasons (decides rr.tcdModule), n `elem` ["fact", "inside", "later"] ]
      named r2 `shouldBe` named r
      Text.count "@ends-because" (prettyLayout r.tcdModule) `shouldBe` 2
