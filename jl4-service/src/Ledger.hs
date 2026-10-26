{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeOperators #-}

-- | The instance ledger's routes (OPERATIONAL-LOWERING-SPEC §3, §9 WPO3),
-- beside the decision routes of a deployment:
--
-- * @POST \/deployments\/{id}\/instances@ creates an instance;
-- * @POST \/deployments\/{id}\/instances\/{instance}\/events@ proposes an
--   act to it ('L4.Ledger.Append.appendIf');
-- * @GET \/deployments\/{id}\/instances\/{instance}\/position@ says what may
--   be done now ('L4.Ledger.Append.positionOf').
--
-- The ledger itself is "L4.Ledger.Append"; this module finds the contract a
-- deployment runs, holds a request to the ledger's limits, and says what
-- the ledger answered. Every reply is JSON, and every one says whether
-- anything was applied.
--
-- How a reply goes wrong, sorted by whether the caller hears it:
--
-- * __Loud__: 404 for an instance the ledger does not hold (never a fresh
--   instance in its place), 409 for a strict proposal whose cell moved
--   (@Conflict@) or an instance created twice, 422 for an act that is not
--   an event of the contract (@Refused@), and 503 for every reply that
--   applied nothing for another reason: the evaluator could not decide
--   (@Unknown@), a limit stopped the request, the ledger's slots are all
--   taken, the store could not be reached. A 503 is "not applied", as the
--   app-wide limiter's own 503 is (D-O10), and a retry with the same
--   idempotency key is always safe. "Not applied" means the act: tick rows
--   that were due are appended first and survive a refusal, a conflict or
--   an @Unknown@, and the reply does not list them.
-- * __Silent, if the caller lets it be__: a 503 from a limit that fell
--   after the row was written. The reply cannot tell, and says so; the
--   retry with the same key then reads the row back, as done. A proposer
--   that reads a 503 as permission and acts on its own is design D1.
-- * __Silent, by assumption__: the ledger clock is whole seconds since the
--   Unix epoch ('Ledger.Service.posixClock'), and a contract written
--   against another unit or epoch runs with every deadline shifted (D-O8).
module Ledger
  ( InstanceRoutes
  , instanceRoutesHandler
    -- * What the control plane asks
  , refuseIfInstancesHeld
  , withCreationLock
    -- * The contract a deployment runs (exported for tests)
  , ledgerDeployment
  , validInstanceId
    -- * Shared with the MCP tool ("Ledger.Mcp")
  , LedgerReply (..)
  , resolveDeployment
  , instanceFor
  , ledgerOf
  , ledgerOver
  , runLimited
  , rowJson
  , resultReply
  , positionReply
  , timeJson
  , storeFields
  ) where

import qualified BundleStore
import BundleStore (StoredMetadata (..))
import EvalLimits (LimitHit (..), withThreadLimits)
import Ledger.Service
import Ledger.Store.Config (OpenedStore (..))
import Ledger.Store.Sql (LedgerStoreError (..))
import Shared (jsonError)
import Types

import Control.Concurrent.MVar (withMVar)
import Control.Concurrent.STM (readTVarIO)
import Control.Exception (IOException, catches)
import qualified Control.Exception as Exception
import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Reader (ask, runReaderT)
import Data.Aeson ((.=))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Aeson.Types as Aeson
import Data.ByteString (ByteString)
import Data.Char (isAlphaNum)
import Data.List (sort)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe)
import Data.Ratio (denominator, numerator)
import Data.Scientific (Scientific)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as Text
import Network.HTTP.Types (HeaderName)
import Servant
import System.FilePath (takeBaseName, takeExtension)

import L4.API.VirtualFS (extractImportNames, moduleNameToProjectUri)
import L4.Ledger.Append
import L4.Ledger.Replay (Deployment (..))
import L4.Ledger.Row
import L4.Ledger.Store (LedgerStore (..))
import L4.Lts.List (TraceReport (..), reportJson)
import L4.Parser (execProgramParser)

