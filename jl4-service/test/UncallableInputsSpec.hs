{-# LANGUAGE OverloadedStrings #-}

-- | The deploy-time warning for inputs no call can fill (UncallableInputs).
--
-- A constructor that carries data has no JSON form the service accepts as an
-- input, yet the published schema lists its name; so such an input deploys
-- cleanly and fails on every call. These tests pin what is warned about, what
-- is not, and that the warning is only a warning: the deploy applies, the
-- schema is what it was, and the warning reaches the job result and the
-- deployment's status.
--
-- They say nothing about what the JSON form of such a constructor should be.
module UncallableInputsSpec (spec) where

import Test.Hspec

import Application (app)
import BundleStore (initStore)
import Compiler (compileBundle)
import ControlPlane (DeploymentStatusResponse (..), UpdateStatusResponse (..))
import L4.FunctionSchema (Parameters (..), Parameter (..))
import Logging (newLogger)
import Options (Options (..))
import TestStoreDir (withStoreDir)
import Types

import qualified Codec.Archive.Zip as Zip
import Control.Concurrent (threadDelay)
import Control.Concurrent.STM (newTVarIO)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text.Encoding
import Network.HTTP.Client
  ( Manager, RequestBody (..), defaultManagerSettings, httpLbs, method
  , newManager, parseRequest, requestBody, requestHeaders, responseBody )
import Network.Wai.Handler.Warp (testWithApplication)

-- | The types the cases use. Only Shape, TwoNumbers and Colour are sums.
preamble :: Text
preamble = Text.unlines
  [ "DECLARE Shape IS ONE OF"
  , "    Circle HAS"
  , "      radius IS A NUMBER"
  , "    Unspecified"
  , ""
  , "DECLARE TwoNumbers IS ONE OF"
  , "    MkTwoNumbers HAS"
  , "      num1 IS A NUMBER"
  , "      num2 IS A NUMBER"
  , ""
  , "DECLARE Colour IS ONE OF Red, Green"
  , ""
  , "DECLARE Plot HAS"
  , "    name IS A STRING"
  , "    shape IS A Shape"
  , ""
  , "DECLARE Lot HAS"
  , "    name IS A STRING"
  , "    spare IS A MAYBE Shape"
  , ""
  , "DECLARE Parcel HAS"
  , "    name IS A STRING"
  , "    shape IS A Shape TYPICALLY Unspecified"
  , ""
  , "DECLARE Painted HAS"
  , "    name IS A STRING"
  , "    colour IS A Colour"
  , ""
  , "DECLARE ShapeAlias IS A Shape"
  , ""
  ]

-- | An exported function of one input and no real body.
fn :: Text -> Text -> Text
fn name given = Text.unlines
  [ "@export " <> name
  , "GIVEN x IS " <> given
  , "GIVETH A NUMBER"
  , name <> " x MEANS 0"
  , ""
  ]

-- | What a source's compile says about it: (function, path, type, can't send, can send).
type Warned = (Text, [Text], Text, [Text], [Text])

warnedBy :: Text -> IO [Warned]
warnedBy src = do
  meta <- metaOf src
  pure [ (w.dwFunction, w.dwParameter, w.dwType, w.dwConstructors, w.dwCanSupply) | w <- meta.metaWarnings ]

metaOf :: Text -> IO DeploymentMetadata
metaOf src = do
  logger <- newLogger False
  compileBundle logger "spec" (Map.singleton "main.l4" (preamble <> src)) >>= \case
    Left err -> fail ("the fixture did not compile: " <> Text.unpack err)
    Right (_, meta) -> pure meta

