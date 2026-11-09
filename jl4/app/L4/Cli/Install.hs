{-# LANGUAGE CPP #-}
-- | @l4 install legalese@ — download the @legalese@ CLI (which signs you in
-- to Legalese Cloud for @l4 deploy@) and put it on your PATH.
--
-- Does what https://legalese.cloud/cli/install.sh does, except that the
-- checksum is required: a binary with no matching @SHA256SUMS@ entry is
-- not installed. It never escalates with sudo; when @/usr/local/bin@
-- isn't writable it installs to @~/.local/bin@.
module L4.Cli.Install
  ( InstallOptions(..)
  , installOptionsParser
  , installCmd
  ) where

import qualified Base.Text as Text
import Control.Exception (SomeException, onException, try)
import Control.Monad (unless, when)
import Crypto.Hash (Digest, SHA256, hashlazy)
import qualified Data.ByteString.Lazy as BSL
import qualified Data.ByteString.Lazy.Char8 as BSL8
import Data.Char (toLower)
import Data.Maybe (listToMaybe)
import Network.HTTP.Client (httpLbs, parseRequest, requestHeaders, responseBody, responseStatus)
import Network.HTTP.Client.TLS (newTlsManager)
import Network.HTTP.Types (statusCode)
import Options.Applicative
import System.Directory
  ( createDirectoryIfMissing
  , doesDirectoryExist
  , getHomeDirectory
  , getPermissions
  , removeFile
  , renameFile
  , writable
  )
import System.Exit (ExitCode(..))
#if !defined(mingw32_HOST_OS)
import System.Posix.Files (setFileMode)
#endif
import System.FilePath (getSearchPath, normalise, takeDirectory, (</>))
import System.Info (arch, os)
import System.IO (hClose, openBinaryTempFile)
import System.Process (readProcessWithExitCode)

import L4.Cli.Cloud (die, findLegaleseCli, note)

data InstallOptions = InstallOptions
  { dir :: Maybe FilePath
  }

installOptionsParser :: Parser InstallOptions
installOptionsParser = subparser $
  command "legalese"
    (info (helper <*> (InstallOptions <$> optional (strOption
              ( long "dir"
             <> metavar "DIR"
             <> help "Install into DIR (default: /usr/local/bin if writable, else ~/.local/bin)"
              ))))
      (progDesc "Install or upgrade the legalese CLI (signs you in to Legalese Cloud for `l4 deploy`)"))

downloadBase :: String
downloadBase = "https://legalese.cloud/cli/latest"

installCmd :: InstallOptions -> IO ()
installCmd opts = do
  asset <- case (os, arch) of
    ("darwin", a) | Just a' <- archName a -> pure ("legalese-darwin-" <> a')
    ("linux", a)  | Just a' <- archName a -> pure ("legalese-linux-" <> a')
    _ -> die ("There's no prebuilt legalese CLI for " <> Text.pack os <> "/" <> Text.pack arch <> " yet.\n"
           <> "Deploy from the VS Code extension instead, or to your own jl4-service with `l4 deploy FILE --server URL`.")

  mgr <- newTlsManager
  let fetch what url = do
        -- Legalese Cloud's firewall turns away requests with no User-Agent.
        r <- try (parseRequest url >>= \req -> httpLbs req { requestHeaders = [("User-Agent", "l4-cli")] } mgr)
        case r of
          Left (e :: SomeException) -> die ("Could not download " <> what <> ": " <> Text.pack (show e))
          Right resp -> do
            let code = statusCode (responseStatus resp)
            unless (code == 200) $
              die ("Could not download " <> what <> " (" <> Text.pack url <> "): HTTP " <> Text.pack (show code))
            pure (responseBody resp)

  sums <- fetch "the checksums" (downloadBase <> "/SHA256SUMS")
  expected <- case lookupSum asset sums of
    Just h -> pure h
    Nothing -> die ("No checksum for " <> Text.pack asset <> " in " <> Text.pack downloadBase <> "/SHA256SUMS; not installing.")

  note ("Downloading " <> Text.pack downloadBase <> "/" <> Text.pack asset)
  binary <- fetch "the legalese CLI" (downloadBase <> "/" <> asset)
  let actual = show (hashlazy binary :: Digest SHA256)
  when (map toLower expected /= actual) $
    die ("Checksum mismatch for " <> Text.pack asset <> " (expected " <> Text.pack expected <> ", got " <> Text.pack actual <> "); not installing.")

  binDir <- maybe defaultBinDir pure opts.dir
  createDirectoryIfMissing True binDir
  let dest = binDir </> "legalese"
  -- Write next to the destination, then rename over it: an upgrade never
  -- leaves a half-written `legalese` behind.
  written <- try do
    (tmp, h) <- openBinaryTempFile binDir ".legalese-download"
    (BSL.hPut h binary >> hClose h) `onException` removeFile tmp
    makeExecutable tmp
    renameFile tmp dest `onException` removeFile tmp
  case written of
    Left (e :: SomeException) ->
      die ("Could not write " <> Text.pack dest <> ": " <> Text.pack (show e) <> "\nPick a writable directory with --dir.")
    Right () -> pure ()

  (vcode, vout, _) <- readProcessWithExitCode dest ["--version"] ""
  note $ "Installed legalese"
    <> (if vcode == ExitSuccess then " " <> Text.strip (Text.pack vout) else "")
    <> " to " <> Text.pack dest

  searchPath <- map normalise <$> getSearchPath
  onPath <- findLegaleseCli
  if normalise binDir `notElem` searchPath
    then note ("Add " <> Text.pack binDir <> " to your PATH to run `legalese`.")
    else case onPath of
      Just other | normalise (takeDirectory other) /= normalise binDir ->
        note ("Note: `legalese` on your PATH is " <> Text.pack other <> ", which comes before this one.")
      _ -> pure ()
  note "Next: `legalese login`, then `l4 deploy FILE`."
  where
    archName = \case
      "aarch64" -> Just "arm64"
      "x86_64"  -> Just "x64"
      _         -> Nothing

-- | The hash for @asset@ in a @sha256sum@-style listing.
lookupSum :: String -> BSL.ByteString -> Maybe String
lookupSum asset sums = listToMaybe
  [ h
  | line <- lines (BSL8.unpack sums)
  , [h, n] <- [words line]
  , n == asset || n == '*' : asset
  ]

-- | @/usr/local/bin@ when it exists and is writable, else @~/.local/bin@.
defaultBinDir :: IO FilePath
defaultBinDir = do
  let system = "/usr/local/bin"
  exists <- doesDirectoryExist system
  ok <- if exists then writable <$> getPermissions system else pure False
  if ok
    then pure system
    else (</> ".local" </> "bin") <$> getHomeDirectory

-- | rwxr-xr-x, as install.sh leaves it (the temp file starts as rw-------).
makeExecutable :: FilePath -> IO ()
#if defined(mingw32_HOST_OS)
makeExecutable _ = pure ()
#else
makeExecutable p = setFileMode p 0o755
#endif
