{-# LANGUAGE DataKinds, ExplicitNamespaces, DisambiguateRecordFields, OverloadedRecordDot, OverloadedStrings, PatternSynonyms, TupleSections #-}
-- | Call expansions are opt-in per @l4.visualize@ request (WHERE-INLINING-SPEC §10).
--
-- With expansions on, a render of @regcf.l4@ took about 7.1 s against about 2.5 s
-- without, at 3.4x the bytes (2026-10-05), and the IDE's displayers ignore the
-- field. So the lens asks for none, a client that wants them appends
-- @{"expandCalls": true}@, and auto-refresh and @l4/inlineExprs@ keep whatever
-- the most recent render chose.
--
-- Every case drives the real path: the lens's own arguments, decoded by
-- 'decodeVisualiseArgs', handed to 'visualise' with a recent-visualisation store
-- held in 'State', exactly as the handler wires it.
module VisualiseExpansionOptInSpec (spec) where

import Control.Monad.Except (runExceptT)
import Control.Monad.State (State, get, put, runState)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import Data.Foldable (for_, toList)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import System.Directory (createDirectoryIfMissing, getTemporaryDirectory)
import System.FilePath (takeDirectory, (</>))

import Language.LSP.Protocol.Message (Method (..), TResponseError (..))
import Language.LSP.Protocol.Types
  ( CodeLens (..), Command (..), Null (..), VersionedTextDocumentIdentifier (..), type (|?) (..)
  , fromNormalizedUri, normalizedFilePathToUri )

import L4.EvaluateLazy (resolveEvalConfig)
import L4.EvaluateLazy.GraphVizOptions (defaultGraphVizOptions)
import L4.TracePolicy (lspDefaultPolicy)
import qualified L4.Viz.VizExpr as V
import LSP.Core.Shake (RecentlyVisualised (..))
import qualified LSP.Core.Shake as Shake
import LSP.L4.Actions (VisualiseOptions (..), decisionGraphCodeLenses, decodeVisualiseArgs, renderAfterInlining, visualise)
import LSP.L4.Oneshot (oneshotL4ActionAndErrors)
import LSP.L4.Rules (TypeCheckResult (..), pattern TypeCheck)

import Test.Hspec

checkSource :: String -> T.Text -> IO (VersionedTextDocumentIdentifier, TypeCheckResult)
checkSource stem source = do
  tmp <- getTemporaryDirectory
  let path = tmp </> "jl4-visualise-expansion-opt-in-spec" </> (stem <> ".l4")
  createDirectoryIfMissing True (takeDirectory path)
  T.writeFile path source
  evalConfig <- resolveEvalConfig Nothing (lspDefaultPolicy defaultGraphVizOptions)
  (_, mRes) <- oneshotL4ActionAndErrors evalConfig path \nfp -> do
    let uri = normalizedFilePathToUri nfp
    _   <- Shake.addVirtualFileFromFS nfp
    mTc <- Shake.use TypeCheck uri
    pure $ fmap (VersionedTextDocumentIdentifier (fromNormalizedUri uri) 0,) mTc
  maybe (fail "fixture did not type-check") pure mRes

-- | Two callees, so that after @l4/inlineExprs@ unfolds one of them a call
-- to the other is still drawn as a call leaf.
fixture :: T.Text
fixture = T.unlines
  [ "DECLARE Person"
  , "  HAS `has stable income` IS A BOOLEAN"
  , "      `has collateral`     IS A BOOLEAN"
  , ""
  , "GIVEN p IS A Person"
  , "GIVETH A BOOLEAN"
  , "DECIDE `is creditworthy` p IF p's `has stable income`"
  , ""
  , "GIVEN p IS A Person"
  , "GIVETH A BOOLEAN"
  , "DECIDE `is secured` p IF p's `has collateral`"
  , ""
  , "GIVEN p IS A BOOLEAN"
  , "      q IS A BOOLEAN"
  , "DECIDE `limb` p q IF p AND q"
  , ""
  , "GIVEN a IS A Person"
  , "      x IS A BOOLEAN"
  , "      y IS A BOOLEAN"
  , "GIVETH A BOOLEAN"
  , "DECIDE `may lend` a x y IF"
  , "      `is creditworthy` a"
  , "  AND `is secured` a"
  , "  AND `limb` x y"
  ]

target :: T.Text
target = "`may lend`"

type Store = Maybe RecentlyVisualised

-- | One @l4.visualize@ request, as the handler runs it: decode the arguments
-- after the document id, then visualise against the store.
request :: TypeCheckResult -> VersionedTextDocumentIdentifier -> [Aeson.Value] -> Store -> IO (Maybe Aeson.Value, Store)
request tc verId args store = case decodeVisualiseArgs args of
  Left err -> fail ("decodeVisualiseArgs: " <> T.unpack err)
  Right msrcPos -> do
    let run :: State Store (Either (TResponseError 'Method_WorkspaceExecuteCommand) (Aeson.Value |? Null))
        run = runExceptT (visualise (Just tc) (get, put . Just) verId msrcPos)
    case runState run store of
      (Left e, _) -> fail ("visualise: " <> T.unpack e._message)
      (Right (InL v), store') -> pure (Just v, store')
      (Right (InR Null), store') -> pure (Nothing, store')

-- | The arguments the "Show decision graph" lens sends for @target@, minus the
-- document id.
lensArgs :: TypeCheckResult -> VersionedTextDocumentIdentifier -> IO [Aeson.Value]
lensArgs = lensArgsFor target

-- | The same, for the decision named @wanted@.
lensArgsFor :: T.Text -> TypeCheckResult -> VersionedTextDocumentIdentifier -> IO [Aeson.Value]
lensArgsFor wanted tc verId = do
  let lenses =
        [ args
        | CodeLens {_command = Just Command {_command = "l4.visualize", _arguments = Just (_ : args)}}
            <- decisionGraphCodeLenses verId tc
        ]
  named <- traverse (\args -> (,args) <$> fmap (fmap nameOf . fst) (request tc verId args Nothing)) lenses
  case [args | (Just (Just n), args) <- named, n == wanted] of
    [args] -> pure args
    other -> fail ("expected one lens for " <> T.unpack wanted <> ", found " <> show (length other))
  where
    nameOf v = case Aeson.fromJSON v of
      Aeson.Success (info :: V.RenderAsLadderInfo) -> Just info.funDecl.fnName.label
      Aeson.Error _ -> Nothing

-- | How many objects anywhere in the reply carry an @expansion@ key.
expansionKeys :: Aeson.Value -> Int
expansionKeys = \case
  Aeson.Object o -> (if KeyMap.member "expansion" o then 1 else 0) + sum (map expansionKeys (KeyMap.elems o))
  Aeson.Array xs -> sum (map expansionKeys (toList xs))
  _ -> 0

expandOn :: Aeson.Value
expandOn = Aeson.object ["expandCalls" Aeson..= True]

-- | The unique of the call leaf to @is creditworthy@ in the stored ladder.
creditworthyCall :: RecentlyVisualised -> IO Int
creditworthyCall rv = case [nm.unique | V.UBoolVar _ nm _ True _ _ _ <- leaves rv.ladderInfo.funDecl.body, nm.label == "`is creditworthy` OF a"] of
  (u : _) -> pure u
  [] -> fail "no `is creditworthy` OF a call leaf"
  where
    leaves = \case
      V.And _ xs -> concatMap leaves xs
      V.Or _ xs -> concatMap leaves xs
      V.Not _ x -> leaves x
      e -> [e]

spec :: Spec
spec = describe "call expansions are opt-in per l4.visualize request" $ do
  it "the lens sends three arguments after the document id: it does not ask for expansions" $ do
    (verId, tc) <- checkSource "lens" fixture
    args <- lensArgs tc verId
    length args `shouldBe` 2

  it "decodes the options argument, and refuses one it cannot read" $ do
    (verId, tc) <- checkSource "decode" fixture
    args <- lensArgs tc verId
    let opts as = fmap (fmap (\(_, _, o) -> o)) (decodeVisualiseArgs as)
    opts args `shouldBe` Right (Just (VisualiseOptions False))
    opts (args <> [expandOn]) `shouldBe` Right (Just (VisualiseOptions True))
    opts (args <> [Aeson.object []]) `shouldBe` Right (Just (VisualiseOptions False))
    opts (args <> [Aeson.object ["expandCalls" Aeson..= False, "unknown" Aeson..= True]]) `shouldBe` Right (Just (VisualiseOptions False))
    either (const True) (const False) (opts (args <> [Aeson.String "yes"])) `shouldBe` True
    -- the document id alone is auto-refresh, as it always was
    opts [] `shouldBe` Right Nothing

  it "a render without the flag carries no `expansion` anywhere; with it, it does" $ do
    (verId, tc) <- checkSource "render" fixture
    args <- lensArgs tc verId
    (without, _) <- request tc verId args Nothing
    fmap expansionKeys without `shouldBe` Just 0
    -- positive control: the same request, asking
    (with, _) <- request tc verId (args <> [expandOn]) Nothing
    fmap expansionKeys with `shouldSatisfy` maybe False (>= 3)

  it "auto-refresh keeps the most recent render's choice" $ do
    (verId, tc) <- checkSource "refresh" fixture
    args <- lensArgs tc verId
    (_, storeOn) <- request tc verId (args <> [expandOn]) Nothing
    (refreshedOn, _) <- request tc verId [] storeOn
    fmap expansionKeys refreshedOn `shouldSatisfy` maybe False (>= 3)
    (_, storeOff) <- request tc verId args storeOn
    (refreshedOff, _) <- request tc verId [] storeOff
    fmap expansionKeys refreshedOff `shouldBe` Just 0

  it "l4/inlineExprs keeps the most recent render's choice" $ do
    (verId, tc) <- checkSource "inline" fixture
    args <- lensArgs tc verId
    let inlined store = do
          rv <- maybe (fail "nothing stored") pure store
          u <- creditworthyCall rv
          case renderAfterInlining rv.vizState rv.decide [u] of
            Left e -> fail (show e)
            Right (_, info, _, _) -> pure (expansionKeys (Aeson.toJSON info))
    (_, storeOn) <- request tc verId (args <> [expandOn]) Nothing
    -- `is secured a` and `limb x y` are still calls after the unfold
    inlined storeOn >>= (`shouldSatisfy` (>= 2))
    (_, storeOff) <- request tc verId args Nothing
    inlined storeOff >>= (`shouldBe` 0)

  -- Not about the opt-in: about the labels every render carries. Kept here
  -- because this module drives the real lens path.
  describe "two mixfix calls sharing a head keyword (batch-mixfix-shared-head.l4)" $ do
    it "draw with different labels and different atomIds, with or without expansions" $ do
      (verId, tc) <- checkSource "mixfix-shared-head" mixfixFixture
      args <- lensArgsFor "`gift stands`" tc verId
      for_ [args, args <> [expandOn]] \as -> do
        (reply, _) <- request tc verId as Nothing
        info <- case fmap Aeson.fromJSON reply of
          Just (Aeson.Success (i :: V.RenderAsLadderInfo)) -> pure i
          _ -> fail "no ladder in the reply"
        let calls = [(nm.label, atomId) | V.UBoolVar _ nm _ True atomId _ _ <- topLeaves info.funDecl.body]
        map fst calls `shouldBe`
          [ "`the will` w `is duly executed without` 3"
          , "`the will` w `is revoked counting` 3"
          ]
        case map snd calls of
          [x, y] -> x `shouldNotBe` y
          other -> fail ("expected two call leaves, found " <> show (length other))
  where
    -- the decision's own leaves, not those inside an expansion
    topLeaves = \case
      V.And _ xs -> concatMap topLeaves xs
      V.Or _ xs -> concatMap topLeaves xs
      V.Not _ x -> topLeaves x
      e -> [e]

-- | @jl4/tests-cli/fixtures/batch-mixfix-shared-head.l4@, which guards the same
-- collision for @l4 batch@ (CLAUDE.md §3.2.2).
mixfixFixture :: T.Text
mixfixFixture = T.unlines
  [ "GIVEN w IS A NUMBER"
  , "      n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`the will` w `is duly executed without` n MEANS w GREATER THAN n"
  , ""
  , "GIVEN w IS A NUMBER"
  , "      n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "`the will` w `is revoked counting` n MEANS w LESS THAN n"
  , ""
  , "GIVEN w IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "DECIDE `gift stands` w IS"
  , "  (`the will` w `is duly executed without` 3) AND NOT (`the will` w `is revoked counting` 3)"
  ]
