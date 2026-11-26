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
--
-- Where z3 gives no answer (a timeout, a failure to start, or its own
-- @unknown@), cvc5 is given the same script, if it is installed: @CVC5_EXE@
-- if set, else @cvc5@ on @PATH@ (smucclaw/l4-ide#1098). A z3 that starts and
-- then prints nothing it can read, a crash among them, is an encoding defect
-- as before, and cvc5 is not asked. Its answers are checked by the evaluator
-- as z3's are; without it, the run is z3's alone. @--solver@ chooses the
-- solvers and their order.
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
import L4.EvaluateLazy.Exceptions (isLimitStop, prettyEvalException, prettyRefusal)
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
    , "  Two solvers. z3 (Z3_EXE, else z3 on PATH) is asked first. Where it"
    , "  gives no answer (a timeout, or its own unknown), cvc5 (CVC5_EXE, else"
    , "  cvc5 on PATH) is given the same script and the same --timeout, if it"
    , "  is installed, and the row says which solver answered. Its answers are"
    , "  checked by the evaluator as z3's are, and output from it that cannot"
    , "  be read counts as no answer. Without cvc5, a last line counts any"
    , "  obligations z3 gave no answer to, which were not retried. A CVC5_EXE"
    , "  set to a file that does not exist stops the run, as a Z3_EXE does,"
    , "  even if z3 would have answered everything. --solver chooses the"
    , "  solvers and their order; a solver it names must be found. An"
    , "  obligation no solver answers takes up to --timeout per solver asked."
    , ""
    , "  Exit status: 0 every obligation proved; 1 the file, an option, z3 or a"
    , "  solver --solver names could not be used, or Z3_EXE or CVC5_EXE names"
    , "  a file that does not exist; 2 an obligation refuted, or an #ASSERT"
    , "  the evaluator itself found FALSE or that raised; 3 an obligation"
    , "  unknown and none of those; 4 an encoding defect."
    ]

----------------------------------------------------------------------------
-- Options
----------------------------------------------------------------------------

data ProveOptions = ProveOptions
  { proveFile     :: FilePath
  , proveTimeout  :: Int
  , proveEmitSmt  :: Maybe FilePath
  , proveSolvers  :: [SolverKind]
    -- ^ as given to @--solver@, in order; empty for the default
  , proveFixedNow :: FixedNowOpt
  , proveLimits   :: EvalLimits
  }

proveOptionsParser :: Parser ProveOptions
proveOptionsParser = ProveOptions
  <$> strArgument (metavar "FILE" <> help "Path to the .l4 file")
  <*> option auto
        ( long "timeout"
       <> metavar "SECONDS"
       <> value 10
       <> showDefault
       <> help "Give each solver this long per obligation; past it that solver has no answer, and the verdict is unknown (timeout) if no solver had one"
        )
  <*> optional
        ( strOption
            ( long "emit-smt"
           <> metavar "DIR"
           <> help "Write each obligation's SMT-LIB2 script to DIR and stop, without running a solver"
            )
        )
  <*> many
        ( option (eitherReader readSolverKind)
            ( long "solver"
           <> metavar "NAME"
           <> help "Ask this solver, z3 or cvc5; give two to ask both in that order, the second only where the first gave no answer (default: z3, then cvc5 if it is installed)"
            )
        )
  <*> fixedNowParser
  <*> evalLimitsParser

----------------------------------------------------------------------------
-- The solver (R-V6): text in, text out, behind one record
----------------------------------------------------------------------------

data Solver = Solver
  { solverName    :: Text
    -- ^ @z3@ or @cvc5@, as the report names it
  , solverVersion :: Text
  , solverRun     :: Int -> Text -> IO (Either Text Text)
    -- ^ seconds, script; 'Left' names a timeout or a crash
  }

