-- | The instance ledger's one MCP tool (OPERATIONAL-LOWERING-SPEC §3.3, §5,
-- §9 WPO4): "what may I do now, and what would it do".
--
-- It is registered in a wrapper in front of the MCP handler
-- ('withLedgerTool'), not inside it: a @tools/list@ goes to
-- "McpServer".'McpServer.mcpHandler' as before and the tool is added to its
-- answer, and a @tools/call@ naming the tool is answered here and never
-- reaches it. Every other request goes to it untouched. So the decision
-- tools' dispatch, and every line it calls, is as it was, and a service
-- whose ledger store cannot be opened answers its decision tools as it
-- always did.
--
-- The tool reads; it never appends (§5: an agent calling for Alice over
-- MCP evaluates the rule at knowledge time, and that evaluation is
-- advisory). It says the instance's position, the same answer as
-- @GET .../position@, and, given an act, what the ledger would do with it
-- if it arrived now: 'L4.Ledger.Append.appendIf' itself, run over a scratch
-- copy of the instance's rows, so the preview and the append are one
-- function by construction and disagree only about which head is current.
-- To act, an agent proposes the act on the instance's events route, naming
-- the head it decided against.
--
-- How it fails, sorted by whether the agent hears it: a deployment or
-- instance that is not there, or a store that cannot be opened, is a tool
-- error (@isError@), loud; an answer that has gone stale by the time the
-- agent acts is not an error at all, and is why the reply names its head
-- and says it is advisory. An agent that treats the preview as the append,
-- and buys on it without proposing, is design D1.
module Ledger.Mcp
  ( withLedgerTool
  , ledgerToolName
  , ledgerToolDefinition
  ) where

import Ledger
import Ledger.Service (LedgerService (..))
import Ledger.Store.Config (OpenedStore (..))
import Logging (logInfo)
import Types

import Control.Monad (forM_)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Reader (ask, runReaderT)
import Data.Aeson ((.=))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString.Lazy as LBS
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text.Encoding as Text.Encoding
import qualified Data.Vector as Vector
import Servant (ServerError (..), runHandler)

import L4.Ledger.Append
import L4.Ledger.Row (Row (..))
import L4.Ledger.Store (LedgerStore (..), newMemoryStore)

-- | The tool's name, within the tool-name rule the decision tools keep to
-- (@^[a-zA-Z0-9_-]{1,64}$@). A decision function whose name sanitizes to
-- this one is shadowed by it on an endpoint that lists both.
ledgerToolName :: Text
ledgerToolName = "what-may-I-do-now"

ledgerToolDefinition :: Aeson.Value
ledgerToolDefinition = Aeson.object
  [ "name" .= ledgerToolName
  , "description" .= ("Contract instance ledger: what may be done now on a running contract instance, and, given an act, what it would do if it were proposed now. Advisory: the answer is computed at the head it names, outside the ledger's compare-and-append, and nothing is appended over MCP. To act, POST the act to /deployments/{deployment}/instances/{instance}/events with decidedAgainst set to that head; the ledger decides there, against the head that is current when the act arrives." :: Text)
  , "inputSchema" .= Aeson.object
      [ "type" .= ("object" :: Text)
      , "properties" .= Aeson.object
          [ "deployment" .= stringProp "The deployment; omit it on a deployment's own MCP endpoint"
          , "instance" .= stringProp "The instance, as it was created"
          , "party" .= stringProp "With action: the party of the act to try, as L4 source (e.g. World)"
          , "action" .= stringProp "With party: the act to try, as L4 source (e.g. `Alice buys dinner` TRUE)"
          , "idempotencyKey" .= stringProp "Optional: the key you would propose the act under; a key the instance already holds reads back as done"
          ]
      , "required" .= (["instance"] :: [Text])
      ]
  ]
  where
    stringProp :: Text -> Aeson.Value
    stringProp d = Aeson.object ["type" .= ("string" :: Text), "description" .= d]

-- | The MCP handler, with the ledger's tool in front of it. A service
-- without a ledger, or a caller the visibility headers do not show the
-- functions to or let evaluate, gets the handler alone.
withLedgerTool
  :: (Visibility -> Maybe Text -> Aeson.Value -> AppM Aeson.Value)
  -> Visibility -> Maybe Text -> Aeson.Value -> AppM Aeson.Value
withLedgerTool inner vis mScope req = do
  env <- ask
  case (env.ledger, req) of
    (Just ldg, Aeson.Object o)
      | vis.showFunctions && vis.showEvaluate
      , Just (Aeson.String method) <- KeyMap.lookup "method" o ->
          let reqId = KeyMap.lookup "id" o
              params = fromMaybe (Aeson.object []) (KeyMap.lookup "params" o)
          in case method of
            "tools/list" -> listed <$> inner vis mScope req
            "tools/call" | stringAt "name" params == Just ledgerToolName ->
              callLedgerTool ldg mScope reqId (fromMaybe (Aeson.object []) (at "arguments" params))
            _ -> inner vis mScope req
    _ -> inner vis mScope req

-- | The handler's @tools/list@ answer with the ledger's tool added; any
-- other answer (an error) as it was.
listed :: Aeson.Value -> Aeson.Value
listed resp = case resp of
  Aeson.Object o
    | Just (Aeson.Object r) <- KeyMap.lookup "result" o
    , Just (Aeson.Array tools) <- KeyMap.lookup "tools" r ->
        Aeson.Object (KeyMap.insert "result" (Aeson.Object (KeyMap.insert "tools" (Aeson.Array (Vector.snoc tools ledgerToolDefinition)) r)) o)
  other -> other

