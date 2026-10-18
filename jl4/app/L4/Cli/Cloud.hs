-- | Where @l4 deploy@ and friends send their requests, and how.
--
-- Two kinds of target:
--
--   * __Legalese Cloud__ (the default): credentials come from the
--     @legalese@ CLI (@legalese token@, @legalese whoami@), so the user
--     signs in once with @legalese login@ and @l4@ never stores a token.
--     Requests go to the consolidated api host,
--     @https://api.legalese.cloud/{org}@, whose path scheme differs from
--     jl4-service's (see 'deploymentPath').
--
--   * __A self-hosted jl4-service__ (@--server URL@), optionally with an
--     API key from @L4_API_KEY@ or @--api-key-file@. The Legalese Cloud
--     token is never sent here: with @--server@ the legalese CLI isn't
--     consulted at all.
--
-- Every request disables redirects, so a credential can't follow a 3xx to
-- another host.
module L4.Cli.Cloud
  ( -- * Options
    TargetOptions(..)
  , targetOptionsParser

    -- * Targets
  , Target(..)
  , resolveTarget
  , listPath
  , deploymentPath
  , updatePath

    -- * Requests
  , ApiResponse(..)
  , newRequest
  , send
  , errorMessage
  , isSuccess

    -- * The legalese CLI
  , findLegaleseCli

    -- * Output
  , die
  , note
  ) where

import Base.Text (Text)
import qualified Base.Text as Text
import Control.Exception (try)
import Control.Monad (unless, when)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Lazy as BSL
import qualified Data.ByteString.Lazy.Char8 as BSL8
import Data.Char (isSpace)
import Data.List (dropWhileEnd)
import qualified Data.Text.Encoding as TE
import Network.HTTP.Client
  ( HttpException(..)
  , Manager
  , Request
  , httpLbs
  , method
  , parseRequest
  , redirectCount
  , requestHeaders
  , responseBody
  , responseHeaders
  , responseStatus
  , responseTimeout
  , responseTimeoutMicro
  )
import Network.HTTP.Client.TLS (newTlsManager)
import Network.HTTP.Types (Method, hAuthorization, statusCode, urlEncode)
import Network.URI (URI(..), URIAuth(..), parseAbsoluteURI)
import Options.Applicative
import System.Directory (findExecutable)
import System.Environment (lookupEnv)
import System.Exit (ExitCode(..), exitFailure)
import System.Info (os)
import System.IO (stderr)
import System.Process (readProcessWithExitCode)

----------------------------------------------------------------------------
-- Options
----------------------------------------------------------------------------

data TargetOptions = TargetOptions
  { server     :: Maybe String
  , apiKeyFile :: Maybe FilePath
  }

targetOptionsParser :: Parser TargetOptions
targetOptionsParser = TargetOptions
  <$> optional (strOption
        ( long "server"
       <> metavar "URL"
       <> help "A self-hosted jl4-service. Default: Legalese Cloud, signed in with the legalese CLI (`legalese login`)"
        ))
  <*> optional (strOption
        ( long "api-key-file"
       <> metavar "FILE"
       <> help "File holding the API key for --server (or set L4_API_KEY)"
        ))

----------------------------------------------------------------------------
-- Targets
----------------------------------------------------------------------------

data Target = Target
  { baseUrl       :: String
    -- ^ No trailing slash. For Legalese Cloud, includes the @/{org}@ slug.
  , apiHost       :: Bool
    -- ^ Legalese Cloud's api-host path scheme (see 'deploymentPath').
  , authorization :: Maybe BS8.ByteString
  , label         :: Text
    -- ^ Where this is, for humans: "Legalese Cloud org 'acme' (as …)".
  , manager       :: Manager
  }

resolveTarget :: TargetOptions -> IO Target
resolveTarget opts = do
  mgr <- newTlsManager
  case opts.server of
    Just url -> serverTarget mgr url opts.apiKeyFile
    Nothing -> do
      when (opts.apiKeyFile /= Nothing) $
        die "--api-key-file only applies with --server. For Legalese Cloud, sign in with `legalese login` (or set LEGALESE_TOKEN for an API key)."
      cloudTarget mgr