spec :: Spec
spec = describe "inputs no call can fill (UncallableInputs)" do

  describe "are warned about" do
    it "a required input of a type with a constructor that carries data" do
      warnedBy (fn "direct" "A Shape")
        `shouldReturn` [("direct", ["x"], "Shape", ["Circle"], ["Unspecified"])]

    it "a required field of a record input, with the path to it" do
      warnedBy (fn "nested" "A Plot")
        `shouldReturn` [("nested", ["x", "shape"], "Shape", ["Circle"], ["Unspecified"])]

    it "an input reached through a synonym" do
      warnedBy (fn "viaSynonym" "A ShapeAlias")
        `shouldReturn` [("viaSynonym", ["x"], "Shape", ["Circle"], ["Unspecified"])]

    it "EITHER, which is built in and has two constructors that carry data" do
      warnedBy (fn "either" "AN EITHER STRING NUMBER")
        `shouldReturn` [("either", ["x"], "EITHER", ["LEFT", "RIGHT"], [])]

    it "a type whose only constructor carries data, which is a record written as a sum" do
      warnedBy (fn "single" "A TwoNumbers")
        `shouldReturn` [("single", ["x"], "TwoNumbers", ["MkTwoNumbers"], [])]

    it "each offending function by its own name, and only those" do
      warnedBy (fn "bad" "A Shape" <> fn "fine" "A Colour" <> fn "alsoBad" "A Plot")
        `shouldReturn`
          [ ("bad", ["x"], "Shape", ["Circle"], ["Unspecified"])
          , ("alsoBad", ["x", "shape"], "Shape", ["Circle"], ["Unspecified"])
          ]

  describe "are not warned about" do
    it "a type whose constructors carry no data" do
      warnedBy (fn "plain" "A Colour") `shouldReturn` []

    it "a record whose fields are all plain" do
      warnedBy (fn "painted" "A Painted") `shouldReturn` []

    it "an input that may be left out: MAYBE" do
      warnedBy (fn "optional" "A MAYBE Shape") `shouldReturn` []

    it "an input that may be an empty list" do
      warnedBy (fn "several" "A LIST OF Shape") `shouldReturn` []

    it "an input with a TYPICALLY default" do
      warnedBy (fn "defaulted" "A Shape TYPICALLY Unspecified") `shouldReturn` []

    it "a record field that may be left out: MAYBE, or TYPICALLY" do
      warnedBy (fn "lot" "A Lot" <> fn "parcel" "A Parcel") `shouldReturn` []

    it "a type that carries data only in what a function returns" do
      warnedBy (Text.unlines
        [ "@export out"
        , "GIVEN r IS A NUMBER"
        , "GIVETH A Shape"
        , "out r MEANS Circle OF r"
        ]) `shouldReturn` []

    it "a function that is not exported" do
      warnedBy (Text.unlines
        [ "GIVEN x IS A Shape"
        , "GIVETH A NUMBER"
        , "internal x MEANS 0"
        ]) `shouldReturn` []

  describe "the warning" do
    it "names the function, the path to the input, the type and the constructor" do
      meta <- metaOf (fn "area" "A Plot")
      case meta.metaWarnings of
        [w] -> do
          w.dwKind `shouldBe` "uncallable-input"
          w.dwMessage `shouldSatisfy` Text.isInfixOf "area"
          w.dwMessage `shouldSatisfy` Text.isInfixOf "`x` > `shape`"
          w.dwMessage `shouldSatisfy` Text.isInfixOf "Shape"
          w.dwMessage `shouldSatisfy` Text.isInfixOf "Circle"
          w.dwMessage `shouldSatisfy` Text.isInfixOf "Unspecified"
        other -> expectationFailure ("expected one warning, got " <> show (length other))

    it "changes nothing the service publishes: the deploy applies and the schema is as it was" do
      meta <- metaOf (fn "area" "A Shape")
      [fs] <- pure meta.metaFunctions
      Map.keys fs.fsParameters.parameterMap `shouldBe` ["x"]
      let p = fs.fsParameters.parameterMap Map.! "x"
      p.parameterType `shouldBe` "string"
      p.parameterEnum `shouldBe` ["Circle", "Unspecified"]
      fs.fsParameters.required `shouldBe` ["x"]

    it "is left out of the metadata JSON when there is nothing to say, and read back when there is" do
      clean <- metaOf (fn "plain" "A Colour")
      KeyMap.member "warnings" (asObject (Aeson.toJSON clean)) `shouldBe` False
      dirty <- metaOf (fn "direct" "A Shape")
      KeyMap.member "warnings" (asObject (Aeson.toJSON dirty)) `shouldBe` True
      (Aeson.fromJSON (Aeson.toJSON dirty) :: Aeson.Result DeploymentMetadata)
        `shouldSatisfy` \case
          Aeson.Success m -> m.metaWarnings == dirty.metaWarnings
          Aeson.Error _ -> False
      -- a metadata cache written before warnings existed has no such key
      (Aeson.fromJSON (Aeson.toJSON clean) :: Aeson.Result DeploymentMetadata)
        `shouldSatisfy` \case
          Aeson.Success m -> null m.metaWarnings
          Aeson.Error _ -> False

  describe "reaches the operator" do
    it "in the job result and in the deployment's status, and the deploy still applies" do
      withService $ \baseUrl mgr -> do
        job <- deploy baseUrl mgr "warned" (preamble <> fn "direct" "A Shape")
        job.usStatus `shouldBe` "applied"
        job.usError `shouldBe` Nothing
        map (.dwFunction) job.usWarnings `shouldBe` ["direct"]
        status <- getDeployment baseUrl mgr "warned"
        status.dsStatus `shouldBe` "ready"
        (map (.dwFunction) . (.metaWarnings) <$> status.dsMetadata) `shouldBe` Just ["direct"]
        fmap (.dwParameter) (concatMap (.metaWarnings) status.dsMetadata) `shouldBe` [["x"]]

    it "says nothing for a deploy with nothing to warn about" do
      withService $ \baseUrl mgr -> do
        job <- deploy baseUrl mgr "clean" (preamble <> fn "plain" "A Colour")
        job.usStatus `shouldBe` "applied"
        job.usWarnings `shouldBe` []
        status <- getDeployment baseUrl mgr "clean"
        (null . (.metaWarnings) <$> status.dsMetadata) `shouldBe` Just True