callLedgerTool :: LedgerService -> Maybe Text -> Maybe Aeson.Value -> Aeson.Value -> AppM Aeson.Value
callLedgerTool ldg mScope reqId args = do
  env <- ask
  case toolArguments mScope args of
    Left why -> pure (toolResult reqId True (Aeson.object ["applied" .= False, "because" .= why]))
    Right (deployId, name, mAct) -> do
      liftIO $ logInfo env.logger "MCP ledger tool called"
        [("deploymentId", Aeson.toJSON deployId), ("instance", Aeson.toJSON name), ("act", Aeson.toJSON (fmap (.action) mAct))]
      -- the routes' own lookup, its refusals read back as the tool's answer
      found <- liftIO (runHandler (runReaderT (resolveDeployment deployId >>= \ (_, dep) -> instanceFor dep name) env))
      case found of
        Left err -> pure (toolResult reqId True (errorBody err))
        Right inst -> do
          now <- runLimited ldg \ o -> do
            t <- ldg.clock
            positionReply inst t <$> positionOf (ledgerOf ldg o) inst
          ifNow <- traverse (\ p -> runLimited ldg \ o -> previewReply <$> preview ldg o inst p) mAct
          pure $ toolResult reqId (now.status /= 200) $ Aeson.object $
            [ "deployment" .= deployId
            , "instance" .= name
            , "now" .= now.body
            ]
            <> maybe [] (\ r -> ["ifProposedNow" .= r.body]) ifNow
            <> [ "appendedOverMcp" .= False
               , "howToAct" .= ("To act, POST {party, action, idempotencyKey, decidedAgainst} to /deployments/" <> deployId <> "/instances/" <> name <> "/events, with decidedAgainst the head above. The ledger decides there, against the head current when the act arrives; this answer is advisory." :: Text)
               ]

-- | The deployment, the instance, and the act to try, if one is named.
toolArguments :: Maybe Text -> Aeson.Value -> Either Text (Text, Text, Maybe Proposed)
toolArguments mScope args = do
  deployId <- case (stringAt "deployment" args, mScope) of
    (Just d, Just s) | d /= s -> Left ("this endpoint is deployment " <> s <> "'s, and the call names " <> d)
    (Just d, _) -> Right d
    (Nothing, Just s) -> Right s
    (Nothing, Nothing) -> Left "name the deployment: this endpoint is not one deployment's"
  name <- maybe (Left "name the instance") Right (stringAt "instance" args)
  act <- case (stringAt "party" args, stringAt "action" args) of
    (Nothing, Nothing) -> Right Nothing
    (Just p, Just a) -> Right (Just MkProposed
      { party = p
      , action = a
      , claimedAt = Nothing
      , decidedAgainst = Nothing
      , idempotencyKey = fromMaybe "what-may-I-do-now preview" (stringAt "idempotencyKey" args)
      , strict = False
      })
    _ -> Left "an act to try names its party and its action, both"
  Right (deployId, name, act)

-- | What 'appendIf' would answer were the act proposed now: 'appendIf'
-- itself, over a scratch store holding a copy of the instance's rows, so
-- that any tick that is due comes first in the preview as it would in the
-- append. The instance's own store is only read.
preview :: LedgerService -> OpenedStore -> Instance -> Proposed -> IO Result
preview ldg o inst p = o.store.readRows key >>= \ case
  [] -> pure NotFound
  rows -> do
    scratch <- newMemoryStore
    forM_ rows \ r -> scratch.appendRow key r.seqNo r
    appendIf (ledgerOver ldg scratch) inst p
  where
    key = instanceKey inst

-- | A preview's reply: the append's own reply, saying it applied nothing
-- and what it would have been.
previewReply :: Result -> LedgerReply
previewReply r = MkLedgerReply rep.status (foldl set rep.body
  [ ("result", Aeson.String would)
  , ("applied", Aeson.Bool False)
  , ("advisory", Aeson.String "nothing was appended: this is what the ledger would do with the act were it proposed now, at the head named under now")
  ])
  where
    rep = resultReply r
    would = case r of
      Appended {} -> "would be appended"
      Refused {} -> "would be refused"
      Conflict {} -> "would conflict"
      Unknown {} -> "unknown"
      NotFound -> "not found"
    set v (k, x) = case v of
      Aeson.Object m -> Aeson.Object (KeyMap.insert k x m)
      other -> other

-- | A refusal the routes' lookup raised, as the tool says it: its JSON
-- body when it has one.
errorBody :: ServerError -> Aeson.Value
errorBody err = fromMaybe
  (Aeson.object ["applied" .= False, "because" .= Text.Encoding.decodeUtf8Lenient (LBS.toStrict err.errBody)])
  (Aeson.decode err.errBody)

toolResult :: Maybe Aeson.Value -> Bool -> Aeson.Value -> Aeson.Value
toolResult reqId isError v = jsonRpcResult reqId $ Aeson.object $
  [ "content" .= [ Aeson.object
      [ "type" .= ("text" :: Text)
      , "text" .= Text.Encoding.decodeUtf8Lenient (LBS.toStrict (Aeson.encode v))
      ] ]
  ] <> [ "isError" .= True | isError ]

-- | A JSON-RPC 2.0 result, as "McpServer" writes one.
jsonRpcResult :: Maybe Aeson.Value -> Aeson.Value -> Aeson.Value
jsonRpcResult reqId result = Aeson.object $
  [ "jsonrpc" .= ("2.0" :: Text)
  , "result" .= result
  ] <> maybe [] (\ i -> ["id" .= i]) reqId

at :: Text -> Aeson.Value -> Maybe Aeson.Value
at k = \ case
  Aeson.Object o -> KeyMap.lookup (Key.fromText k) o
  _ -> Nothing

stringAt :: Text -> Aeson.Value -> Maybe Text
stringAt k v = case at k v of
  Just (Aeson.String s) -> Just s
  _ -> Nothing
