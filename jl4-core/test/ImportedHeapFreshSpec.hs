{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | smucclaw\/l4-ide#1116, in the process that evaluates twice: an imported
-- rule with no inputs that reads a ledger must answer each evaluation from that
-- evaluation's own ledger, whatever an earlier evaluation of the same imports
-- left behind.
--
-- A host that keeps the imports' environment between evaluations evaluates a
-- file on a heap that an earlier evaluation may have forced. jl4-lsp's Shake
-- cache is such a host: 'LSP.L4.Rules.evaluateOn' builds the environment as the
-- union of one cached 'GetLazyEvaluationDependenciesFile' result per import, and
-- evaluates the file on it with 'execEvalModuleWithEnvAndImports'
-- (jl4-lsp/src/LSP/L4/Rules.hs:1455). jl4-service's direct path hands its
-- import environment, built once and kept for every request, to
-- 'execEvalExprInContextOfModuleWith', which reaches the same code
-- (jl4-service/src/Backend/Jl4.hs:1297).
--
-- The module under test has two directives. One evaluates the imported rule
-- against an empty ledger. The other is a @#TRACE@ that commits @taken@ and
-- then reads the rule. Run alone, on an environment no other evaluation has
-- touched, the first answers FALSE and the second passes its buy over
-- (@WITHIN 9@). Each is then evaluated on ONE environment after the other,
-- in each order, and must give the answer it gives alone.
--
-- Two evaluations of one module against one environment would not show this.
-- The first forcer's answer persists, so the second evaluation gives what the
-- first did, right or wrong, and "the second is the first's" holds under the
-- fault. So each evaluation here is of a module that holds ONE of the two
-- directives, cut from a single type check (so the imports' 'Unique's are the
-- ones the environment was built from), and what it gives is compared with what
-- the same module gives on an environment of its own.
--
-- The clock is pinned, because the examples of @l4 run@ that put one directive
-- of an imported file before the importer's own (@own-eval.l4@ in
-- @jl4\/tests-cli\/fixtures\/run-imported@) give the importer the answer it
-- gives alone with the clock free, and the wrong one with it pinned
-- (measured on an unfixed build, 2026-11-26).
--
-- What this pins is the contract of 'execEvalModuleWithEnv' and
-- 'execEvalModuleWithEnvAndImports', the calls that take the imports' environment
-- ('evaluateOn' passes the one it keeps): each directive of the module sees the
-- imports' rules afresh, whatever has been forced in the environment it is
-- given, and leaves that environment as it found it. A repair that leaves those
-- calls as they are, and gives each directive its own imports some other way,
-- would not satisfy it.
--
-- Two further examples pin the other half of the contract. The first reads the
-- imports' environment before and after the evaluations and requires that no
-- Reference that was unforced has been forced: the originals are only ever
-- copied, because a host keeps them for the next evaluation. The second forces
-- the imported rule in the environment by another route (the evaluator's
-- test seam for ledger reads, 'evalExprForLedgerWithEnv') before any
-- directive runs, as a host that evaluated on the environment without copying
-- it would have left it, and requires the same answers: a copy starts as the
-- rule was before anything forced it, whatever answer its original holds.
module ImportedHeapFreshSpec (spec) where

import Control.Monad (foldM, forM, forM_)
import Data.IORef (readIORef)
import Data.List (mapAccumL)
import qualified Data.Map.Strict as Map
import Data.Maybe (catMaybes)
import qualified Data.Text as Text
import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

import L4.API.VirtualFS (checkWithImports, vfsFromList)
import L4.Evaluate.ValueLazy (Environment, Reference (..), Thunk (..), Value (..))
import L4.EvaluateLazy
  ( EvalConfig
  , EvalDirectiveResult (..)
  , EvalDirectiveValue (..)
  , ReductionOutcome (..)
  , evalExprForLedgerWithEnv
  , execEvalModuleWithEnv
  , resolveEvalConfig
  , runEvalAction
  )
import L4.Import.Resolution (ResolvedImport (..), TypeCheckWithDepsResult (..), extractImportNames)
import L4.Print (prettyLayout)
import L4.Syntax (Directive (..), Expr, Module (..), Resolved, Section (..), TopDecl (..))
import L4.TracePolicy (apiDefaultPolicy)
import L4.TypeCheck.Types (CheckResult (..))

fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 0)

