module Options (
  Options (..),
  buildOpts,
  parseOptions,
  parseOptionsPure,
) where

import Data.Char (toLower)
import Data.List (isPrefixOf)
import Data.Maybe (isNothing)
import Data.Text (Text)
import qualified Data.Text as Text
import Options.Applicative
import System.Environment (getProgName, lookupEnv)
import System.Exit (ExitCode (..), exitSuccess, exitWith)
import System.IO (hPutStrLn, stderr)
import Text.Read (readMaybe)

data Options = Options
  { port                  :: !Int
  , storePath             :: !FilePath
  , serverName            :: !(Maybe Text)
  , instanceToken         :: !(Maybe Text)
  , lazyLoad              :: !Bool
  , debug                 :: !Bool
  , maxZipSize            :: !Int
  , maxFileCount          :: !Int
  , maxDeployments        :: !Int
  , maxConcurrentRequests :: !Int
  , maxEvalMemoryMb       :: !Int
  , maxCompileMemoryMb    :: !Int
  , evalTimeout           :: !Int
  , compileTimeout        :: !Int
  , maxLadderNodes        :: !Int
  -- ^ Ceiling on the size of a ladder visualization, in IR nodes.
  --
  -- Unlike the other limits here this one bounds a RESPONSE, not an input or a
  -- runtime. The ladder is built by distributing OR over AND to reach CNF, so
  -- its size is exponential in the width of a disjunction of conjunctions:
  -- @(a AND b) OR (c AND d) OR …@ over 2n variables expands to 2^n clauses.
  -- Measured on this service, 8 variables give a 12 KB response, 16 give 366 KB
  -- and 32 give tens of megabytes over minutes — while the request that asks
  -- for it is a bare unauthenticated GET holding one of the
  -- 'maxConcurrentRequests' slots the whole time. No timeout bounds that: the
  -- cost is in serializing the answer, not in computing it.
  --
  -- The default is far above anything a person could read off a diagram
  -- (a few hundred nodes is already a wall of boxes) and far below the
  -- pathological cases, so a legitimate model should never meet it. Raise it if
  -- one does.
  , checkStore            :: !(Maybe FilePath)
  -- ^ With a directory here the service does not serve. It compiles every
  -- deployment stored in the directory, the way a restart does and under the
  -- same limits, reports one line for each, and exits ('CheckStore'). It starts
  -- no server and writes nothing to the directory, so an operator can run a new
  -- binary over a store before a rollout switches to it.
  , checkJson             :: !Bool
  -- ^ With 'checkStore': print the report as one JSON document.
  }

