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
-- This tool reads; it never appends (§5: an agent calling for Alice over
-- MCP evaluates the rule at knowledge time, and that evaluation is
-- advisory). It says the instance's position, the same answer as
-- @GET .../position@, and, given an act, what the ledger would do with it
-- if it arrived now: 'L4.Ledger.Append.appendIf' itself, run over a scratch
-- copy of the instance's rows, so the preview and the append are one
-- function by construction and disagree only about which head is current.
-- To act, an agent proposes the act on the instance's events route, naming
-- the head it decided against, or, where the service has the write tools
-- on (below), calls one.
--
-- The write tools (§9 WPO6, D-O13) are off unless the service is started
-- with @--ledger-mcp-write@. With them on, a deployment's own endpoint
-- (never the org-wide one) lists one tool, @act-<the act's name>@, for each
-- act the caller's party may perform, read off the deployment's source
-- ("L4.Ledger.Offer"). The caller's party is the @X-L4-Party@ header a
-- proxy sets, and never an argument; with no header there is no write tool,
-- and a call to one is refused. A call is 'appendIf' on the true head, the
-- function the events route calls, so what it answers is the events
-- route's own answer: appended, refused, conflict or unknown, with the
-- ticks it appended. The party is a claim and not an authentication, as the
-- events route's @party@ is; who the caller is, is D-O2, open.
--
-- A write tool shadows a decision function whose name sanitizes to the same
-- tool name, as the read tool does; the prefix @act-@ makes that unlikely.
--
-- How the read tool fails, sorted by whether the agent hears it: a deployment or
-- instance that is not there, or a store that cannot be opened, is a tool
-- error (@isError@), loud; an answer that has gone stale by the time the
-- agent acts is not an error at all, and is why the reply names its head
-- and says it is advisory. An agent that treats the preview as the append,
-- and buys on it without proposing, is design D1.
--
-- How the write tools fail. Loud, with @isError@: a call with no party, a
-- tool not offered to the party, an argument that does not fit, an unknown
-- instance; and the ledger's own refused, conflict and unknown. Silent: an
-- act that is not offered because its fields are not all BOOLEAN, NUMBER
-- or STRING is missing from @tools/list@ with no word there; the read
-- tool's reply names every such act and why under @writeTools@. A deployment
-- whose acts could not be read lists no write tool, and the same reply says
-- so.
module Ledger.Mcp
  ( withLedgerTool
  , ledgerToolName
  , ledgerToolDefinition
  , writeToolPrefix
  ) where

import Ledger
import Ledger.Service (LedgerService (..), offersOfDeployment)
import Ledger.Store.Config (OpenedStore (..))
import Logging (logInfo)
import Options (Options (..))
import Shared (sanitizePropertyName)
import Types

import Control.Monad (forM_, unless)
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Reader (ask, runReaderT)
import Data.Aeson ((.=))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString.Lazy as LBS
import Data.Maybe (fromMaybe, isJust)
import Data.Scientific (base10Exponent, isInteger)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text.Encoding
import qualified Data.Vector as Vector
import Servant (ServerError (..), runHandler)

import L4.Ledger.Append
import L4.Ledger.Offer (Arg (..), Field (..), FieldType (..), Offered (..), Offers (..), Unoffered (..), actSource)
import L4.Ledger.Replay (Deployment (..))
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
  , "description" .= ("Contract instance ledger: what may be done now on a running contract instance, and, given an act, what it would do if it were proposed now. Advisory: the answer is computed at the head it names, outside the ledger's compare-and-append, and this tool appends nothing. To act, POST the act to /deployments/{deployment}/instances/{instance}/events with decidedAgainst set to that head, or, where the service has them on, call one of the act-* write tools (see writeTools in the answer); the ledger decides there, against the head that is current when the act arrives." :: Text)
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
              args = fromMaybe (Aeson.object []) (at "arguments" params)
          in case method of
            "tools/list" -> do
              writes <- writeToolDefinitions ldg vis mScope
              listed writes <$> inner vis mScope req
            "tools/call"
              | stringAt "name" params == Just ledgerToolName ->
                  callLedgerTool ldg vis mScope reqId args
              | Just n <- stringAt "name" params, writeToolPrefix `Text.isPrefixOf` n, env.options.ledgerMcpWrite, Just d <- mScope ->
                  callWriteTool ldg vis d reqId n args (inner vis mScope req)
            _ -> inner vis mScope req
    _ -> inner vis mScope req

