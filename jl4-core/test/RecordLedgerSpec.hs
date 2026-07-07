{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}

-- | M1 surface-WRITE and M1.5 surface-READ tests for the event-sourced ledger.
--
-- The WRITE half (@RECORD@ / @COMMIT@ / @ATTEST@ → the 'Record' AST node)
-- proves the whole write path — parse, typecheck, eval, ledger append:
--
--   (a) @RECORD \`x\` IS 273.15@ parses to a 'Record' node (isOfficial = False);
--   (b) it type-checks (the cell is a STRING path; the whole expression has the
--       type of the written value, so it can chain in a HENCE continuation);
--   (c) it evaluates to 273.15 (the written value is returned);
--   (d) the ledger afterwards contains @Assign ["x"] 273.15 _@, observed via the
--       'currentLedger' test seam after a forward-eval of the resolved node.
--
-- A @COMMIT@ variant asserts that the official/own distinction is recorded
-- (faithfully stored on the node as isOfficial = True and surfaced in the
-- provenance source as "COMMIT", ready for the M4 own/official ledger split).
--
-- The READ half (@RECALL@ → the 'ReadCell' AST node) proves the read path
-- end-to-end (M1.5):
--
--   (1) after @RECORD \`x\` IS 273.15@, @RECALL \`x\`@ evaluates to @JUST 273.15@;
--   (2) @RECALL \`missing\`@ evaluates to @NOTHING@;
--   (3) ISOLATION: a @RECALL@ evaluated in a FRESH directive/ledger, after a
--       write in a SEPARATE directive, returns @NOTHING@ — proving that
--       'withFreshLedger' still isolates per-directive (the M0 invariant).
--
-- Tests (1) and (2) drive the write and the read through the 'evalExprForLedger'
-- seam in ONE 'runEvalAction' (sharing one 'EvalState'/ledger, so no
-- 'withFreshLedger' wipes between them). Test (3) drives both directives through
-- 'execEvalModuleWithEnv', which wraps every directive in 'withFreshLedger'.
module RecordLedgerSpec (spec) where

import qualified Data.Map.Strict as Map
import qualified Data.Text as Text

import L4.API.VirtualFS (vfsFromList, checkWithImports)
import L4.Import.Resolution (TypeCheckWithDepsResult (..))
import L4.Syntax
  ( Directive (..)
  , Expr (..)
  , Module (..)
  , RecallMode (..)
  , Resolved
  , Section (..)
  , TopDecl (..)
  , getUnique
  )
import L4.Evaluate.Ledger
  ( LedgerEvent (..)
  , LedgerStore (..)
  , Provenance (..)
  , readCellAll
  , snapshot
  )
import L4.Evaluate.ValueLazy (NF (..), Value (..), WHNF)
import L4.EvaluateLazy
  ( EvalDirectiveResult (..)
  , EvalDirectiveValue (..)
  , currentLedger
  , currentStore
  , evalExprForLedger
  , evalExprForLedgerWithEnv
  , moduleEnvForLedger
  , execEvalModuleWithEnv
  , prettyEvalDirectiveResult
  , resolveEvalConfig
  , runEvalAction
  )
import L4.EvaluateLazy.Machine (emptyEnvironment)
import qualified L4.TypeCheck as TypeCheck
import L4.TracePolicy (apiDefaultPolicy)

import Data.Time (UTCTime (..), fromGregorian, secondsToDiffTime)
import Test.Hspec

-- A fixed time keeps evaluation deterministic.
fixedNow :: UTCTime
fixedNow = UTCTime (fromGregorian 2026 1 1) (secondsToDiffTime 0)

-- | Collect every directive body expression from a typechecked module,
-- recursing into nested sections.
directiveExprs :: Module Resolved -> [Expr Resolved]
directiveExprs (MkModule _ _ sec) = goSection sec
  where
    goSection (MkSection _ _ _ decls) = concatMap goDecl decls
    goDecl (Directive _ (LazyEval _ e))      = [e]
    goDecl (Directive _ (LazyEvalTrace _ e)) = [e]
    goDecl (Section _ s)                     = goSection s
    goDecl _                                 = []

-- | The single 'Record' node we expect from a one-directive module.
theRecord :: Module Resolved -> Maybe (Expr Resolved, Expr Resolved, Bool)
theRecord m = case directiveExprs m of
  [Record _ _mParty cell val isOfficial _mHence] -> Just (cell, val, isOfficial)
  _                                       -> Nothing

-- 'WHNF'/'NF' have no 'Eq' (they carry IORef thunks), so we compare via Show.
showVal :: WHNF -> String
showVal = show

-- | Is this WHNF a @JUST _@ (the prelude MAYBE constructor)?
isJustWHNF :: WHNF -> Bool
isJustWHNF (ValConstructor r [_]) = getUnique r == TypeCheck.justUnique
isJustWHNF _                      = False

-- | Is this WHNF the empty list (@ValNil@)? @RECALL ALL@ on a never-written
-- cell yields @[]@ (NOT @NOTHING@) — the deliberate difference from plain RECALL.
isNilWHNF :: WHNF -> Bool
isNilWHNF ValNil = True
isNilWHNF _      = False

-- | Is this WHNF a @NOTHING@ (the prelude MAYBE constructor)?
isNothingWHNF :: WHNF -> Bool
isNothingWHNF (ValConstructor r []) = getUnique r == TypeCheck.nothingUnique
isNothingWHNF _                     = False

-- | Is this fully-forced NF a @NOTHING@?
isNothingNF :: NF -> Bool
isNothingNF (MkNF (ValConstructor r [])) = getUnique r == TypeCheck.nothingUnique
isNothingNF _                            = False

-- | Is this fully-forced NF a @ValBreached@ (i.e. a deontic BREACH)?
isBreachedNF :: NF -> Bool
isBreachedNF (MkNF (ValBreached _)) = True
isBreachedNF _                      = False

spec :: Spec
spec = describe "STATE-AS-LEDGER: RECORD/COMMIT/ATTEST (M1 write) + RECALL (M1.5 read)" $ do
  cfg <- runIO (resolveEvalConfig (Just fixedNow) apiDefaultPolicy)

  let src isOfficialKw =
        (if isOfficialKw then "#EVAL COMMIT `x` IS 273.15\n"
                         else "#EVAL RECORD `x` IS 273.15\n")
      vfs = vfsFromList []

  describe "RECORD (own ledger)" $ do
    it "(b) type-checks, and (a) parses to a Record node with isOfficial = False" $
      case checkWithImports vfs (src False) of
        Left errs -> expectationFailure ("expected a clean typecheck, got: " <> show errs)
        Right r ->
          case theRecord r.tcdModule of
            Nothing -> expectationFailure "expected exactly one Record directive node"
            Just (_cell, _val, isOfficial) -> isOfficial `shouldBe` False

    it "(c) evaluates to 273.15 (the written value is returned)" $
      case checkWithImports vfs (src False) of
        Left errs -> expectationFailure ("typecheck failed: " <> show errs)
        Right r -> do
          (_, results) <- execEvalModuleWithEnv cfg r.tcdEntityInfo emptyEnvironment r.tcdModule
          case results of
            [res] -> case res.result of
              Reduction (Right (MkNF (ValNumber n))) -> n `shouldBe` (5463 / 20)  -- 273.15
              other -> expectationFailure ("expected 273.15, got: " <> show other)
            _ -> expectationFailure ("expected exactly one directive result, got " <> show (length results))

    it "(d) appends Assign [\"x\"] 273.15 to the ledger (source = RECORD), via the seam" $
      case checkWithImports vfs (src False) of
        Left errs -> expectationFailure ("typecheck failed: " <> show errs)
        Right r ->
          case directiveExprs r.tcdModule of
            [recordExpr] -> do
              res <- runEvalAction cfg (evalExprForLedger recordExpr >> currentLedger)
              case res of
                Left e -> expectationFailure ("unexpected Eval exception: " <> show e)
                Right ledger -> do
                  let snap = snapshot ledger
                  Map.size snap `shouldBe` 1
                  fmap showVal (Map.lookup ["x"] snap) `shouldBe` Just (showVal (ValNumber (5463 / 20)))
                  map provSource (provenances ledger) `shouldBe` ["RECORD"]
            other -> expectationFailure ("expected one Record directive, got " <> show (length other))

  describe "COMMIT (official record) records the own/official distinction" $ do
    it "parses to a Record node with isOfficial = True" $
      case checkWithImports vfs (src True) of
        Left errs -> expectationFailure ("typecheck failed: " <> show errs)
        Right r ->
          case theRecord r.tcdModule of
            Nothing -> expectationFailure "expected one Record node"
            Just (_cell, _val, isOfficial) -> isOfficial `shouldBe` True

    it "records source = COMMIT in the OFFICIAL ledger provenance, via the seam (M4 routing)" $
      case checkWithImports vfs (src True) of
        Left errs -> expectationFailure ("typecheck failed: " <> show errs)
        Right r ->
          case directiveExprs r.tcdModule of
            [recordExpr] -> do
              res <- runEvalAction cfg (evalExprForLedger recordExpr >> currentStore)
              case res of
                Left e -> expectationFailure ("unexpected Eval exception: " <> show e)
                Right store -> do
                  -- M4: a COMMIT routes to the official record, not an own ledger.
                  map provSource (provenances store.officialLedger) `shouldBe` ["COMMIT"]
                  -- and nothing landed in any own ledger.
                  null store.ownLedgers `shouldBe` True
            other -> expectationFailure ("expected one Record directive, got " <> show (length other))

  describe "RECALL (M1.5 read): MAYBE-typed cell read" $ do
    -- One module, two directives: the WRITE then the READ. We collect both
    -- resolved exprs and choose how to sequence them depending on the test.
    let writeThenReadSrc = "#EVAL RECORD `x` IS 273.15\n#EVAL RECALL `x`\n"
        readMissingSrc   = "#EVAL RECALL `missing`\n"

    it "parses RECALL to a ReadCell node and type-checks (cell : STRING ⇒ MAYBE a)" $
      case checkWithImports vfs readMissingSrc of
        Left errs -> expectationFailure ("expected a clean typecheck, got: " <> show errs)
        Right r ->
          case directiveExprs r.tcdModule of
            [ReadCell _ _mParty _isOfficial _mode _cell] -> pure ()
            other -> expectationFailure ("expected exactly one ReadCell directive, got: " <> show (length other))

    it "(1) after RECORD `x` IS 273.15, RECALL `x` evaluates to JUST 273.15 (shared ledger, via the seam)" $
      case checkWithImports vfs writeThenReadSrc of
        Left errs -> expectationFailure ("typecheck failed: " <> show errs)
        Right r ->
          case directiveExprs r.tcdModule of
            [writeExpr, readExpr] -> do
              -- Both run in ONE runEvalAction => one EvalState => one ledger.
              -- The read MUST see the prior write (no withFreshLedger between).
              res <- runEvalAction cfg $ do
                _ <- evalExprForLedger writeExpr        -- RECORD `x` IS 273.15
                readWHNF <- evalExprForLedger readExpr  -- RECALL `x`
                ledger <- currentLedger
                pure (readWHNF, ledger)
              case res of
                Left e -> expectationFailure ("unexpected Eval exception: " <> show e)
                Right (readWHNF, ledger) -> do
                  -- the read is JUST _ ...
                  isJustWHNF readWHNF `shouldBe` True
                  -- ... and the value it wraps is the 273.15 that was written
                  -- (the JUST payload is the very WHNF stored in the ledger).
                  let snap = snapshot ledger
                  fmap showVal (Map.lookup ["x"] snap)
                    `shouldBe` Just (showVal (ValNumber (5463 / 20)))
            other -> expectationFailure ("expected a write + a read directive, got " <> show (length other))

    it "(2) RECALL `missing` evaluates to NOTHING (never written, via the seam)" $
      case checkWithImports vfs readMissingSrc of
        Left errs -> expectationFailure ("typecheck failed: " <> show errs)
        Right r ->
          case directiveExprs r.tcdModule of
            [readExpr] -> do
              res <- runEvalAction cfg (evalExprForLedger readExpr)
              case res of
                Left e -> expectationFailure ("unexpected Eval exception: " <> show e)
                Right readWHNF -> isNothingWHNF readWHNF `shouldBe` True
            other -> expectationFailure ("expected one RECALL directive, got " <> show (length other))

    it "(3) ISOLATION: RECALL in a FRESH directive does NOT see a RECORD from an earlier directive (withFreshLedger)" $
      -- Two #EVAL directives in one module. execEvalModuleWithEnv runs each
      -- through nfDirective => withFreshLedger, so the read directive starts
      -- from an EMPTY ledger and must return NOTHING despite the prior write.
      case checkWithImports vfs writeThenReadSrc of
        Left errs -> expectationFailure ("typecheck failed: " <> show errs)
        Right r -> do
          (_, results) <- execEvalModuleWithEnv cfg r.tcdEntityInfo emptyEnvironment r.tcdModule
          case results of
            [writeRes, readRes] -> do
              -- the write directive still returns its written value ...
              case writeRes.result of
                Reduction (Right (MkNF (ValNumber n))) -> n `shouldBe` (5463 / 20)
                other -> expectationFailure ("write directive: expected 273.15, got " <> show other)
              -- ... but the read directive, isolated, sees NOTHING.
              case readRes.result of
                Reduction (Right nfVal) ->
                  isNothingNF nfVal `shouldBe` True
                other -> expectationFailure ("read directive: expected NOTHING, got " <> show other)
            _ -> expectationFailure ("expected exactly two directive results, got " <> show (length results))

  describe "CAF ISOLATION: a nullary def containing RECALL re-evaluates per directive" $ do
    -- The DECISIVE REPRO for the shared-CAF bug. 'reader' is a NULLARY top-level
    -- definition whose body performs an effectful RECALL. Because top-level defs
    -- are stored as shared Reference IORefs that the lazy evaluator memoizes in
    -- place on first force, a naive driver forces 'reader' ONCE (when directive 1
    -- evaluates 'recordThenRead', which writes `x` then chains into 'reader' and
    -- gets FULFILLED) and then SHARES that WHNF with directive 2's bare
    -- '#EVAL reader'. That is wrong: directive 2 runs against a FRESH (empty)
    -- ledger (withFreshLedger), so its RECALL `x` is NOTHING and the CONSIDER must
    -- route to BREACH. The fix (fresh evaluation heap per directive) re-thunks the
    -- top-level defs before each directive so the CAF re-evaluates against that
    -- directive's own ledger. This guards against regressing to a shared forced CAF.
    let cafSrc = Text.unlines
          [ "IMPORT prelude"
          , "DECLARE Actor IS ONE OF P"
          , "DECLARE Action IS ONE OF act"
          , "GIVETH A DEONTIC Actor Action"
          , "reader MEANS"
          , "    CONSIDER RECALL `x`"
          , "    WHEN JUST v  THEN FULFILLED"
          , "    WHEN NOTHING THEN BREACH"
          , "GIVETH A DEONTIC Actor Action"
          , "recordThenRead MEANS RECORD `x` IS TRUE HENCE reader"
          , "#EVAL recordThenRead"   -- forces the 'reader' CAF (x present) => FULFILLED
          , "#EVAL reader"           -- fresh ledger, x absent => must be BREACH (NOT a cached FULFILLED)
          ]

    it "(4) the 2nd '#EVAL reader' BREACHES (fresh ledger), not a cached FULFILLED from the 1st directive" $
      case checkWithImports vfs cafSrc of
        Left errs -> expectationFailure ("typecheck failed: " <> show errs)
        Right r -> do
          (_, results) <- execEvalModuleWithEnv cfg r.tcdEntityInfo emptyEnvironment r.tcdModule
          case results of
            [firstRes, secondRes] -> do
              -- directive 1 (recordThenRead): writes `x`, reads it back, FULFILLED.
              case firstRes.result of
                Reduction (Right nf) -> do
                  isBreachedNF nf `shouldBe` False
                  prettyEvalDirectiveResult firstRes `shouldSatisfy` Text.isInfixOf "FULFILLED"
                other -> expectationFailure ("first directive: expected FULFILLED, got " <> show other)
              -- directive 2 (bare reader): isolated fresh ledger => RECALL is
              -- NOTHING => BREACH. The bug returned a cached FULFILLED here.
              case secondRes.result of
                Reduction (Right nf) -> isBreachedNF nf `shouldBe` True
                other -> expectationFailure ("second directive: expected a BREACH (ValBreached), got " <> show other)
            _ -> expectationFailure ("expected exactly two directive results, got " <> show (length results))

  describe "NOTIFY v1: recipient-qualified RECORD (cross-party WRITE, symmetric to cross-party RECALL)" $ do
    -- The IRREDUCIBLE CORE of NOTIFY: @RECORD q's <cell> IS v@ — the symmetric
    -- WRITE to @RECALL q's <cell>@. The acting party performs the write, but the
    -- value lands in the RECIPIENT's own ledger, keyed by the SAME 'partyKeyWHNF'
    -- that a cross-party RECALL reads — so write-key ≡ read-key BY CONSTRUCTION.
    --
    -- Module: two parties; a recipient-qualified write into Bob's ledger, then
    -- three reads collected as directive exprs and SEQUENCED IN ONE
    -- 'runEvalAction' (one EvalState / one ledger, so no 'withFreshLedger' wipes
    -- between them — the M4.5 cross-party-read seam, reused here for the write).
    let notifySrc = Text.unlines
          [ "IMPORT prelude"
          , "DECLARE Person IS ONE OF Alice, Bob"
          , "#EVAL RECORD Bob's `k` IS TRUE"   -- WRITE into Bob's own ledger (NOTIFY)
          , "#EVAL RECALL Bob's `k`"           -- recipient read: must be JUST TRUE
          , "#EVAL RECALL Alice's `k`"         -- another party: must be NOTHING (isolation)
          , "#EVAL RECALL `k`"                 -- bare/own read (acting party): must be NOTHING
          ]

    it "(N1) RECORD Bob's `k` IS TRUE parses to a Record node carrying a recipient qualifier (mParty = Just _)" $
      case checkWithImports vfs notifySrc of
        Left errs -> expectationFailure ("expected a clean typecheck, got: " <> show errs)
        Right r ->
          case directiveExprs r.tcdModule of
            (Record _ mParty _cell _val isOfficial _mHence : _) -> do
              -- the recipient qualifier is present, and it is an OWN write (a
              -- NOTIFY is RECORD, not COMMIT) — so isOfficial is False.
              case mParty of
                Just _  -> pure ()
                Nothing -> expectationFailure "expected a recipient qualifier (mParty = Just _) on the NOTIFY RECORD"
              isOfficial `shouldBe` False
            other -> expectationFailure ("expected a recipient-qualified Record first, got " <> show (length other) <> " directives")

    it "(N2) read-key ≡ write-key: RECALL Bob's `k` sees JUST; RECALL Alice's `k` and bare RECALL `k` see NOTHING; only Bob's own ledger got the write" $
      case checkWithImports vfs notifySrc of
        Left errs -> expectationFailure ("typecheck failed: " <> show errs)
        Right r ->
          case directiveExprs r.tcdModule of
            [writeExpr, readBobExpr, readAliceExpr, readBareExpr] -> do
              -- All FOUR directives run in ONE runEvalAction => one EvalState =>
              -- one ledger. The cross-party reads MUST see (or not see) the prior
              -- recipient-qualified write through the SHARED store. We evaluate
              -- against the MODULE env (so the `Bob`/`Alice` party constructors in
              -- the recipient/qualifier positions resolve) but WITHOUT
              -- withFreshLedger between directives (the shared-ledger seam).
              res <- runEvalAction cfg $ do
                menv     <- moduleEnvForLedger emptyEnvironment r.tcdModule
                _        <- evalExprForLedgerWithEnv menv writeExpr      -- RECORD Bob's `k` IS TRUE
                readBob  <- evalExprForLedgerWithEnv menv readBobExpr    -- RECALL Bob's `k`
                readAli  <- evalExprForLedgerWithEnv menv readAliceExpr  -- RECALL Alice's `k`
                readBare <- evalExprForLedgerWithEnv menv readBareExpr   -- RECALL `k`
                store    <- currentStore
                pure (readBob, readAli, readBare, store)
              case res of
                Left e -> expectationFailure ("unexpected Eval exception: " <> show e)
                Right (readBob, readAli, readBare, store) -> do
                  -- (i) the RECIPIENT read sees the write: JUST TRUE.
                  isJustWHNF readBob   `shouldBe` True
                  -- (ii) a DIFFERENT party's own ledger is isolated: NOTHING.
                  isNothingWHNF readAli `shouldBe` True
                  -- (iii) the ACTING party's bare/own read does NOT see it: the
                  -- write went to Bob's ledger, not the acting party's. NOTHING.
                  isNothingWHNF readBare `shouldBe` True
                  -- (iv) STRUCTURAL: exactly ONE own ledger received the write,
                  -- and it is keyed by the recipient (Bob) — NOT the anonymous
                  -- acting party "" and NOT Alice. The write's provenance records
                  -- the acting party (anonymous "") and source = NOTIFY, proving
                  -- the acting party performed it while it landed in Bob's inbox.
                  let nonEmpty = [ (key, l) | (key, l) <- Map.toList store.ownLedgers
                                            , not (null (foldr (:) [] l)) ]
                  length nonEmpty `shouldBe` 1
                  -- the single recipient key must NOT be the anonymous acting key.
                  map fst nonEmpty `shouldNotBe` [""]
                  -- and the routed write carries source = NOTIFY in its provenance.
                  case nonEmpty of
                    [(_recipientKey, recipientLedger)] ->
                      map provSource (provenances recipientLedger) `shouldBe` ["NOTIFY"]
                    _ -> expectationFailure "expected exactly one non-empty own ledger (the recipient's)"
            other -> expectationFailure ("expected write + three reads, got " <> show (length other) <> " directives")

  describe "RECALL ALL (approach B): collect-all read folds the WHOLE per-cell history into a LIST" $ do
    -- Approach B exposes the accumulation the append-only ledger ALREADY retains.
    -- Plain RECALL is last-write-wins (MAYBE a); RECALL ALL collects EVERY Assign
    -- to the cell into a LIST OF a, oldest->newest. No write-side change: each
    -- write is already its own event. These tests are LOAD-BEARING — they pin the
    -- grammar, the LIST (not MAYBE) typing, oldest->newest order, the empty-list
    -- (not NOTHING) behaviour, and — critically — that the RecallMode reaches BOTH
    -- evaluator frames (ReadCell1 for own/official, ReadCell2 for cross-party).

    it "(B0) RECALL ALL `c` parses to a ReadCell with RecallAll mode and type-checks as LIST OF a (not MAYBE a)" $
      case checkWithImports vfs "IMPORT prelude\n#EVAL RECALL ALL `c`\n" of
        Left errs -> expectationFailure ("expected a clean typecheck, got: " <> show errs)
        Right r ->
          case directiveExprs r.tcdModule of
            [ReadCell _ _mParty _isOfficial mode _cell] -> mode `shouldBe` RecallAll
            other -> expectationFailure ("expected one RECALL ALL ReadCell, got: " <> show (length other))

    it "(B1) a bare RECALL (no ALL) still parses to RecallLast — RECALL ALL is opt-in, plain RECALL is unchanged" $
      case checkWithImports vfs "IMPORT prelude\n#EVAL RECALL `c`\n" of
        Left errs -> expectationFailure ("typecheck failed: " <> show errs)
        Right r ->
          case directiveExprs r.tcdModule of
            [ReadCell _ _mParty _isOfficial mode _cell] -> mode `shouldBe` RecallLast
            other -> expectationFailure ("expected one plain RECALL ReadCell, got: " <> show (length other))

    -- NOTE on the harness: 'checkWithImports (vfsFromList [])' provides BUILT-IN
    -- bindings (LIST, RECORD/RECALL, arithmetic) but NOT the prelude.l4 runtime
    -- definitions (sum/count/fromMaybe-from-prelude). So these tests assert
    -- approach B WITHOUT prelude helpers: the writes go through the real
    -- evaluator (a LIST of RECORDs forces every write, left-to-right), and the
    -- collect-all behaviour is asserted via the 'readCellAll' PROJECTION over the
    -- captured ledger/store — i.e. the exact fold the runtime 'RECALL ALL' uses,
    -- read off the very ledger the evaluator wrote. The end-to-end runtime value
    -- of 'RECALL ALL' (a real ValCons/ValNil list) is covered by B0/B5 and the
    -- jl4/experiments/recall-all.l4 demo (run under the real prelude).

    it "(B2) OWN ledger, multi-write (ReadCell1 path): readCellAll folds ALL three writes oldest->newest; plain readCell is unchanged (JUST the last)" $
      -- Three writes as SEPARATE forced exprs sharing one ledger (the seam), then
      -- read the ledger back. readCellAll over the captured ledger is the
      -- collect-all projection; plain readCell (snapshot) is still last-write-wins.
      let writeSrc = Text.unlines
            [ "#EVAL RECORD `n` IS 10"
            , "#EVAL RECORD `n` IS 20"
            , "#EVAL RECORD `n` IS 30"
            ]
      in case checkWithImports vfs writeSrc of
        Left errs -> expectationFailure ("typecheck failed: " <> show errs)
        Right r ->
          case directiveExprs r.tcdModule of
            [w1, w2, w3] -> do
              res <- runEvalAction cfg $ do
                _ <- evalExprForLedger w1
                _ <- evalExprForLedger w2
                _ <- evalExprForLedger w3
                currentLedger
              case res of
                Left e -> expectationFailure ("unexpected Eval exception: " <> show e)
                Right ledger -> do
                  -- COLLECT-ALL: every write, oldest->newest.
                  map showVal (readCellAll ["n"] ledger)
                    `shouldBe` map (showVal . ValNumber) [10, 20, 30]
                  -- LAST-WRITE-WINS is unchanged: plain readCell sees only 30.
                  fmap showVal (Map.lookup ["n"] (snapshot ledger))
                    `shouldBe` Just (showVal (ValNumber 30))
            other -> expectationFailure ("expected three writes, got " <> show (length other))

    it "(B3) CROSS-PARTY, multi-write (ReadCell2 path — the silent-fallback trap): readCellAll over Bob's OWN ledger folds [1,2,3]; a never-written party (Alice) folds []" $
      -- THIS guards the design's highest-risk gap: the cross-party branch pushes
      -- ReadCell2 BEFORE finishRead, so a missing mode thread would SILENTLY fall
      -- back to last-write-wins with NO type error. We write `c` THREE times into
      -- Bob's own ledger (recipient-qualified RECORD), then assert the collect-all
      -- projection over Bob's ledger is the FULL [1,2,3] (a fallback would expose
      -- only the last). Alice's ledger, never written, folds to [].
      let crossSrc = Text.unlines
            [ "DECLARE Person IS ONE OF Alice, Bob"
            , "#EVAL RECORD Bob's `c` IS 1"
            , "#EVAL RECORD Bob's `c` IS 2"
            , "#EVAL RECORD Bob's `c` IS 3"
            ]
      in case checkWithImports vfs crossSrc of
        Left errs -> expectationFailure ("typecheck failed: " <> show errs)
        Right r ->
          case directiveExprs r.tcdModule of
            [w1, w2, w3] -> do
              res <- runEvalAction cfg $ do
                menv <- moduleEnvForLedger emptyEnvironment r.tcdModule
                _    <- evalExprForLedgerWithEnv menv w1
                _    <- evalExprForLedgerWithEnv menv w2
                _    <- evalExprForLedgerWithEnv menv w3
                currentStore
              case res of
                Left e -> expectationFailure ("unexpected Eval exception: " <> show e)
                Right store -> do
                  let bobLedger   = Map.findWithDefault mempty "Bob"   store.ownLedgers
                      aliceLedger = Map.findWithDefault mempty "Alice" store.ownLedgers
                  -- COLLECT-ALL across a DIFFERENT party's ledger: all three, in order.
                  map showVal (readCellAll ["c"] bobLedger)
                    `shouldBe` map (showVal . ValNumber) [1, 2, 3]
                  -- last-write-wins on Bob's ledger is still the last value only.
                  fmap showVal (Map.lookup ["c"] (snapshot bobLedger))
                    `shouldBe` Just (showVal (ValNumber 3))
                  -- a party that received no write folds to [].
                  readCellAll ["c"] aliceLedger `shouldSatisfy` null
            other -> expectationFailure ("expected three writes, got " <> show (length other))

    it "(B3b) CROSS-PARTY RECALL ALL evaluates end-to-end to a real list (ValCons), NOT a last-write-wins JUST — the ReadCell2 thread is live" $
      -- The runtime complement to B3: evaluate `RECALL ALL Bob's c` THROUGH the
      -- ReadCell2 cross-party frame and assert the value is a list head (ValCons),
      -- which a last-write-wins fallback (a ValConstructor JUST) could never be.
      let crossSrc = Text.unlines
            [ "DECLARE Person IS ONE OF Alice, Bob"
            , "#EVAL RECORD Bob's `c` IS 1"
            , "#EVAL RECORD Bob's `c` IS 2"
            , "#EVAL RECALL ALL Bob's `c`"
            ]
      in case checkWithImports vfs crossSrc of
        Left errs -> expectationFailure ("typecheck failed: " <> show errs)
        Right r ->
          case directiveExprs r.tcdModule of
            [w1, w2, readAllExpr] -> do
              res <- runEvalAction cfg $ do
                menv <- moduleEnvForLedger emptyEnvironment r.tcdModule
                _    <- evalExprForLedgerWithEnv menv w1
                _    <- evalExprForLedgerWithEnv menv w2
                evalExprForLedgerWithEnv menv readAllExpr   -- RECALL ALL Bob's `c`
              case res of
                Left e -> expectationFailure ("unexpected Eval exception: " <> show e)
                Right readWHNF -> do
                  -- a NON-EMPTY list (ValCons), not NOTHING and not a JUST.
                  isNilWHNF readWHNF     `shouldBe` False
                  isNothingWHNF readWHNF `shouldBe` False
                  case readWHNF of
                    ValCons _ _ -> pure ()
                    other -> expectationFailure ("expected a ValCons list head (cross-party RECALL ALL), got " <> show other)
            other -> expectationFailure ("expected 2 writes + 1 read, got " <> show (length other))

    it "(B4) OFFICIAL ledger, multi-write: readCellAll over the official record folds every COMMIT [5,7,9] oldest->newest" $
      let officialSrc = Text.unlines
            [ "#EVAL COMMIT `c` IS 5"
            , "#EVAL COMMIT `c` IS 7"
            , "#EVAL COMMIT `c` IS 9"
            ]
      in case checkWithImports vfs officialSrc of
        Left errs -> expectationFailure ("typecheck failed: " <> show errs)
        Right r ->
          case directiveExprs r.tcdModule of
            [w1, w2, w3] -> do
              res <- runEvalAction cfg $ do
                _ <- evalExprForLedger w1
                _ <- evalExprForLedger w2
                _ <- evalExprForLedger w3
                currentStore
              case res of
                Left e -> expectationFailure ("unexpected Eval exception: " <> show e)
                Right store ->
                  map showVal (readCellAll ["c"] store.officialLedger)
                    `shouldBe` map (showVal . ValNumber) [5, 7, 9]
            other -> expectationFailure ("expected three COMMITs, got " <> show (length other))

    it "(B5) EMPTY case: RECALL ALL on a never-written cell evaluates to [] (ValNil), NOT NOTHING" $
      case checkWithImports vfs "#EVAL RECALL ALL `never`\n" of
        Left errs -> expectationFailure ("typecheck failed: " <> show errs)
        Right r ->
          case directiveExprs r.tcdModule of
            [readExpr] -> do
              res <- runEvalAction cfg (evalExprForLedger readExpr)
              case res of
                Left e -> expectationFailure ("unexpected Eval exception: " <> show e)
                Right readWHNF -> do
                  isNilWHNF readWHNF     `shouldBe` True   -- it IS the empty list
                  isNothingWHNF readWHNF `shouldBe` False  -- and it is NOT NOTHING
            other -> expectationFailure ("expected one RECALL ALL directive, got " <> show (length other))

    it "(B6) NO KEYWORD CLASH: reusing the existing TKAll token leaves `FOR ALL` (forall types) and lowercase `all` (an ordinary identifier) parsing exactly as before" $
      -- 'RECALL ALL' reuses the SAME TKAll token as 'FOR ALL'. There is no clash:
      -- 'FOR ALL' needs a preceding TKFor in type position; 'RECALL ALL' needs a
      -- preceding TKRecall in expression position; and case-sensitivity keeps the
      -- lowercase identifier `all` distinct from the all-caps keyword. This module
      -- exercises all three in one file; it must type-check cleanly.
      let clashSrc = Text.unlines
            [ "ASSUME polymap IS"
            , "  FOR ALL a AND b"           -- forall type still parses (TKFor TKAll)
            , "  A FUNCTION FROM a TO b"
            , "GIVEN all IS A NUMBER"        -- lowercase `all` is an ordinary param name
            , "GIVETH A NUMBER"
            , "DECIDE twice all IS all TIMES 2"
            ]
      in case checkWithImports vfs clashSrc of
        Left errs -> expectationFailure ("expected FOR ALL + identifier `all` to still type-check, got: " <> show errs)
        Right _   -> pure ()

  where
    provenances ledger = [ p | Assign _ _ p <- foldr (:) [] ledger ]
    provSource p = p.source
