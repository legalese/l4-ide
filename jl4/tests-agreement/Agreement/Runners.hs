-- | Running a subject through l4, jl4-repl, jl4-lsp and the browser's
-- evaluator and planner, and reading what each gives.
module Agreement.Runners
  ( runText
  , runJson
  , runBatchCalls
  , runTrace
  , ReplRun (..)
  , runRepl
  , LspRun (..)
  , runLsp
  , runLspPlans
  , browserEval
  , browserEvalDirective
  , editorPlan
  , planSeenOfJson
  ) where

import Control.Monad (forM)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.ByteString.Lazy as LBS
import Data.Foldable (toList)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.Read as TR
import qualified Language.LSP.Protocol.Types as LSP
import System.FilePath ((</>))

import qualified L4.API as API
import qualified L4.Decision.EditorQueryPlan as EditorQueryPlan

import Agreement.Cli
import Agreement.Corpus
import Agreement.Lsp
import Agreement.Process
import Agreement.Verdict

-- | @l4 run@ on a file, read as text.
runText :: FilePath -> FilePath -> FilePath -> IO (Either String (Map.Map Int Seen))
runText l4 dir file = do
  (_, out, err) <- runIn dir l4 ["run", dir </> file] ""
  let seen = parseRunText out
  pure (if Map.null seen then Left (T.unpack (out <> err)) else Right seen)

-- | @l4 run --json@ on a file.
runJson :: FilePath -> FilePath -> FilePath -> IO (Either String (Map.Map Int Seen))
runJson l4 dir file = do
  (_, out, err) <- runIn dir l4 ["run", "--json", dir </> file] ""
  pure case parseRunJson out of
    Left e -> Left (e <> ": " <> T.unpack (out <> err))
    Right seen -> Right seen

-- | @l4 batch@ on the subject, once for each rule, a row for each of its
-- cases.
runBatchCalls :: FilePath -> FilePath -> FilePath -> Subject -> [Call] -> IO (Either String (Map.Map Int Seen))
runBatchCalls l4 dir rowsDir s calls = do
  perRule <- forM (zip [1 :: Int ..] s.rules) \(i, r) -> do
    let mine = [c | c <- calls, c.rule.name == r.name]
    res <- runBatch l4 dir s.file (rowsDir </> (T.unpack s.moduleName <> "-" <> show i <> ".json")) r.name [c.theCase.inputs | c <- mine]
    pure (zip (map (.line) mine) <$> res)
  pure (Map.fromList . concat <$> sequence perRule)

-- | @l4 trace@ on the file with an #EVALTRACE for each call: the outcome at
-- the root of each call's graph.
runTrace :: FilePath -> FilePath -> FilePath -> [Call] -> IO (Either String (Map.Map Int Seen))
runTrace l4 dir file calls = do
  (_, out, err) <- runIn dir l4 ["trace", dir </> file] ""
  let roots = parseDotRoots out
  pure
    if length roots /= length calls
      then Left ("graphs for " <> show (length roots) <> " of the calls: " <> T.unpack (T.take 4000 (out <> err)))
      else Right (Map.fromList (zipWith rootOf calls roots))
 where
  rootOf c (label, seen)
    | label == callLabel c = (c.line, seen)
    | otherwise = (c.line, SeenText ("a graph whose root is " <> label))

-- | How a trace labels a call: the rule's name, "OF", and its arguments.
callLabel :: Call -> T.Text
callLabel c = quoteName c.rule.name <> " OF " <> T.intercalate ", " c.args

data ReplRun = MkReplRun
  { eval :: Map.Map Int Seen
  , traceAscii :: Map.Map Int Seen
  , traceDot :: Map.Map Int Seen
  , plans :: Map.Map Int PlanSeen
  -- ^ by the index of the question; a question about a rule whose name has
  -- a space is not asked
  }

-- | jl4-repl with the subject loaded: each call, each call with
-- @:traceascii@ and with @:trace@, and @:queryplan@ for each question.
runRepl :: FilePath -> FilePath -> FilePath -> [Call] -> [PlanRow] -> IO ReplRun
runRepl repl home file calls rows = do
  let texts = map (.text) calls
      asked = [(i, row) | (i, row) <- zip [0 :: Int ..] rows, not (T.any (== ' ') row.rule.name)]
      planQuestion row = T.unwords ((":queryplan " <> row.rule.name) : [k <> "=" <> (if b then "true" else "false") | (k, b) <- row.bindings])
      queries = texts <> map (":traceascii " <>) texts <> map (":trace " <>) texts <> map (planQuestion . snd) asked
  replies <- replReplies home repl file queries
  let n = length calls
      (evals, rest1) = splitAt n replies
      (asciis, rest2) = splitAt n rest1
      (dots, planReplies) = splitAt n rest2
      byLine f xs = Map.fromList (zip (map (.line) calls) (map f xs))
  pure
    MkReplRun
      { eval = byLine replReply evals
      , traceAscii = byLine traceAsciiReply asciis
      , traceDot = byLine dotReply dots
      , plans = Map.fromList (zip (map fst asked) (map replPlan planReplies))
      }
 where
  dotReply t = case parseDotRoots t of
    [(_, seen)] -> seen
    _ -> SeenText t
  replPlan t = case T.stripPrefix "determined: " (T.takeWhile (/= '\n') t) of
    Just "True" -> Planned (Just True)
    Just "False" -> Planned (Just False)
    Just "Unknown" -> Planned Nothing
    _
      | "No query plan for " `T.isPrefixOf` t -> DeclinedText t
      | otherwise -> NoPlan t

