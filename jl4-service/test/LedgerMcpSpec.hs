{-# LANGUAGE OverloadedStrings #-}
-- | The instance ledger's MCP tool, OPERATIONAL-LOWERING-SPEC WPO4: "what
-- may I do now and what would it do", reading the position query.
--
-- The acceptance items run here:
--
-- * __An agent following the tool's answers reproduces Sequence B and is
--   refused in Sequence A.__ The agent is scripted, not a model: it asks
--   the tool what buying dinner would do now, and proposes the buy on the
--   instance's events route, naming the head it was told, only when the
--   tool says the buy would commit a dinner. In Sequence A it is refused
--   twice over: told at 18:05 that the buy would commit a dinner, it
--   proposes at 18:07, after Bob's purchase is recorded at 18:06, and the
--   ledger's step blocks the buy (a row that commits nothing; with a
--   strict proposal, a 409 and no row); asked afresh at 18:07, the tool
--   says the buy would commit nothing, and the agent does not propose.
-- * __A decision tool called with the store absent still answers__: with
--   no ledger at all, and with a ledger whose store cannot be opened.
--
-- The ledger clock is the test's, for §6's times (see "LedgerRoutesSpec").
module LedgerMcpSpec (spec) where

import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import Data.Foldable (toList)
import Data.IORef (newIORef)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text.Encoding
import qualified Data.Text.IO as Text.IO
import Network.HTTP.Types (Header)
import System.FilePath ((</>))
import Test.Hspec

import Ledger.Store.Config (ResolvedStore (..))
import LedgerRoutesSpec hiding (spec)
import TestStoreDir (withStoreDir)

spec :: Spec
spec = do
  dinner <- runIO loadDinnerBundle
  describe "the instance ledger's MCP tool (WPO4)" do
    listSpec dinner
    agentSpec dinner
    absentSpec dinner

-- | A deployment with one decision tool, @is-large@.
decideBundle :: Map FilePath Text
decideBundle = Map.fromList [("decide.l4", Text.unlines
  [ "@export default whether a number is more than five"
  , "GIVEN n IS A NUMBER"
  , "GIVETH A BOOLEAN"
  , "DECIDE `is large` IF n GREATER THAN 5" ])]

----------------------------------------------------------------------------
-- MCP
----------------------------------------------------------------------------

rpc :: Service -> String -> Text -> Aeson.Value -> IO Aeson.Value
rpc s path method params = snd <$> request s "POST" path (Just (Aeson.object
  [ "jsonrpc" Aeson..= ("2.0" :: Text), "id" Aeson..= (1 :: Int), "method" Aeson..= method, "params" Aeson..= params ]))

toolNamesAt :: Service -> [Header] -> String -> IO [Text]
toolNamesAt s headers path = do
  (_, resp) <- requestWith s headers "POST" path (Just (Aeson.object
    [ "jsonrpc" Aeson..= ("2.0" :: Text), "id" Aeson..= (1 :: Int), "method" Aeson..= ("tools/list" :: Text) ]))
  pure case field "result" resp >>= field "tools" of
    Just (Aeson.Array ts) -> [ n | t <- toList ts, Just n <- [str "name" t] ]
    _ -> []

-- | A tool call's answer: whether it is an error, and its text read as JSON
-- (or as a string when it is not JSON).
callTool :: Service -> String -> Text -> Aeson.Value -> IO (Bool, Aeson.Value)
callTool s path name args = do
  resp <- rpc s path "tools/call" (Aeson.object ["name" Aeson..= name, "arguments" Aeson..= args])
  case field "result" resp of
    Just r -> do
      let isErr = field "isError" r == Just (Aeson.Bool True)
          text = case field "content" r of
            Just (Aeson.Array cs) | (c : _) <- toList cs, Just t <- str "text" c -> t
            _ -> ""
      pure (isErr, maybe (Aeson.String text) id (Aeson.decodeStrict (Text.Encoding.encodeUtf8 text)))
    Nothing -> pure (True, resp)

-- | Ask the ledger's tool about an instance of the dinner deployment, on
-- that deployment's own endpoint, perhaps with an act to try.
askTool :: Service -> Text -> Maybe Text -> IO (Bool, Aeson.Value)
askTool s inst mAct = callTool s "/deployments/dinner/.mcp" "what-may-I-do-now" (Aeson.object
  (("instance" Aeson..= inst) : maybe [] (\ a -> ["party" Aeson..= ("World" :: Text), "action" Aeson..= a]) mAct))

headNow :: Aeson.Value -> Maybe Int
headNow answer = field "now" answer >>= int "head"

----------------------------------------------------------------------------
-- The agent
----------------------------------------------------------------------------

