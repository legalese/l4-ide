{-# LANGUAGE PatternSynonyms #-}
-- | 'LSP.L4.BlockingErrors': which files the editor's Deploy buttons refuse.
--
-- Each case writes a small project to a temporary directory and runs the real
-- oneshot pipeline on its entry file: typecheck, evaluate, walk the import
-- closure, keep the blocking diagnostics. The cases that matter most are the
-- ones where the entry file's own typecheck still reports success.
module BlockingErrorsSpec (spec) where

import Control.Monad (forM_)
import qualified Data.Set as Set
import qualified Data.Text as T
import qualified Data.Text.IO as T
import System.Directory (createDirectoryIfMissing, getTemporaryDirectory, removePathForcibly)
import System.FilePath ((</>))

import Data.Text (Text)
import Language.LSP.Protocol.Types (Diagnostic (..), NormalizedUri, Position (..), Range (..), normalizedFilePathToUri, toNormalizedFilePath)

import L4.EvaluateLazy (resolveEvalConfig)
import L4.EvaluateLazy.GraphVizOptions (defaultGraphVizOptions)
import L4.TracePolicy (lspDefaultPolicy)
import qualified LSP.Core.Shake as Shake
import LSP.Core.Types.Diagnostics (FileDiagnostic (..))
import LSP.L4.BlockingErrors (ImportCycle (..), blockingErrorsIn, importClosure, importCycles)
import LSP.L4.Oneshot (oneshotL4ActionAndDiagnostics)
import LSP.L4.Rules (EvaluateLazy (..), TypeCheckResult (..), pattern TypeCheck)

import Test.Hspec

data Outcome = Outcome
  { rootTypechecks :: Bool
  , closure :: [NormalizedUri]
  , blocking :: [FileDiagnostic]
  , cycles :: [ImportCycle]
  , mainImportErrors :: [(Int, Text)]
  -- ^ The errors on @main@'s own IMPORT lines (0-based line, message)
  }

-- | Write @files@ (name without extension, source) to a fresh directory and
-- check @main@.
checkProject :: String -> [(String, T.Text)] -> IO Outcome
checkProject name files = do
  tmp <- getTemporaryDirectory
  let dir = tmp </> "jl4-lsp-blocking-errors-spec" </> name
  removePathForcibly dir
  createDirectoryIfMissing True dir
  forM_ files \(stem, src) -> T.writeFile (dir </> stem <> ".l4") src
  let entry = dir </> "main.l4"
  evalConfig <- resolveEvalConfig Nothing (lspDefaultPolicy defaultGraphVizOptions)
  (_, diags, (mTc, uris, cs)) <- oneshotL4ActionAndDiagnostics evalConfig entry \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _ <- Shake.addVirtualFileFromFS nfp
    mTc <- Shake.use TypeCheck uri
    _ <- Shake.use EvaluateLazy uri
    uris <- importClosure uri
    cs <- importCycles uri
    pure (mTc, uris, cs)
  pure Outcome
    { rootTypechecks = maybe False (.success) mTc
    , closure = uris
    , blocking = blockingErrorsIn uris diags
    , cycles = cs
    , mainImportErrors =
        [ (fromIntegral d._range._start._line, d._message)
        | fd <- diags
        , fd.fdFilePath == normalizedFilePathToUri (toNormalizedFilePath entry)
        , let d = fd.fdLspDiagnostic
        , d._source == Just "import"
        ]
    }

uriOf :: String -> String -> IO NormalizedUri
uriOf name stem = do
  tmp <- getTemporaryDirectory
  pure $ normalizedFilePathToUri $ toNormalizedFilePath $
    tmp </> "jl4-lsp-blocking-errors-spec" </> name </> stem <> ".l4"

spec :: Spec
spec = describe "LSP.L4.BlockingErrors" do
  it "lets a file with a clean import through" do
    o <- checkProject "clean"
      [ ("main", "IMPORT helper\n\nfine MEANS helped\n")
      , ("helper", "helped MEANS 1\n")
      ]
    o.blocking `shouldSatisfy` null
    length o.closure `shouldBe` 2
    o.mainImportErrors `shouldBe` []

  it "refuses a file with a type error" do
    o <- checkProject "own-error"
      [ ("main", "GIVEN x IS A NUMBER\nGIVETH A BOOLEAN\nDECIDE bad x IS x\n") ]
    o.blocking `shouldSatisfy` (not . null)

  it "refuses a file whose import has a type error" do
    o <- checkProject "imported-error"
      [ ("main", "IMPORT broken\n\nfine MEANS 1\n")
      , ("broken", "GIVEN x IS A NUMBER\nGIVETH A BOOLEAN\nDECIDE bad x IS x\n")
      ]
    broken <- uriOf "imported-error" "broken"
    map (.fdFilePath) o.blocking `shouldSatisfy` (broken `elem`)
    -- The IMPORT is marked too, but not counted again.
    map fst o.mainImportErrors `shouldBe` [0]
    main <- uriOf "imported-error" "main"
    map (.fdFilePath) o.blocking `shouldNotSatisfy` (main `elem`)

  it "marks the IMPORT of a module whose own import is broken" do
    o <- checkProject "transitive"
      [ ("main", "-- top\nIMPORT middle\n\nfine MEANS 1\n")
      , ("middle", "IMPORT broken\n\nm MEANS 1\n")
      , ("broken", "GIVEN x IS A NUMBER\nGIVETH A BOOLEAN\nDECIDE bad x IS x\n")
      ]
    o.rootTypechecks `shouldBe` True
    map fst o.mainImportErrors `shouldBe` [1]

  it "refuses a file whose import does not parse, though the file itself typechecks" do
    o <- checkProject "imported-syntax"
      [ ("main", "IMPORT bad\n\nfine MEANS 1\n")
      , ("bad", "DECIDE IS IS\n")
      ]
    o.rootTypechecks `shouldBe` True
    o.blocking `shouldSatisfy` (not . null)

  it "refuses an IMPORT that resolves to no module, though the file itself typechecks" do
    o <- checkProject "missing"
      [ ("main", "IMPORT zz_no_such_module_blocking_spec\n\nfine MEANS 1\n") ]
    o.rootTypechecks `shouldBe` True
    o.blocking `shouldSatisfy` (not . null)

  it "refuses an import cycle, though the file itself typechecks" do
    o <- checkProject "cycle"
      [ ("main", "IMPORT dua\n\nfine MEANS 1\n")
      , ("dua", "IMPORT dub\n\nfoo MEANS 1\n")
      , ("dub", "IMPORT dua\n\nbar MEANS 2\n")
      ]
    o.rootTypechecks `shouldBe` True
    Set.fromList o.closure `shouldSatisfy` ((== 3) . Set.size)
    o.blocking `shouldSatisfy` (not . null)
    [dua, dub] <- traverse (uriOf "cycle") ["dua", "dub"]
    map (\c -> (c.importer, c.line, c.cycle)) o.cycles
      `shouldBe` [(dub, Just 1, [dua, dub, dua])]

  it "finds no cycle in a diamond of imports" do
    o <- checkProject "diamond"
      [ ("main", "IMPORT left\nIMPORT right\n\nfine MEANS 1\n")
      , ("left", "IMPORT base\n\nl MEANS 1\n")
      , ("right", "IMPORT base\n\nr MEANS 1\n")
      , ("base", "b MEANS 1\n")
      ]
    o.blocking `shouldSatisfy` null
    map (.cycle) o.cycles `shouldBe` []

  it "lets a warning in an import through" do
    o <- checkProject "warning"
      [ ("main", "IMPORT partial\n\ntotal MEANS 1\n")
      , ("partial", T.unlines
          [ "DECLARE Colour IS ONE OF Red, Green, Blue"
          , ""
          , "GIVEN c IS A Colour"
          , "GIVETH A NUMBER"
          , "DECIDE price Red   IS 1"
          , "DECIDE price Green IS 2"
          ])
      ]
    o.blocking `shouldSatisfy` null

  it "lets a failed #ASSERT through" do
    o <- checkProject "assert"
      [ ("main", "one MEANS 1\n\n#ASSERT one EQUALS 2\n") ]
    o.blocking `shouldSatisfy` null