-- | jl4\/tests-cli\/fixtures\/run-imported\/taken.l4, less its comment.
takenSrc :: Text.Text
takenSrc = Text.unlines
  [ "IMPORT prelude"
  , ""
  , "GIVEN dflt IS A BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "`is taken` dflt MEANS fromMaybe dflt (RECALL OFFICIAL's `taken`)"
  , ""
  , "GIVETH A BOOLEAN"
  , "`taken now` MEANS `is taken` WITH dflt IS FALSE"
  ]

-- | The importer: jl4\/tests-cli\/fixtures\/run-imported\/eval-first.l4, less
-- its comment, with the @#EVAL@ as its first directive and the skip trace its
-- second.
mainSrc :: Text.Text
mainSrc = Text.unlines
  [ "IMPORT prelude"
  , "IMPORT taken"
  , ""
  , "DECLARE Actor IS ONE OF Bob"
  , "DECLARE Mode IS ONE OF peek, skip"
  , "DECLARE Act IS ONE OF"
  , "    go HAS mode IS A Mode"
  , "    buy"
  , ""
  , "GIVETH A DEONTIC Actor Act"
  , "`shop` MEANS"
  , "    PARTY Bob"
  , "    MAY buy PROVIDED NOT `taken now`"
  , "    WITHIN 10"
  , "    HENCE COMMIT `taken` IS TRUE HENCE `shop`"
  , "    LEST FULFILLED"
  , ""
  , "GIVETH A DEONTIC Actor Act"
  , "`start` MEANS"
  , "    PARTY Bob"
  , "    MAY go m"
  , "    WITHIN 10"
  , "    HENCE COMMIT `taken` IS (IF m EQUALS peek THEN NOT `taken now` ELSE TRUE) HENCE `shop`"
  , "    LEST FULFILLED"
  , ""
  , "#EVAL `taken now`"
  , ""
  , "#TRACE `start` AT 0 WITH"
  , "    PARTY Bob DOES go skip AT 1"
  , "    PARTY Bob DOES buy AT 2"
  ]

-- | The module with every directive dropped but the @n@th, counting from 0 in
-- source order. The rest of the module is untouched, so it still refers to the
-- imports by the 'Unique's of the one type check.
onlyDirective :: Int -> Module Resolved -> Module Resolved
onlyDirective n (MkModule a uri s) = MkModule a uri (snd (section 0 s))
  where
    section i (MkSection sa name aka given decls) =
      let (i', decls') = mapAccumL decl i decls
      in (i', MkSection sa name aka given (catMaybes decls'))
    decl i = \ case
      Directive da d -> (i + 1, if i == n then Just (Directive da d) else Nothing)
      Section sa s' -> let (i', s'') = section i s' in (i', Just (Section sa s''))
      other -> (i, Just other)