-- | Alice's agent deciding whether to buy: it asks the tool what buying
-- dinner would do now, and decides to buy, against the head it was told,
-- only if the tool says the buy would commit a dinner.
decideToBuy :: Service -> Text -> IO (Maybe Int)
decideToBuy s inst = do
  (isErr, answer) <- askTool s inst (Just buy)
  isErr `shouldBe` False
  field "appendedOverMcp" answer `shouldBe` Just (Aeson.Bool False)
  let would = field "ifProposedNow" answer
  (would >>= str "result", would >>= field "applied") `shouldBe` (Just "would be appended", Just (Aeson.Bool False))
  pure if maybe False commitsDinner would then headNow answer else Nothing

-- | The agent acting on its decision: the buy, on the events route, naming
-- the head it decided against.
buyAgainst :: Service -> Text -> [(Aeson.Key, Aeson.Value)] -> Text -> Int -> IO (Int, Aeson.Value)
buyAgainst s inst extra key seen =
  proposeWith s "dinner" inst (("decidedAgainst", Aeson.toJSON seen) : extra) key buy

-- | Create the instance at 18:00, and have the agent check at 18:05: it
-- asks the tool for the position first, and finds the instance at its
-- opening.
evening :: Service -> Text -> IO ()
evening s inst = do
  _ <- at s 64800 (create s "dinner" inst)
  (isErr, answer) <- at s 65100 (askTool s inst Nothing)
  (isErr, headNow answer, field "ifProposedNow" answer) `shouldBe` (False, Just 1, Nothing)
  _ <- at s 65100 (propose s "dinner" inst (inst <> "-check") check)
  pure ()

agentSpec :: Map FilePath Text -> Spec
agentSpec dinner = describe "an agent following the tool's answers" do
  it "reproduces Sequence B: told at 18:05:30 that buying commits a dinner, it buys as row 3, and Bob's purchase is row 4" do
    withStoreDir "ledger-mcp-b" \ dir -> do
      clk <- newIORef 0
      withService dir clk [("dinner", dinner)] \ s -> do
        evening s "b"
        decided <- at s 65130 (decideToBuy s "b")
        decided `shouldBe` Just 2
        (code, r) <- maybe (pure (0, Aeson.Null)) (at s 65130 . buyAgainst s "b" [] "b-buy") decided
        (code, int "seq" r, commitsDinner r) `shouldBe` (200, Just 3, True)
        (_, bob) <- at s 65160 (propose s "dinner" "b" "b-bob" bobBuys)
        (int "seq" bob, commitsDinner bob) `shouldBe` (Just 4, False)
        (_, p) <- position s "dinner" "b"
        dinnersAtHead p `shouldBe` 1

  it "is refused in Sequence A: told at 18:05 that buying commits a dinner, it buys at 18:07, after Bob's purchase, and the ledger's step commits none" do
    withStoreDir "ledger-mcp-a" \ dir -> do
      clk <- newIORef 0
      withService dir clk [("dinner", dinner)] \ s -> do
        evening s "a"
        decided <- at s 65100 (decideToBuy s "a")
        decided `shouldBe` Just 2
        _ <- at s 65160 (propose s "dinner" "a" "a-bob" bobBuys)
        (code, r) <- maybe (pure (0, Aeson.Null)) (at s 65220 . buyAgainst s "a" [] "a-buy") decided
        (code, int "seq" r, commitsDinner r) `shouldBe` (200, Just 4, False)
        texts "wrote" r `shouldBe` ["RECORD Alice's `belief` IS taken", "RECORD Alice's `plan` IS stopped"]
        (_, p) <- position s "dinner" "a"
        dinnersAtHead p `shouldBe` 0

  it "is refused in Sequence A as a strict proposal too: a 409, and no row" do
    withStoreDir "ledger-mcp-a-strict" \ dir -> do
      clk <- newIORef 0
      withService dir clk [("dinner", dinner)] \ s -> do
        evening s "a"
        decided <- at s 65100 (decideToBuy s "a")
        _ <- at s 65160 (propose s "dinner" "a" "a-bob" bobBuys)
        let strictly = [("strict", Aeson.Bool True), ("cells", Aeson.toJSON ["dinner status record" :: Text])]
        (code, r) <- maybe (pure (0, Aeson.Null)) (at s 65220 . buyAgainst s "a" strictly "a-buy") decided
        (code, str "result" r) `shouldBe` (409, Just "conflict")
        (_, p) <- position s "dinner" "a"
        (int "head" p, dinnersAtHead p) `shouldBe` (Just 3, 0)

  it "does not buy in Sequence A when it asks after Bob's purchase is recorded: the tool says the buy commits nothing" do
    withStoreDir "ledger-mcp-a-fresh" \ dir -> do
      clk <- newIORef 0
      withService dir clk [("dinner", dinner)] \ s -> do
        evening s "a"
        _ <- at s 65160 (propose s "dinner" "a" "a-bob" bobBuys)
        at s 65220 (decideToBuy s "a") `shouldReturn` Nothing
        (_, p) <- position s "dinner" "a"
        (int "head" p, dinnersAtHead p) `shouldBe` (Just 3, 0)

  it "never appends: the tool's preview leaves the instance at its head, and the act it tried is still the agent's to propose" do
    withStoreDir "ledger-mcp-noappend" \ dir -> do
      clk <- newIORef 0
      withService dir clk [("dinner", dinner)] \ s -> do
        evening s "x"
        _ <- at s 65130 (askTool s "x" (Just buy))
        _ <- at s 65130 (askTool s "x" (Just buy))
        (_, p) <- position s "dinner" "x"
        (int "head" p, dinnersAtHead p) `shouldBe` (Just 2, 0)
        -- the key the preview used is not taken: the real buy is row 3
        (_, r) <- at s 65130 (propose s "dinner" "x" "what-may-I-do-now preview" buy)
        (int "seq" r, field "replayed" r) `shouldBe` (Just 3, Just (Aeson.Bool True))

  it "is told plainly when the instance is not there" do
    withStoreDir "ledger-mcp-nf" \ dir -> do
      clk <- newIORef 65100
      withService dir clk [("dinner", dinner)] \ s -> do
        (isErr, answer) <- askTool s "nobody" (Just buy)
        isErr `shouldBe` True
        (field "now" answer >>= str "result") `shouldBe` Just "not found"

