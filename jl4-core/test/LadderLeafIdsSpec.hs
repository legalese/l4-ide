{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | A bare name in a rule is a leaf of the ladder keyed by the name's own
-- unique, and every other leaf (a comparison, an @IF@, a @REFUSE@) by a fresh
-- id from a counter. If the two ranges overlap, two different propositions are
-- one variable of the diagram: the query plan then asks a refusal's reason as an
-- ordinary question, or takes an answer for a refusal. The counter starts above
-- every unique in the rule, in this ladder (the one the browser's plan builder
-- draws) as in the language server's.
--
-- How many rules come first moves a name's unique against the counter's range,
-- so each shape is drawn after every number of rules of no inputs from one to
-- thirteen, and no particular numbering is relied on.
module LadderLeafIdsSpec (spec) where

import Test.Hspec
import Control.Monad (forM_)
import qualified Data.IntMap.Strict as IntMap
import qualified Data.List as List
import Data.Text (Text)
import qualified Data.Text as Text

import L4.API.VirtualFS (checkWithImports, emptyVFS)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.Viz.Ladder (getRefusingAtoms, visualizeByNameSpelledOut, visualizeByNameWithState)
import L4.Viz.VizExpr (FunDecl (..), IRExpr (..), Name (..), RenderAsLadderInfo (..))

-- | @n + 1@ rules of no inputs, @p0@ to @pn@, then two rules that read the last
-- of them beside a leaf that is not a name.
source :: Int -> Text
source n =
  Text.unlines $
    concat [["GIVETH A BOOLEAN", "p" <> tshow k <> " MEANS TRUE", ""] | k <- [0 .. n]]
      <> [ "GIVEN a IS A BOOLEAN"
         , "      b IS A BOOLEAN"
         , "GIVETH A BOOLEAN"
         , "ifCase a b MEANS p" <> tshow n <> " AND (IF b THEN b ELSE b)"
         , ""
         , "GIVEN a IS A BOOLEAN"
         , "      b IS A BOOLEAN"
         , "GIVETH A BOOLEAN"
         , "refuseCase a b MEANS p" <> tshow n <> " OR (REFUSE \"L1\")"
         ]
  where
    tshow = Text.pack . show

-- | Every leaf the plan treats as a variable, with the unique it is keyed by.
leaves :: IRExpr -> [(Text, Int)]
leaves = \case
  And _ xs -> concatMap leaves xs
  Or _ xs -> concatMap leaves xs
  Not _ x -> leaves x
  UBoolVar _ nm _ _ _ -> [(nm.label, nm.unique)]
  App _ nm _ _ -> [(nm.label, nm.unique)]
  TrueE _ _ -> []
  FalseE _ _ -> []
  InertE {} -> []

-- | How a rule is drawn: simplified, as written, or as written with each
-- @IMPLIES@ and @IF@ spelled out.
data Drawing = Simplified | AsWritten | SpelledOut
  deriving stock (Show, Eq, Enum, Bounded)

spec :: Spec
spec =
  describe "the ladder's leaf ids" $
    forM_ [0 .. 12 :: Int] \n ->
      describe ("after " <> show (n + 1) <> " rules of no inputs") $ do
        let lastRule = "p" <> Text.pack (show n)
            draw drawing fn = case checkWithImports emptyVFS (source n) of
              Left errs -> Left (Text.unlines errs)
              Right r ->
                let uri = r.tcdUri
                    drawn = case drawing of
                      Simplified -> visualizeByNameWithState uri "t.l4" 1 r.tcdModule r.tcdSubstitution True fn
                      AsWritten -> visualizeByNameWithState uri "t.l4" 1 r.tcdModule r.tcdSubstitution False fn
                      SpelledOut -> visualizeByNameSpelledOut uri "t.l4" 1 r.tcdModule r.tcdSubstitution fn
                 in either (Left . Text.pack . show) Right drawn

        forM_ [minBound .. maxBound :: Drawing] \drawing ->
          describe (show drawing) $ do
            it "keeps an IF beside a name apart from the name" $
              case draw drawing "ifCase" of
                Left e -> expectationFailure (Text.unpack e)
                Right (info, _) -> do
                  let ls = List.nub (leaves info.funDecl.body)
                  -- the name, and the IF as one leaf or the names it reads
                  lastRule `elem` map fst ls `shouldBe` True
                  length (List.nub (map snd ls)) `shouldBe` length ls

            it "keeps a REFUSE beside a name apart from the name, and marks only the REFUSE" $
              case draw drawing "refuseCase" of
                Left e -> expectationFailure (Text.unpack e)
                Right (info, state) -> do
                  let ls = List.nub (leaves info.funDecl.body)
                      uniqueOf label = [u | (l, u) <- ls, l == label]
                      refusing = IntMap.keys (getRefusingAtoms state)
                  length (List.nub (map snd ls)) `shouldBe` length ls
                  length (uniqueOf lastRule) `shouldBe` 1
                  refusing `shouldBe` uniqueOf "REFUSE \"L1\""
