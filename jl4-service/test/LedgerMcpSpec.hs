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
-- * __The write tools (WPO6, D-O13)__, off unless the service is started
--   with @--ledger-mcp-write@: Sequence B over MCP appends as over HTTP,
--   a strict buy in Sequence A is a conflict and appends nothing, a retry
--   under the same key makes one row, an act that is not offered to the
--   caller's party is refused, and with the flag off none is listed.
--
-- The ledger clock is the test's, for §6's times (see "LedgerRoutesSpec").
module LedgerMcpSpec (spec) where

import qualified Data.Aeson as Aeson
import Control.Monad (forM_)
import qualified Data.ByteString.Lazy as LBS
import Data.Foldable (toList)
import Data.IORef (newIORef)
import Data.List (find, sort)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text.Encoding
import qualified Data.Text.IO as Text.IO
import Network.HTTP.Types (Header)
import System.Directory (doesFileExist, getCurrentDirectory)
import System.FilePath (takeDirectory, (</>))
import Test.Hspec

import Ledger.Store.Config (ResolvedStore (..))
import LedgerRoutesSpec hiding (spec)
import TestStoreDir (withStoreDir)

spec :: Spec
spec = do
  dinner <- runIO loadDinnerBundle
  exchange <- runIO loadExchangeBundle
  describe "the instance ledger's MCP tool (WPO4)" do
    listSpec dinner
    agentSpec dinner
    absentSpec dinner
  describe "the instance ledger's MCP write tools (WPO6)" do
    writeSpec dinner exchange

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