asObject :: Aeson.Value -> Aeson.Object
asObject (Aeson.Object o) = o
asObject _ = mempty

------------------------------------------------------------------------
-- Harness: the real application on a free port, as PutGuardSpec has it.
------------------------------------------------------------------------

testOpts :: Options
testOpts = Options
  { port = 0
  , storePath = "unused"
  , serverName = Nothing
  , lazyLoad = False
  , debug = True
  , maxZipSize = 2097152
  , maxFileCount = 5096
  , maxDeployments = 1024
  , maxConcurrentRequests = 20
  , maxEvalMemoryMb = 256
  , maxCompileMemoryMb = 512
  , evalTimeout = 60
  , compileTimeout = 60
  , instanceToken = Nothing
  , maxLadderNodes = 10000
  }

withService :: (String -> Manager -> IO a) -> IO a
withService act = withStoreDir "uncallable-inputs" \tmpPath -> do
  logger <- newLogger False
  store <- initStore tmpPath
  registry <- newTVarIO Map.empty
  pendingUpd <- newTVarIO Map.empty
  tasksReg <- newTVarIO Map.empty
  slots <- newBatchSlots
  let env = MkAppEnv registry pendingUpd store Nothing logger testOpts tasksReg slots
  mgr <- newManager defaultManagerSettings
  testWithApplication (pure $ app env) $ \prt ->
    act ("http://localhost:" <> show prt) mgr

-- | POST a one-file bundle and wait for its job to finish.
deploy :: String -> Manager -> Text -> Text -> IO UpdateStatusResponse
deploy baseUrl mgr deployId src = do
  req0 <- parseRequest (baseUrl <> "/deployments")
  let boundary = "----UncallableInputsBoundary"
      crlf = "\r\n"
      zipBytes = Zip.fromArchive $ Zip.addEntryToArchive
        (Zip.toEntry "main.l4" 0 (LBS.fromStrict (Text.Encoding.encodeUtf8 src))) Zip.emptyArchive
      body = LBS.fromChunks
        [ "--" <> boundary <> crlf
        , "Content-Disposition: form-data; name=\"id\"" <> crlf <> crlf
        , Text.Encoding.encodeUtf8 deployId <> crlf
        , "--" <> boundary <> crlf
        , "Content-Disposition: form-data; name=\"sources\"; filename=\"bundle.zip\"" <> crlf
        , "Content-Type: application/zip" <> crlf <> crlf
        ] <> zipBytes <> LBS.fromChunks [crlf, "--" <> boundary <> "--" <> crlf]
  resp <- httpLbs req0
    { method = "POST"
    , requestBody = RequestBodyLBS body
    , requestHeaders = [("Content-Type", "multipart/form-data; boundary=" <> boundary)]
    } mgr
  uid <- case Aeson.decode (responseBody resp) of
    Just (DeploymentStatusResponse{dsUpdateId = Just u}) -> pure u
    _ -> fail ("no updateId in the deploy response: " <> show (responseBody resp))
  poll uid (120 :: Int)
 where
  poll _ 0 = fail "the deploy job did not finish"
  poll uid n = do
    req <- parseRequest (baseUrl <> "/deployments/" <> Text.unpack deployId <> "/updates/" <> Text.unpack uid)
    resp <- httpLbs req mgr
    case Aeson.decode (responseBody resp) of
      Just u | u.usStatus /= "compiling" -> pure u
      Just _ -> threadDelay 500_000 >> poll uid (n - 1)
      Nothing -> fail ("undecodable job: " <> show (responseBody resp))

getDeployment :: String -> Manager -> Text -> IO DeploymentStatusResponse
getDeployment baseUrl mgr deployId = do
  req <- parseRequest (baseUrl <> "/deployments/" <> Text.unpack deployId)
  resp <- httpLbs req mgr
  maybe (fail ("undecodable status: " <> show (responseBody resp))) pure (Aeson.decode (responseBody resp))
