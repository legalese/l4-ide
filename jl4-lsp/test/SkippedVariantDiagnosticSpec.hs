{-# LANGUAGE ExplicitNamespaces #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE TupleSections #-}

-- | What the editor sees when an IMPORT resolves but passes a file over
-- because of its capitals (smucclaw/l4-ide#1080): a Warning on the IMPORT
-- line, with the text of the log line. The log line alone reached only the
-- editor's output channel, so a user saw an error such as "could not find a
-- definition" and no reason for it. Assumed (GM, 2026-11-21), for Meng's
-- review.
--
-- These run the real Shake rules, as the language server does, on files in a
-- scratch folder, with JL4_LIBRARY_PATH unset (with it set, its folder ranks
-- above the project and nothing is passed over) and an empty XDG store.
module SkippedVariantDiagnosticSpec (spec) where

import Control.Exception (bracket)
import Control.Monad (forM_)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import System.Directory (createDirectoryIfMissing, getTemporaryDirectory, removePathForcibly)
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.FilePath ((</>))

import Language.LSP.Protocol.Types
  ( CodeDescription (..)
  , Diagnostic (..)
  , DiagnosticSeverity (..)
  , Position (..)
  , Range (..)
  , Uri (..)
  , normalizedFilePathToUri
  , type (|?) (..)
  )

import L4.EvaluateLazy (resolveEvalConfig)
import L4.EvaluateLazy.GraphVizOptions (defaultGraphVizOptions)
import L4.TracePolicy (lspDefaultPolicy)
import qualified LSP.Core.Shake as Shake
import LSP.Core.Types.Diagnostics (FileDiagnostic (..))
import LSP.L4.Oneshot (oneshotL4ActionAndDiagnostics)
import LSP.L4.Rules (pattern TypeCheck)

import Test.Hspec

-- | Check @main.l4@ in a fresh folder holding @files@, and hand back every
-- diagnostic published.
diagnosticsOf :: String -> [(FilePath, T.Text)] -> IO [Diagnostic]
diagnosticsOf name = diagnosticsOfFile name "main.l4"

-- | 'diagnosticsOf', checking @entry@ instead of @main.l4@.
diagnosticsOfFile :: String -> FilePath -> [(FilePath, T.Text)] -> IO [Diagnostic]
diagnosticsOfFile name entry files = do
  tmp <- getTemporaryDirectory
  let dir = tmp </> "jl4-skipped-variant-spec" </> name
      xdg = tmp </> "jl4-skipped-variant-spec" </> "xdg-empty"
  removePathForcibly dir
  createDirectoryIfMissing True dir
  createDirectoryIfMissing True xdg
  forM_ files $ \ (f, body) -> T.writeFile (dir </> f) body
  withEnv [("JL4_LIBRARY_PATH", Nothing), ("XDG_DATA_HOME", Just xdg)] $ do
    evalConfig <- resolveEvalConfig Nothing (lspDefaultPolicy defaultGraphVizOptions)
    (_, diags, _) <- oneshotL4ActionAndDiagnostics evalConfig (dir </> entry) \nfp -> do
      let uri = normalizedFilePathToUri nfp
      _ <- Shake.addVirtualFileFromFS nfp
      Shake.use TypeCheck uri
    pure [ d | FileDiagnostic{fdLspDiagnostic = d} <- diags ]

-- | Run with these variables set or unset, restoring them afterwards.
withEnv :: [(String, Maybe String)] -> IO a -> IO a
withEnv vars act = bracket save restore (const (mapM_ set vars >> act))
  where
    save = traverse (\ (k, _) -> (k,) <$> lookupEnv k) vars
    restore = mapM_ set
    set (k, v) = maybe (unsetEnv k) (setEnv k) v

warnings :: [Diagnostic] -> [Diagnostic]
warnings ds = [ d | d <- ds, d._severity == Just DiagnosticSeverity_Warning ]

-- | The warning's stable code and its link (jl4-lsp/DIAGNOSTIC-CODES.md;
-- code decided by Claude 2026-11-22, pending Meng's review).
hasSkippedVariantCode :: Diagnostic -> Expectation
hasSkippedVariantCode d = do
  d._code `shouldBe` Just (InR "import/case-variant-skipped")
  d._codeDescription `shouldBe`
    Just CodeDescription { _href = Uri "https://legalese.com/l4/reference/errors#import-case-variant-skipped" }

spec :: Spec
spec = describe "a file passed over because of its capitals, in the editor (#1080)" $ do
  -- Design probe P12.
  it "is a Warning on the IMPORT line, with the log line's text" $ do
    ds <- diagnosticsOf "p12"
      [ ("Math.l4", "DECIDE siblingMarker IS 11\n")
      , ("main.l4", "IMPORT math\n#EVAL 1 PLUS 1\n")
      ]
    case warnings ds of
      [d] -> do
        d._message `shouldBe` T.unlines
          [ "`IMPORT math` did not use `Math.l4` beside the importing file, because capital letters count in a module name: `Math` and `math` are different names."
          , "It used the standard library's `math` instead."
          , "To use that file, change the IMPORT to `Math`, or rename the file to `math.l4`."
          ]
        d._range `shouldBe` Range (Position 0 0) (Position 0 11)
        hasSkippedVariantCode d
      other -> expectationFailure ("expected exactly one warning, got " <> show (map (._message) other))

  -- Review finding A, as revised by GM (2026-11-21): the file passed over is
  -- the importing file itself, so the editor's copy says what is true and
  -- offers no fix that would make the file import itself.
  it "says so when the file passed over is the importing file itself" $ do
    ds <- diagnosticsOfFile "self" "Math.l4" [("Math.l4", "IMPORT math\n#EVAL 1 PLUS 1\n")]
    case warnings ds of
      [d] -> do
        d._message `shouldBe` T.unlines
          [ "`IMPORT math` did not use `Math.l4`, which is the importing file itself: `math` differs from `Math`, the name of this file's own module, only in its capitals."
          , "It used the standard library's `math` instead."
          , "If you meant this file, remove the IMPORT: a module cannot import itself, and a file's own definitions need no IMPORT. If you meant the standard library's `math`, nothing needs to change."
          ]
        d._range `shouldBe` Range (Position 0 0) (Position 0 11)
        hasSkippedVariantCode d
      other -> expectationFailure ("expected exactly one warning, got " <> show (map (._message) other))

  -- The control: the same import with nothing passed over.
  it "is absent when no file was passed over" $ do
    ds <- diagnosticsOf "control" [("main.l4", "IMPORT math\n#EVAL 1 PLUS 1\n")]
    map (._message) (warnings ds) `shouldBe` []

  -- Review finding B: the standard library's own IMPORT is not the user's.
  it "is absent for an IMPORT written inside the standard library" $ do
    ds <- diagnosticsOf "stdlib-import"
      [ ("Jurisdiction.l4", "DECIDE userMarker IS 1\n")
      , ("main.l4", "IMPORT currency\n#EVAL 1 PLUS 1\n")
      ]
    map (._message) (warnings ds) `shouldBe` []
