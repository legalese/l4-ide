-- | The agreement test: every surface that gives a verdict gives core's.
--
-- Core (L4.EvaluateLazy) owns what a program means. Each file of
-- jl4/examples/agreement is a small program that may refuse to answer, with
-- "agreement:" lines naming the verdict of each case: an answer, a refusal
-- and its reason, or an evaluation that raises. The test checks that core
-- gives each case that verdict, then runs every case through every surface
-- and checks that each gives core's verdict, in the surface's own wire
-- shape, and with the flag it writes beside a result, if it writes one, to
-- say whether the result succeeded. A query planner passes by declining a
-- rule that may refuse as core declines it, and otherwise by agreeing with
-- core or by leaving the answer open, never by answering differently.
--
-- The surfaces are the constructors of "Agreement.Surface", each run by a
-- function that matches on it with no wildcard, so a new constructor fails
-- the build until it has a runner. "Agreement.Registry" lists every door
-- through which a program of this repository gives a result, read from the
-- program or its source, so a new door fails this test until a row says
-- which surface it is, or why it gives no verdict.
module Main (main) where

import Control.Concurrent.MVar (modifyMVar, newMVar)
import Control.Monad (forM_, unless)
import qualified Data.Aeson as Aeson
import Data.List (sort, (\\))
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import qualified Data.Set as Set
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.ByteString as BS
import System.Directory (canonicalizePath, createDirectoryIfMissing, doesDirectoryExist, doesFileExist)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec

import L4.Refusal (declineMessage)

import Agreement.Corpus
import Agreement.Page
import Agreement.Process (locateBinary)
import Agreement.Registry
import Agreement.Runners
import Agreement.Service
import Agreement.Surface
import Agreement.Verdict

data Bins = MkBins
  { l4 :: Maybe FilePath
  , repl :: Maybe FilePath
  , lsp :: Maybe FilePath
  }

-- | A subject, with what core gives for it and the surfaces' runs, each
-- run at most once.
data Prep = MkPrep
  { subject :: Subject
  , origCore :: Either [T.Text] CoreRun
  -- ^ core on the subject as written
  , evalCore :: Either [T.Text] CoreRun
  -- ^ core on the subject with an #EVAL of each call after it
  , calls :: [Call]
  , rows :: [PlanRow]
  , evalDir :: FilePath
  , traceDir :: FilePath
  , origDir :: FilePath
  , rowsDir :: FilePath
  , replRun :: IO (Either String ReplRun)
  , lspRun :: IO (Either String LspRun)
  , lspPlans :: IO (Either String (Map.Map Int PlanSeen))
  , serviceRun :: IO (Either String ServiceRun)
  }

main :: IO ()
main = do
  inPackage <- doesDirectoryExist "examples/agreement"
  let (corpusDir, root) = if inPackage then ("examples/agreement", "..") else ("jl4/examples/agreement", ".")
  bins <- MkBins <$> locateBinary "L4_BIN" "jl4:exe:l4" <*> locateBinary "L4_REPL_BIN" "jl4-repl:exe:jl4-repl" <*> locateBinary "JL4_LSP_BIN" "jl4-lsp:exe:jl4-lsp"
  withSystemTempDirectory "l4-agreement" \tmp0 -> do
    tmp <- canonicalizePath tmp0
    (subjects, helpers, headerErrors) <- readCorpus corpusDir
    preps <- mapM (prepare bins tmp subjects helpers) subjects
    hspec (spec bins root helpers headerErrors preps)

-- | Run an action at most once, and give its result each time after.
once :: IO a -> IO (IO a)
once act = do
  var <- newMVar Nothing
  pure $ modifyMVar var \case
    Just a -> pure (Just a, a)
    Nothing -> do
      a <- act
      pure (Just a, a)