-- | The three routes, mounted under @\/deployments\/{id}@ beside the
-- decision routes ("DataPlane").
type InstanceRoutes =
       "instances" :> ReqBody '[JSON] CreateInstance :> Verb 'POST 201 '[JSON] Aeson.Value
  :<|> "instances" :> Capture "instanceId" Text :> "events" :> ReqBody '[JSON] ProposeEvent :> Post '[JSON] Aeson.Value
  :<|> "instances" :> Capture "instanceId" Text :> "position" :> Get '[JSON] Aeson.Value

instanceRoutesHandler :: Text -> ServerT InstanceRoutes AppM
instanceRoutesHandler deployIdText =
       createInstanceHandler deployIdText
  :<|> proposeEventHandler deployIdText
  :<|> positionHandler deployIdText

----------------------------------------------------------------------------
-- Requests
----------------------------------------------------------------------------

-- | @{"instance": "…", "contract": "…"}@: the instance's name, and the
-- contract expression its @#TRACE@ runs, as L4 source.
data CreateInstance = MkCreateInstance
  { instanceName :: !Text
  , contract     :: !Text
  }

instance Aeson.FromJSON CreateInstance where
  parseJSON = Aeson.withObject "CreateInstance" \ o ->
    MkCreateInstance <$> o Aeson..: "instance" <*> o Aeson..: "contract"

-- | An act proposed (§3.2): @party@ and @action@ as L4 source, the
-- proposer's @idempotencyKey@, and optionally the head it decided against,
-- @strict@ with the official @cells@ whose version it decided on (none
-- means the whole head), and @claimedAt@ for an act the party reports
-- having done in the world.
data ProposeEvent = MkProposeEvent
  { party          :: !Text
  , action         :: !Text
  , idempotencyKey :: !Text
  , decidedAgainst :: !(Maybe Int)
  , strict         :: !Bool
  , cells          :: ![Text]
  , claimedAt      :: !(Maybe Scientific)
  }

instance Aeson.FromJSON ProposeEvent where
  parseJSON = Aeson.withObject "ProposeEvent" \ o ->
    MkProposeEvent
      <$> o Aeson..: "party"
      <*> o Aeson..: "action"
      <*> o Aeson..: "idempotencyKey"
      <*> o Aeson..:? "decidedAgainst"
      <*> o Aeson..:? "strict" Aeson..!= False
      <*> o Aeson..:? "cells" Aeson..!= []
      <*> o Aeson..:? "claimedAt"

----------------------------------------------------------------------------
-- Handlers
----------------------------------------------------------------------------

-- | A reply: its status and body.
data LedgerReply = MkLedgerReply
  { status :: !Int
  , body   :: !Aeson.Value
  }

createInstanceHandler :: Text -> CreateInstance -> AppM Aeson.Value
createInstanceHandler deployIdText req = do
  (ldg, dep) <- resolveDeployment deployIdText
  inst <- instanceFor dep req.instanceName
  env <- ask
  reply <- runLimited ldg \ o -> withMVar ldg.creationLock \ _ -> do
    -- the deployment is asked for again under the lock, which a delete
    -- holds from its check to its last file
    registry <- readTVarIO env.deploymentRegistry
    if not (Map.member (DeploymentId deployIdText) registry)
      then pure (gone deployIdText)
      else o.store.readRows (instanceKey inst) >>= \ case
        (_ : _) -> pure (MkLedgerReply 409 (Aeson.object
          [ "result" .= ("refused" :: Text), "applied" .= False
          , "because" .= ("the instance " <> req.instanceName <> " already exists" :: Text) ]))
        [] -> do
          r <- createInstance (ledgerOf ldg o) inst req.contract
          pure case resultReply r of
            MkLedgerReply 200 b -> MkLedgerReply 201 b
            other -> other
  answer reply

proposeEventHandler :: Text -> Text -> ProposeEvent -> AppM Aeson.Value
proposeEventHandler deployIdText instanceIdText req = do
  (ldg, dep0) <- resolveDeployment deployIdText
  let dep = dep0 {versionedCells = req.cells}
  inst <- instanceFor dep instanceIdText
  let proposal = MkProposed
        { party = req.party
        , action = req.action
        , claimedAt = toRational <$> req.claimedAt
        , decidedAgainst = req.decidedAgainst
        , idempotencyKey = req.idempotencyKey
        , strict = req.strict
        }
  reply <- runLimited ldg \ o -> resultReply <$> appendIf (ledgerOf ldg o) inst proposal
  answer reply

