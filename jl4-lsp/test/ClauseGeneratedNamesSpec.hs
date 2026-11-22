-- | The editor never shows a name the clause machinery made up.
--
-- A rule written as clauses is compiled to a definition whose inputs, when
-- its GIVEN names none, are named by the desugarer (@input 1@), and to local
-- bindings that hold the clauses not yet tried (@the result of clause 2@).
-- Neither can be written in source ('L4.Parser.generatedName'), so the outline
-- and the completion list leave them out. The outline is built in the
-- document-symbol handler (@jl4-lsp\/app@), out of the tests' reach, from the
-- lists 'outlineGivenParams' and 'outlineLocals' filter; completion is
-- 'completions'.
--
-- Each case type-checks a module through the real oneshot pipeline. The
-- groups are the three shapes that make the machinery name something: a group
-- with a GIVEN whose input is named after a constructor and whose first
-- clause falls through, a group with no GIVEN, and a one-clause group with a
-- literal and no GIVEN. Every case first finds a generated name in the
-- unfiltered list, so that taking a filter out turns the case red rather than
-- leaving it vacuously green.
module ClauseGeneratedNamesSpec (spec) where

import Data.Maybe (fromMaybe)
import qualified Data.Text as T
import qualified Data.Text.Mixed.Rope as Rope

import Language.LSP.Protocol.Types
  ( CompletionItem (..)
  , NormalizedUri
  , Position (..)
  , VersionedTextDocumentIdentifier (..)
  , toNormalizedUri
  )

import L4.Syntax
  ( AppForm (..)
  , Decide (..)
  , Expr (..)
  , GivenSig (..)
  , LocalDecl (..)
  , Module (..)
  , OptionallyTypedName (..)
  , Resolved
  , Section (..)
  , TopDecl (..)
  , TypeSig (..)
  , getOriginal
  , isGeneratedName
  , rawName
  , rawNameToText
  )
import LSP.L4.Actions (completions, outlineGivenParams, outlineLocals)
import LSP.L4.Rules (TypeCheckResult (..))

import CheckSource (checkSource)

import Test.Hspec

source :: T.Text
source = T.unlines
  [ "DECLARE Colour IS ONE OF Red, Green, Blue"
  , ""
  , "GIVEN Green IS A Colour"
  , "GIVETH A NUMBER"
  , "DECIDE shade Red IS 1"
  , "DECIDE shade Green IS 2"
  , ""
  , "DECIDE size Red n IS n"
  , "DECIDE size Green n IS n + 1"
  , ""
  , "DECIDE zero 0 IS 1"
  , ""
  , "GIVEN m IS A NUMBER"
  , "GIVETH A NUMBER"
  , "DECIDE twice m IS m * 2"
  , ""
  , "GIVEN k IS A NUMBER"
  , "GIVETH A NUMBER"
  , "DECIDE band 1 IS 10"
  , "DECIDE band 2 IS 20"
  , "DECIDE band k IS k + 30"
  ]

-- | The top-level definitions of a module, by name.
decides :: TypeCheckResult -> [(T.Text, Decide Resolved)]
decides tc = go section
  where
    MkModule _ _ section = tc.module'
    go (MkSection _ _ _ _ decls) = concatMap top decls
    top = \ case
      Decide _ d@(MkDecide _ _ (MkAppForm _ n _ _) _) -> [(textOf n, d)]
      Section _ s                                     -> go s
      _                                               -> []

textOf :: Resolved -> T.Text
textOf = rawNameToText . rawName . getOriginal

isGenerated :: Resolved -> Bool
isGenerated = isGeneratedName . rawName . getOriginal

givenParams :: Decide Resolved -> [OptionallyTypedName Resolved]
givenParams (MkDecide _ (MkTypeSig _ (MkGivenSig _ otns) _) _ _) = otns

body :: Decide Resolved -> Expr Resolved
body (MkDecide _ _ _ b) = b

paramName :: OptionallyTypedName Resolved -> Resolved
paramName (MkOptionallyTypedName _ n _ _) = n

-- | The local bindings of a body, as the checker left them, before the
-- outline's filter.
allLocals :: Expr Resolved -> [LocalDecl Resolved]
allLocals = \ case
  Where _ _ locals -> locals
  LetIn _ locals _ -> locals
  _                -> []

localName :: LocalDecl Resolved -> Resolved
localName = \ case
  LocalDecide _ (MkDecide _ _ (MkAppForm _ n _ _) _) -> n
  LocalAssume _ _                                    -> error "localName: an ASSUME"

