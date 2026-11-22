{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | What the passes over JSONDECODE cost a module that has none
-- (smucclaw/l4-ide#1078).
module JsonDecodeCostSpec (spec) where

import Control.DeepSeq (force)
import Control.Exception (evaluate)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Optics
import System.Mem (getAllocationCounter)
import Test.Hspec

import L4.API.VirtualFS (checkWithImports, emptyVFS)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.Syntax (Expr, Module, Resolved, cosmosExpr)
import L4.TypeCheck (decodesAtTypeParameters, moduleTypeParameters, zonkDecodeTargets)

spec :: Spec
spec = describe "the passes over JSONDECODE" $ do
  -- They run on every module checked, the prelude included, so a module with
  -- no JSONDECODE must pay next to nothing for them: each first asks whether
  -- the module mentions JSONDECODE at all, from its names alone
  -- ('L4.TypeCheck.mentionsJsonDecode'). While they found their nodes by
  -- walking every expression, ledger requests in jl4-service-test went over
  -- the ledger's limit of 8192 MB.
  --
  -- Counted in the bytes this thread allocates, which nothing else running
  -- changes, as a share of what checking the same module allocates. Not
  -- against a walk of its own: what one walk costs depends on how GHC
  -- compiles it, and the same walk was measured at 41 MB and at 561 MB on the
  -- prelude in different builds. The zonk builds its result lazily, so the
  -- result is forced in full: unforced, only its first constructor would be
  -- counted, and a pass that rebuilt every expression would still look free.
  -- Forcing a module costs 0.1% of checking it by itself. Measured on the
  -- change that added the second pass: 0.3%.
  it "cost a module with none under 1% of checking it" $ do
    (checkCost, r, m) <- checkedModule (manyRules 400)
    passCost <- allocated (passes r m)
    passCost / checkCost `shouldSatisfy` (< 0.01)

  -- The control: on the same module and limit, one walk over every
  -- expression, the cheapest way the passes have found their nodes, is over
  -- it, so passes that walked again would fail the test above. Measured: 2.0%.
  it "would not if they walked every expression (the control)" $ do
    (checkCost, _, m) <- checkedModule (manyRules 400)
    walkCost <- allocated (evaluate (length (Optics.toListOf (Optics.gplate @(Expr Resolved) Optics.% cosmosExpr) m)))
    walkCost / checkCost `shouldSatisfy` (> 0.01)

  -- A module that has one pays little more: the passes walk only the parts of
  -- it that name JSONDECODE, and collect only the type parameters its types
  -- mention ('L4.TypeCheck.modulePieces'). While they walked the whole module
  -- instead, checking these rules with one JSONDECODE more allocated 21% more
  -- than checking them with none, and the passes cost 33% of it. Measured on
  -- the change that made them walk less: 0.4%.
  it "cost the same rules and one JSONDECODE more under 1% of checking it" $ do
    (checkCost, r, m) <- checkedModule (manyRules 400 <> oneDecode)
    passCost <- allocated (passes r m)
    passCost / checkCost `shouldSatisfy` (< 0.01)

  -- The second control: where every rule names JSONDECODE, the passes walk
  -- all of it, and are over the limit, so the two tests above see the
  -- passes' work. Measured: 12.4%.
  it "are over it when every rule has one (the second control)" $ do
    (checkCost, r, m) <- checkedModule (manyDecodes 400)
    passCost <- allocated (passes r m)
    passCost / checkCost `shouldSatisfy` (> 0.01)

-- | Both passes over a checked module: the zonked module forced in full, and
-- the errors counted.
passes :: TypeCheckWithDepsResult -> Module Resolved -> IO Int
passes r m = do
  let subst = r.tcdSubstitution
      typeParams = moduleTypeParameters subst m
  _ <- evaluate (force (zonkDecodeTargets subst typeParams m))
  evaluate (length (decodesAtTypeParameters subst typeParams m))

-- | What checking a module allocates, and the module it gives, forced
-- in full so that measuring a pass over it counts only the pass.
checkedModule :: Text -> IO (Double, TypeCheckWithDepsResult, Module Resolved)
checkedModule src = do
  -- Whatever the first check of a module computes once, it computes here.
  _ <- check (manyRules 1) >>= \ r -> evaluate (length r.tcdErrors)
  checkCost <- allocated (check src >>= \ r -> evaluate (length r.tcdErrors))
  r <- check src
  m <- evaluate (force r.tcdModule)
  pure (checkCost, r, m)

check :: Text -> IO TypeCheckWithDepsResult
check src = case checkWithImports emptyVFS src of
  Left errs -> fail ("the module failed to check: " <> show errs)
  Right r -> pure r

allocated :: IO a -> IO Double
allocated act = do
  a0 <- getAllocationCounter
  _ <- act
  a1 <- getAllocationCounter
  pure (fromIntegral (a0 - a1))

-- | @k@ rules with no JSONDECODE, each with a few expressions to walk.
manyRules :: Int -> Text
manyRules k = Text.unlines (concatMap rule [1 .. k])
  where
    rule i =
      let n = Text.pack (show i)
      in [ "GIVEN x IS A NUMBER"
         , "GIVETH A NUMBER"
         , "`rule " <> n <> "` x MEANS"
         , "  IF x > " <> n <> " THEN x * 2 + " <> n <> " ELSE x - " <> n
         , ""
         ]

-- | One rule that decodes JSON, at a type written down.
oneDecode :: Text
oneDecode = Text.unlines
  [ "GIVEN s IS A STRING"
  , "GIVETH AN EITHER STRING NUMBER"
  , "`decode it` s MEANS JSONDECODE s"
  ]

-- | @k@ rules that each decode JSON, at a type written down.
manyDecodes :: Int -> Text
manyDecodes k = Text.unlines (concatMap rule [1 .. k])
  where
    rule i =
      let n = Text.pack (show i)
      in [ "GIVEN s IS A STRING"
         , "GIVETH AN EITHER STRING NUMBER"
         , "`decode " <> n <> "` s MEANS JSONDECODE s"
         , ""
         ]
