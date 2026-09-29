-- | The ladder's "expand this leaf" gesture (@l4/inlineExprs@) on a call WITH
-- arguments. It used to replace @f x y@ by @f@'s bare body and drop the
-- arguments, masked only because the gesture was offered on bare references
-- alone. See specs/todo/WHERE-INLINING-SPEC.md §9.7.
module VizInline (spec) where

import Base
import qualified Base.Text as Text

import L4.API.VirtualFS (checkWithImports, emptyVFS, TypeCheckWithDepsResult (..))
import L4.Names (getName)
import L4.Syntax
import qualified L4.Viz.VizExpr as V

import qualified LSP.L4.Viz.Ladder as Ladder

import Language.LSP.Protocol.Types (VersionedTextDocumentIdentifier (..))
import Test.Hspec

-- The house style: a rule takes one record, and calls a helper that takes it too.
src :: Text
src =
  "DECLARE Facts HAS\n\
  \    `it was lawful` IS A BOOLEAN\n\
  \    `it was an accident` IS A BOOLEAN\n\
  \GIVEN f IS A Facts\n\
  \GIVETH A BOOLEAN\n\
  \DECIDE `the helper` f IF f's `it was lawful` AND f's `it was an accident`\n\
  \GIVEN g IS A Facts\n\
  \GIVETH A BOOLEAN\n\
  \DECIDE compliant g IF `the helper` g\n"

spec :: Spec
spec = describe "expanding a call with arguments in the ladder (§9.7)" $ do
  it "offers the gesture on the call, and substitutes the argument when used" $
    case checkWithImports emptyVFS src of
      Left errs -> expectationFailure ("source failed to typecheck: " <> show errs)
      Right tc -> do
        let verDoc = VersionedTextDocumentIdentifier (fromNormalizedUri tc.tcdUri) 0
            cfg = Ladder.mkVizConfig verDoc tc.tcdModule tc.tcdSubstitution False
            decide = findDecide "compliant" tc.tcdModule
        case Ladder.doVisualize decide cfg of
          Left e -> expectationFailure ("doVisualize failed: " <> show e)
          Right (info, vizState) ->
            case info.funDecl.body of
              V.UBoolVar _ nm _ canInline _ _ -> do
                canInline `shouldBe` True
                let expanded = Ladder.inlineExprs vizState decide [nm.unique]
                case Ladder.doVisualize expanded cfg of
                  Left e -> expectationFailure ("doVisualize after expanding failed: " <> show e)
                  Right (info', _) -> do
                    let atoms = atomsOf info'.funDecl.body
                    -- Two atoms, both read off the CALLER's parameter `g`. The
                    -- old gesture left the helper's own `f` behind, unbound.
                    length atoms `shouldBe` 2
                    atoms `shouldSatisfy` all ("g's" `Text.isPrefixOf`)
              other -> expectationFailure ("expected one call leaf, got: " <> show other)

findDecide :: Text -> Module Resolved -> Decide Resolved
findDecide nm m =
  case foldTopLevelDecides (\d -> [d | matches d]) m of
    (d : _) -> d
    [] -> error ("findDecide: no top-level DECIDE named " <> show nm)
  where
    matches (MkDecide _ _ af _) = nameToText (getName af) == nm

atomsOf :: V.IRExpr -> [Text]
atomsOf = \case
  V.UBoolVar _ nm _ _ _ _ -> [nm.label]
  V.And _ es -> concatMap atomsOf es
  V.Or _ es -> concatMap atomsOf es
  V.Not _ e -> atomsOf e
  V.Implies _ p q _ -> atomsOf p <> atomsOf q
  V.App _ _ es _ -> concatMap atomsOf es
  _ -> []
