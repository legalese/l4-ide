{-# LANGUAGE PatternSynonyms #-}
-- | @l4 prove FILE@ — decide, with an SMT solver, the @#ASSERT@s the evaluator
-- cannot (VERIFICATION-BACKEND-LOWERING-SPEC, Phase 1).
--
-- An @#ASSERT@ that reads a section @GIVEN@ is a statement about every value
-- of it, so evaluation, which needs a value, cannot decide it: it reports
-- "assertion could not be evaluated". This command lowers each such assertion
-- to SMT-LIB2 ("L4.Prove.Lower"), asks a solver whether its negation has a
-- solution, and reports one of three verdicts (R-V8):
--
-- [@proved@] the negation is unsatisfiable: the assertion holds for every
--   value of what it reads, within the fragment.
-- [@refuted@] the solver found values at which it does not hold, and the
--   evaluator, run at those values, agrees (R-V5).
-- [@unknown@] with its reason: out of fragment, a timeout, or the solver's own
--   @unknown@.
--
-- and, outside the three, @ENCODING DEFECT@: the solver and the evaluator
-- disagree. That is a bug in this command, and it is reported as one rather
-- than resolved in either oracle's favour (R-V5): on @sat@, a model at which
-- the evaluator says the assertion holds; on @unsat@, a sample point at which
-- it does not.
--
-- The solver is a subprocess reading SMT-LIB2 text, never a library (R-V6):
-- @Z3_EXE@ if set, else @z3@ on @PATH@. A missing solver is a named failure,
-- because the verdicts were the thing asked for.
module L4.Cli.Prove
  ( ProveOptions (..)
  , proveOptionsParser
  , proveCmd
  , proveBound
  , Solver (..)
  , findZ3
  , samplePointsUpTo
  ) where

import Base
import qualified Base.Text as Text
import Control.Exception (IOException, try)
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Options.Applicative
import System.Directory (createDirectoryIfMissing, doesFileExist, findExecutable)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..), exitWith)
import System.FilePath (takeBaseName, (</>))
import System.Process (readProcessWithExitCode)
import System.Timeout (timeout)

import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import Language.LSP.Protocol.Types (normalizedFilePathToUri)

import L4.Annotation (emptyAnno, rangeOf)
import L4.Evaluate.ValueLazy (Environment, NF (..))
import L4.EvaluateLazy.Machine (pattern ValBool)
import L4.EvaluateLazy
  ( AssertionOutcome (..)
  , EvalConfig
  , EvalDirectiveResult (..)
  , EvalDirectiveValue (..)
  , ReductionOutcome (..)
  , execEvalExprInContextOfModule
  , prettyAssertionOutcome
  )
import L4.EvaluateLazy.Exceptions (prettyEvalException, prettyRefusal)
import L4.Export (AssumeRewrite (..), rewriteModuleAssumes)
import qualified L4.Dmn.Analysis as Safety
import L4.Parser.SrcSpan (SrcPos (..), SrcRange (..), prettySrcRange)
import L4.Print (prettyLayout)
import L4.Prove.Lower
import L4.Prove.Smt
import L4.Syntax
import qualified L4.TypeCheck as TC

import L4.Cli.Common

----------------------------------------------------------------------------
-- The honest bound
----------------------------------------------------------------------------