positionHandler :: Text -> Text -> AppM Aeson.Value
positionHandler deployIdText instanceIdText = do
  (ldg, dep) <- resolveDeployment deployIdText
  inst <- instanceFor dep instanceIdText
  reply <- runLimited ldg \ o -> do
    now <- ldg.clock
    positionReply inst now <$> positionOf (ledgerOf ldg o) inst
  answer reply

-- | The position, as the route and the MCP tool both say it: advisory,
-- stamped with its head (§3.3).
positionReply :: Instance -> Rational -> Either Result LedgerPosition -> LedgerReply
positionReply inst now = \ case
  Left r -> resultReply r
  Right p -> MkLedgerReply 200 (Aeson.object
    [ "deployment" .= inst.deploymentOf.deploymentId
    , "instance" .= inst.instanceId
    , "head" .= p.headSeq
    , "clock" .= timeJson now
    , "terminal" .= p.terminal
    , "nextDeadline" .= fmap timeJson p.nextDeadline
    , "deadlinePassed" .= maybe False (< now) p.nextDeadline
    , "ledger" .= p.ledgerAtHead
    , "position" .= reportJson False ((p.report) {rpLine = Nothing})
    , "advisory" .= ("computed at head " <> showT p.headSeq <> ", outside the ledger's compare-and-append; an act proposed now is decided against the head current when it arrives" :: Text)
    ])

instanceFor :: Deployment -> Text -> AppM Instance
instanceFor dep name = case validInstanceId name of
  Just why -> throwError err400 {errBody = jsonError why, errHeaders = [jsonHeader]}
  Nothing -> pure MkInstance {deploymentOf = dep, instanceId = name}

-- | An instance name is one path segment: letters, digits, hyphens and
-- underscores, at most 128 of them. 'Just' says why a name is not one.
validInstanceId :: Text -> Maybe Text
validInstanceId name
  | Text.null name = Just "An instance name is not empty"
  | Text.length name > 128 = Just "An instance name is at most 128 characters"
  | not (Text.all (\ c -> isAlphaNum c || c == '-' || c == '_') name) =
      Just "An instance name holds only letters, digits, - and _"
  | otherwise = Nothing

----------------------------------------------------------------------------
-- The contract a deployment runs
----------------------------------------------------------------------------

-- | The ledger and the deployment's contract, or the reply that says why
-- there is none.
resolveDeployment :: Text -> AppM (LedgerService, Deployment)
resolveDeployment deployIdText = do
  env <- ask
  ldg <- maybe (throwJson (MkLedgerReply 503 (notApplied "this service runs without an instance ledger"))) pure env.ledger
  registry <- liftIO (readTVarIO env.deploymentRegistry)
  case Map.lookup (DeploymentId deployIdText) registry of
    Nothing -> throwJson (gone deployIdText)
    Just DeploymentCompiling -> throwJson (MkLedgerReply 503 (notApplied "the deployment is compiling; ask again"))
    Just (DeploymentFailed _) -> throwJson (MkLedgerReply 422 (notApplied "the deployment failed to compile, so the ledger has no contract to run"))
    Just _ -> do
      loaded <- liftIO ((Right <$> BundleStore.loadBundle env.bundleStore deployIdText) `catches`
        [Exception.Handler \ (e :: IOException) -> pure (Left (Text.pack (show e)))])
      case loaded of
        Left why -> throwJson (MkLedgerReply 503 (notApplied ("the deployment's files could not be read: " <> why)))
        Right (sources, meta) ->
          case ledgerDeployment deployIdText (fromMaybe meta.smVersion meta.smDeploymentVersion) sources of
            Left why -> throwJson (MkLedgerReply 422 (notApplied why))
            Right dep -> pure (ldg, dep)