prepare :: Bins -> FilePath -> [Subject] -> [(FilePath, T.Text)] -> Subject -> IO Prep
prepare bins tmp subjects helpers s = do
  let vfs = [(T.pack (dropL4 f), src) | (f, src) <- helpers] <> [(x.moduleName, x.source) | x <- subjects]
      dropL4 f = take (length f - 3) f
      stem = T.unpack s.moduleName
      origDir = tmp </> "orig"
      evalDir = tmp </> "eval" </> stem
      traceDir = tmp </> "trace" </> stem
      rowsDir = tmp </> "rows"
  origCore <- runCore vfs s.moduleName s.source
  let givenOf = either (const Map.empty) (fmap (.givens) . (.rulesByName)) origCore
      calls = callsOf s givenOf
      rows = planRows s (either (const Map.empty) (.rulesByName) origCore)
      evalText = evalSource s calls
      traceText = traceSource s calls
  evalCore <- runCore vfs s.moduleName evalText
  forM_ [origDir, evalDir, traceDir, rowsDir] (createDirectoryIfMissing True)
  let corpusFiles = helpers <> [(x.file, x.source) | x <- subjects]
  forM_ [origDir, evalDir, traceDir] \d -> forM_ corpusFiles \(f, src) -> BS.writeFile (d </> f) (TE.encodeUtf8 src)
  BS.writeFile (evalDir </> s.file) (TE.encodeUtf8 evalText)
  BS.writeFile (traceDir </> s.file) (TE.encodeUtf8 traceText)
  let directives = case evalCore of
        Right c -> [(d.line, d.column, if isAssert s d.line then "#ASSERT" else "#EVAL") | d <- c.directives]
        Left _ -> []
      needs what = maybe (pure (Left ("found no " <> what <> " binary")))
  -- jl4-repl checks each input as a file in its working directory that holds
  -- the module's text, so it finds a file the module imports only when it
  -- runs in the module's directory: run elsewhere, it answers every input of
  -- boolean-rules.l4 "Failed to type check expression", with a REFUSE in the
  -- module or without one. So it runs in the module's directory.
  replRun <- once $ needs "jl4-repl" (\r -> Right <$> runRepl r origDir (origDir </> s.file) calls rows) bins.repl
  lspRun <- once $ needs "jl4-lsp" (\l -> Right <$> runLsp l (evalDir </> s.file) directives) bins.lsp
  lspPlans <- once $ needs "jl4-lsp" (\l -> Right <$> runLspPlans l (origDir </> s.file) (either (const Map.empty) (.rulesByName) origCore) rows) bins.lsp
  serviceRun <- once $ runService tmp s helpers calls rows
  pure MkPrep {subject = s, origCore, evalCore, calls, rows, evalDir, traceDir, origDir, rowsDir, replRun, lspRun, lspPlans, serviceRun}

