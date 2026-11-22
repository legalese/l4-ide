{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
-- | The core ladder visualiser ("L4.Viz.Ladder", behind "L4.API" and jl4-wasm)
-- negates a guard on every route where it fails, and the scope of a nested
-- implication. When the guard or the scope was already a @NOT@, it drew
-- @NOT (NOT x)@: true, and a box inside a box for the reader to undo. Those
-- negations now go through 'V.negateIR', which cancels the pair. A @NOT@ the
-- author wrote is still drawn as written.
--
-- The same is pinned for the LSP visualiser in jl4's VizGuardedRows and VizImplies.
module LadderDoubleNegationSpec (spec) where

import Data.Text (Text)
import qualified Data.Text as Text
import Test.Hspec

import L4.API.VirtualFS
import qualified L4.Viz.Ladder as Ladder
import qualified L4.Viz.VizExpr as V

-- | The ladder body of @compliant@ in the source.
body :: Text -> IO V.IRExpr
body src =
  case checkWithImports emptyVFS src of
    Left errs -> expectationFailure (Text.unpack (Text.unlines errs)) >> fail "typecheck"
    Right r ->
      case Ladder.visualizeByName r.tcdUri "" 0 r.tcdModule r.tcdSubstitution False "compliant" of
        Left e -> expectationFailure (show e) >> fail "visualise"
        Right info -> pure info.funDecl.body

-- | Connectives and atom labels, without node ids.
shape :: V.IRExpr -> String
shape = \case
  V.UBoolVar _ nm _ _ _ _ _ -> Text.unpack nm.label
  V.And _ es -> "(and " <> unwords (map shape es) <> ")"
  V.Or _ es -> "(or " <> unwords (map shape es) <> ")"
  V.Not _ e -> "(not " <> shape e <> ")"
  V.Implies _ p q _ -> "(implies " <> shape p <> " " <> shape q <> ")"
  other -> show other

givens :: Text
givens = "GIVEN a IS A BOOLEAN\n      b IS A BOOLEAN\n      c IS A BOOLEAN\n"

spec :: Spec
spec = describe "core ladder: a negation the lowering adds cancels a NOT the guard already has" $ do
  it "IF NOT a THEN b ELSE c: the ELSE route reads a, not NOT (NOT a)" $
    (shape <$> body (givens <> "DECIDE compliant IF\n  IF NOT a THEN b ELSE c\n"))
      `shouldReturn` "(or (and (not a) b) (and a c))"

  -- The shape of the Charities Law's charity test, Article 5(1).
  it "IF NOT a THEN FALSE ELSE b draws a and b, with no NOT at all" $
    (shape <$> body (givens <> "DECIDE compliant IF\n  IF NOT a THEN FALSE ELSE b\n"))
      `shouldReturn` "(and a b)"

  it "a nested implication whose scope is NOT a reads a OR b" $
    (shape <$> body (givens <> "DECIDE compliant IF\n  c AND ((NOT a) IMPLIES b)\n"))
      `shouldReturn` "(and c (or a b))"

  it "a NOT NOT the author wrote is drawn as written" $
    (shape <$> body (givens <> "DECIDE compliant IF\n  NOT (NOT a)\n"))
      `shouldReturn` "(not (not a))"