-- | The handler's @tools/list@ answer with the ledger's tool, and these
-- write tools, added; any other answer (an error) as it was.
listed :: [Aeson.Value] -> Aeson.Value -> Aeson.Value
listed writes resp = case resp of
  Aeson.Object o
    | Just (Aeson.Object r) <- KeyMap.lookup "result" o
    , Just (Aeson.Array tools) <- KeyMap.lookup "tools" r ->
        Aeson.Object (KeyMap.insert "result" (Aeson.Object (KeyMap.insert "tools" (Aeson.Array (tools <> Vector.fromList (ledgerToolDefinition : writes))) r)) o)
  other -> other

callLedgerTool :: LedgerService -> Visibility -> Maybe Text -> Maybe Aeson.Value -> Aeson.Value -> AppM Aeson.Value
callLedgerTool ldg vis mScope reqId args = do
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
          writes <- if env.options.ledgerMcpWrite
            then Just <$> writeToolsReport ldg vis inst.deploymentOf
            else pure Nothing
          pure $ toolResult reqId (now.status /= 200) $ Aeson.object $
            [ "deployment" .= deployId
            , "instance" .= name
            , "now" .= now.body
            ]
            <> maybe [] (\ r -> ["ifProposedNow" .= r.body]) ifNow
            <> maybe [] (\ w -> ["writeTools" .= w]) writes
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

----------------------------------------------------------------------------
-- The write tools (WPO6, D-O13)
----------------------------------------------------------------------------

-- | The prefix of every write tool's name: with the sanitized act name,
-- which is at most 60 characters, it stays within the 64 the tool-name
-- rule allows.
writeToolPrefix :: Text
writeToolPrefix = "act-"

-- | A write tool: the act it appends, and the argument each of the act's
-- fields is read from.
data WriteTool = MkWriteTool
  { toolName :: !Text
  , act      :: !Offered
  , argNames :: ![Text]
  }

-- | The arguments every write tool takes itself; a field of an act cannot
-- be named one.
reservedArgs :: [Text]
reservedArgs = ["instance", "idempotencyKey", "decidedAgainst"]

-- | The write tool of each act the offers name, one per party and act, and
-- the acts that could not have one, with the reason: two acts of a party
-- whose names sanitize to one tool name, and an act whose fields cannot
-- be told apart or take the call's own argument names. An act the offers
-- left out ('unoffered') is not here.
planFor :: Offers -> ([WriteTool], [(Text, Text, Text)])
planFor offers = (usable, problems)
  where
    candidates =
      [ MkWriteTool (writeToolPrefix <> sanitizePropertyName o.constructor) o (map (sanitizePropertyName . (.name)) o.fields)
      | o <- offers.offered ]
    verdicts = [ (t, verdict t) | t <- candidates ]
    usable = [ t | (t, Right ()) <- verdicts ]
    problems = [ (t.act.party, t.act.constructor, why) | (t, Left why) <- verdicts ]
    verdict t
      | length [ () | u <- candidates, u.act.party == t.act.party, u.toolName == t.toolName ] > 1 =
          Left ("another act of " <> t.act.party <> " has the same tool name, " <> t.toolName)
      | any (`elem` reservedArgs) t.argNames =
          Left ("one of its fields would be an argument named like one of the call's own (" <> Text.intercalate ", " reservedArgs <> ")")
      | length (Map.keys (Map.fromList [ (a, ()) | a <- t.argNames ])) /= length t.argNames =
          Left "two of its fields would be arguments of the same name"
      | otherwise = Right ()

-- | What is offered to one party as tools.
toolsFor :: Text -> Offers -> [WriteTool]
toolsFor party offers = [ t | t <- fst (planFor offers), t.act.party == party ]

-- | The acts a party may perform that have no tool, and why.
notOffered :: Text -> Offers -> [(Text, Text)]
notOffered party offers =
  [ (u.constructor, u.reason) | u <- offers.unoffered, u.party == party || Text.null u.party ]
  <> [ (c, why) | (p, c, why) <- snd (planFor offers), p == party ]