-- | The deployment as the ledger runs it: its one @.l4@ file that no other
-- @.l4@ file of the bundle imports is the contract's source, and every
-- other @.l4@ file is an import, by its file name less @.l4@, which is how
-- an @IMPORT@ names it.
--
-- Assumed, not ruled. The rows are the only thing the ledger keeps (§3.1),
-- so the contract's file has to follow from the bundle, the same on every
-- append; a bundle with two such files (two designs side by side) is
-- refused, naming them, rather than one being picked. The dinner bundle,
-- @d3-atomic.l4@ importing @properties.l4@, has one.
ledgerDeployment :: Text -> Text -> Map FilePath Text -> Either Text Deployment
ledgerDeployment deployIdText version sources = do
  let l4Files = [ (Text.pack (takeBaseName p), p, src) | (p, src) <- Map.toList sources, takeExtension p == ".l4" ]
      names = [ n | (n, _, _) <- l4Files ]
      dupes = Set.toList (Set.fromList [ n | (n, k) <- Map.toList (Map.fromListWith (+) [ (n, 1 :: Int) | n <- names ]), k > 1 ])
  case () of
    _ | null l4Files -> Left "the deployment holds no .l4 file"
      | not (null dupes) -> Left ("two .l4 files of the deployment share the import name " <> Text.intercalate ", " dupes)
      | otherwise -> pure ()
  imports <- traverse (\ (n, p, src) -> case execProgramParser (moduleNameToProjectUri n) src of
                  Left _ -> Left (Text.pack p <> " does not parse, so what it imports is not known")
                  Right (m, _) -> Right (n, Set.fromList (extractImportNames m))) l4Files
  let importedBy n = Set.unions [ is | (m, is) <- imports, m /= n ]
      roots = [ f | f@(n, _, _) <- l4Files, not (n `Set.member` importedBy n) ]
  case roots of
    [(_, rootPath, src)] -> Right MkDeployment
      { deploymentId = deployIdText
      , deploymentVersion = version
      , deploymentSource = src
      , deploymentImports = [ (n, s) | (n, p, s) <- l4Files, p /= rootPath ]
      , versionedCells = []
      }
    [] -> Left "every .l4 file of the deployment is imported by another, so none is the contract's"
    many -> Left ("the deployment has " <> showT (length many) <> " .l4 files that no other imports ("
      <> Text.intercalate ", " (sort [ Text.pack p | (_, p, _) <- many ])
      <> "); the ledger runs the one such file, so deploy each design on its own")

----------------------------------------------------------------------------
-- Running a request
----------------------------------------------------------------------------

-- | The ledger over an opened store.
ledgerOf :: LedgerService -> OpenedStore -> Ledger
ledgerOf ldg o = ledgerOver ldg o.store

-- | The ledger over any store: the service's clock, configuration and
-- limits with these rows. The MCP tool's preview runs it over a scratch
-- copy of an instance's rows ("Ledger.Mcp").
ledgerOver :: LedgerService -> LedgerStore -> Ledger
ledgerOver ldg st = MkLedger
  { store = st
  , clock = ldg.clock
  , evalConfig = ldg.evalConfig
  , timeBound = ldg.timeoutSec * 1_000_000
  , retryCap = ldg.retryCap
  }

