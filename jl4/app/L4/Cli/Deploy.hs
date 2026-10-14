-- | @l4 deploy@, @l4 redeploy@, @l4 undeploy@, @l4 deployments@ — manage
-- deployments on Legalese Cloud or a self-hosted jl4-service, the way the
-- VS Code extension's Deployments tab does.
--
-- @deploy@ creates and refuses to touch an existing deployment;
-- @redeploy@ updates and refuses to create one. An update goes through
-- the service's compatibility gate (@PUT@), which rejects changes that
-- would break existing integrations; @redeploy --force@ overwrites past
-- it (@POST@), as the extension does once you confirm the breaking change.
--
-- The upload is the file plus its transitive imports, flat by file name,
-- typechecked locally first. Like the extension's, it includes the
-- standard libraries the file imports (prelude, daydate, …).
module L4.Cli.Deploy
  ( DeployOptions(..)
  , deployOptionsParser
  , redeployOptionsParser
  , deployCmd
  , redeployCmd
  , UndeployOptions(..)
  , undeployOptionsParser
  , undeployCmd
  , DeploymentsOptions(..)
  , deploymentsOptionsParser
  , deploymentsCmd
  ) where

import Base.Text (Text)
import qualified Base.Text as Text
import qualified Codec.Archive.Zip as Zip
import Control.Concurrent (threadDelay)
import Control.Exception (IOException, try)
import Control.Monad (forM, unless, when)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString.Lazy as BSL
import qualified Data.ByteString.Lazy.Char8 as BSL8
import Data.Char (isAscii, isAlphaNum)
import Data.List (sortOn)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, mapMaybe)
import qualified Data.Set as Set
import qualified Data.Text.Encoding as TE
import qualified Data.Vector as Vector
import Data.Time.Clock.POSIX (getPOSIXTime)
import Network.HTTP.Client (RequestBody(..), method)
import Network.HTTP.Client.MultipartFormData (formDataBody, partBS, partContentType, partFileRequestBody)
import Options.Applicative
import System.Directory (doesFileExist, makeAbsolute)
import System.Exit (exitFailure)
import System.FilePath (dropExtension, isAbsolute, takeFileName)
import System.IO (hFlush, hIsTerminalDevice, stderr, stdin)

import qualified LSP.Core.Shake as Shake
import qualified LSP.L4.Rules as Rules
import Language.LSP.Protocol.Types
  ( NormalizedUri
  , fromNormalizedFilePath
  , normalizedFilePathToUri
  , uriToNormalizedFilePath
  )
import qualified L4.API.EmbeddedLibraries as EmbeddedLibraries
import L4.Syntax (Module(..))

import L4.Cli.Cloud
import L4.Cli.Common (FixedNowOpt(..), makeEvalConfig, putDiagnostics, runOneshot)

----------------------------------------------------------------------------
-- Options
----------------------------------------------------------------------------

data DeployOptions = DeployOptions
  { file        :: FilePath
  , name        :: Maybe Text
  , description :: Maybe Text
  , force       :: Bool
  , noWait      :: Bool
  , jsonOut     :: Bool
  , target      :: TargetOptions
  }

deployOptionsParser :: Parser DeployOptions
deployOptionsParser = commonDeployOptions (pure False)

redeployOptionsParser :: Parser DeployOptions
redeployOptionsParser = commonDeployOptions $
  switch
    ( long "force"
   <> help "Apply the update even if it breaks existing integrations (removed or changed functions)"
    )

commonDeployOptions :: Parser Bool -> Parser DeployOptions
commonDeployOptions forceP = DeployOptions
  <$> strArgument (metavar "FILE" <> help "The .l4 file to deploy (its imports are included)")
  <*> optional (strOption
        ( long "name"
       <> metavar "NAME"
       <> help "Deployment name (default: the file name, e.g. tax-rules for tax-rules.l4)"
        ))
  <*> optional (strOption
        ( long "description"
       <> metavar "TEXT"
       <> help "Intended use, shown to integrators and AI agents (kept when omitted on redeploy)"
        ))
  <*> forceP
  <*> switch (long "no-wait" <> help "Return once the upload is accepted, without waiting for it to compile")
  <*> switch (long "json" <> help "Print the result as JSON")
  <*> targetOptionsParser

