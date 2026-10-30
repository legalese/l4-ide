-- | jl4-service, run in this process with a subject deployed: each of its
-- doors that gives a verdict, called through every route that reaches it.
module Agreement.Service
  ( ServiceRun (..)
  , runService
  , serviceRoutes
  , routesWrapper
  ) where

import Control.Concurrent.STM (newTVarIO)
import Control.Monad (forM)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString.Lazy as LBS
import Data.Foldable (toList)
import Data.List (nub)
import qualified Data.Map.Strict as Map
import Data.Proxy (Proxy (..))
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Network.HTTP.Client (Manager, RequestBody (..), defaultManagerSettings, httpLbs, method, newManager, parseRequest, requestBody, requestHeaders, responseBody, responseStatus)
import Network.HTTP.Types.Status (statusCode)
import Network.HTTP.Types.URI (urlEncode)
import Network.Wai.Handler.Warp (testWithApplication)
import Servant (Server, err501)
import Servant.Server.Internal (route)
import Servant.Server.Internal.Context (Context (EmptyContext))
import Servant.Server.Internal.Delayed (Delayed, emptyDelayed)
import Servant.Server.Internal.RouteResult (RouteResult (FailFatal))
import Servant.Server.Internal.Router (CaptureHint (..), RouterStructure (..), routerStructure)
import System.FilePath ((</>))
import System.IO (IOMode (..), withFile)

import Application (ServiceApi, app)
import Backend.Api (FnLiteral)
import Backend.Jl4 (requiresWrapperEvaluation)
import BundleStore (initStore)
import Compiler (compileBundle)
import Logging (newLoggerTo)
import Options (Options (..))
import Types (AppEnv (..), DeploymentId (..), DeploymentState (..))

import Agreement.Corpus
import Agreement.Registry (doorsOf)
import Agreement.Surface
import Agreement.Verdict

-- | What the service gave: for each surface, the verdict of each call on
-- each route that reaches it, by the call's line; and each planner question
-- put to each route of the query plan.
data ServiceRun = MkServiceRun
  { evals :: Map.Map EvalSurface [(T.Text, Either String (Map.Map Int Seen))]
  , plans :: [(T.Text, Int, PlanSeen)]
  -- ^ the route, the index of the question, and the answer
  }

-- | Every route of the service, as Servant reads its API: the path, with
-- each capture written as its name in braces.
serviceRoutes :: [T.Text]
serviceRoutes = nub (go [] structure)
 where
  structure = routerStructure (route (Proxy @ServiceApi) EmptyContext (emptyDelayed (FailFatal err501) :: Delayed () (Server ServiceApi)))
  go p = \case
    StaticRouterStructure m n -> ["/" <> T.intercalate "/" p | n > 0] <> concat [go (p <> [k]) s | (k, s) <- Map.toList m]
    CaptureRouterStructure hints s -> go (p <> ["{" <> T.intercalate "|" (nub [h.captureName | h <- hints]) <> "}"]) s
    RawRouterStructure -> ["/" <> T.intercalate "/" p <> " (raw)"]
    ChoiceStructure a b -> go p a <> go p b

-- | Whether the service evaluates a call with these inputs through its
-- generated wrapper rather than on its direct path.
routesWrapper :: [(T.Text, Aeson.Value)] -> Either String Bool
routesWrapper inputs = do
  lits <- forM inputs \(k, v) -> case Aeson.fromJSON v :: Aeson.Result FnLiteral of
    Aeson.Success l -> Right (k, Just l)
    Aeson.Error e -> Left e
  pure (requiresWrapperEvaluation lits)

serviceSurfaces :: [EvalSurface]
serviceSurfaces = [ServiceDirect, ServiceWrapper, ServiceBatchDirect, ServiceBatchWrapper, McpDirect, McpWrapper]

-- | The input `pad` for a surface: a number for the direct path, and {} for
-- the wrapper, which the service reads as UNCERTAIN.
padFor :: EvalSurface -> Aeson.Value
padFor s
  | s `elem` [ServiceWrapper, ServiceBatchWrapper, McpWrapper] = Aeson.object []
  | otherwise = Aeson.Number 1

