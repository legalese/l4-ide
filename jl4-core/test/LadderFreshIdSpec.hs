{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
-- | The core ladder visualiser ("L4.Viz.Ladder", behind "L4.API" and jl4-wasm)
-- keys a bare reference by its name's unique and every other leaf by a fresh
-- id. When the fresh ids started at zero they could equal an argument's unique,
-- and two different propositions became one variable to anything keyed by
-- unique — the query plan among them (smucclaw/l4-ide#991). The fresh ids now
-- start above every unique in the rule, as in "LSP.L4.Viz.Ladder".
module LadderFreshIdSpec (spec) where

import Data.List (nub)
import Data.Text (Text)
import qualified Data.Text as Text
import Test.Hspec

import L4.API.VirtualFS
import qualified L4.Viz.Ladder as Ladder
import qualified L4.Viz.VizExpr as V

fixture :: [Text] -> Text
fixture leading = Text.unlines $
  [ "GIVEN p IS A BOOLEAN"
  , "      q IS A BOOLEAN"
  , "DECIDE `limb` p q IF p AND q"
  , ""
  ] <> givens (leading <> ["a", "b", "c", "d"]) <>
  [ "DECIDE `different actuals` " <> Text.unwords (leading <> ["a", "b", "c", "d"]) <> " IF"
  , "      `limb` a b"
  , "  AND `limb` c d"
  ]
  where
    givens [] = []
    givens (n : ns) = ("GIVEN " <> n <> " IS A BOOLEAN") : map (\m -> "      " <> m <> " IS A BOOLEAN") ns

-- | Every leaf's variable key and label.
keyed :: V.IRExpr -> [(Int, Text)]
keyed = \case
  V.And _ xs -> concatMap keyed xs
  V.Or _ xs -> concatMap keyed xs
  V.Not _ x -> keyed x
  V.Implies _ p q _ -> keyed p <> keyed q
  V.UBoolVar _ nm _ _ _ _ _ -> [(nm.unique, nm.label)]
  V.App _ nm args _ _ -> (nm.unique, nm.label) : concatMap keyed args
  _ -> []

spec :: Spec
spec = describe "core ladder: fresh ids never equal a name's unique (smucclaw/l4-ide#991)" $
  mapM_ (\(name, leading) ->
    it ("no key stands for two different leaves, " <> name) $
      case checkWithImports emptyVFS (fixture leading) of
        Left errs -> expectationFailure (Text.unpack (Text.unlines errs))
        Right r ->
          case Ladder.visualizeByName r.tcdUri "" 0 r.tcdModule r.tcdSubstitution False "`different actuals`" of
            Left e -> expectationFailure (show e)
            Right info -> do
              let ks = keyed info.funDecl.body
              map snd ks `shouldSatisfy` (\ls -> all (`elem` ls) ["a", "b", "c", "d"])
              [ (k, ls) | k <- nub (map fst ks), let ls = nub [l | (k', l) <- ks, k' == k], length ls > 1 ]
                `shouldBe` []
    ) [("as written", []), ("shifted by one unused input", ["z"])]