-- | The deployment the routes would run and what its source offers, or
-- why not.
deploymentOffers :: LedgerService -> Text -> AppM (Either Text (Deployment, Offers))
deploymentOffers ldg deployId = do
  env <- ask
  found <- liftIO (runHandler (runReaderT (resolveDeployment deployId) env))
  case found of
    Left err -> pure (Left (fromMaybe "the deployment is not available to the ledger" (stringAt "because" (errorBody err))))
    Right (_, dep) -> liftIO (offersOfDeployment ldg dep) >>= \ case
      Left why -> pure (Left why)
      Right offers -> pure (Right (dep, offers))

-- | The write tools to list: those of the caller's party, on a deployment's
-- own endpoint, with the service's flag on. None otherwise, and none, with
-- a line in the log, when the deployment's acts cannot be read.
writeToolDefinitions :: LedgerService -> Visibility -> Maybe Text -> AppM [Aeson.Value]
writeToolDefinitions ldg vis mScope = do
  env <- ask
  case (env.options.ledgerMcpWrite, mScope, vis.callerParty) of
    (True, Just deployId, Just party) -> deploymentOffers ldg deployId >>= \ case
      Left why -> do
        liftIO $ logInfo env.logger "MCP ledger write tools not listed"
          [("deploymentId", Aeson.toJSON deployId), ("because", Aeson.toJSON why)]
        pure []
      Right (_, offers) -> pure (map writeToolDefinition (toolsFor party offers))
    _ -> pure []

writeToolDefinition :: WriteTool -> Aeson.Value
writeToolDefinition t = Aeson.object
  [ "name" .= t.toolName
  , "description" .= ("Propose the act `" <> t.act.constructor <> "` as " <> t.act.party
      <> " on a contract instance's ledger. The ledger decides it against the true head, not against what you last read, and answers appended, refused, conflict or unknown, with the row, the head and any ticks it appended first. Only appended puts your act on the record. After a lost reply, call again with the same idempotencyKey: the first answer is read back and nothing more is appended. With decidedAgainst, the call is strict: it is a conflict if the head has moved since. The party is the one this connection is for and cannot be given here." :: Text)
  , "inputSchema" .= Aeson.object
      [ "type" .= ("object" :: Text)
      , "properties" .= Aeson.object
          ( [ "instance" .= prop "string" "The instance, as it was created"
            , "idempotencyKey" .= prop "string" "A key you choose for this proposal; required"
            , "decidedAgainst" .= prop "integer" "Optional: the head your decision rested on; given, the call is strict and a conflict if the head has moved"
            ]
          <> [ Key.fromText k .= prop (typeName f.kind) ("The act's field " <> f.name) | (k, f) <- zip t.argNames t.act.fields ]
          )
      , "required" .= (["instance", "idempotencyKey"] <> t.argNames)
      ]
  ]
  where
    prop :: Text -> Text -> Aeson.Value
    prop ty d = Aeson.object ["type" .= ty, "description" .= d]
    typeName = \ case
      FieldBoolean -> "boolean"
      FieldNumber -> "number"
      FieldString -> "string"

-- | What the read tool says of the write tools: those the caller's party
-- has, those it would have had but could not, and why there are none.
writeToolsReport :: LedgerService -> Visibility -> Deployment -> AppM Aeson.Value
writeToolsReport ldg vis dep = do
  r <- liftIO (offersOfDeployment ldg dep)
  pure $ Aeson.object $ ["party" .= vis.callerParty, "listedOn" .= ("/deployments/" <> dep.deploymentId <> "/.mcp" :: Text)] <> case (r, vis.callerParty) of
    (Left why, _) -> ["tools" .= ([] :: [Text]), "because" .= ("the deployment's acts could not be read: " <> why)]
    (Right _, Nothing) -> ["tools" .= ([] :: [Text]), "because" .= ("this connection names no party (the X-L4-Party header), so it is offered no write tool" :: Text)]
    (Right offers, Just p) ->
      [ "tools" .= map (.toolName) (toolsFor p offers)
      , "notOffered" .= [ Aeson.object ["act" .= c, "because" .= why] | (c, why) <- notOffered p offers ]
      ]

