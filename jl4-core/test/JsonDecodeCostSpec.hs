{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

-- | What the pass over JSONDECODE costs a module that has none
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
import L4.TypeCheck (zonkDecodeTargets)

spec :: Spec
spec = describe "the pass over JSONDECODE" $ do
  -- It runs on every module checked, the prelude included, so a module with
  -- no JSONDECODE must pay next to nothing for it: it first asks whether the
  -- module mentions JSONDECODE at all, from its names alone
  -- ('L4.TypeCheck.mentionsJsonDecode'). While JSONDECODE's passes found
  -- their nodes by walking every expression, ledger requests in
  -- jl4-service-test went over the ledger's limit of 8192 MB.
  --
  -- Counted in the bytes this thread allocates, which nothing else running
  -- changes, as a share of what checking the same module allocates. Not
  -- against a walk of its own: what one walk costs depends on how GHC
  -- compiles it, and the same walk was measured at 41 MB and at 561 MB on the
  -- prelude in different builds. The pass builds its result lazily, so the
  -- result is forced in full: unforced, only its first constructor would be
  -- counted, and a pass that rebuilt every expression would still look free.
  -- Forcing a module costs 0.1% of checking it by itself. Measured on the
  -- change that made the pass ask: 0.2%; with the question answered yes for
  -- every module, 2.7%.
  it "costs a module with none under 1% of checking it" $ do
    (checkCost, r, m) <- checkedModule (manyRules 400)
    passCost <- allocated (evaluate (force (zonkDecodeTargets r.tcdSubstitution m)))
    passCost / checkCost `shouldSatisfy` (< 0.01)

  -- The control: on the same module and limit, one walk over every
  -- expression, the cheapest way the pass has found its nodes, is over it,
  -- so a pass that walked again would fail the test above. Measured: 2.0%.
  it "would not if it walked every expression (the control)" $ do
    (checkCost, _, m) <- checkedModule (manyRules 400)
    walkCost <- allocated (evaluate (length (Optics.toListOf (Optics.gplate @(Expr Resolved) Optics.% cosmosExpr) m)))
    walkCost / checkCost `shouldSatisfy` (> 0.01)

  -- The second control: the pass itself, on the same rules and one
  -- JSONDECODE more, is over the limit, so the test above sees the pass's
  -- work, and what keeps a module with none under it is the question the
  -- pass asks first. Measured: 6.5%.
  it "is over it on the same rules and one JSONDECODE more (the second control)" $ do
    (checkCost, r, m) <- checkedModule (manyRules 400 <> oneDecode)
    passCost <- allocated (evaluate (force (zonkDecodeTargets r.tcdSubstitution m)))
    passCost / checkCost `shouldSatisfy` (> 0.01)

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