-- | Open the store (outside the limits: opening is not evaluating), take a
-- ledger slot, and run under the ledger's time and allocation limits
-- ('EvalLimits.withThreadLimits'), the reply forced inside them. Every
-- reply carries which store answered, and the in-memory store's warning.
runLimited :: LedgerService -> (OpenedStore -> IO LedgerReply) -> AppM LedgerReply
runLimited ldg act = liftIO do
  withOpenedStore ldg pure >>= \ case
    Left why -> pure (MkLedgerReply 503 (notApplied why))
    Right o -> do
      slot <- withLedgerSlot ldg (withThreadLimits ldg.timeoutSec ldg.memoryMb (forced <$> guarded (act o)))
      pure $ withStore o case slot of
        Nothing -> MkLedgerReply 503 (notApplied ("all " <> showT ldg.slotCount <> " of the ledger's evaluation slots are taken; ask again"))
        Just (Left (hit, _)) -> MkLedgerReply 503 (notApplied (limitText hit) `withField` ("retry" .= retryText))
        Just (Right ((code, b), _)) -> MkLedgerReply code b
  where
    forced r = (r.status, r.body)
    limitText = \ case
      TimeLimitHit -> "the request did not finish within the ledger's time limit of " <> showT ldg.timeoutSec <> " s (--eval-timeout)"
      AllocationLimitHit -> "the request allocated more than the ledger's limit of " <> showT ldg.memoryMb <> " MB (--ledger-max-eval-memory-mb)"
    retryText :: Text
    retryText = "if the limit fell after the row was written, the same idempotency key reads it back; if before, the retry appends it"
    -- a store that fails, or a file that cannot be read, is a reply, not a
    -- dropped connection; nothing asynchronous is caught here, so the
    -- limits still stop the request
    guarded io = io `catches`
      [ Exception.Handler \ (LedgerStoreError why) -> pure (MkLedgerReply 503 (notApplied ("the ledger store failed: " <> why)))
      , Exception.Handler \ (e :: IOException) -> pure (MkLedgerReply 503 (notApplied ("the ledger store failed: " <> Text.pack (show e))))
      ]

withStore :: OpenedStore -> LedgerReply -> LedgerReply
withStore o r = MkLedgerReply {status = r.status, body = foldl withField r.body (storeFields o)}

-- | Which store answered, and the in-memory store's warning when it is the
-- one.
storeFields :: OpenedStore -> [Aeson.Pair]
storeFields o = ("store" .= o.backend) : maybe [] (\ w -> ["warning" .= w]) o.nonDurable

-- | The object with this field set, replacing one of the same name.
withField :: Aeson.Value -> Aeson.Pair -> Aeson.Value
withField v (k, x) = case v of
  Aeson.Object m -> Aeson.Object (KeyMap.insert k x m)
  other -> other

answer :: LedgerReply -> AppM Aeson.Value
answer r
  | r.status == 200 || r.status == 201 = pure r.body
  | otherwise = throwJson r

throwJson :: LedgerReply -> AppM a
throwJson r = throwError ServerError
  { errHTTPCode = r.status
  , errReasonPhrase = reason r.status
  , errBody = Aeson.encode r.body
  , errHeaders = jsonHeader : [ ("Retry-After", "1") | r.status == 503 ]
  }
  where
    reason = \ case
      400 -> "Bad Request"
      404 -> "Not Found"
      409 -> "Conflict"
      422 -> "Unprocessable Entity"
      503 -> "Service Unavailable"
      _ -> "Error"

jsonHeader :: (HeaderName, ByteString)
jsonHeader = ("Content-Type", "application/json")

----------------------------------------------------------------------------
-- What the ledger said
----------------------------------------------------------------------------

-- | A 'Result' as a reply.
resultReply :: Result -> LedgerReply
resultReply = \ case
  Appended {row, steps, wrote, replayed, ticks} -> MkLedgerReply 200 (Aeson.object
    [ "result" .= ("appended" :: Text)
    , "applied" .= True
    , "seq" .= row.seqNo
    , "row" .= rowJson row
    , "wrote" .= wrote
    , "ticks" .= map rowJson ticks
    , "replayed" .= replayed
    , "steps" .= length steps
    ])
  Refused {because, headSeq} -> MkLedgerReply 422 (Aeson.object
    [ "result" .= ("refused" :: Text), "applied" .= False, "because" .= because, "head" .= headSeq ])
  Conflict {because, headSeq} -> MkLedgerReply 409 (Aeson.object
    [ "result" .= ("conflict" :: Text), "applied" .= False, "because" .= because, "head" .= headSeq ])
  Unknown {because} -> MkLedgerReply 503 (notApplied because `withField` ("result" .= ("unknown" :: Text)))
  NotFound -> MkLedgerReply 404 (Aeson.object
    [ "result" .= ("not found" :: Text), "applied" .= False
    , "because" .= ("the ledger holds no such instance; an instance is created by POST /deployments/{id}/instances, never by an append or a read" :: Text) ])

