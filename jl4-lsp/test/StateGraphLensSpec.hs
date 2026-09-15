{-# LANGUAGE OverloadedRecordDot, PatternSynonyms, OverloadedStrings, ExplicitNamespaces, TupleSections, DataKinds #-}
-- | The two code lenses the language server puts above a top-level @DECIDE@
-- ('LSP.L4.Actions.decisionGraphCodeLenses' and
-- 'LSP.L4.Actions.stateGraphCodeLenses'), and the click the second one
-- serves ('LSP.L4.Actions.stateGraphAtPos').
--
-- The property worth pinning is R13 of
-- @specs/todo/lexipedia-superset/LTS-VISUALISER.md@ §8: the ladder's lens and
-- the state graph's lens never stack on one line. A boolean rule earns
-- "Show decision graph" and not "Show state graph"; a regulative rule earns
-- the reverse; and no anchor position carries both. That was measured over
-- the corpus on 2026-09-15 (0 of 12 regulative rules also pass the ladder's
-- gate); here it is asserted on a fixture that has one of each, and on two
-- corpus files when they are where @cabal test@ expects them.
module StateGraphLensSpec (spec) where

import Data.Maybe (mapMaybe)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Text as T
import qualified Data.Text.IO as T
import System.Directory (createDirectoryIfMissing, doesFileExist, getTemporaryDirectory)
import System.FilePath ((</>))

import Control.Monad.Except (runExceptT)
import Language.LSP.Protocol.Message (Method (..), TResponseError (..))
import Language.LSP.Protocol.Types
  ( CodeLens (..), Command (..), Position (..), Range (..)
  , VersionedTextDocumentIdentifier (..), fromNormalizedUri, normalizedFilePathToUri, type (|?) (..), Null
  )

import L4.EvaluateLazy (resolveEvalConfig)
import L4.EvaluateLazy.GraphVizOptions (defaultGraphVizOptions)
import L4.Parser.SrcSpan (SrcPos (..))
import L4.TracePolicy (lspDefaultPolicy)
import qualified LSP.Core.Shake as Shake
import LSP.L4.Actions (decisionGraphCodeLenses, stateGraphAtPos, stateGraphCodeLenses)
import LSP.L4.Oneshot (oneshotL4ActionAndErrors)
import LSP.L4.Rules (TypeCheckResult (..), pattern TypeCheck)

import Test.Hspec

-- | Type-check a source text through the real oneshot pipeline and hand back
-- the type-check result with the document identifier the lenses are built
-- for.
checkSource :: FilePath -> T.Text -> IO (Maybe (VersionedTextDocumentIdentifier, TypeCheckResult))
checkSource path source = do
  createDirectoryIfMissing True (takeDirectoryOf path)
  T.writeFile path source
  checkFile path
  where
    takeDirectoryOf = reverse . drop 1 . dropWhile (/= '/') . reverse

-- | Type-check a file already on disk.
checkFile :: FilePath -> IO (Maybe (VersionedTextDocumentIdentifier, TypeCheckResult))
checkFile path = do
  evalConfig <- resolveEvalConfig Nothing (lspDefaultPolicy defaultGraphVizOptions)
  (_, mRes) <- oneshotL4ActionAndErrors evalConfig path \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _   <- Shake.addVirtualFileFromFS nfp
    mTc <- Shake.use TypeCheck uri
    pure $ fmap (VersionedTextDocumentIdentifier (fromNormalizedUri uri) 0,) mTc
  pure mRes

scratch :: String -> IO FilePath
scratch stem = do
  tmp <- getTemporaryDirectory
  pure (tmp </> "jl4-state-graph-lens-spec" </> (stem <> ".l4"))

-- | One boolean rule and one regulative rule, with a line of space between
-- them so the two anchors cannot coincide by accident. A @DECIDE@ node
-- starts at its type signature, so each lens anchors on the @GIVEN@ /
-- @GIVETH@ line above the rule, not on the rule's own line.
fixture :: T.Text
fixture = T.unlines
  [ "DECLARE Person IS ONE OF Alice, Bob"
  , "DECLARE Action IS ONE OF pay, deliver"
  , ""
  , "GIVEN n IS A NUMBER"                       -- line 3 (0-based): the boolean rule's anchor
  , "GIVETH A BOOLEAN"
  , "DECIDE `is adult` n IF n >= 18"
  , ""
  , "GIVETH DEONTIC Person Action"              -- line 7 (0-based): the regulative rule's anchor
  , "`the deal` MEANS"
  , "  PARTY Alice MUST pay WITHIN 3"
  , "  HENCE PARTY Bob MUST deliver WITHIN 5"
  ]

-- | Serve a click as the @workspace/executeCommand@ handler would, keeping
-- only the message of a refusal.
click :: TypeCheckResult -> VersionedTextDocumentIdentifier -> SrcPos -> IO (Either T.Text (Aeson.Value |? Null))
click tc verId pos = do
  r <- runExceptT (stateGraphAtPos (Just tc) verId pos)
  pure $ case r of
    Left (e :: TResponseError 'Method_WorkspaceExecuteCommand) -> Left e._message
    Right v -> Right v

lensTitle :: CodeLens -> Maybe T.Text
lensTitle l = (._title) <$> l._command

lensLine :: CodeLens -> Int
lensLine l = fromIntegral l._range._start._line

titlesByLine :: [CodeLens] -> [(Int, T.Text)]
titlesByLine = mapMaybe \l -> (lensLine l,) <$> lensTitle l

spec :: Spec
spec = do
  describe "the state-graph lens sits above regulative rules only" $ do
    it "one boolean rule, one regulative rule: one lens each, on different lines" $ do
      path <- scratch "one-of-each"
      mRes <- checkSource path fixture
      case mRes of
        Nothing -> expectationFailure "fixture did not type-check"
        Just (verId, tc) -> do
          let ladder = decisionGraphCodeLenses verId tc
              graph  = stateGraphCodeLenses verId tc
          titlesByLine ladder `shouldBe` [(3, "Show decision graph")]
          titlesByLine graph  `shouldBe` [(7, "Show state graph")]
          -- R13: no anchor carries both.
          filter (`elem` map lensLine graph) (map lensLine ladder) `shouldBe` []

    it "the state-graph lens carries the command and arguments the host routes on" $ do
      path <- scratch "arguments"
      mRes <- checkSource path fixture
      case mRes of
        Nothing -> expectationFailure "fixture did not type-check"
        Just (verId, tc) -> do
          case stateGraphCodeLenses verId tc of
            [CodeLens { _command = Just cmd }] -> do
              cmd._command `shouldBe` "l4.stateGraph"
              -- [verTextDocId, srcPos] — the ladder's shape minus the simplify flag
              case cmd._arguments of
                Just [docArg, posArg] -> do
                  docArg `shouldBe` Aeson.toJSON verId
                  -- SrcPos is 1-based
                  posArg `shouldBe` Aeson.object [("line", Aeson.Number 8), ("column", Aeson.Number 1)]
                other -> expectationFailure ("expected two arguments, got " <> show other)
            other -> expectationFailure ("expected exactly one lens with a command, got " <> show (length other))

  describe "clicking the state-graph lens" $ do
    it "returns DOT for the rule at that position, named after the rule" $ do
      path <- scratch "click"
      mRes <- checkSource path fixture
      case mRes of
        Nothing -> expectationFailure "fixture did not type-check"
        Just (verId, tc) -> do
          -- SrcPos is 1-based; the regulative rule's node starts at line 8, column 1.
          r <- click tc verId (MkSrcPos 8 1)
          case r of
            Right (InL (Aeson.Object o)) -> do
              KeyMap.lookup "name" o `shouldBe` Just (Aeson.String "the deal")
              case KeyMap.lookup "dot" o of
                Just (Aeson.String dot) -> do
                  dot `shouldSatisfy` T.isPrefixOf "digraph"
                  dot `shouldSatisfy` T.isInfixOf "pay"
                  dot `shouldSatisfy` T.isInfixOf "deliver"
                other -> expectationFailure ("no dot field: " <> show other)
            other -> expectationFailure ("unexpected response: " <> show other)

    it "refuses a position where no regulative rule starts" $ do
      path <- scratch "miss"
      mRes <- checkSource path fixture
      case mRes of
        Nothing -> expectationFailure "fixture did not type-check"
        Just (verId, tc) -> do
          -- the boolean rule's own anchor
          r <- click tc verId (MkSrcPos 4 1)
          fmap (const ()) r `shouldBe` Left "No regulative rule starts at that position (the program may have changed between pressing the code lens and rendering it)"

  describe "R13 on the corpus" $ do
    -- cabal runs the suite from the package directory; the corpus is one up.
    mapM_ corpusCase
      [ ("../jl4/examples/ok/contracts.l4", 7)
      , ("../doc/reference/regulative/every-run-example.l4", 2)
      ]
  where
    corpusCase :: (FilePath, Int) -> Spec
    corpusCase (file, expectedGraphs) =
      it (file <> ": every regulative rule gets a state-graph lens and none gets the ladder's") $ do
        present <- doesFileExist file
        if not present
          then pendingWith ("not found from cwd: " <> file)
          else do
            mRes <- checkFile file
            case mRes of
              Nothing -> expectationFailure (file <> " did not type-check")
              Just (verId, tc) -> do
                let ladder = decisionGraphCodeLenses verId tc
                    graph  = stateGraphCodeLenses verId tc
                length graph `shouldBe` expectedGraphs
                filter (`elem` map lensLine graph) (map lensLine ladder) `shouldBe` []
