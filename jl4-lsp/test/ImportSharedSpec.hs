-- | What importers of one module share, and what the type-check result does
-- not walk (smucclaw/l4-ide#1008).
--
-- 'ImportOnceSpec' counts how often a module's diagnostics are published, so
-- it sees a module that is checked or evaluated once per import path as soon as
-- it has something to report. It cannot see two other regressions, and each
-- of them passes every example there:
--
-- * Evaluation keyed by the importers' chain again. Each importer then
--   evaluates its own copy of a module it shares with another. Nothing is
--   published twice, so nothing is counted, but the work doubles at every
--   level: a library of n modules that each import the ones before it takes
--   seconds at n = 14 instead of a fraction of one. The first group of
--   examples looks at the evaluated heaps themselves.
--
-- * A deep force of the 'dependencies' of a type-check result. Every entry is
--   the full result of another module and carries its own closure, so forcing
--   it all the way down walks the import graph as a tree. The second group
--   poisons the parts of each entry that such a walk would reach.
--
-- Neither group measures time. Time is what the regressions show, but it is
-- what a loaded machine shows too; these examples fail on the structure that
-- causes the time, and they fail the same way on any machine.
module ImportSharedSpec (spec) where

import Control.DeepSeq (force)
import Control.Exception (ErrorCall (..), evaluate, try)
import Control.Monad (forM_, unless, void)
import qualified Data.Map.Strict as Map
import Data.Maybe (isJust)
import qualified Data.Text as T
import System.FilePath ((<.>), (</>))

import Language.LSP.Protocol.Types
  ( Uri (..)
  , fromNormalizedUri
  , normalizedFilePathToUri
  , toNormalizedFilePath
  )

import L4.Evaluate.ValueLazy (Reference (..))
import L4.EvaluateLazy (resolveEvalConfig)
import L4.EvaluateLazy.GraphVizOptions (defaultGraphVizOptions)
import L4.Syntax (Unique (..))
import L4.TracePolicy (lspDefaultPolicy)
import qualified LSP.Core.Shake as Shake
import LSP.L4.Oneshot (oneshotL4ActionAndDiagnostics)
import LSP.L4.Rules (GetLazyEvaluationDependencies (..), SuccessfulTypeCheck (..), TypeCheckResult (..))

import ImportOnceSpec (Mode (..), diamond, fun, runTree, withTree)

import Test.Hspec

spec :: Spec
spec = do
  oneHeapPerModule
  closureIsNotWalked

oneHeapPerModule :: Spec
oneHeapPerModule = describe "a module that two importers share, when they are evaluated" $ do
  it "is one evaluated heap, not one per importer" $ do
    -- @left@ and @right@ both import @bottom@, and @top@ imports both. Each
    -- importer's evaluated environment holds a reference for every
    -- definition of @bottom@. Evaluated once, the two environments hold the
    -- same references (the same mutable cell for every definition, so a
    -- thunk forced through one importer is forced for the other). Evaluated
    -- once per importer, they hold two sets.
    (envLeft, envRight) <- withTree "shared-heap" (diamond (fun "base" "x PLUS 1")) \dir -> do
      evalConfig <- resolveEvalConfig Nothing (lspDefaultPolicy defaultGraphVizOptions)
      let uriOf name = normalizedFilePathToUri (toNormalizedFilePath (dir </> name <.> "l4"))
          evaluated name =
            -- the call stack in the key is ignored; each importer is asked
            -- for under a stack of its own, as a caller that reached it by
            -- a different route would ask
            fmap fst <$> Shake.use (Shake.AttachCallStack [uriOf name] GetLazyEvaluationDependencies) (uriOf name)
      (_logs, _diags, envs) <- oneshotL4ActionAndDiagnostics evalConfig (dir </> "top" <.> "l4") \nfp -> do
        _ <- Shake.addVirtualFileFromFS nfp
        _ <- Shake.use SuccessfulTypeCheck (normalizedFilePathToUri nfp)
        (,) <$> evaluated "left" <*> evaluated "right"
      pure envs
    isJust envLeft `shouldBe` True
    isJust envRight `shouldBe` True
    let ofBottom = Map.filterWithKey \k _ -> "/bottom.l4" `T.isSuffixOf` (fromNormalizedUri k.moduleUri).getUri
        fromLeft = maybe Map.empty ofBottom envLeft
        fromRight = maybe Map.empty ofBottom envRight
    -- there is something to compare, and both importers see the same names
    Map.null fromLeft `shouldBe` False
    Map.keys fromLeft `shouldBe` Map.keys fromRight
    let same = [l.pointer == r.pointer | (l, r) <- zip (Map.elems fromLeft) (Map.elems fromRight)]
    unless (and same) $
      expectationFailure $
        "the two importers hold the shared module in separate heaps: "
          <> show (length (filter not same))
          <> " of its "
          <> show (length same)
          <> " definitions are not the same reference"

closureIsNotWalked :: Spec
closureIsNotWalked = describe "the type-check result of an importer, when it is forced" $ do
  -- The rule machinery forces every result a rule produces with 'force'
  -- (@defineEarlyCutoff'@ in LSP.Core.Shake). That is 'rnf' of the
  -- 'TypeCheckResult' instance. Each entry in 'dependencies' is the result of
  -- another module, already forced when that module's rule produced it, so the
  -- importer forces the list and each entry to weak head normal form and goes
  -- no deeper. An entry that is poisoned below its outermost constructor
  -- therefore must not be reached; one that is reached raises the error.
  forM_
    [ ("its own dependencies", \tc -> tc {dependencies = poison "the dependencies of an entry"})
    , ("its module", \tc -> tc {module' = poison "the module of an entry"})
    ]
    \(what, spoil) ->
      it ("does not look inside an entry: " <> what) $ do
        tc <- importer
        -- poison every entry of the importer, and nothing else
        let spoiled = tc {dependencies = map spoil tc.dependencies}
        length spoiled.dependencies `shouldSatisfy` (> 1)
        outcome <- try (void (evaluate (force spoiled)))
        case outcome of
          Right () -> pure ()
          Left (ErrorCall e) -> expectationFailure ("forcing the result reached into an entry: " <> e)

  it "does force the fields of the result itself (so the poison above is live)" $ do
    -- The control for the two examples above: the same poison in the result's
    -- own fields is reached. Without it, a poison that no force could ever
    -- reach would make those examples pass for any instance at all.
    tc <- importer
    outcome <- try (void (evaluate (force (tc {module' = poison "the module of the result"}))))
    case outcome of
      Left (ErrorCall _) -> pure ()
      Right () -> expectationFailure "forcing the result did not reach its own module"
 where
  poison :: String -> a
  poison what = error what
  -- @top@ imports @left@ and @right@, which import @bottom@: three entries.
  importer :: IO TypeCheckResult
  importer = do
    (_, mTc) <- runTree "closure-forced" Check (diamond (fun "base" "x")) "top"
    maybe (fail "top did not type-check") pure mTc