notApplied :: Text -> Aeson.Value
notApplied why = Aeson.object ["result" .= ("not applied" :: Text), "applied" .= False, "because" .= why]

gone :: Text -> LedgerReply
gone deployIdText = MkLedgerReply 404 (notApplied ("no deployment " <> deployIdText))

rowJson :: Row -> Aeson.Value
rowJson r = Aeson.object
  [ "seq" .= r.seqNo
  , "event" .= case r.event of
      OpeningEvent c -> Aeson.object ["kind" .= ("opening" :: Text), "contract" .= c]
      ActEvent p a -> Aeson.object ["kind" .= ("act" :: Text), "party" .= p, "action" .= a]
      TickEvent -> Aeson.object ["kind" .= ("tick" :: Text)]
  , "at" .= timeJson r.at
  , "txTime" .= timeJson r.txTime
  , "verdict" .= case r.verdict of
      VDischarging -> Aeson.object ["kind" .= ("discharging" :: Text)]
      VBreaching who -> Aeson.object ["kind" .= ("breaching" :: Text), "party" .= who]
      VAdvancing -> Aeson.object ["kind" .= ("advancing" :: Text)]
      VPassedOver why -> Aeson.object ["kind" .= ("passed over" :: Text), "because" .= why]
  , "decidedAgainst" .= r.decidedAgainst
  , "idempotencyKey" .= r.idempotencyKey
  , "ruleVersion" .= r.ruleVersion
  ]

-- | A time on the contract clock: a JSON number when it has an exact
-- decimal form, as every stamp of the service's whole-second clock does,
-- else the string @n/d@, never a float.
timeJson :: Rational -> Aeson.Value
timeJson t = case renderStamp t of
  Right s | [(x, "")] <- reads (Text.unpack s) -> Aeson.Number x
  _ -> Aeson.String (showT (numerator t) <> "/" <> showT (denominator t))

----------------------------------------------------------------------------
-- What the control plane asks (R-O5)
----------------------------------------------------------------------------

-- | Refuse, with a 409, to delete or overwrite a deployment the ledger holds
-- instances of; refuse with a 503 when the store cannot say. A service with
-- no ledger refuses nothing.
--
-- "Live" is read as "held": an instance the contract has finished is still
-- replayed against whatever is deployed under its id, so a finished one
-- protects the deployment as an open one does. Assumed, not ruled. There is
-- no route that removes an instance, so a deployment that has had one is not
-- deleted or overwritten by an ungated @POST@ through this service; a gated
-- @PUT@ still updates it (the rule under a live instance changing is D-O9).
refuseIfInstancesHeld :: Text -> Text -> AppM ()
refuseIfInstancesHeld deployIdText doing = do
  env <- ask
  case env.ledger of
    Nothing -> pure ()
    Just ldg -> liftIO (instancesHeld ldg deployIdText) >>= \ case
      Right [] -> pure ()
      Right names -> throwError err409
        { errBody = jsonError
            ( "Deployment " <> deployIdText <> " is not " <> doing <> ": the instance ledger holds "
              <> showT (length names) <> " instance" <> (if length names == 1 then "" else "s") <> " of it ("
              <> Text.intercalate ", " (take 10 names) <> (if length names > 10 then ", …" else "")
              <> "), whose rows would replay against whatever is deployed under this id next (OPERATIONAL-LOWERING-SPEC R-O5)" )
        , errHeaders = [jsonHeader] }
      Left why -> throwError err503
        { errBody = jsonError ("Deployment " <> deployIdText <> " is not " <> doing <> ": whether the instance ledger holds instances of it is not known (" <> why <> ")")
        , errHeaders = [jsonHeader] }

-- | Run holding the ledger's creation lock, so that an instance is not
-- created between a delete's check and its last file. A service with no
-- ledger takes no lock.
withCreationLock :: AppM a -> AppM a
withCreationLock act = do
  env <- ask
  case env.ledger of
    Nothing -> act
    Just ldg -> do
      r <- liftIO (withMVar ldg.creationLock \ _ -> runHandler (runReaderT act env))
      either throwError pure r

showT :: Show a => a -> Text
showT = Text.pack . show
