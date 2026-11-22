-- | Tests for @etc/build-identity.sh@, which the release workflow
-- (@main-tag.yml@) runs to write the variables that "LSP.L4.BuildInfo" bakes
-- into @l4@ and @jl4-lsp@. What the binaries print is tested in
-- "CliTest.BuildVersion".
module CliTest.BuildIdentity (spec, fixtures) where

import Data.Char (isDigit)
import Data.List (isInfixOf, isPrefixOf)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as BS
import qualified Data.Text as T
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.Info (os)
import System.Process (CreateProcess (..), proc, readCreateProcessWithExitCode)
import Test.Hspec

import CliTest.Common

-- | Files this module's tests need to exist, relative to @jl4/@.
fixtures :: [FilePath]
fixtures = ["../etc/build-identity.sh", "../ts-apps/vscode/package.json"]

spec :: Spec
spec = do
  describe "etc/build-identity.sh" $ do
    let script = "../etc/build-identity.sh"
        posixOnly act
          | os == "mingw32" = pendingWith "needs a POSIX shell; the release workflow runs it on Windows under Git Bash"
          | otherwise = act
        -- The parent's environment, less the two variables a workflow run sets
        -- (CI has them), plus the ones the case gives.
        runScript set = do
          parent <- getEnvironment
          let inherited = [kv | kv@(k, _) <- parent, k `notElem` ["GITHUB_RUN_NUMBER", "GITHUB_SHA", "GITHUB_REF_NAME"]]
          readCreateProcessWithExitCode (proc "bash" [script]) {env = Just (inherited ++ set)} ""
        sha = "0123456789abcdef0123456789abcdef01234567"
        datePrefix = "L4_BUILD_DATE=" :: String
        isDate d = length d == 10 && all isDigit (take 4 d) && d !! 4 == '-' && all isDigit (take 2 (drop 5 d))
                     && d !! 7 == '-' && all isDigit (drop 8 d)

    it "prints the release, the first seven characters of the commit, and today, one VAR=value per line" $ posixOnly $ do
      (code, out, _) <- runScript [("GITHUB_RUN_NUMBER", "91"), ("GITHUB_SHA", sha), ("GITHUB_REF_NAME", "main")]
      code `shouldBe` ExitSuccess
      package <- BS.readFile "../ts-apps/vscode/package.json"
      let version = case Aeson.decodeStrict package >>= (`objField` "version") of
            Just (Aeson.String v) -> T.unpack v
            _ -> ""
          majorMinor = reverse (drop 1 (dropWhile (/= '.') (reverse version)))
      version `shouldSatisfy` (not . null)
      case lines out of
        [r, b, c, d] -> do
          r `shouldBe` "L4_BUILD_RELEASE=" ++ majorMinor ++ ".91"
          b `shouldBe` "L4_BUILD_BRANCH=main"
          c `shouldBe` "L4_BUILD_COMMIT=0123456"
          d `shouldSatisfy` isPrefixOf datePrefix
          drop (length datePrefix) d `shouldSatisfy` isDate
        other -> expectationFailure ("expected four lines, got " ++ show other)

    it "names the branch the workflow ran on, whatever it is called" $ posixOnly $ do
      (code, out, _) <- runScript [("GITHUB_RUN_NUMBER", "91"), ("GITHUB_SHA", sha), ("GITHUB_REF_NAME", "feature/x")]
      code `shouldBe` ExitSuccess
      lines out `shouldSatisfy` ("L4_BUILD_BRANCH=feature/x" `elem`)

    it "says unknown when the workflow gave no branch, and does not ask Git" $ posixOnly $ do
      (code, out, _) <- runScript [("GITHUB_RUN_NUMBER", "91"), ("GITHUB_SHA", sha)]
      code `shouldBe` ExitSuccess
      lines out `shouldSatisfy` ("L4_BUILD_BRANCH=unknown" `elem`)

    it "refuses to print anything without a run number, so a local run cannot pass for a release" $ posixOnly $ do
      (code, out, err) <- runScript [("GITHUB_SHA", sha)]
      code `shouldSatisfy` (/= ExitSuccess)
      out `shouldBe` ""
      err `shouldSatisfy` ("GITHUB_RUN_NUMBER" `isInfixOf`)

    it "refuses to print anything without a commit" $ posixOnly $ do
      (code, out, err) <- runScript [("GITHUB_RUN_NUMBER", "91")]
      code `shouldSatisfy` (/= ExitSuccess)
      out `shouldBe` ""
      err `shouldSatisfy` ("GITHUB_SHA" `isInfixOf`)
