-- | A module's mixfix registries include its imports' registries, so merging
-- them must not keep a copy of an entry per import path. Appending did, and
-- with each module importing every earlier one the k-th module held 2^k
-- copies of each imported mixfix function (smucclaw\/l4-ide#1008).
module MixfixRegistryMergeSpec (spec) where

import Base
import qualified Data.Map.Strict as Map
import Test.Hspec

import L4.API.VirtualFS (checkWithImports, vfsFromList)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.Parser (execProgramParserWithHintPass)
import L4.Parser.MixfixRegistry (MixfixHintRegistry (..))
import L4.Syntax (RawName)
import L4.TypeCheck.Types (MixfixRegistry (..), unionMixfixRegistry)

sharedSrc :: Text
sharedSrc = "GIVEN a IS A NUMBER, b IS A NUMBER\na `zork with` b MEANS a PLUS b\n"

-- | The registry of a module that reaches @shared@ by two paths.
diamondRegistry :: IO MixfixRegistry
diamondRegistry =
  case checkWithImports vfs "IMPORT left\nIMPORT right\n\n#EVAL 1 `zork with` 2\n" of
    Left errs -> fail (show errs)
    Right r -> do
      r.tcdSuccess `shouldBe` True
      pure r.tcdMixfixRegistry
 where
  vfs = vfsFromList
    [ ("shared", sharedSrc)
    , ("left", "IMPORT shared\n")
    , ("right", "IMPORT shared\n")
    ]

-- | How many entries each key holds: what a merge that keeps a copy per path
-- inflates, and small enough to print when a test fails (the entries are not).
entryCounts :: MixfixRegistry -> (Map RawName Int, Map RawName Int)
entryCounts reg = (length <$> reg.byCanonicalName, length <$> reg.byFirstKeyword)

spec :: Spec
spec = describe "Merging mixfix registries across imports (#1008)" $ do
  it "registers a function reached by two import paths once" $ do
    reg <- diamondRegistry
    bimap Map.elems Map.elems (entryCounts reg) `shouldBe` ([1], [1])

  it "adds nothing when the typechecker's registry is merged with itself" $ do
    reg <- diamondRegistry
    entryCounts (unionMixfixRegistry reg reg) `shouldBe` entryCounts reg
    (unionMixfixRegistry reg reg == reg) `shouldBe` True

  it "adds nothing when the parser's hint registry is merged with itself" $
    case execProgramParserWithHintPass (toNormalizedUri (Uri "file:///shared.l4")) sharedSrc of
      Left errs -> expectationFailure (show errs)
      Right (_, hints, _) -> do
        Map.elems (length <$> hints.byFirstKeyword) `shouldBe` [1]
        length <$> (hints <> hints).byFirstKeyword `shouldBe` length <$> hints.byFirstKeyword
        (hints <> hints == hints) `shouldBe` True