spec :: Bins -> FilePath -> [(FilePath, T.Text)] -> [HeaderError] -> [Prep] -> Spec
spec bins root helpers headerErrors preps = do
  describe "the agreement corpus" do
    it "reads every \"agreement:\" line" do
      map show headerErrors `shouldBe` []

    it "imports each file that has no \"agreement:\" line into a subject" do
      let imported = Set.fromList (concat [c.imports | p <- preps, Right c <- [p.origCore]])
      [f | (f, _) <- helpers, T.pack (take (length f - 3) f) `Set.notMember` imported] `shouldBe` []

    -- An MCP tool call and a batch case evaluate a function returning
    -- DEONTIC with no start time and no events, and the service's doors
    -- give different verdicts for a function that does not return DEONTIC
    -- and has an input named, or listed by its MCP tool as, startTime,
    -- events or arguments: the two known limits that the commit "A refusal
    -- is a warning, has no verdict, and is one value at the service's
    -- doors" names, owned by McpServer, DataPlane's batch handler and its
    -- evalFunctionHandler. The corpus keeps clear of both.
    it "names no input startTime, events or arguments, and has no rule that answers DEONTIC or PROVISION" do
      let found =
            [ (p.subject.file, n)
            | p <- preps
            , Right c <- [p.origCore]
            , (n, r) <- Map.toList c.rulesByName
            , any (`elem` ["startTime", "events", "arguments"]) r.givens || r.returns `elem` [Just "DEONTIC", Just "PROVISION"]
            ]
      found `shouldBe` []

    forM_ preps \p -> describe p.subject.file do
      it "checks, as written and with a call of each case after it" do
        either (map T.unpack) (const []) p.origCore `shouldBe` []
        either (map T.unpack) (const []) p.evalCore `shouldBe` []

      it "has core give each case the verdict its line names" do
        core <- needCore p
        let verdicts = Map.fromList [(d.line, d.verdict) | d <- core.directives]
            bad =
              [ T.unpack c.theCase.header <> ": core gives " <> maybe "nothing" show v
              | c <- p.calls
              , let v = Map.lookup c.line verdicts
              , maybe True (not . expectAgrees c.theCase.expect) v
              ]
        bad `shouldBe` []

      it "has every #ASSERT of the file hold in core" do
        core <- needCore p
        [(d.line, d.verdict) | d <- core.directives, isAssert p.subject d.line, d.verdict /= CoreHolds] `shouldBe` []

      it "names each rule's inputs, pad aside, and every reason it may refuse with" do
        core <- needOrigCore p
        let bad = concat
              [ case Map.lookup r.name core.rulesByName of
                  Nothing -> [T.unpack r.name <> ": no such rule"]
                  Just cr ->
                    [T.unpack r.name <> ": has no input pad" | "pad" `notElem` cr.givens]
                      <> [ T.unpack c.header <> ": the inputs are " <> show (sort (cr.givens \\ ["pad"]))
                         | c <- r.cases
                         , sort (map fst c.inputs) /= sort (cr.givens \\ ["pad"])
                         ]
                      <> [ T.unpack r.name <> ": core reads the reasons " <> show cr.reasons
                         | fmap sort r.mayRefuse /= Just (sort cr.reasons)
                         ]
              | r <- p.subject.rules
              ]
        bad `shouldBe` []

      it "has a case for every assignment of a boolean rule's inputs" do
        core <- needOrigCore p
        let bad =
              [ T.unpack r.name
              | r <- p.subject.rules
              , Just cr <- [Map.lookup r.name core.rulesByName]
              , cr.boolean
              , sort [sort [(k, b) | (k, Aeson.Bool b) <- c.inputs] | c <- r.cases]
                  /= sort (map sort (boolAssignments (cr.givens \\ ["pad"])))
              ]
        bad `shouldBe` []

  describe "every surface gives core's verdict" do
    forM_ [minBound .. maxBound] \surface -> describe (show surface) do
      forM_ preps \p -> forM_ (evalRunner bins p surface) \run ->
        it p.subject.file do
          core <- needCore p
          let verdicts = Map.fromList [(d.line, d.verdict) | d <- core.directives]
              expected
                | readsDirectives surface = verdicts
                | otherwise = Map.filterWithKey (\l _ -> not (isAssert p.subject l)) verdicts
          results <- run
          unless (not (null results)) (expectationFailure "the surface has no door")
          forM_ results \(door, res) -> case res of
            Left e -> expectationFailure (T.unpack door <> ": " <> e)
            Right seen -> case disagreements expected seen of
              [] -> pure ()
              bad -> expectationFailure (unlines ((T.unpack door <> ":") : bad))

  describe "every query planner declines a rule as core does, or agrees with core" do
    forM_ [minBound .. maxBound] \surface -> describe (show surface) do
      forM_ preps \p -> forM_ (planRunner p surface) \run ->
        it p.subject.file do
          orig <- needOrigCore p
          core <- needCore p
          let answers = Map.fromList [(d.line, d.verdict) | d <- core.directives]
          results <- run
          forM_ results \(door, res) -> case res of
            Left e -> expectationFailure (T.unpack door <> ": " <> e)
            Right seen -> do
              let bad =
                    [ T.unpack door <> " " <> T.unpack row.rule.name <> " " <> show row.bindings <> ": " <> why
                    | (i, row) <- zip [0 ..] p.rows
                    , asks surface row
                    , Just why <- [judgePlan surface orig answers p.calls row (Map.lookup i seen)]
                    ]
              unless (null bad) (expectationFailure (unlines bad))

  describe "a surface's flag" do
    let flags =
          [Success Aeson.Null, Success (Aeson.Bool True), Success (Aeson.Bool False)]
            <> [Severity (Aeson.Number n) | n <- [1, 2, 3]]
            <> [IsError True, IsError False, HttpStatus 200, HttpStatus 422, HttpStatus 500]
        agreeing core seen = [f | f <- flags, agrees core (SeenFlagged f seen)]
    it "agrees with a refusal only as a null success, a warning, an MCP error, or a 422" do
      agreeing (CoreRefuses "r") (SeenRefused "r") `shouldBe` [Success Aeson.Null, Severity (Aeson.Number 2), IsError True, HttpStatus 422]
    it "agrees with an answer only as a success, information, an MCP result that is no error, or a 200" do
      agreeing (CoreAnswers "TRUE" (Aeson.Bool True) False) (SeenText "TRUE") `shouldBe` [Success (Aeson.Bool True), Severity (Aeson.Number 3), IsError False, HttpStatus 200]
    it "agrees with an evaluation that raises only as a failure, an error, an MCP error, or a 422" do
      agreeing (CoreRaises "boom") (SeenRaised "boom") `shouldBe` [Success (Aeson.Bool False), Severity (Aeson.Number 1), IsError True, HttpStatus 422]

  describe "the service's routing" do
    it "evaluates a call with a number for pad on its direct path, and one with {} through its wrapper" do
      let bad =
            [ (T.unpack c.theCase.header, pad, r)
            | p <- preps
            , c <- p.calls
            , (pad, wrapper) <- [(Aeson.Number 1, False), (Aeson.object [], True)]
            , let r = routesWrapper (c.theCase.inputs <> [("pad", pad)])
            , r /= Right wrapper
            ]
      bad `shouldBe` []

  describe "the registry of surfaces" do
    let fams = families root (fromMaybe "l4" bins.l4) serviceRoutes
    forM_ fams \fam -> it ("has a row for each of " <> T.unpack fam.title <> ", and for nothing else") do
      found <- fam.enumerate
      case found of
        Left e -> expectationFailure (T.unpack e)
        Right items -> do
          let rows = map fst fam.table
          (items \\ rows, rows \\ items) `shouldBe` ([], [])

    it "puts every surface behind a door" do
      let doors = concat [ss | fam <- fams, (_, Door ss) <- fam.table]
      [surfaceName s | s <- allSurfaces, s `notElem` doors] `shouldBe` []

    it "lists, in each row that sends to another list, a list that the registry has" do
      let titles = map (.title) fams
      [t | fam <- fams, (_, Listed t) <- fam.table, t `notElem` titles] `shouldBe` []

  -- The reference page for REFUSE says, in one table, what each surface
  -- shows for a refusal. Each surface's row is named in Agreement.Page.
  describe "the reference page for REFUSE" do
    let readRoot p = do
          let f = root </> p
          found <- doesFileExist f
          unless found (expectationFailure ("there is no " <> p))
          TE.decodeUtf8 <$> BS.readFile f
        pageRows = concat . pageTables <$> readRoot pagePath
        rowsOf rows s = [r | r@(c : _) <- rows, c == pageRow s]
        quotedIn rows s q = any (any (q `T.isInfixOf`)) (rowsOf rows s)

    it "has one table, with a row for each surface and no row for anything else" do
      tables <- pageTables <$> readRoot pagePath
      length tables `shouldBe` 1
      let firsts = [c | r <- concat tables, c : _ <- [r]]
          named = Set.toList (Set.fromList (map pageRow allSurfaces))
      (named \\ firsts, firsts \\ named) `shouldBe` ([], [])

    it "reads, in every row, a refusal and its reason, and no error" do
      rows <- pageRows
      let says w r = w `T.isInfixOf` T.toLower (T.unwords r)
      [r | r <- rows, not (says "refus" r) || not (says "reason" r) || says "error" r] `shouldBe` []

    it "quotes, in the row of each surface that prints a refusal as text, the text this test reads it by" do
      rows <- pageRows
      [ (surfaceName s, q)
        | s@(Eval _) <- allSurfaces
        , Just q <- [pageQuote "" s]
        , not (quotedIn rows s q)
        ]
        `shouldBe` []

    it "quotes, in the row of the query plan, the decline core gives the example's rule" do
      rows <- pageRows
      exampleSource <- readRoot examplePath
      core <- runCore [] "refuse-example" exampleSource
      decline <- case core of
        Left e -> fail ("core does not check the example: " <> show e)
        Right c -> case Map.lookup exampleRule c.rulesByName >>= (.decline) of
          Nothing -> fail ("core does not decline the example's rule " <> T.unpack exampleRule)
          Just d -> pure (declineMessage d)
      [ (surfaceName s, q)
        | s@(Plan _) <- allSurfaces
        , Just q <- [pageQuote decline s]
        , not (quotedIn rows s q)
        ]
        `shouldBe` []

