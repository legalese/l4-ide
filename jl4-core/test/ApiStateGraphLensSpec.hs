{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}
-- | The wasm side of the state-graph code lens: 'L4.API.l4CodeLenses' emits
-- a name-addressed "Show state graph" lens above every regulative rule, and
-- 'L4.API.l4StateGraphByName' serves the click with the name the lens
-- carried. The web IDE in wasm mode has no language server, so this is the
-- only producer it sees there; over its websocket transport it gets the LSP
-- producer instead (LTS-VISUALISER.md §4.8, "two producers, two addressing
-- modes, two hosts").
module ApiStateGraphLensSpec (spec) where

import Test.Hspec
import Data.Aeson (Value (..), decodeStrict)
import qualified Data.Aeson.KeyMap as KeyMap
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import qualified Data.Vector as Vector

import L4.API (l4CodeLenses, l4StateGraphByName)

-- | One boolean rule, one regulative rule (see StateGraphLensSpec in
-- jl4-lsp for the LSP twin of this fixture).
fixture :: Text
fixture = Text.unlines
  [ "DECLARE Person IS ONE OF Alice, Bob"
  , "DECLARE Action IS ONE OF pay, deliver"
  , ""
  , "GIVEN n IS A NUMBER"                       -- line 4 (1-based, Monaco): the boolean rule's anchor
  , "GIVETH A BOOLEAN"
  , "DECIDE `is adult` n IF n >= 18"
  , ""
  , "GIVETH DEONTIC Person Action"              -- line 8 (1-based, Monaco): the regulative rule's anchor
  , "`the deal` MEANS"
  , "  PARTY Alice MUST pay WITHIN 3"
  , "  HENCE PARTY Bob MUST deliver WITHIN 5"
  ]

-- | @(command id, title, 1-based start line, arguments)@ of every lens.
lenses :: Text -> [(Text, Text, Int, [Value])]
lenses src =
  case decodeStrict (Text.encodeUtf8 (l4CodeLenses src "file:///fixture.l4" 0)) of
    Just (Array vs) -> mapMaybe lens (Vector.toList vs)
    _ -> []
  where
    lens (Object o) = do
      Object cmd <- KeyMap.lookup "command" o
      Object rng <- KeyMap.lookup "range" o
      String cid <- KeyMap.lookup "id" cmd
      String title <- KeyMap.lookup "title" cmd
      Array args <- KeyMap.lookup "arguments" cmd
      Number ln <- KeyMap.lookup "startLineNumber" rng
      pure (cid, title, truncate ln, Vector.toList args)
    lens _ = Nothing

decodeObject :: Text -> Maybe (KeyMap.KeyMap Value)
decodeObject t = case decodeStrict (Text.encodeUtf8 t) of
  Just (Object o) -> Just o
  _ -> Nothing

spec :: Spec
spec = do
  describe "l4CodeLenses" $ do
    it "puts \"Show state graph\" above the regulative rule and \"Show decision graph\" above the boolean one" $ do
      let ls = lenses fixture
      [ (t, ln) | ("l4.stateGraph", t, ln, _) <- ls ] `shouldBe` [("Show state graph", 8)]
      [ (t, ln) | ("l4.visualize", t, ln, _) <- ls ] `shouldBe` [("Show decision graph", 4)]
      -- R13: the two lenses never share a line
      let graphLines = [ ln | ("l4.stateGraph", _, ln, _) <- ls ]
          ladderLines = [ ln | ("l4.visualize", _, ln, _) <- ls ]
      filter (`elem` graphLines) ladderLines `shouldBe` []

    it "addresses the target by name, as the wasm host expects: [verDocId, name]" $ do
      case [ args | ("l4.stateGraph", _, _, args) <- lenses fixture ] of
        [[Object doc, String name]] -> do
          KeyMap.lookup "uri" doc `shouldBe` Just (String "file:///fixture.l4")
          name `shouldBe` "`the deal`"
        other -> expectationFailure ("unexpected arguments: " <> show other)

  describe "l4StateGraphByName" $ do
    it "round-trips the name the lens carried into DOT" $ do
      case [ args | ("l4.stateGraph", _, _, args) <- lenses fixture ] of
        [[_, String name]] ->
          case decodeObject (l4StateGraphByName fixture name) of
            Just o -> do
              KeyMap.lookup "name" o `shouldBe` Just (String "the deal")
              case KeyMap.lookup "dot" o of
                Just (String dot) -> do
                  dot `shouldSatisfy` Text.isPrefixOf "digraph"
                  dot `shouldSatisfy` Text.isInfixOf "pay"
                  dot `shouldSatisfy` Text.isInfixOf "deliver"
                other -> expectationFailure ("no dot field: " <> show other)
            Nothing -> expectationFailure "response was not a JSON object"
        other -> expectationFailure ("unexpected arguments: " <> show other)

    it "reports notFound for a rule that has no state graph" $ do
      case decodeObject (l4StateGraphByName fixture "`is adult`") of
        Just o -> KeyMap.lookup "notFound" o `shouldBe` Just (Bool True)
        Nothing -> expectationFailure "response was not a JSON object"