-- | The solvers @l4 prove@ can ask (smucclaw/l4-ide#1098).
data SolverKind = Z3 | Cvc5
  deriving stock (Eq, Show)

kindName :: SolverKind -> Text
kindName = \case
  Z3 -> "z3"
  Cvc5 -> "cvc5"

-- | The variable that names a solver's executable.
kindEnv :: SolverKind -> Text
kindEnv = \case
  Z3 -> "Z3_EXE"
  Cvc5 -> "CVC5_EXE"

-- | How each solver is told to read SMT-LIB2 on standard input. cvc5 1.4.2
-- reads it so, and answers as it does given the script as a file (measured
-- 2026-11-25 on every script of the l4 prove fixtures). @--dag-thresh=0@
-- makes cvc5 print each model value in full: by default it abbreviates a
-- part that occurs twice with @let@, which 'liftModelValue' does not read,
-- so a counterexample whose two fields hold equal records was unknown. On
-- the 26 scripts of the l4 prove fixtures, the flag changes that one model
-- and no other byte of output (measured 2026-11-25).
kindArgs :: SolverKind -> [String]
kindArgs = \case
  Z3 -> ["-smt2", "-in"]
  Cvc5 -> ["--lang=smt2", "--dag-thresh=0"]

readSolverKind :: String -> Either String SolverKind
readSolverKind = \case
  "z3" -> Right Z3
  "cvc5" -> Right Cvc5
  other -> Left ("unknown solver " <> other <> ": the solvers are z3 and cvc5")

-- | Where a solver is: its variable first (a path that does not exist is a
-- hard failure, 'Left'), then its name on @PATH@ ('Right' 'Nothing' when it
-- is not there).
locateSolver :: SolverKind -> IO (Either Text (Maybe FilePath))
locateSolver k = do
  configured <- lookupEnv (Text.unpack (kindEnv k))
  case configured of
    Just p | not (null p) -> do
      ok <- doesFileExist p
      pure (if ok then Right (Just p) else Left (kindEnv k <> " is set to " <> Text.pack p <> ", which does not exist"))
    _ -> Right <$> findExecutable (Text.unpack (kindName k))

-- | Ask the solver at this path for its version, and wrap it.
openSolver :: SolverKind -> FilePath -> IO (Either Text Solver)
openSolver k exe = do
  r <- try (readProcessWithExitCode exe ["--version"] "")
  case r of
    Left (e :: IOException) -> pure (Left ("could not run " <> Text.pack exe <> ": " <> Text.pack (show e)))
    Right (_, out, _) -> pure $ Right Solver
      { solverName = kindName k
      , solverVersion = Text.strip (Text.pack (takeWhile (/= '\n') out))
      , solverRun = \secs script -> do
          -- the time limit is the driver's, not a solver option: the script
          -- stays portable (R-V6), and killing the process is solver-agnostic
          res <- timeout (secs * 1000000) (try (readProcessWithExitCode exe (kindArgs k) (Text.unpack script)))
          pure case res of
            Nothing -> Left ("timeout after " <> Text.pack (show secs) <> "s")
            Just (Left (e :: IOException)) -> Left ("the solver failed: " <> Text.pack (show e))
            Just (Right (_, out', _)) -> Right (Text.pack out')
      }

-- | @Z3_EXE@ first (a path that does not exist is a hard failure), then @z3@
-- on @PATH@.
findZ3 :: IO (Either Text Solver)
findZ3 = locateSolver Z3 >>= \case
  Left why -> pure (Left why)
  Right Nothing -> pure (Left "no SMT solver found: set Z3_EXE or put z3 on PATH")
  Right (Just exe) -> openSolver Z3 exe

-- | The solvers a run asks, in order: the first about every obligation, the
-- second only about those the first gave no answer to.
data Chain = Chain
  { chFirst  :: Solver
  , chSecond :: Maybe Second
  }

data Second = Second
  { scGet  :: IO (Either Text Solver)
    -- ^ the solver, found the first time it is needed; 'Left' says why it
    -- cannot be asked, in the words of the report's last line
  , scPeek :: IO (Maybe (Either Text Solver))
    -- ^ what 'scGet' found, without looking
  }

-- | The solvers for @--solver@'s list. Each named solver must be found. With
-- no @--solver@, z3 must be found and cvc5 is optional: it is looked for only
-- once an obligation needs it, so a run z3 answers starts no cvc5, but a
-- @CVC5_EXE@ that names nothing is a hard failure at once, as @Z3_EXE@'s is
-- (decided by Claude 2026-11-25, pending Meng's review).
resolveChain :: [SolverKind] -> IO (Either Text Chain)
resolveChain = \case
  [] -> do
    mz3 <- findZ3
    mcvc5 <- locateSolver Cvc5
    case (mz3, mcvc5) of
      (Left why, _) -> pure (Left why)
      (_, Left why) -> pure (Left why)
      (Right z3, Right mexe) -> do
        ref <- newIORef Nothing
        let find' = case mexe of
              Nothing -> pure (Left ("none found (set " <> kindEnv Cvc5 <> " or put cvc5 on PATH)"))
              Just exe -> first (\why -> "none (" <> why <> ")") <$> openSolver Cvc5 exe
            get' = readIORef ref >>= \case
              Just found -> pure found
              Nothing -> do
                found <- find'
                writeIORef ref (Just found)
                pure found
        pure (Right (Chain z3 (Just (Second get' (readIORef ref)))))
  kinds -> do
    found <- traverse named kinds
    pure case sequence found of
      Left why -> Left why
      Right (s : more) -> Right (Chain s (case more of
        (s2 : _) -> Just (Second (pure (Right s2)) (pure (Just (Right s2))))
        [] -> Nothing))
      Right [] -> Left "no solver was named"
 where
  named k = locateSolver k >>= \case
    Left why -> pure (Left why)
    Right Nothing -> pure (Left ("--solver " <> kindName k <> " was asked for, but no " <> kindName k
                                 <> " was found: set " <> kindEnv k <> " or put " <> kindName k <> " on PATH"))
    Right (Just exe) -> openSolver k exe

-- | A solver named twice in @--solver@'s list.
twiceNamed :: [SolverKind] -> Maybe SolverKind
twiceNamed ks = listToMaybe [ k | (k, n) <- [ (k, length (filter (== k) ks)) | k <- nub ks ], n > 1 ]

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
  , rowAsked  :: Maybe Asked
    -- ^ 'Nothing' for an #ASSERT no solver was asked about
  }

-- | The solvers an obligation reached, in the order asked: those that gave no
-- answer, with why, and then the one that answered, if one did, with what it
-- said (@sat@ or @unsat@).
data Asked = Asked
  { askedNoAnswer :: [(Text, Text)]
  , askedBy       :: Maybe (Text, Text)
  }

----------------------------------------------------------------------------
-- Entry point
----------------------------------------------------------------------------

proveCmd :: ProveOptions -> IO ()
proveCmd opts = do
  evalConfig <- withEvalLimits opts.proveLimits =<< makeEvalConfig opts.proveFixedNow
  guardRunStop "l4 prove" evalConfig (proveWith opts evalConfig)

-- | 'proveCmd' under the limits its flags set (ruled by Meng 2026-11-21, extending L2).
proveWith :: ProveOptions -> EvalConfig -> IO ()
proveWith opts evalConfig = do
  for_ (twiceNamed opts.proveSolvers) \k -> do
    Text.hPutStrLn stderr ("l4 prove: --solver " <> kindName k <> " is given twice")
    exitWith (ExitFailure 1)
  (errs, res) <- runOneshot evalConfig opts.proveFile \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    mtc <- Rules.useEvaluableTypeCheck uri
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
          mchain <- if needSolver then resolveChain opts.proveSolvers else pure (Left "")
          case mchain of
            Left why | needSolver -> do
              Text.hPutStrLn stderr ("l4 prove: " <> why)
              exitWith (ExitFailure 1)
            _ -> pure ()
          rows <- for lowered \(r, e, c) -> do
            (v, asked) <- case c of
              Left v -> pure (v, Nothing)
              Right ob -> case mchain of
                Right chain -> fmap Just <$> solve opts evalConfig tc importEnv chain r e ob
                Left _ -> pure (Unknown "no solver", Nothing)
            pure (Row r (oneLine (prettyLayout e)) v asked)
          let crossModule =
                nubOrd [ u | (_, _, Right ob) <- lowered, u <- Set.toList ob.obReached, not (Set.member u ownDecides) ]
              crossNames = [ Map.findWithDefault "?" u decideNames | u <- crossModule ]
          solverLines <- either (const (pure [])) (solverFooter rows) mchain
          Text.putStr (render opts rows refusedCount crossNames solverLines)
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
  -- A limit is not the evaluator's answer: it stopped before it had one
  -- (decided by Claude 2026-11-21, pending Meng's review: L2 extension, choice 2).
  Just (Assertion (Errored exc))
    | isLimitStop exc ->
        Left (Unknown ("the evaluator stopped at a limit before it could decide it: "
                       <> oneLine (Text.unlines (prettyEvalException exc))))
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

-- | What a solver's output says about an obligation.
data Reply
  = NoAnswer Text      -- ^ a timeout, a failure to start, @unknown@, and so on
  | Unreadable Text    -- ^ output that cannot be read: an encoding defect
  | GotUnsat
  | GotSat [SExpr]     -- ^ the @get-value@ pairs

-- | Read a solver's output. Strictness goes by the order asked, not by the
-- solver. The first solver asked, z3 unless @--solver@ says otherwise, is
-- read as strictly as z3 was before there was a second (smucclaw/l4-ide#1098):
-- output it cannot read is an encoding defect. A solver asked second is
-- asked only because the first gave no answer, so output from it that cannot
-- be read is no answer either, and never turns an unknown into a defect; only
-- its first expressions need parse, since what follows an @unsat@ is the
-- error a solver prints for the script's @get-value@. An answer from it that
-- the evaluator disagrees with is still a defect (decided by Claude
-- 2026-11-25, pending Meng's review).
readReply :: Bool -> Obligation -> Either Text Text -> Reply
readReply strict ob = \case
  Left why -> NoAnswer why
  Right txt ->
    let (exprs, stopped) = parseSExprsPrefix txt
        unreadable why later
          | strict = Unreadable why
          | otherwise = NoAnswer ("could not read its output: " <> later)
        shown = clip (oneLine txt)
    in case (stopped, exprs) of
      (Just perr, _) | strict -> Unreadable ("could not read the solver's output (" <> perr <> "): " <> oneLine txt)
      (_, answer : rest) -> case readCheckSat answer of
        Just CsUnsat -> GotUnsat
        Just CsUnknown -> NoAnswer (maybe "the solver said unknown" ("the solver said unknown; likely cause: " <>) ob.obNonLinear)
        Just CsSat -> case rest of
          (SList pairs : _) -> GotSat pairs
          _ -> unreadable ("the solver said sat but gave no values: " <> oneLine txt) ("it said sat but gave no values: " <> shown)
        Nothing -> unreadable ("unexpected solver output: " <> oneLine txt) shown
      (Nothing, []) -> unreadable "the solver printed nothing" "it printed nothing"
      (Just perr, []) -> unreadable perr ("(" <> perr <> ") " <> shown)
 where
  clip t = if Text.length t > 300 then Text.take 300 t <> " ..." else t

solve
  :: ProveOptions -> EvalConfig -> Rules.TypeCheckResult -> Environment -> Chain
  -> Maybe SrcRange -> Expr Resolved -> Obligation -> IO (Verdict, Asked)
solve opts evalConfig tc importEnv chain mr e ob = askSolver True chain.chFirst []
 where
  -- Ask one solver; on no answer, the next, with the same script and the
  -- whole --timeout. An obligation no solver answers is unknown for the
  -- first solver's reason, and the report adds the others'.
  askSolver isFirst solver gaveUp = do
    out <- solver.solverRun opts.proveTimeout (scriptText mr ob)
    let answered said v = (v, Asked gaveUp (Just (solver.solverName, said)))
    case readReply isFirst ob out of
      NoAnswer why -> next isFirst (gaveUp <> [(solver.solverName, why)])
      Unreadable why -> pure (answered "output that could not be read" (Defect why))
      GotUnsat -> answered "unsat" <$> sampleCheck
      GotSat pairs -> answered "sat" <$> replay pairs

  next wasFirst gaveUp = case chain.chSecond of
    Just sc | wasFirst -> sc.scGet >>= \case
      Right solver -> askSolver False solver gaveUp
      Left _ -> pure (noVerdict gaveUp)
    _ -> pure (noVerdict gaveUp)

  noVerdict gaveUp = (Unknown (maybe "no solver gave an answer" snd (listToMaybe gaveUp)), Asked gaveUp Nothing)

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
          EvStopped msg -> Unknown ("the solver says the assertion fails at " <> showBinding shown
                                    <> ", but the evaluator stopped at a limit there before it could say: " <> msg)

  -- unsat: the encoding says the assertion holds everywhere, so the evaluator
  -- must say TRUE at every point it is asked about. A point where it does not
  -- is an over-constrained encoding, which would otherwise prove everything.
  sampleCheck = do
    let points = samplePoints [ (fv, proofSampleValues ob fv.fvSort) | fv <- ob.obFree ]
    bad <- firstBad Nothing points
    pure case bad of
      Nothing -> Proved (length points)
      Just (shown, Right what) -> Defect ("the solver proved it, but at " <> showBinding shown <> " the evaluator " <> what)
      Just (shown, Left msg) -> Unknown ("the solver proved it, but at " <> showBinding shown
                                         <> " the evaluator stopped at a limit before it could check it: " <> msg)

  -- The first point the evaluator disagrees at. A point it stopped at is
  -- not a disagreement, so the check goes on past it, and reports the first
  -- such point only when no later one disagrees.
  firstBad stop [] = pure (fmap (fmap Left) stop)
  firstBad stop (p : ps) = do
    r <- evalAt p
    let shown = [ (fv.fvName, oneLine (prettyLayout (exactValue x))) | (fv, x) <- p ]
    case r of
      EvTrue -> firstBad stop ps
      EvStopped msg -> firstBad (maybe (Just (shown, msg)) Just stop) ps
      EvFalse -> pure (Just (shown, Right "says it is FALSE"))
      EvRaised msg -> pure (Just (shown, Right ("says it raises: " <> msg)))
      EvOther what -> pure (Just (shown, Right what))

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
        Reduction (ReducedErrored exc)
          | isLimitStop exc -> EvStopped (oneLine (Text.unlines (prettyEvalException exc)))
          | otherwise -> EvRaised (oneLine (Text.unlines (prettyEvalException exc)))
        Reduction (ReducedRefused r) -> EvOther ("refuses there: " <> oneLine (Text.unlines (prettyRefusal r)))
        Reduction (ReducedUndetermined _) -> EvOther "still cannot decide it there, so the lowering missed an input"
        Assertion _ -> EvOther "returned an assertion outcome for an expression"

-- | What the evaluator said at one point. 'EvStopped' is a limit (a count,
-- time or memory), which is not an answer about the assertion.
data EvalAt = EvTrue | EvFalse | EvRaised Text | EvOther Text | EvStopped Text

-- | At most 64 points of the product of the sample sets: all of it when it is
-- that small, otherwise a deterministic spread across it.
-- | The proof check's points: all of the product when it is at most 64;
-- otherwise first one point per position of the longest sample list, each
-- variable taking its own k-th value (so every sample value of every variable
-- appears at least once, the fractions that 'proofSampleValues' puts first
-- among them), then the deterministic spread, up to 64 in all.
samplePoints :: [(FreeVar, [Expr Resolved])] -> [[(FreeVar, Expr Resolved)]]
samplePoints vars
  | any (null . snd) vars = []
  | product [ toInteger (length xs) | (_, xs) <- vars ] <= 64 = samplePointsUpTo 64 vars
  | otherwise = take 64 (nubOrdOn key (diagonal <> samplePointsUpTo 64 vars))
 where
  diagonal =
    [ [ (fv, xs !! (k `mod` length xs)) | (fv, xs) <- vars ]
    | k <- [0 .. maximum [ length xs | (_, xs) <- vars ] - 1] ]
  key = map (prettyLayout . snd)

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

-- | The report's last lines about the solvers: the first one's version, as
-- before there was a second, and a line about the second only when an
-- obligation reached it, so that a run the first solver answers throughout
-- reads exactly as it did (decided by Claude 2026-11-25, pending Meng's
-- review).
solverFooter :: [Row] -> Chain -> IO [Text]
solverFooter rows chain = do
  let reached = length [ () | r <- rows, Just a <- [r.rowAsked], not (null a.askedNoAnswer) ]
      firstName = chain.chFirst.solverName
      obligations n = tshow n <> " obligation" <> (if n == 1 then "" else "s")
  secondLines <- case chain.chSecond of
    Just sc | reached > 0 -> flip fmap sc.scPeek \case
      Just (Right s) ->
        [ "second solver: " <> s.solverVersion <> ", asked where " <> firstName <> " gave no answer: " <> obligations reached ]
      Just (Left why) ->
        [ "second solver: " <> why <> ", so " <> obligations reached <> " " <> firstName <> " gave no answer to "
            <> (if reached == 1 then "was" else "were") <> " not retried" ]
      Nothing -> []
    _ -> pure []
  pure (("solver: " <> chain.chFirst.solverVersion) : secondLines)

render :: ProveOptions -> [Row] -> Int -> [Text] -> [Text] -> Text
render opts rows refusedCount crossNames solverLines =
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
    <> solverLines
 where
  renderRow r = verdictLines r <> map ("      " <>) (maybe [] (attribution r.rowResult) r.rowAsked)
  verdictLines r = case r.rowResult of
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
  -- Which solver answered, when it was not the first asked; or, when none
  -- did, the reasons of all but the first, whose reason is the verdict's.
  attribution v a = case (a.askedNoAnswer, a.askedBy) of
    ([], _) -> []
    (gaveUp, Just (by, said)) ->
      [ lead v by said <> " after "
          <> Text.intercalate "; " [ n <> " gave no answer: " <> why | (n, why) <- gaveUp ] ]
    (_ : later, Nothing) -> [ n <> ", asked next, gave no answer either: " <> why | (n, why) <- later ]
  -- An answer that leaves the verdict unknown (a model the evaluator cannot
  -- be given, or a limit it stopped at) settled nothing, so the row says
  -- what the solver said, and the line above it why that is no verdict.
  lead v by said = case v of
    Proved _ -> "proved by " <> by
    Refuted _ _ -> "refuted by " <> by
    Unknown _ -> by <> " said " <> said
    _ -> "answered by " <> by
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