-- | Deploy the subject, with the files it may import, and call every door.
runService :: FilePath -> Subject -> [(FilePath, T.Text)] -> [Call] -> [PlanRow] -> IO (Either String ServiceRun)
runService tmp s helpers calls rows = do
  let deployId = s.moduleName
      store = tmp </> "service-store" </> T.unpack deployId
  withFile (tmp </> ("service-" <> T.unpack deployId <> ".log")) WriteMode \h -> do
    logger <- newLoggerTo h False
    compiled <- compileBundle logger deployId (Map.fromList ((s.file, s.source) : helpers))
    case compiled of
      Left e -> pure (Left ("the service does not compile the subject: " <> T.unpack e))
      Right (fns, meta) -> do
        bundles <- initStore store
        registry <- newTVarIO (Map.singleton (DeploymentId deployId) (DeploymentReady fns meta))
        jobs <- newTVarIO Map.empty
        tasks <- newTVarIO Map.empty
        let env = MkAppEnv registry jobs bundles Nothing logger (options store) tasks
        mgr <- newManager defaultManagerSettings
        testWithApplication (pure (app env)) \port -> do
          let base = "http://127.0.0.1:" <> show port
          evals <- forM serviceSurfaces \surface -> do
            perRoute <- forM (doorsOf (Eval surface)) \r -> do
              res <- callSurface mgr base deployId surface r
              pure (r, res)
            pure (surface, perRoute)
          planned <- fmap concat $ forM (doorsOf (Plan ServicePlan)) \r ->
            forM (zip [0 ..] rows) \(i, row) -> do
              p <- askPlan mgr base (path r deployId row.rule.name) row.bindings
              pure (r, i, p)
          pure (Right MkServiceRun {evals = Map.fromList evals, plans = planned})
 where
  callSurface mgr base deployId surface r = case surface of
    ServiceDirect -> evaluateEach mgr base deployId surface r
    ServiceWrapper -> evaluateEach mgr base deployId surface r
    ServiceBatchDirect -> evaluateBatch mgr base deployId surface r
    ServiceBatchWrapper -> evaluateBatch mgr base deployId surface r
    McpDirect -> evaluateMcp mgr base deployId surface r
    McpWrapper -> evaluateMcp mgr base deployId surface r
    _ -> pure (Left (show surface <> " is not a door of the service"))

  argsOf surface c = Aeson.object [(Key.fromText k, v) | (k, v) <- c.theCase.inputs <> [("pad", padFor surface)]]

  evaluateEach mgr base deployId surface r = do
    seen <- forM calls \c -> do
      (st, body) <- post mgr (base <> T.unpack (path r deployId c.rule.name)) (Aeson.object ["arguments" Aeson..= argsOf surface c])
      pure (c.line, seenOfResponse st body)
    pure (Right (Map.fromList seen))

  evaluateBatch mgr base deployId surface r = do
    perRule <- forM s.rules \rule -> do
      let mine = [(i, c) | (i, c) <- zip [1 :: Int ..] calls, c.rule.name == rule.name]
          cases = [Aeson.Object (KeyMap.insert "@id" (Aeson.toJSON i) o) | (i, c) <- mine, Aeson.Object o <- [argsOf surface c]]
      (st, body) <- post mgr (base <> T.unpack (path r deployId rule.name)) (Aeson.object ["cases" Aeson..= cases, "outcomes" Aeson..= ([] :: [Aeson.Value])])
      pure case Aeson.decode body >>= field "cases" of
        Just (Aeson.Array rs) ->
          let byId = Map.fromList [(i, row) | row <- toList rs, Just (Aeson.Number n) <- [field "@id" row], let i = round n :: Int]
           in Right [(c.line, maybe (SeenText "no row for the case") seenOfBatchRow (Map.lookup i byId)) | (i, c) <- mine]
        _ -> Left ("status " <> show st <> ": " <> show body)
    pure (Map.fromList . concat <$> sequence perRule)

  evaluateMcp mgr base deployId surface r = do
    let url = base <> T.unpack (path r deployId "")
    (_, listed) <- post mgr url (rpc (1 :: Int) "tools/list" (Aeson.object []))
    let tools =
          Map.fromList
            [ (target, name)
            | Just (Aeson.Array ts) <- [Aeson.decode listed >>= field "result" >>= field "tools"]
            , t <- toList ts
            , Just (Aeson.String name) <- [field "name" t]
            , Just (Aeson.String desc) <- [field "description" t]
            , let target = T.dropEnd 1 (snd (T.breakOnEnd " [" desc))
            ]
    seen <- forM (zip [2 :: Int ..] calls) \(i, c) ->
      case Map.lookup (deployId <> "/" <> c.rule.name) tools of
        Nothing -> pure (c.line, SeenText ("no tool for " <> c.rule.name <> " in " <> TE.decodeUtf8Lenient (LBS.toStrict listed)))
        Just tool -> do
          (_, body) <- post mgr url (rpc i "tools/call" (Aeson.object ["name" Aeson..= tool, "arguments" Aeson..= argsOf surface c]))
          pure (c.line, seenOfToolResult body)
    pure (Right (Map.fromList seen))

  rpc :: Int -> T.Text -> Aeson.Value -> Aeson.Value
  rpc i m params = Aeson.object ["jsonrpc" Aeson..= ("2.0" :: T.Text), "id" Aeson..= i, "method" Aeson..= m, "params" Aeson..= params]

  askPlan mgr base url bindings = do
    (st, body) <- post mgr (base <> T.unpack url) (Aeson.object ["arguments" Aeson..= Aeson.object [(Key.fromText k, Aeson.Bool b) | (k, b) <- bindings]])
    pure case Aeson.decode body of
      Just v
        | st == 200, Just d <- field "determined" v -> Planned (case d of Aeson.Bool b -> Just b; _ -> Nothing)
        | Just "declined" <- field "kind" v -> Declined v
      _ -> NoPlan (T.pack (show st) <> " " <> TE.decodeUtf8Lenient (LBS.toStrict body))