-- | Build the CLI parser with environment variable defaults.
-- Env vars are read first; CLI args override them.
buildOpts :: IO (ParserInfo Options)
buildOpts = do
  envPort       <- readEnvInt "JL4_PORT"
  envStorePath  <- lookupEnv "JL4_STORE_PATH"
  envServerName <- lookupEnv "JL4_SERVER_NAME"
  envInstToken  <- lookupEnv "JL4_INSTANCE_TOKEN"
  envLazyLoad   <- readEnvBool "JL4_LAZY_LOAD"
  envDebug      <- readEnvBool "JL4_DEBUG"
  envMaxZip     <- readEnvInt "JL4_MAX_ZIP_SIZE"
  envMaxFiles   <- readEnvInt "JL4_MAX_FILE_COUNT"
  envMaxDeploy  <- readEnvInt "JL4_MAX_DEPLOYMENTS"
  envMaxConc    <- readEnvInt "JL4_MAX_CONCURRENT_REQUESTS"
  envMaxMem     <- readEnvInt "JL4_MAX_EVAL_MEMORY_MB"
  envMaxCompMem <- readEnvInt "JL4_MAX_COMPILE_MEMORY_MB"
  envEvalTO     <- readEnvInt "JL4_EVAL_TIMEOUT"
  envCompTO     <- readEnvInt "JL4_COMPILE_TIMEOUT"
  envMaxLadder  <- readEnvInt "JL4_MAX_LADDER_NODES"

  let parser = Options
        <$> option auto
              ( long "port"
                  <> short 'p'
                  <> metavar "PORT"
                  <> value (maybe 8080 id envPort)
                  <> showDefault
                  <> help "HTTP port to listen on (env: JL4_PORT)"
              )
        <*> strOption
              ( long "store-path"
                  <> metavar "PATH"
                  <> value (maybe "/tmp/jl4-store" id envStorePath)
                  <> showDefault
                  <> help "Directory for persisting deployment bundles (env: JL4_STORE_PATH)"
              )
        <*> optional
              ( strOption
                  ( long "server-name"
                      <> short 's'
                      <> metavar "NAME"
                      <> maybe mempty value (Text.pack <$> envServerName)
                      <> help "Server name exposed in OpenAPI metadata (env: JL4_SERVER_NAME)"
                  )
              )
        <*> optional
              ( strOption
                  ( long "instance-token"
                      <> metavar "TOKEN"
                      <> maybe mempty value (Text.pack <$> envInstToken)
                      <> help "Opaque token returned in /health for process identity verification (env: JL4_INSTANCE_TOKEN)"
                  )
              )
        <*> ( switch
                ( long "lazy-load"
                    <> help "Compile deployments on first request instead of at startup (env: JL4_LAZY_LOAD)"
                )
              <|> pure (maybe False id envLazyLoad)
            )
        <*> ( switch
                ( long "debug"
                    <> help "Enable debug mode: verbose logging and detailed error responses (env: JL4_DEBUG)"
                )
              <|> pure (maybe False id envDebug)
            )
        <*> option auto
              ( long "max-zip-size"
                  <> metavar "BYTES"
                  <> value (maybe 2097152 id envMaxZip)
                  <> showDefault
                  <> help "Maximum upload zip file size in bytes (env: JL4_MAX_ZIP_SIZE)"
              )
        <*> option auto
              ( long "max-file-count"
                  <> metavar "COUNT"
                  <> value (maybe 5096 id envMaxFiles)
                  <> showDefault
                  <> help "Maximum number of files per deployment zip (env: JL4_MAX_FILE_COUNT)"
              )
        <*> option auto
              ( long "max-deployments"
                  <> metavar "COUNT"
                  <> value (maybe 1024 id envMaxDeploy)
                  <> showDefault
                  <> help "Maximum number of concurrent deployments (env: JL4_MAX_DEPLOYMENTS)"
              )
        <*> option auto
              ( long "max-concurrent-requests"
                  <> metavar "COUNT"
                  <> value (maybe 20 id envMaxConc)
                  <> showDefault
                  <> help "Maximum number of concurrent requests (env: JL4_MAX_CONCURRENT_REQUESTS)"
              )
        <*> option auto
              ( long "max-eval-memory-mb"
                  <> metavar "MB"
                  <> value (maybe 256 id envMaxMem)
                  <> showDefault
                  <> help "Maximum memory allocation per evaluation in MB (env: JL4_MAX_EVAL_MEMORY_MB)"
              )
        <*> option auto
              ( long "max-compile-memory-mb"
                  <> metavar "MB"
                  <> value (maybe 256 id envMaxCompMem)
                  <> showDefault
                  <> help "Maximum memory allocation per compilation in MB (env: JL4_MAX_COMPILE_MEMORY_MB)"
              )
        <*> option auto
              ( long "eval-timeout"
                  <> metavar "SECONDS"
                  <> value (maybe 60 id envEvalTO)
                  <> showDefault
                  <> help "Evaluation timeout in seconds (env: JL4_EVAL_TIMEOUT)"
              )
        <*> option auto
              ( long "compile-timeout"
                  <> metavar "SECONDS"
                  <> value (maybe 60 id envCompTO)
                  <> showDefault
                  <> help "Compilation timeout in seconds (env: JL4_COMPILE_TIMEOUT)"
              )
        <*> option auto
              ( long "max-ladder-nodes"
                  <> metavar "COUNT"
                  <> value (maybe 10000 id envMaxLadder)
                  <> showDefault
                  <> help
                       "Maximum ladder-diagram size, in IR nodes, that query-plan and ladder \
                       \will build or serve (env: JL4_MAX_LADDER_NODES)"
              )
        <*> optional
              ( strOption
                  ( long "check-store"
                      <> metavar "DIR"
                      <> help
                           "Compile every deployment stored in DIR the way a restart does, under \
                           \--compile-timeout and --max-compile-memory-mb, print one line for each, \
                           \and exit. Starts no server and writes nothing to DIR. Exit status: 0 if \
                           \every deployment compiles, 1 if any does not, 2 for a usage or I/O error"
                  )
              )
        <*> switch
              ( long "json"
                  <> help "With --check-store, print the report as one JSON document"
              )

  pure $ info
    (parser <**> helper)
    ( fullDesc
        <> progDesc "Multi-tenant decision service for L4 rule bundles"
        <> header "jl4-service — persistent, multi-tenant L4 decision service"
    )

-- | Parse the command line, and exit as 'parseOptionsPure' says if it does not
-- parse.
parseOptions :: ParserInfo Options -> [String] -> IO Options
parseOptions parserInfo args = do
  progName <- getProgName
  case parseOptionsPure progName parserInfo args of
    Right options -> pure options
    Left (Left completion) -> do
      completions <- execCompletion completion progName
      putStr completions
      exitSuccess
    Left (Right (message, code)) -> do
      case code of
        ExitSuccess -> putStrLn message
        ExitFailure _ -> hPutStrLn stderr message
      exitWith code

-- | The parse of a command line, or why it is not one: the message to print
-- and the exit status to give it (@--help@ is a success, with the help as its
-- message).
--
-- A command line that does not parse is a usage error. optparse-applicative
-- gives it status 1; with @--check-store@ that is the status for "a deployment
-- failed", so a usage error there is 2 and a script can tell the two apart. The
-- server's own status for a usage error is unchanged.
parseOptionsPure
  :: String
  -> ParserInfo Options
  -> [String]
  -> Either (Either CompletionResult (String, ExitCode)) Options
parseOptionsPure progName parserInfo args = case execParserPure defaultPrefs parserInfo args of
  Success options
    | options.checkJson && isNothing options.checkStore ->
        Left (Right ("--json goes with --check-store, which was not given", ExitFailure 2))
    | otherwise -> Right options
  CompletionInvoked completion -> Left (Left completion)
  Failure failure ->
    let (message, code) = renderFailure failure progName
        code' = case code of
          ExitFailure 1 | any ("--check-store" `isPrefixOf`) args -> ExitFailure 2
          _ -> code
    in Left (Right (message, code'))

-- | Read an optional integer from an environment variable.
readEnvInt :: String -> IO (Maybe Int)
readEnvInt name = do
  mVal <- lookupEnv name
  pure (mVal >>= readMaybe)

-- | Read an optional boolean from an environment variable.
-- Accepts "1", "true", "yes" (case-insensitive) as True.
readEnvBool :: String -> IO (Maybe Bool)
readEnvBool name = do
  mVal <- lookupEnv name
  pure $ mVal >>= \val ->
    case map toLower val of
      "1"    -> Just True
      "true" -> Just True
      "yes"  -> Just True
      "0"     -> Just False
      "false" -> Just False
      "no"    -> Just False
      _      -> Nothing