-- | What a run does and does not establish; the @--help@ footer.
proveBound :: String
proveBound =
  unlines
    [ "WHAT A VERDICT MEANS, AND WHAT IT DOES NOT"
    , ""
    , "  Only an #ASSERT the evaluator could not decide is sent to the solver:"
    , "  one that reads a section GIVEN (or an ASSUME) and therefore states"
    , "  something about every value of it. An #ASSERT the evaluator decided"
    , "  is listed with the evaluator's answer and is not proved again."
    , ""
    , "  `proved' is relative to the fragment: BOOLEAN, NUMBER (exact"
    , "  rationals), records and enumerations, IF / BRANCH / CONSIDER, the"
    , "  arithmetic and comparison operators, ROUND / FLOOR / CEILING (exact),"
    , "  and calls to other DECIDEs, which are unfolded. A point at which the"
    , "  assertion would RAISE (a division by zero, say) counts against it."
    , "  STRING, DATE, LIST, MAYBE, recursion, lambdas, transcendental"
    , "  functions and regulative rules are refused by name, as unknown."
    , ""
    , "  Every counterexample has been replayed through the evaluator, which"
    , "  agreed. Every proof has been spot-checked by the evaluator at up to"
    , "  64 sample points, fractions among them. A disagreement in either"
    , "  direction is printed as an ENCODING DEFECT: a bug in this command,"
    , "  not a fact about the rules."
    , ""
    , "  Not attempted: the well-definedness obligations R-V2 generates with no"
    , "  #ASSERT (every division, every CONSIDER), the #ASSERTs of imported"
    , "  files, and #ASSERT REFUSED. Decisions in other modules are unfolded"
    , "  but were not certified by the safety analysis, which sees only this"
    , "  module; the coverage line names them."
    , ""
    , "  Exit status: 0 every obligation proved; 1 the file, an option or the"
    , "  solver could not be used; 2 an obligation refuted, or an #ASSERT the"
    , "  evaluator itself found FALSE or that raised; 3 an obligation unknown"
    , "  and none of those; 4 an encoding defect."
    ]

----------------------------------------------------------------------------
-- Options
----------------------------------------------------------------------------

data ProveOptions = ProveOptions
  { proveFile     :: FilePath
  , proveTimeout  :: Int
  , proveEmitSmt  :: Maybe FilePath
  , proveFixedNow :: FixedNowOpt
  }

proveOptionsParser :: Parser ProveOptions
proveOptionsParser = ProveOptions
  <$> strArgument (metavar "FILE" <> help "Path to the .l4 file")
  <*> option auto
        ( long "timeout"
       <> metavar "SECONDS"
       <> value 10
       <> showDefault
       <> help "Give the solver this long per obligation; past it the verdict is unknown (timeout)"
        )
  <*> optional
        ( strOption
            ( long "emit-smt"
           <> metavar "DIR"
           <> help "Write each obligation's SMT-LIB2 script to DIR and stop, without running a solver"
            )
        )
  <*> fixedNowParser

----------------------------------------------------------------------------
-- The solver (R-V6): text in, text out, behind one record
----------------------------------------------------------------------------

data Solver = Solver
  { solverVersion :: Text
  , solverRun     :: Int -> Text -> IO (Either Text Text)
    -- ^ seconds, script; 'Left' names a timeout or a crash
  }