----------------------------------------------------------------------------
-- Where the tool is listed
----------------------------------------------------------------------------

listSpec :: Map FilePath Text -> Spec
listSpec dinner = describe "the tool's registration" do
  it "is listed beside the decision tools, on the org-wide endpoint and a deployment's own, and not to a caller that may not evaluate" do
    withStoreDir "ledger-mcp-list" \ dir -> do
      clk <- newIORef 64800
      withService dir clk [("dinner", dinner), ("decide", decideBundle)] \ s -> do
        org <- toolNamesAt s [] "/.mcp"
        org `shouldSatisfy` (\ ns -> "what-may-I-do-now" `elem` ns && "is-large" `elem` ns)
        own <- toolNamesAt s [] "/deployments/dinner/.mcp"
        own `shouldSatisfy` ("what-may-I-do-now" `elem`)
        hidden <- toolNamesAt s [("X-Include-Evaluate", "false")] "/.mcp"
        hidden `shouldSatisfy` notElem "what-may-I-do-now"

----------------------------------------------------------------------------
-- The store absent (§8, "decision tools still stateless")
----------------------------------------------------------------------------

absentSpec :: Map FilePath Text -> Spec
absentSpec dinner = describe "a decision tool with the ledger's store absent" do
  it "still answers when the service has no ledger, and the ledger's tool is not listed" do
    withStoreDir "ledger-mcp-none" \ dir -> do
      clk <- newIORef 64800
      withServiceUsing NoLedger [] dir clk [("decide", decideBundle)] \ s -> do
        names <- toolNamesAt s [] "/.mcp"
        names `shouldSatisfy` (\ ns -> "is-large" `elem` ns && "what-may-I-do-now" `notElem` ns)
        decision s

  it "still answers when the ledger's store cannot be opened, and the ledger's own tool and routes say so" do
    withStoreDir "ledger-mcp-blocked" \ dir -> do
      clk <- newIORef 64800
      -- a file where the store's directory should be
      let blocked = dir <> "-not-a-directory"
      Text.IO.writeFile blocked "this is a file"
      withServiceUsing (LedgerAt (SqliteAt (blocked </> "ledger"))) [] dir clk [("decide", decideBundle), ("dinner", dinner)] \ s -> do
        decision s
        (isErr, answer) <- askTool s "evening" Nothing
        isErr `shouldBe` True
        (field "now" answer >>= str "because") `shouldSatisfy` maybe False ("could not be opened" `Text.isInfixOf`)
        (code, r) <- create s "dinner" "evening"
        (code, field "applied" r) `shouldBe` (503, Just (Aeson.Bool False))
        decision s
  where
    decision s = do
      (isErr, answer) <- callTool s "/.mcp" "is-large" (Aeson.object ["n" Aeson..= (7 :: Int)])
      isErr `shouldBe` False
      Text.Encoding.decodeUtf8 (LBS.toStrict (Aeson.encode answer)) `shouldSatisfy` Text.isInfixOf "true"