needCore :: Prep -> IO CoreRun
needCore p = either (\e -> fail ("core does not check the subject with its calls: " <> show e)) pure p.evalCore

needOrigCore :: Prep -> IO CoreRun
needOrigCore p = either (\e -> fail ("core does not check the subject: " <> show e)) pure p.origCore

-- | Where core and a surface differ: a directive whose verdicts disagree, a
-- directive the surface gives nothing for, and a line where the surface
-- gives a verdict and core has no directive.
disagreements :: Map.Map Int CoreVerdict -> Map.Map Int Seen -> [String]
disagreements expected seen =
  [ "line " <> show l <> ": core " <> show v <> ", the surface " <> maybe "nothing" show s
  | (l, v) <- Map.toList expected
  , let s = Map.lookup l seen
  , maybe True (not . agrees v) s
  ]
    <> [ "line " <> show l <> ": the surface gives " <> show s <> ", where core has no directive"
       | (l, s) <- Map.toList seen
       , Map.notMember l expected
       ]

-- | Whether a surface reads every directive of a file, the subject's own
-- #ASSERTs among them, or only the calls it is given.
readsDirectives :: EvalSurface -> Bool
readsDirectives = \case
  RunText -> True
  RunJson -> True
  Batch -> False
  Trace -> False
  ReplEval -> False
  ReplTraceAscii -> False
  ReplTraceDot -> False
  ServiceDirect -> False
  ServiceWrapper -> False
  ServiceBatchDirect -> False
  ServiceBatchWrapper -> False
  McpDirect -> False
  McpWrapper -> False
  LspDiagnostics -> True
  LspDirectiveResult -> True
  LspDirectiveResultsUpdated -> True
  BrowserEval -> True
  BrowserEvalDirective -> True