-- | The cursor's position just after the first @marker@ on line @ln@ of the
-- source (counting from 1).
cursorAfter :: Int -> T.Text -> Position
cursorAfter ln marker =
  let line = T.lines source !! (ln - 1)
      (upTo, _) = T.breakOn marker line
  in Position (fromIntegral (ln - 1)) (fromIntegral (T.length upTo + T.length marker))

-- | What the completion list offers at a position, as the names it offers:
-- a name that needs backticks is offered with them.
labelsAt :: NormalizedUri -> TypeCheckResult -> Position -> [T.Text]
labelsAt nuri tc pos = map (unquoted . (._label)) (completions (Rope.fromText source) nuri tc pos)
  where
    unquoted l = fromMaybe l (T.stripPrefix "`" l >>= T.stripSuffix "`")

-- | Every name the desugarer makes up for the groups in 'source'.
madeUp :: [T.Text]
madeUp =
  [ "input 1", "input 2"
  , "the result of clause 2", "the result of clause 3", "the result of clauses 2 to 3"
  ]

spec :: Spec
spec = do
  (verDoc, tc) <- runIO (checkSource "clause-generated-names" source)
  let nuri = toNormalizedUri verDoc._uri
  describe "the editor leaves out the names clauses are compiled with" do
    let named n = case lookup n (decides tc) of
          Just d  -> d
          Nothing -> error ("no definition named " <> T.unpack n)
        generated = map textOf . filter isGenerated

    it "type-checks the module" $ tc.success `shouldBe` True

    describe "outline" do
      it "lists a GIVEN input named after a constructor, and no made-up local, for a group that falls through" do
        let d = named "shade"
        generated (map localName (allLocals (body d))) `shouldBe` ["the result of clause 2"]
        map (textOf . paramName) (outlineGivenParams (givenParams d)) `shouldBe` ["Green"]
        map (textOf . localName) (outlineLocals (body d)) `shouldBe` []

      it "lists no made-up input or local for a group with no GIVEN" do
        let d = named "size"
        generated (map paramName (givenParams d)) `shouldBe` ["input 1", "input 2"]
        generated (map localName (allLocals (body d))) `shouldBe` ["the result of clause 2"]
        map (textOf . paramName) (outlineGivenParams (givenParams d)) `shouldBe` []
        map (textOf . localName) (outlineLocals (body d)) `shouldBe` []

      it "lists no made-up input for a one-clause group with a literal and no GIVEN" do
        let d = named "zero"
        generated (map paramName (givenParams d)) `shouldBe` ["input 1"]
        map (textOf . paramName) (outlineGivenParams (givenParams d)) `shouldBe` []

      it "lists the GIVEN input and no made-up local for a three-clause group" do
        let d = named "band"
        generated (map localName (allLocals (body d))) `shouldBe` ["the result of clauses 2 to 3"]
        map (textOf . paramName) (outlineGivenParams (givenParams d)) `shouldBe` ["k"]
        map (textOf . localName) (outlineLocals (body d)) `shouldBe` []

      it "still lists what was written, for a rule that is no group" do
        let d = named "twice"
        map (textOf . paramName) (outlineGivenParams (givenParams d)) `shouldBe` ["m"]

    describe "completion" do
      it "offers no made-up name in the body of a group that falls through, and its GIVEN input named after a constructor once" do
        let labels = labelsAt nuri tc (cursorAfter 5 "IS ")
        filter (`elem` madeUp) labels `shouldBe` []
        -- the constructor `Green` and the input `Green`; its second spelling would be a third
        length (filter (== "Green") labels) `shouldBe` 2
        labels `shouldSatisfy` elem "Red"

      it "offers no made-up name in the body of a group with no GIVEN" do
        let labels = labelsAt nuri tc (cursorAfter 8 "IS ")
        filter (`elem` madeUp) labels `shouldBe` []
        labels `shouldSatisfy` elem "n"

      it "offers no made-up name in the body of a one-clause group with a literal" do
        let labels = labelsAt nuri tc (cursorAfter 11 "IS ")
        filter (`elem` madeUp) labels `shouldBe` []
        labels `shouldSatisfy` elem "Red"

      it "offers no made-up name in the second clause of a three-clause group, and its GIVEN input once" do
        let labels = labelsAt nuri tc (cursorAfter 20 "IS ")
        filter (`elem` madeUp) labels `shouldBe` []
        length (filter (== "k") labels) `shouldBe` 1