data LspRun = MkLspRun
  { diagnostics :: Either String (Map.Map Int Seen)
  , directiveResult :: Either String (Map.Map Int Seen)
  , resultsUpdated :: Either String (Map.Map Int Seen)
  }

-- | jl4-lsp with the file open: the diagnostic it publishes for each
-- directive, with its severity, its l4/directiveResultsUpdated notification,
-- and its answer to l4/evalDirectiveResult at each directive, each with its
-- success.
runLsp :: FilePath -> FilePath -> [(Int, Int, T.Text)] -> IO LspRun
runLsp lsp absFile directives =
  withLspSession lsp absFile \sess -> do
    let n = length directives
        sameUri v = fmap LSP.toNormalizedUri (uriOf v) == Just (LSP.toNormalizedUri (LSP.Uri sess.uri))
        uriOf v = case objField v "params" >>= (`objField` "uri") of
          Just (Aeson.String u) -> Just (LSP.Uri u)
          _ -> Nothing
        evalDiagnostics v = case objField v "params" >>= (`objField` "diagnostics") of
          Just (Aeson.Array ds) -> [d | d <- toList ds, objField d "source" == Just "eval"]
          _ -> []
        isMethod m v = objField v "method" == Just (Aeson.String m)
        updates v = case objField v "params" >>= (`objField` "results") of
          Just (Aeson.Array rs) -> toList rs
          _ -> []
    mDiag <- awaitNotification sess \v -> isMethod "textDocument/publishDiagnostics" v && sameUri v && length (evalDiagnostics v) == n
    mUpd <- awaitNotification sess \v -> isMethod "l4/directiveResultsUpdated" v && sameUri v && length (updates v) >= n
    perDirective <- forM directives \(line, column, kind) -> do
      answer <- sess.request "l4/evalDirectiveResult" (Aeson.object
        [ "verDocId" Aeson..= Aeson.object ["uri" Aeson..= sess.uri, "version" Aeson..= (1 :: Int)]
        , "srcPos" Aeson..= Aeson.object ["line" Aeson..= line, "column" Aeson..= column]
        , "directiveType" Aeson..= kind
        ])
      pure (line, maybe (SeenText "no answer") (\a -> maybe (SeenText (T.pack (show a))) directiveSeen (objField a "result")) answer)
    pure
      MkLspRun
        { diagnostics = case mDiag of
            Nothing -> Left "no diagnostics for every directive"
            Just v -> Right (Map.fromList (map diagnosticSeen (evalDiagnostics v)))
        , directiveResult = Right (Map.fromList perDirective)
        , resultsUpdated = case mUpd of
            Nothing -> Left "no l4/directiveResultsUpdated with every directive"
            Just v -> Right (Map.fromList [r | Just r <- map updateSeen (updates v)])
        }
 where
  diagnosticSeen d =
    let line = maybe 0 (+ 1) (intAt d ["range", "start", "line"])
        message = case objField d "message" of
          Just (Aeson.String m) -> m
          _ -> ""
        severity = fromMaybe Aeson.Null (objField d "severity")
     in (line, SeenFlagged (Severity severity) (seenOfPretty (severity == Aeson.Number 1) message))
  directiveSeen r = case objField r "prettyText" of
    Just (Aeson.String t) -> withSuccess r t
    _ -> SeenText (T.pack (show r))
  updateSeen u = case (objField u "directiveId", objField u "prettyText") of
    (Just (Aeson.String i), Just (Aeson.String t))
      | Right (line, _) <- TR.decimal i ->
          Just (line, withSuccess u t)
    _ -> Nothing

-- | A directive's result as core prints it, with the success the object
-- that holds it gives, an absent one read as null.
withSuccess :: Aeson.Value -> T.Text -> Seen
withSuccess v t = SeenFlagged (Success success) (seenOfPretty (success == Aeson.Bool False) t)
 where
  success = fromMaybe Aeson.Null (objField v "success")

intAt :: Aeson.Value -> [T.Text] -> Maybe Int
intAt v = \case
  [] -> case v of
    Aeson.Number n -> Just (round n)
    _ -> Nothing
  k : ks -> objField v k >>= (`intAt` ks)