-- | Run a surface on a subject: what it gives at each door, by line; or
-- Nothing where the surface does not run the subject. L4.API and the
-- browser editor's planner check a text with no file beside it, so they run
-- only the subjects that import nothing.
evalRunner :: Bins -> Prep -> EvalSurface -> Maybe (IO [(T.Text, Either String (Map.Map Int Seen))])
evalRunner bins p = \case
  RunText -> Just (withL4 \l -> runText l p.evalDir s.file)
  RunJson -> Just (withL4 \l -> runJson l p.evalDir s.file)
  Batch -> Just (withL4 \l -> runBatchCalls l p.origDir p.rowsDir s p.calls)
  Trace -> Just (withL4 \l -> runTrace l p.traceDir s.file p.calls)
  ReplEval -> Just (fromRepl (.eval))
  ReplTraceAscii -> Just (fromRepl (.traceAscii))
  ReplTraceDot -> Just (fromRepl (.traceDot))
  ServiceDirect -> Just (fromService ServiceDirect)
  ServiceWrapper -> Just (fromService ServiceWrapper)
  ServiceBatchDirect -> Just (fromService ServiceBatchDirect)
  ServiceBatchWrapper -> Just (fromService ServiceBatchWrapper)
  McpDirect -> Just (fromService McpDirect)
  McpWrapper -> Just (fromService McpWrapper)
  LspDiagnostics -> Just (fromLsp (.diagnostics))
  LspDirectiveResult -> Just (fromLsp (.directiveResult))
  LspDirectiveResultsUpdated -> Just (fromLsp (.resultsUpdated))
  BrowserEval -> importFree (one <$> browserEval evalText)
  BrowserEvalDirective -> importFree (one <$> browserEvalDirective evalText directives)
 where
  s = p.subject
  one r = [("", r)]
  withL4 k = maybe (pure (one (Left "found no l4 binary"))) (fmap one . k) bins.l4
  fromRepl f = one . fmap f <$> p.replRun
  fromLsp f = one . (>>= f) <$> p.lspRun
  fromService surface = do
    run <- p.serviceRun
    pure case run of
      Left e -> one (Left e)
      Right r -> Map.findWithDefault [] surface r.evals
  importFree act = if importsNothing p then Just act else Nothing
  evalText = evalSource s p.calls
  directives = case p.evalCore of
    Right c -> [(d.line, d.column, if isAssert s d.line then "#ASSERT" else "#EVAL") | d <- c.directives]
    Left _ -> []