-- | A JSON-RPC call, with request headers as a proxy would set them.
rpcWith :: Service -> [Header] -> String -> Text -> Aeson.Value -> IO Aeson.Value
rpcWith s headers path method params = snd <$> requestWith s headers "POST" path (Just (Aeson.object
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
callTool s = callToolWith s []

-- | 'callTool' with request headers.
callToolWith :: Service -> [Header] -> String -> Text -> Aeson.Value -> IO (Bool, Aeson.Value)
callToolWith s headers path name args = do
  resp <- rpcWith s headers path "tools/call" (Aeson.object ["name" Aeson..= name, "arguments" Aeson..= args])
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

  it "is told in a preview what a refused act would be preceded by, and appends nothing: past the deadline, the tick is listed and no row is written" do
    withStoreDir "ledger-mcp-late-refusal" \ dir -> do
      clk <- newIORef 0
      withService dir clk [("dinner", dinner)] \ s -> do
        evening s "late"
        (isErr, answer) <- at s 75700 (askTool s "late" (Just "`Alice sings`"))
        let would = field "ifProposedNow" answer
        (isErr, would >>= str "result", would >>= int "head") `shouldBe` (False, Just "would be refused", Just 3)
        fmap tickRows would `shouldBe` Just [(Just 3, Just (Aeson.Number 75601))]
        (_, p) <- position s "dinner" "late"
        int "head" p `shouldBe` Just 2

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

----------------------------------------------------------------------------
-- The write tools (WPO6, D-O13)
----------------------------------------------------------------------------

-- | The two-party fixture of the write tools' tests, as a deployment
-- uploads it: one file.
loadExchangeBundle :: IO (Map FilePath Text)
loadExchangeBundle = do
  root <- getCurrentDirectory >>= findRoot
  src <- Text.IO.readFile (root </> fixture)
  pure (Map.fromList [("two-party.l4", src)])
  where
    fixture = "jl4/examples/explore/ledger/two-party.l4"
    findRoot d = do
      found <- doesFileExist (d </> fixture)
      if found then pure d
      else if takeDirectory d == d then fail ("LedgerMcpSpec: the repository root (" <> fixture <> ") was not found above the working directory")
      else findRoot (takeDirectory d)

-- | The tools a caller is shown at an endpoint, as their definitions.
toolListAt :: Service -> [Header] -> String -> IO [Aeson.Value]
toolListAt s headers path = do
  resp <- rpcWith s headers path "tools/list" (Aeson.object [])
  pure case field "result" resp >>= field "tools" of
    Just (Aeson.Array ts) -> toList ts
    _ -> []

-- | The service with the write tools on.
withWrites :: FilePath -> [(Text, Map FilePath Text)] -> (Service -> IO a) -> IO a
withWrites tag deployments act = withStoreDir tag \ dir -> do
  clk <- newIORef 64800
  withServiceUsing DefaultLedger ["--ledger-mcp-write"] dir clk deployments act

isWriteTool :: Text -> Bool
isWriteTool = Text.isPrefixOf "act-"

-- | The party a proxy says the caller is.
asParty :: Text -> [Header]
asParty p = [("X-L4-Party", Text.Encoding.encodeUtf8 p)]

ownEndpoint :: Text -> String
ownEndpoint d = "/deployments/" <> Text.unpack d <> "/.mcp"

-- | Create an instance of a deployment's contract.
createFor :: Service -> Text -> Text -> Text -> IO (Int, Aeson.Value)
createFor s dep name contract = request s "POST" ("/deployments/" <> Text.unpack dep <> "/instances") (Just (Aeson.object
  ["instance" Aeson..= name, "contract" Aeson..= contract]))

-- | The head of an instance, if it is there.
headOf :: Service -> Text -> Text -> IO (Maybe Int)
headOf s dep name = int "head" . snd <$> position s dep name

-- | A write tool called by a party on a deployment's own endpoint, for an
-- instance, with these further arguments.
callAs :: Service -> Text -> Text -> Text -> Text -> [(Aeson.Key, Aeson.Value)] -> IO (Bool, Aeson.Value)
callAs s party dep inst tool extra =
  callToolWith s (asParty party) (ownEndpoint dep) tool (Aeson.object (("instance" Aeson..= inst) : extra))

idemKey :: Text -> (Aeson.Key, Aeson.Value)
idemKey k = ("idempotencyKey", Aeson.String k)

writeSpec :: Map FilePath Text -> Map FilePath Text -> Spec
writeSpec dinner exchange = do
  it "is off by default: no write tool is listed to any caller, a call to one appends nothing, and the read tool does not mention them" do
    withStoreDir "ledger-mcp-w-off" \ dir -> do
      clk <- newIORef 64800
      withService dir clk [("dinner", dinner)] \ s -> do
        names <- toolNamesAt s (asParty "World") (ownEndpoint "dinner")
        filter isWriteTool names `shouldBe` []
        _ <- at s 64800 (create s "dinner" "off")
        (isErr, _) <- callAs s "World" "dinner" "off" "act-Alice-checks-whether-dinner-is-bought" [idemKey "k1"]
        isErr `shouldBe` True
        headOf s "dinner" "off" `shouldReturn` Just 1
        (_, answer) <- callToolWith s (asParty "World") (ownEndpoint "dinner") "what-may-I-do-now" (Aeson.object ["instance" Aeson..= ("off" :: Text)])
        field "writeTools" answer `shouldBe` Nothing

  it "lists, to the party World, one tool for each act of the dinner contract, and none on the org-wide endpoint" do
    withWrites "ledger-mcp-w-list" [("dinner", dinner)] \ s -> do
      names <- toolNamesAt s (asParty "World") (ownEndpoint "dinner")
      sort (filter isWriteTool names) `shouldBe` sort
        [ "act-Alice-buys-dinner", "act-Alice-checks-whether-dinner-is-bought", "act-Alice-is-done"
        , "act-Messages-delivers-the-message", "act-ledger-records-Bob-s-purchase" ]
      defs <- toolListAt s (asParty "World") (ownEndpoint "dinner")
      let buyDef = find ((== Just "act-Alice-buys-dinner") . str "name") defs
      (buyDef >>= field "inputSchema" >>= \ sch -> Just (texts "required" sch)) `shouldBe` Just ["instance", "idempotencyKey", "ledger-answered"]
      org <- toolNamesAt s (asParty "World") "/.mcp"
      filter isWriteTool org `shouldBe` []

  it "offers an act only to the party whose clause names it: a caller that is not World, or names no party, has no tool for a dinner act, and a call is refused with nothing appended" do
    withWrites "ledger-mcp-w-scope" [("dinner", dinner)] \ s -> do
      _ <- at s 64800 (create s "dinner" "scope")
      forM_ [asParty "Alice", []] \ who -> do
        names <- toolNamesAt s who (ownEndpoint "dinner")
        filter isWriteTool names `shouldBe` []
      (eA, rA) <- callToolWith s (asParty "Alice") (ownEndpoint "dinner") "act-Alice-is-done" (Aeson.object ["instance" Aeson..= ("scope" :: Text), idemKey "s1"])
      (eA, field "applied" rA, str "because" rA >>= \ b -> Just ("not offered to Alice" `Text.isInfixOf` b)) `shouldBe` (True, Just (Aeson.Bool False), Just True)
      (eN, rN) <- callToolWith s [] (ownEndpoint "dinner") "act-Alice-is-done" (Aeson.object ["instance" Aeson..= ("scope" :: Text), idemKey "s2"])
      (eN, str "because" rN >>= \ b -> Just ("names no party" `Text.isInfixOf` b)) `shouldBe` (True, Just True)
      headOf s "dinner" "scope" `shouldReturn` Just 1

  it "Sequence B over MCP: the buy is row 3 and commits the dinner, Bob's purchase is row 4, and a retry under the same key is the same row" do
    withWrites "ledger-mcp-w-b" [("dinner", dinner)] \ s -> do
      _ <- at s 64800 (create s "dinner" "b")
      let call tool extra = callAs s "World" "dinner" "b" tool extra
      (e2, r2) <- at s 65100 (call "act-Alice-checks-whether-dinner-is-bought" [idemKey "b2"])
      (e2, str "result" r2, int "seq" r2) `shouldBe` (False, Just "appended", Just 2)
      (e3, r3) <- at s 65130 (call "act-Alice-buys-dinner" [idemKey "b3", "ledger-answered" Aeson..= True])
      (e3, int "seq" r3, commitsDinner r3) `shouldBe` (False, Just 3, True)
      (_, r4) <- at s 65160 (call "act-ledger-records-Bob-s-purchase" [idemKey "b4"])
      (int "seq" r4, commitsDinner r4) `shouldBe` (Just 4, False)
      (eR, rR) <- at s 65170 (call "act-Alice-buys-dinner" [idemKey "b3", "ledger-answered" Aeson..= True])
      (eR, int "seq" rR, field "replayed" rR) `shouldBe` (False, Just 3, Just (Aeson.Bool False))
      (_, p) <- position s "dinner" "b"
      (int "head" p, dinnersAtHead p) `shouldBe` (Just 4, 1)

  it "Sequence A over MCP: a strict buy decided against head 2 is a conflict and appends nothing, and the same buy not strict is row 4 and commits no dinner" do
    withWrites "ledger-mcp-w-a" [("dinner", dinner)] \ s -> do
      _ <- at s 64800 (create s "dinner" "a")
      let call tool extra = callAs s "World" "dinner" "a" tool extra
      _ <- at s 65100 (call "act-Alice-checks-whether-dinner-is-bought" [idemKey "a2"])
      _ <- at s 65160 (call "act-ledger-records-Bob-s-purchase" [idemKey "a3"])
      (eS, rS) <- at s 65220 (call "act-Alice-buys-dinner" [idemKey "a4s", "ledger-answered" Aeson..= True, "decidedAgainst" Aeson..= (2 :: Int)])
      (eS, str "result" rS, field "applied" rS) `shouldBe` (True, Just "conflict", Just (Aeson.Bool False))
      headOf s "dinner" "a" `shouldReturn` Just 3
      (eN, rN) <- at s 65221 (call "act-Alice-buys-dinner" [idemKey "a4", "ledger-answered" Aeson..= True])
      (eN, int "seq" rN, commitsDinner rN) `shouldBe` (False, Just 4, False)
      (_, p) <- position s "dinner" "a"
      dinnersAtHead p `shouldBe` 0

  it "refuses, loudly and with nothing appended, a call with no idempotency key, a field of the wrong type, and an argument the tool does not take, among them a party" do
    withWrites "ledger-mcp-w-args" [("dinner", dinner)] \ s -> do
      _ <- at s 64800 (create s "dinner" "args")
      let call = callAs s "World" "dinner" "args"
          because r = str "because" r
      (e1, r1) <- call "act-Alice-is-done" []
      (e1, because r1 >>= \ b -> Just ("idempotencyKey" `Text.isInfixOf` b)) `shouldBe` (True, Just True)
      (e2, r2) <- call "act-Alice-buys-dinner" [idemKey "x", "ledger-answered" Aeson..= ("yes" :: Text)]
      (e2, because r2 >>= \ b -> Just ("true or false" `Text.isInfixOf` b)) `shouldBe` (True, Just True)
      (e3, r3) <- call "act-Alice-is-done" [idemKey "x", "party" Aeson..= ("Alice" :: Text)]
      (e3, because r3 >>= \ b -> Just ("does not take party" `Text.isInfixOf` b)) `shouldBe` (True, Just True)
      headOf s "dinner" "args" `shouldReturn` Just 1

  describe "on a contract whose clauses name their actors" do
    it "offers Alice the quote and Bob the acceptance, and refuses each the other's act" do
      withWrites "ledger-mcp-w-party" [("exchange", exchange)] \ s -> do
        aliceNames <- toolNamesAt s (asParty "Alice") (ownEndpoint "exchange")
        filter isWriteTool aliceNames `shouldBe` ["act-Alice-quotes"]
        bobNames <- toolNamesAt s (asParty "Bob") (ownEndpoint "exchange")
        filter isWriteTool bobNames `shouldBe` ["act-Bob-accepts"]
        _ <- at s 1000 (createFor s "exchange" "e1" "`the exchange`")
        (eB, rB) <- callAs s "Bob" "exchange" "e1" "act-Alice-quotes" [idemKey "p1", "price" Aeson..= (1 :: Int), "note" Aeson..= ("x" :: Text)]
        (eB, str "because" rB >>= \ b -> Just ("not offered to Bob" `Text.isInfixOf` b)) `shouldBe` (True, Just True)
        (eA, rA) <- callAs s "Alice" "exchange" "e1" "act-Bob-accepts" [idemKey "p2", "agreed" Aeson..= True]
        (eA, str "because" rA >>= \ b -> Just ("not offered to Alice" `Text.isInfixOf` b)) `shouldBe` (True, Just True)
        headOf s "exchange" "e1" `shouldReturn` Just 1

    it "performs an act with a NUMBER and a STRING field as the source the ledger replays, and then Bob's acceptance" do
      withWrites "ledger-mcp-w-fields" [("exchange", exchange)] \ s -> do
        _ <- at s 1000 (createFor s "exchange" "e2" "`the exchange`")
        (eQ, rQ) <- at s 2000 (callAs s "Alice" "exchange" "e2" "act-Alice-quotes" [idemKey "q1", "price" Aeson..= (12.5 :: Double), "note" Aeson..= ("hello" :: Text)])
        (eQ, str "result" rQ, int "seq" rQ) `shouldBe` (False, Just "appended", Just 2)
        (field "row" rQ >>= field "event" >>= str "action") `shouldBe` Just "(`Alice quotes` 12.5 \"hello\")"
        (eC, rC) <- at s 3000 (callAs s "Bob" "exchange" "e2" "act-Bob-accepts" [idemKey "c1", "agreed" Aeson..= True])
        (eC, str "result" rC, int "seq" rC) `shouldBe` (False, Just "appended", Just 3)

    it "writes a negative number in parentheses, and refuses a string that holds a quote" do
      withWrites "ledger-mcp-w-neg" [("exchange", exchange)] \ s -> do
        _ <- at s 1000 (createFor s "exchange" "e3" "`the exchange`")
        (eQ, rQ) <- at s 2000 (callAs s "Alice" "exchange" "e3" "act-Alice-quotes" [idemKey "q1", "price" Aeson..= (-5 :: Int), "note" Aeson..= ("x" :: Text)])
        (eQ, (field "row" rQ >>= field "event" >>= str "action")) `shouldBe` (False, Just "(`Alice quotes` (-5) \"x\")")
        _ <- at s 1000 (createFor s "exchange" "e4" "`the exchange`")
        (eS, rS) <- at s 2000 (callAs s "Alice" "exchange" "e4" "act-Alice-quotes" [idemKey "q2", "price" Aeson..= (1 :: Int), "note" Aeson..= ("say \"hi\"" :: Text)])
        (eS, str "because" rS >>= \ b -> Just ("quote" `Text.isInfixOf` b)) `shouldBe` (True, Just True)
        headOf s "exchange" "e4" `shouldReturn` Just 1

    it "has the read tool name the acts a party has no tool for, and why: a list field, and a field named like the call's own argument" do
      withWrites "ledger-mcp-w-report" [("exchange", exchange)] \ s -> do
        _ <- at s 1000 (createFor s "exchange" "e5" "`the exchange`")
        (isErr, answer) <- callToolWith s (asParty "Alice") (ownEndpoint "exchange") "what-may-I-do-now" (Aeson.object ["instance" Aeson..= ("e5" :: Text)])
        isErr `shouldBe` False
        let report = field "writeTools" answer
        (report >>= \ r -> Just (texts "tools" r)) `shouldBe` Just ["act-Alice-quotes"]
        (report >>= field "notOffered") `shouldSatisfy` \ case
          Just (Aeson.Array xs) -> any (\ x -> str "act" x == Just "Alice asks to see the terms" && maybe False ("LIST" `Text.isInfixOf`) (str "because" x)) (toList xs)
          _ -> False
        (report >>= field "notOffered") `shouldSatisfy` \ case
          Just (Aeson.Array xs) -> any (\ x -> str "act" x == Just "Alice files a reference" && maybe False ("named like" `Text.isInfixOf`) (str "because" x)) (toList xs)
          _ -> False