-- | jl4-lsp with the subject open: each question, asked as the decision
-- graph asks it, from the lens above the rule ("Show decision graph"), whose
-- command draws the graph, and then l4/queryPlan. A rule with no lens has no
-- plan.
runLspPlans :: FilePath -> FilePath -> Map.Map T.Text CoreRule -> [PlanRow] -> IO (Map.Map Int PlanSeen)
runLspPlans lsp absFile byName rows =
  withLspSession lsp absFile \sess -> do
    lensAnswer <- sess.request "textDocument/codeLens" (Aeson.object ["textDocument" Aeson..= Aeson.object ["uri" Aeson..= sess.uri]])
    let lenses = case lensAnswer >>= (`objField` "result") of
          Just (Aeson.Array ls) -> toList ls
          _ -> []
        lensAt line =
          [ args
          | l <- lenses
          , intAt l ["range", "start", "line"] == Just (line - 1)
          , Just cmd <- [objField l "command"]
          , objField cmd "command" == Just "l4.visualize"
          , Just (Aeson.Array args) <- [objField cmd "arguments"]
          ]
    fmap Map.fromList $ forM (zip [0 ..] rows) \(i, row) ->
      case Map.lookup row.rule.name byName >>= (.startLine) of
        Nothing -> pure (i, NoPlan "the rule is not in the module")
        Just line -> case lensAt line of
          [] -> pure (i, NoPlan "no lens draws the rule's decision graph")
          args : _ -> do
            _ <- sess.request "workspace/executeCommand" (Aeson.object ["command" Aeson..= ("l4.visualize" :: T.Text), "arguments" Aeson..= args])
            answer <- sess.request "l4/queryPlan" (Aeson.object
              [ "fnName" Aeson..= row.rule.name
              , "bindings" Aeson..= Aeson.object [(Key.fromText k, Aeson.Bool b) | (k, b) <- row.bindings]
              , "verDocId" Aeson..= fromMaybe Aeson.Null (case toList args of a : _ -> Just a; [] -> Nothing)
              ])
            pure (i, case answer of
              Nothing -> NoPlan "no answer"
              Just a -> case (objField a "result", objField a "error") of
                (Just r, _) | r /= Aeson.Null -> planSeenOfJson r
                (_, Just e) -> NoPlan (T.pack (show e))
                _ -> NoPlan (T.pack (show a)))

-- | A planner's JSON answer: a decline, a plan, or no plan.
planSeenOfJson :: Aeson.Value -> PlanSeen
planSeenOfJson v
  | objField v "kind" == Just "declined" = Declined v
  | Just d <- objField v "determined" = Planned (case d of Aeson.Bool b -> Just b; _ -> Nothing)
  | otherwise = NoPlan (T.pack (show v))

-- | L4.API's l4Eval on a text: the result of each directive, by its line,
-- with its severity and its success.
browserEval :: T.Text -> IO (Either String (Map.Map Int Seen))
browserEval src = do
  out <- API.l4Eval src
  pure case Aeson.decodeStrict (TE.encodeUtf8 out) >>= (`objField` "results") of
    Just (Aeson.Array rs) ->
      Right (Map.fromList [one r | r <- toList rs])
    _ -> Left (T.unpack out)
 where
  one r =
    let line = maybe 0 (+ 1) (intAt r ["range", "start", "line"])
        text = case objField r "result" of
          Just (Aeson.String t) -> t
          _ -> ""
     in (line, SeenFlagged (Severity (fromMaybe Aeson.Null (objField r "severity"))) (withSuccess r text))

-- | L4.API's l4EvalDirective on a text, at each directive.
browserEvalDirective :: T.Text -> [(Int, Int, T.Text)] -> IO (Either String (Map.Map Int Seen))
browserEvalDirective src directives = do
  seen <- forM directives \(line, column, kind) -> do
    out <- API.l4EvalDirective src line column kind
    pure case Aeson.decodeStrict (TE.encodeUtf8 out) of
      Just r | Just (Aeson.String t) <- objField r "prettyText" -> (line, withSuccess r t)
      _ -> (line, SeenText out)
  pure (Right (Map.fromList seen))

-- | The browser editor's planner on a text, for each question.
editorPlan :: T.Text -> [PlanRow] -> Map.Map Int PlanSeen
editorPlan src rows =
  Map.fromList
    [ (i, maybe (NoPlan answer) planSeenOfJson (Aeson.decodeStrict (TE.encodeUtf8 answer)))
    | (i, row) <- zip [0 ..] rows
    , let bindings = TE.decodeUtf8 (LBS.toStrict (Aeson.encode (Aeson.object [(Key.fromText k, Aeson.Bool b) | (k, b) <- row.bindings])))
          answer = EditorQueryPlan.l4QueryPlan src "file:///agreement.l4" (quoteName row.rule.name) bindings
    ]
