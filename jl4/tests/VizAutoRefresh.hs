-- | Regression test for smucclaw/l4-ide#557.
--
-- Ladder auto-refresh (the @didChange@-driven path in 'LSP.L4.Actions.visualise')
-- builds its 'Ladder.VizConfig' with 'Actions.updateVizConfig', which used to
-- refresh @verDocId@, @moduleUri@ and @substitution@ from the fresh typecheck
-- result but NOT @module'@ — it kept re-using the module snapshot captured by the
-- last *manual* Visualize. Because @canInline@ (the @+@/unfold affordance) is
-- computed from @cfg.module'@ (via 'collectDefsForInlining'), adding a DECIDE that
-- makes an atom inline-able updated the ladder structure but left @canInline@
-- frozen — you only got the @+@ after a manual re-visualize.
--
-- This test drives 'Actions.updateVizConfig' directly: it visualises a function
-- @f@ that references an atom @g@ against a "stale" module (where @g@ is only a
-- GIVEN parameter, hence not inline-able), then refreshes the config from a
-- "fresh" module (where @g@ has become a top-level DECIDE, hence inline-able) and
-- checks that @canInline@ for @g@ flips to 'True'. It fails before the one-line
-- fix (@& set #module' tcRes.module'@) and passes after.
module VizAutoRefresh (spec) where

import Base

import L4.API.VirtualFS (checkWithImports, emptyVFS, TypeCheckWithDepsResult (..))
import L4.Names (getName)
import L4.Parser.SrcSpan (SrcPos (..))
import L4.Syntax
import qualified L4.Viz.VizExpr as V

import qualified LSP.L4.Actions as Actions
import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import qualified LSP.L4.Viz.Ladder as Ladder

import Language.LSP.Protocol.Types (VersionedTextDocumentIdentifier (..))
import Test.Hspec

-- | Stale module: @g@ is a GIVEN parameter of @f@, so it is not a top-level
-- DECIDE and therefore not inline-able.
staleSrc :: Text
staleSrc = "GIVEN g IS A BOOLEAN\nDECIDE f IF g\n"

-- | Fresh module: @g@ is now a top-level DECIDE (so it IS inline-able) and @f@
-- references it. This models the user adding a DECIDE between auto-refreshes.
-- @f@ is declared before @g@ so that @g@'s 'Unique' does not coincide with the
-- stale module's @f@ 'Unique' (DECIDE heads are numbered in declaration order).
freshSrc :: Text
freshSrc = "DECIDE f IF g\nDECIDE g IF TRUE\n"

spec :: Spec
spec =
  describe "Viz auto-refresh keeps canInline in sync with the module (#557)" $
    it "updateVizConfig refreshes module' so a newly-added DECIDE becomes inline-able" $
      case (checkWithImports emptyVFS staleSrc, checkWithImports emptyVFS freshSrc) of
        (Left errs, _) -> expectationFailure ("stale source failed to typecheck: " <> show errs)
        (_, Left errs) -> expectationFailure ("fresh source failed to typecheck: " <> show errs)
        (Right stale, Right fresh) -> do
          let verDoc =
                VersionedTextDocumentIdentifier (fromNormalizedUri fresh.tcdUri) 0

              -- The config the last *manual* Visualize would have produced: it
              -- carries the stale module snapshot.
              cfgStale =
                Ladder.mkVizConfig verDoc stale.tcdModule stale.tcdSubstitution False

              staleF = findDecide "f" stale.tcdModule
              freshF = findDecide "f" fresh.tcdModule

              vizStateStale = case Ladder.doVisualize staleF cfgStale of
                Right (_, s) -> s
                Left e -> error ("stale doVisualize failed: " <> show e)

              recentlyVisualised =
                Shake.RecentlyVisualised
                  { pos = MkSrcPos 1 1
                  , name = NormalName "f"
                  , decide = staleF
                  , type' = decideType staleF
                  , vizState = vizStateStale
                  }

              freshTc = partialTypeCheckResult fresh

              -- The config auto-refresh builds. Before the fix its module' stays
              -- stale; after the fix it is the fresh module.
              cfgRefreshed = Actions.updateVizConfig verDoc freshTc recentlyVisualised

              -- The config the pre-fix code produced: auto-refresh DID refresh the
              -- substitution/uri, but left module' frozen at the stale snapshot.
              -- We reconstruct that by forcing module' back to stale, so the only
              -- difference from cfgRefreshed is exactly the field the bug omitted.
              cfgBuggy = set #module' stale.tcdModule cfgRefreshed

              -- Visualise the *fresh* f (as auto-refresh does) against the given
              -- config and read whether its single atom g is inline-able.
              gCanInline cfg = case Ladder.doVisualize freshF cfg of
                Right (info, _) -> firstAtomCanInline info.funDecl.body
                Left e -> error ("fresh doVisualize failed: " <> show e)

          -- Deterministic anchor: the fix is exactly "propagate module'".
          view #module' cfgRefreshed `shouldBe` fresh.tcdModule

          -- Baseline: with the frozen (stale) module snapshot, g is (wrongly) not
          -- inline-able — this is the buggy behaviour.
          gCanInline cfgBuggy `shouldBe` Just False

          -- The regression itself: after refreshing the config from the fresh
          -- typecheck result, g's inline affordance appears.
          gCanInline cfgRefreshed `shouldBe` Just True

-- | Find the first top-level DECIDE with the given function name.
findDecide :: Text -> Module Resolved -> Decide Resolved
findDecide nm m =
  case foldTopLevelDecides (\d -> [d | matches d]) m of
    (d : _) -> d
    [] -> error ("findDecide: no top-level DECIDE named " <> show nm)
  where
    matches (MkDecide _ _ af _) = nameToText (getName af) == nm

-- | The resolved return type of a typechecked DECIDE (used only to fill the
-- strict 'Shake.type'' field of 'RecentlyVisualised'; never inspected here).
decideType :: Decide Resolved -> Type' Resolved
decideType (MkDecide anno _ _ _) =
  case view annInfo anno of
    Just (TypeInfo ty _) -> ty
    _ -> error "decideType: DECIDE is missing its resolved type info"

-- | 'canInline' of the first 'V.UBoolVar' atom in a ladder body. Our @f@ bodies
-- are a single atom @g@, so this reads exactly that atom.
firstAtomCanInline :: V.IRExpr -> Maybe Bool
firstAtomCanInline = go
  where
    go (V.UBoolVar _ _ _ ci _ _) = Just ci
    go (V.And _ es) = listToMaybe (mapMaybe go es)
    go (V.Or _ es) = listToMaybe (mapMaybe go es)
    go (V.Not _ e) = go e
    go (V.App _ _ es _) = listToMaybe (mapMaybe go es)
    go _ = Nothing

-- | A 'Rules.TypeCheckResult' carrying only the two fields the visualise/
-- auto-refresh path reads (@module'@ and @substitution@). All other fields are
-- intentionally undefined: forcing one would be a bug in this test's assumptions.
partialTypeCheckResult :: TypeCheckWithDepsResult -> Rules.TypeCheckResult
partialTypeCheckResult r =
  Rules.TypeCheckResult
    { module' = r.tcdModule
    , substitution = r.tcdSubstitution
    , infoMap = unused "infoMap"
    , nlgMap = unused "nlgMap"
    , scopeMap = unused "scopeMap"
    , descMap = unused "descMap"
    , success = unused "success"
    , environment = unused "environment"
    , entityInfo = unused "entityInfo"
    , infos = unused "infos"
    , errors = unused "errors"
    , dependencies = unused "dependencies"
    , mixfixRegistry = unused "mixfixRegistry"
    }
  where
    unused field =
      error
        ( "partialTypeCheckResult: field '"
            <> field
            <> "' is intentionally unused by the viz auto-refresh path (see #557 test)"
        )