-- | A write tool's call. A name that is no write tool's, here or at all, goes
-- to the handler as it came, so a decision function named @act-…@, or a
-- deployment the ledger cannot run, is answered as it always was.
callWriteTool :: LedgerService -> Visibility -> Text -> Maybe Aeson.Value -> Text -> Aeson.Value -> AppM Aeson.Value -> AppM Aeson.Value
callWriteTool ldg vis deployId reqId name args fallThrough = do
  env <- ask
  found <- deploymentOffers ldg deployId
  case found of
    Left _ -> fallThrough
    Right (dep, offers) -> case [ t | t <- fst (planFor offers), t.toolName == name ] of
      [] -> fallThrough
      named -> case vis.callerParty of
        Nothing -> refuse "this connection names no party (the X-L4-Party header), so it may perform no act"
        Just p -> case [ t | t <- named, t.act.party == p ] of
          [] -> refuse ("the act `" <> (head' named).act.constructor <> "` is not offered to " <> p <> "; it is " <> Text.intercalate ", " [ t.act.party | t <- named ] <> "'s")
          (t : _) -> case parseWriteArgs t args of
            Left why -> refuse why
            Right (instName, key, decided, actArgs) -> case actSource t.act actArgs of
              Left why -> refuse why
              Right actText -> do
                liftIO $ logInfo env.logger "MCP ledger write tool called"
                  [ ("deploymentId", Aeson.toJSON deployId), ("instance", Aeson.toJSON instName)
                  , ("party", Aeson.toJSON t.act.party), ("act", Aeson.toJSON t.act.constructor) ]
                located <- liftIO (runHandler (runReaderT (instanceFor dep instName) env))
                case located of
                  Left err -> pure (toolResult reqId True (errorBody err))
                  Right inst -> do
                    let proposal = MkProposed
                          { party = t.act.party
                          , action = actText
                          , claimedAt = Nothing
                          , decidedAgainst = decided
                          , idempotencyKey = key
                          , strict = isJust decided
                          }
                    reply <- runLimited ldg \ o -> resultReply <$> appendIf (ledgerOf ldg o) inst proposal
                    pure (toolResult reqId (reply.status /= 200) reply.body)
  where
    refuse :: Text -> AppM Aeson.Value
    refuse why = pure (toolResult reqId True (Aeson.object ["result" .= ("not applied" :: Text), "applied" .= False, "because" .= why]))
    head' = \ case
      (x : _) -> x
      [] -> error "callWriteTool: no tool named"

-- | The call's arguments: the instance, the idempotency key (both required;
-- the key has no default), the head decided against if one is given, and
-- the act's fields in order. An argument the tool does not take is refused,
-- naming it, and so is a field of the wrong type.
parseWriteArgs :: WriteTool -> Aeson.Value -> Either Text (Text, Text, Maybe Int, [Arg])
parseWriteArgs t args = do
  obj <- case args of
    Aeson.Object o -> Right o
    _ -> Left "the arguments are not an object"
  let known = reservedArgs <> t.argNames
      extra = [ k | k <- map Key.toText (KeyMap.keys obj), k `notElem` known ]
  unless (null extra) $
    Left ("the tool does not take " <> Text.intercalate ", " extra <> "; it takes " <> Text.intercalate ", " known)
  instName <- required "instance"
  key <- required "idempotencyKey"
  decided <- case at "decidedAgainst" args of
    Nothing -> Right Nothing
    Just Aeson.Null -> Right Nothing
    Just (Aeson.Number n) | base10Exponent n <= 15, isInteger n, n >= 0 -> Right (Just (truncate n))
    Just _ -> Left "decidedAgainst is the head you decided against: a whole number, 0 or more"
  actArgs <- traverse field (zip t.act.fields t.argNames)
  Right (instName, key, decided, actArgs)
  where
    required k = case stringAt k args of
      Just v | not (Text.null (Text.strip v)) -> Right v
      _ -> Left ("name the " <> k <> ": a string that is not empty")
    field (f, k) = case (f.kind, at k args) of
      (_, Nothing) -> Left ("the argument " <> k <> " is missing")
      (FieldBoolean, Just (Aeson.Bool b)) -> Right (ArgBool b)
      (FieldNumber, Just (Aeson.Number n))
        | abs (base10Exponent n) <= 30 -> Right (ArgNumber (toRational n))
        | otherwise -> Left ("the argument " <> k <> " is out of range: a power of ten above 30")
      (FieldString, Just (Aeson.String s)) -> Right (ArgText s)
      (kind, Just _) -> Left ("the argument " <> k <> " must be " <> case kind of
        FieldBoolean -> "true or false"
        FieldNumber -> "a number"
        FieldString -> "a string")