data UndeployOptions = UndeployOptions
  { name    :: Text
  , yes     :: Bool
  , target  :: TargetOptions
  }

undeployOptionsParser :: Parser UndeployOptions
undeployOptionsParser = UndeployOptions
  <$> strArgument (metavar "NAME" <> help "The deployment to delete")
  <*> switch (long "yes" <> help "Don't ask for confirmation (required when not run from a terminal)")
  <*> targetOptionsParser

data DeploymentsOptions = DeploymentsOptions
  { jsonOut :: Bool
  , target  :: TargetOptions
  }

deploymentsOptionsParser :: Parser DeploymentsOptions
deploymentsOptionsParser = DeploymentsOptions
  <$> switch (long "json" <> help "Print the service's JSON")
  <*> targetOptionsParser

----------------------------------------------------------------------------
-- deploy / redeploy
----------------------------------------------------------------------------

data Mode = Create | Update

deployCmd :: DeployOptions -> IO ()
deployCmd = publish Create

redeployCmd :: DeployOptions -> IO ()
redeployCmd = publish Update

publish :: Mode -> DeployOptions -> IO ()
publish mode opts = do
  depName <- either die pure $ deploymentName opts.file opts.name
  files <- bundle opts.file
  t <- resolveTarget opts.target

  existing <- lookupDeployment t depName
  case (mode, existing) of
    (Create, Just _) -> die $
      "'" <> depName <> "' already exists in " <> t.label <> ".\n"
        <> "Update it with `l4 redeploy " <> Text.pack opts.file <> nameFlag opts <> "`."
    (Update, Nothing) -> die $
      "There is no deployment '" <> depName <> "' in " <> t.label <> ".\n"
        <> "Create it with `l4 deploy " <> Text.pack opts.file <> nameFlag opts <> "`."
    _ -> pure ()

  note $ verb <> " '" <> depName <> "' to " <> t.label <> ": "
    <> Text.intercalate ", " (map (Text.pack . fst) files)

  now <- round <$> getPOSIXTime
  let zipBytes = Zip.fromArchive $ foldr Zip.addEntryToArchive Zip.emptyArchive
        [ Zip.toEntry n now c | (n, c) <- files ]
      overwrite = case mode of
        Create -> True
        Update -> opts.force
      (httpMethod, path) =
        if overwrite then ("POST", listPath t) else ("PUT", deploymentPath t depName)
      parts =
        [ (partFileRequestBody "sources" "sources.zip" (RequestBodyLBS zipBytes))
            { partContentType = Just "application/zip" } ]
        <> [ partBS "id" (TE.encodeUtf8 depName) | overwrite ]
        <> [ partBS "description" (TE.encodeUtf8 d)
           | Just d <- [Text.strip <$> opts.description <|> keptDescription], not (Text.null d) ]
      -- PUT keeps the stored description when none is sent; the POST
      -- behind --force replaces it, so carry it over.
      keptDescription
        | overwrite = existing >>= objectField "metadata" >>= textField "description"
        | otherwise = Nothing
  req <- newRequest t httpMethod path >>= formDataBody parts
  resp <- send t req { method = httpMethod }
  unless (isSuccess resp) $
    die (verb <> " failed: " <> errorMessage resp)

  let accepted = decodeObject resp.body
      updateId = accepted >>= textField "updateId"
      result status extra = Aeson.object $
        [ "deployment" Aeson..= depName
        , "target"     Aeson..= t.baseUrl
        , "status"     Aeson..= (status :: Text)
        , "files"      Aeson..= map fst files
        , "updateId"   Aeson..= updateId
        ] <> extra

  outcome <-
    if opts.noWait
      then pure (Right "accepted")
      else case updateId of
        Just job -> do
          note "Compiling…"
          waitForJob t depName job
        -- No job: the sources are identical to what's deployed (or an
        -- older service). Fall back to the deployment's own status.
        Nothing
          | (accepted >>= textField "status") == Just "ready" -> pure (Right "unchanged")
          | otherwise -> do
              note "Compiling…"
              waitForDeployment t depName

  case outcome of
    Left err -> do
      let hint = case mode of
            Update | not opts.force, "Update rejected" `Text.isPrefixOf` err ->
              "\nTo apply it anyway, run `l4 redeploy " <> Text.pack opts.file <> nameFlag opts <> " --force`."
            _ -> ""
      if opts.jsonOut
        then BSL8.putStrLn (Aeson.encode (result "rejected" ["error" Aeson..= err]))
        else note (err <> hint)
      exitFailure
    Right "accepted" ->
      if opts.jsonOut
        then BSL8.putStrLn (Aeson.encode (result "accepted" []))
        else Text.putStrLn $
          "Accepted '" <> depName <> "'"
            <> maybe "" (\j -> " (job " <> j <> ")") updateId
            <> ". Check on it with `l4 deployments`."
    Right status -> do
      deployed <- getDeployment t depName
      let meta = deployed >>= objectField "metadata"
          fns = maybe [] (mapMaybe (textField "name") . arrayField "functions") meta
          version = meta >>= textField "deploymentVersion"
          url = Text.pack (t.baseUrl <> deploymentPath t depName)
      if opts.jsonOut
        then BSL8.putStrLn $ Aeson.encode $ result status
          [ "version"   Aeson..= version
          , "functions" Aeson..= fns
          , "url"       Aeson..= url
          ]
        else do
          Text.putStrLn $
            (if status == "unchanged" then "'" <> depName <> "' is already up to date" else "Deployed '" <> depName <> "'")
              <> maybe "" (\v -> " (version " <> v <> ")") version
              <> case fns of
                   [] -> "."
                   _ -> " with " <> plural (length fns) "function" <> ":"
          mapM_ (Text.putStrLn . ("  " <>)) fns
          Text.putStrLn ("API: " <> url)
  where
    verb = case mode of
      Create -> "Deploying"
      Update -> "Redeploying"