serverTarget :: Manager -> String -> Maybe FilePath -> IO Target
serverTarget mgr url0 keyFile = do
  let url = dropWhileEnd (== '/') url0
  uri <- maybe (die ("--server: not a URL: " <> Text.pack url0)) pure (parseAbsoluteURI url)
  unless (uri.uriScheme `elem` ["https:", "http:"]) $
    die "--server must be an http(s) URL"
  key <- case keyFile of
    Just f -> Just . strip <$> readFile f
    Nothing -> fmap strip <$> lookupEnv "L4_API_KEY"
  let host = maybe "" (.uriRegName) uri.uriAuthority
      hasKey = maybe False (not . null) key
  when (hasKey && uri.uriScheme == "http:" && not (isLoopback host)) $
    die ("Refusing to send an API key over plain http to " <> Text.pack host <> ". Use https.")
  pure Target
    { baseUrl = url
      -- Pointing --server at the Legalese Cloud api host itself (with an
      -- API key) needs its path scheme too.
    , apiHost = host == "api.legalese.cloud"
    , authorization = if hasKey then (\k -> "Bearer " <> BS8.pack k) <$> key else Nothing
    , label = Text.pack url
    , manager = mgr
    }

cloudTarget :: Manager -> IO Target
cloudTarget mgr = do
  exe <- findLegaleseCli >>= \case
    Just exe -> pure exe
    Nothing -> die $ Text.unlines
      [ "No --server given, so this goes to Legalese Cloud, which needs the legalese CLI."
      , "Install it with `l4 install legalese`, then sign in with `legalese login`."
      ]
  token <- strip <$> runLegalese exe ["token"]
  whoami <- runLegalese exe ["--json", "whoami"]
  identity <- case Aeson.eitherDecode (BSL8.pack whoami) of
    Right (Aeson.Object o) -> pure o
    _ -> die "Could not read `legalese whoami --json`. Is the legalese CLI up to date? (`l4 install legalese`)"
  let org = textAt ["organization", "slug"] identity <|> textAt ["org"] identity
      who = textAt ["user", "email"] identity
  slug <- maybe (die "The legalese CLI isn't bound to an org. Sign in with `legalese login`, or set LEGALESE_ORG for an API key.") pure org
  apiBase <- maybe "https://api.legalese.cloud" (dropWhileEnd (== '/')) <$> lookupEnv "LEGALESE_API_URL"
  case parseAbsoluteURI apiBase of
    Just u | u.uriScheme == "https:" -> pure ()
           | u.uriScheme == "http:", Just a <- u.uriAuthority, isLoopback a.uriRegName -> pure ()
    _ -> die ("LEGALESE_API_URL must be an https URL: " <> Text.pack apiBase)
  pure Target
    { baseUrl = apiBase <> "/" <> BS8.unpack (urlEncode False (TE.encodeUtf8 slug))
    , apiHost = True
    , authorization = Just ("Bearer " <> BS8.pack token)
    , label = "Legalese Cloud org '" <> slug <> "'" <> maybe "" (\e -> " (as " <> e <> ")") who
    , manager = mgr
    }
  where
    textAt path o = go path (Aeson.Object o)
      where
        go [] (Aeson.String t) = Just t
        go (k : ks) (Aeson.Object m) = KeyMap.lookup (Key.fromText k) m >>= go ks
        go _ _ = Nothing