-- | A route's path for the deployment and the rule.
path :: T.Text -> T.Text -> T.Text -> T.Text
path r deployId ruleName =
  T.replace "{deploymentId}" deployId (T.replace "{name}" (TE.decodeUtf8 (urlEncode False (TE.encodeUtf8 ruleName))) r)

options :: FilePath -> Options
options store =
  Options
    { port = 0
    , storePath = store
    , serverName = Nothing
    , lazyLoad = False
    , debug = False
    , maxZipSize = 2097152
    , maxFileCount = 5096
    , maxDeployments = 1024
    , maxConcurrentRequests = 20
    , maxEvalMemoryMb = 256
    , maxCompileMemoryMb = 512
    , evalTimeout = 60
    , compileTimeout = 60
    , instanceToken = Nothing
    }

post :: Manager -> String -> Aeson.Value -> IO (Int, LBS.ByteString)
post mgr url body = do
  req0 <- parseRequest url
  let req = req0 {method = "POST", requestBody = RequestBodyLBS (Aeson.encode body), requestHeaders = [("Content-Type", "application/json")]}
  resp <- httpLbs req mgr
  pure (statusCode (responseStatus resp), responseBody resp)

field :: T.Text -> Aeson.Value -> Maybe Aeson.Value
field k = \case
  Aeson.Object o -> KeyMap.lookup (Key.fromText k) o
  _ -> Nothing

-- | The evaluation endpoint's answer: a SimpleResponse, or an Error that is
-- a refusal or an error of the evaluator; with its HTTP status.
seenOfResponse :: Int -> LBS.ByteString -> Seen
seenOfResponse st body = case Aeson.decode body >>= seenOfSimple of
  Just seen -> SeenFlagged (HttpStatus st) seen
  Nothing -> SeenText (T.pack (show st) <> " " <> TE.decodeUtf8Lenient (LBS.toStrict body))

seenOfSimple :: Aeson.Value -> Maybe Seen
seenOfSimple v = case (field "tag" v, field "contents" v) of
  (Just "SimpleResponse", Just c) -> SeenJson <$> (field "result" c >>= field "value")
  (Just "Error", Just c)
    | Just "refused" <- field "kind" c, Just (Aeson.String r) <- field "reason" c -> Just (SeenRefused r)
    | Just (Aeson.String m) <- field "contents" c -> Just (SeenRaised m)
  _ -> Nothing

-- | A case of the batch endpoint's answer: a refusal, an error, or the
-- answer under a key of its own.
seenOfBatchRow :: Aeson.Value -> Seen
seenOfBatchRow row
  | Just r <- field "@refused" row, Just (Aeson.String reason) <- field "reason" r = SeenRefused reason
  | Just (Aeson.String e) <- field "@error" row = SeenRaised e
  | Aeson.Object o <- row
  , (_, v) : _ <- [(k, v) | (k, v) <- KeyMap.toList o, not ("@" `T.isPrefixOf` Key.toText k)] =
      SeenJson v
  | otherwise = SeenText (T.pack (show row))

-- | A tool call's answer: its text, which holds a SimpleResponse, a refusal
-- (a JSON object whose kind is "refused"), or, when the call is an error,
-- the error's text; with the result's isError.
seenOfToolResult :: LBS.ByteString -> Seen
seenOfToolResult body =
  case Aeson.decode body >>= field "result" of
    Just res
      | Just (Aeson.Array cs) <- field "content" res
      , c : _ <- toList cs
      , Just (Aeson.String t) <- field "text" c ->
          let isError = field "isError" res == Just (Aeson.Bool True)
              asJson = Aeson.decodeStrict (TE.encodeUtf8 t)
           in SeenFlagged (IsError isError) case asJson of
                Just v
                  | Just seen <- seenOfSimple v -> seen
                  | Just "refused" <- field "kind" v, Just (Aeson.String r) <- field "reason" v -> SeenRefused r
                _ | isError -> SeenRaised t
                  | otherwise -> SeenText t
    _ -> SeenText (TE.decodeUtf8Lenient (LBS.toStrict body))
