{-# LANGUAGE OverloadedRecordDot, OverloadedStrings, PatternSynonyms, TupleSections #-}
-- | The @atomId@s the ladder emits for a rule that calls another rule
-- (smucclaw/l4-ide#991). A call leaf's variable used to be keyed by a fresh id
-- from a counter that could equal an argument's resolver unique, and the
-- atomId reconciliation then gave the argument the call's atomId. Whether that
-- happens depends on how definitions are numbered, so each case is checked
-- under two numberings.
module LadderAtomIdSpec (spec) where

import Data.List (nub)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import System.Directory (createDirectoryIfMissing, getTemporaryDirectory)
import System.FilePath (takeDirectory, (</>))

import Language.LSP.Protocol.Types (VersionedTextDocumentIdentifier (..), fromNormalizedUri, normalizedFilePathToUri)

import L4.EvaluateLazy (resolveEvalConfig)
import L4.EvaluateLazy.GraphVizOptions (defaultGraphVizOptions)
import L4.Syntax (foldTopLevelDecides)
import L4.TracePolicy (lspDefaultPolicy)
import qualified L4.Viz.VizExpr as V
import qualified LSP.Core.Shake as Shake
import LSP.L4.Oneshot (oneshotL4ActionAndErrors)
import LSP.L4.Rules (TypeCheckResult (..), pattern TypeCheck)
import qualified LSP.L4.Viz.Ladder as Ladder
import qualified LSP.L4.Viz.QueryPlan as VizQueryPlan

import Test.Hspec

checkSource :: FilePath -> T.Text -> IO (Maybe (VersionedTextDocumentIdentifier, TypeCheckResult))
checkSource path source = do
  createDirectoryIfMissing True (takeDirectory path)
  T.writeFile path source
  evalConfig <- resolveEvalConfig Nothing (lspDefaultPolicy defaultGraphVizOptions)
  (_, mRes) <- oneshotL4ActionAndErrors evalConfig path \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _   <- Shake.addVirtualFileFromFS nfp
    mTc <- Shake.use TypeCheck uri
    pure $ fmap (VersionedTextDocumentIdentifier (fromNormalizedUri uri) 0,) mTc
  pure mRes

scratch :: String -> IO FilePath
scratch stem = do
  tmp <- getTemporaryDirectory
  pure (tmp </> "jl4-ladder-atomid-spec" </> (stem <> ".l4"))

-- | @leading@ is spliced in front of the callers' own inputs; adding one
-- unused input shifts every resolver unique after it by one.
fixture :: [T.Text] -> T.Text
fixture leading = T.unlines $
  [ "GIVEN p IS A BOOLEAN"
  , "      q IS A BOOLEAN"
  , "DECIDE `limb` p q IF p AND q"
  , ""
  ] <> givens ["a", "b", "c", "d"] <>
  [ "DECIDE `different actuals` " <> T.unwords (leading <> ["a", "b", "c", "d"]) <> " IF"
  , "      `limb` a b"
  , "  AND `limb` c d"
  , ""
  ] <> givens ["a", "b"] <>
  [ "DECIDE `same actuals` " <> T.unwords (leading <> ["a", "b"]) <> " IF"
  , "      `limb` a b"
  , "  AND `limb` a b"
  ]
  where
    givens names = case leading <> names of
      [] -> []
      (n : ns) -> ("GIVEN " <> n <> " IS A BOOLEAN") : map (\m -> "      " <> m <> " IS A BOOLEAN") ns

-- | Every leaf's label and atomId, as the "Show decision graph" command emits
-- them, for the rule named @target@.
ladderLeaves :: FilePath -> T.Text -> T.Text -> IO [(T.Text, T.Text)]
ladderLeaves path source target = do
  mRes <- checkSource path source
  case mRes of
    Nothing -> fail "fixture did not type-check"
    Just (verId, tc) -> do
      let cfg = Ladder.mkVizConfig verId tc.module' tc.substitution False
          rendered =
            [ (VizQueryPlan.annotateLadderWithAtomIds info st).funDecl
            | d <- foldTopLevelDecides (\d -> [d]) tc.module'
            , Right (info, st) <- [Ladder.doVisualize d cfg]
            ]
      case [fd | fd <- rendered, fd.fnName.label == target] of
        [fd] -> pure (leaves fd.body)
        other -> fail ("expected one rule named " <> T.unpack target <> ", found " <> show (length other))

leaves :: V.IRExpr -> [(T.Text, T.Text)]
leaves = \case
  V.And _ xs -> concatMap leaves xs
  V.Or _ xs -> concatMap leaves xs
  V.Not _ x -> leaves x
  V.Implies _ scope requirement _ -> leaves scope <> leaves requirement
  V.UBoolVar _ name _ _ atomId _ _ -> [(name.label, atomId)]
  V.App _ fnName args atomId _ -> (fnName.label, atomId) : concatMap leaves args
  V.TrueE _ _ -> []
  V.FalseE _ _ -> []
  V.InertE _ _ _ -> []

-- | atomIds that stand for more than one distinct label.
sharedAcrossLabels :: [(T.Text, T.Text)] -> [(T.Text, [T.Text])]
sharedAcrossLabels ls =
  [ (atomId, labels)
  | atomId <- nub (map snd ls)
  , let labels = nub [l | (l, a) <- ls, a == atomId]
  , length labels > 1
  ]

atomIdsOf :: T.Text -> [(T.Text, T.Text)] -> [T.Text]
atomIdsOf label ls = nub [a | (l, a) <- ls, l == label]

spec :: Spec
spec = describe "ladder atomIds for calls to another rule (smucclaw/l4-ide#991)" $ do
  let numberings = [("as written", []), ("shifted by one unused input", ["z"])]
  mapM_ (\(name, leading) -> describe name $ do
    it "no two different propositions share an atomId" $ do
      path <- scratch ("different-" <> show (length leading))
      ls <- ladderLeaves path (fixture leading) "`different actuals`"
      [l | l <- ["limb OF a, b", "a", "b", "limb OF c, d", "c", "d"], l `notElem` map fst ls] `shouldBe` []
      sharedAcrossLabels ls `shouldBe` []

    it "the same call made twice is still one atom" $ do
      path <- scratch ("same-" <> show (length leading))
      ls <- ladderLeaves path (fixture leading) "`same actuals`"
      length (atomIdsOf "limb OF a, b" ls) `shouldBe` 1
      length [() | (l, _) <- ls, l == "limb OF a, b"] `shouldBe` 2
      sharedAcrossLabels ls `shouldBe` []
    ) numberings