-- | @Z3_EXE@ first (a path that does not exist is a hard failure), then @z3@
-- on @PATH@.
findZ3 :: IO (Either Text Solver)
findZ3 = do
  configured <- lookupEnv "Z3_EXE"
  mexe <- case configured of
    Just p | not (null p) -> do
      ok <- doesFileExist p
      pure (if ok then Right p else Left ("Z3_EXE is set to " <> Text.pack p <> ", which does not exist"))
    _ -> maybe (Left "no SMT solver found: set Z3_EXE or put z3 on PATH") Right <$> findExecutable "z3"
  case mexe of
    Left why -> pure (Left why)
    Right exe -> do
      r <- try (readProcessWithExitCode exe ["--version"] "")
      case r of
        Left (e :: IOException) -> pure (Left ("could not run " <> Text.pack exe <> ": " <> Text.pack (show e)))
        Right (_, out, _) -> pure $ Right Solver
          { solverVersion = Text.strip (Text.pack (takeWhile (/= '\n') out))
          , solverRun = \secs script -> do
              -- the time limit is the driver's, not a z3 option: the script
              -- stays portable (R-V6), and killing the process is solver-agnostic
              res <- timeout (secs * 1000000) (try (readProcessWithExitCode exe ["-smt2", "-in"] (Text.unpack script)))
              pure case res of
                Nothing -> Left ("timeout after " <> Text.pack (show secs) <> "s")
                Just (Left (e :: IOException)) -> Left ("the solver failed: " <> Text.pack (show e))
                Just (Right (_, out', _)) -> Right (Text.pack out')
          }

----------------------------------------------------------------------------
-- Results
----------------------------------------------------------------------------

data Verdict
  = Proved Int                 -- ^ sample points the evaluator agreed at
  | Refuted [(Text, Text)] Text -- ^ the counterexample, and what the evaluator said there
  | Unknown Text
  | Defect Text
  | Decided Bool Text          -- ^ not an obligation: the evaluator's own answer,
                               -- and whether that answer fails the file (FALSE, or a raise)

data Row = Row
  { rowRange  :: Maybe SrcRange
  , rowText   :: Text
  , rowResult :: Verdict
  }

----------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------

proveCmd :: ProveOptions -> IO ()
proveCmd opts = do
  evalConfig <- makeEvalConfig opts.proveFixedNow
  (errs, res) <- runOneshot evalConfig opts.proveFile \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    mtc <- Shake.use Rules.SuccessfulTypeCheck uri
    meval <- Shake.use Rules.EvaluateLazy uri
    imports <- fromMaybe [] <$> Shake.use Rules.GetImports uri
    deps <- catMaybes <$> Shake.uses Rules.GetLazyEvaluationDependenciesFile (map (.moduleUri) imports)
    pure (mtc, meval, mconcat (map fst deps))
  -- The evaluator's own diagnostics include "assertion could not be evaluated"
  -- for every obligation, which is the question this command answers, so they
  -- are shown only when the file could not be checked at all.
  case res of
    (Nothing, _, _) -> putDiagnostics errs
    _ -> pure ()
  case res of
    (Just tc, Just evals, importEnv) -> do
      let mods = tc.module' : map (.module') (Rules.transitiveDependencies tc)
          env = mkProveEnv mods (tc.entityInfo <> foldMap (.entityInfo) (Rules.transitiveDependencies tc))
          directives = _foldNodeType (: []) tc.module' :: [Directive Resolved]
          asserts = [ (rangeOf ann, e) | Assert ann e <- directives ]
          refusedCount = length [ () | AssertRefused {} <- directives ]
          decideNames = Map.fromList
            [ (getUnique r, nameToText (getOriginal r))
            | m <- mods, MkDecide _ _ (MkAppForm _ r _ _) _ <- foldTopLevelDecides (: []) m ]
          outcomes = Map.fromList [ (r, d.result) | d <- evals, Just r <- [d.range] ]
          safety = safetyIssues tc
          ownDecides = Set.fromList [ getUnique r | MkDecide _ _ (MkAppForm _ r _ _) _ <- foldTopLevelDecides (: []) tc.module' ]
          MkModule _ entryUri _ = tc.module'
          lowered = [ (r, e, classify entryUri env outcomes safety r e) | (r, e) <- asserts ]
      case opts.proveEmitSmt of
        Just dir -> do
          let cannotWrite (e :: IOException) = do
                Text.hPutStrLn stderr ("l4 prove: cannot write the scripts to " <> Text.pack dir <> ": "
                                       <> oneLine (Text.pack (show e)))
                exitWith (ExitFailure 1)
          either cannotWrite pure =<< try (createDirectoryIfMissing True dir)
          -- Named by line AND column, since `;` puts two #ASSERTs on one line.
          -- A name this run has already written is a hard failure: a script
          -- silently overwritten is a question a second solver never sees.
          let targets = [ (dir </> (takeBaseName opts.proveFile <> "-" <> posOf r <> ".smt2"), r, ob)
                        | (r, _, Right ob) <- lowered ]
              clashes = [ f | (f, n) <- Map.toList (Map.fromListWith (+) [ (f, 1 :: Int) | (f, _, _) <- targets ]), n > 1 ]
          unless (null clashes) $ do
            Text.hPutStrLn stderr ("l4 prove: two obligations would be written to the same file, so neither was written: "
                                   <> Text.intercalate ", " (map Text.pack clashes))
            exitWith (ExitFailure 1)
          written <- for targets \(f, r, ob) -> do
            either cannotWrite pure =<< try (Text.writeFile f (scriptText r ob))
            pure f
          for_ written \f -> Text.putStrLn ("wrote " <> Text.pack f)
          Text.putStrLn (Text.pack (show (length written)) <> " obligation script(s) written; no solver was run")
        Nothing -> do
          needSolver <- pure (any (\(_, _, c) -> isRight' c) lowered)
          msolver <- if needSolver then findZ3 else pure (Left "")
          case msolver of
            Left why | needSolver -> do
              Text.hPutStrLn stderr ("l4 prove: " <> why)
              exitWith (ExitFailure 1)
            _ -> pure ()
          rows <- for lowered \(r, e, c) -> do
            v <- case c of
              Left v -> pure v
              Right ob -> case msolver of
                Right solver -> solve opts evalConfig tc importEnv solver r e ob
                Left _ -> pure (Unknown "no solver")
            pure (Row r (oneLine (prettyLayout e)) v)
          let crossModule =
                nubOrd [ u | (_, _, Right ob) <- lowered, u <- Set.toList ob.obReached, not (Set.member u ownDecides) ]
              crossNames = [ Map.findWithDefault "?" u decideNames | u <- crossModule ]
          Text.putStr (render opts rows refusedCount crossNames (either (const Nothing) (Just . (.solverVersion)) msolver))
          exitWith (exitFor rows)
    _ -> exitWith (ExitFailure 1)
 where
  isRight' = \case Right _ -> True; Left _ -> False
  posOf = maybe "0-0" (\rg -> show rg.start.line <> "-" <> show rg.start.column)

-- | Is this @#ASSERT@ an obligation, and if so, its lowering.
classify
  :: NormalizedUri -> ProveEnv -> Map SrcRange EvalDirectiveValue -> Map Unique [Safety.SafetyIssue]
  -> Maybe SrcRange -> Expr Resolved -> Either Verdict Obligation
classify entryUri env outcomes safety mr e = case outcome of
  Just (Assertion Holds) -> Left (Decided False "by evaluation: assertion satisfied")
  Just (Assertion Fails) -> Left (Decided True "by evaluation: assertion failed")
  Just (Assertion a@(FailsBecause _)) -> Left (Decided True ("by evaluation: " <> oneLine (prettyAssertionOutcome a)))
  -- a refusal is a designed outcome, exit 0, as under `l4 run`
  Just (Assertion (Refused r)) -> Left (Decided False ("by evaluation: refused: " <> oneLine (Text.unlines (prettyRefusal r))))
  -- An error that is not "waiting for an input" is the evaluator's answer
  -- whatever the assertion reads (R-V3: every other way of being stuck stays
  -- Errored), so it is not re-proved.
  Just (Assertion (Errored exc)) ->
    Left (Decided True ("not an obligation: the evaluator reports an error: "
                   <> oneLine (Text.unlines (prettyEvalException exc))))
  Just (Assertion _)
    | null reads' -> Left (Unknown "the evaluator could not decide it, and it reads no section GIVEN")
    | otherwise -> lowerChecked
  Just (Reduction _) -> Left (Unknown "the evaluator reported this #ASSERT as an #EVAL")
  Nothing -> Left (Unknown "the evaluator reported no result for this #ASSERT")
 where
  outcome = mr >>= \r -> Map.lookup r outcomes
  reads' = assumesReadBy env e
  lowerChecked = case lowerObligation env e of
    Left why -> Left (Unknown why)
    Right ob -> case (duplicateDeclarations ob.obCommands, refusalsIn ob <> importedBinders ob) of
      -- a duplicate binder is shadowed silently by the solver, so it is a
      -- defect in this command whatever the solver would answer
      (ds@(_ : _), _) -> Left (Defect ("the emitted script declares " <> Text.intercalate ", " ds <> " twice"))
      (_, why : _) -> Left (Unknown why)
      ([], []) -> Right ob
  -- The replay rebinds the entry module's ASSUMEs only, so a binder another
  -- module declares could not be given its model value: refuse it here
  -- rather than report the replay's failure as an encoding defect.
  importedBinders ob =
    [ "out of fragment: `" <> fv.fvName <> "` is a section GIVEN of an imported module"
    | fv <- ob.obFree, fv.fvUnique.moduleUri /= entryUri ]
  -- R-V4: analyzeSafety's clauses are side conditions where the lowering
  -- already encodes them as definedness (division, MODULO, a CONSIDER with no
  -- matching branch, and the TOTAL a caller inherits from one), and named
  -- refusals otherwise.
  refusalsIn ob =
    [ "out of fragment (" <> i.safClause <> "): " <> i.safDetail
    | u <- Set.toList ob.obReached
    , i <- Map.findWithDefault [] u safety
    , i.safClause `notElem` ["L1", "L3", "L4", "TOTAL"]
    ]

-- | 'Safety.analyzeSafety' over this module, with the checker's own
-- exhaustiveness warnings, extracted as @l4 export dmn@ extracts them.
safetyIssues :: Rules.TypeCheckResult -> Map Unique [Safety.SafetyIssue]
safetyIssues tc =
  Safety.analyzeSafety
    Safety.MkSafetyInput
      { Safety.siMissingRanges =
          [ r | e@(TC.MkCheckErrorWithContext (TC.CheckWarning (TC.PatternMatchesMissing _ _)) _) <- tc.infos
              , Just r <- [rangeOf e] ]
      , Safety.siClauseMatrixRanges =
          [ r | e@(TC.MkCheckErrorWithContext (TC.CheckWarning (TC.PatternClausesMissing {})) _) <- tc.infos
              , Just r <- [rangeOf e] ]
      , Safety.siNonexhaustive = Safety.nonexhaustiveDecides decides
      , Safety.siEnumFields = Map.empty
      , Safety.siComponentTypes = Map.empty
      , Safety.siSubst = tc.substitution
      , Safety.siUri = uri
      }
    (Safety.buildCallGraph decides (_foldNodeType (: []) tc.module') [])
    decides
 where
  decides = foldTopLevelDecides (: []) tc.module'
  MkModule _ uri _ = tc.module'

----------------------------------------------------------------------------
-- Solving, and the two-oracle check (R-V5)
----------------------------------------------------------------------------

scriptText :: Maybe SrcRange -> Obligation -> Text
scriptText mr ob =
  "; l4 prove: the negation of the #ASSERT at " <> maybe "?" prettySrcRange mr <> "\n"
    <> renderScript ob.obCommands

solve
  :: ProveOptions -> EvalConfig -> Rules.TypeCheckResult -> Environment -> Solver
  -> Maybe SrcRange -> Expr Resolved -> Obligation -> IO Verdict
solve opts evalConfig tc importEnv solver mr e ob = do
  out <- solver.solverRun opts.proveTimeout (scriptText mr ob)
  case out of
    Left why -> pure (Unknown why)
    Right txt -> case parseSExprs txt of
      Left perr -> pure (Defect ("could not read the solver's output (" <> perr <> "): " <> oneLine txt))
      Right (answer : rest) -> case readCheckSat answer of
        Just CsUnsat -> sampleCheck
        Just CsUnknown -> pure (Unknown (maybe "the solver said unknown" ("the solver said unknown; likely cause: " <>) ob.obNonLinear))
        Just CsSat -> case rest of
          (SList pairs : _) -> replay pairs
          _ -> pure (Defect ("the solver said sat but gave no values: " <> oneLine txt))
        Nothing -> pure (Defect ("unexpected solver output: " <> oneLine txt))
      Right [] -> pure (Defect "the solver printed nothing")
 where
  replay pairs = do
    let values = Map.fromList [ (unbar s, v) | SList [Atom s, v] <- pairs ]
        unbar = Text.dropAround (== '|')
        lifted = for ob.obFree \fv -> case Map.lookup (unbar fv.fvSymbol) values of
          Nothing -> Left ("the solver gave no value for " <> fv.fvName)
          Just v -> (fv,) <$> liftModelValue ob fv.fvSort v
    case lifted of
      Left why -> pure (Unknown why)
      Right binding -> do
        r <- evalAt binding
        let shown = [ (fv.fvName, oneLine (prettyLayout (exactValue x))) | (fv, x) <- binding ]
        pure case r of
          EvFalse -> Refuted shown "the evaluator agrees: the assertion is FALSE there"
          EvRaised msg -> Refuted shown ("the evaluator agrees: the assertion raises there: " <> msg)
          EvTrue -> Defect ("the solver says the assertion fails at " <> showBinding shown
                            <> ", but the evaluator says it holds there")
          EvOther what -> Defect ("the solver says the assertion fails at " <> showBinding shown
                                  <> ", but the evaluator " <> what)

  -- unsat: the encoding says the assertion holds everywhere, so the evaluator
  -- must say TRUE at every point it is asked about. A point where it does not
  -- is an over-constrained encoding, which would otherwise prove everything.
  sampleCheck = do
    let points = samplePoints [ (fv, proofSampleValues ob fv.fvSort) | fv <- ob.obFree ]
    bad <- firstBad points
    pure case bad of
      Nothing -> Proved (length points)
      Just (shown, what) -> Defect ("the solver proved it, but at " <> showBinding shown <> " the evaluator " <> what)

  firstBad [] = pure Nothing
  firstBad (p : ps) = do
    r <- evalAt p
    let shown = [ (fv.fvName, oneLine (prettyLayout (exactValue x))) | (fv, x) <- p ]
    case r of
      EvTrue -> firstBad ps
      EvFalse -> pure (Just (shown, "says it is FALSE"))
      EvRaised msg -> pure (Just (shown, "says it raises: " <> msg))
      EvOther what -> pure (Just (shown, what))

  -- Bind each ASSUME to its value by replacing it with a definition at its
  -- own address (as @l4 batch@ and the service do), then evaluate the
  -- assertion's expression once against that module.
  evalAt binding = do
    let byUnique = Map.fromList [ (fv.fvUnique, x) | (fv, x) <- binding ]
        bind (MkAssume _ tySig appForm@(MkAppForm _ r _ _) _ _) =
          case Map.lookup (getUnique r) byUnique of
            Nothing -> KeepAssume
            Just x -> ReplaceAssume (Decide emptyAnno (MkDecide emptyAnno tySig appForm x))
        bound = rewriteModuleAssumes bind tc.module'
    res <- execEvalExprInContextOfModule evalConfig tc.entityInfo e (importEnv, bound)
    pure case res of
      Nothing -> EvOther "returned no result"
      Just d -> case d.result of
        Reduction (Reduced (MkNF (ValBool True))) -> EvTrue
        Reduction (Reduced (MkNF (ValBool False))) -> EvFalse
        Reduction (Reduced _) -> EvOther "returned a value that is not BOOLEAN"
        Reduction (ReducedErrored exc) -> EvRaised (oneLine (Text.unlines (prettyEvalException exc)))
        Reduction (ReducedRefused r) -> EvOther ("refuses there: " <> oneLine (Text.unlines (prettyRefusal r)))
        Reduction (ReducedUndetermined _) -> EvOther "still cannot decide it there, so the lowering missed an input"
        Assertion _ -> EvOther "returned an assertion outcome for an expression"

data EvalAt = EvTrue | EvFalse | EvRaised Text | EvOther Text

-- | At most 64 points of the product of the sample sets: all of it when it is
-- that small, otherwise a deterministic spread across it.
samplePoints :: [(FreeVar, [Expr Resolved])] -> [[(FreeVar, Expr Resolved)]]
samplePoints = samplePointsUpTo 64

samplePointsUpTo :: Integer -> [(FreeVar, [Expr Resolved])] -> [[(FreeVar, Expr Resolved)]]
samplePointsUpTo limit vars
  | any (null . snd) vars = []
  | total <= limit = [ pick (mixedRadix k) | k <- [0 .. total - 1] ]
  | otherwise = nubOrdOn (map (prettyLayout . snd)) [ pick (spread k) | k <- [0 .. limit - 1] ]
 where
  sizes = [ toInteger (length xs) | (_, xs) <- vars ]
  total = product sizes
  pick ixs = [ (fv, xs !! fromInteger i) | ((fv, xs), i) <- zip vars ixs ]
  mixedRadix k = snd (mapAccumL (\q n -> (q `div` n, q `mod` n)) k sizes)
  spread k = [ (k * 7919 + toInteger j * 104729 + (k * k * 31)) `mod` n | (j, n) <- zip [0 :: Int ..] sizes ]

showBinding :: [(Text, Text)] -> Text
showBinding xs = Text.intercalate ", " [ n <> " = " <> v | (n, v) <- xs ]

oneLine :: Text -> Text
oneLine = Text.unwords . Text.words

----------------------------------------------------------------------------
-- The report
----------------------------------------------------------------------------

render :: ProveOptions -> [Row] -> Int -> [Text] -> Maybe Text -> Text
render opts rows refusedCount crossNames mversion =
  Text.unlines $
    [ "l4 prove: " <> Text.pack opts.proveFile ]
    <> concatMap renderRow rows
    <> [ coverage
       , "not attempted: well-definedness obligations generated without an #ASSERT (R-V2)"
           <> "; #ASSERTs in imported files"
           <> (if refusedCount > 0 then "; " <> tshow refusedCount <> " #ASSERT REFUSED" else "")
           <> (if null crossNames then ""
               else "; safety analysis of the imported decisions unfolded (" <> Text.intercalate ", " (map quote crossNames) <> ")")
       ]
    <> [ "solver: " <> v | Just v <- [mversion] ]
 where
  renderRow r = case r.rowResult of
    Proved n -> [ line "proved " <> "  (the evaluator agreed at " <> tshow n <> " sample point" <> plural n <> ")" ]
    Refuted cex said ->
      [ line "refuted"
      , "      counterexample: " <> showBinding cex
      , "      " <> said ]
    Unknown why -> [ line "unknown", "      " <> why ]
    Defect why -> [ line "ENCODING DEFECT", "      " <> why ]
    Decided _ what -> [ line "decided", "      " <> what ]
   where
    line verdict = "  " <> verdict <> "  " <> maybe "?" prettySrcRange r.rowRange <> "  #ASSERT " <> r.rowText
  coverage =
    "coverage: " <> tshow (length rows) <> " #ASSERT: "
      <> tshow decided <> " decided by evaluation, not re-proved; "
      <> tshow sent <> " obligation" <> plural sent <> ": "
      <> tshow proved <> " proved, " <> tshow refuted <> " refuted, " <> tshow unknown <> " unknown"
      <> (if defects > 0 then ", " <> tshow defects <> " ENCODING DEFECT" else "")
  decided = count \case Decided _ _ -> True; _ -> False
  proved  = count \case Proved _ -> True; _ -> False
  refuted = count \case Refuted _ _ -> True; _ -> False
  unknown = count \case Unknown _ -> True; _ -> False
  defects = count \case Defect _ -> True; _ -> False
  sent = proved + refuted + unknown + defects
  count p = length (filter (p . (.rowResult)) rows)
  plural n = if n == 1 then "" else "s"
  quote t = "`" <> t <> "`"

exitFor :: [Row] -> ExitCode
exitFor rows
  | has \case Defect _ -> True; _ -> False = ExitFailure 4
  | has \case Refuted _ _ -> True; _ -> False = ExitFailure 2
  -- an #ASSERT the evaluator itself found FALSE, or that raised, fails the
  -- file as a refutation does, so `l4 prove f && deploy` cannot pass it
  | has \case Decided True _ -> True; _ -> False = ExitFailure 2
  | has \case Unknown _ -> True; _ -> False = ExitFailure 3
  | otherwise = ExitSuccess
 where
  has p = any (p . (.rowResult)) rows

tshow :: Show a => a -> Text
tshow = Text.pack . show