importsNothing :: Prep -> Bool
importsNothing p = either (const False) (null . (.imports)) p.origCore

-- | Run a planner on a subject's questions: what it gives at each door, by
-- the index of the question.
planRunner :: Prep -> PlanSurface -> Maybe (IO [(T.Text, Either String (Map.Map Int PlanSeen))])
planRunner p = \case
  ServicePlan -> Just do
    run <- p.serviceRun
    pure case run of
      Left e -> [("", Left e)]
      Right r ->
        [ (door, Right (Map.fromList [(i, seen) | (d, i, seen) <- r.plans, d == door]))
        | door <- doorsOf (Plan ServicePlan)
        ]
  ReplPlan -> Just ((\r -> [("", fmap (.plans) r)]) <$> p.replRun)
  LspPlan -> Just ((\r -> [("", r)]) <$> p.lspPlans)
  EditorPlan ->
    if importsNothing p
      then Just (pure [("", Right (editorPlan p.subject.source p.rows))])
      else Nothing

-- | Whether a planner is asked a question. jl4-repl's :queryplan reads the
-- rule's name as the first word of what follows it (queryPlanCommand in
-- jl4-repl/app/Main.hs), so it cannot be asked about a rule whose name has
-- a space.
asks :: PlanSurface -> PlanRow -> Bool
asks surface row = case surface of
  ReplPlan -> not (T.any (== ' ') row.rule.name)
  ServicePlan -> True
  LspPlan -> True
  EditorPlan -> True

-- | What is wrong with a planner's answer to a question, if anything.
--
-- For a rule that core declines (it may refuse), the planner gives core's
-- decline: as JSON, or, in the REPL, as its sentence. The language server
-- has no decision graph, and so neither plan nor decline, for a rule that
-- does not answer a BOOLEAN (a known limit of the commit "Every query
-- planner declines a rule that may refuse, and core says why").
--
-- For a rule that core does not decline, a planner does not decline. A
-- plan that settles the answer gives the answer core gives on every case
-- that agrees with the inputs bound; a plan that leaves it open passes,
-- except where every input is bound for a rule whose line says it is
-- planned from its inputs, which keeps a planner that never settles an
-- answer from passing. A rule that does not answer a BOOLEAN may have no
-- plan.
judgePlan :: PlanSurface -> CoreRun -> Map.Map Int CoreVerdict -> [Call] -> PlanRow -> Maybe PlanSeen -> Maybe String
judgePlan surface orig answers calls row mSeen = case (Map.lookup row.rule.name orig.rulesByName, mSeen) of
  (Nothing, _) -> Just "core has no such rule"
  (_, Nothing) -> Just "the planner gave no answer"
  (Just cr, Just seen) -> case cr.decline of
    Just d -> case (surface, seen) of
      (ReplPlan, DeclinedText t) | t == declineMessage d -> Nothing
      (_, Declined v) | surface /= ReplPlan, v == Aeson.toJSON d -> Nothing
      (LspPlan, NoPlan _) | not cr.boolean -> Nothing
      _ -> Just ("core declines with " <> show (Aeson.toJSON d) <> ", the planner gives " <> show seen)
    Nothing -> case seen of
      Declined v -> Just ("core does not decline, the planner declines with " <> show v)
      DeclinedText t -> Just ("core does not decline, the planner declines with " <> show t)
      NoPlan t
        | cr.boolean -> Just ("the planner gives no plan: " <> T.unpack t)
        | otherwise -> Nothing
      Planned Nothing
        | row.rule.plannedFromInputs && fullyBound cr -> Just "every input is bound, and the plan leaves the answer open"
        | otherwise -> Nothing
      Planned (Just b) ->
        case [(c.theCase.header, v) | c <- calls, c.rule.name == row.rule.name, consistent c, let v = Map.lookup c.line answers, not (answersBool b v)] of
          [] -> Nothing
          bad -> Just ("the plan settles " <> show b <> ", where core gives " <> show bad)
 where
  consistent c = and [lookup k c.theCase.inputs == Just (Aeson.Bool b) | (k, b) <- row.bindings]
  fullyBound cr = not (null row.bindings) && sort (map fst row.bindings) == sort (cr.givens \\ ["pad"])
  answersBool b = \case
    Just (CoreAnswers _ (Aeson.Bool b') False) -> b == b'
    _ -> False