nameFlag :: DeployOptions -> Text
nameFlag opts = maybe "" (\n -> " --name " <> n) opts.name

-- | The deployment name: @--name@, or the file name made safe (as the
-- extension's sidebar does). jl4-service allows @[A-Za-z0-9_-]@, ≤ 36.
deploymentName :: FilePath -> Maybe Text -> Either Text Text
deploymentName fp explicit
  | Text.null n = Left "The deployment name is empty. Pass --name."
  | Text.length n > 36 = Left ("'" <> n <> "' is longer than 36 characters. Pass a shorter --name.")
  | not (Text.all validChar n) = Left ("'" <> n <> "' may only contain letters, digits, - and _.")
  | n `elem` ["health", "deployments", "openapi.json"] = Left ("'" <> n <> "' is reserved. Pass another --name.")
  | otherwise = Right n
  where
    n = case explicit of
      Just e -> Text.strip e
      Nothing -> Text.map (\c -> if validChar c then c else '-') (Text.pack (dropExtension (takeFileName fp)))
    validChar c = isAscii c && (isAlphaNum c || c == '-' || c == '_')

-- | Typecheck the file and collect it plus its transitive imports as
-- (name in the zip, contents), root first.
bundle :: FilePath -> IO [(FilePath, BSL.ByteString)]
bundle fp = do
  absFp <- makeAbsolute fp
  present <- doesFileExist absFp
  unless present $ die ("No such file: " <> Text.pack fp)
  evalConfig <- makeEvalConfig (FixedNowOpt Nothing)
  (errs, mTc) <- runOneshot evalConfig absFp \nfp -> do
    _ <- Shake.addVirtualFileFromFS nfp
    Shake.use Rules.SuccessfulTypeCheck (normalizedFilePathToUri nfp)
  tc <- case mTc of
    Just tc | tc.success -> pure tc
    _ -> do
      putDiagnostics errs
      die (Text.pack fp <> " doesn't typecheck; fix it before deploying (see `l4 check`).")

  let paths = absFp : mapMaybe moduleFile (drop 1 (flatten tc))
  files <- fmap concat $ forM (dedupe paths) \p ->
    if isAbsolute p
      then pure . (p,) <$> BSL.readFile p
      -- A standard library the typechecker took from the copies built
      -- into l4 (nothing on disk); the extension uploads its bundled copy.
      else case EmbeddedLibraries.lookupEmbeddedLibrary (Text.pack (dropExtension (takeFileName p))) of
        Just src -> pure [(p, BSL.fromStrict (TE.encodeUtf8 src))]
        Nothing -> [] <$ note ("Skipping " <> Text.pack p <> ": not found")

  let byName = Map.fromListWith (flip (<>)) [ (takeFileName p, [p]) | (p, _) <- files ]
  case [ (n, ps) | (n, ps@(_ : _ : _)) <- Map.toList byName ] of
    [] -> pure ()
    clashes -> die $ Text.unlines $
      "These imported files share a name, but the upload is flat (as from VS Code). Rename one of each:"
        : [ "  " <> Text.pack n <> ": " <> Text.intercalate ", " (map Text.pack ps) | (n, ps) <- clashes ]
  pure [ (takeFileName p, c) | (p, c) <- files ]
  where
    moduleUri :: Rules.TypeCheckResult -> NormalizedUri
    moduleUri r = case r.module' of MkModule _ u _ -> u
    moduleFile r = fromNormalizedFilePath <$> uriToNormalizedFilePath (moduleUri r)
    -- The dependency tree visits a module once per import path; keep the
    -- first (pre-order), as the LSP's l4/getExportedFunctions does.
    flatten root = snd (go Set.empty root)
      where
        go seen r
          | moduleUri r `Set.member` seen = (seen, [])
          | otherwise =
              let step (s, acc) d = let (s', xs) = go s d in (s', acc <> xs)
                  (seenN, deps) = foldl step (Set.insert (moduleUri r) seen, []) r.dependencies
              in (seenN, r : deps)
    dedupe = go Set.empty
      where
        go _ [] = []
        go s (x : xs)
          | x `Set.member` s = go s xs
          | otherwise = x : go (Set.insert x s) xs

-- | The deployment's status (without functions), or Nothing if there's
-- no such deployment.
lookupDeployment :: Target -> Text -> IO (Maybe Aeson.Object)
lookupDeployment t depName = do
  r <- send t =<< newRequest t "GET" (deploymentPath t depName <> "?functions=none")
  if r.status == 404
    then pure Nothing
    else if isSuccess r
      then pure (Just (fromMaybe mempty (decodeObject r.body)))
      else die ("Could not look up '" <> depName <> "' in " <> t.label <> ": " <> errorMessage r)

getDeployment :: Target -> Text -> IO (Maybe Aeson.Object)
getDeployment t depName = do
  r <- send t =<< newRequest t "GET" (deploymentPath t depName)
  pure (if isSuccess r then decodeObject r.body else Nothing)

-- | Poll a deploy/update job until it's applied (Right) or rejected (Left).
waitForJob :: Target -> Text -> Text -> IO (Either Text Text)
waitForJob t depName job = poll \n -> do
  r <- send t =<< newRequest t "GET" (updatePath t depName job)
  if r.status == 404 && n == 0
    then Just <$> waitForDeployment t depName -- a service without job polling
    else do
      unless (isSuccess r) $ pollFailed t depName r
      let o = decodeObject r.body
      pure $ case o >>= textField "status" of
        Just "applied" -> Just (Right "deployed")
        Just "rejected" -> Just (Left (fromMaybe "The update was rejected." (o >>= textField "error")))
        _ -> Nothing

-- | Poll the deployment itself until it's ready or failed.
waitForDeployment :: Target -> Text -> IO (Either Text Text)
waitForDeployment t depName = poll \_ -> do
  r <- send t =<< newRequest t "GET" (deploymentPath t depName <> "?functions=none")
  unless (isSuccess r) $ pollFailed t depName r
  let o = decodeObject r.body
  pure $ case o >>= textField "status" of
    Just "ready" -> Just (Right "deployed")
    Just "failed" -> Just (Left ("Compilation failed: " <> fromMaybe "no details" (o >>= textField "error")))
    _ -> Nothing

-- | Call @step@ every second or two until it answers, for up to 10 minutes.
poll :: (Int -> IO (Maybe a)) -> IO a
poll step = go 0
  where
    go n
      | n >= 400 = die "Still compiling after 10 minutes. Check on it later with `l4 deployments`."
      | otherwise = step n >>= \case
          Just a -> pure a
          Nothing -> threadDelay (if n < 10 then 1000000 else 2000000) >> go (n + 1)

pollFailed :: Target -> Text -> ApiResponse -> IO a
pollFailed t depName r = die $
  "Lost track of '" <> depName <> "' in " <> t.label <> " (" <> errorMessage r <> ").\n"
    <> "The upload was accepted; check on it with `l4 deployments`."

----------------------------------------------------------------------------
-- undeploy
----------------------------------------------------------------------------

undeployCmd :: UndeployOptions -> IO ()
undeployCmd opts = do
  t <- resolveTarget opts.target
  -- No lookup first: Legalese Cloud answers lookups from a read model that
  -- can lag a minute behind a recent undeploy/redeploy of the same name,
  -- while DELETE reaches the service itself.
  unless opts.yes do
    tty <- hIsTerminalDevice stdin
    unless tty $
      die "Refusing to undeploy without confirmation. Pass --yes."
    note $ "This deletes '" <> opts.name <> "' from " <> t.label
      <> ". Anything calling it will stop working."
    Text.hPutStr stderr "Type the deployment name to confirm: "
    hFlush stderr
    answer <- try @IOException Text.getLine
    when (fmap Text.strip answer /= Right opts.name) $
      die "Not confirmed; nothing was deleted."
  r <- send t =<< newRequest t "DELETE" (deploymentPath t opts.name)
  when (r.status == 404) $
    die ("There is no deployment '" <> opts.name <> "' in " <> t.label <> ".")
  unless (isSuccess r) $
    die ("Undeploy failed: " <> errorMessage r)
  Text.putStrLn ("Undeployed '" <> opts.name <> "' from " <> t.label <> ".")

----------------------------------------------------------------------------
-- deployments
----------------------------------------------------------------------------

deploymentsCmd :: DeploymentsOptions -> IO ()
deploymentsCmd opts = do
  t <- resolveTarget opts.target
  r <- send t =<< newRequest t "GET" (listPath t)
  unless (isSuccess r) $
    die ("Could not list deployments in " <> t.label <> ": " <> errorMessage r)
  let deployments = case Aeson.decode r.body of
        Just (Aeson.Array a) -> [ o | Aeson.Object o <- Vector.toList a ]
        Just (Aeson.Object o) -> arrayField "deployments" o
        _ -> []
  if opts.jsonOut
    then BSL8.putStrLn (Aeson.encode deployments)
    else if null deployments
      then note ("No deployments in " <> t.label <> ".")
      else do
        note ("Deployments in " <> t.label <> ":")
        let row o =
              let meta = objectField "metadata" o
              in [ fromMaybe "?" (textField "id" o)
                 , fromMaybe "?" (textField "status" o)
                 , fromMaybe "" (meta >>= textField "deploymentVersion")
                 , maybe "" (Text.pack . show . length . arrayField "functions") meta
                 , oneLine (fromMaybe "" (meta >>= textField "description"))
                 ]
            rows = ["NAME", "STATUS", "VERSION", "FUNCTIONS", "DESCRIPTION"]
              : sortOn (map Text.toLower) (map row deployments)
            widths = map (maximum . map Text.length) (transposeRows rows)
            render cells = Text.stripEnd $ Text.intercalate "  " $
              zipWith (\w c -> Text.justifyLeft w ' ' c) widths cells
        mapM_ (Text.putStrLn . render) rows
  where
    transposeRows rows = foldr (zipWith (:)) (repeat []) rows
    oneLine d =
      let s = Text.unwords (Text.words d)
      in if Text.length s > 60 then Text.take 59 s <> "…" else s

----------------------------------------------------------------------------
-- JSON helpers
----------------------------------------------------------------------------

decodeObject :: BSL.ByteString -> Maybe Aeson.Object
decodeObject b = case Aeson.decode b of
  Just (Aeson.Object o) -> Just o
  _ -> Nothing

textField :: Text -> Aeson.Object -> Maybe Text
textField k o = KeyMap.lookup (Key.fromText k) o >>= \case
  Aeson.String s -> Just s
  _ -> Nothing

objectField :: Text -> Aeson.Object -> Maybe Aeson.Object
objectField k o = case KeyMap.lookup (Key.fromText k) o of
  Just (Aeson.Object x) -> Just x
  _ -> Nothing

arrayField :: Text -> Aeson.Object -> [Aeson.Object]
arrayField k o = case KeyMap.lookup (Key.fromText k) o of
  Just (Aeson.Array a) -> [ x | Aeson.Object x <- Vector.toList a ]
  _ -> []

plural :: Int -> Text -> Text
plural 1 w = "1 " <> w
plural n w = Text.pack (show n) <> " " <> w <> "s"