-- | Run the legalese CLI and return its stdout; on failure, pass its
-- stderr through (it says what's wrong, e.g. "not signed in") and exit.
runLegalese :: FilePath -> [String] -> IO String
runLegalese exe args = do
  (code, out, err) <- readProcessWithExitCode exe args ""
  case code of
    ExitSuccess -> pure out
    ExitFailure _ -> do
      Text.hPutStr stderr (Text.pack err)
      die ("`legalese " <> Text.pack (unwords args) <> "` failed. Sign in with `legalese login`.")

-- | The @legalese@ executable on PATH (an npm install on Windows is a
-- @.cmd@ shim).
findLegaleseCli :: IO (Maybe FilePath)
findLegaleseCli = do
  exe <- findExecutable "legalese"
  case exe of
    Nothing | os == "mingw32" -> findExecutable "legalese.cmd"
    _ -> pure exe

isLoopback :: String -> Bool
isLoopback h = h `elem` ["localhost", "127.0.0.1", "[::1]"]

strip :: String -> String
strip = dropWhileEnd isSpace . dropWhile isSpace

-- | Paths, in jl4-service's canonical scheme or the api host's
-- (@/deployments/{id}@ → @/{id}@ under @/{org}@).
listPath :: Target -> String
listPath t = if t.apiHost then "" else "/deployments"

deploymentPath :: Target -> Text -> String
deploymentPath t name =
  (if t.apiHost then "" else "/deployments") <> "/" <> BS8.unpack (urlEncode False (TE.encodeUtf8 name))

updatePath :: Target -> Text -> Text -> String
updatePath t name job =
  deploymentPath t name <> "/updates/" <> BS8.unpack (urlEncode False (TE.encodeUtf8 job))

----------------------------------------------------------------------------
-- Requests
----------------------------------------------------------------------------

data ApiResponse = ApiResponse
  { status :: Int
  , body   :: BSL.ByteString
  }

-- | A request to @baseUrl <> path@ with the target's credentials and no
-- redirects.
newRequest :: Target -> Method -> String -> IO Request
newRequest t m path = do
  req <- parseRequest (t.baseUrl <> path)
  pure req
    { method = m
    , redirectCount = 0
    , requestHeaders =
        ("Accept", "application/json")
          : ("User-Agent", "l4-cli")
          : maybe [] (\a -> [(hAuthorization, a)]) t.authorization
    , responseTimeout = responseTimeoutMicro (5 * 60 * 1000000)
    }

send :: Target -> Request -> IO ApiResponse
send t req = do
  r <- try (httpLbs req t.manager)
  case r of
    Left (HttpExceptionRequest _ content) ->
      die ("Could not reach " <> t.label <> ": " <> Text.pack (show content))
    Left (InvalidUrlException url why) ->
      die ("Invalid URL " <> Text.pack url <> ": " <> Text.pack why)
    Right resp -> do
      let code = statusCode (responseStatus resp)
      when (code >= 300 && code < 400) $
        die ( t.label <> " answered with a redirect"
           <> maybe "" (\l -> " to " <> TE.decodeUtf8Lenient l) (lookup "Location" (responseHeaders resp))
           <> ". Not following it with your credentials; check the URL." )
      pure ApiResponse { status = code, body = responseBody resp }

isSuccess :: ApiResponse -> Bool
isSuccess r = r.status >= 200 && r.status < 300

-- | The server's reason for a failed request: the JSON @error@/@message@
-- field when there is one, else the body text, else the status.
errorMessage :: ApiResponse -> Text
errorMessage r = case Aeson.decode r.body of
  Just (Aeson.Object o)
    | Just (Aeson.String e) <- KeyMap.lookup "error" o <|> KeyMap.lookup "message" o -> withStatus e
  _ | BSL.null r.body -> withStatus (statusText r.status)
    | otherwise -> withStatus (Text.strip (Text.take 500 (TE.decodeUtf8Lenient (BSL.toStrict r.body))))
  where
    withStatus msg = Text.pack (show r.status) <> ": " <> msg
    statusText = \case
      401 -> "not signed in, or the session expired"
      403 -> "not allowed"
      404 -> "not found"
      _ -> "request failed"

----------------------------------------------------------------------------
-- Output
----------------------------------------------------------------------------

-- | Print to stderr and exit 1.
die :: Text -> IO a
die msg = do
  Text.hPutStrLn stderr (Text.stripEnd msg)
  exitFailure

-- | A progress line on stderr (stdout stays clean for @--json@).
note :: Text -> IO ()
note = Text.hPutStrLn stderr