-- | The imports' heaps as @l4 lts@ assembles them (jl4-lsp's
-- @GetLazyEvaluationDependenciesFile@): every resolved import evaluated on top
-- of its own imports' heaps, dependencies first, and their union. Copied from
-- @jl4\/tests\/LtsList.hs@ (@importsEnv@), which a core test cannot import.
-- Each call is a new environment, nothing in it forced.
importsEnv :: EvalConfig -> [ResolvedImport] -> IO Environment
importsEnv cfg imports = fst <$> foldM visit (mempty, Map.empty) (Map.keys byName)
  where
    byName = Map.fromList [ (ri.riModuleName, ri) | ri <- imports ]
    visit (acc, memo) name = case Map.lookup name memo of
      Just _  -> pure (acc, memo)
      Nothing -> case Map.lookup name byName of
        Nothing -> pure (acc, memo)
        Just ri -> do
          let deps = extractImportNames ri.riParsed
          (acc', memo') <- foldM visit (acc, memo) deps
          let depEnv = mconcat [ e | d <- deps, Just e <- [Map.lookup d memo'] ]
          (own, _) <- execEvalModuleWithEnv cfg ri.riTypeChecked.entityInfo depEnv ri.riTypeChecked.program
          let env = own <> depEnv
          pure (acc' <> env, Map.insert name env memo')

render :: EvalDirectiveResult -> Text.Text
render res = case res.result of
  Reduction (Reduced nf) -> prettyLayout nf
  other                  -> Text.pack (show other)

-- | What a directive of the module answers, each on its own module (one
-- directive) cut from the type check.
evaluateOn :: EvalConfig -> TypeCheckWithDepsResult -> Environment -> Int -> IO [Text.Text]
evaluateOn cfg r env i = do
  (_, results) <- execEvalModuleWithEnv cfg r.tcdEntityInfo env (onlyDirective i r.tcdModule)
  pure (map render results)

-- | Each directive on an environment of its own: the answer to ask for.
answersAlone :: EvalConfig -> TypeCheckWithDepsResult -> IO [(Int, [Text.Text])]
answersAlone cfg r = forM [0, 1] \ i -> do
  env <- importsEnv cfg r.tcdResolvedImports
  (,) i <$> evaluateOn cfg r env i

typeChecked :: IO TypeCheckWithDepsResult
typeChecked = case checkWithImports (vfsFromList [("taken.l4", takenSrc)]) mainSrc of
  Left errs -> fail ("typecheck failed: " <> show errs)
  Right ok  -> pure ok

-- | The kind of thunk each Reference of an environment holds now.
thunkKinds :: Environment -> IO (Map.Map String String)
thunkKinds env = fmap Map.fromList $ forM (Map.toList env) \ (u, rf) -> do
  t <- readIORef rf.pointer
  pure . (show u,) $ case t of
    Unevaluated{}             -> "unevaluated"
    WHNFWhen{}                -> "forced, cached for a temporal context"
    WHNF (ValClosure{})       -> "closure"
    WHNF _                    -> "value"

-- | The expression of the nth directive of the module, an @#EVAL@.
evalExprOf :: Int -> TypeCheckWithDepsResult -> IO (Expr Resolved)
evalExprOf n r = case [ e | MkModule _ _ (MkSection _ _ _ _ ds) <- [onlyDirective n r.tcdModule], Directive _ (LazyEval _ e) <- ds ] of
  [e] -> pure e
  other -> fail ("directive " <> show n <> " was to be one #EVAL, and there are " <> show (length other))

spec :: Spec
spec = describe "an imported rule that reads a ledger, evaluated again on the imports' one environment (#1116)" do
  forM_
    [ ("an #EVAL of it, then the skip trace", [0, 1])
    , ("the skip trace, then an #EVAL of it", [1, 0])
    ] \ (order, directives) ->
    it ("answers each evaluation from its own ledger: " <> order) do
      cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
      r <- typeChecked
      -- each directive on an environment of its own: the answer to ask for
      alone <- answersAlone cfg r
      case alone of
        [(_, [eval]), (_, [skip])] -> do
          eval `shouldBe` "FALSE"
          skip `shouldSatisfy` Text.isInfixOf "WITHIN 9"
        _ -> expectationFailure ("each module was to hold one directive: " <> show alone)
      -- the two, one after the other, on one environment
      shared <- do
        env <- importsEnv cfg r.tcdResolvedImports
        forM directives \ i -> (,) i <$> evaluateOn cfg r env i
      Map.fromList shared `shouldBe` Map.fromList alone

  it "leaves the imports' environment as it found it: nothing unforced is forced" do
    cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
    r <- typeChecked
    env <- importsEnv cfg r.tcdResolvedImports
    kindsBefore <- thunkKinds env
    -- the control: the environment has unforced rules in it to be forced
    Map.size (Map.filter (== "unevaluated") kindsBefore) `shouldSatisfy` (> 0)
    forM_ [0, 1, 0, 1] (evaluateOn cfg r env)
    kindsAfter <- thunkKinds env
    kindsAfter `shouldBe` kindsBefore

  it "answers each evaluation from its own ledger when the rule was forced in the environment beforehand" do
    cfg <- resolveEvalConfig (Just fixedNow) apiDefaultPolicy
    r <- typeChecked
    alone <- answersAlone cfg r
    env <- importsEnv cfg r.tcdResolvedImports
    -- force `taken now` on the shared environment, against an empty ledger,
    -- by a route that does not copy it
    eval <- evalExprOf 0 r
    forced <- runEvalAction cfg (evalExprForLedgerWithEnv env eval)
    either (\ e -> expectationFailure ("the rule was to be forced: " <> show e)) (const (pure ())) forced
    kinds <- thunkKinds env
    Map.size (Map.filter (== "forced, cached for a temporal context") kinds) `shouldSatisfy` (> 0)
    shared <- forM [1, 0] \ i -> (,) i <$> evaluateOn cfg r env i
    Map.fromList shared `shouldBe` Map.fromList alone
