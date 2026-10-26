{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

-- | The helpers are exported for "StdlibResolutionSpec", which needs the same
-- in-process service but must control the environment around it.
module IntegrationSpec (spec, withServiceFromSources, evalFunction, assertSuccess, testOptions) where

import Test.Hspec

import Application (app)
import Backend.Api
import qualified BundleStore
import BundleStore (initStore)
import Compiler (compileBundle, computeVersion)
import qualified DeploymentLoader
import qualified Version
import ControlPlane (DeploymentStatusResponse (..))
import Logging (newLogger, newLoggerTo)
import Options (Options (..))
import Types
import L4.FunctionSchema (Parameters (..))

import Control.Concurrent.Async (concurrently, forConcurrently)
import Control.Monad (forM, forM_, guard, replicateM, unless, when)
import Control.Concurrent (getNumCapabilities, setNumCapabilities, threadDelay)
import Control.Concurrent.STM (TVar, newTVarIO, readTVarIO)
import Control.Exception (bracket, try)
import Data.Foldable (for_, toList)
import Data.IORef (newIORef, readIORef, writeIORef)
import qualified Data.List as List
import qualified Codec.Archive.Zip as Zip
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Aeson.Key
import qualified Data.Aeson.KeyMap as Aeson.KeyMap
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as BS8
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Maybe as Maybe
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.IO as Text.IO
import Data.Time (diffUTCTime, getCurrentTime)
import qualified Data.Text.Encoding as Text.Encoding
import Network.HTTP.Client (defaultManagerSettings, newManager, httpLbs, parseRequest, requestBody, requestHeaders, method, Request, RequestBody (..), Response, responseStatus, responseBody, Manager)
import Network.HTTP.Types.Status (statusCode)
import Network.Wai.Handler.Warp (testWithApplication)
import System.FilePath (takeDirectory, (</>))
import System.Directory (createDirectoryIfMissing, doesFileExist, removePathForcibly, withCurrentDirectory)
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.IO (Handle, IOMode (..), hClose, openFile, withFile)
import System.IO.Temp (createTempDirectory, getCanonicalTemporaryDirectory)
import System.IO.Error (isPermissionError)
import System.Timeout (timeout)
import TestData (maybeSynonymJL4, synonymWrapperJL4)

import TestData (qualifiesJL4, recordJL4, maybeParamJL4, saleContractJL4, deonticExportJL4, deonticDeadlineJL4, deonticShapesJL4, deonticLineBreakJL4, deonticRecordPartyJL4, spacedFieldsJL4, assumeParamJL4, assumeHelperJL4, refuseJL4, importedRecordDeclJL4, importedRecordMainJL4, dnfBlowupJL4, considerPlanJL4, twinLeavesJL4, missingBooleanJL4, sectionBooleanJL4, deonticBooleanJL4, considerBooleanJL4, decidedAnywayJL4, deonticConsiderJL4, maybeInputsJL4, timeInputsJL4, ruleDefaultJL4, recordDefaultJL4, maybeHardJL4, sectionSecondJL4, twoDefaultsJL4, refuseDefaultJL4, exactDecimalJL4, enumSchemaJL4, wrapperNullJL4, enumNullJL4, recordWrapJL4, ownDecodeJL4, deonticDefaultJL4, spinJL4, spinOrRefuseJL4, spinWrapperJL4, powerJL4, heavyLibJL4, heavyMainJL4, deepJL4, wireProbeJL4, declineLabelsJL4, twoDatesJL4, bareInputJL4, refusingConditionJL4, refusingDeepJL4, refusingOrJL4, refusingFirstJL4, refusingArmJL4, answeredConditionJL4, refusingDistributedJL4, refusingNotJL4, refusingImpliesJL4, refusingImpliesNestedJL4, refusingSeamOpenJL4, refusingBothArmsJL4, conditionalRefuserJL4, clauseGroupSingleJL4, clauseGroupEnumJL4, handEnumJL4, clauseGroupMixedJL4, handMixedJL4, handSingleJL4, clauseGroupCallJL4, handCallJL4, clauseTableJL4, handTableJL4, clauseTable2JL4, handTable2JL4, clauseNewNameJL4, handNewNameJL4, clauseGroupNoGivethJL4, letEnumJL4, rowsClauseGroupJL4, letChainJL4, clauseGroupLetResultJL4, lineBreakJL4, partialClausesJL4, jsonDecodePersonJL4, taxpayerJL4, implicitFlagJL4, nameClashJL4, inputThenInputJL4, longClausesJL4, longNumberClausesJL4, catchAllHugeJL4, handCatchAllHugeJL4, newNameHugeJL4, newNameDnfJL4, maybeTableJL4, exactlyNameDnfJL4, exactlyHugeJL4, dnfClauseJL4, handDnfJL4)
import TestStoreDir (withStoreDir)

spec :: SpecWith ()
spec = describe "integration" do
  describe "data plane (direct compilation)" do
    it "evaluates a deployed function with all args true" do
      withServiceFromSources "eval-true" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "eval-true" "compute_qualifies"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "walks" Aeson..= True
                , "eats" Aeson..= True
                , "drinks" Aeson..= True
                ]
            ])
        assertSuccess resp \r ->
          Map.lookup "value" r.fnResult `shouldBe` Just (FnLitBool True)

    it "evaluates a deployed function with all args false" do
      withServiceFromSources "eval-false" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "eval-false" "compute_qualifies"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "walks" Aeson..= False
                , "eats" Aeson..= False
                , "drinks" Aeson..= False
                ]
            ])
        assertSuccess resp \r ->
          Map.lookup "value" r.fnResult `shouldBe` Just (FnLitBool False)

    -- REFUSE (R7): the model declined to answer. It must reach the caller as
    -- a refusal, NOT as an 'InterpreterError' — that reads as a server fault,
    -- and it is exactly the conflation REFUSE exists to prevent. The answering
    -- input in the twin test proves the refusal is the input's doing and not a
    -- broken deployment.
    it "reports a REFUSE as a refusal, not as an interpreter error" do
      withServiceFromSources "refuse-eval" [("fee.l4", refuseJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "refuse-eval" "fee"
          (Aeson.object [ "arguments" Aeson..= Aeson.object [ "y" Aeson..= (1999 :: Int) ] ])
        case Aeson.decode (responseBody resp) :: Maybe SimpleResponse of
          Just (SimpleError e@(EvaluatorRefused _ _)) ->
            prettyEvaluatorError e `shouldBe`
              "The model refuses to answer: this schedule is not encoded for years before 2000"
          other -> expectationFailure ("Expected a refusal error, got: " <> show other)
        -- And the distinction is MACHINE-readable on the wire, not merely
        -- legible in the prose: 'EvaluatorError''s derived encoding tags the
        -- constructor, so a consumer separates refused from error by reading
        -- contents.tag rather than by string-matching the message prefix.
        let constructorTag = case Aeson.decode (responseBody resp) :: Maybe Aeson.Value of
              Just (Aeson.Object o)
                | Just (Aeson.Object c) <- Aeson.KeyMap.lookup "contents" o ->
                    Aeson.KeyMap.lookup "tag" c
              _ -> Nothing
        constructorTag `shouldBe` Just (Aeson.String "EvaluatorRefused")

    it "answers normally for an input the same function does cover" do
      withServiceFromSources "refuse-eval-ok" [("fee.l4", refuseJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "refuse-eval-ok" "fee"
          (Aeson.object [ "arguments" Aeson..= Aeson.object [ "y" Aeson..= (2001 :: Int) ] ])
        assertSuccess resp \r ->
          Map.lookup "value" r.fnResult `shouldBe` Just (FnLitInt 100)

    it "promotes referenced ASSUMEs to parameters on @export (true case)" do
      -- Verifies the direct-AST path binds module-level ASSUMEs from the
      -- caller's input via a LET wrapper around the call.
      withServiceFromSources "assume-true" [("adult.l4", assumeParamJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "assume-true" "is_adult"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "threshold" Aeson..= (18 :: Int)
                , "age" Aeson..= (25 :: Int)
                ]
            ])
        assertSuccess resp \r ->
          Map.lookup "value" r.fnResult `shouldBe` Just (FnLitBool True)

    it "promotes referenced ASSUMEs to parameters on @export (false case)" do
      withServiceFromSources "assume-false" [("adult.l4", assumeParamJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "assume-false" "is_adult"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "threshold" Aeson..= (18 :: Int)
                , "age" Aeson..= (15 :: Int)
                ]
            ])
        assertSuccess resp \r ->
          Map.lookup "value" r.fnResult `shouldBe` Just (FnLitBool False)

    -- The read-set is transitive: an ASSUME read only by a helper the
    -- export calls is bound for the helper too. Before, the value was
    -- bound with a LET around the inlined export body, which the helper's
    -- closure never saw, so evaluation got stuck on "an assumed term".
    it "binds an ASSUME read only by a helper of the @export (true case)" do
      withServiceFromSources "assume-helper-true" [("drive.l4", assumeHelperJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "assume-helper-true" "may_drive"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "licensed" Aeson..= True
                , "age" Aeson..= (25 :: Int)
                ]
            ])
        assertSuccess resp \r ->
          Map.lookup "value" r.fnResult `shouldBe` Just (FnLitBool True)

    it "binds an ASSUME read only by a helper of the @export (false case)" do
      withServiceFromSources "assume-helper-false" [("drive.l4", assumeHelperJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "assume-helper-false" "may_drive"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "licensed" Aeson..= True
                , "age" Aeson..= (15 :: Int)
                ]
            ])
        assertSuccess resp \r ->
          Map.lookup "value" r.fnResult `shouldBe` Just (FnLitBool False)

    it "lists a helper-read ASSUME as a required parameter in the schema" do
      withServiceFromSources "assume-helper-schema" [("drive.l4", assumeHelperJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/deployments?functions=full")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        let body = Aeson.decode @Aeson.Value (responseBody resp)
        case body of
          Just (Aeson.Array deployments) -> do
            let findRequired = do
                  Aeson.Object deploy <- toList deployments
                  Aeson.Object meta <- toList $ Aeson.KeyMap.lookup "metadata" deploy
                  Aeson.Array fns <- toList $ Aeson.KeyMap.lookup "functions" meta
                  Aeson.Object fn <- toList fns
                  guard (Aeson.KeyMap.lookup "name" fn == Just (Aeson.String "may_drive"))
                  Aeson.Object params <- toList $ Aeson.KeyMap.lookup "parameters" fn
                  Aeson.Array reqArr <- toList $ Aeson.KeyMap.lookup "required" params
                  pure [t | Aeson.String t <- toList reqArr]
            case findRequired of
              (reqList:_) -> reqList `shouldBe` ["licensed", "age"]
              [] -> expectationFailure "Could not find may_drive function in deployment response"
          other -> expectationFailure ("Expected JSON array of deployments, got: " <> show other)

    it "lists functions for a deployment" do
      withServiceFromSources "list-fns" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/deployments/list-fns/functions")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200

    it "returns 404 for unknown deployment" do
      withServiceFromSources "exists" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/deployments/nonexistent/functions")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 404

    it "returns 404 for unknown function" do
      withServiceFromSources "exists2" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/deployments/exists2/functions/no_such_fn")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 404

  describe "record output with named fields" do
    it "returns record fields as named object keys" do
      withServiceFromSources "record-named" [("record.l4", recordJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "record-named" "make_person"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "n" Aeson..= ("Alice" :: Text)
                , "a" Aeson..= (30 :: Int)
                ]
            ])
        assertSuccess resp \r -> do
          let mValue = Map.lookup "value" r.fnResult
          case mValue of
            Just (FnObject [(conName, FnObject fields)]) -> do
              conName `shouldBe` "Person"
              let fieldMap = Map.fromList fields
              Map.lookup "name" fieldMap `shouldBe` Just (FnLitString "Alice")
              Map.lookup "age" fieldMap `shouldBe` Just (FnLitInt 30)
            other ->
              expectationFailure ("Expected FnObject with named fields, got: " <> show other)

  describe "record parameter declared in an imported file" do
    -- Regression: before the fix, the direct-AST fast path's
    -- `buildModuleInfo` only walked the entry module's own
    -- `flattenDeclares`, so a DECLARE that lived in an IMPORTed file
    -- wasn't in `miRecords`. `lookupRecord` missed → evaluation bailed
    -- with "FnObject but expected type is not a known record" for any
    -- rule whose parameter was a cross-file record. The ASEAN Cosmetic
    -- Directive deployment surfaced this in production. This test
    -- pins the behaviour so we can't regress again.
    it "resolves the record type across IMPORT boundaries" do
      withServiceFromSources
        "imported-record"
        [ ("imported_record_decl.l4", importedRecordDeclJL4)
        , ("imported_record_main.l4", importedRecordMainJL4)
        ] \baseUrl mgr -> do
          resp <- evalFunction baseUrl mgr "imported-record" "applicant-is-an-adult"
            (Aeson.object
              [ "arguments" Aeson..= Aeson.object
                  [ "applicant" Aeson..= Aeson.object
                      [ "name" Aeson..= ("Alice" :: Text)
                      , "age" Aeson..= (30 :: Int)
                      ]
                  ]
              ])
          assertSuccess resp \r ->
            Map.lookup "value" r.fnResult `shouldBe` Just (FnLitBool True)

  describe "MAYBE parameter handling" do
    it "handles NOTHING (null) for a MAYBE parameter" do
      withServiceFromSources "maybe-null" [("maybe.l4", maybeParamJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "maybe-null" "with_maybe"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "label" Aeson..= ("test" :: Text)
                , "extra" Aeson..= Aeson.Null
                ]
            ])
        assertSuccess resp \r -> do
          let mValue = Map.lookup "value" r.fnResult
          case mValue of
            Just (FnObject [(conName, FnObject fields)]) -> do
              conName `shouldBe` "Result"
              let fieldMap = Map.fromList fields
              Map.lookup "label" fieldMap `shouldBe` Just (FnLitString "test")
              Map.lookup "extra_provided" fieldMap `shouldBe` Just (FnLitBool False)
            other ->
              expectationFailure ("Expected FnObject with named fields, got: " <> show other)

    it "handles JUST (non-null) for a MAYBE parameter" do
      withServiceFromSources "maybe-just" [("maybe.l4", maybeParamJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "maybe-just" "with_maybe"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "label" Aeson..= ("test" :: Text)
                , "extra" Aeson..= ("hello" :: Text)
                ]
            ])
        assertSuccess resp \r -> do
          let mValue = Map.lookup "value" r.fnResult
          case mValue of
            Just (FnObject [(conName, FnObject fields)]) -> do
              conName `shouldBe` "Result"
              let fieldMap = Map.fromList fields
              Map.lookup "label" fieldMap `shouldBe` Just (FnLitString "test")
              Map.lookup "extra_provided" fieldMap `shouldBe` Just (FnLitBool True)
            other ->
              expectationFailure ("Expected FnObject with named fields, got: " <> show other)

    it "handles omitted MAYBE parameter (not present in JSON)" do
      withServiceFromSources "maybe-omit" [("maybe.l4", maybeParamJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "maybe-omit" "with_maybe"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "label" Aeson..= ("test" :: Text)
                -- "extra" is intentionally omitted
                ]
            ])
        assertSuccess resp \r -> do
          let mValue = Map.lookup "value" r.fnResult
          case mValue of
            Just (FnObject [(conName, FnObject fields)]) -> do
              conName `shouldBe` "Result"
              let fieldMap = Map.fromList fields
              Map.lookup "label" fieldMap `shouldBe` Just (FnLitString "test")
              Map.lookup "extra_provided" fieldMap `shouldBe` Just (FnLitBool False)
            other ->
              expectationFailure ("Expected FnObject with named fields, got: " <> show other)

    -- Three kinds of request go through the generated wrapper and not the direct
    -- path: an input whose value is `{}`, a batch case with a `null`, and an MCP
    -- call with a `null`. The wrapper's own test for a MAYBE (`isMaybeType`)
    -- does not expand a synonym; what keeps that from mattering is that
    -- `wrapperPlan` decodes such an input as its own type. These pin the
    -- answers, with `plain maybe` as the control, so that a change to either
    -- cannot turn a null for a synonym for a MAYBE into "missing required
    -- parameter".
    describe "a synonym for a MAYBE, on the wrapper path" do
      let deployId = "maybe-synonym-wrapper"
          withSynonyms = withServiceFromSources deployId [("synonym.l4", maybeSynonymJL4)]
          pathOf fn = Text.unpack (Text.replace " " "%20" fn)
      forM_ ["year maybe", "optional number", "plain maybe" :: Text] \fn -> describe (Text.unpack fn) do
        it "answers a {} value as NOTHING" do
          withSynonyms \baseUrl mgr -> do
            resp <- evalFunction baseUrl mgr deployId fn
              (Aeson.object [ "arguments" Aeson..= Aeson.object [ "y" Aeson..= Aeson.object [] ] ])
            let value = case Aeson.decode (responseBody resp) of
                  Just (SimpleResponse r) -> Map.lookup "value" r.fnResult
                  _ -> Nothing
            (statusCode' resp, value) `shouldBe` (200, Just (FnLitInt 0))
        it "answers a null, a {} and a left-out input in a batch case as NOTHING" do
          withSynonyms \baseUrl mgr -> do
            req <- buildJsonPost (baseUrl <> "/deployments/" <> Text.unpack deployId <> "/functions/" <> pathOf fn <> "/evaluation/batch")
              (Aeson.object
                [ "outcomes" Aeson..= ([] :: [Text])
                , "cases" Aeson..=
                    [ Aeson.object [ "@id" Aeson..= (1 :: Int), "y" Aeson..= (2020 :: Int) ]
                    , Aeson.object [ "@id" Aeson..= (2 :: Int), "y" Aeson..= Aeson.Null ]
                    , Aeson.object [ "@id" Aeson..= (3 :: Int) ]
                    , Aeson.object [ "@id" Aeson..= (4 :: Int), "y" Aeson..= Aeson.object [] ]
                    ]
                ])
            resp <- httpLbs req mgr
            statusCode' resp `shouldBe` 200
            fmap (map (\c -> (c.outcome, Map.lookup "value" c.attributes)) . (.cases))
                (Aeson.decode (responseBody resp) :: Maybe BatchResponse)
              `shouldBe` Just [ (CaseAnswered, Just (FnLitInt 2021))
                              , (CaseAnswered, Just (FnLitInt 0))
                              , (CaseAnswered, Just (FnLitInt 0))
                              , (CaseAnswered, Just (FnLitInt 0)) ]
        it "answers a null, a {} and a left-out input in an MCP tool call as NOTHING" do
          withSynonyms \baseUrl mgr ->
            forM_ ([ ("2020", Aeson.object [ "y" Aeson..= (2020 :: Int) ], "2021")
                   , ("null", Aeson.object [ "y" Aeson..= Aeson.Null ], "0")
                   , ("{}", Aeson.object [ "y" Aeson..= Aeson.object [] ], "0")
                   , ("left out", Aeson.object [], "0") ] :: [(Text, Aeson.Value, Text)]) \(what, args, expected) -> do
              req <- buildJsonPost (baseUrl <> "/deployments/" <> Text.unpack deployId <> "/.mcp") $ Aeson.object
                [ "jsonrpc" Aeson..= ("2.0" :: Text)
                , "id" Aeson..= (1 :: Int)
                , "method" Aeson..= ("tools/call" :: Text)
                , "params" Aeson..= Aeson.object
                    [ "name" Aeson..= Text.replace " " "-" fn
                    , "arguments" Aeson..= args
                    ]
                ]
              resp <- httpLbs req mgr
              let answered = case mcpToolText (responseBody resp) of
                    Just (isErr, text) -> Just (isErr, ("\"value\":" <> expected) `Text.isInfixOf` text)
                    Nothing -> Nothing
              (what, statusCode' resp, answered) `shouldBe` (what, 200, Just (False, True))

    -- Every other synonym is answered on the wrapper path too. `wrapperPlan`
    -- decodes an input that is not a MAYBE, a BOOLEAN or a DATE, TIME or DATETIME
    -- as its own type, and the JSON decoder expands a synonym, so a synonym for a
    -- record, an enum, a LIST, a DATE, a TIME or a DATETIME is read as the type it
    -- stands for, and a synonym below the head (`MAYBE Hue`) is too. These pin the
    -- answers. Each request has a spare MAYBE input, pad, that is @null@ or @{}@,
    -- which sends it through the wrapper. `plain point x` and `plain deadline
    -- year` write a record and a DATE out: the control.
    describe "a synonym at the head of an input's type, on the wrapper path" do
      let deployId = "wrapper-synonym"
          withSynonyms = withServiceFromSources deployId [("synonym.l4", synonymWrapperJL4)]
          pathOf fn = Text.unpack (Text.replace " " "%20" fn)
          recordInput = ("p" :: Aeson.Key.Key, Aeson.object [ "x" Aeson..= (7 :: Int) ])
          enumInput = ("h" :: Aeson.Key.Key, Aeson.String "Green")
          dateInput = ("d" :: Aeson.Key.Key, Aeson.String "2020-06-15")
          listInput = ("ys" :: Aeson.Key.Key, Aeson.toJSON [7, 8 :: Int])
          timeInput = ("t" :: Aeson.Key.Key, Aeson.String "12:30:00")
          datetimeInput = ("dt" :: Aeson.Key.Key, Aeson.String "2020-06-15T12:30:00Z")
      forM_ ([ ("point x", recordInput, 7), ("plain point x", recordInput, 7)
             , ("hue code", enumInput, 2)
             , ("deadline year", dateInput, 2020), ("plain deadline year", dateInput, 2020)
             , ("first year", listInput, 7)
             , ("clock code", timeInput, 5)
             , ("stamp code", datetimeInput, 6) ]
              :: [(Text, (Aeson.Key.Key, Aeson.Value), Int)]) \(fn, (name, input), expected) -> describe (Text.unpack fn) do
        it "answers a {} for the spare input" do
          withSynonyms \baseUrl mgr -> do
            resp <- evalFunction baseUrl mgr deployId fn
              (Aeson.object [ "arguments" Aeson..= Aeson.object [ name Aeson..= input, "pad" Aeson..= Aeson.object [] ] ])
            let value = case Aeson.decode (responseBody resp) of
                  Just (SimpleResponse r) -> Map.lookup "value" r.fnResult
                  _ -> Nothing
            (statusCode' resp, value) `shouldBe` (200, Just (FnLitInt (fromIntegral expected)))
        it "answers a batch case with a null for the spare input" do
          withSynonyms \baseUrl mgr -> do
            req <- buildJsonPost (baseUrl <> "/deployments/" <> Text.unpack deployId <> "/functions/" <> pathOf fn <> "/evaluation/batch")
              (Aeson.object
                [ "outcomes" Aeson..= ([] :: [Text])
                , "cases" Aeson..=
                    [ Aeson.object [ "@id" Aeson..= (1 :: Int), name Aeson..= input, "pad" Aeson..= Aeson.Null ]
                    , Aeson.object [ "@id" Aeson..= (2 :: Int), name Aeson..= input, "pad" Aeson..= (1 :: Int) ]
                    ]
                ])
            resp <- httpLbs req mgr
            statusCode' resp `shouldBe` 200
            fmap (map (\c -> (c.outcome, Map.lookup "value" c.attributes)) . (.cases))
                (Aeson.decode (responseBody resp) :: Maybe BatchResponse)
              `shouldBe` Just (replicate 2 (CaseAnswered, Just (FnLitInt (fromIntegral expected))))
        it "answers an MCP tool call with a null for the spare input" do
          withSynonyms \baseUrl mgr -> do
            req <- buildJsonPost (baseUrl <> "/deployments/" <> Text.unpack deployId <> "/.mcp") $ Aeson.object
              [ "jsonrpc" Aeson..= ("2.0" :: Text)
              , "id" Aeson..= (1 :: Int)
              , "method" Aeson..= ("tools/call" :: Text)
              , "params" Aeson..= Aeson.object
                  [ "name" Aeson..= Text.replace " " "-" fn
                  , "arguments" Aeson..= Aeson.object [ name Aeson..= input, "pad" Aeson..= Aeson.Null ]
                  ]
              ]
            resp <- httpLbs req mgr
            let answered = case mcpToolText (responseBody resp) of
                  Just (isErr, text) -> Just (isErr, ("\"value\":" <> Text.pack (show expected)) `Text.isInfixOf` text)
                  Nothing -> Nothing
            (statusCode' resp, answered) `shouldBe` (200, Just (False, True))

    -- A synonym for a BOOLEAN is answered when the host has no copy of the
    -- standard library in the places this example controls: the bundle's import
    -- of the standard library is served from the one built into the service
    -- (StdlibResolutionSpec), and CI exports JL4_LIBRARY_PATH for the whole run,
    -- which would hide a wrapper that needed the host's. Around its call this
    -- example drops JL4_LIBRARY_PATH and puts XDG_DATA_HOME and the working
    -- directory in an empty directory; the path beside the executable, which the
    -- service also searches, it does not touch.
    it "answers a synonym for a BOOLEAN when the host has no library to import" do
      withNoLibraryOnTheHost $
        withServiceFromSources "wrapper-synonym-bool" [("synonym.l4", synonymWrapperJL4)] \baseUrl mgr -> do
          resp <- evalFunction baseUrl mgr "wrapper-synonym-bool" "flag code"
            (Aeson.object [ "arguments" Aeson..= Aeson.object [ "b" Aeson..= True, "pad" Aeson..= Aeson.object [] ] ])
          let value = case Aeson.decode (responseBody resp) of
                Just (SimpleResponse r) -> Map.lookup "value" r.fnResult
                _ -> Nothing
          (statusCode' resp, value) `shouldBe` (200, Just (FnLitInt 1))

    -- A synonym below the head of an input's type: `h IS A MAYBE Hue`, the last
    -- input, with a null inside a record to take the wrapper path.
    describe "a synonym below the head of an input's type, on the wrapper path" do
      let deployId = "wrapper-synonym-nested"
      forM_ [("nested hue", "a MAYBE of a synonym for an enum"), ("nested colour plain", "the enum written out, the control")] \(fn, what) ->
        it (Text.unpack fn <> ": " <> what <> " answers with a null inside a record") do
          withServiceFromSources deployId [("synonym.l4", synonymWrapperJL4)] \baseUrl mgr -> do
            resp <- evalFunction baseUrl mgr deployId fn
              (Aeson.object [ "arguments" Aeson..= Aeson.object
                  [ "r" Aeson..= Aeson.object [ "f" Aeson..= Aeson.Null ], "h" Aeson..= ("Green" :: Text) ] ])
            let value = case Aeson.decode (responseBody resp) of
                  Just (SimpleResponse r) -> Map.lookup "value" r.fnResult
                  _ -> Nothing
            (statusCode' resp, value) `shouldBe` (200, Just (FnLitInt 2))

    it "MAYBE parameter is not in the required list of the schema" do
      withServiceFromSources "maybe-schema" [("maybe.l4", maybeParamJL4)] \baseUrl mgr -> do
        -- GET /deployments?functions=full returns deployment with function schemas
        req <- parseRequest (baseUrl <> "/deployments?functions=full")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        let body = Aeson.decode @Aeson.Value (responseBody resp)
        case body of
          Just (Aeson.Array deployments) -> do
            -- Find the with_maybe function's parameters.required list
            -- Response structure: [{metadata: {functions: [{name, parameters: {required: [...]}}]}}]
            let findRequired = do
                  Aeson.Object deploy <- toList deployments
                  Aeson.Object meta <- toList $ Aeson.KeyMap.lookup "metadata" deploy
                  Aeson.Array fns <- toList $ Aeson.KeyMap.lookup "functions" meta
                  Aeson.Object fn <- toList fns
                  guard (Aeson.KeyMap.lookup "name" fn == Just (Aeson.String "with_maybe"))
                  Aeson.Object params <- toList $ Aeson.KeyMap.lookup "parameters" fn
                  Aeson.Array reqArr <- toList $ Aeson.KeyMap.lookup "required" params
                  pure [t | Aeson.String t <- toList reqArr]
            case findRequired of
              (reqList:_) -> do
                reqList `shouldContain` ["label"]
                reqList `shouldNotContain` ["extra"]
              [] -> expectationFailure "Could not find with_maybe function in deployment response"
          other -> expectationFailure ("Expected JSON array of deployments, got: " <> show other)

    -- A MAYBE input followed by another input, on the wrapper path. The wrapper
    -- wrote its input record with a leading comma on each field after the first,
    -- which does not parse after a field whose type is an application
    -- (`MAYBE OF NUMBER`), so a function with such an input before another input
    -- failed with a parser error on every request that takes the wrapper: a `{}`
    -- value, a batch case or an MCP call with a `null`, and every request to a
    -- DEONTIC function. `syn then number` and `syn then maybe` take a synonym for
    -- a MAYBE first, `plain maybe then number` a MAYBE NUMBER written out first,
    -- and `number then syn` takes the synonym last: the control.
    describe "a MAYBE input followed by another input, on the wrapper path" do
      let deployId = "wrapper-then-input"
          withFns = withServiceFromSources deployId [("then-input.l4", inputThenInputJL4)]
          valueOf resp = case Aeson.decode (responseBody resp) of
            Just (SimpleResponse r) -> Map.lookup "value" r.fnResult
            _ -> Nothing
      forM_ ["syn then number", "syn then maybe", "plain maybe then number", "number then syn" :: Text] \fn -> describe (Text.unpack fn) do
        it "answers a {} for the MAYBE input" do
          withFns \baseUrl mgr -> do
            resp <- evalFunction baseUrl mgr deployId fn
              (Aeson.object [ "arguments" Aeson..= Aeson.object [ "y" Aeson..= Aeson.object [], "z" Aeson..= (3 :: Int) ] ])
            (statusCode' resp, valueOf resp) `shouldBe` (200, Just (FnLitInt 3))
        it "answers a batch case with a null for the MAYBE input" do
          withFns \baseUrl mgr -> do
            req <- buildJsonPost (baseUrl <> "/deployments/" <> Text.unpack deployId <> "/functions/" <> Text.unpack (Text.replace " " "%20" fn) <> "/evaluation/batch")
              (Aeson.object
                [ "outcomes" Aeson..= ([] :: [Text])
                , "cases" Aeson..=
                    [ Aeson.object [ "@id" Aeson..= (1 :: Int), "y" Aeson..= Aeson.Null, "z" Aeson..= (3 :: Int) ]
                    , Aeson.object [ "@id" Aeson..= (2 :: Int), "y" Aeson..= (2020 :: Int), "z" Aeson..= (3 :: Int) ]
                    ]
                ])
            resp <- httpLbs req mgr
            statusCode' resp `shouldBe` 200
            fmap (map (\c -> (c.outcome, Map.lookup "value" c.attributes)) . (.cases))
                (Aeson.decode (responseBody resp) :: Maybe BatchResponse)
              `shouldBe` Just [ (CaseAnswered, Just (FnLitInt 3)), (CaseAnswered, Just (FnLitInt 2023)) ]
        it "answers an MCP tool call with a null for the MAYBE input" do
          withFns \baseUrl mgr -> do
            req <- buildJsonPost (baseUrl <> "/deployments/" <> Text.unpack deployId <> "/.mcp") $ Aeson.object
              [ "jsonrpc" Aeson..= ("2.0" :: Text)
              , "id" Aeson..= (1 :: Int)
              , "method" Aeson..= ("tools/call" :: Text)
              , "params" Aeson..= Aeson.object
                  [ "name" Aeson..= Text.replace " " "-" fn
                  , "arguments" Aeson..= Aeson.object [ "y" Aeson..= Aeson.Null, "z" Aeson..= (3 :: Int) ]
                  ]
              ]
            resp <- httpLbs req mgr
            let answered = case mcpToolText (responseBody resp) of
                  Just (isErr, text) -> Just (isErr, "\"value\":3" `Text.isInfixOf` text)
                  Nothing -> Nothing
            (statusCode' resp, answered) `shouldBe` (200, Just (False, True))
      forM_ ["syn contract", "plain contract", "control contract" :: Text] \fn -> describe (Text.unpack fn) do
        forM_ [("a value", Aeson.Number 2020), ("a null", Aeson.Null)] \(what, y) ->
          it ("answers " <> what <> " for the MAYBE input of a DEONTIC function") do
            withFns \baseUrl mgr -> do
              resp <- evalFunction baseUrl mgr deployId fn
                (Aeson.object
                  [ "arguments" Aeson..= Aeson.object [ "y" Aeson..= y, "z" Aeson..= (3 :: Int) ]
                  , "startTime" Aeson..= (0 :: Int)
                  , "events" Aeson..= ([] :: [Aeson.Value])
                  ])
              assertSuccess resp \r -> case Map.lookup "value" r.fnResult of
                Just (FnObject [("OBLIGATION", FnObject fields)]) ->
                  Map.lookup "modal" (Map.fromList fields) `shouldBe` Just (FnLitString "MUST")
                other -> expectationFailure ("Expected OBLIGATION, got: " <> show other)

  describe "missing BOOLEAN on the wrapper path (smucclaw/l4-ide#992)" do
    -- A {} anywhere in a request sends it through the generated wrapper,
    -- which read every missing BOOLEAN as FALSE.
    let uncertain = Aeson.object []

    it "stops and names a missing BOOLEAN that the rule reads" do
      withServiceFromSources "w1-read" [("eligible.l4", missingBooleanJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "w1-read" "eligible"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "is resident" Aeson..= True
                , "unused flag" Aeson..= uncertain
                ]
            ])
        assertNotSupplied resp "has criminal record"

    it "short-circuits past a missing BOOLEAN that the rule does not read" do
      withServiceFromSources "w1-skip" [("eligible.l4", missingBooleanJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "w1-skip" "eligible"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "is resident" Aeson..= False
                , "unused flag" Aeson..= uncertain
                ]
            ])
        assertSuccess resp \r ->
          Map.lookup "value" r.fnResult `shouldBe` Just (FnLitBool False)

    it "uses a BOOLEAN that is supplied" do
      withServiceFromSources "w1-given" [("eligible.l4", missingBooleanJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "w1-given" "eligible"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "is resident" Aeson..= True
                , "has criminal record" Aeson..= False
                , "unused flag" Aeson..= uncertain
                ]
            ])
        assertSuccess resp \r ->
          Map.lookup "value" r.fnResult `shouldBe` Just (FnLitBool True)

    it "names a section GIVEN BOOLEAN sent as {}, and takes no default for it" do
      withServiceFromSources "w1-section" [("capacity.l4", sectionBooleanJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "w1-section" "may contract"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "has capacity" Aeson..= uncertain
                , "is adult" Aeson..= True
                ]
            ])
        assertNotSupplied resp "has capacity"

    it "stops a deontic rule instead of taking its ELSE branch" do
      withServiceFromSources "w1-deontic" [("seatbelt.l4", deonticBooleanJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "w1-deontic" "seatbelt requirement"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "driver" Aeson..= Aeson.object ["name" Aeson..= ("Alice" :: Text)] ]
            , "startTime" Aeson..= (0 :: Int)
            , "events" Aeson..= ([] :: [Aeson.Value])
            ])
        assertNotSupplied resp "is motorway"

    it "stops and names a missing BOOLEAN read by CONSIDER, not taking its OTHERWISE" do
      withServiceFromSources "w1-consider" [("fee.l4", considerBooleanJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "w1-consider" "fee"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "amount" Aeson..= (10 :: Int)
                , "unused flag" Aeson..= uncertain
                ]
            ])
        assertNotSupplied resp "is member"

    it "answers when a missing BOOLEAN the rule reads cannot change the answer" do
      withServiceFromSources "w1-anyway" [("eligible.l4", decidedAnywayJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "w1-anyway" "eligible"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "unused flag" Aeson..= uncertain ]
            ])
        assertSuccess resp \r ->
          Map.lookup "value" r.fnResult `shouldBe` Just (FnLitBool True)

    it "uses a BOOLEAN read by CONSIDER when it is supplied" do
      withServiceFromSources "w1-consider-given" [("fee.l4", considerBooleanJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "w1-consider-given" "fee"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "amount" Aeson..= (10 :: Int)
                , "is member" Aeson..= False
                , "unused flag" Aeson..= uncertain
                ]
            ])
        assertSuccess resp \r ->
          Map.lookup "value" r.fnResult `shouldBe` Just (FnLitInt 10)

    it "stops a deontic rule instead of taking its OTHERWISE" do
      withServiceFromSources "w1-deontic-consider" [("seatbelt.l4", deonticConsiderJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "w1-deontic-consider" "seatbelt requirement"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "driver" Aeson..= Aeson.object ["name" Aeson..= ("Alice" :: Text)] ]
            , "startTime" Aeson..= (0 :: Int)
            , "events" Aeson..= ([] :: [Aeson.Value])
            ])
        assertNotSupplied resp "is motorway"

    it "delivers a supplied section GIVEN, not its default" do
      withServiceFromSources "w1-binder" [("capacity.l4", sectionBooleanJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "w1-binder" "may contract"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "has capacity" Aeson..= False
                , "is adult" Aeson..= True
                , "unused flag" Aeson..= uncertain
                ]
            ])
        assertSuccess resp \r ->
          Map.lookup "value" r.fnResult `shouldBe` Just (FnLitBool False)

  describe "MAYBE inputs on the wrapper path" do
    -- A {} on an unread input sends the request through the generated wrapper.
    let uncertain = Aeson.object []

    it "decodes a MAYBE DATE and a MAYBE NUMBER that are followed by other inputs" do
      withServiceFromSources "maybe-of-just" [("dated.l4", maybeInputsJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "maybe-of-just" "dated"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "start date" Aeson..= ("2020-01-01" :: Text)
                , "count" Aeson..= (3 :: Int)
                , "flag" Aeson..= True
                , "unused" Aeson..= uncertain
                ]
            ])
        assertSuccess resp \r ->
          Map.lookup "value" r.fnResult `shouldBe` Just (FnLitBool True)

    it "parses a TIME and a DATETIME input" do
      withServiceFromSources "time-inputs" [("timed.l4", timeInputsJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "time-inputs" "timed"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "flag" Aeson..= True
                , "unused" Aeson..= uncertain
                , "t" Aeson..= ("10:00:00" :: Text)
                , "dt" Aeson..= ("2020-01-01T10:00:00Z" :: Text)
                ]
            ])
        assertSuccess resp \r ->
          Map.lookup "value" r.fnResult `shouldBe` Just (FnLitBool True)

    it "reads an absent MAYBE DATE as NOTHING" do
      withServiceFromSources "maybe-of-nothing" [("dated.l4", maybeInputsJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "maybe-of-nothing" "dated"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "count" Aeson..= (3 :: Int)
                , "flag" Aeson..= True
                , "unused" Aeson..= uncertain
                ]
            ])
        assertSuccess resp \r ->
          Map.lookup "value" r.fnResult `shouldBe` Just (FnLitBool False)

  describe "answers on the direct and wrapper paths (smucclaw/l4-ide#1003)" do
    -- The wrapper answers JUST (f args). Its JUST used to be dissolved with
    -- every other JUST before anything looked at it, so a NOTHING answer came
    -- back as an error and a one-element list as its element.
    aroundAll (\k -> withServiceFromSources "wire" [("probe.l4", wireProbeJL4)] (curry k)) do
      forM_ wireCases \(caseId, fn, args, expected) ->
        it (Text.unpack (caseId <> " " <> fn <> " " <> Text.Encoding.decodeUtf8 (LBS.toStrict (Aeson.encode args)))) \(baseUrl, mgr) -> do
          resp <- evalFunction baseUrl mgr "wire" (Text.replace " " "%20" fn) (Aeson.object ["arguments" Aeson..= args])
          resp `shouldCarry` expected

      -- Under trace=full the wrapper's directive is #EVALTRACE rather than #EVAL.
      it "trace=full, wrapper path: cap and single" \(baseUrl, mgr) -> do
        let traced fn = do
              req <- buildJsonPost (baseUrl <> "/deployments/wire/functions/" <> fn <> "/evaluation?trace=full")
                (Aeson.object ["arguments" Aeson..= Aeson.object ["n" Aeson..= (5 :: Int), "pad" Aeson..= Aeson.object []]])
              httpLbs req mgr
        cap <- traced "cap"
        cap `shouldCarry` Answers Aeson.Null
        wireAt cap ["contents", "reasoning"] `shouldSatisfy` \case
          Right (Aeson.Object o) -> not (Aeson.KeyMap.null o)
          _ -> False
        single <- traced "single"
        single `shouldCarry` Answers (Aeson.toJSON [5 :: Int])

      -- A batch case's null is an unknown value, not a missing one, so it takes
      -- the wrapper; and batch drops a case that errors, still answering 200.
      it "batch, where null takes the wrapper: cap and single" \(baseUrl, mgr) -> do
        let batch fn cases = do
              req <- buildJsonPost (baseUrl <> "/deployments/wire/functions/" <> fn <> "/evaluation/batch")
                (Aeson.object ["outcomes" Aeson..= ([] :: [Text]), "cases" Aeson..= cases])
              httpLbs req mgr
            input :: Int -> Int -> Aeson.Value
            input caseId v = Aeson.object ["@id" Aeson..= caseId, "n" Aeson..= v, "pad" Aeson..= Aeson.Null]
            answers resp = do
              Aeson.Array cs <- either (const Nothing) Just (wireAt resp ["cases"])
              Aeson.Number ignored <- either (const Nothing) Just (wireAt resp ["summary", "casesIgnored"])
              pure ([ Aeson.KeyMap.lookup "value" c | Aeson.Object c <- toList cs ], ignored)
        cap <- batch "cap" [input 1 5, input 2 15]
        answers cap `shouldBe` Just ([Just Aeson.Null, Just (Aeson.Number 15)], 0)
        single <- batch "single" [input 1 5]
        answers single `shouldBe` Just ([Just (Aeson.toJSON [5 :: Int])], 0)

    describe "when the wrapper cannot call the function" do
      it "quotes a TIME it could not read, and names a missing one" do
        withServiceFromSources "decline-time" [("timed.l4", timeInputsJL4)] \baseUrl mgr -> do
          let call t = evalFunction baseUrl mgr "decline-time" "timed" $ Aeson.object
                [ "arguments" Aeson..= Aeson.object
                    ([ "flag" Aeson..= True
                     , "unused" Aeson..= Aeson.object []
                     , "dt" Aeson..= ("2020-01-01T10:00:00Z" :: Text)
                     ] <> t)
                ]
          unread <- call ["t" Aeson..= ("not a time" :: Text)]
          unread `shouldCarry` Refuses "Parameter 't': could not read \"not a time\" as a TIME"
          missing <- call []
          missing `shouldCarry` Refuses "Parameter 't': missing required parameter"

      -- A NUMBER is decoded as its own type, so JSONDECODE refuses it by name
      -- before the wrapper could decline.
      it "names a missing ASSUME on both paths" do
        withServiceFromSources "decline-assume" [("drive.l4", assumeHelperJL4)] \baseUrl mgr -> do
          let call licensed = evalFunction baseUrl mgr "decline-assume" "may_drive" $
                Aeson.object ["arguments" Aeson..= Aeson.object ["licensed" Aeson..= licensed]]
          wrapped <- call (Aeson.object [])
          wrapped `shouldCarry` Refuses "Missing required field 'age' in JSON object"
          direct <- call (Aeson.Bool True)
          direct `shouldCarry` Refuses "ASSUME 'age': missing required parameter"

      it "names a missing input of a deontic rule" do
        withServiceFromSources "decline-deontic" [("seatbelt.l4", deonticRecordPartyJL4)] \baseUrl mgr -> do
          resp <- evalFunction baseUrl mgr "decline-deontic" "Seatbelt Requirement"
            (Aeson.object
              [ "arguments" Aeson..= Aeson.object
                  [ "car" Aeson..= Aeson.object ["number of wheels" Aeson..= (4 :: Int)] ]
              , "startTime" Aeson..= (0 :: Int)
              , "events" Aeson..= ([] :: [Aeson.Value])
              ])
          resp `shouldCarry` Refuses "Missing required field 'driver' in JSON object"

      -- A DATE is read from a string, so it is still unwrapped by the wrapper,
      -- which declines without calling the function. Only an ASSUME the author
      -- wrote is called one; a section GIVEN is a parameter.
      it "names the DATE TODATE could not read, not one it could" do
        withServiceFromSources "decline-dates" [("dates.l4", twoDatesJL4)] \baseUrl mgr -> do
          let call one two = evalFunction baseUrl mgr "decline-dates" "later" $ Aeson.object
                [ "arguments" Aeson..= Aeson.object
                    [ "d one" Aeson..= (one :: Text), "d two" Aeson..= (two :: Text), "pad" Aeson..= Aeson.object [] ] ]
          readable <- call "2026/01/31" "2026-02-28"
          readable `shouldCarry` Answers (Aeson.Number 1)
          declined <- call "2026/01/31" "2026-02-30"
          declined `shouldCarry` Refuses "Parameter 'd two': could not read \"2026-02-30\" as a DATE"

      it "labels a missing DATE as the direct path does" do
        withServiceFromSources "decline-labels" [("dated.l4", declineLabelsJL4)] \baseUrl mgr -> do
          let call path given = evalFunction baseUrl mgr "decline-labels" "dated" $ Aeson.object
                [ "arguments" Aeson..= Aeson.object
                    ([ "flag" Aeson..= True, "unused" Aeson..= path ] <> given) ]
              wrapper = Aeson.object []
              direct = Aeson.Bool False
          forM_ [wrapper, direct] \path -> do
            noStart <- call path ["end date" Aeson..= ("2026-01-31" :: Text)]
            noStart `shouldCarry` Refuses "ASSUME 'start date': missing required parameter"
            noEnd <- call path ["start date" Aeson..= ("2026-01-01" :: Text)]
            noEnd `shouldCarry` Refuses "Parameter 'end date': missing required parameter"

  describe "TYPICALLY defaults (W2, W3 of TYPICALLY-ONE-BEHAVIOUR-SPEC)" do
    let uncertain = Aeson.object []
        args kvs = Aeson.object ["arguments" Aeson..= Aeson.object kvs]
        hard kvs = Aeson.object ["arguments" Aeson..= Aeson.object kvs, "presumption" Aeson..= ("hard" :: Text)]
        expectAnswer resp v ps = assertSuccess resp \r ->
          (Map.lookup "value" r.fnResult, r.presumed) `shouldBe` (Just v, ps)
        expectError resp fragment =
          case Aeson.decode (responseBody resp) :: Maybe SimpleResponse of
            Just (SimpleError (InterpreterError msg)) -> msg `shouldSatisfy` Text.isInfixOf fragment
            other -> expectationFailure ("Expected an error containing " <> show fragment <> ", got: " <> show other)

    -- W2: the published schema is R8's surface: optional, with its default.
    it "publishes a section GIVEN's default and leaves it out of required (W2)" do
      withServiceFromSources "ty-schema" [("capacity.l4", sectionBooleanJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/deployments/ty-schema/functions/may%20contract")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        let body = decodeObject (responseBody resp)
            params = case lookupKey "parameters" body of
              Just (Aeson.Object o) -> o
              _ -> mempty
            required = case Aeson.KeyMap.lookup "required" params of
              Just (Aeson.Array xs) -> [t | Aeson.String t <- toList xs]
              _ -> []
            capacity = case Aeson.KeyMap.lookup "properties" params of
              Just (Aeson.Object props) -> Aeson.KeyMap.lookup "has capacity" props
              _ -> Nothing
        required `shouldNotContain` ["has capacity"]
        required `shouldContain` ["is adult"]
        (capacity >>= \case Aeson.Object c -> Aeson.KeyMap.lookup "default" c; _ -> Nothing)
          `shouldBe` Just (Aeson.Bool True)

    it "fills a left-out section GIVEN on the direct path and lists it in presumed" do
      withServiceFromSources "ty-sec-direct" [("capacity.l4", sectionBooleanJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "ty-sec-direct" "may contract"
          (args ["is adult" Aeson..= True, "unused flag" Aeson..= False])
        expectAnswer resp (FnLitBool True) ["has capacity"]

    -- The positive control for presumed: a default the rule never forces is
    -- not listed, although the request left it out just the same.
    it "does not list a rule GIVEN's default the rule never read" do
      withServiceFromSources "ty-rule-unread" [("capacity.l4", ruleDefaultJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "ty-rule-unread" "may contract"
          (args ["is adult" Aeson..= False, "unused flag" Aeson..= False])
        expectAnswer resp (FnLitBool False) []

    it "fills a left-out section GIVEN on the wrapper path too" do
      withServiceFromSources "ty-sec-wrap" [("capacity.l4", sectionBooleanJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "ty-sec-wrap" "may contract"
          (args ["is adult" Aeson..= True, "unused flag" Aeson..= uncertain])
        expectAnswer resp (FnLitBool True) ["has capacity"]

    it "fills a left-out rule GIVEN on the direct and the wrapper path" do
      withServiceFromSources "ty-rule" [("capacity.l4", ruleDefaultJL4)] \baseUrl mgr -> do
        direct <- evalFunction baseUrl mgr "ty-rule" "may contract"
          (args ["is adult" Aeson..= True, "unused flag" Aeson..= False])
        expectAnswer direct (FnLitBool True) ["has capacity"]
        wrapped <- evalFunction baseUrl mgr "ty-rule" "may contract"
          (args ["is adult" Aeson..= True, "unused flag" Aeson..= uncertain])
        expectAnswer wrapped (FnLitBool True) ["has capacity"]

    it "fills left-out record fields from their DECLARE, enum defaults included (T1b)" do
      withServiceFromSources "ty-record" [("budget.l4", recordDefaultJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "ty-record" "budget"
          (args ["cfg" Aeson..= Aeson.object ["retries" Aeson..= (2 :: Int)]])
        expectAnswer resp (FnLitInt 32) ["cfg.colour", "shade", "cfg.timeout"]

    it "lets a supplied value win, and presumes nothing" do
      withServiceFromSources "ty-supplied" [("capacity.l4", sectionBooleanJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "ty-supplied" "may contract"
          (args ["is adult" Aeson..= True, "unused flag" Aeson..= False, "has capacity" Aeson..= False])
        expectAnswer resp (FnLitBool False) []

    -- T3: null is "I don't know", never an omission.
    it "never takes a default for null" do
      withServiceFromSources "ty-null" [("capacity.l4", ruleDefaultJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "ty-null" "may contract"
          (args ["is adult" Aeson..= True, "unused flag" Aeson..= False, "has capacity" Aeson..= Aeson.Null])
        expectError resp "never takes the TYPICALLY default"

    -- T4: presumption hard withdraws the default; the refusal names the input
    -- and stays loud, on both paths.
    it "with presumption hard, refuses a left-out input on the direct path" do
      withServiceFromSources "ty-hard" [("capacity.l4", sectionBooleanJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "ty-hard" "may contract"
          (hard ["is adult" Aeson..= True, "unused flag" Aeson..= False])
        expectError resp "'has capacity': missing required parameter"

    it "with presumption hard, stops on a left-out input on the wrapper path" do
      withServiceFromSources "ty-hard-wrap" [("capacity.l4", ruleDefaultJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "ty-hard-wrap" "may contract"
          (hard ["is adult" Aeson..= True, "unused flag" Aeson..= uncertain])
        expectError resp "has capacity (not supplied)"

    -- T1b: presumption hard withdraws D7.3's MAYBE fallback too, the same way
    -- on both paths.
    it "with presumption hard, refuses a left-out MAYBE input on both paths" do
      withServiceFromSources "ty-maybe" [("premium.l4", maybeHardJL4)] \baseUrl mgr -> do
        -- NOTHING for a left-out MAYBE is a presumption, listed like a default
        soft <- evalFunction baseUrl mgr "ty-maybe" "premium due" (args ["unused flag" Aeson..= False])
        expectAnswer soft (FnLitInt 0) ["premium"]
        softWrapped <- evalFunction baseUrl mgr "ty-maybe" "premium due" (args ["unused flag" Aeson..= uncertain])
        expectAnswer softWrapped (FnLitInt 0) ["premium"]
        -- null is a value, not an omission: NOTHING, and nothing presumed
        nulled <- evalFunction baseUrl mgr "ty-maybe" "premium due" (args ["unused flag" Aeson..= False, "premium" Aeson..= Aeson.Null])
        expectAnswer nulled (FnLitInt 0) []
        direct <- evalFunction baseUrl mgr "ty-maybe" "premium due" (hard ["unused flag" Aeson..= False])
        expectError direct "a MAYBE left out is NOTHING only while presumption is soft"
        wrapped <- evalFunction baseUrl mgr "ty-maybe" "premium due" (hard ["unused flag" Aeson..= uncertain])
        -- the wrapper's own field name (`premium (input)`) does not leak (review m6)
        expectError wrapped "Missing required field 'premium'"

    -- T6: a section default counts when the rule first READS it, not when
    -- discharge binds it at the root. `FALSE AND <defaulted input>`.
    it "lists a section default only when the rule reads it, on both paths" do
      withServiceFromSources "ty-sec-read" [("capacity.l4", sectionSecondJL4)] \baseUrl mgr -> do
        unread <- evalFunction baseUrl mgr "ty-sec-read" "may contract"
          (args ["is adult" Aeson..= False, "unused flag" Aeson..= False])
        expectAnswer unread (FnLitBool False) []
        unreadWrapped <- evalFunction baseUrl mgr "ty-sec-read" "may contract"
          (args ["is adult" Aeson..= False, "unused flag" Aeson..= uncertain])
        expectAnswer unreadWrapped (FnLitBool False) []
        readWrapped <- evalFunction baseUrl mgr "ty-sec-read" "may contract"
          (args ["is adult" Aeson..= True, "unused flag" Aeson..= uncertain])
        expectAnswer readWrapped (FnLitBool True) ["has capacity"]

    -- T3's four cells, on the wrapper path: absent takes the default, null and
    -- {} do not. (The direct path's null is the "never takes a default for
    -- null" test above.)
    it "keeps null apart from absent on the wrapper path" do
      withServiceFromSources "ty-null-wrap" [("capacity.l4", ruleDefaultJL4)] \baseUrl mgr -> do
        absent <- evalFunction baseUrl mgr "ty-null-wrap" "may contract"
          (args ["is adult" Aeson..= True, "unused flag" Aeson..= uncertain])
        expectAnswer absent (FnLitBool True) ["has capacity"]
        nulled <- evalFunction baseUrl mgr "ty-null-wrap" "may contract"
          (args ["is adult" Aeson..= True, "unused flag" Aeson..= uncertain, "has capacity" Aeson..= Aeson.Null])
        expectError nulled "has capacity (not supplied)"
        uncertainCap <- evalFunction baseUrl mgr "ty-null-wrap" "may contract"
          (args ["is adult" Aeson..= True, "unused flag" Aeson..= False, "has capacity" Aeson..= uncertain])
        expectError uncertainCap "has capacity (not supplied)"

    it "keeps null apart from absent for a section GIVEN on the wrapper path" do
      withServiceFromSources "ty-null-sec" [("capacity.l4", sectionSecondJL4)] \baseUrl mgr -> do
        nulled <- evalFunction baseUrl mgr "ty-null-sec" "may contract"
          (args ["is adult" Aeson..= True, "unused flag" Aeson..= uncertain, "has capacity" Aeson..= Aeson.Null])
        expectError nulled "has capacity (not supplied)"

    it "with presumption hard, names every defaulted input left out" do
      withServiceFromSources "ty-hard-two" [("capacity.l4", twoDefaultsJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "ty-hard-two" "may contract" (hard ["is adult" Aeson..= True])
        expectError resp "Parameter 'of sound mind': missing required parameter"
        -- a section GIVEN is a parameter, not an ASSUME (review nit 22)
        expectError resp "Parameter 'has capacity': missing required parameter"

    -- Review M5: a refusal that rests on a default says so, on both
    -- endpoints, and a refused or errored case of the batch endpoint is
    -- returned with its reason instead of only being counted (review m5).
    it "carries presumed on a refusal, and on a refused batch case" do
      withServiceFromSources "ty-refuse" [("eligible.l4", refuseDefaultJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "ty-refuse" "eligible" (args ["age" Aeson..= (30 :: Int)])
        case Aeson.decode (responseBody resp) :: Maybe SimpleResponse of
          Just (SimpleError (EvaluatorRefused reason ps)) -> do
            reason `shouldBe` "cannot decide for a non-resident"
            ps `shouldBe` ["is resident"]
          other -> expectationFailure ("Expected a refusal, got: " <> show other)
        supplied <- evalFunction baseUrl mgr "ty-refuse" "eligible"
          (args ["age" Aeson..= (30 :: Int), "is resident" Aeson..= False])
        case Aeson.decode (responseBody supplied) :: Maybe SimpleResponse of
          Just (SimpleError (EvaluatorRefused _ ps)) -> ps `shouldBe` []
          other -> expectationFailure ("Expected a refusal, got: " <> show other)
        let body = Aeson.object
              [ "outcomes" Aeson..= ([] :: [Text])
              , "cases" Aeson..=
                  [ Aeson.object ["@id" Aeson..= (1 :: Int), "age" Aeson..= (30 :: Int)]
                  , Aeson.object ["@id" Aeson..= (2 :: Int), "age" Aeson..= (30 :: Int), "is resident" Aeson..= True]
                  ]
              ]
        req <- buildJsonPost (baseUrl <> "/deployments/ty-refuse/functions/eligible/evaluation/batch") body
        batchResp <- httpLbs req mgr
        case Aeson.decode (responseBody batchResp) :: Maybe BatchResponse of
          Nothing -> expectationFailure ("Failed to decode batch response: " <> show (responseBody batchResp))
          Just batch -> do
            map (\c -> (c.outcome, c.presumed)) batch.cases `shouldBe`
              [ (CaseRefused "cannot decide for a non-resident", ["is resident"]), (CaseAnswered, []) ]
            batch.summary.casesProcessed `shouldBe` 2

    it "returns an errored batch case with its reason, under presumption hard" do
      withServiceFromSources "ty-batch-hard" [("capacity.l4", sectionBooleanJL4)] \baseUrl mgr -> do
        let body = Aeson.object
              [ "outcomes" Aeson..= ([] :: [Text])
              , "presumption" Aeson..= ("hard" :: Text)
              , "cases" Aeson..= [ Aeson.object ["@id" Aeson..= (1 :: Int), "is adult" Aeson..= True, "unused flag" Aeson..= False] ]
              ]
        req <- buildJsonPost (baseUrl <> "/deployments/ty-batch-hard/functions/may%20contract/evaluation/batch") body
        resp <- httpLbs req mgr
        case Aeson.decode (responseBody resp) :: Maybe BatchResponse of
          Just batch -> case map (.outcome) batch.cases of
            [CaseErrored msg] -> msg `shouldSatisfy` Text.isInfixOf "Parameter 'has capacity': missing required parameter"
            other -> expectationFailure ("Expected one errored case, got: " <> show other)
          Nothing -> expectationFailure ("Failed to decode batch response: " <> show (responseBody resp))

    it "refuses an unknown presumption with a 400" do
      withServiceFromSources "ty-bad-switch" [("capacity.l4", sectionBooleanJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "ty-bad-switch" "may contract"
          (Aeson.object ["arguments" Aeson..= Aeson.object ["is adult" Aeson..= True], "presumption" Aeson..= ("medium" :: Text)])
        statusCode' resp `shouldBe` 400

    -- Review m1: an exact default reaches the evaluator exactly on both paths.
    it "keeps a decimal default exact on the direct and the wrapper path" do
      withServiceFromSources "ty-exact" [("exact.l4", exactDecimalJL4)] \baseUrl mgr -> do
        direct <- evalFunction baseUrl mgr "ty-exact" "is exact" (args ["u" Aeson..= True])
        expectAnswer direct (FnLitBool True) ["r"]
        wrapped <- evalFunction baseUrl mgr "ty-exact" "is exact" (args ["u" Aeson..= uncertain])
        expectAnswer wrapped (FnLitBool True) ["r"]

    -- Review m2 and code #7: the schema publishes an enum default as the
    -- constructor's own name, NOTHING as null, and a rule GIVEN's default;
    -- and the direct path accepts the published enum value.
    it "publishes enum, NOTHING and rule GIVEN defaults a request can send back" do
      withServiceFromSources "ty-schema-enum" [("which.l4", enumSchemaJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/deployments/ty-schema-enum/functions/which")
        resp <- httpLbs req mgr
        let props = case lookupKey "parameters" (decodeObject (responseBody resp)) of
              Just (Aeson.Object o) | Just (Aeson.Object ps) <- Aeson.KeyMap.lookup "properties" o -> ps
              _ -> mempty
            defaultOf k = case Aeson.KeyMap.lookup k props of
              Just (Aeson.Object p) -> Aeson.KeyMap.lookup "default" p
              _ -> Nothing
        defaultOf "s" `shouldBe` Just (Aeson.String "Red")
        defaultOf "m" `shouldBe` Just Aeson.Null
        defaultOf "k" `shouldBe` Just (Aeson.Number 5)
        sent <- evalFunction baseUrl mgr "ty-schema-enum" "which" (args ["s" Aeson..= ("Red" :: Text)])
        expectAnswer sent (FnLitInt 5) ["k"]

    -- Review m8 and m4, report item 5: on the wrapper path a non-BOOLEAN
    -- input sent as null is refused by name (it used to be "Evaluation
    -- produced unknown value"), and hard mode compiles a MAYBE default.
    it "refuses null by name on the wrapper path, and names every input under hard" do
      withServiceFromSources "ty-wrap-null" [("wp.l4", wrapperNullJL4)] \baseUrl mgr -> do
        direct <- evalFunction baseUrl mgr "ty-wrap-null" "wp" (args ["k" Aeson..= Aeson.Null])
        expectError direct "Parameter 'k' is null, which means the value is not known, and that never takes the TYPICALLY default"
        wrapped <- evalFunction baseUrl mgr "ty-wrap-null" "wp" (args ["u" Aeson..= uncertain, "k" Aeson..= Aeson.Null])
        expectError wrapped "Field 'k' is null, which means the value is not known, and that never takes the TYPICALLY default"
        soft <- evalFunction baseUrl mgr "ty-wrap-null" "wp" (args ["u" Aeson..= uncertain])
        expectAnswer soft (FnLitInt 1050) ["m", "k", "flag"]
        hardWrapped <- evalFunction baseUrl mgr "ty-wrap-null" "wp"
          (Aeson.object ["arguments" Aeson..= Aeson.object ["u" Aeson..= uncertain], "presumption" Aeson..= ("hard" :: Text)])
        expectError hardWrapped "Missing required fields 'm'"
        expectError hardWrapped "'k' (it has a TYPICALLY default, but presumption is hard"

    it "refuses null on an enum by name, and reads a MAYBE synonym as a MAYBE" do
      withServiceFromSources "ty-enum-null" [("red.l4", enumNullJL4)] \baseUrl mgr -> do
        direct <- evalFunction baseUrl mgr "ty-enum-null" "is red"
          (args ["shade" Aeson..= Aeson.Null, "second" Aeson..= ("Red" :: Text), "unused flag" Aeson..= False])
        expectError direct "Parameter 'shade' is null, which means the value is not known"
        wrapped <- evalFunction baseUrl mgr "ty-enum-null" "is red"
          (args ["shade" Aeson..= Aeson.Null, "second" Aeson..= ("Red" :: Text), "unused flag" Aeson..= uncertain])
        expectError wrapped "Field 'shade' is null, which means the value is not known"
        synonym <- evalFunction baseUrl mgr "ty-enum-null" "is red"
          (args ["shade" Aeson..= ("Red" :: Text), "second" Aeson..= Aeson.Null, "unused flag" Aeson..= False])
        expectAnswer synonym (FnLitBool True) []
        synonymAbsent <- evalFunction baseUrl mgr "ty-enum-null" "is red"
          (args ["shade" Aeson..= ("Red" :: Text), "unused flag" Aeson..= False])
        expectAnswer synonymAbsent (FnLitBool True) ["second"]

    it "fills a record field default on the wrapper path, and names it without the wrapper's suffix" do
      withServiceFromSources "ty-rec-wrap" [("budget.l4", recordWrapJL4)] \baseUrl mgr -> do
        filled <- evalFunction baseUrl mgr "ty-rec-wrap" "budget"
          (args ["cfg" Aeson..= Aeson.object ["retries" Aeson..= (2 :: Int)], "unused flag" Aeson..= uncertain])
        expectAnswer filled (FnLitInt 32) ["cfg.timeout"]
        nulled <- evalFunction baseUrl mgr "ty-rec-wrap" "budget"
          (args ["cfg" Aeson..= Aeson.object ["retries" Aeson..= (2 :: Int), "timeout" Aeson..= Aeson.Null], "unused flag" Aeson..= uncertain])
        expectError nulled "Field 'cfg.timeout' is null"

    -- Review M3 / code #1: a rule's own decode is not the request's.
    it "lets a rule's own JSONDECODE fill its default under hard, and says so" do
      withServiceFromSources "ty-own" [("own.l4", ownDecodeJL4)] \baseUrl mgr -> do
        soft <- evalFunction baseUrl mgr "ty-own" "within limit" (args ["amount" Aeson..= (5 :: Int)])
        expectAnswer soft (FnLitBool True) []
        hardResp <- evalFunction baseUrl mgr "ty-own" "within limit"
          (Aeson.object ["arguments" Aeson..= Aeson.object ["amount" Aeson..= (5 :: Int)], "presumption" Aeson..= ("hard" :: Text)])
        expectAnswer hardResp (FnLitBool True) ["JSONDECODE Settings: limit"]

    it "fills a default on the deontic wrapper path and lists it" do
      withServiceFromSources "ty-deontic" [("seatbelt.l4", deonticDefaultJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "ty-deontic" "seatbelt requirement"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object [ "driver" Aeson..= Aeson.object ["name" Aeson..= ("Alice" :: Text)] ]
            , "startTime" Aeson..= (0 :: Int)
            , "events" Aeson..= ([] :: [Aeson.Value])
            ])
        assertSuccess resp \r -> r.presumed `shouldBe` ["is motorway"]

    -- Review M1 (decided overnight 2026-10-02, pending Meng's review): where
    -- an input or a field left out takes its default, a name that matches
    -- nothing is refused, naming the nearest; elsewhere it is ignored.
    it "refuses an unknown argument where a default is taken, and ignores it elsewhere" do
      withServiceFromSources "ty-typo" [("capacity.l4", sectionBooleanJL4)] \baseUrl mgr -> do
        typo <- evalFunction baseUrl mgr "ty-typo" "may contract"
          (args ["is adult" Aeson..= True, "unused flag" Aeson..= False, "has capasity" Aeson..= False])
        expectError typo "Unknown parameter 'has capasity' (did you mean 'has capacity'?)"
        wrappedTypo <- evalFunction baseUrl mgr "ty-typo" "may contract"
          (args ["is adult" Aeson..= True, "unused flag" Aeson..= uncertain, "has capasity" Aeson..= False])
        expectError wrappedTypo "Unknown parameter 'has capasity' (did you mean 'has capacity'?)"
        nothingTaken <- evalFunction baseUrl mgr "ty-typo" "may contract"
          (args ["is adult" Aeson..= True, "unused flag" Aeson..= False, "has capacity" Aeson..= False, "has capasity" Aeson..= True])
        expectAnswer nothingTaken (FnLitBool False) []
      withServiceFromSources "ty-typo-rec" [("budget.l4", recordDefaultJL4)] \baseUrl mgr -> do
        direct <- evalFunction baseUrl mgr "ty-typo-rec" "budget"
          (args ["cfg" Aeson..= Aeson.object ["retries" Aeson..= (2 :: Int), "timout" Aeson..= (5 :: Int)], "shade" Aeson..= ("Green" :: Text)])
        expectError direct "Unknown field 'cfg.timout' (did you mean 'cfg.timeout'?)"
        full <- evalFunction baseUrl mgr "ty-typo-rec" "budget"
          (args [ "cfg" Aeson..= Aeson.object ["retries" Aeson..= (2 :: Int), "timeout" Aeson..= (5 :: Int), "colour" Aeson..= ("Red" :: Text), "timout" Aeson..= (1 :: Int)]
                , "shade" Aeson..= ("Green" :: Text) ])
        expectAnswer full (FnLitInt 7) []
      withServiceFromSources "ty-typo-wrap" [("budget.l4", recordWrapJL4)] \baseUrl mgr -> do
        wrapped <- evalFunction baseUrl mgr "ty-typo-wrap" "budget"
          (args ["cfg" Aeson..= Aeson.object ["retries" Aeson..= (2 :: Int), "timout" Aeson..= (5 :: Int)], "unused flag" Aeson..= uncertain])
        expectError wrapped "Unknown field 'cfg.timout' (did you mean 'cfg.timeout'?)"

    -- Review M2 (decided overnight 2026-10-02, pending Meng's review): {} on
    -- a record input is null, so it is refused by name, as in l4 batch.
    it "refuses {} on a record input by name" do
      withServiceFromSources "ty-rec-empty" [("budget.l4", recordWrapJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "ty-rec-empty" "budget"
          (args ["cfg" Aeson..= Aeson.object [], "unused flag" Aeson..= False])
        expectError resp "Field 'cfg' is {}, which means the value is not known: supply a value"

    -- Review code #3: the "took its default" registry is per evaluation, so
    -- concurrent requests on one cached deployment cannot see each other's.
    it "keeps presumed apart across concurrent requests" do
      withServiceFromSources "ty-concurrent" [("capacity.l4", sectionSecondJL4)] \baseUrl mgr -> do
        let request i =
              let adult = even (i :: Int)
              in ( adult
                 , args ["is adult" Aeson..= adult, "unused flag" Aeson..= (if i `mod` 3 == 0 then uncertain else Aeson.Bool False)] )
        results <- forConcurrently [1 .. 24] \i -> do
          let (adult, body) = request i
          resp <- evalFunction baseUrl mgr "ty-concurrent" "may contract" body
          pure (adult, Aeson.decode (responseBody resp) :: Maybe SimpleResponse)
        forM_ results \(adult, r) -> case r of
          Just (SimpleResponse rwr) ->
            (Map.lookup "value" rwr.fnResult, rwr.presumed) `shouldBe`
              (Just (FnLitBool adult), [ "has capacity" | adult ])
          other -> expectationFailure ("Expected an answer, got: " <> show other)

    it "carries presumed on each case of the batch endpoint" do
      withServiceFromSources "ty-batch" [("capacity.l4", sectionBooleanJL4)] \baseUrl mgr -> do
        let body = Aeson.object
              [ "outcomes" Aeson..= ([] :: [Text])
              , "cases" Aeson..=
                  [ Aeson.object ["@id" Aeson..= (1 :: Int), "is adult" Aeson..= True, "unused flag" Aeson..= False]
                  , Aeson.object ["@id" Aeson..= (2 :: Int), "is adult" Aeson..= True, "unused flag" Aeson..= False, "has capacity" Aeson..= False]
                  ]
              ]
        req <- buildJsonPost (baseUrl <> "/deployments/ty-batch/functions/may%20contract/evaluation/batch") body
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        case Aeson.decode (responseBody resp) :: Maybe BatchResponse of
          Nothing -> expectationFailure ("Failed to decode batch response: " <> show (responseBody resp))
          Just batch -> map (\c -> c.presumed) batch.cases `shouldBe` [["has capacity"], []]

  describe "field name sanitization (hyphen remapping)" do
    it "accepts hyphenated field names and hyphenated function name in URL" do
      withServiceFromSources "hyphen-eval" [("spaced.l4", spacedFieldsJL4)] \baseUrl mgr -> do
        -- Use hyphenated function name and field keys (as advertised in schemas)
        resp <- evalFunction baseUrl mgr "hyphen-eval" "check-person"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "first-name" Aeson..= ("Alice" :: Text)
                , "is-a-citizen" Aeson..= True
                ]
            ])
        assertSuccess resp \r ->
          Map.lookup "value" r.fnResult `shouldBe` Just (FnLitBool True)

    it "accepts URL-encoded spaced function name (percent encoding)" do
      withServiceFromSources "urlenc-eval" [("spaced.l4", spacedFieldsJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "urlenc-eval" "check%20person"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "first-name" Aeson..= ("Alice" :: Text)
                , "is-a-citizen" Aeson..= True
                ]
            ])
        assertSuccess resp \r ->
          Map.lookup "value" r.fnResult `shouldBe` Just (FnLitBool True)

    it "accepts plus-encoded spaced function name" do
      withServiceFromSources "plus-eval" [("spaced.l4", spacedFieldsJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "plus-eval" "check+person"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "first-name" Aeson..= ("Alice" :: Text)
                , "is-a-citizen" Aeson..= True
                ]
            ])
        assertSuccess resp \r ->
          Map.lookup "value" r.fnResult `shouldBe` Just (FnLitBool True)

    it "accepts original spaced field names in REST API" do
      withServiceFromSources "space-eval" [("spaced.l4", spacedFieldsJL4)] \baseUrl mgr -> do
        -- Use original spaced keys (backwards compatibility)
        resp <- evalFunction baseUrl mgr "space-eval" "check%20person"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "first name" Aeson..= ("Bob" :: Text)
                , "is a citizen" Aeson..= False
                ]
            ])
        assertSuccess resp \r ->
          Map.lookup "value" r.fnResult `shouldBe` Just (FnLitBool False)

    it "returns original spaced field names in OpenAPI schema" do
      withServiceFromSources "openapi-san" [("spaced.l4", spacedFieldsJL4)] \baseUrl mgr -> do
        -- Use /deployments?functions=full to check parameter schemas
        req <- parseRequest (baseUrl <> "/deployments?functions=full")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        let body = responseBody resp
        case Aeson.decode body of
          Just (Aeson.Array deps) -> do
            length deps `shouldSatisfy` (> 0)
            let dep = case toList deps of { (x:_) -> x; [] -> error "empty deployments" }
                mFns = case dep of
                  Aeson.Object o -> case Aeson.KeyMap.lookup "metadata" o of
                    Just (Aeson.Object m) -> Aeson.KeyMap.lookup "functions" m
                    _ -> Nothing
                  _ -> Nothing
            case mFns of
              Just (Aeson.Array fns) -> do
                length fns `shouldSatisfy` (> 0)
                let fn = case toList fns of { (x:_) -> x; [] -> error "empty functions" }
                    mParams = case fn of
                      Aeson.Object o -> Aeson.KeyMap.lookup "parameters" o
                      _ -> Nothing
                    mProps = case mParams of
                      Just (Aeson.Object p) -> Aeson.KeyMap.lookup "properties" p
                      _ -> Nothing
                case mProps of
                  Just (Aeson.Object props) -> do
                    -- Deployments endpoint preserves original L4 names (spaces, not hyphens)
                    Aeson.KeyMap.member "first name" props `shouldBe` True
                    Aeson.KeyMap.member "is a citizen" props `shouldBe` True
                  other ->
                    expectationFailure ("Expected properties object, got: " <> show other)
              other ->
                expectationFailure ("Expected functions array, got: " <> show other)
          other ->
            expectationFailure ("Expected deployments array, got: " <> show other)

  describe "batch evaluation" do
    it "evaluates multiple cases in parallel" do
      withServiceFromSources "batch" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        let batchBody = Aeson.object
              [ "outcomes" Aeson..= ([] :: [Text])
              , "cases" Aeson..= map mkBatchCase [1..10 :: Int]
              ]
        req <- buildJsonPost (baseUrl <> "/deployments/batch/functions/compute_qualifies/evaluation/batch") batchBody
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        let mBatch = Aeson.decode (responseBody resp) :: Maybe BatchResponse
        case mBatch of
          Nothing -> expectationFailure ("Failed to decode batch response: " <> show (responseBody resp))
          Just batch -> do
            length batch.cases `shouldBe` 10
            batch.summary.casesRead `shouldBe` 10
            batch.summary.casesProcessed `shouldBe` 10
            batch.summary.casesIgnored `shouldBe` 0
        -- every response states its report (UNKNOWN-EVALUATION-SPEC §4.7.4)
        reportOf resp `shouldBe` Just "default"

    -- TRAFFICJAM (2026-10-02). A case's time limit is wall-clock, and the batch
    -- used to start every case at once. On one core each case's timer then
    -- counted its siblings' work as well as its own, so forty cases that each
    -- take about a fifth of a second failed the whole batch with a 500 under a
    -- three-second limit, and one slow case took thirty-nine answers with it.
    --
    -- These run at one capability, set here rather than by the RTS options, so
    -- that GHCRTS=-N10 cannot hand the forty cases ten cores and hide the bug.
    describe "at one capability" $ around_ (withCapabilities 1) do
      it "answers 10 fast cases under a 3-second limit" do
        withServiceFromSourcesOpts spinOptions "spin-10" [("spin.l4", spinJL4)] \baseUrl mgr -> do
          resp <- postSpinBatch baseUrl mgr "spin-10" (replicate 10 spinFast)
          expectBatchOutcomes resp (replicate 10 CaseAnswered)

      it "answers 40 fast cases under a 3-second limit that no one case comes near" do
        withServiceFromSourcesOpts spinOptions "spin-40" [("spin.l4", spinJL4)] \baseUrl mgr -> do
          resp <- postSpinBatch baseUrl mgr "spin-40" (replicate 40 spinFast)
          expectBatchOutcomes resp (replicate 40 CaseAnswered)

      it "answers 39 fast cases and errs on 1 slow one, without failing the batch" do
        -- The slow case comes first, so the others wait behind it: a case's
        -- clock starts when the case starts running, not when the batch arrives.
        withServiceFromSourcesOpts spinOptions "spin-39-1" [("spin.l4", spinJL4)] \baseUrl mgr -> do
          resp <- postSpinBatch baseUrl mgr "spin-39-1" (spinSlow : replicate 39 spinFast)
          expectBatchOutcomes resp
            ( CaseLimited TimeLimitHit "Evaluation resource limit exceeded: this case did not finish within the time limit of 3 s (--eval-timeout)"
                : replicate 39 CaseAnswered )

      it "errs on the case that allocates too much, and answers the cases after it" do
        let stingy = testOptions { maxEvalMemoryMb = 64 }
        withServiceFromSourcesOpts stingy "spin-alloc" [("spin.l4", spinJL4)] \baseUrl mgr -> do
          resp <- postSpinBatch baseUrl mgr "spin-alloc" [1_000, spinFast, 1_000]
          expectBatchOutcomes resp
            [ CaseAnswered
            , CaseLimited AllocationLimitHit "Evaluation resource limit exceeded: this case allocated more than the memory limit of 64 MB (--max-eval-memory-mb)"
            , CaseAnswered ]
          map (Aeson.KeyMap.lookup "@limit") (rawBatchCases resp)
            `shouldBe` [Nothing, Just (Aeson.String "memory"), Nothing]

      -- SPEEDTRAP (2026-10-03): only a case a limit stopped carries @limit.
      it "puts @limit on the case a limit stopped, and on no other" do
        withServiceFromSourcesOpts spinOptions "spin-limit-key" [("spin.l4", spinOrRefuseJL4)] \baseUrl mgr -> do
          let body = Aeson.object
                [ "outcomes" Aeson..= ([] :: [Text])
                , "cases" Aeson..=
                    [ Aeson.object ["@id" Aeson..= (1 :: Int), "n" Aeson..= spinSlow]
                    , Aeson.object ["@id" Aeson..= (2 :: Int)]
                    , Aeson.object ["@id" Aeson..= (3 :: Int), "n" Aeson..= (-1 :: Int)]
                    , Aeson.object ["@id" Aeson..= (4 :: Int), "n" Aeson..= (1_000 :: Int)]
                    ]
                ]
          req <- buildJsonPost (baseUrl <> "/deployments/spin-limit-key/functions/spin/evaluation/batch") body
          resp <- httpLbs req mgr
          let raw = rawBatchCases resp
          map (Aeson.KeyMap.lookup "@limit") raw
            `shouldBe` [Just (Aeson.String "time"), Nothing, Nothing, Nothing]
          map (Aeson.KeyMap.member "@error") raw `shouldBe` [True, True, False, False]
          map (Aeson.KeyMap.member "@refused") raw `shouldBe` [False, False, True, False]

      it "answers 10 batches sent at once, which share the core's one slot" do
        -- The slots are the process's, not each request's. With a set per
        -- request, ten one-case batches ran ten cases at once on the core, and
        -- a case taking a fifth of the limit alone ran past it.
        withServiceFromSourcesOpts spinOptions "spin-shared" [("spin.l4", spinJL4)] \baseUrl mgr -> do
          resps <- forConcurrently [1 .. 10 :: Int] \_ ->
            postSpinBatch baseUrl mgr "spin-shared" [spinFifth]
          mapM_ (\resp -> expectBatchOutcomes resp [CaseAnswered]) resps

      it "runs a one-case batch sent just behind a big batch next, not after it" do
        -- Each request queues at most as many cases for the shared slots as
        -- there are slots (here one), and a freed slot goes to the oldest
        -- waiter, so the small batch's case runs as soon as the big batch's
        -- current case is done. With every case of the big batch queued at
        -- once, the small batch waited behind most of them: 4 to 6 s here,
        -- against about one case-time with the bound. The case-time is
        -- measured, as the big batch's time over its eight cases, so that the
        -- test does not depend on how fast the machine is.
        withServiceFromSourcesOpts spinOptions "spin-hol" [("spin.l4", spinJL4)] \baseUrl mgr -> do
          bigStarted <- getCurrentTime
          (bigDone, (smallResp, smallSent, smallDone)) <- concurrently
            (postSpinBatch baseUrl mgr "spin-hol" (replicate 8 spinFifth) >> getCurrentTime)
            ( do
                threadDelay 300_000
                sent <- getCurrentTime
                resp <- postSpinBatch baseUrl mgr "spin-hol" [1_000]
                done <- getCurrentTime
                pure (resp, sent, done) )
          expectBatchOutcomes smallResp [CaseAnswered]
          let caseTime = diffUTCTime bigDone bigStarted / 8
          diffUTCTime smallDone smallSent `shouldSatisfy` (< 2 * caseTime)

    -- Production runs one capability per core (-N), so a batch runs that many
    -- cases at once. At two, the forty cases still each meet the limit alone.
    describe "at two capabilities" $ around_ (withCapabilities 2) do
      it "answers 40 fast cases, none of them past its limit" do
        withServiceFromSourcesOpts spinOptions "spin-40-n2" [("spin.l4", spinJL4)] \baseUrl mgr -> do
          resp <- postSpinBatch baseUrl mgr "spin-40-n2" (replicate 40 spinFast)
          expectBatchOutcomes resp (replicate 40 CaseAnswered)

  -- SIEVE (2026-10-07): the three gaps the README listed under "What the
  -- limits do not cover yet".
  describe "evaluation limits that used to miss" do
    -- smucclaw/l4-ide#1018. The wrapper path evaluates as a Shake rule on a
    -- thread of its own, so the allocation limit set on the calling thread
    -- never saw it. The time limit is large here so that only the memory
    -- limit can stop the case.
    describe "the memory limit on the wrapper path" do
      let stingy = testOptions { maxEvalMemoryMb = 64, evalTimeout = 60 }
          wrapped n = Aeson.object
            [ "arguments" Aeson..= Aeson.object ["n" Aeson..= (n :: Int), "u" Aeson..= Aeson.object []] ]

      it "stops a single evaluation that allocates too much" do
        withServiceFromSourcesOpts stingy "wrap-mem-single" [("spin.l4", spinWrapperJL4)] \baseUrl mgr -> do
          small <- evalFunction baseUrl mgr "wrap-mem-single" "spin" (wrapped 1_000)
          assertSuccess small \r -> Map.lookup "value" r.fnResult `shouldBe` Just (FnLitBool True)
          big <- evalFunction baseUrl mgr "wrap-mem-single" "spin" (wrapped spinFast)
          statusCode' big `shouldBe` 500
          LBS.toStrict (responseBody big) `shouldSatisfy` BS.isInfixOf "Evaluation resource limit exceeded"

      it "reports the case that allocates too much, and answers the cases after it" do
        withCapabilities 1 $
          withServiceFromSourcesOpts stingy "wrap-mem-batch" [("spin.l4", spinWrapperJL4)] \baseUrl mgr -> do
            let body = Aeson.object
                  [ "outcomes" Aeson..= ([] :: [Text])
                  , "cases" Aeson..=
                      [ Aeson.object ["@id" Aeson..= i, "n" Aeson..= n, "u" Aeson..= Aeson.object []]
                      | (i, n) <- zip [1 :: Int ..] [1_000, spinFast, 1_000] ]
                  ]
            req <- buildJsonPost (baseUrl <> "/deployments/wrap-mem-batch/functions/spin/evaluation/batch") body
            resp <- httpLbs req mgr
            expectBatchOutcomes resp
              [ CaseAnswered
              , CaseLimited AllocationLimitHit "Evaluation resource limit exceeded: this case allocated more than the memory limit of 64 MB (--max-eval-memory-mb)"
              , CaseAnswered ]
            map (Aeson.KeyMap.lookup "@limit") (rawBatchCases resp)
              `shouldBe` [Nothing, Just (Aeson.String "memory"), Nothing]

    -- Review of the first fix (2026-10-07). After the memory limit is hit, the
    -- RTS raises again for every further 100 KB the thread allocates; the
    -- unwinding that #1020 added allocates, and those raises used to land
    -- outside the handler and drop the connection. A tail call (spin) has
    -- almost no frames to unwind and hid it, so these use a recursion that is
    -- not a tail call.
    describe "the memory limit on the direct path, in a deep recursion" do
      let stingy = testOptions { maxEvalMemoryMb = 64, evalTimeout = 60 }
          call n = Aeson.object ["arguments" Aeson..= Aeson.object ["n" Aeson..= (n :: Int)]]
          tooDeep = 10_000
          limitText = "Evaluation resource limit exceeded"

      it "answers a small one, stops a deep one with a 500, and answers the next on the same connection" do
        withServiceFromSourcesOpts stingy "deep-single" [("deep.l4", deepJL4)] \baseUrl mgr -> do
          small <- evalFunction baseUrl mgr "deep-single" "deep" (call 10)
          assertSuccess small \r -> Map.lookup "value" r.fnResult `shouldBe` Just (FnLitInt 55)
          hit <- evalFunction baseUrl mgr "deep-single" "deep" (call tooDeep)
          statusCode' hit `shouldBe` 500
          LBS.toStrict (responseBody hit) `shouldSatisfy` BS.isInfixOf limitText
          again <- evalFunction baseUrl mgr "deep-single" "deep" (call 10)
          assertSuccess again \r -> Map.lookup "value" r.fnResult `shouldBe` Just (FnLitInt 55)

      it "reports a deep batch case as the memory limit, and answers the cases around it" do
        withServiceFromSourcesOpts stingy "deep-batch" [("deep.l4", deepJL4)] \baseUrl mgr -> do
          resp <- postBatchTo baseUrl mgr "deep-batch" "deep" [10, tooDeep, 10]
          expectBatchOutcomes resp
            [ CaseAnswered
            , CaseLimited AllocationLimitHit "Evaluation resource limit exceeded: this case allocated more than the memory limit of 64 MB (--max-eval-memory-mb)"
            , CaseAnswered ]

      it "answers a deep MCP call with the limit, and the next call on the same connection" do
        withServiceFromSourcesOpts stingy "deep-mcp" [("deep.l4", deepJL4)] \baseUrl mgr -> do
          let callTool i n = do
                req <- buildJsonPost (baseUrl <> "/deployments/deep-mcp/.mcp") $ Aeson.object
                  [ "jsonrpc" Aeson..= ("2.0" :: Text), "id" Aeson..= (i :: Int)
                  , "method" Aeson..= ("tools/call" :: Text)
                  , "params" Aeson..= Aeson.object
                      [ "name" Aeson..= ("deep" :: Text)
                      , "arguments" Aeson..= Aeson.object ["n" Aeson..= (n :: Int)] ] ]
                responseBody <$> httpLbs req mgr
          hit <- callTool 1 tooDeep
          LBS.toStrict hit `shouldSatisfy` BS.isInfixOf limitText
          again <- callTool 2 10
          LBS.toStrict again `shouldSatisfy` BS.isInfixOf "55"

    -- Review (2026-10-07): a batch never writes the reasoning tree, so a
    -- traced batch must not be made to compute it. Five cases of 1,000 steps
    -- with ?trace=full answered under 64 MB before the limits forced the
    -- response, and all five were stopped once the tree was forced too.
    describe "a batch with a trace" do
      it "answers cases that fit, as it did before the response was forced" do
        let stingy = testOptions { maxEvalMemoryMb = 64, evalTimeout = 60 }
        withServiceFromSourcesOpts stingy "trace-batch" [("spin.l4", spinJL4)] \baseUrl mgr -> do
          let body = Aeson.object
                [ "outcomes" Aeson..= ([] :: [Text])
                , "cases" Aeson..=
                    [ Aeson.object ["@id" Aeson..= i, "n" Aeson..= (1_000 :: Int)] | i <- [1 .. 5 :: Int] ] ]
          req <- buildJsonPost (baseUrl <> "/deployments/trace-batch/functions/spin/evaluation/batch?trace=full") body
          resp <- httpLbs req mgr
          expectBatchOutcomes resp (replicate 5 CaseAnswered)

    -- smucclaw/l4-ide#1019. The evaluation returns an unfinished number at
    -- once; its digits used to be computed by the JSON encoder, after both
    -- limits were off.
    describe "arithmetic the evaluator leaves unfinished" do
      let hasty = testOptions { evalTimeout = 1, maxEvalMemoryMb = 100_000 }
          power n = Aeson.object ["arguments" Aeson..= Aeson.object ["n" Aeson..= (n :: Int)]]

      it "answers a number that finishes inside the limits" do
        withServiceFromSourcesOpts hasty "power-ok" [("power.l4", powerJL4)] \baseUrl mgr -> do
          resp <- evalFunction baseUrl mgr "power-ok" "power" (power 2)
          assertSuccess resp \r -> Map.lookup "value" r.fnResult `shouldBe` Just (FnLitInt (10 ^ (80 :: Int)))

      it "stops a number that does not, inside the time limit" do
        withServiceFromSourcesOpts hasty "power-slow" [("power.l4", powerJL4)] \baseUrl mgr -> do
          t0 <- getCurrentTime
          resp <- evalFunction baseUrl mgr "power-slow" "power" (power powerSlow)
          t1 <- getCurrentTime
          statusCode' resp `shouldBe` 500
          LBS.toStrict (responseBody resp) `shouldSatisfy` BS.isInfixOf "Evaluation resource limit exceeded"
          -- the limit is one second; finishing the number took 12 s without it
          (realToFrac (diffUTCTime t1 t0) :: Double) `shouldSatisfy` (< 4)

      it "reports a batch case whose number does not, and answers the cases around it" do
        withCapabilities 1 $
          withServiceFromSourcesOpts hasty "power-batch" [("power.l4", powerJL4)] \baseUrl mgr -> do
            resp <- postBatchTo baseUrl mgr "power-batch" "power" [2, powerSlow, 2]
            expectBatchOutcomes resp
              [ CaseAnswered
              , CaseLimited TimeLimitHit "Evaluation resource limit exceeded: this case did not finish within the time limit of 1 s (--eval-timeout)"
              , CaseAnswered ]

    -- smucclaw/l4-ide#1020. A limit hit while forcing an imported value left
    -- the forcing thread's mark on the value's thunk, which outlives the
    -- request; the next request on the same thread then met its own mark and
    -- reported "Infinite loop detected".
    describe "a limit hit inside an imported value" do
      let stingy = testOptions { maxEvalMemoryMb = 64, evalTimeout = 60 }
          sources = [("heavy_lib.l4", heavyLibJL4), ("heavy_main.l4", heavyMainJL4)]
          call n = Aeson.object ["arguments" Aeson..= Aeson.object ["n" Aeson..= (n :: Int)]]
          -- 47 MB of the case's own steps leaves too little for the value
          tooMuch = 7_000
          loopMessage = "Infinite loop detected"

      it "does not spoil the next single evaluation on the same connection" do
        withServiceFromSourcesOpts stingy "heavy-single" sources \baseUrl mgr -> do
          hit <- evalFunction baseUrl mgr "heavy-single" "use-heavy" (call tooMuch)
          statusCode' hit `shouldBe` 500
          LBS.toStrict (responseBody hit) `shouldSatisfy` BS.isInfixOf "Evaluation resource limit exceeded"
          again <- evalFunction baseUrl mgr "heavy-single" "use-heavy" (call 0)
          LBS.toStrict (responseBody again) `shouldSatisfy` (not . BS.isInfixOf loopMessage)
          assertSuccess again \r -> Map.lookup "value" r.fnResult `shouldBe` Just (FnLitBool True)
          -- the hit above landed inside the imported value: once it is worked
          -- out and kept, the same 47 MB of the case's own steps fit
          cached <- evalFunction baseUrl mgr "heavy-single" "use-heavy" (call tooMuch)
          assertSuccess cached \r -> Map.lookup "value" r.fnResult `shouldBe` Just (FnLitBool True)

      it "does not spoil the next evaluation on a new connection, or a batch case" do
        withServiceFromSourcesOpts stingy "heavy-new" sources \baseUrl mgr -> do
          hit <- evalFunction baseUrl mgr "heavy-new" "use-heavy" (call tooMuch)
          statusCode' hit `shouldBe` 500
          fresh <- newManager defaultManagerSettings
          other <- evalFunction baseUrl fresh "heavy-new" "use-heavy" (call 0)
          assertSuccess other \r -> Map.lookup "value" r.fnResult `shouldBe` Just (FnLitBool True)
          resp <- postBatchTo baseUrl mgr "heavy-new" "use-heavy" [0, 0]
          expectBatchOutcomes resp [CaseAnswered, CaseAnswered]

      it "does not spoil the next MCP call on the same connection" do
        withServiceFromSourcesOpts stingy "heavy-mcp" sources \baseUrl mgr -> do
          let rpc :: Int -> Aeson.Value -> Aeson.Value
              rpc i params = Aeson.object
                [ "jsonrpc" Aeson..= ("2.0" :: Text), "id" Aeson..= i
                , "method" Aeson..= ("tools/call" :: Text), "params" Aeson..= params ]
              listBody = Aeson.object
                [ "jsonrpc" Aeson..= ("2.0" :: Text), "id" Aeson..= (0 :: Int), "method" Aeson..= ("tools/list" :: Text) ]
              mcp body = do
                req <- buildJsonPost (baseUrl <> "/deployments/heavy-mcp/.mcp") body
                responseBody <$> httpLbs req mgr
          listed <- mcp listBody
          let toolNames = case Aeson.decode listed of
                Just (Aeson.Object o)
                  | Just (Aeson.Object r) <- Aeson.KeyMap.lookup "result" o
                  , Just (Aeson.Array ts) <- Aeson.KeyMap.lookup "tools" r ->
                      [ n | Aeson.Object t <- toList ts, Just (Aeson.String n) <- [Aeson.KeyMap.lookup "name" t] ]
                _ -> []
          let tool = "use-heavy"
          toolNames `shouldContain` [tool]
          let callTool i n = mcp (rpc i (Aeson.object ["name" Aeson..= tool, "arguments" Aeson..= Aeson.object ["n" Aeson..= (n :: Int)]]))
          hit <- callTool 2 tooMuch
          LBS.toStrict hit `shouldSatisfy` BS.isInfixOf "Evaluation resource limit exceeded"
          again <- callTool 3 0
          LBS.toStrict again `shouldSatisfy` (not . BS.isInfixOf loopMessage)
          LBS.toStrict again `shouldSatisfy` BS.isInfixOf "true"

  -- U7b: the report a response carries is never left to be guessed. Until
  -- build step 6 adds the others it is always the default one.
  describe "the stated report" do
    it "is \"default\" on a successful evaluation and on one that stopped" do
      withServiceFromSources "report" [("eligible.l4", missingBooleanJL4)] \baseUrl mgr -> do
        decided <- evalFunction baseUrl mgr "report" "eligible"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "is resident" Aeson..= False
                , "unused flag" Aeson..= Aeson.object []
                ]
            ])
        statusCode' decided `shouldBe` 200
        reportOf decided `shouldBe` Just "default"
        waiting <- evalFunction baseUrl mgr "report" "eligible"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "is resident" Aeson..= True
                , "unused flag" Aeson..= Aeson.object []
                ]
            ])
        statusCode' waiting `shouldBe` 422
        reportOf waiting `shouldBe` Just "default"

    -- Decided by Claude 2026-10-07, pending Meng's review. @p AND TRUE@ is @p@:
    -- a bare unknown inside the wrapper's JUST must be undetermined and name
    -- the input, as on the direct path, and not "#EVAL produced ASSUME".
    it "names the input when a wrapper-path answer is the bare missing input" do
      withServiceFromSources "bare-input" [("gate.l4", bareInputJL4)] \baseUrl mgr -> do
        let ask q = evalFunction baseUrl mgr "bare-input" "gate"
              (Aeson.object
                [ "arguments" Aeson..= Aeson.object [ "p" Aeson..= Aeson.object [], "q" Aeson..= q ] ])
            textOf = Text.Encoding.decodeUtf8 . LBS.toStrict . responseBody
        -- positive control: the same request, decided by q, answers
        decided <- ask False
        statusCode' decided `shouldBe` 200
        -- the answer is p itself
        waiting <- ask True
        statusCode' waiting `shouldBe` 422
        textOf waiting `shouldSatisfy` Text.isInfixOf "I could not continue evaluating"
        textOf waiting `shouldSatisfy` Text.isInfixOf "`p (not supplied)`"
        textOf waiting `shouldSatisfy` (not . Text.isInfixOf "produced ASSUME")
        reportOf waiting `shouldBe` Just "default"

    it "is \"default\" in an MCP tool's answer, and in its undetermined error" do
      withServiceFromSources "report-mcp" [("eligible.l4", missingBooleanJL4)] \baseUrl mgr -> do
        let call args = do
              req <- buildJsonPost (baseUrl <> "/.mcp") $ Aeson.object
                [ "jsonrpc" Aeson..= ("2.0" :: Text)
                , "id" Aeson..= (1 :: Int)
                , "method" Aeson..= ("tools/call" :: Text)
                , "params" Aeson..= Aeson.object
                    [ "name" Aeson..= ("eligible" :: Text)
                    , "arguments" Aeson..= args
                    ]
                ]
              resp <- httpLbs req mgr
              statusCode' resp `shouldBe` 200
              pure (mcpToolText (responseBody resp))
        decided <- call $ Aeson.object
          [ "is resident" Aeson..= False, "unused flag" Aeson..= Aeson.object [] ]
        fmap fst decided `shouldBe` Just False
        (reportOfText . snd =<< decided) `shouldBe` Just "default"
        waiting <- call $ Aeson.object
          [ "is resident" Aeson..= True, "unused flag" Aeson..= Aeson.object [] ]
        fmap fst waiting `shouldBe` Just True
        (reportOfText . snd =<< waiting) `shouldBe` Just "default"
        (snd <$> waiting) `shouldSatisfy` maybe False ("I needed to know the value" `Text.isInfixOf`)

  describe "control plane (HTTP multipart)" do
    it "deploys a bundle and reaches ready state" do
      withEmptyService \baseUrl mgr -> do
        let zipBytes = createZipBundle [("qualifies.l4", qualifiesJL4)]
        postReq <- buildMultipartRequest (baseUrl <> "/deployments") "http-deploy" zipBytes
        postResp <- httpLbs postReq mgr
        statusCode' postResp `shouldBe` 202
        let mStatus = Aeson.decode (responseBody postResp) :: Maybe DeploymentStatusResponse
        case mStatus of
          Nothing -> expectationFailure "Failed to decode deployment response"
          Just status -> do
            status.dsId `shouldBe` "http-deploy"
            status.dsStatus `shouldBe` "compiling"

        pollUntilReady baseUrl mgr "http-deploy" 60

    it "lists deployments" do
      withEmptyService \baseUrl mgr -> do
        let zipBytes = createZipBundle [("qualifies.l4", qualifiesJL4)]
        req1 <- buildMultipartRequest (baseUrl <> "/deployments") "list-a" zipBytes
        _ <- httpLbs req1 mgr
        req2 <- buildMultipartRequest (baseUrl <> "/deployments") "list-b" zipBytes
        _ <- httpLbs req2 mgr
        pollUntilReady baseUrl mgr "list-a" 60
        pollUntilReady baseUrl mgr "list-b" 60

        listReq <- parseRequest (baseUrl <> "/deployments")
        listResp <- httpLbs listReq mgr
        statusCode' listResp `shouldBe` 200
        let mList = Aeson.decode (responseBody listResp) :: Maybe [DeploymentStatusResponse]
        case mList of
          Nothing -> expectationFailure "Failed to decode deployment list"
          Just deploys -> do
            length deploys `shouldSatisfy` (>= 2)
            map (.dsId) deploys `shouldContain` ["list-a"]
            map (.dsId) deploys `shouldContain` ["list-b"]

    -- The content-hash shortcut is keyed on the id too. Keyed on content
    -- alone, a POST for "beta" whose bytes equalled "alpha"'s answered with
    -- alpha's id and metadata, and created nothing.
    it "skips recompiling identical sources only under the same id" do
      withEmptyService \baseUrl mgr -> do
        let zipBytes = createZipBundle [("qualifies.l4", qualifiesJL4)]
            postAs did = do
              req <- buildMultipartRequest (baseUrl <> "/deployments") did zipBytes
              resp <- httpLbs req mgr
              statusCode' resp `shouldBe` 202
              case Aeson.decode (responseBody resp) :: Maybe DeploymentStatusResponse of
                Just s -> pure s
                Nothing -> fail ("Failed to decode deployment response: " <> show (responseBody resp))
        _ <- postAs "alpha"
        pollUntilReady baseUrl mgr "alpha" 60

        beta <- postAs "beta"
        beta.dsId `shouldBe` "beta"
        pollUntilReady baseUrl mgr "beta" 60
        getReq <- parseRequest (baseUrl <> "/deployments/beta")
        getResp <- httpLbs getReq mgr
        statusCode' getResp `shouldBe` 200

        again <- postAs "beta"
        (again.dsId, again.dsStatus, again.dsUpdateId) `shouldBe` ("beta", "ready", Nothing)

    it "deletes a deployment" do
      withEmptyService \baseUrl mgr -> do
        let zipBytes = createZipBundle [("qualifies.l4", qualifiesJL4)]
        postReq <- buildMultipartRequest (baseUrl <> "/deployments") "to-delete" zipBytes
        _ <- httpLbs postReq mgr
        pollUntilReady baseUrl mgr "to-delete" 60

        deleteReq <- parseRequest (baseUrl <> "/deployments/to-delete")
        let deleteReq' = deleteReq { method = "DELETE" }
        deleteResp <- httpLbs deleteReq' mgr
        statusCode' deleteResp `shouldBe` 204

        getReq <- parseRequest (baseUrl <> "/deployments/to-delete")
        getResp <- httpLbs getReq mgr
        statusCode' getResp `shouldBe` 404

    it "stamps the deployment version and bumps RUNNING on redeploy" do
      withEmptyService \baseUrl mgr -> do
        let major = Text.pack (show Version.serviceMajor)
            -- Read deploymentVersion off GET /deployments/{id}?functions=full.
            getVersion did = do
              req <- parseRequest
                (baseUrl <> "/deployments/" <> did <> "?functions=full")
              resp <- httpLbs req mgr
              statusCode' resp `shouldBe` 200
              case Aeson.decode (responseBody resp) :: Maybe DeploymentStatusResponse of
                Just s | Just m <- s.dsMetadata -> pure m.metaDeploymentVersion
                _ -> expectationFailure "no metadata" >> pure ""

        -- First deploy → {major}.0.0
        postReq <- buildMultipartRequest (baseUrl <> "/deployments") "ver-test"
          (createZipBundle [("qualifies.l4", qualifiesJL4)])
        _ <- httpLbs postReq mgr
        pollUntilReady baseUrl mgr "ver-test" 60
        getVersion "ver-test" `shouldReturn` (major <> ".0.0")

        -- Redeploy the same id with different (compatible) source → RUNNING
        -- bumps, BREAKING unchanged → {major}.0.1. The old version is already
        -- "ready", so poll the version itself rather than readiness (which
        -- would return immediately on the stale deployment).
        let awaitVersion expected n = do
              v <- getVersion "ver-test"
              if v == expected || n <= (0 :: Int)
                then v `shouldBe` expected
                else threadDelay 200_000 >> awaitVersion expected (n - 1)
        reReq <- buildMultipartRequest (baseUrl <> "/deployments") "ver-test"
          (createZipBundle [("qualifies.l4", qualifiesJL4 <> "\n-- v2\n")])
        _ <- httpLbs reReq mgr
        awaitVersion (major <> ".0.1") 50

  -- REFUSE (R7) is a throw at force, never a value. The plan must reach it where
  -- evaluation does: a rule of no inputs that always refuses is not a question
  -- (no answer to it is ever used), and a case that reaches a refusal is reported
  -- as one, with evaluation's reason. /evaluation is the oracle.
  describe "query-plan and evaluation agree on refusals" do
    let args :: [(Text, Bool)] -> Aeson.Value
        args bs = Aeson.object ["arguments" Aeson..= Aeson.object [Aeson.Key.fromText k Aeson..= v | (k, v) <- bs]]

        refusalReasons :: Maybe Aeson.Object -> [Text]
        refusalReasons plan = case lookupKey "refusal" plan of
          Just (Aeson.Object r) | Just (Aeson.Array rs) <- Aeson.KeyMap.lookup "reasons" r -> [t | Aeson.String t <- toList rs]
          _ -> []

        -- The questions a plan asks, by label.
        askedLabels :: Maybe Aeson.Object -> [Text]
        askedLabels plan = case lookupKey "stillNeeded" plan of
          Just (Aeson.Array xs) -> [l | Aeson.Object a <- toList xs, Just (Aeson.String l) <- [Aeson.KeyMap.lookup "label" a]]
          _ -> []

        -- Every complete set of answers to the inputs is evaluated, and the plan
        -- for it must say the same: the same truth value, or a refusal whose one
        -- reason is the reason /evaluation gives. Every partial set is planned too,
        -- and where the plan settles the case early, every way of answering the
        -- rest must agree with it: the same truth value, or a refusal, with the
        -- plan's reasons exactly the ones those completions reach. No plan asks
        -- anything but an input.
        oracle :: Text -> Text -> [Text] -> SpecWith ()
        oracle dep src inputs =
          it (Text.unpack dep <> ": the plan agrees with /evaluation on every set of answers") do
            withServiceFromSources dep [("rule.l4", src)] \baseUrl mgr -> do
              let completions bs =
                    [ List.sort (bs <> zip rest vals)
                    | let rest = [n | n <- inputs, n `notElem` map fst bs]
                    , vals <- replicateM (length rest) [False, True]
                    ]
                  partials = [[a | Just a <- answers] | answers <- traverse (\n -> [Nothing, Just (n, False), Just (n, True)]) inputs]
              evaluated <- fmap Map.fromList $ forM (completions []) \bs -> do
                ev <- evalFunction baseUrl mgr dep "eligible" (args bs)
                case Aeson.decode (responseBody ev) :: Maybe SimpleResponse of
                  Just (SimpleError (EvaluatorRefused reason _)) -> pure (bs, Left reason)
                  Just (SimpleResponse r) | Just (FnLitBool b) <- Map.lookup "value" r.fnResult -> pure (bs, Right b)
                  other -> fail ("unexpected evaluation of " <> show bs <> ": " <> show other)
              for_ partials \bs -> do
                qp <- queryPlan' baseUrl mgr dep "eligible" (args bs)
                statusCode' qp `shouldBe` 200
                let plan = decodeObject (responseBody qp)
                    outs = [evaluated Map.! c | c <- completions bs]
                    reasons = refusalReasons plan
                    verdict = lookupKey "verdict" plan
                (bs, filter (`notElem` inputs) (askedLabels plan)) `shouldBe` (bs, [])
                case lookupKey "determined" plan of
                  Just (Aeson.Bool b) -> do
                    (bs, reasons) `shouldBe` (bs, [])
                    (bs, verdict `elem` map (Just . Aeson.String) ["Undetermined", "Refused"]) `shouldBe` (bs, False)
                    (bs, outs) `shouldBe` (bs, map (const (Right b)) outs)
                  Just Aeson.Null
                    | not (null reasons) -> do
                        (bs, verdict) `shouldBe` (bs, Just (Aeson.String "Refused"))
                        (bs, length reasons, List.nub (List.sort [r | Left r <- outs]), length [() | Left _ <- outs])
                          `shouldBe` (bs, length (List.nub reasons), List.sort reasons, length outs)
                    | otherwise -> do
                        (bs, verdict) `shouldBe` (bs, Just (Aeson.String "Undetermined"))
                        (bs, length bs < length inputs) `shouldBe` (bs, True)
                  other -> expectationFailure (show bs <> ": determined is " <> show other)

    -- The measured rule: `adult AND` a rule of no inputs that refuses.
    oracle "refuse-and" refusingConditionJL4 ["adult"]
    -- OR, the same way round: TRUE where adult is.
    oracle "refuse-or" refusingOrJL4 ["adult"]
    -- The refusing rule read first refuses whatever adult is.
    oracle "refuse-first" refusingFirstJL4 ["adult"]
    oracle "refuse-not" refusingNotJL4 ["adult", "resident"]
    oracle "refuse-implies" refusingImpliesJL4 ["adult", "resident"]
    oracle "refuse-implies-nested" refusingImpliesNestedJL4 ["adult", "resident"]
    oracle "refuse-seam-open" refusingSeamOpenJL4 ["adult"]
    -- Three rules of no inputs deep, one under a WHERE.
    oracle "refuse-deep" refusingDeepJL4 ["adult"]
    -- Inside a disjunction of conjunctions: planned as written, not simplified.
    oracle "refuse-dist" refusingDistributedJL4 ["adult", "resident"]
    -- A REFUSE written on an arm of the rule.
    oracle "refuse-arm" refusingArmJL4 ["resident", "adult"]
    oracle "refuse-both-arms" refusingBothArmsJL4 ["resident"]

    it "asks only adult, never the rule that refuses" do
      withServiceFromSources "refuse-asks" [("rule.l4", refusingConditionJL4)] \baseUrl mgr -> do
        qp <- queryPlan' baseUrl mgr "refuse-asks" "eligible" (args [])
        statusCode' qp `shouldBe` 200
        let plan = decodeObject (responseBody qp)
        lookupKey "verdict" plan `shouldBe` Just (Aeson.String "Undetermined")
        askedLabels plan `shouldBe` ["adult"]

    it "both arms of an IF refuse: refused before the condition is answered, with both reasons" do
      withServiceFromSources "refuse-both" [("rule.l4", refusingBothArmsJL4)] \baseUrl mgr -> do
        qp <- queryPlan' baseUrl mgr "refuse-both" "eligible" (args [])
        let plan = decodeObject (responseBody qp)
        lookupKey "verdict" plan `shouldBe` Just (Aeson.String "Refused")
        askedLabels plan `shouldBe` []
        List.sort (refusalReasons plan)
          `shouldBe` ["the rules for non-residents are not modelled", "the rules for residents are not modelled"]

    it "an answer for the rule that refuses changes nothing: evaluation takes none" do
      withServiceFromSources "refuse-bound" [("rule.l4", refusingConditionJL4)] \baseUrl mgr -> do
        qp <- queryPlan' baseUrl mgr "refuse-bound" "eligible"
          (args [("adult", True), ("the other conditions are not modelled", True)])
        let plan = decodeObject (responseBody qp)
        lookupKey "verdict" plan `shouldBe` Just (Aeson.String "Refused")
        refusalReasons plan `shouldBe` ["the other conditions are not modelled"]

    -- The guards: a rule of no inputs that cannot refuse, or refuses on only one
    -- path, is still a question, exactly as before.
    it "still asks a rule of no inputs that cannot refuse" do
      withServiceFromSources "answered-cond" [("rule.l4", answeredConditionJL4)] \baseUrl mgr -> do
        qp <- queryPlan' baseUrl mgr "answered-cond" "eligible" (args [("adult", True)])
        let plan = decodeObject (responseBody qp)
        lookupKey "verdict" plan `shouldBe` Just (Aeson.String "Undetermined")
        askedLabels plan `shouldBe` ["the fee is paid"]
        lookupKey "refusal" plan `shouldSatisfy` maybe True (== Aeson.Null)

    it "still asks a rule of no inputs that refuses on only one path" do
      withServiceFromSources "conditional-refuser" [("rule.l4", conditionalRefuserJL4)] \baseUrl mgr -> do
        qp <- queryPlan' baseUrl mgr "conditional-refuser" "eligible" (args [("adult", True)])
        let plan = decodeObject (responseBody qp)
        lookupKey "verdict" plan `shouldBe` Just (Aeson.String "Undetermined")
        askedLabels plan `shouldBe` ["the cap applies"]
        lookupKey "refusal" plan `shouldSatisfy` maybe True (== Aeson.Null)

  describe "query-plan" do
    it "returns a query plan with no bindings" do
      withServiceFromSources "qp-empty" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        resp <- queryPlan' baseUrl mgr "qp-empty" "compute_qualifies"
          (Aeson.object ["arguments" Aeson..= Aeson.object []])
        statusCode' resp `shouldBe` 200
        let body = decodeObject (responseBody resp)
        lookupKey "determined" body `shouldBe` Just Aeson.Null
        lookupArrayLength "stillNeeded" body `shouldSatisfy` maybe False (> 0)
        lookupArrayLength "asks" body `shouldSatisfy` maybe False (> 0)

    it "determines True when all args are true" do
      withServiceFromSources "qp-all-true" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        resp <- queryPlan' baseUrl mgr "qp-all-true" "compute_qualifies"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "walks" Aeson..= True
                , "eats" Aeson..= True
                , "drinks" Aeson..= True
                ]
            ])
        statusCode' resp `shouldBe` 200
        let body = decodeObject (responseBody resp)
        lookupKey "determined" body `shouldBe` Just (Aeson.Bool True)
        lookupArrayLength "stillNeeded" body `shouldBe` Just 0

    it "determines False when one arg is false" do
      withServiceFromSources "qp-one-false" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        resp <- queryPlan' baseUrl mgr "qp-one-false" "compute_qualifies"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "walks" Aeson..= False
                ]
            ])
        statusCode' resp `shouldBe` 200
        let body = decodeObject (responseBody resp)
        lookupKey "determined" body `shouldBe` Just (Aeson.Bool False)

    it "is undetermined with partial true bindings" do
      withServiceFromSources "qp-partial" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        resp <- queryPlan' baseUrl mgr "qp-partial" "compute_qualifies"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "walks" Aeson..= True
                , "eats" Aeson..= True
                ]
            ])
        statusCode' resp `shouldBe` 200
        let body = decodeObject (responseBody resp)
        lookupKey "determined" body `shouldBe` Just Aeson.Null
        lookupArrayLength "stillNeeded" body `shouldSatisfy` maybe False (> 0)

    it "caches the query plan across requests" do
      withServiceFromSources "qp-cache" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        -- First request builds the cache
        resp1 <- queryPlan' baseUrl mgr "qp-cache" "compute_qualifies"
          (Aeson.object ["arguments" Aeson..= Aeson.object []])
        statusCode' resp1 `shouldBe` 200

        -- Second request should use the cached version
        resp2 <- queryPlan' baseUrl mgr "qp-cache" "compute_qualifies"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "walks" Aeson..= True
                , "eats" Aeson..= True
                , "drinks" Aeson..= True
                ]
            ])
        statusCode' resp2 `shouldBe` 200
        let body = decodeObject (responseBody resp2)
        lookupKey "determined" body `shouldBe` Just (Aeson.Bool True)

    it "is held to --eval-timeout, and says so when it runs out" do
      -- The cached decision structure of this function is cheap to build, and
      -- its plan is not. A plan left to be computed while the response was
      -- sent was under no limit of ours: the request held its slot, and the
      -- service went on computing after the client had left, or the
      -- connection closed with no status once Warp's own timeout ran out.
      -- evalTimeout is dropped to 2s so the suite stays pleasant. If plans
      -- get faster and this one stops running out, raise the count.
      let impatient = testOptions { evalTimeout = 2 }
      withServiceFromSourcesOpts impatient "qp-timeout" [("carries.l4", considerPlanJL4 22)]
        \baseUrl mgr -> do
          started <- getCurrentTime
          resp <- queryPlan' baseUrl mgr "qp-timeout" "carries"
            (Aeson.object ["arguments" Aeson..= Aeson.object []])
          finished <- getCurrentTime
          statusCode' resp `shouldBe` 500
          lookupKey "error" (decodeObject (responseBody resp))
            `shouldBe` Just (Aeson.String "Query plan timed out")
          -- The client gives up at 30 s, so a bound at that is no bound.
          diffUTCTime finished started `shouldSatisfy` (< 15)

    it "returns 404 for unknown function" do
      withServiceFromSources "qp-404" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        resp <- queryPlan' baseUrl mgr "qp-404" "no_such_fn"
          (Aeson.object ["arguments" Aeson..= Aeson.object []])
        statusCode' resp `shouldBe` 404

  describe "ladder" do
    it "returns the ladder IR for a boolean DECIDE" do
      withServiceFromSources "ladder-ok" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        resp <- getLadder baseUrl mgr "ladder-ok" "compute_qualifies"
        statusCode' resp `shouldBe` 200
        let body = decodeObject (responseBody resp)
        lookupKey "verDocId" body `shouldSatisfy` Maybe.isJust
        case lookupKey "funDecl" body of
          Just (Aeson.Object fd) -> do
            -- FunDecl serialises fnName under the key "name" (VizExpr.hs).
            Aeson.KeyMap.lookup "name" fd `shouldSatisfy` Maybe.isJust
            length (ladderParams fd) `shouldBe` 3
            -- walks AND eats AND drinks
            ladderBodyType fd `shouldBe` Just "And"
            ladderAtomLabels fd `shouldBe` ["drinks", "eats", "walks"]
          other -> expectationFailure ("expected funDecl object, got: " <> show other)

    it "returns exactly the ladder that query-plan already embeds" do
      -- The GET is not a new information surface: byte-for-byte the same value
      -- is in every query-plan 200. This invariant must survive any future
      -- change to how the ladder is built, so assert JSON equality, not shape.
      withServiceFromSources "ladder-same" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        qpResp <- queryPlan' baseUrl mgr "ladder-same" "compute_qualifies"
          (Aeson.object ["arguments" Aeson..= Aeson.object []])
        statusCode' qpResp `shouldBe` 200
        ldResp <- getLadder baseUrl mgr "ladder-same" "compute_qualifies"
        statusCode' ldResp `shouldBe` 200
        let embedded = lookupKey "ladder" (decodeObject (responseBody qpResp))
            standalone = Aeson.decode (responseBody ldResp) :: Maybe Aeson.Value
        embedded `shouldNotBe` Just Aeson.Null
        standalone `shouldBe` embedded

    it "still answers query-plan, with the same ladder, after a ladder-first request" do
      -- Request ORDER must not change either answer. Deliberately NOT named for
      -- the cache: this assertion cannot see the cache at all (see the note on
      -- the registry tests below), and a name claiming otherwise would advertise
      -- coverage that does not exist.
      withServiceFromSources "ladder-first" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        ldResp <- getLadder baseUrl mgr "ladder-first" "compute_qualifies"
        statusCode' ldResp `shouldBe` 200
        qpResp <- queryPlan' baseUrl mgr "ladder-first" "compute_qualifies"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "walks" Aeson..= True
                , "eats" Aeson..= True
                , "drinks" Aeson..= True
                ]
            ])
        statusCode' qpResp `shouldBe` 200
        let body = decodeObject (responseBody qpResp)
        lookupKey "determined" body `shouldBe` Just (Aeson.Bool True)
        lookupKey "ladder" body `shouldBe` (Aeson.decode (responseBody ldResp) :: Maybe Aeson.Value)

    -- The test above is about AGREEMENT, and it holds whether or not anything
    -- is cached — both endpoints are deterministic, so an implementation that
    -- rebuilt the visualization + BDD on every request would pass it byte for
    -- byte. Memoisation itself is unobservable from the wire, so assert it
    -- against the registry instead. It is not a nicety: the uncached build runs
    -- outside `timeoutAction` and holds one of the `maxConcurrentRequests`
    -- slots, and "it is built once" is the only thing bounding that.
    it "builds the decision-query cache once and writes it back to the registry" do
      withServiceFromSourcesTVar "ladder-memo" [("qualifies.l4", qualifiesJL4)]
        \registry baseUrl mgr -> do
          let cached = hasDecisionQueryCache registry "ladder-memo" "compute_qualifies"
          -- Nothing is built at deploy time: the first request pays for it.
          cached `shouldReturn` False
          ldResp <- getLadder baseUrl mgr "ladder-memo" "compute_qualifies"
          statusCode' ldResp `shouldBe` 200
          cached `shouldReturn` True

    it "...and query-plan first warms the same cache" do
      withServiceFromSourcesTVar "qp-memo" [("qualifies.l4", qualifiesJL4)]
        \registry baseUrl mgr -> do
          let cached = hasDecisionQueryCache registry "qp-memo" "compute_qualifies"
          cached `shouldReturn` False
          qpResp <- queryPlan' baseUrl mgr "qp-memo" "compute_qualifies"
            (Aeson.object ["arguments" Aeson..= Aeson.object []])
          statusCode' qpResp `shouldBe` 200
          cached `shouldReturn` True

    -- A deployment outlives the process that compiled it. A restart used to
    -- read a cache that carries no annotations, which is where the ladder's
    -- boolean-return check reads its type from, and both routes 400ed for every
    -- restarted deployment.
    it "serves the ladder after a restart" do
      withServiceRestarted "ladder-restart" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        resp <- getLadder baseUrl mgr "ladder-restart" "compute_qualifies"
        statusCode' resp `shouldBe` 200
        case lookupKey "funDecl" (decodeObject (responseBody resp)) of
          Just (Aeson.Object fd) -> do
            ladderBodyType fd `shouldBe` Just "And"
            ladderAtomLabels fd `shouldBe` ["drinks", "eats", "walks"]
          other -> expectationFailure ("expected funDecl object, got: " <> show other)

    it "serves query-plan after a restart" do
      -- The sibling route, broken by the same cause. Pinned here because
      -- nothing else in the suite restarts.
      withServiceRestarted "qp-restart" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        resp <- queryPlan' baseUrl mgr "qp-restart" "compute_qualifies"
          (Aeson.object ["arguments" Aeson..= Aeson.object []])
        statusCode' resp `shouldBe` 200
        lookupKey "ladder" (decodeObject (responseBody resp)) `shouldNotBe` Just Aeson.Null

    -- A rule written as DECIDE clauses is the same rule as the CONSIDER
    -- it stands for, so its plan and its ladder must be the same: the same
    -- inputs, the same questions, the same nodes. Compared whole, modulo the
    -- numbering of nodes ('withoutNodeIds'), so that a clause group drawn as
    -- one leaf that asks nothing (or one that names a generated binding) fails.
    describe "a BOOLEAN rule written as DECIDE clauses" do
      let sameAsHandWritten :: Text -> Text -> Text -> SpecWith ()
          sameAsHandWritten name clauses hand =
            it (Text.unpack ("has the plan and the ladder of its hand-written CONSIDER: " <> name)) do
              withServiceFromSources ("cg-" <> name) [("rule.l4", clauses)] \baseUrl mgr -> do
                withServiceFromSources ("hw-" <> name) [("rule.l4", hand)] \baseUrl' mgr' -> do
                  qpC <- queryPlan' baseUrl mgr ("cg-" <> name) "rule" (Aeson.object ["arguments" Aeson..= Aeson.object []])
                  qpH <- queryPlan' baseUrl' mgr' ("hw-" <> name) "rule" (Aeson.object ["arguments" Aeson..= Aeson.object []])
                  statusCode' qpC `shouldBe` 200
                  statusCode' qpH `shouldBe` 200
                  ldC <- getLadder baseUrl mgr ("cg-" <> name) "rule"
                  statusCode' ldC `shouldBe` 200
                  let planC = withoutNodeIds <$> (Aeson.decode (responseBody qpC) :: Maybe Aeson.Value)
                      planH = withoutNodeIds <$> (Aeson.decode (responseBody qpH) :: Maybe Aeson.Value)
                  planC `shouldBe` planH
                  -- the plan asks something
                  lookupArrayLength "inputs" (decodeObject (responseBody qpC)) `shouldSatisfy` maybe False (> 0)
                  -- and no name the desugarer made up reaches a label, an ask or an input
                  let text = Text.pack (show (responseBody qpC)) <> Text.pack (show (responseBody ldC))
                  for_ ["the result of", "input 1", "__pm_", "LET"] \g ->
                    (g, g `Text.isInfixOf` text) `shouldBe` (g, False)
      -- The ladder of a rule written as clauses can be far larger than the clauses,
      -- and its plan far larger still (measured: 3,441 nodes, a 325 MB plan in 20 s),
      -- so a rule written as clauses may draw 300 nodes and no more.
      it "answers a clause group that draws exactly 300 nodes" do
        withServiceFromSources "rows-598" [("rule.l4", rowsClauseGroupJL4 598)] \baseUrl mgr -> do
          resp <- queryPlan' baseUrl mgr "rows-598" "rule" (Aeson.object ["arguments" Aeson..= Aeson.object []])
          statusCode' resp `shouldBe` 200
          ld <- getLadder baseUrl mgr "rows-598" "rule"
          statusCode' ld `shouldBe` 200

      it "refuses a clause group that would draw 301, on /query-plan and /ladder, naming why" do
        withServiceFromSources "rows-600" [("rule.l4", rowsClauseGroupJL4 600)] \baseUrl mgr -> do
          resp <- queryPlan' baseUrl mgr "rows-600" "rule" (Aeson.object ["arguments" Aeson..= Aeson.object []])
          statusCode' resp `shouldBe` 400
          LBS.toStrict (responseBody resp) `shouldSatisfy` BS.isInfixOf "more than 300 boxes"
          ld <- getLadder baseUrl mgr "rows-600" "rule"
          statusCode' ld `shouldBe` 400
          LBS.toStrict (responseBody ld) `shouldSatisfy` BS.isInfixOf "more than 300 boxes"

      -- Only the LETs the desugarer generated are read through. A LET the
      -- drafter wrote stays as written, so a chain of LETs that each use the one
      -- before twice (which doubles for each LET when written out) is the one
      -- atom it always was, however long.
      for_ [3 :: Int, 5, 6, 7, 10, 15] \n ->
        it ("answers a chain of " <> show n <> " doubling LETs fast on /query-plan and /ladder, as written") do
          withServiceFromSources "chain" [("rule.l4", letChainJL4 n)] \baseUrl mgr -> do
            resp <- queryPlan' baseUrl mgr "chain" "rule" (Aeson.object ["arguments" Aeson..= Aeson.object []])
            statusCode' resp `shouldBe` 200
            -- the one question is the LET itself, labelled with its text
            LBS.toStrict (responseBody resp) `shouldSatisfy` BS.isInfixOf "LET"
            ld <- getLadder baseUrl mgr "chain" "rule"
            statusCode' ld `shouldBe` 200
            -- the plan embeds the ladder the route serves
            lookupKey "ladder" (decodeObject (responseBody resp)) `shouldBe` (Aeson.decode (responseBody ld) :: Maybe Aeson.Value)

      -- A clause whose result is a LET the drafter wrote: the group around it is
      -- read through, and the LET inside the clause stays as written.
      it "answers a clause group whose clause result is a LET, on /query-plan and /ladder" do
        withServiceFromSources "cg-let-result" [("rule.l4", clauseGroupLetResultJL4)] \baseUrl mgr -> do
          resp <- queryPlan' baseUrl mgr "cg-let-result" "rule" (Aeson.object ["arguments" Aeson..= Aeson.object []])
          statusCode' resp `shouldBe` 200
          -- the colour is asked: the group's CONSIDER is read through
          lookupArrayLength "inputs" (decodeObject (responseBody resp)) `shouldSatisfy` maybe False (> 0)
          ld <- getLadder baseUrl mgr "cg-let-result" "rule"
          statusCode' ld `shouldBe` 200

      sameAsHandWritten "enum" clauseGroupEnumJL4 handEnumJL4
      -- A LET the drafter wrote is not read through: it is answered, as the one
      -- atom it was before clauses were read through.
      it "answers a LET the drafter wrote as written, on /query-plan and /ladder" do
        withServiceFromSources "let-enum" [("rule.l4", letEnumJL4)] \baseUrl mgr -> do
          resp <- queryPlan' baseUrl mgr "let-enum" "rule" (Aeson.object ["arguments" Aeson..= Aeson.object []])
          statusCode' resp `shouldBe` 200
          LBS.toStrict (responseBody resp) `shouldSatisfy` BS.isInfixOf "LET"
          ld <- getLadder baseUrl mgr "let-enum" "rule"
          statusCode' ld `shouldBe` 200
      sameAsHandWritten "mixed" clauseGroupMixedJL4 handMixedJL4
      sameAsHandWritten "single" clauseGroupSingleJL4 handSingleJL4
      -- The hand-written CONSIDER without a GIVETH is itself refused (its type is an
      -- inference variable the service never resolves), so the group without one is
      -- compared with the hand-written rule that has one.
      sameAsHandWritten "nogiveth" clauseGroupNoGivethJL4 handEnumJL4
      sameAsHandWritten "call" clauseGroupCallJL4 handCallJL4
      -- Rows that share an earlier column: the desugarer tests it again in every
      -- later clause, and the ladder reads each test with what the branches
      -- around it already decided.
      sameAsHandWritten "table" clauseTableJL4 handTableJL4
      sameAsHandWritten "table2" clauseTable2JL4 handTable2JL4
      -- A last clause whose pattern is a new name is the OTHERWISE.
      sameAsHandWritten "newname" clauseNewNameJL4 handNewNameJL4

      -- The plans above are compared whole, atomIds included. This compares the
      -- atomIds alone, so that a failure names them, and adds what the whole-plan
      -- compare does not: GET /ladder of both forms, and, within one rule, the
      -- plan's questions among the ladder's atoms. A leaf's atomId is the hash
      -- of its term (R3), and a group is read through to the CONSIDER it stands
      -- for before it is drawn, so each of its leaves is keyed as the
      -- hand-written leaf is.
      let sameAtomIds :: Text -> Text -> Text -> SpecWith ()
          sameAtomIds name clauses hand =
            it (Text.unpack ("names every atom as its hand-written CONSIDER does, on /ladder and /query-plan: " <> name)) do
              withServiceFromSources ("cga-" <> name) [("rule.l4", clauses)] \baseUrl mgr -> do
                withServiceFromSources ("hwa-" <> name) [("rule.l4", hand)] \baseUrl' mgr' -> do
                  let noArguments = Aeson.object ["arguments" Aeson..= Aeson.object []]
                  qpC <- queryPlan' baseUrl mgr ("cga-" <> name) "rule" noArguments
                  qpH <- queryPlan' baseUrl' mgr' ("hwa-" <> name) "rule" noArguments
                  ldC <- getLadder baseUrl mgr ("cga-" <> name) "rule"
                  ldH <- getLadder baseUrl' mgr' ("hwa-" <> name) "rule"
                  for_ [qpC, qpH, ldC, ldH] \r -> statusCode' r `shouldBe` 200
                  let ladderIds r = case lookupKey "funDecl" (decodeObject (responseBody r)) of
                        Just (Aeson.Object fd) -> List.sort (List.nub (ladderAtomIds fd))
                        _ -> []
                      planIds r = case lookupKey "impactByAtomId" (decodeObject (responseBody r)) of
                        Just (Aeson.Object m) -> List.sort (map Aeson.Key.toText (Aeson.KeyMap.keys m))
                        _ -> []
                  -- both are non-empty, so the equalities below mean something
                  ladderIds ldC `shouldSatisfy` (not . null)
                  planIds qpC `shouldSatisfy` (not . null)
                  -- the two forms name their atoms alike, on both routes
                  ladderIds ldC `shouldBe` ladderIds ldH
                  planIds qpC `shouldBe` planIds qpH
                  -- within one rule, every question the plan asks is an atom of
                  -- the ladder the route serves, and the plan embeds that ladder
                  for_ [(qpC, ldC), (qpH, ldH)] \(qp, ld) -> do
                    filter (`notElem` ladderIds ld) (planIds qp) `shouldBe` []
                    lookupKey "ladder" (decodeObject (responseBody qp)) `shouldBe` (Aeson.decode (responseBody ld) :: Maybe Aeson.Value)
      sameAtomIds "enum" clauseGroupEnumJL4 handEnumJL4
      sameAtomIds "mixed" clauseGroupMixedJL4 handMixedJL4
      sameAtomIds "single" clauseGroupSingleJL4 handSingleJL4
      sameAtomIds "nogiveth" clauseGroupNoGivethJL4 handEnumJL4
      sameAtomIds "call" clauseGroupCallJL4 handCallJL4
      sameAtomIds "table" clauseTableJL4 handTableJL4
      sameAtomIds "table2" clauseTable2JL4 handTable2JL4
      sameAtomIds "newname" clauseNewNameJL4 handNewNameJL4

      let noArguments = Aeson.object ["arguments" Aeson..= Aeson.object []]

      -- A restart compiles the stored sources again, as a deploy does (#666), so
      -- a clause group is planned after one as it was when deployed. Before #666
      -- a restart read a cache that kept no type for the generated nodes, and
      -- /query-plan answered 400 for every boolean rule, written as clauses or by
      -- hand. The fresh side must answer 200 with a body, so that two empty
      -- answers cannot pass for equal.
      for_ [ ("enum", clauseGroupEnumJL4), ("mixed", clauseGroupMixedJL4), ("single", clauseGroupSingleJL4)
           , ("nogiveth", clauseGroupNoGivethJL4), ("call", clauseGroupCallJL4), ("table", clauseTableJL4)
           , ("table2", clauseTable2JL4), ("newname", clauseNewNameJL4) ] \(name, src) ->
        it ("restarted: is planned as it was before the restart: " <> name) do
          let probe baseUrl mgr deployId =
                answerOf baseUrl deployId <$> queryPlan' baseUrl mgr deployId "rule" noArguments
          (fresh, restarted) <- beforeAndAfterRestart ("cg-restart-" <> Text.pack name) [("rule.l4", src)] probe
          fst fresh `shouldBe` 200
          snd fresh `shouldSatisfy` Maybe.isJust
          restarted `shouldBe` fresh

      -- Clauses whose CONSIDER, written out, would be more than 20,000 parts are
      -- not read through, and not drawn as the generated LETs either (one leaf
      -- that asks nothing): the answer says why.
      it "refuses clauses that come to more than 20000 parts, naming why" do
        withServiceFromSources "long-rows" [("rule.l4", longClausesJL4 60 200)] \baseUrl mgr -> do
          resp <- queryPlan' baseUrl mgr "long-rows" "rule" noArguments
          statusCode' resp `shouldBe` 400
          LBS.toStrict (responseBody resp) `shouldSatisfy` BS.isInfixOf "too long to draw"
          LBS.toStrict (responseBody resp) `shouldSatisfy` BS.isInfixOf "more than 20000 parts"
      it "says long clauses that return a number are not boolean, not that they are too long" do
        withServiceFromSources "long-num" [("rule.l4", longNumberClausesJL4 60 200)] \baseUrl mgr -> do
          resp <- queryPlan' baseUrl mgr "long-num" "rule" noArguments
          statusCode' resp `shouldBe` 400
          LBS.toStrict (responseBody resp) `shouldSatisfy` BS.isInfixOf "returns a boolean"

      -- A group whose first clause names each of its inputs as the GIVEN does has
      -- nothing to read through: the clauses after it are never reached, and its
      -- body is that clause's result, as a rule written without clauses has it.
      -- A rule written without clauses is planned however long or large its result,
      -- and so is such a group. The service simplifies the ladder, and a disjunction of
      -- conjunctions rewritten into conjunctive normal form grows past 300 boxes
      -- at six pairs of inputs (449 boxes).
      it "catch-all: answers a group whose first clause names each input as the GIVEN does, simplified to 193 boxes" do
        withServiceFromSources "dnf-5" [("rule.l4", dnfClauseJL4 5)] \baseUrl mgr -> do
          resp <- queryPlan' baseUrl mgr "dnf-5" "rule" noArguments
          statusCode' resp `shouldBe` 200
      it "catch-all: answers such a group whose simplified ladder is 449 boxes, as it answers the rule written without clauses" do
        withServiceFromSources "dnf-6" [("rule.l4", dnfClauseJL4 6)] \baseUrl mgr -> do
          withServiceFromSources "hand-dnf-6" [("rule.l4", handDnfJL4 6)] \baseUrl' mgr' -> do
            qpC <- queryPlan' baseUrl mgr "dnf-6" "rule" noArguments
            qpH <- queryPlan' baseUrl' mgr' "hand-dnf-6" "rule" noArguments
            statusCode' qpC `shouldBe` 200
            statusCode' qpH `shouldBe` 200
            let planOf r = withoutNodeIds <$> (Aeson.decode (responseBody r) :: Maybe Aeson.Value)
            planOf qpC `shouldBe` planOf qpH
            lookupArrayLength "inputs" (decodeObject (responseBody qpC)) `shouldSatisfy` maybe False (> 0)
      it "catch-all: answers such a group whose result is more than 20000 parts long, as it answers the rule written without clauses" do
        withServiceFromSources "catchall-huge" [("rule.l4", catchAllHugeJL4)] \baseUrl mgr -> do
          withServiceFromSources "hand-catchall-huge" [("rule.l4", handCatchAllHugeJL4)] \baseUrl' mgr' -> do
            qpC <- queryPlan' baseUrl mgr "catchall-huge" "rule" noArguments
            qpH <- queryPlan' baseUrl' mgr' "hand-catchall-huge" "rule" noArguments
            statusCode' qpC `shouldBe` 200
            statusCode' qpH `shouldBe` 200
            let planOf r = withoutNodeIds <$> (Aeson.decode (responseBody r) :: Maybe Aeson.Value)
            planOf qpC `shouldSatisfy` Maybe.isJust
            planOf qpC `shouldBe` planOf qpH

      -- A first clause that matches every input through a NEW name is not that: it
      -- is a test the desugarer generates, with the clauses after it as the other
      -- answer, so the group is read through and limited like any other. These
      -- pass with and without the guard that exempts the own-name first clause.
      it "new name: refuses a group whose first clause gives an input a new name when its simplified ladder is more than 300 boxes" do
        withServiceFromSources "newname-dnf-6" [("rule.l4", newNameDnfJL4 6)] \baseUrl mgr -> do
          resp <- queryPlan' baseUrl mgr "newname-dnf-6" "rule" noArguments
          statusCode' resp `shouldBe` 400
          LBS.toStrict (responseBody resp) `shouldSatisfy` BS.isInfixOf "more than 300 boxes"
      -- `(EXACTLY n)` for the input's own name is not exempt either: only the bare
      -- name and `_` are, so the desugarer tests it and the group is read through.
      -- Six pairs of it are planned; a first clause of 22,000 parts is refused. (I
      -- infer it reads through to one CONSIDER, which is one box, so that the
      -- 300-box limit is not reached; that is not drawn.)
      it "EXACTLY its own name: plans a group of six pairs, which reads through to one CONSIDER" do
        withServiceFromSources "exactly-dnf-6" [("rule.l4", exactlyNameDnfJL4 6)] \baseUrl mgr -> do
          resp <- queryPlan' baseUrl mgr "exactly-dnf-6" "rule" noArguments
          statusCode' resp `shouldBe` 200
      it "EXACTLY its own name: refuses such a group whose result is more than 20000 parts long" do
        withServiceFromSources "exactly-huge" [("rule.l4", exactlyHugeJL4)] \baseUrl mgr -> do
          resp <- queryPlan' baseUrl mgr "exactly-huge" "rule" noArguments
          statusCode' resp `shouldBe` 400
          LBS.toStrict (responseBody resp) `shouldSatisfy` BS.isInfixOf "too long to draw"
      -- A table of optional inputs taken apart with `JUST`, with new names for the
      -- others, was refused only after a minute (24 clauses): see the same-named
      -- block in ClauseGroupLadderSpec. The wait is far above what it takes now
      -- (about a second) and far below the minute.
      it "new names: refuses a table of 24 clauses of optional inputs taken apart with JUST within seconds" do
        withServiceFromSources "maybe-new-24" [("rule.l4", maybeTableJL4 False 24)] \baseUrl mgr -> do
          answer <- timeout 8_000_000 (queryPlan' baseUrl mgr "maybe-new-24" "rule" noArguments)
          case answer of
            Nothing -> expectationFailure "no answer within 8 seconds"
            Just resp -> do
              statusCode' resp `shouldBe` 400
              LBS.toStrict (responseBody resp) `shouldSatisfy` BS.isInfixOf "too long to draw"
      -- These two are controls: eight clauses are still planned, with either spelling.
      -- On `main` that takes about a second and this test allowed eight. On `unstable`
      -- the same plan takes about 19 s with either spelling (30 s with new names
      -- before `pruneGeneratedConsiders` carried the renaming), because the R3 keying
      -- walks the one 13,500-node leaf that a table of `JUST` patterns reads through
      -- to, several times (measured 2026-10-19 on a 4-core Linux host, with this test
      -- run on `unstable` before the sync). So the wait here is a minute and more,
      -- not eight seconds: it checks that the plan is still produced, not that it
      -- is quick. The 24-clause test above keeps its eight seconds, since it passes
      -- on `unstable` within them. Bring this back to eight when the plan path's cost
      -- on such a table is back near `main`'s.
      it "new names: still plans the same table at 8 clauses, as it plans it with the GIVEN's names" do
        withServiceFromSources "maybe-new-8" [("rule.l4", maybeTableJL4 False 8)] \baseUrl mgr -> do
          withServiceFromSources "maybe-own-8" [("rule.l4", maybeTableJL4 True 8)] \baseUrl' mgr' -> do
            qpN <- timeout 120_000_000 (queryPlan' baseUrl mgr "maybe-new-8" "rule" noArguments)
            qpO <- timeout 120_000_000 (queryPlan' baseUrl' mgr' "maybe-own-8" "rule" noArguments)
            fmap statusCode' qpN `shouldBe` Just 200
            fmap statusCode' qpO `shouldBe` Just 200
      it "new name: answers such a group when its simplified ladder is less than 300 boxes" do
        withServiceFromSources "newname-dnf-5" [("rule.l4", newNameDnfJL4 5)] \baseUrl mgr -> do
          resp <- queryPlan' baseUrl mgr "newname-dnf-5" "rule" noArguments
          statusCode' resp `shouldBe` 200
      it "new name: refuses such a group whose result is more than 20000 parts long" do
        withServiceFromSources "newname-huge" [("rule.l4", newNameHugeJL4)] \baseUrl mgr -> do
          resp <- queryPlan' baseUrl mgr "newname-huge" "rule" noArguments
          statusCode' resp `shouldBe` 400
          LBS.toStrict (responseBody resp) `shouldSatisfy` BS.isInfixOf "too long to draw"
          LBS.toStrict (responseBody resp) `shouldSatisfy` BS.isInfixOf "more than 20000 parts"

    it "and evaluation still works across that restart" do
      -- The control. /evaluation needs no type annotations, so it kept working
      -- throughout; if this ever goes red the restart harness itself is broken,
      -- not the visualization path.
      withServiceRestarted "eval-restart" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "eval-restart" "compute_qualifies"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "walks" Aeson..= True
                , "eats" Aeson..= True
                , "drinks" Aeson..= True
                ]
            ])
        assertSuccess resp \r ->
          Map.lookup "value" r.fnResult `shouldBe` Just (FnLitBool True)

    it "is reachable on the short route too" do
      withServiceFromSources "ladder-short" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/ladder-short/compute_qualifies/ladder")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        lookupKey "funDecl" (decodeObject (responseBody resp)) `shouldSatisfy` Maybe.isJust

    it "returns 400 for a DECIDE that does not return a boolean" do
      withServiceFromSources "ladder-nonbool" [("record.l4", recordJL4)] \baseUrl mgr -> do
        resp <- getLadder baseUrl mgr "ladder-nonbool" "make_person"
        statusCode' resp `shouldBe` 400

    it "refuses a ladder past maxLadderNodes instead of streaming megabytes" do
      -- 32 boolean parameters in a disjunction of conjunctions: four lines of
      -- L4, and a ladder of 2^16 clauses. Unbounded, this route answered 200
      -- and was still streaming past 36 MB five minutes later — on an
      -- unauthenticated GET that a browser will happily prefetch, holding one
      -- of the maxConcurrentRequests slots the whole time. The refusal must be
      -- small and prompt; QueryPlanSpec pins the promptness, this pins that the
      -- route surfaces it rather than swallowing it.
      withServiceFromSources "ladder-huge" [("blowup.l4", dnfBlowupJL4 32)] \baseUrl mgr -> do
        resp <- getLadder baseUrl mgr "ladder-huge" "blowup"
        statusCode' resp `shouldBe` 400
        LBS.length (responseBody resp) `shouldSatisfy` (< 4096)
        qpResp <- queryPlan' baseUrl mgr "ladder-huge" "blowup"
          (Aeson.object ["arguments" Aeson..= Aeson.object []])
        statusCode' qpResp `shouldBe` 400

    it "gives up on a ladder that takes too long to build, rather than holding the slot" do
      -- The node budget bounds the RESPONSE, and cannot bound the BUILD: by the
      -- time it can be consulted, doVisualize has already materialised the whole
      -- normal form. At 64 variables that build does not finish — measured, it
      -- was still going after ten minutes — so without a timeout this request
      -- pins a thread and one of maxConcurrentRequests forever, on a GET a
      -- browser will prefetch. evalTimeout is dropped to 2s here because
      -- testOptions' 60s would make the suite unpleasant; the property is the
      -- same at either value.
      let impatient = testOptions { evalTimeout = 2 }
      withServiceFromSourcesOpts impatient "ladder-slow" [("blowup.l4", dnfBlowupJL4 64)]
        \baseUrl mgr -> do
          started <- getCurrentTime
          resp <- getLadder baseUrl mgr "ladder-slow" "blowup"
          finished <- getCurrentTime
          statusCode' resp `shouldBe` 500
          diffUTCTime finished started `shouldSatisfy` (< 30)

    it "returns 404 for unknown function" do
      withServiceFromSources "ladder-404" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        resp <- getLadder baseUrl mgr "ladder-404" "no_such_fn"
        statusCode' resp `shouldBe` 404

    it "returns 404 for unknown deployment" do
      withEmptyService \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/deployments/nope/functions/compute_qualifies/ladder")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 404

    it "ladder atomIds ARE the query-plan's atomIds (smucclaw/l4-ide#935)" do
      -- Was a characterisation test pinning the disagreement, with a note to
      -- invert it when the two surfaces were reconciled. This is that inversion.
      --
      -- The gap, then: the ladder hashed each input ref as its numeric
      -- rootUnique over the atom's DIRECT ref set, while
      -- L4.Decision.QueryPlan.atomIdByUnique hashed it as the ref's LABEL over
      -- the TRANSITIVE closure. The ids therefore disagreed for every atom with
      -- a non-empty ref set — which is every ordinary leaf — so a client could
      -- not join `ladder` leaves to `impactByAtomId`, and a binding keyed by a
      -- ladder atomId was accepted with a 200 and quietly did nothing.
      -- Both now hash the leaf's C1 term key, which the ladder records once and
      -- the plan reads (R3, smucclaw/l4-ide#1013), so they agree by construction;
      -- this test is what says so.
      withServiceFromSources "ladder-atomids" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        qpResp <- queryPlan' baseUrl mgr "ladder-atomids" "compute_qualifies"
          (Aeson.object ["arguments" Aeson..= Aeson.object []])
        statusCode' qpResp `shouldBe` 200
        let body = decodeObject (responseBody qpResp)
            planIds = case lookupKey "impactByAtomId" body of
              Just (Aeson.Object m) -> map Aeson.Key.toText (Aeson.KeyMap.keys m)
              _ -> []
            ladderIds = case lookupKey "ladder" body of
              Just (Aeson.Object l) -> case Aeson.KeyMap.lookup "funDecl" l of
                Just (Aeson.Object fd) -> ladderAtomIds fd
                _ -> []
              _ -> []
        -- Both sides are non-empty, so the equality below is meaningful.
        planIds `shouldSatisfy` (not . null)
        ladderIds `shouldSatisfy` (not . null)
        List.sort (List.nub planIds) `shouldBe` List.sort (List.nub ladderIds)

    it "the GET /ladder atomIds match the POST /query-plan atomIds" do
      -- #935 was measured across the two ROUTES, not within one response, so
      -- pin it that way too: a client that fetches the diagram once and then
      -- posts answers is joining two HTTP responses.
      withServiceFromSources "ladder-atomids-2routes" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        ladResp <- getLadder baseUrl mgr "ladder-atomids-2routes" "compute_qualifies"
        statusCode' ladResp `shouldBe` 200
        let getIds = case lookupKey "funDecl" (decodeObject (responseBody ladResp)) of
              Just (Aeson.Object fd) -> ladderAtomIds fd
              _ -> []
        qpResp <- queryPlan' baseUrl mgr "ladder-atomids-2routes" "compute_qualifies"
          (Aeson.object ["arguments" Aeson..= Aeson.object []])
        let planIds = case lookupKey "impactByAtomId" (decodeObject (responseBody qpResp)) of
              Just (Aeson.Object m) -> map Aeson.Key.toText (Aeson.KeyMap.keys m)
              _ -> []
        getIds `shouldSatisfy` (not . null)
        List.sort (List.nub getIds) `shouldBe` List.sort (List.nub planIds)

    it "a binding keyed by a ladder atomId MOVES the decision, and reaches every twin" do
      -- The end-to-end claim of #935, stated as a value rather than a type: read
      -- the atomId off GET /ladder, post it as a binding, and watch `determined`
      -- change. Before the fix this route returned 200 with `determined` still
      -- null — the silent no-op the issue reports.
      --
      -- The fixture's atom appears TWICE (see 'twinLeavesJL4'), and only binding
      -- BOTH occurrences settles the decision, so this also pins that the
      -- atomId -> unique inversion in L4.Decision.QueryPlan is one-to-many
      -- rather than last-wins.
      withServiceFromSources "ladder-atomid-binds" [("twins.l4", twinLeavesJL4)] \baseUrl mgr -> do
        ladResp <- getLadder baseUrl mgr "ladder-atomid-binds" "twins"
        statusCode' ladResp `shouldBe` 200
        -- A twin is one atomId held by two different uniques; a bare input
        -- drawn twice keeps its one unique and is not one (and under
        -- simplification the inputs are drawn twice too).
        let atoms = case lookupKey "funDecl" (decodeObject (responseBody ladResp)) of
              Just (Aeson.Object fd) -> ladderLeafAtoms fd
              _ -> []
            twins =
              [ a
              | (a, us) <- Map.toList (Map.fromListWith (<>) [(a, [u]) | (a, u) <- atoms])
              , length (List.nub us) >= 2
              ]
        -- Guard: without a genuine twin the binding assertion would pass for the
        -- wrong reason.
        twinId <- case twins of
          [] -> fail "the ladder carries no duplicated atomId"
          (t : _) -> pure t
        unbound <- queryPlan' baseUrl mgr "ladder-atomid-binds" "twins"
          (Aeson.object ["arguments" Aeson..= Aeson.object []])
        lookupKey "determined" (decodeObject (responseBody unbound)) `shouldBe` Just Aeson.Null
        bound <- queryPlan' baseUrl mgr "ladder-atomid-binds" "twins"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ Aeson.Key.fromText twinId Aeson..= False ]
            ])
        statusCode' bound `shouldBe` 200
        lookupKey "determined" (decodeObject (responseBody bound)) `shouldBe` Just (Aeson.Bool False)

  -- A deployment outlives the process that compiled it. On restart the service
  -- compiles the stored sources again, as a deploy does. Everything below asks
  -- one question of one deployment, once on the freshly compiled functions and
  -- once on a service that came back from the store, and wants the same answer.
  describe "after a restart" do
    it "answers query-plan for a boolean rule as it did before the restart" do
      let asks =
            [ Aeson.object ["arguments" Aeson..= Aeson.object []]
            , Aeson.object
                [ "arguments" Aeson..= Aeson.object
                    [ "walks" Aeson..= True
                    , "eats" Aeson..= True
                    , "drinks" Aeson..= True
                    ]
                ]
            ]
          probe baseUrl mgr deployId = forM asks \ask ->
            answerOf baseUrl deployId <$> queryPlan' baseUrl mgr deployId "compute_qualifies" ask
      (fresh, restarted) <- beforeAndAfterRestart "qp-restart-same" [("qualifies.l4", qualifiesJL4)] probe
      map fst fresh `shouldBe` [200, 200]
      restarted `shouldBe` fresh

    it "answers query-plan for a rule that decodes JSON as it did before the restart" do
      -- The call smucclaw/l4-ide#1040 measures: 200 before the restart, 400 after.
      let probe baseUrl mgr deployId =
            answerOf baseUrl deployId <$> queryPlan' baseUrl mgr deployId "is%20a%20person"
              (Aeson.object ["arguments" Aeson..= Aeson.object []])
      (fresh, restarted) <- beforeAndAfterRestart "qp-decode-restart" [("person.l4", jsonDecodePersonJL4)] probe
      fst fresh `shouldBe` 200
      restarted `shouldBe` fresh

    it "decodes JSON into a record as it did before the restart" do
      -- The seven requests of smucclaw/l4-ide#1040, in its order. The names are
      -- percent-encoded because they go straight into the URL.
      let cases =
            [ ("age%20next%20year", "{\"name\":\"Alice\",\"age\":40}")
            , ("age%20next%20year", "{\"name\":\"Alice\",\"age\":\"forty\"}")
            , ("is%20a%20person", "{\"name\":\"Alice\",\"age\":40}")
            , ("is%20a%20person", "{\"name\":\"Alice\",\"age\":\"forty\"}")
            , ("is%20a%20person", "{\"foo\":1}")
            , ("is%20a%20person", "[1,2]")
            , ("is%20a%20person", "not json")
            ]
          probe baseUrl mgr deployId = forM cases \(fnName, json) -> do
            resp <- evalFunction baseUrl mgr deployId fnName
              (Aeson.object ["arguments" Aeson..= Aeson.object ["json" Aeson..= (json :: Text)]])
            let (status, body) = answerOf baseUrl deployId resp
                contents = do
                  Aeson.Object c <- lookupKey "contents" (body >>= asObject)
                  pure c
                result = resultValue body
                -- {"tag": "Error", "contents": {"tag": "InterpreterError", "contents": "..."}}
                message = Aeson.KeyMap.lookup "contents" =<< contents
            pure (fnName, json, status, result, message)
      (fresh, restarted) <- beforeAndAfterRestart "decode-restart" [("person.l4", jsonDecodePersonJL4)] probe
      -- What the answers should be, so that "the same as before" cannot be
      -- satisfied by two runs that are wrong in the same way.
      [(status, result) | (_, _, status, result, _) <- fresh] `shouldBe`
        [ (200, Just (Aeson.Number 41))
        , (422, Nothing)
        , (200, Just (Aeson.Bool True))
        , (422, Nothing)
        , (422, Nothing)
        , (422, Nothing)
        , (200, Just (Aeson.Bool False))
        ]
      -- The inputs whose answer, message included, changed across the restart.
      [(f, r) | (f, r) <- zip fresh restarted, f /= r] `shouldBe` []

    it "evaluates and describes functions as it did before the restart" do
      -- The control. /evaluation needs no type annotations, so it kept working
      -- throughout; if this goes red the restart harness itself is broken, not
      -- the visualization or decoding paths.
      let probe baseUrl mgr deployId = do
            evalResp <- evalFunction baseUrl mgr deployId "compute_qualifies"
              (Aeson.object
                [ "arguments" Aeson..= Aeson.object
                    [ "walks" Aeson..= True
                    , "eats" Aeson..= True
                    , "drinks" Aeson..= True
                    ]
                ])
            detailsResp <- httpGet mgr (baseUrl <> "/deployments/" <> Text.unpack deployId <> "/functions/compute_qualifies")
            listResp <- httpGet mgr (baseUrl <> "/deployments/" <> Text.unpack deployId <> "/functions")
            pure (map (answerOf baseUrl deployId) [evalResp, detailsResp, listResp])
      (fresh, restarted) <- beforeAndAfterRestart "ctl-restart" [("qualifies.l4", qualifiesJL4)] probe
      map fst fresh `shouldBe` [200, 200, 200]
      restarted `shouldBe` fresh

    it "reads a record input declared in an imported file as it did before the restart" do
      let probe baseUrl mgr deployId = do
            resp <- evalFunction baseUrl mgr deployId "applicant-is-an-adult"
              (Aeson.object
                [ "arguments" Aeson..= Aeson.object
                    [ "applicant" Aeson..= Aeson.object
                        [ "name" Aeson..= ("Alice" :: Text)
                        , "age" Aeson..= (30 :: Int)
                        ]
                    ]
                ])
            pure (answerOf baseUrl deployId resp)
      (fresh, restarted) <- beforeAndAfterRestart "record-restart"
        [ ("imported_record_decl.l4", importedRecordDeclJL4)
        , ("imported_record_main.l4", importedRecordMainJL4)
        ] probe
      resultValue (snd fresh) `shouldBe` Just (Aeson.Bool True)
      restarted `shouldBe` fresh

    it "words the error for an input no clause matches as it did before the restart" do
      -- review of legalese/l4-ide#545: a rule written as clauses words its
      -- run-time error from a mark on the CONSIDERs the clauses compile to.
      let probe baseUrl mgr deployId =
            answerOf baseUrl deployId <$> evalFunction baseUrl mgr deployId "price"
              (Aeson.object ["arguments" Aeson..= Aeson.object ["c" Aeson..= ("Blue" :: Text)]])
      (fresh, restarted) <- beforeAndAfterRestart "clauses-restart" [("price.l4", partialClausesJL4)] probe
      show fresh `shouldSatisfy` ("No clause of `price` matches these inputs." `Text.isInfixOf`) . Text.pack
      restarted `shouldBe` fresh

    it "describes a function, and its fields, as it did before the restart" do
      -- The schema is built from the DECLAREs, whose @desc text sits on
      -- annotations that a cache of the checked module did not keep.
      let probe baseUrl mgr deployId = do
            let url path = baseUrl <> "/deployments/" <> Text.unpack deployId <> path
            openapi <- httpGet mgr (url "/openapi.json")
            details <- httpGet mgr (url "/functions/disclosure")
            list <- httpGet mgr (url "/functions")
            -- The document's version is the deployment's, which a test that
            -- registers its functions directly never gave one.
            let withoutInfo (status, body) = (status, withoutKey "info" <$> body)
                withoutKey k (Aeson.Object o) = Aeson.Object (Aeson.KeyMap.delete (Aeson.Key.fromText k) o)
                withoutKey _ v = v
            pure
              [ withoutInfo (answerOf baseUrl deployId openapi)
              , answerOf baseUrl deployId details
              , answerOf baseUrl deployId list
              ]
      (fresh, restarted) <- beforeAndAfterRestart "schema-restart" [("taxpayer.l4", taxpayerJL4)] probe
      map fst fresh `shouldBe` [200, 200, 200]
      -- the descriptions are there to be lost: the OpenAPI document and the
      -- function's own page carry them (the list of functions does not)
      forM_ (take 2 (map snd fresh)) \body ->
        show body `shouldSatisfy` ("Income earned abroad, if any" `Text.isInfixOf`) . Text.pack
      restarted `shouldBe` fresh

    it "lists an input the module never declared as it did before the restart" do
      -- The deploy turns a name the type checker finds out of scope into an
      -- input, from the type checker's errors, which a cache of the checked
      -- module did not hold. (Calling `above` answers "flag is not in scope"
      -- on a fresh deploy too, so only the listing is compared.)
      let probe baseUrl mgr deployId =
            answerOf baseUrl deployId <$> httpGet mgr (baseUrl <> "/deployments/" <> Text.unpack deployId <> "/functions/above")
      (fresh, restarted) <- beforeAndAfterRestart "implicit-restart" [("flag.l4", implicitFlagJL4)] probe
      fst fresh `shouldBe` 200
      show fresh `shouldSatisfy` ("flag" `Text.isInfixOf`) . Text.pack
      restarted `shouldBe` fresh

    it "serves a function added to a stored file, as a deploy of the edited files would" do
      -- A restart used to take the list of files that had functions from its
      -- cache, so a function added to any other file never appeared.
      let helper = Text.unlines ["GIVEN n IS A NUMBER", "GIVETH A BOOLEAN", "DECIDE big IF n > 10"]
          deployments = [("grown", [("qualifies.l4", qualifiesJL4), ("helper.l4", helper)])]
          export = editSource "grown" "helper.l4" ("@export Whether a number is big\n" <>)
      withServicesRestarted deployments export \_logLines baseUrl mgr -> do
        listed <- httpGet mgr (baseUrl <> "/deployments/grown/functions")
        functionNames (responseBody listed) `shouldBe` ["big", "compute_qualifies"]
        resp <- evalFunction baseUrl mgr "grown" "big" (Aeson.object ["arguments" Aeson..= Aeson.object ["n" Aeson..= (11 :: Int)]])
        assertSuccess resp \r ->
          Map.lookup "value" r.fnResult `shouldBe` Just (FnLitBool True)

    it "ignores a bundle.cbor that an older build left, and leaves it where it is" do
      -- Older builds kept a cache of the checked module beside the sources and
      -- started from it. This one compiles the sources and does not read it, so
      -- what is in the file changes nothing; and the file is not touched, so a
      -- rollback to a build that reads it finds it as it was.
      storeDir <- newIORef ""
      let oldCache = "what an older build wrote"
          leave dir = do
            writeIORef storeDir dir
            Text.IO.writeFile (dir </> "old" </> "bundle.cbor") oldCache
      withServicesRestarted [("old", [("qualifies.l4", qualifiesJL4)])] leave \logLines baseUrl mgr -> do
        assertRecompiled "old" logLines
        [m | m <- messagesAbout "old" logLines, "cbor" `Text.isInfixOf` Text.toLower m] `shouldBe` []
        resp <- evalFunction baseUrl mgr "old" "compute_qualifies" allTrueArgs
        assertSuccess resp \r ->
          Map.lookup "value" r.fnResult `shouldBe` Just (FnLitBool True)
        dir <- readIORef storeDir
        Text.IO.readFile (dir </> "old" </> "bundle.cbor") `shouldReturn` oldCache

    it "serves a function that calls sum from a store whose cache holds the standard library at its old address" do
      -- bundle.cbor in the fixture directory was written by a service built from
      -- main before library resolution changed (00298eb60): it holds the
      -- prelude at `file://prelude.l4`, 1,084 times, and never at
      -- `jl4-embedded:`. A build that read it paired it with a library
      -- environment at the new address, and every library function, `sum`
      -- among them, was "not in scope" at call time. This build compiles the
      -- sources and reads no cache, so the function answers, and the file is
      -- left as it was.
      let fixtureDir = "test/fixtures/old-prelude-cache"
      here <- doesFileExist (fixtureDir </> "bundle.cbor")
      let dirOfFixture = if here then fixtureDir else "jl4-service" </> fixtureDir
      oldCache <- BS.readFile (dirOfFixture </> "bundle.cbor")
      total <- Text.IO.readFile (dirOfFixture </> "total.l4")
      storeDir <- newIORef ""
      let plant dir = do
            writeIORef storeDir dir
            BS.writeFile (dir </> "oldsum" </> "bundle.cbor") oldCache
      withServicesRestarted [("oldsum", [("total.l4", total)])] plant \logLines baseUrl mgr -> do
        assertRecompiled "oldsum" logLines
        resp <- evalFunction baseUrl mgr "oldsum" "total"
          (Aeson.object ["arguments" Aeson..= Aeson.object ["xs" Aeson..= ([1, 2, 3] :: [Int])]])
        assertSuccess resp \r ->
          Map.lookup "value" r.fnResult `shouldBe` Just (FnLitInt 6)
        dir <- readIORef storeDir
        BS.readFile (dir </> "oldsum" </> "bundle.cbor") `shouldReturn` oldCache

    it "compiles a restarted deployment under --compile-timeout, as a deploy does" do
      -- A timeout of zero is over before the compile starts. A restart that
      -- read a cache instead did not compile, and so was not subject to it.
      withServicesRestartedOpts testOptions {compileTimeout = 0}
        [("slow", [("qualifies.l4", qualifiesJL4)])] (const (pure ())) \logLines baseUrl mgr -> do
          status <- deploymentStatus baseUrl mgr "slow"
          fmap (.dsStatus) status `shouldBe` Just "failed"
          messagesAbout "slow" logLines `shouldContain` ["Compilation timed out or exceeded memory limit"]

    describe "when compiling a stored deployment throws" do
      -- A source whose inputs collide once their names are sanitised
      -- (`a b` and `a-b`) makes the compiler raise an error rather than refuse
      -- it. The service loads every deployment of the store before it listens,
      -- so one of them must not stop it: the deployment is failed, with the
      -- reason, and the others load.
      let deployments = [("fine", [("qualifies.l4", qualifiesJL4)]), ("clash", [("clash.l4", nameClashJL4)])]
      it "fails that deployment and loads the others when the store is loaded eagerly" do
        withServicesRestarted deployments (const (pure ())) \logLines baseUrl mgr -> do
          status <- deploymentStatus baseUrl mgr "clash"
          fmap (.dsStatus) status `shouldBe` Just "failed"
          fmap (.dsError) status `shouldSatisfy` maybe False (maybe False ("collision after sanitization" `Text.isInfixOf`))
          messagesAbout "clash" logLines `shouldContain` ["Deployment failed"]
          fineStatus <- deploymentStatus baseUrl mgr "fine"
          fmap (.dsStatus) fineStatus `shouldBe` Just "ready"
          resp <- evalFunction baseUrl mgr "fine" "compute_qualifies" allTrueArgs
          assertSuccess resp \r ->
            Map.lookup "value" r.fnResult `shouldBe` Just (FnLitBool True)

      it "fails it, with the reason, when the store is loaded lazily" do
        withPendingService "clash-lazy" [("clash.l4", nameClashJL4)] \baseUrl mgr -> do
          resp <- evalFunction baseUrl mgr "clash-lazy" "clash" (Aeson.object ["arguments" Aeson..= Aeson.object []])
          statusCode' resp `shouldSatisfy` (>= 500)
          status <- deploymentStatus baseUrl mgr "clash-lazy"
          fmap (.dsStatus) status `shouldBe` Just "failed"
          fmap (.dsError) status `shouldSatisfy` maybe False (maybe False ("collision after sanitization" `Text.isInfixOf`))

    describe "when the stored sources no longer check" do
      -- The sources on disk are what the operator last deployed, but they are
      -- only files. A restart compiles what they are now: if that does not
      -- parse or type-check, the deployment is failed, with the errors a deploy
      -- of those sources would get and a warning that names the file and prints
      -- them, and the others in the store load as usual.
      let deployments =
            [ ("kept", [("qualifies.l4", qualifiesJL4)])
            , ("edited", [("qualifies.l4", qualifiesJL4)])
            ]
          -- @mention@ is something the errors must say: what a deploy of the
          -- edited source would be told, and what the warning prints.
          refusesTheEdit label edit mention =
            it label do
              withServicesRestarted deployments (editSource "edited" "qualifies.l4" edit) \logLines baseUrl mgr -> do
                status <- deploymentStatus baseUrl mgr "edited"
                fmap (.dsStatus) status `shouldBe` Just "failed"
                -- the reason is given
                fmap (.dsError) status `shouldSatisfy` maybe False (maybe False (mention `Text.isInfixOf`))
                -- the log prints it, naming the file
                errorsLoggedFor "edited" "qualifies.l4" logLines `shouldSatisfy` any (mention `Text.isInfixOf`)
                -- and nothing is served
                resp <- evalFunction baseUrl mgr "edited" "compute_qualifies" allTrueArgs
                statusCode' resp `shouldBe` 500
                -- the other deployment is not affected
                keptStatus <- deploymentStatus baseUrl mgr "kept"
                fmap (.dsStatus) keptStatus `shouldBe` Just "ready"
                keptResp <- evalFunction baseUrl mgr "kept" "compute_qualifies" allTrueArgs
                assertSuccess keptResp \r ->
                  Map.lookup "value" r.fnResult `shouldBe` Just (FnLitBool True)
      refusesTheEdit "fails a deployment whose stored source has a type error"
        (Text.replace "walks AND eats AND drinks" "walks AND eats AND 5")
        "is expected to be of type"
      refusesTheEdit "fails a deployment whose stored source does not parse"
        (<> "\nDECIDE ( IS\n")
        "unexpected ("

    describe "when the stored sources hold a name that begins with a known annotation" do
      -- `@descr x` is `@desc` with the text "r x", and `@nlgg x` is `@nlg` with
      -- "g x": the lexer has always read a name that begins with a known one as
      -- that annotation, and still does, so a deployment stored with one comes
      -- up after a restart as it did, and nothing is logged as ignored. (A line
      -- the lexer IGNORES, which it used to refuse, cannot be in a store: see
      -- "an annotation this version ignores".)
      let deployments =
            [ ("kept", [("qualifies.l4", qualifiesJL4)])
            , ("edited", [("qualifies.l4", qualifiesJL4)])
            , ("twice", [("qualifies.l4", qualifiesJL4)])
            ]
          edits dir = do
            editSource "edited" "qualifies.l4" ("@descr a longer description\n" <>) dir
            editSource "twice" "qualifies.l4" (Text.replace "drinks IS A BOOLEAN" "drinks IS A BOOLEAN @nlgg whether they drink") dir
      it "loads the deployments and serves their functions" do
        withServicesRestarted deployments edits
          \logLines baseUrl mgr -> do
            forM_ ["edited", "twice"] \deployId -> do
              status <- deploymentStatus baseUrl mgr deployId
              fmap (.dsStatus) status `shouldBe` Just "ready"
              resp <- evalFunction baseUrl mgr deployId "compute_qualifies" allTrueArgs
              assertSuccess resp \r ->
                Map.lookup "value" r.fnResult `shouldBe` Just (FnLitBool True)
              ignoredLoggedFor deployId "qualifies.l4" logLines `shouldBe` []

    it "answers a record input as before when an edit shifts the numbering of the types" do
      -- The stored sources are re-checked, and the record's type is found by
      -- its Unique, which is the position of its DECLARE in the file. Add a
      -- DECLARE above it and every Unique after it moves.
      let call baseUrl mgr deployId = do
            resp <- evalFunction baseUrl mgr deployId "disclosure"
              (Aeson.object
                [ "arguments" Aeson..= Aeson.object
                    [ "tp" Aeson..= Aeson.object
                        [ "name" Aeson..= ("Alice" :: Text)
                        , "income" Aeson..= (20000 :: Int)
                        ]
                    ]
                ])
            pure (answerOf baseUrl deployId resp)
      fresh <- withServiceFromSources "shift-fresh" [("taxpayer.l4", taxpayerJL4)] \baseUrl mgr ->
        call baseUrl mgr "shift-fresh"
      fst fresh `shouldBe` 200
      restarted <- withServicesRestarted [("shifted", [("taxpayer.l4", taxpayerJL4)])]
        (editSource "shifted" "taxpayer.l4" ("DECLARE Shift HAS\n    sx IS A NUMBER\n\n" <>))
        \_logLines baseUrl mgr -> call baseUrl mgr "shifted"
      -- the same answer, or none, and never "not a known record"
      restarted `shouldBe` fresh

  describe "evaluation with trace" do
    it "includes reasoning when trace=full" do
      withServiceFromSources "trace-full" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        req <- buildJsonPost
          (baseUrl <> "/deployments/trace-full/functions/compute_qualifies/evaluation?trace=full")
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "walks" Aeson..= True
                , "eats" Aeson..= True
                , "drinks" Aeson..= True
                ]
            ])
        resp <- httpLbs req mgr
        assertSuccess resp \r -> do
          -- trace=full should produce a non-trivial reasoning tree
          let ResponseWithReason{reasoning = tree} = r
          isEmptyReasoning tree `shouldBe` False

    -- `exampleCode` is source: it prints a string literal as the source
    -- spells it, a line break as \n and a tab as \t. #595 changed that from a
    -- raw line break, and with it `l4 run`'s trace text and `l4 trace`.
    -- `explanation` of a plain string result prints a VALUE, and keeps the line
    -- break; one that prints rule source, such as a DEONTIC contract, is escaped.
    -- Ruled 2026-10-12 (bench "Main Wave Rulings", card R2, option A): the
    -- escaped form stays on every surface; recorded in
    -- specs/done/BATCH-PROCESSING-SPEC.md.
    it "spells a string literal in exampleCode as source, and keeps the line break in explanation" do
      withServiceFromSources "trace-line-break" [("line-break.l4", lineBreakJL4)] \baseUrl mgr -> do
        req <- buildJsonPost
          (baseUrl <> "/deployments/trace-line-break/functions/s/evaluation?trace=full")
          (Aeson.object [ "arguments" Aeson..= Aeson.object [ "x" Aeson..= (1 :: Int) ] ])
        resp <- httpLbs req mgr
        assertSuccess resp \r -> do
          let ResponseWithReason{reasoning = tree} = r
              nodes t = t : concatMap nodes t.children
              code = concatMap (.exampleCode) (nodes tree)
              explained = concatMap (.explanation) (nodes tree)
          -- the literal is in the tree at all, spelled with a backslash and an n
          code `shouldSatisfy` any (Text.isInfixOf "\"line\\nnext\"")
          -- and no step of the code holds a raw line break
          code `shouldSatisfy` all (not . Text.isInfixOf "\n")
          -- the value's own print keeps the break
          explained `shouldSatisfy` any (Text.isInfixOf "\"line\nnext\"")

    it "includes graphviz DOT when trace=full and graphviz=true" do
      withServiceFromSources "trace-gv" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        req <- buildJsonPost
          (baseUrl <> "/deployments/trace-gv/functions/compute_qualifies/evaluation?trace=full&graphviz=true")
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "walks" Aeson..= True
                , "eats" Aeson..= True
                , "drinks" Aeson..= True
                ]
            ])
        resp <- httpLbs req mgr
        assertSuccess resp \r ->
          case r.graphviz of
            Just gv ->
              gv.dot `shouldSatisfy` Text.isInfixOf "digraph"
            Nothing ->
              expectationFailure "Expected graphviz to be present with trace=full&graphviz=true"

    it "omits graphviz when trace=none" do
      withServiceFromSources "trace-none" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        req <- buildJsonPost
          (baseUrl <> "/deployments/trace-none/functions/compute_qualifies/evaluation?trace=none")
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "walks" Aeson..= True
                , "eats" Aeson..= True
                , "drinks" Aeson..= True
                ]
            ])
        resp <- httpLbs req mgr
        assertSuccess resp \r ->
          r.graphviz `shouldBe` Nothing

  describe "function details and metadata" do
    it "returns function schema via GET" do
      withServiceFromSources "fn-details" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/deployments/fn-details/functions/compute_qualifies")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        let body = decodeObject (responseBody resp)
        -- FunctionSummary has name, parameters, returnType
        lookupKey "name" body `shouldBe` Just (Aeson.String "compute_qualifies")
        lookupKey "returnType" body `shouldSatisfy` Maybe.isJust

    -- The function-schema endpoint is the single source of truth for chat-side
    -- render metadata: it must surface "x-l4-type" recursively on record/enum
    -- nodes plus a full structured "returnSchema" so the chat can render
    -- arguments and results back into L4 syntax.
    it "function-schema endpoint surfaces x-l4-type and returnSchema for record types" do
      withServiceFromSources "fn-render-meta" [("record.l4", recordJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/deployments/fn-render-meta/functions/make_person")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        let body = decodeObject (responseBody resp)
        -- returnSchema present and tagged with the L4 record name
        case lookupKey "returnSchema" body of
          Just (Aeson.Object rs) -> do
            Aeson.KeyMap.lookup "x-l4-type" rs `shouldBe` Just (Aeson.String "Person")
            Aeson.KeyMap.lookup "type" rs `shouldBe` Just (Aeson.String "object")
          other ->
            expectationFailure ("Expected returnSchema object with x-l4-type, got: " <> show other)

    it "OpenAPI spec strips x-l4-type so the LLM-facing surface stays byte-clean" do
      withServiceFromSources "no-l4ext-openapi" [("record.l4", recordJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/deployments/no-l4ext-openapi/openapi.json")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        let bs = LBS.toStrict (responseBody resp)
        BS.isInfixOf "x-l4-type" bs `shouldBe` False

    it "MCP tools/list strips x-l4-type from inputSchema" do
      withServiceFromSources "no-l4ext-mcp" [("record.l4", recordJL4)] \baseUrl mgr -> do
        let mcpReq = Aeson.object
              [ "jsonrpc" Aeson..= ("2.0" :: Text)
              , "id" Aeson..= (1 :: Int)
              , "method" Aeson..= ("tools/list" :: Text)
              ]
        req <- buildJsonPost (baseUrl <> "/.mcp") mcpReq
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        let bs = LBS.toStrict (responseBody resp)
        BS.isInfixOf "x-l4-type" bs `shouldBe` False

    -- ------------------------------------------------------------------------
    -- MCP 2026-07-28 spec migration: version negotiation, stateless model,
    -- Tasks extension surface. Tasks lifecycle against a real slow-compile
    -- is covered by the out-of-tree smoke test client.
    -- ------------------------------------------------------------------------

    it "MCP initialize echoes 2026-07-28 when client requests it" do
      withServiceFromSources "mcp-init-new" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        let mcpReq = Aeson.object
              [ "jsonrpc" Aeson..= ("2.0" :: Text)
              , "id" Aeson..= (1 :: Int)
              , "method" Aeson..= ("initialize" :: Text)
              , "params" Aeson..= Aeson.object
                  [ "protocolVersion" Aeson..= ("2026-07-28" :: Text) ]
              ]
        req <- buildJsonPost (baseUrl <> "/.mcp") mcpReq
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        let body = decodeObject (responseBody resp)
        case lookupKey "result" body of
          Just (Aeson.Object res) ->
            Aeson.KeyMap.lookup "protocolVersion" res
              `shouldBe` Just (Aeson.String "2026-07-28")
          _ -> expectationFailure "Missing result object"

    it "MCP initialize echoes legacy 2025-03-26 for old clients" do
      withServiceFromSources "mcp-init-old" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        let mcpReq = Aeson.object
              [ "jsonrpc" Aeson..= ("2.0" :: Text)
              , "id" Aeson..= (1 :: Int)
              , "method" Aeson..= ("initialize" :: Text)
              , "params" Aeson..= Aeson.object
                  [ "protocolVersion" Aeson..= ("2025-03-26" :: Text) ]
              ]
        req <- buildJsonPost (baseUrl <> "/.mcp") mcpReq
        resp <- httpLbs req mgr
        let body = decodeObject (responseBody resp)
        case lookupKey "result" body of
          Just (Aeson.Object res) ->
            Aeson.KeyMap.lookup "protocolVersion" res
              `shouldBe` Just (Aeson.String "2025-03-26")
          _ -> expectationFailure "Missing result object"

    it "MCP initialize defaults to latest when client sends unknown version" do
      withServiceFromSources "mcp-init-unknown" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        let mcpReq = Aeson.object
              [ "jsonrpc" Aeson..= ("2.0" :: Text)
              , "id" Aeson..= (1 :: Int)
              , "method" Aeson..= ("initialize" :: Text)
              , "params" Aeson..= Aeson.object
                  [ "protocolVersion" Aeson..= ("9999-99-99" :: Text) ]
              ]
        req <- buildJsonPost (baseUrl <> "/.mcp") mcpReq
        resp <- httpLbs req mgr
        let body = decodeObject (responseBody resp)
        case lookupKey "result" body of
          Just (Aeson.Object res) ->
            Aeson.KeyMap.lookup "protocolVersion" res
              `shouldBe` Just (Aeson.String "2026-07-28")
          _ -> expectationFailure "Missing result object"

    it "MCP initialize advertises Tasks extension under both namespaces" do
      withServiceFromSources "mcp-init-caps" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        let mcpReq = Aeson.object
              [ "jsonrpc" Aeson..= ("2.0" :: Text)
              , "id" Aeson..= (1 :: Int)
              , "method" Aeson..= ("initialize" :: Text)
              ]
        req <- buildJsonPost (baseUrl <> "/.mcp") mcpReq
        resp <- httpLbs req mgr
        let bs = LBS.toStrict (responseBody resp)
        BS.isInfixOf "io.modelcontextprotocol/tasks" bs `shouldBe` True
        BS.isInfixOf "ext-tasks" bs `shouldBe` True

    it "MCP server is stateless: tools/list works without prior initialize" do
      -- Two cold POSTs back-to-back, no initialize between them. The new
      -- stateless model says this MUST work; a server that maintained
      -- session state would 4xx the second call.
      withServiceFromSources "mcp-stateless" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        let listReq = Aeson.object
              [ "jsonrpc" Aeson..= ("2.0" :: Text)
              , "id" Aeson..= (1 :: Int)
              , "method" Aeson..= ("tools/list" :: Text)
              ]
        r1 <- buildJsonPost (baseUrl <> "/.mcp") listReq >>= flip httpLbs mgr
        r2 <- buildJsonPost (baseUrl <> "/.mcp") listReq >>= flip httpLbs mgr
        statusCode' r1 `shouldBe` 200
        statusCode' r2 `shouldBe` 200
        responseBody r1 `shouldBe` responseBody r2

    it "MCP tools/list accepts _meta.io.modelcontextprotocol/clientInfo" do
      withServiceFromSources "mcp-clientinfo" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        let mcpReq = Aeson.object
              [ "jsonrpc" Aeson..= ("2.0" :: Text)
              , "id" Aeson..= (1 :: Int)
              , "method" Aeson..= ("tools/list" :: Text)
              , "params" Aeson..= Aeson.object
                  [ "_meta" Aeson..= Aeson.object
                      [ "io.modelcontextprotocol/clientInfo" Aeson..= Aeson.object
                          [ "name" Aeson..= ("smoke-test" :: Text)
                          , "version" Aeson..= ("1.0" :: Text)
                          ]
                      ]
                  ]
              ]
        req <- buildJsonPost (baseUrl <> "/.mcp") mcpReq
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200

    it "MCP tasks/get on unknown id returns server-error code" do
      withServiceFromSources "mcp-tasks-404" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        let mcpReq = Aeson.object
              [ "jsonrpc" Aeson..= ("2.0" :: Text)
              , "id" Aeson..= (1 :: Int)
              , "method" Aeson..= ("tasks/get" :: Text)
              , "params" Aeson..= Aeson.object
                  [ "taskId" Aeson..= ("does-not-exist" :: Text) ]
              ]
        req <- buildJsonPost (baseUrl <> "/.mcp") mcpReq
        resp <- httpLbs req mgr
        let body = decodeObject (responseBody resp)
        case lookupKey "error" body of
          Just (Aeson.Object err) ->
            Aeson.KeyMap.lookup "code" err `shouldBe` Just (Aeson.Number (-32000))
          _ -> expectationFailure "Expected error object"

    it "MCP tasks/cancel on unknown id returns server-error code" do
      withServiceFromSources "mcp-tasks-cancel-404" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        let mcpReq = Aeson.object
              [ "jsonrpc" Aeson..= ("2.0" :: Text)
              , "id" Aeson..= (1 :: Int)
              , "method" Aeson..= ("tasks/cancel" :: Text)
              , "params" Aeson..= Aeson.object
                  [ "taskId" Aeson..= ("nope" :: Text) ]
              ]
        req <- buildJsonPost (baseUrl <> "/.mcp") mcpReq
        resp <- httpLbs req mgr
        let body = decodeObject (responseBody resp)
        case lookupKey "error" body of
          Just (Aeson.Object err) ->
            Aeson.KeyMap.lookup "code" err `shouldBe` Just (Aeson.Number (-32000))
          _ -> expectationFailure "Expected error object"

    it "MCP discovery exposes supported protocol versions and Tasks extension" do
      withServiceFromSources "mcp-discovery" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/.well-known/mcp")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        let bs = LBS.toStrict (responseBody resp)
        BS.isInfixOf "2026-07-28" bs `shouldBe` True
        BS.isInfixOf "supported_protocol_versions" bs `shouldBe` True
        BS.isInfixOf "io.modelcontextprotocol/tasks" bs `shouldBe` True

    it "returns OpenAPI 3.0 spec via per-deployment openapi.json" do
      withServiceFromSources "openapi" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/deployments/openapi/openapi.json")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        let body = decodeObject (responseBody resp)
        lookupKey "openapi" body `shouldBe` Just (Aeson.String "3.0.0")
        lookupKey "paths" body `shouldSatisfy` Maybe.isJust

    -- The batch response schema names exactly the keys a batch response
    -- carries: every case key the code emits for an answered, refused,
    -- errored and limit-stopped case, plus @graphviz, which needs
    -- ?trace=full&graphviz=true; and every summary key.
    it "documents in OpenAPI exactly the keys a batch response carries" do
      let stingy = testOptions { maxEvalMemoryMb = 64 }
      withServiceFromSourcesOpts stingy "batch-doc" [("spin.l4", spinOrRefuseJL4)] \baseUrl mgr -> do
        let body = Aeson.object
              [ "outcomes" Aeson..= ([] :: [Text])
              , "cases" Aeson..=
                  [ Aeson.object ["@id" Aeson..= (1 :: Int), "n" Aeson..= (1_000 :: Int)]
                  , Aeson.object ["@id" Aeson..= (2 :: Int), "n" Aeson..= (-1 :: Int)]
                  , Aeson.object ["@id" Aeson..= (3 :: Int)]
                  , Aeson.object ["@id" Aeson..= (4 :: Int), "n" Aeson..= spinFast]
                  ]
              ]
        req <- buildJsonPost (baseUrl <> "/deployments/batch-doc/functions/spin/evaluation/batch") body
        resp <- httpLbs req mgr
        docReq <- parseRequest (baseUrl <> "/deployments/batch-doc/openapi.json")
        docResp <- httpLbs docReq mgr
        let at k = \case
              Aeson.Object o -> Aeson.KeyMap.lookup k o
              _ -> Nothing
            keysOf = \case
              Just (Aeson.Object o) -> List.sort (Aeson.KeyMap.keys o)
              _ -> []
            emittedCases = rawBatchCases resp
            emittedCaseKeys = List.sort (List.nub ("@graphviz" : concatMap Aeson.KeyMap.keys emittedCases))
            emitted = Aeson.decode (responseBody resp) :: Maybe Aeson.Value
            batchOps = case Aeson.decode (responseBody docResp) >>= at "paths" of
              Just (Aeson.Object ps) ->
                [ op | (k, op) <- Aeson.KeyMap.toList ps
                     , "/evaluation/batch" `Text.isSuffixOf` Aeson.Key.toText k ]
              _ -> []
            schema = case batchOps of
              [op] -> at "post" op >>= at "responses" >>= at "200" >>= at "content"
                        >>= at "application/json" >>= at "schema"
              _ -> Nothing
        length batchOps `shouldBe` 1
        map (\c -> Aeson.KeyMap.member "@limit" c) emittedCases `shouldBe` [False, False, False, True]
        keysOf (schema >>= at "properties" >>= at "cases" >>= at "items" >>= at "properties")
          `shouldBe` emittedCaseKeys
        keysOf (schema >>= at "properties") `shouldBe` keysOf emitted
        keysOf (schema >>= at "properties" >>= at "summary" >>= at "properties")
          `shouldBe` keysOf (emitted >>= at "summary")

    it "returns OpenAPI 3.0 spec via org-wide /openapi.json" do
      withServiceFromSources "org-openapi" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/openapi.json")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        let body = decodeObject (responseBody resp)
        lookupKey "openapi" body `shouldBe` Just (Aeson.String "3.0.0")
        lookupKey "paths" body `shouldSatisfy` Maybe.isJust

    it "filters deployments by scope" do
      withServiceFromSources "scope-test" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        -- With matching scope
        req1 <- parseRequest (baseUrl <> "/deployments?functions=full&scope=scope-test/*")
        resp1 <- httpLbs req1 mgr
        statusCode' resp1 `shouldBe` 200
        case Aeson.decode (responseBody resp1) of
          Just (Aeson.Array deps) -> length deps `shouldSatisfy` (> 0)
          _ -> expectationFailure "Expected non-empty deployments array"
        -- With non-matching scope
        req2 <- parseRequest (baseUrl <> "/deployments?functions=full&scope=nonexistent/*")
        resp2 <- httpLbs req2 mgr
        statusCode' resp2 `shouldBe` 200
        case Aeson.decode (responseBody resp2) of
          Just (Aeson.Array deps) -> length deps `shouldBe` 0
          _ -> expectationFailure "Expected empty deployments array"

  describe "deontic evaluation" do
    it "evaluates a deontic function to FULFILLED with all events" do
      withServiceFromSources "deontic-ok" [("contract.l4", deonticExportJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "deontic-ok" "the sale contract"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object []
            , "startTime" Aeson..= (0 :: Int)
            , "events" Aeson..=
                [ Aeson.object ["party" Aeson..= ("the seller" :: Text), "action" Aeson..= ("deliver the goods" :: Text), "at" Aeson..= (5 :: Int)]
                , Aeson.object ["party" Aeson..= ("the buyer" :: Text), "action" Aeson..= ("pay the invoice" :: Text), "at" Aeson..= (20 :: Int)]
                ]
            ])
        assertSuccess resp \r ->
          Map.lookup "value" r.fnResult `shouldBe` Just (FnLitString "FULFILLED")

    it "returns initial OBLIGATION with empty events" do
      withServiceFromSources "deontic-init" [("contract.l4", deonticExportJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "deontic-init" "the sale contract"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object []
            , "startTime" Aeson..= (0 :: Int)
            , "events" Aeson..= ([] :: [Aeson.Value])
            ])
        assertSuccess resp \r -> do
          let mValue = Map.lookup "value" r.fnResult
          case mValue of
            Just (FnObject [("OBLIGATION", FnObject fields)]) -> do
              let fieldMap = Map.fromList fields
              Map.lookup "modal" fieldMap `shouldBe` Just (FnLitString "MUST")
            other ->
              expectationFailure ("Expected OBLIGATION, got: " <> show other)

    it "returns residual OBLIGATION after partial events" do
      withServiceFromSources "deontic-partial" [("contract.l4", deonticExportJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "deontic-partial" "the sale contract"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object []
            , "startTime" Aeson..= (0 :: Int)
            , "events" Aeson..=
                [ Aeson.object ["party" Aeson..= ("the seller" :: Text), "action" Aeson..= ("deliver the goods" :: Text), "at" Aeson..= (5 :: Int)]
                ]
            ])
        assertSuccess resp \r -> do
          let mValue = Map.lookup "value" r.fnResult
          case mValue of
            Just (FnObject [("OBLIGATION", FnObject fields)]) -> do
              let fieldMap = Map.fromList fields
              Map.lookup "modal" fieldMap `shouldBe` Just (FnLitString "MUST")
            other ->
              expectationFailure ("Expected OBLIGATION for buyer to pay, got: " <> show other)

    it "returns 400 when events provided for non-deontic function" do
      withServiceFromSources "deontic-err" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        req <- buildJsonPost (baseUrl <> "/deployments/deontic-err/functions/compute_qualifies/evaluation")
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object ["walks" Aeson..= True, "eats" Aeson..= True, "drinks" Aeson..= True]
            , "startTime" Aeson..= (0 :: Int)
            , "events" Aeson..= ([] :: [Aeson.Value])
            ])
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 400
        let body = decodeObject (responseBody resp)
        lookupKey "error" body `shouldSatisfy` Maybe.isJust

    it "returns 400 when startTime missing for deontic function" do
      withServiceFromSources "deontic-no-st" [("contract.l4", deonticExportJL4)] \baseUrl mgr -> do
        req <- buildJsonPost (baseUrl <> "/deployments/deontic-no-st/functions/the%20sale%20contract/evaluation")
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object []
            , "events" Aeson..= ([] :: [Aeson.Value])
            ])
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 400
        let body = decodeObject (responseBody resp)
        lookupKey "error" body `shouldSatisfy` Maybe.isJust

    it "returns 400 when events missing for deontic function" do
      withServiceFromSources "deontic-no-ev" [("contract.l4", deonticExportJL4)] \baseUrl mgr -> do
        req <- buildJsonPost (baseUrl <> "/deployments/deontic-no-ev/functions/the%20sale%20contract/evaluation")
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object []
            , "startTime" Aeson..= (0 :: Int)
            ])
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 400
        let body = decodeObject (responseBody resp)
        lookupKey "error" body `shouldSatisfy` Maybe.isJust

    it "includes startTime and events in function schema for deontic function" do
      withServiceFromSources "deontic-schema" [("contract.l4", deonticExportJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/deployments/deontic-schema/functions/the%20sale%20contract")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        let body = decodeObject (responseBody resp)
        -- Check that parameters include startTime and events in required
        case lookupKey "parameters" body of
          Just (Aeson.Object params) ->
            case Aeson.KeyMap.lookup "required" params of
              Just reqArr -> do
                let reqList = Aeson.decode (Aeson.encode reqArr) :: Maybe [Text]
                reqList `shouldSatisfy` maybe False (elem "startTime")
                reqList `shouldSatisfy` maybe False (elem "events")
              _ -> expectationFailure "Missing required array in parameters"
          _ -> expectationFailure "Missing parameters in response"

  -- TWOFACE (fired 2026-10-08): one party and one action were spelled two ways
  -- in the same answer. BREACH's `eventParty` and `eventAction` are a
  -- constructor's name, plain, but OBLIGATION's `party`, `action`, and BREACH's
  -- `obligationAction` and the `action` of a failure were L4 source, so a name
  -- with a space in it came back in backticks. A client that asks "is the party
  -- who acted the party who was obliged?" by comparing the two strings got a
  -- false no. The README's rule for an enum answer is the plain name, and a
  -- party or an action NAME is an enum answer.
  --
  -- This is not the string-literal escaping of R2 (2026-10-12, recorded in
  -- specs/done/BATCH-PROCESSING-SPEC.md): that covers rule source, and an
  -- action that carries a value, @say "pay\nnow"@, is still printed as rule
  -- source, escaped. A bare name is not a string value, and not rule source.
  describe "deontic answers spell a party and an action one way" do
    let seller = "the seller" :: Text
        buyer = "the buyer" :: Text
        delivery = "deliver the goods" :: Text
        payment = "pay the invoice" :: Text
        sale events = Aeson.object
          [ "arguments" Aeson..= Aeson.object []
          , "startTime" Aeson..= (0 :: Int)
          , "events" Aeson..= (events :: [Aeson.Value])
          ]
        event who what time = Aeson.object
          ["party" Aeson..= (who :: Text), "action" Aeson..= (what :: Text), "at" Aeson..= (time :: Int)]
        stringAt key fields = case lookup key fields of
          Just (FnLitString t) -> Just t
          _ -> Nothing
        -- the party and the action an OBLIGATION names
        obligationNames fields = (stringAt "party" fields, stringAt "action" fields)

    it "names the obliged party and its action without backticks, before any event" do
      withServiceFromSources "deontic-names-init" [("contract.l4", deonticExportJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "deontic-names-init" "the sale contract" (sale [])
        assertSuccess resp \r ->
          case Map.lookup "value" r.fnResult of
            Just (FnObject [("OBLIGATION", FnObject fields)]) ->
              obligationNames fields `shouldBe` (Just seller, Just delivery)
            other -> expectationFailure ("Expected OBLIGATION, got: " <> show other)

    it "names the obliged party and its action without backticks, after an event" do
      withServiceFromSources "deontic-names-resid" [("contract.l4", deonticExportJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "deontic-names-resid" "the sale contract"
          (sale [event seller delivery 5])
        assertSuccess resp \r ->
          case Map.lookup "value" r.fnResult of
            Just (FnObject [("OBLIGATION", FnObject fields)]) ->
              obligationNames fields `shouldBe` (Just buyer, Just payment)
            other -> expectationFailure ("Expected OBLIGATION, got: " <> show other)

    it "spells the party and the action of a BREACH the same in every field" do
      withServiceFromSources "deontic-names-breach" [("contract.l4", deonticDeadlineJL4)] \baseUrl mgr -> do
        -- the seller delivers at 20, after its deadline of 14
        resp <- evalFunction baseUrl mgr "deontic-names-breach" "the sale contract"
          (sale [event seller delivery 20])
        assertSuccess resp \r ->
          case Map.lookup "value" r.fnResult of
            Just (FnObject [("BREACH", FnObject fields)]) -> do
              -- the event that revealed the miss
              stringAt "eventParty" fields `shouldBe` Just seller
              stringAt "eventAction" fields `shouldBe` Just delivery
              -- the obligation that was missed
              stringAt "obligatedParty" fields `shouldBe` Just seller
              stringAt "obligationAction" fields `shouldBe` Just delivery
              lookup "obligatedParties" fields `shouldBe` Just (FnArray [FnLitString seller])
              case lookup "failures" fields of
                Just (FnArray [FnObject failure]) -> do
                  stringAt "party" failure `shouldBe` Just seller
                  stringAt "action" failure `shouldBe` Just delivery
                other -> expectationFailure ("Expected one failure, got: " <> show other)
            other -> expectationFailure ("Expected BREACH, got: " <> show other)

    -- the client's question, asked across two answers
    it "lets a client compare the party who acted with the party who was obliged" do
      withServiceFromSources "deontic-names-compare" [("contract.l4", deonticDeadlineJL4)] \baseUrl mgr -> do
        punctual <- evalFunction baseUrl mgr "deontic-names-compare" "the sale contract" (sale [])
        tardy <- evalFunction baseUrl mgr "deontic-names-compare" "the sale contract"
          (sale [event seller delivery 20])
        assertSuccess punctual \b -> assertSuccess tardy \l ->
          case (Map.lookup "value" b.fnResult, Map.lookup "value" l.fnResult) of
            (Just (FnObject [("OBLIGATION", FnObject obl)]), Just (FnObject [("BREACH", FnObject br)])) -> do
              stringAt "eventParty" br `shouldBe` stringAt "party" obl
              stringAt "eventAction" br `shouldBe` stringAt "action" obl
            other -> expectationFailure ("Expected an OBLIGATION and a BREACH, got: " <> show other)

    -- the operands of a ROR or a RAND are OBLIGATIONs of their own
    it "names the party and the action of each operand of a ROR and of a RAND" do
      withServiceFromSources "deontic-names-rops" [("contract.l4", deonticShapesJL4)] \baseUrl mgr -> do
        let operands tag fn = do
              resp <- evalFunction baseUrl mgr "deontic-names-rops" fn (sale [])
              assertSuccess resp \r ->
                case Map.lookup "value" r.fnResult of
                  Just (FnObject [(t, FnArray [FnObject [("OBLIGATION", FnObject first)], FnObject [("OBLIGATION", FnObject second)]])])
                    | t == tag -> do
                        obligationNames first `shouldBe` (Just seller, Just delivery)
                        obligationNames second `shouldBe` (Just buyer, Just payment)
                  other -> expectationFailure ("Expected two OBLIGATIONs under " <> show tag <> ", got: " <> show other)
        operands "OR" "the alternative"
        operands "AND" "the conjunction"

    -- an action the rule does not declare is a binder, and a space in it changes nothing
    it "names an action that is a binder without backticks" do
      withServiceFromSources "deontic-names-binder" [("contract.l4", deonticShapesJL4)] \baseUrl mgr -> do
        initial <- evalFunction baseUrl mgr "deontic-names-binder" "the binder" (sale [])
        late <- evalFunction baseUrl mgr "deontic-names-binder" "the binder"
          (sale [event seller "inspect the goods" 50])
        assertSuccess initial \r ->
          case Map.lookup "value" r.fnResult of
            Just (FnObject [("OBLIGATION", FnObject fields)]) ->
              obligationNames fields `shouldBe` (Just seller, Just "some act")
            other -> expectationFailure ("Expected OBLIGATION, got: " <> show other)
        assertSuccess late \r ->
          case Map.lookup "value" r.fnResult of
            Just (FnObject [("BREACH", FnObject fields)]) -> do
              stringAt "obligationAction" fields `shouldBe` Just "some act"
              case lookup "failures" fields of
                Just (FnArray [FnObject failure]) ->
                  stringAt "action" failure `shouldBe` Just "some act"
                other -> expectationFailure ("Expected one failure, got: " <> show other)
            other -> expectationFailure ("Expected BREACH, got: " <> show other)

    -- a party read from a GIVEN: the answer is the input's name, not the party
    -- it was given, until an event has been compared with it
    it "names a party that is a GIVEN input by its name, without backticks" do
      withServiceFromSources "deontic-names-given" [("contract.l4", deonticShapesJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "deontic-names-given" "the given party"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object ["the payer" Aeson..= seller]
            , "startTime" Aeson..= (0 :: Int)
            , "events" Aeson..= ([] :: [Aeson.Value])
            ])
        assertSuccess resp \r ->
          case Map.lookup "value" r.fnResult of
            Just (FnObject [("OBLIGATION", FnObject fields)]) ->
              obligationNames fields `shouldBe` (Just "the payer", Just delivery)
            other -> expectationFailure ("Expected OBLIGATION, got: " <> show other)

    -- R2: an action that carries a string is rule source, and stays escaped
    it "keeps an action that carries a string as rule source, escaped" do
      withServiceFromSources "deontic-names-literal" [("contract.l4", deonticLineBreakJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "deontic-names-literal" "the contract" (sale [])
        assertSuccess resp \r ->
          case Map.lookup "value" r.fnResult of
            Just (FnObject [("OBLIGATION", FnObject fields)]) -> do
              stringAt "party" fields `shouldBe` Just "Alice"
              stringAt "action" fields `shouldBe` Just "say \"pay\\nnow\""
            other -> expectationFailure ("Expected OBLIGATION, got: " <> show other)

  describe "deontic evaluation with record-typed parties" do
    it "evaluates to FULFILLED when record-typed party wears seatbelt then drives" do
      withServiceFromSources "deontic-rec-ok" [("seatbelt.l4", deonticRecordPartyJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "deontic-rec-ok" "Seatbelt Requirement"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "car" Aeson..= Aeson.object ["number of wheels" Aeson..= (4 :: Int)]
                , "driver" Aeson..= Aeson.object ["name" Aeson..= ("Alice" :: Text)]
                ]
            , "startTime" Aeson..= (0 :: Int)
            , "events" Aeson..=
                [ Aeson.object ["party" Aeson..= Aeson.object ["name" Aeson..= ("Alice" :: Text)], "action" Aeson..= ("wear seatbelt" :: Text), "at" Aeson..= (1 :: Int)]
                , Aeson.object ["party" Aeson..= Aeson.object ["name" Aeson..= ("Alice" :: Text)], "action" Aeson..= ("drive" :: Text), "at" Aeson..= (2 :: Int)]
                ]
            ])
        assertSuccess resp \r ->
          Map.lookup "value" r.fnResult `shouldBe` Just (FnLitString "FULFILLED")

    it "returns OBLIGATION when record-typed party drives without seatbelt" do
      withServiceFromSources "deontic-rec-obl" [("seatbelt.l4", deonticRecordPartyJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "deontic-rec-obl" "Seatbelt Requirement"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "car" Aeson..= Aeson.object ["number of wheels" Aeson..= (4 :: Int)]
                , "driver" Aeson..= Aeson.object ["name" Aeson..= ("Alice" :: Text)]
                ]
            , "startTime" Aeson..= (0 :: Int)
            , "events" Aeson..=
                [ Aeson.object ["party" Aeson..= Aeson.object ["name" Aeson..= ("Alice" :: Text)], "action" Aeson..= ("drive" :: Text), "at" Aeson..= (1 :: Int)]
                ]
            ])
        assertSuccess resp \r -> do
          let mValue = Map.lookup "value" r.fnResult
          case mValue of
            Just (FnObject [("OBLIGATION", FnObject fields)]) -> do
              let fieldMap = Map.fromList fields
              Map.lookup "modal" fieldMap `shouldBe` Just (FnLitString "MUST")
            other ->
              expectationFailure ("Expected OBLIGATION, got: " <> show other)

    it "evaluates 3-wheeled car to FULFILLED without seatbelt" do
      withServiceFromSources "deontic-rec-3w" [("seatbelt.l4", deonticRecordPartyJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "deontic-rec-3w" "Seatbelt Requirement"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "car" Aeson..= Aeson.object ["number of wheels" Aeson..= (3 :: Int)]
                , "driver" Aeson..= Aeson.object ["name" Aeson..= ("Bob" :: Text)]
                ]
            , "startTime" Aeson..= (0 :: Int)
            , "events" Aeson..=
                [ Aeson.object ["party" Aeson..= Aeson.object ["name" Aeson..= ("Bob" :: Text)], "action" Aeson..= ("drive" :: Text), "at" Aeson..= (1 :: Int)]
                ]
            ])
        assertSuccess resp \r ->
          Map.lookup "value" r.fnResult `shouldBe` Just (FnLitString "FULFILLED")

    it "includes record-typed party schema in events parameter" do
      withServiceFromSources "deontic-rec-sch" [("seatbelt.l4", deonticRecordPartyJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/deployments/deontic-rec-sch/functions/Seatbelt%20Requirement")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        let body = decodeObject (responseBody resp)
        -- Check events parameter has object-typed party with "name" field
        case lookupKey "parameters" body of
          Just (Aeson.Object params) ->
            case Aeson.KeyMap.lookup "properties" params of
              Just (Aeson.Object props) ->
                case Aeson.KeyMap.lookup "events" props of
                  Just (Aeson.Object eventsParam) ->
                    case Aeson.KeyMap.lookup "items" eventsParam of
                      Just (Aeson.Object items) ->
                        case Aeson.KeyMap.lookup "properties" items of
                          Just (Aeson.Object eventProps) -> do
                            -- party should be an object type (record), not a string (enum)
                            case Aeson.KeyMap.lookup "party" eventProps of
                              Just (Aeson.Object partyParam) ->
                                Aeson.KeyMap.lookup "type" partyParam `shouldBe` Just (Aeson.String "object")
                              _ -> expectationFailure "Missing party in event properties"
                            -- action should be a string type (enum)
                            case Aeson.KeyMap.lookup "action" eventProps of
                              Just (Aeson.Object actionParam) ->
                                Aeson.KeyMap.lookup "type" actionParam `shouldBe` Just (Aeson.String "string")
                              _ -> expectationFailure "Missing action in event properties"
                          _ -> expectationFailure "Missing properties in events items"
                      _ -> expectationFailure "Missing items in events parameter"
                  _ -> expectationFailure "Missing events in properties"
              _ -> expectationFailure "Missing properties in parameters"
          _ -> expectationFailure "Missing parameters in response"

  describe "state graphs" do
    it "returns empty list for a boolean-only module" do
      withServiceFromSources "sg-empty" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/deployments/sg-empty/functions/compute_qualifies/state-graphs")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        let body = decodeObject (responseBody resp)
        lookupArrayLength "graphs" body `shouldBe` Just 0

    it "returns state graphs for a module with regulative rules" do
      withServiceFromSources "sg-contract" [("contract.l4", saleContractJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/deployments/sg-contract/functions/test_fn/state-graphs")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        let body = decodeObject (responseBody resp)
        lookupArrayLength "graphs" body `shouldSatisfy` maybe False (> 0)

    it "returns DOT text for a specific state graph" do
      withServiceFromSources "sg-dot" [("contract.l4", saleContractJL4)] \baseUrl mgr -> do
        -- First get the list to find a graph name
        listReq <- parseRequest (baseUrl <> "/deployments/sg-dot/functions/test_fn/state-graphs")
        listResp <- httpLbs listReq mgr
        statusCode' listResp `shouldBe` 200
        let listBody = decodeObject (responseBody listResp)
        case lookupKey "graphs" listBody of
          Just (Aeson.Array graphs) | not (null graphs) -> do
            -- Extract the first graph name
            case toList graphs of
              (Aeson.Object g : _) ->
                case Aeson.KeyMap.lookup "graphName" g of
                  Just (Aeson.String graphName) -> do
                    -- Fetch the DOT output
                    dotReq <- parseRequest (baseUrl <> "/deployments/sg-dot/functions/test_fn/state-graphs/" <> Text.unpack graphName)
                    dotResp <- httpLbs dotReq mgr
                    statusCode' dotResp `shouldBe` 200
                    let dotText = Text.Encoding.decodeUtf8 (LBS.toStrict (responseBody dotResp))
                    dotText `shouldSatisfy` Text.isInfixOf "digraph"
                    -- This endpoint is how the captions reach a user, and until
                    -- now "digraph" was the whole of what it asserted — a
                    -- caption inverted the way smucclaw/l4-ide#927 describes
                    -- would have travelled the entire HTTP surface untested.
                    -- `the sale contract` is two nested MUSTs, each with a
                    -- WITHIN and an explicit LEST BREACH, so both LEST arms are
                    -- reached by the clock and both read "timeout".
                    --
                    -- The caption names the deadline that TAKES the arm, so it
                    -- is per-edge — 14 on the delivery, 30 on the invoice — and
                    -- GraphViz then quotes it. This read `label=timeout` until
                    -- 2026-09-21 and the deadline broke it: an unquoted
                    -- `label=timeout` is exactly what the emitter stopped
                    -- producing, and `Text.isInfixOf` on it went from true to
                    -- false in a suite the change's author did not run. Assert
                    -- the whole caption, so the next move is caught here too.
                    dotText `shouldSatisfy` Text.isInfixOf "label=\"timeout [14]\""
                    dotText `shouldSatisfy` Text.isInfixOf "label=\"timeout [30]\""
                    -- and nothing here is a prohibition or a deadline-less rule
                    dotText `shouldNotSatisfy` Text.isInfixOf "violation"
                    dotText `shouldNotSatisfy` Text.isInfixOf "unreachable"
                  _ -> expectationFailure "Graph object missing graphName"
              _ -> expectationFailure "Expected graph object in array"
          _ -> expectationFailure "Expected non-empty graphs array"

    it "returns 404 for non-existent state graph" do
      withServiceFromSources "sg-404" [("contract.l4", saleContractJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/deployments/sg-404/functions/test_fn/state-graphs/nonexistent")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 404

  describe "visibility headers" do
    it "X-Include-Functions: false hides functions from deployment response" do
      withServiceFromSources "vis-fn" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/deployments")
        let req' = req { requestHeaders = [("X-Include-Functions", "false")] }
        resp <- httpLbs req' mgr
        statusCode' resp `shouldBe` 200
        case Aeson.decode (responseBody resp) of
          Just (Aeson.Array deps) -> do
            length deps `shouldSatisfy` (> 0)
            let dep = safeHead (toList deps)
                mFns = case dep of
                  Aeson.Object o -> case Aeson.KeyMap.lookup "metadata" o of
                    Just (Aeson.Object m) -> Aeson.KeyMap.lookup "functions" m
                    _ -> Nothing
                  _ -> Nothing
            -- functions should be absent (empty = omitted)
            mFns `shouldBe` Nothing
          _ -> expectationFailure "Expected deployments array"

    it "X-Include-Files: false hides files from deployment response" do
      withServiceFromSources "vis-fi" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/deployments")
        let req' = req { requestHeaders = [("X-Include-Files", "false")] }
        resp <- httpLbs req' mgr
        statusCode' resp `shouldBe` 200
        case Aeson.decode (responseBody resp) of
          Just (Aeson.Array deps) -> do
            length deps `shouldSatisfy` (> 0)
            let dep = safeHead (toList deps)
                mFiles = case dep of
                  Aeson.Object o -> case Aeson.KeyMap.lookup "metadata" o of
                    Just (Aeson.Object m) -> Aeson.KeyMap.lookup "files" m
                    _ -> Nothing
                  _ -> Nothing
            -- files should be absent
            mFiles `shouldBe` Nothing
          _ -> expectationFailure "Expected deployments array"

    it "X-Include-Evaluate: false hides evaluation paths from OpenAPI" do
      withServiceFromSources "vis-ev" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/openapi.json")
        let req' = req { requestHeaders = [("X-Include-Evaluate", "false")] }
        resp <- httpLbs req' mgr
        statusCode' resp `shouldBe` 200
        let body = decodeObject (responseBody resp)
        case lookupKey "paths" body of
          Just (Aeson.Object paths) -> do
            -- Should have function GET paths but no evaluation POST paths
            let pathKeys = map Aeson.Key.toText (Aeson.KeyMap.keys paths)
                hasEval = any (Text.isInfixOf "/evaluation") pathKeys
            hasEval `shouldBe` False
          _ -> expectationFailure "Expected paths object"

    it "X-Include-Evaluate: false hides evaluation tools from MCP" do
      withServiceFromSources "vis-mcp" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        let mcpReq = Aeson.object
              [ "jsonrpc" Aeson..= ("2.0" :: Text)
              , "id" Aeson..= (1 :: Int)
              , "method" Aeson..= ("tools/list" :: Text)
              ]
        req <- buildJsonPost (baseUrl <> "/.mcp") mcpReq
        let req' = req { requestHeaders = ("X-Include-Evaluate", "false") : requestHeaders req }
        resp <- httpLbs req' mgr
        statusCode' resp `shouldBe` 200
        let body = decodeObject (responseBody resp)
        -- result.tools should exist but have no function evaluation tools
        case lookupKey "result" body of
          Just (Aeson.Object result) ->
            case Aeson.KeyMap.lookup "tools" result of
              Just (Aeson.Array tools) ->
                -- Should have file tools but no function tools
                let toolNames = [ n | Aeson.Object t <- toList tools
                                    , Just (Aeson.String n) <- [Aeson.KeyMap.lookup "name" t] ]
                    hasEvalTool = any (\n -> n /= "list_files" && n /= "read_file"
                                          && n /= "search_identifier" && n /= "search_text") toolNames
                in hasEvalTool `shouldBe` False
              _ -> expectationFailure "Expected tools array"
          _ -> expectationFailure "Expected result object"

    it "X-Include-Functions: false hides all function tools from MCP" do
      withServiceFromSources "vis-mcp-fn" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        let mcpReq = Aeson.object
              [ "jsonrpc" Aeson..= ("2.0" :: Text)
              , "id" Aeson..= (1 :: Int)
              , "method" Aeson..= ("tools/list" :: Text)
              ]
        req <- buildJsonPost (baseUrl <> "/.mcp") mcpReq
        let req' = req { requestHeaders = ("X-Include-Functions", "false") : requestHeaders req }
        resp <- httpLbs req' mgr
        statusCode' resp `shouldBe` 200
        let body = decodeObject (responseBody resp)
        case lookupKey "result" body of
          Just (Aeson.Object result) ->
            case Aeson.KeyMap.lookup "tools" result of
              Just (Aeson.Array tools) ->
                -- Should only have file tools, no function evaluation tools
                let toolNames = [ n | Aeson.Object t <- toList tools
                                    , Just (Aeson.String n) <- [Aeson.KeyMap.lookup "name" t] ]
                    fileToolNames = ["list_files", "read_file", "search_identifier", "search_text"] :: [Text]
                    nonFileTools = filter (`notElem` fileToolNames) toolNames
                in nonFileTools `shouldBe` []
              _ -> expectationFailure "Expected tools array"
          _ -> expectationFailure "Expected result object"

    it "X-Include-Files: false hides file tools from MCP" do
      withServiceFromSources "vis-mcp-fi" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        let mcpReq = Aeson.object
              [ "jsonrpc" Aeson..= ("2.0" :: Text)
              , "id" Aeson..= (1 :: Int)
              , "method" Aeson..= ("tools/list" :: Text)
              ]
        req <- buildJsonPost (baseUrl <> "/.mcp") mcpReq
        let req' = req { requestHeaders = ("X-Include-Files", "false") : requestHeaders req }
        resp <- httpLbs req' mgr
        statusCode' resp `shouldBe` 200
        let body = decodeObject (responseBody resp)
        case lookupKey "result" body of
          Just (Aeson.Object result) ->
            case Aeson.KeyMap.lookup "tools" result of
              Just (Aeson.Array tools) ->
                -- Should have function tools but no file tools
                let toolNames = [ n | Aeson.Object t <- toList tools
                                    , Just (Aeson.String n) <- [Aeson.KeyMap.lookup "name" t] ]
                    fileToolNames = ["list_files", "read_file", "search_identifier", "search_text"] :: [Text]
                    hasFileTool = any (`elem` fileToolNames) toolNames
                in hasFileTool `shouldBe` False
              _ -> expectationFailure "Expected tools array"
          _ -> expectationFailure "Expected result object"

  describe "deployments query params" do
    it "?functions=full includes parameters in listing" do
      withServiceFromSources "qp-full" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/deployments?functions=full")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        case Aeson.decode (responseBody resp) of
          Just (Aeson.Array deps) -> do
            length deps `shouldSatisfy` (> 0)
            let dep = safeHead (toList deps)
                hasFnParams = case dep of
                  Aeson.Object o -> case Aeson.KeyMap.lookup "metadata" o of
                    Just (Aeson.Object m) -> case Aeson.KeyMap.lookup "functions" m of
                      Just (Aeson.Array fns) | not (null fns) ->
                        case safeHead (toList fns) of
                          Aeson.Object fn -> Aeson.KeyMap.member "parameters" fn
                          _ -> False
                      _ -> False
                    _ -> False
                  _ -> False
            hasFnParams `shouldBe` True
          _ -> expectationFailure "Expected deployments array"

    it "default listing includes functions with name but not parameters" do
      withServiceFromSources "qp-default" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/deployments")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        case Aeson.decode (responseBody resp) of
          Just (Aeson.Array deps) -> do
            length deps `shouldSatisfy` (> 0)
            let dep = safeHead (toList deps)
                check = case dep of
                  Aeson.Object o -> case Aeson.KeyMap.lookup "metadata" o of
                    Just (Aeson.Object m) -> case Aeson.KeyMap.lookup "functions" m of
                      Just (Aeson.Array fns) | not (null fns) ->
                        case safeHead (toList fns) of
                          Aeson.Object fn ->
                            -- Has name but parameters should be empty (simple mode)
                            Aeson.KeyMap.member "name" fn
                          _ -> False
                      _ -> False
                    _ -> False
                  _ -> False
            check `shouldBe` True
          _ -> expectationFailure "Expected deployments array"

    it "?scope= filters deployments" do
      withServiceFromSources "qp-scope" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        -- Matching scope
        req1 <- parseRequest (baseUrl <> "/deployments?scope=qp-scope")
        resp1 <- httpLbs req1 mgr
        statusCode' resp1 `shouldBe` 200
        case Aeson.decode (responseBody resp1) of
          Just (Aeson.Array deps) -> length deps `shouldSatisfy` (> 0)
          _ -> expectationFailure "Expected non-empty deployments array"
        -- Non-matching scope
        req2 <- parseRequest (baseUrl <> "/deployments?scope=nonexistent")
        resp2 <- httpLbs req2 mgr
        statusCode' resp2 `shouldBe` 200
        case Aeson.decode (responseBody resp2) of
          Just (Aeson.Array deps) -> length deps `shouldBe` 0
          _ -> expectationFailure "Expected empty deployments array"

  describe "lazy-load (compile on first request)" do
    it "GET /deployments/{id} compiles pending deployment and returns ready" do
      withPendingService "lazy-get" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/deployments/lazy-get")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        let mStatus = Aeson.decode (responseBody resp) :: Maybe DeploymentStatusResponse
        case mStatus of
          Just s -> s.dsStatus `shouldBe` "ready"
          Nothing -> expectationFailure "Failed to decode deployment status response"

    it "evaluation on pending deployment compiles and succeeds in one request" do
      withPendingService "lazy-eval" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "lazy-eval" "compute_qualifies"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "walks" Aeson..= True
                , "eats" Aeson..= True
                , "drinks" Aeson..= True
                ]
            ])
        assertSuccess resp \r ->
          Map.lookup "value" r.fnResult `shouldBe` Just (FnLitBool True)

    it "listing functions on pending deployment compiles and returns functions" do
      withPendingService "lazy-fns" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/deployments/lazy-fns/functions")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200

    it "GET /deployments lists pending deployments without triggering compilation" do
      withPendingService "lazy-list" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/deployments")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        let mList = Aeson.decode (responseBody resp) :: Maybe [DeploymentStatusResponse]
        case mList of
          Just ds -> do
            length ds `shouldBe` 1
            case ds of
              (d:_) -> d.dsStatus `shouldBe` "pending"
              [] -> expectationFailure "Expected at least one deployment"
          Nothing -> expectationFailure "Failed to decode deployment list"

    it "health endpoint shows pending count before compilation" do
      withPendingService "lazy-health" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/health")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        let body = decodeObject (responseBody resp)
        lookupKey "deployments" body `shouldSatisfy` \case
          Just (Aeson.Object dObj) ->
            case Aeson.KeyMap.lookup "pending" dObj of
              Just (Aeson.Number n) -> n >= 1
              _ -> False
          _ -> False

  describe "pre-compilation file access" do
    it "GET /deployments/{id}/files returns files for pending deployment" do
      withPendingService "precomp-files" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/deployments/precomp-files/files")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        let body = decodeObject (responseBody resp)
        case lookupKey "files" body of
          Just (Aeson.Array files) -> length files `shouldSatisfy` (> 0)
          _ -> expectationFailure "Expected 'files' array in response"

    it "GET /deployments/{id}/files?file=qualifies.l4 returns file content for pending deployment" do
      withPendingService "precomp-file" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/deployments/precomp-file/files?file=qualifies.l4")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        -- Response should include file content with L4 keywords
        let body = LBS.toStrict (responseBody resp)
        body `shouldSatisfy` ("DECIDE" `BS.isInfixOf`)

    it "GET /deployments/{id}/files?search=DECIDE returns matches for pending deployment" do
      withPendingService "precomp-search" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/deployments/precomp-search/files?search=DECIDE")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        let respBody = responseBody resp
        -- Response should contain both files and search matches
        LBS.toStrict respBody `shouldSatisfy` \bs ->
          "DECIDE" `BS.isInfixOf` bs && "matches" `BS.isInfixOf` bs

    it "MCP list_files returns files for pending deployment" do
      withPendingService "precomp-mcp-list" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        let rpcBody = Aeson.object
              [ "jsonrpc" Aeson..= ("2.0" :: Text)
              , "id" Aeson..= (1 :: Int)
              , "method" Aeson..= ("tools/call" :: Text)
              , "params" Aeson..= Aeson.object
                  [ "name" Aeson..= ("list_files" :: Text)
                  , "arguments" Aeson..= Aeson.object
                      [ "deployment" Aeson..= ("precomp-mcp-list" :: Text)
                      ]
                  ]
              ]
        req <- buildJsonPost (baseUrl <> "/.mcp") rpcBody
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        let body = decodeObject (responseBody resp)
        -- Should have a result with content (not an error)
        lookupKey "error" body `shouldBe` Nothing
        lookupKey "result" body `shouldSatisfy` Maybe.isJust

    it "MCP read_file returns content for pending deployment" do
      withPendingService "precomp-mcp-read" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        let rpcBody = Aeson.object
              [ "jsonrpc" Aeson..= ("2.0" :: Text)
              , "id" Aeson..= (1 :: Int)
              , "method" Aeson..= ("tools/call" :: Text)
              , "params" Aeson..= Aeson.object
                  [ "name" Aeson..= ("read_file" :: Text)
                  , "arguments" Aeson..= Aeson.object
                      [ "deployment" Aeson..= ("precomp-mcp-read" :: Text)
                      , "path" Aeson..= ("qualifies.l4" :: Text)
                      ]
                  ]
              ]
        req <- buildJsonPost (baseUrl <> "/.mcp") rpcBody
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        let body = decodeObject (responseBody resp)
        lookupKey "error" body `shouldBe` Nothing
        -- The content text should contain L4 source
        let mResult = lookupKey "result" body
        mResult `shouldSatisfy` Maybe.isJust

    it "MCP search_identifier returns results for pending deployment" do
      withPendingService "precomp-mcp-ident" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        let rpcBody = Aeson.object
              [ "jsonrpc" Aeson..= ("2.0" :: Text)
              , "id" Aeson..= (1 :: Int)
              , "method" Aeson..= ("tools/call" :: Text)
              , "params" Aeson..= Aeson.object
                  [ "name" Aeson..= ("search_identifier" :: Text)
                  , "arguments" Aeson..= Aeson.object
                      [ "identifier" Aeson..= ("compute_qualifies" :: Text)
                      , "deployment" Aeson..= ("precomp-mcp-ident" :: Text)
                      ]
                  ]
              ]
        req <- buildJsonPost (baseUrl <> "/.mcp") rpcBody
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        let body = decodeObject (responseBody resp)
        lookupKey "error" body `shouldBe` Nothing
        -- Should find the function definition
        LBS.toStrict (responseBody resp) `shouldSatisfy` ("compute_qualifies" `BS.isInfixOf`)

    it "MCP read_file rejects path traversal (../)" do
      withPendingService "precomp-traversal" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        let rpcBody = Aeson.object
              [ "jsonrpc" Aeson..= ("2.0" :: Text)
              , "id" Aeson..= (1 :: Int)
              , "method" Aeson..= ("tools/call" :: Text)
              , "params" Aeson..= Aeson.object
                  [ "name" Aeson..= ("read_file" :: Text)
                  , "arguments" Aeson..= Aeson.object
                      [ "deployment" Aeson..= ("precomp-traversal" :: Text)
                      , "path" Aeson..= ("../metadata.json" :: Text)
                      ]
                  ]
              ]
        req <- buildJsonPost (baseUrl <> "/.mcp") rpcBody
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        let body = decodeObject (responseBody resp)
        -- Should return a "File not found" result (path safety check rejects ../)
        lookupKey "result" body `shouldSatisfy` Maybe.isJust

    it "GET /deployments/{id}/files rejects path traversal in file param" do
      withPendingService "precomp-traversal2" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/deployments/precomp-traversal2/files?file=../metadata.json")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        -- Response should have empty files array (path doesn't match any .l4 file)
        let body = decodeObject (responseBody resp)
        case lookupKey "files" body of
          Just (Aeson.Array files) -> length files `shouldBe` 0
          _ -> pure ()  -- Any non-success is fine

  describe "failed deployment file access" do
    it "GET /deployments/{id}/files returns files for failed deployment" do
      withFailedService "failed-files" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        req <- parseRequest (baseUrl <> "/deployments/failed-files/files")
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        let body = decodeObject (responseBody resp)
        case lookupKey "files" body of
          Just (Aeson.Array files) -> length files `shouldSatisfy` (> 0)
          _ -> expectationFailure "Expected 'files' array in response"

    it "MCP list_files returns files for failed deployment" do
      withFailedService "failed-mcp-list" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        let rpcBody = Aeson.object
              [ "jsonrpc" Aeson..= ("2.0" :: Text)
              , "id" Aeson..= (1 :: Int)
              , "method" Aeson..= ("tools/call" :: Text)
              , "params" Aeson..= Aeson.object
                  [ "name" Aeson..= ("list_files" :: Text)
                  , "arguments" Aeson..= Aeson.object
                      [ "deployment" Aeson..= ("failed-mcp-list" :: Text)
                      ]
                  ]
              ]
        req <- buildJsonPost (baseUrl <> "/.mcp") rpcBody
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        let body = decodeObject (responseBody resp)
        lookupKey "error" body `shouldBe` Nothing

    it "MCP read_file returns content for failed deployment" do
      withFailedService "failed-mcp-read" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        let rpcBody = Aeson.object
              [ "jsonrpc" Aeson..= ("2.0" :: Text)
              , "id" Aeson..= (1 :: Int)
              , "method" Aeson..= ("tools/call" :: Text)
              , "params" Aeson..= Aeson.object
                  [ "name" Aeson..= ("read_file" :: Text)
                  , "arguments" Aeson..= Aeson.object
                      [ "deployment" Aeson..= ("failed-mcp-read" :: Text)
                      , "path" Aeson..= ("qualifies.l4" :: Text)
                      ]
                  ]
              ]
        req <- buildJsonPost (baseUrl <> "/.mcp") rpcBody
        resp <- httpLbs req mgr
        statusCode' resp `shouldBe` 200
        let body = decodeObject (responseBody resp)
        lookupKey "error" body `shouldBe` Nothing

    it "evaluation on failed deployment returns 500" do
      withFailedService "failed-eval" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "failed-eval" "compute_qualifies"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "walks" Aeson..= True
                , "eats" Aeson..= True
                , "drinks" Aeson..= True
                ]
            ])
        statusCode' resp `shouldBe` 500

  describe "optimistic compilation" do
    it "evaluation on pending deployment returns 200 (compiles within 2s for small file)" do
      withPendingService "precomp-eval" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "precomp-eval" "compute_qualifies"
          (Aeson.object
            [ "arguments" Aeson..= Aeson.object
                [ "walks" Aeson..= True
                , "eats" Aeson..= True
                , "drinks" Aeson..= True
                ]
            ])
        -- Small file compiles fast enough for the 2s optimistic timeout
        statusCode' resp `shouldSatisfy` (\s -> s == 200 || s == 202)

  describe "compiler" do
    it "compiles valid L4 sources" do
      logger <- newLogger False
      let sources = Map.singleton "qualifies.l4" qualifiesJL4
      result <- compileBundle logger "test" sources
      case result of
        Left err -> expectationFailure ("Compilation failed: " <> Text.unpack err)
        Right (fns, meta) -> do
          Map.size fns `shouldSatisfy` (> 0)
          length meta.metaFunctions `shouldSatisfy` (> 0)
          Text.length meta.metaVersion `shouldBe` 64  -- SHA-256 hex

    it "says why a source does not parse, to the caller and in the log" do
      -- A file that does not parse has no check result at all, so the reason
      -- is not among the type errors; it used to be said nowhere ("Typecheck
      -- failed", and a warning that named the file and nothing else).
      (logPath, h) <- openTempFile' "jl4-service-parse-error"
      logger <- newLoggerTo h False
      result <- compileBundle logger "test" (Map.singleton "broken.l4" (qualifiesJL4 <> "\nDECIDE ( IS\n"))
      hClose h
      logLines <- Maybe.mapMaybe Aeson.decodeStrict . BS8.lines <$> BS.readFile logPath
      removePathForcibly (takeDirectory logPath)
      case result of
        Left err -> do
          err `shouldSatisfy` ("broken.l4" `Text.isInfixOf`)
          err `shouldSatisfy` ("unexpected (" `Text.isInfixOf`)
        Right _ -> expectationFailure "A source that does not parse was compiled"
      errorsLoggedFor "test" "broken.l4" logLines `shouldSatisfy` any ("unexpected (" `Text.isInfixOf`)

    -- An annotation line this version of L4 ignores is a warning in the editor
    -- and in `l4 check`, because the lexer lets it through so that a file
    -- written for a newer L4 still opens in an older one. A deployment is what
    -- the service publishes, so here it is a REFUSAL: a misspelt `@export` was
    -- "applied" with no functions at all, silently. Before the lexer let these
    -- through, the service refused them as lexer errors; it still does.
    describe "an annotation this version ignores" do
      let rule = ["GIVEN n IS A NUMBER", "GIVETH A NUMBER", "DECIDE `add one` n IS n + 1"]
          refusedWith needles line = do
            logger <- newLogger False
            result <- compileBundle logger "test" (Map.singleton "typo.l4" (Text.unlines (line : rule)))
            case result of
              Left err -> forM_ needles \needle -> err `shouldSatisfy` Text.isInfixOf needle
              Right (_fns, meta) ->
                expectationFailure $
                  "Expected a refusal, but compiled and published "
                    <> show (map (.fsName) meta.metaFunctions)

      it "refuses a deployment whose misspelt @export would publish nothing" $
        refusedWith ["typo.l4:1:1:", "`@exprot`", "Did you mean `@export`?"]
          "@exprot default adds one to a number"

      it "refuses a deployment that uses an annotation from a newer L4" $
        refusedWith ["typo.l4:1:1:", "`@future-annotation`", "ignored"]
          "@future-annotation this version has never heard of it"

      it "refuses a malformed @lang, which the editor ignores with a warning" $
        refusedWith ["typo.l4:1:1:", "Malformed annotation `@lang`", "@lang en"]
          "@lang"

      it "names the line of an annotation that is not on the first" do
        logger <- newLogger False
        result <- compileBundle logger "test" (Map.singleton "typo.l4" (Text.unlines (rule <> ["", "@exprot adds two"])))
        case result of
          Left err -> err `shouldSatisfy` Text.isInfixOf "typo.l4:5:1:"
          Right _ -> expectationFailure "Expected a refusal"

      -- A name that merely BEGINS with a known annotation's (`@descr`, `@exports`,
      -- `@nlgg`) is not an ignored annotation: the lexer reads it as that
      -- annotation with stray text, as it always did, and the service accepts it
      -- as it did. `@langx` and `@nonassertablex` were lexer errors, and are
      -- ignored lines now, so they are refused.
      let compiledWith line = do
            (logPath, h) <- openTempFile' "jl4-service-ignored"
            logger <- newLoggerTo h False
            result <- compileBundle logger "test" (Map.singleton "old.l4" (Text.unlines (line <> rule)))
            hClose h
            logLines <- Maybe.mapMaybe Aeson.decodeStrict . BS8.lines <$> BS.readFile logPath
            removePathForcibly (takeDirectory logPath)
            pure (result, ignoredLoggedFor "test" "old.l4" logLines)

      it "accepts a name that begins with a known annotation, as it always did, and ignores nothing" do
        (result, logged) <- compiledWith ["@export default adds one", "@descr a longer description"]
        case result of
          Left err -> expectationFailure ("Expected the deployment, but it was refused: " <> Text.unpack err)
          Right (fns, _meta) -> Map.keys fns `shouldBe` ["add one"]
        logged `shouldBe` []

      it "still refuses a name that begins with an annotation whose lexer checked what follows" $
        forM_ ["@langx en", "@nonassertablex"] \line ->
          refusedWith ["typo.l4:1:1:"] line

      it "accepts a module with @lang en, which only earns the editor a hint" do
        (result, logged) <- compiledWith ["@lang en"]
        case result of
          Left err -> expectationFailure ("Expected the deployment, but it was refused: " <> Text.unpack err)
          Right _ -> pure ()
        logged `shouldBe` []

    -- THE JOIN where the program has its own JOIN: a warning in the editor and
    -- in `l4 check` (LifecycleNounHidesName), a refusal here (B1a, ruled
    -- 2026-10-24). Until then that THE was an optional article, so the module
    -- may mean its own JOIN, and under a HENCE the change is a different number
    -- with no error. The refusal names the hidden name and says that dropping
    -- THE reaches it; renaming is offered only for a name this module defines.
    describe "THE before a noun the program also defines" do
      let hidesJL4 the = Text.unlines
            [ "DECLARE Actor IS ONE OF"
            , "    Tenant HAS name IS A STRING"
            , "DECLARE Action IS ONE OF"
            , "    Sign   HAS signer IS AN Actor"
            , "    Refund HAS who IS AN Actor"
            , ""
            , "alice MEANS Tenant OF \"Alice\""
            , ""
            , "GIVEN start IS A NUMBER"
            , "GIVETH A DEONTIC Actor Action"
            , "`refund within 30 of` MEANS"
            , "    PARTY alice MUST Refund alice WITHIN 30 OF start"
            , ""
            , "GIVETH A DEONTIC Actor Action"
            , "`passes the join` MEANS"
            , "    PARTY alice MUST Sign alice WITHIN 10"
            , "    HENCE `refund within 30 of` WITH start IS " <> the <> "JOIN"
            , ""
            , "@export default adds one to a number"
            , "GIVEN n IS A NUMBER"
            , "GIVETH A NUMBER"
            , "DECIDE `add one` n IS n + 1"
            ]
          compiled sources = do
            logger <- newLogger False
            compileBundle logger "test" (Map.fromList sources)
          refusedWith needles absent sources = do
            result <- compiled sources
            case result of
              Left err -> do
                forM_ needles \needle -> err `shouldSatisfy` Text.isInfixOf needle
                forM_ absent \needle -> err `shouldNotSatisfy` Text.isInfixOf needle
              Right (_fns, meta) ->
                expectationFailure $
                  "Expected a refusal, but compiled and published "
                    <> show (map (.fsName) meta.metaFunctions)

      it "refuses THE JOIN that hides the module's own JOIN, naming it and saying to drop THE" $
        refusedWith
          [ "hides.l4:19:", "THE JOIN here is the lifecycle position", "hides `JOIN`"
          , "which this module defines", "Write JOIN without THE to reach the program's own `JOIN`"
          , "or rename it to keep THE JOIN" ]
          []
          [("hides.l4", "JOIN MEANS 100\n\n" <> hidesJL4 "THE ")]

      it "refuses THE JOIN that hides an imported JOIN, and offers no rename" $
        refusedWith
          [ "main.l4:19:", "hides `JOIN`", "which this module imports"
          , "Write JOIN without THE to reach the program's own `JOIN`" ]
          [ "rename" ]
          [ ("lib.l4", "JOIN MEANS 100\n")
          , ("main.l4", "IMPORT lib.l4\n\n" <> hidesJL4 "THE ")
          ]

      it "deploys the same module written with JOIN and no THE" do
        result <- compiled [("hides.l4", "JOIN MEANS 100\n\n" <> hidesJL4 "")]
        case result of
          Left err -> expectationFailure ("Expected the deployment, but it was refused: " <> Text.unpack err)
          Right (fns, _meta) -> Map.keys fns `shouldBe` ["add one"]

      it "deploys THE JOIN where the program has no JOIN of its own" do
        result <- compiled [("hides.l4", hidesJL4 "THE ")]
        case result of
          Left err -> expectationFailure ("Expected the deployment, but it was refused: " <> Text.unpack err)
          Right (fns, _meta) -> Map.keys fns `shouldBe` ["add one"]

    it "rejects empty bundles" do
      logger <- newLogger False
      let sources = Map.empty :: Map FilePath Text
      result <- compileBundle logger "test" sources
      case result of
        Left err -> err `shouldBe` "No .l4 files found in bundle"
        Right _ -> expectationFailure "Expected compilation to fail for empty bundle"

    -- A module with a genuine type error must be rejected with the actual
    -- error, not compiled into a garbage schema. An @export with no GIVETH
    -- whose body fails to typecheck used to leave its return type as an
    -- unresolved inference variable (e.g. "res184"), which then tripped the
    -- breaking-change check with a baffling "return type changed to res184".
    it "rejects a module with a type error instead of leaking an inference variable" do
      logger <- newLogger False
      let sources = Map.singleton "broken.l4" $ Text.unlines
            [ "IMPORT prelude"
            , "IMPORT daydate"
            , ""
            , "@export The date this was last updated"
            , "`last updated on` MEANS Date 2 6"  -- no 2-arg `Date` overload
            ]
      result <- compileBundle logger "test" sources
      case result of
        Left err -> do
          err `shouldNotSatisfy` Text.isInfixOf "res"
          err `shouldSatisfy` (not . Text.null)
        Right (_fns, meta) ->
          expectationFailure $
            "Expected rejection, but compiled with return types: "
              <> show [fs.fsReturnType | fs <- meta.metaFunctions]

    -- Ruling M2, option A (2026-10-08). A clause group with no GIVEN has
    -- inputs that only the compiler named, and that nothing gives a type. It
    -- used to be published as the inputs `input 1` and `input 2`, typed
    -- "object", and every call to it failed; now the deploy is refused.
    it "refuses a module that @exports a clause group with no GIVEN" do
      logger <- newLogger False
      result <- compileBundle logger "test" (Map.singleton "size.l4" (exportedSizeGroup []))
      case result of
        Left err ->
          err `shouldSatisfy` Text.isInfixOf "`size` is published with @export, but its inputs have no names"
        Right (_fns, meta) ->
          expectationFailure $
            "Expected rejection, but published the inputs "
              <> show [Map.keys fs.fsParameters.parameterMap | fs <- meta.metaFunctions]

    -- Overloads written one after another are gathered by the parser and
    -- separated by the checker; the @export above the second one must stay
    -- with it (refutation of legalese/l4-ide#545's review, round 3).
    it "publishes the overload whose @export is written above it" do
      logger <- newLogger False
      result <- compileBundle logger "test" $ Map.singleton "twice.l4" $ Text.unlines
        [ "DECIDE twice n IS n * 2"
        , "@export the boolean version"
        , "DECIDE twice b IS b AND b"
        ]
      case result of
        Left err -> expectationFailure ("Compilation failed: " <> Text.unpack err)
        Right (_fns, meta) ->
          [(fs.fsName, Map.keys fs.fsParameters.parameterMap) | fs <- meta.metaFunctions] `shouldBe` [("twice", ["b"])]

    it "publishes the same clause group with a GIVEN, under the names it gives" do
      logger <- newLogger False
      result <- compileBundle logger "test" $ Map.singleton "size.l4" $ exportedSizeGroup
        [ "GIVEN c IS A Colour"
        , "      n IS A NUMBER"
        , "GIVETH A NUMBER"
        ]
      case result of
        Left err -> expectationFailure ("Compilation failed: " <> Text.unpack err)
        Right (_fns, meta) ->
          [Map.keys fs.fsParameters.parameterMap | fs <- meta.metaFunctions] `shouldBe` [["c", "n"]]

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------

-- | Run an action with no copy of the standard library in the places a test can
-- control, and put everything back afterwards: JL4_LIBRARY_PATH is dropped,
-- XDG_DATA_HOME points at an empty directory (the service looks in its
-- jl4/libraries), and the working directory is that empty directory too. The
-- path beside the executable is not touched. CI exports JL4_LIBRARY_PATH for the
-- whole run, and a developer's host can hold a library under
-- ~/.local/share/jl4/libraries, so either hides a wrapper that needed the
-- host's library.
withNoLibraryOnTheHost :: IO a -> IO a
withNoLibraryOnTheHost act = bracket acquire release (\(_, _, empty) -> withCurrentDirectory empty act)
  where
    acquire = do
      savedLibrary <- lookupEnv "JL4_LIBRARY_PATH"
      savedXdg <- lookupEnv "XDG_DATA_HOME"
      tmp <- getCanonicalTemporaryDirectory
      empty <- createTempDirectory tmp "jl4-service-no-library"
      createDirectoryIfMissing True empty
      unsetEnv "JL4_LIBRARY_PATH"
      setEnv "XDG_DATA_HOME" empty
      pure (savedLibrary, savedXdg, empty)
    release (savedLibrary, savedXdg, empty) = do
      restore "JL4_LIBRARY_PATH" savedLibrary
      restore "XDG_DATA_HOME" savedXdg
      removePathForcibly empty
    restore name = maybe (unsetEnv name) (setEnv name)

statusCode' :: Response a -> Int
statusCode' = statusCode . responseStatus

-- | A clause group published with @export, under the given signature lines
-- (none: no GIVEN at all).
exportedSizeGroup :: [Text] -> Text
exportedSizeGroup signature = Text.unlines $
  [ "DECLARE Colour IS ONE OF Red, Green, Blue"
  , ""
  , "@export"
  ] <> signature <>
  [ "DECIDE size Red   n IS n"
  , "DECIDE size Green n IS n + 1"
  , "DECIDE size Blue  n IS 0"
  ]

-- | What a client is meant to get back from an evaluation request.
data WireOutcome
  = Answers Aeson.Value
    -- ^ 200, with this JSON as the answer
  | Refuses Text
    -- ^ 422, with an error message that contains this text

shouldCarry :: Response LBS.ByteString -> WireOutcome -> Expectation
shouldCarry resp = \case
  Answers v -> (statusCode' resp, wireAt resp ["contents", "result", "value"]) `shouldBe` (200, Right v)
  Refuses t -> do
    statusCode' resp `shouldBe` 422
    wireAt resp ["contents", "contents"] `shouldSatisfy` \case
      Right (Aeson.String msg) -> t `Text.isInfixOf` msg
      _ -> False

-- | The value at a path in a response body, or the whole body when there is none.
wireAt :: Response LBS.ByteString -> [Aeson.Key] -> Either LBS.ByteString Aeson.Value
wireAt resp path =
  maybe (Left (responseBody resp)) Right $
    foldl (\mv k -> mv >>= \case Aeson.Object o -> Aeson.KeyMap.lookup k o; _ -> Nothing)
      (Aeson.decode (responseBody resp)) path

-- | Requests against 'wireProbeJL4': the 28 measured for smucclaw/l4-ide#1003,
-- then B7, B8, D3d and E1-E4. A pad of 1 keeps a request on the direct path
-- and a pad of {} sends it through the wrapper; on this endpoint a JSON null
-- is a missing input, and stays direct. Every 200 answer on the wrapper path
-- is the direct path's. Against main, A1-A7, B7, B8, C1 and C2 differ only by
-- legalese/l4-ide#162's encoding (null for NOTHING, a bare JUST, an enum name
-- without backticks), and D3 because main answered "NOTHING".
wireCases :: [(Text, Text, Aeson.Value, WireOutcome)]
wireCases =
  [ ("A1", "cap", args [n 5, direct], Answers Aeson.Null)
  , ("A2", "cap", args [n 5, wrapper], Answers Aeson.Null)
  , ("A3", "cap", args [n 15, direct], Answers (num 15))
  , ("A4", "cap", args [n 15, wrapper], Answers (num 15))
  , ("A5", "pass", args ["x" Aeson..= (5 :: Int)], Answers (num 5))
  , ("A6", "pass", args ["x" Aeson..= uncertain], Answers Aeson.Null)
  , ("A7", "pass", args ["x" Aeson..= Aeson.Null], Answers Aeson.Null)
  , ("B1", "single", args [n 5, direct], Answers (nums [5]))
  , ("B2", "single", args [n 5, wrapper], Answers (nums [5]))
  , ("B3", "double list", args [n 5, direct], Answers (nums [5, 5]))
  , ("B4", "double list", args [n 5, wrapper], Answers (nums [5, 5]))
  , ("B5", "none", args [n 5, direct], Answers (nums []))
  , ("B6", "none", args [n 5, wrapper], Answers (nums []))
  , ("B7", "maybe single", args [n 5, direct], Answers (nums [5]))
  , ("B8", "maybe single", args [n 5, wrapper], Answers (nums [5]))
  , ("C1", "outcome", args [n 15, direct], Answers (Aeson.String "fully covered"))
  , ("C2", "outcome", args [n 15, wrapper], Answers (Aeson.String "fully covered"))
  , ("C3", "pair", args [n 5, direct], Answers pair)
  , ("C4", "pair", args [n 5, wrapper], Answers pair)
  , ("C5", "solo", args [n 5, direct], Answers solo)
  , ("C6", "solo", args [n 5, wrapper], Answers solo)
  , ("C7", "big", args [n 15, direct], Answers (Aeson.Bool True))
  , ("C8", "big", args [n 15, wrapper], Answers (Aeson.Bool True))
  , ("C9", "twice", args [n 5, direct], Answers (num 10))
  , ("C10", "twice", args [n 5, wrapper], Answers (num 10))
    -- D1, D4 and D5 show that a pad of {} really takes the wrapper: their
    -- "Expected JSON number" comes from its JSONDECODE, which the direct path
    -- never runs. Should they stop saying so, the routing has changed, and the
    -- other wrapper rows may be testing the direct path twice.
  , ("D1", "twice", args ["n" Aeson..= ("abc" :: Text), wrapper], Refuses "Expected JSON number for field 'n' but got: String")
    -- The direct path does not check that a scalar matches its parameter's
    -- type, so this stops on an internal type error, as it did on main. That
    -- is main's answer, pinned as such, not a good one.
  , ("D2", "twice", args ["n" Aeson..= ("abc" :: Text), direct], Refuses "type error")
    -- main answered "NOTHING" here, as if the rule had.
  , ("D3", "twice", args [wrapper], Refuses "Missing required field 'n' in JSON object")
  , ("D3d", "twice", args [direct], Refuses "Parameter 'n': missing required parameter")
  , ("D4", "twice", args ["n" Aeson..= [1, 2 :: Int], wrapper], Refuses "Expected JSON number for field 'n' but got: Array")
  , ("D5", "twice", args ["n" Aeson..= Aeson.object ["a" Aeson..= (1 :: Int)], wrapper], Refuses "Expected JSON number for field 'n' but got: Object")
    -- A rule's own Nothing and Just are answers, not L4's MAYBE.
  , ("E1", "penalty", args [n 5, direct], Answers (Aeson.String "Nothing"))
  , ("E2", "penalty", args [n 5, wrapper], Answers (Aeson.String "Nothing"))
  , ("E3", "verdict", args [n 5, direct], Answers verdict)
  , ("E4", "verdict", args [n 5, wrapper], Answers verdict)
  ]
 where
  args = Aeson.object
  n :: Int -> (Aeson.Key, Aeson.Value)
  n v = "n" Aeson..= v
  direct = "pad" Aeson..= (1 :: Int)
  wrapper = "pad" Aeson..= uncertain
  uncertain = Aeson.object []
  num :: Int -> Aeson.Value
  num = Aeson.toJSON
  nums :: [Int] -> Aeson.Value
  nums = Aeson.toJSON
  pair = Aeson.object ["Pair" Aeson..= Aeson.object ["left" Aeson..= (5 :: Int), "right" Aeson..= (6 :: Int)]]
  solo = Aeson.object ["Solo" Aeson..= Aeson.object ["only" Aeson..= (5 :: Int)]]
  verdict = Aeson.object ["Just" Aeson..= Aeson.object ["reason" Aeson..= ("lawful" :: Text)]]

mkBatchCase :: Int -> Aeson.Value
mkBatchCase n = Aeson.object
  [ "@id" Aeson..= n
  , "walks" Aeson..= True
  , "eats" Aeson..= True
  , "drinks" Aeson..= True
  ]

-- | Run with this many capabilities, then put the count back.
withCapabilities :: Int -> IO a -> IO a
withCapabilities n act =
  bracket (getNumCapabilities <* setNumCapabilities n) setNumCapabilities (const act)

-- | Steps of 'spinJL4' that take about a fifth of a second (0.19 s on an
-- M-series Mac, 2026-10-02) and allocate about 1 GB.
spinFast :: Int
spinFast = 150_000

-- | Steps that take about a fifth of 'spinOptions'' 3-second limit (about 0.65 s).
spinFifth :: Int
spinFifth = 500_000

-- | The exponent at which 'powerJL4' takes 12 s to answer, nearly all of it
-- after the evaluator has returned (an M-series Mac, 2026-10-07: 3.1 s at
-- 20,000, with the number forced only by the JSON encoder).
powerSlow :: Int
powerSlow = 40_000

-- | Steps that would take some twenty minutes.
spinSlow :: Int
spinSlow = 1_000_000_000

-- | A 3-second time limit, and an allocation limit (100 GB) that a spinning
-- case cannot reach in three seconds, so the time limit is the one it meets.
spinOptions :: Options
spinOptions = testOptions { evalTimeout = 3, maxEvalMemoryMb = 100_000 }

-- | Post one batch of 'spinJL4' cases, the i-th spinning for the i-th count.
postSpinBatch :: String -> Manager -> String -> [Int] -> IO (Response LBS.ByteString)
postSpinBatch baseUrl mgr deployId = postBatchTo baseUrl mgr deployId "spin"

-- | Post one batch of cases to a function that takes @n@, the i-th with the
-- i-th value.
postBatchTo :: String -> Manager -> String -> String -> [Int] -> IO (Response LBS.ByteString)
postBatchTo baseUrl mgr deployId fnName steps = do
  let body = Aeson.object
        [ "outcomes" Aeson..= ([] :: [Text])
        , "cases" Aeson..=
            [ Aeson.object ["@id" Aeson..= i, "n" Aeson..= n] | (i, n) <- zip [1 :: Int ..] steps ]
        ]
  req <- buildJsonPost (baseUrl <> "/deployments/" <> deployId <> "/functions/" <> fnName <> "/evaluation/batch") body
  httpLbs req mgr

-- | The case objects of a batch response, as the service wrote them.
rawBatchCases :: Response LBS.ByteString -> [Aeson.Object]
rawBatchCases resp = case Aeson.decode (responseBody resp) of
  Just (Aeson.Object o) | Just (Aeson.Array cs) <- Aeson.KeyMap.lookup "cases" o ->
    [c | Aeson.Object c <- toList cs]
  _ -> error ("not a batch response: " <> show (responseBody resp))

-- | The batch was a 200, its cases came back with these outcomes in order, and
-- the summary counts the answered ones as processed and the rest as ignored.
expectBatchOutcomes :: Response LBS.ByteString -> [CaseOutcome] -> Expectation
expectBatchOutcomes resp expected = do
  unless (statusCode' resp == 200) $
    expectationFailure ("Expected a 200, got " <> show (statusCode' resp) <> ": " <> show (responseBody resp))
  case Aeson.decode (responseBody resp) :: Maybe BatchResponse of
    Nothing -> expectationFailure ("Failed to decode batch response: " <> show (responseBody resp))
    Just batch -> do
      map (.outcome) batch.cases `shouldBe` expected
      batch.summary.casesProcessed `shouldBe` length (filter (== CaseAnswered) expected)
      batch.summary.casesIgnored `shouldBe` length (filter (/= CaseAnswered) expected)

-- | Save sources to the BundleStore and register as DeploymentPending,
-- simulating a lazy-load restart. The sources exist on disk but are not compiled.
withPendingService :: Text -> [(FilePath, Text)] -> (String -> Manager -> IO a) -> IO a
withPendingService deployId sources act = do
  resOrExc <- try (withPendingService' deployId sources act)
  case resOrExc of
    Left ioe ->
      if isPermissionError ioe
        then pendingWith ("Skipping integration test (cannot bind sockets): " <> show ioe) >> pure undefined
        else do
          expectationFailure (show ioe)
          pure undefined
    Right result -> pure result

withPendingService' :: Text -> [(FilePath, Text)] -> (String -> Manager -> IO a) -> IO a
withPendingService' deployId sources act = withStoreDir (Text.unpack deployId) \tmpPath -> do
  store <- initStore tmpPath
  logger <- newLogger False

  -- Save sources to the BundleStore (so loadAndRegister can find them)
  let sourceMap = Map.fromList sources
      version = computeVersion sourceMap
      storedMeta = BundleStore.StoredMetadata
        { BundleStore.smVersion = version
        , BundleStore.smCreatedAt = "2026-01-01T00:00:00Z"
        , BundleStore.smDescription = Nothing
        , BundleStore.smServiceVersion = Nothing
        , BundleStore.smDeploymentVersion = Nothing
        }
  BundleStore.saveBundle store deployId sourceMap storedMeta

  -- Register as Pending (not compiled)
  registry <- newTVarIO $ Map.singleton (DeploymentId deployId) (DeploymentPending Nothing)
  pendingUpd <- newTVarIO Map.empty
  tasksReg <- newTVarIO Map.empty
  slots <- newBatchSlots
  let env = MkAppEnv registry pendingUpd store Nothing logger testOptions tasksReg slots

  mgr <- newManager defaultManagerSettings
  testWithApplication (pure $ app env) \port -> do
    let baseUrl = "http://localhost:" <> show port
    result <- act baseUrl mgr
    pure result

-- | Save sources to disk and register as DeploymentFailed,
-- simulating a deployment that failed to compile. Sources exist on disk.
withFailedService :: Text -> [(FilePath, Text)] -> (String -> Manager -> IO a) -> IO a
withFailedService deployId sources act = do
  resOrExc <- try (withFailedService' deployId sources act)
  case resOrExc of
    Left ioe ->
      if isPermissionError ioe
        then pendingWith ("Skipping integration test (cannot bind sockets): " <> show ioe) >> pure undefined
        else do
          expectationFailure (show ioe)
          pure undefined
    Right result -> pure result

withFailedService' :: Text -> [(FilePath, Text)] -> (String -> Manager -> IO a) -> IO a
withFailedService' deployId sources act = withStoreDir (Text.unpack deployId) \tmpPath -> do
  store <- initStore tmpPath
  logger <- newLogger False

  let sourceMap = Map.fromList sources
      version = computeVersion sourceMap
      storedMeta = BundleStore.StoredMetadata
        { BundleStore.smVersion = version
        , BundleStore.smCreatedAt = "2026-01-01T00:00:00Z"
        , BundleStore.smDescription = Nothing
        , BundleStore.smServiceVersion = Nothing
        , BundleStore.smDeploymentVersion = Nothing
        }
  BundleStore.saveBundle store deployId sourceMap storedMeta

  -- Register as Failed
  registry <- newTVarIO $ Map.singleton (DeploymentId deployId) (DeploymentFailed "Test: simulated compilation failure")
  pendingUpd <- newTVarIO Map.empty
  tasksReg <- newTVarIO Map.empty
  slots <- newBatchSlots
  let env = MkAppEnv registry pendingUpd store Nothing logger testOptions tasksReg slots

  mgr <- newManager defaultManagerSettings
  testWithApplication (pure $ app env) \port -> do
    let baseUrl = "http://localhost:" <> show port
    result <- act baseUrl mgr
    pure result

-- | Compile sources and register them directly in the TVar,
-- then run a test against the WAI app.
withServiceFromSources :: Text -> [(FilePath, Text)] -> (String -> Manager -> IO a) -> IO a
withServiceFromSources deployId sources act = do
  resOrExc <- try (withServiceFromSources' deployId sources act)
  case resOrExc of
    Left ioe ->
      if isPermissionError ioe
        then pendingWith ("Skipping integration test (cannot bind sockets): " <> show ioe) >> pure undefined
        else do
          expectationFailure (show ioe)
          pure undefined
    Right result -> pure result

withServiceFromSources' :: Text -> [(FilePath, Text)] -> (String -> Manager -> IO a) -> IO a
withServiceFromSources' deployId sources act = withStoreDir (Text.unpack deployId) \tmpPath -> do
  store <- initStore tmpPath
  logger <- newLogger False

  -- Compile the bundle directly
  let sourceMap = Map.fromList sources
  result <- compileBundle logger "test" sourceMap
  (fns, meta) <- case result of
    Left err -> fail ("Test setup: compilation failed: " <> Text.unpack err)
    Right (f, m) -> pure (f, m)

  -- Register directly in the TVar
  registry <- newTVarIO $ Map.singleton (DeploymentId deployId) (DeploymentReady fns meta)
  pendingUpd <- newTVarIO Map.empty
  tasksReg <- newTVarIO Map.empty
  slots <- newBatchSlots
  let env = MkAppEnv registry pendingUpd store Nothing logger testOptions tasksReg slots

  mgr <- newManager defaultManagerSettings
  testWithApplication (pure $ app env) \port -> do
    let baseUrl = "http://localhost:" <> show port
    result' <- act baseUrl mgr
    pure result'

-- | 'withServiceFromSources' under caller-chosen 'Options'.
--
-- The suite otherwise runs everything on 'testOptions', which sets every limit
-- generously enough never to fire — so no test can observe what happens when
-- one does. Tests of the limits themselves need to move one.
withServiceFromSourcesOpts
  :: Options -> Text -> [(FilePath, Text)] -> (String -> Manager -> IO a) -> IO a
withServiceFromSourcesOpts opts deployId sources act = do
  resOrExc <- try (withServiceFromSourcesOpts' opts deployId sources act)
  case resOrExc of
    Left ioe ->
      if isPermissionError ioe
        then pendingWith ("Skipping integration test (cannot bind sockets): " <> show ioe) >> pure undefined
        else do
          expectationFailure (show ioe)
          pure undefined
    Right result -> pure result

withServiceFromSourcesOpts'
  :: Options -> Text -> [(FilePath, Text)] -> (String -> Manager -> IO a) -> IO a
withServiceFromSourcesOpts' opts deployId sources act = withStoreDir (Text.unpack deployId) \tmpPath -> do
  store <- initStore tmpPath
  logger <- newLogger False

  let sourceMap = Map.fromList sources
  result <- compileBundle logger "test" sourceMap
  (fns, meta) <- case result of
    Left err -> fail ("Test setup: compilation failed: " <> Text.unpack err)
    Right (f, m) -> pure (f, m)

  registry <- newTVarIO $ Map.singleton (DeploymentId deployId) (DeploymentReady fns meta)
  pendingUpd <- newTVarIO Map.empty
  tasksReg <- newTVarIO Map.empty
  slots <- newBatchSlots
  let env = MkAppEnv registry pendingUpd store Nothing logger opts tasksReg slots

  mgr <- newManager defaultManagerSettings
  testWithApplication (pure $ app env) \port -> do
    let baseUrl = "http://localhost:" <> show port
    result' <- act baseUrl mgr
    pure result'

-- | 'withServiceFromSources', with the deployment registry itself handed to the
-- test.
--
-- Needed for properties that are invisible from the wire, because they are
-- about what the service /kept/ rather than what it answered. Memoisation is
-- the one this exists for: a handler that rebuilds its cache on every request
-- returns byte-identical responses to one that builds it once, so no sequence
-- of HTTP calls can tell them apart — but the registry can.
withServiceFromSourcesTVar
  :: Text
  -> [(FilePath, Text)]
  -> (TVar (Map DeploymentId DeploymentState) -> String -> Manager -> IO a)
  -> IO a
withServiceFromSourcesTVar deployId sources act = do
  resOrExc <- try (withServiceFromSourcesTVar' deployId sources act)
  case resOrExc of
    Left ioe ->
      if isPermissionError ioe
        then pendingWith ("Skipping integration test (cannot bind sockets): " <> show ioe) >> pure undefined
        else do
          expectationFailure (show ioe)
          pure undefined
    Right result -> pure result

withServiceFromSourcesTVar'
  :: Text
  -> [(FilePath, Text)]
  -> (TVar (Map DeploymentId DeploymentState) -> String -> Manager -> IO a)
  -> IO a
withServiceFromSourcesTVar' deployId sources act = withStoreDir (Text.unpack deployId) \tmpPath -> do
  store <- initStore tmpPath
  logger <- newLogger False

  let sourceMap = Map.fromList sources
  result <- compileBundle logger "test" sourceMap
  (fns, meta) <- case result of
    Left err -> fail ("Test setup: compilation failed: " <> Text.unpack err)
    Right (f, m) -> pure (f, m)

  registry <- newTVarIO $ Map.singleton (DeploymentId deployId) (DeploymentReady fns meta)
  pendingUpd <- newTVarIO Map.empty
  tasksReg <- newTVarIO Map.empty
  slots <- newBatchSlots
  let env = MkAppEnv registry pendingUpd store Nothing logger testOptions tasksReg slots

  mgr <- newManager defaultManagerSettings
  testWithApplication (pure $ app env) \port -> do
    let baseUrl = "http://localhost:" <> show port
    result' <- act registry baseUrl mgr
    pure result'

-- | Whether a deployed function currently holds a built 'CachedDecisionQuery'.
hasDecisionQueryCache :: TVar (Map DeploymentId DeploymentState) -> Text -> Text -> IO Bool
hasDecisionQueryCache registry deployId fnName = do
  reg <- readTVarIO registry
  pure case Map.lookup (DeploymentId deployId) reg of
    Just (DeploymentReady fns _) -> case Map.lookup fnName fns of
      Just vf -> Maybe.isJust vf.fnDecisionQueryCache
      Nothing -> False
    _ -> False

-- | Persist each deployment to the store as a deploy does (its sources and its
-- @metadata.json@), let the caller do something to the store while the service
-- is down, then throw the in-memory registry away and bring every deployment
-- back through the production restart path, 'DeploymentLoader.loadAndRegister'.
--
-- Every other helper in this file registers freshly-compiled
-- 'ValidatedFunction's straight into the TVar, which makes the whole suite
-- blind to anything that differs only after a restart. A restart used to read
-- a cache, @bundle.cbor@, that kept no part of an annotation but the
-- multi-clause mark, so a restarted service answered differently from the one
-- that was deployed: @\/query-plan@ answered 400 ("Can only visualize, as a
-- ladder diagram, a DECIDE that returns a boolean"), a @JSONDECODE@ lost its
-- record type, field descriptions vanished. These tests ask a question of a
-- fresh deployment and of a restarted one, and want the same answer.
--
-- The action gets the lines the restart logged, as JSON.
withServicesRestarted
  :: [(Text, [(FilePath, Text)])]
  -> (FilePath -> IO ())
  -- ^ Given the store's directory, while the service is down.
  -> ([Aeson.Value] -> String -> Manager -> IO a)
  -> IO a
withServicesRestarted = withServicesRestartedOpts testOptions

-- | 'withServicesRestarted' under the options the restarted service is given.
withServicesRestartedOpts
  :: Options
  -> [(Text, [(FilePath, Text)])]
  -> (FilePath -> IO ())
  -> ([Aeson.Value] -> String -> Manager -> IO a)
  -> IO a
withServicesRestartedOpts opts deployments editStore act = do
  resOrExc <- try (withServicesRestarted' opts deployments editStore act)
  case resOrExc of
    Left ioe ->
      if isPermissionError ioe
        then pendingWith ("Skipping integration test (cannot bind sockets): " <> show ioe) >> pure undefined
        else do
          expectationFailure (show ioe)
          pure undefined
    Right result -> pure result

withServicesRestarted'
  :: Options
  -> [(Text, [(FilePath, Text)])]
  -> (FilePath -> IO ())
  -> ([Aeson.Value] -> String -> Manager -> IO a)
  -> IO a
withServicesRestarted' opts deployments editStore act = withStoreDir "restarted" \tmpPath -> do
  store <- initStore tmpPath
  logger <- newLogger False

  forM_ deployments \(deployId, sources) -> do
    let sourceMap = Map.fromList sources
        storedMeta = BundleStore.StoredMetadata
          { BundleStore.smVersion = computeVersion sourceMap
          , BundleStore.smCreatedAt = "2026-01-01T00:00:00Z"
          , BundleStore.smDescription = Nothing
          , BundleStore.smServiceVersion = Nothing
          , BundleStore.smDeploymentVersion = Nothing
          }
    BundleStore.saveBundle store deployId sourceMap storedMeta

  editStore tmpPath

  -- The restart. Nothing survives it but the store on disk. The store's
  -- directory is the only one this call owns, so the log goes beside it. The
  -- file is closed, and read, before the service is up: a handle that is open
  -- for writing locks the file against being read.
  let logPath = takeDirectory tmpPath </> "restart.log"
  registry <- newTVarIO Map.empty
  withFile logPath WriteMode \h -> do
    restartLogger <- newLoggerTo h False
    DeploymentLoader.loadAllAndRegister restartLogger opts registry store (map fst deployments)
  logLines <- Maybe.mapMaybe Aeson.decodeStrict . BS8.lines <$> BS.readFile logPath

  pendingUpd <- newTVarIO Map.empty
  tasksReg <- newTVarIO Map.empty
  slots <- newBatchSlots
  let env = MkAppEnv registry pendingUpd store Nothing logger opts tasksReg slots

  mgr <- newManager defaultManagerSettings
  testWithApplication (pure $ app env) \port -> do
    let baseUrl = "http://localhost:" <> show port
    act logLines baseUrl mgr

-- | One deployment, restarted, and served.
--
-- Fails if the restart did not compile the deployment (see
-- 'assertRecompiled'), or did not leave it ready.
withServiceRestarted :: Text -> [(FilePath, Text)] -> (String -> Manager -> IO a) -> IO a
withServiceRestarted deployId sources act =
  withServicesRestarted [(deployId, sources)] (const (pure ())) \logLines baseUrl mgr -> do
    assertRecompiled deployId logLines
    status <- deploymentStatus baseUrl mgr deployId
    fmap (.dsStatus) status `shouldBe` Just "ready"
    act baseUrl mgr

-- | The restart compiled this deployment from its sources.
--
-- 'Compiler.compileBundle' logs @Compilation complete@ for a deployment with
-- functions. A restart that served the deployment from anything else (a cache
-- an older build kept, say) would not, and a test of what a restart serves
-- would then be a test of something other than the restart.
assertRecompiled :: Text -> [Aeson.Value] -> Expectation
assertRecompiled deployId logLines =
  unless ("Compilation complete" `elem` messagesAbout deployId logLines) $
    expectationFailure
      ( "Test setup: the restart did not compile " <> Text.unpack deployId
        <> " from its sources. It logged: " <> show (messagesAbout deployId logLines)
      )

-- | The messages a restart logged about one deployment.
messagesAbout :: Text -> [Aeson.Value] -> [Text]
messagesAbout deployId logLines =
  [ msg
  | Aeson.Object o <- logLines
  , Aeson.KeyMap.lookup "deploymentId" o == Just (Aeson.String deployId)
  , Just (Aeson.String msg) <- [Aeson.KeyMap.lookup "msg" o]
  ]

-- | A new file in the system's temporary directory, open for writing.
openTempFile' :: String -> IO (FilePath, Handle)
openTempFile' template = do
  tmp <- getCanonicalTemporaryDirectory
  dir <- createTempDirectory tmp template
  let path = dir </> "service.jsonl"
  h <- openFile path WriteMode
  pure (path, h)

-- | The errors a warning about one deployment prints for one of its files:
-- the @errors@ of the warnings that name the file.
errorsLoggedFor :: Text -> FilePath -> [Aeson.Value] -> [Text]
errorsLoggedFor deployId file logLines =
  [ err
  | Aeson.Object o <- logLines
  , Aeson.KeyMap.lookup "level" o == Just (Aeson.String "warn")
  , Aeson.KeyMap.lookup "deploymentId" o == Just (Aeson.String deployId)
  , Aeson.KeyMap.lookup "file" o == Just (Aeson.String (Text.pack file))
  , Just (Aeson.Array errs) <- [Aeson.KeyMap.lookup "errors" o]
  , Aeson.String err <- toList errs
  ]

-- | The annotation lines a warning says one deployment's file holds that the
-- lexer ignores: the @message@ of the "Ignored annotation" warnings that name
-- the file.
ignoredLoggedFor :: Text -> FilePath -> [Aeson.Value] -> [Text]
ignoredLoggedFor deployId file logLines =
  [ m
  | Aeson.Object o <- logLines
  , Aeson.KeyMap.lookup "level" o == Just (Aeson.String "warn")
  , Aeson.KeyMap.lookup "msg" o == Just (Aeson.String "Ignored annotation")
  , Aeson.KeyMap.lookup "deploymentId" o == Just (Aeson.String deployId)
  , Aeson.KeyMap.lookup "file" o == Just (Aeson.String (Text.pack file))
  , Just (Aeson.String m) <- [Aeson.KeyMap.lookup "message" o]
  ]

-- | The names in a deployment's list of functions, sorted.
functionNames :: LBS.ByteString -> [Text]
functionNames body = List.sort
  [ name
  | Just (Aeson.Array fns) <- [Aeson.decode body]
  , Aeson.Object o <- toList fns
  , Just (Aeson.Object f) <- [Aeson.KeyMap.lookup "function" o]
  , Just (Aeson.String name) <- [Aeson.KeyMap.lookup "name" f]
  ]

-- | The arguments that make @compute_qualifies@ true.
allTrueArgs :: Aeson.Value
allTrueArgs = Aeson.object
  [ "arguments" Aeson..= Aeson.object
      [ "walks" Aeson..= True
      , "eats" Aeson..= True
      , "drinks" Aeson..= True
      ]
  ]

-- | Change one of a deployment's stored sources, while the service is down.
-- Fails if the edit changes nothing, so that a pattern that stopped matching
-- cannot turn a test into one about an unedited deployment.
editSource :: Text -> FilePath -> (Text -> Text) -> FilePath -> IO ()
editSource deployId file edit storeDir = do
  let path = storeDir </> Text.unpack deployId </> "sources" </> file
  old <- Text.IO.readFile path
  let new = edit old
  when (new == old) $ fail ("Test setup: the edit did not change " <> path)
  Text.IO.writeFile path new

-- | A deployment's status, as the control plane reports it.
deploymentStatus :: String -> Manager -> Text -> IO (Maybe DeploymentStatusResponse)
deploymentStatus baseUrl mgr deployId = do
  resp <- httpGet mgr (baseUrl <> "/deployments/" <> Text.unpack deployId)
  pure (Aeson.decode (responseBody resp))

-- | A response reduced to what a caller sees: the status and the decoded body,
-- with the deployment's ID (also as the OpenAPI operation IDs spell it, with
-- underscores) and the service's address blanked so that two deployments of the
-- same sources can be compared.
answerOf :: String -> Text -> Response LBS.ByteString -> (Int, Maybe Aeson.Value)
answerOf baseUrl deployId resp =
  ( statusCode' resp
  , Aeson.decode
      (LBS.fromStrict (Text.Encoding.encodeUtf8
        ( Text.replace (Text.replace "-" "_" deployId) "DEPLOYMENT"
        . Text.replace deployId "DEPLOYMENT"
        . Text.replace (Text.pack baseUrl) "BASE"
        . Text.Encoding.decodeUtf8
        . LBS.toStrict
        $ responseBody resp)))
  )

asObject :: Aeson.Value -> Maybe Aeson.Object
asObject (Aeson.Object o) = Just o
asObject _ = Nothing

-- | The @value@ of an evaluation's answer:
-- @{"tag": "SimpleResponse", "contents": {"result": {"value": ...}}}@.
resultValue :: Maybe Aeson.Value -> Maybe Aeson.Value
resultValue body = do
  Aeson.Object c <- lookupKey "contents" (body >>= asObject)
  Aeson.Object r <- Aeson.KeyMap.lookup "result" c
  Aeson.KeyMap.lookup "value" r

httpGet :: Manager -> String -> IO (Response LBS.ByteString)
httpGet mgr url = do
  req <- parseRequest url
  httpLbs req mgr

-- | Ask the same questions of one deployment twice: on the freshly compiled
-- functions, and on a service that came back from the store.
--
-- The probe gets the base URL, the HTTP manager and the deployment's ID, and
-- returns whatever it saw. The two runs use different IDs, so the probe must
-- not depend on the ID in what it returns ('answerOf' blanks it).
beforeAndAfterRestart
  :: Text -> [(FilePath, Text)] -> (String -> Manager -> Text -> IO a) -> IO (a, a)
beforeAndAfterRestart deployId sources probe = do
  let freshId = deployId <> "-fresh"
      restartedId = deployId <> "-restarted"
  fresh <- withServiceFromSources freshId sources \baseUrl mgr -> probe baseUrl mgr freshId
  restarted <- withServiceRestarted restartedId sources \baseUrl mgr -> probe baseUrl mgr restartedId
  pure (fresh, restarted)

-- | Start a service with an empty deployment registry.
withEmptyService :: (String -> Manager -> IO a) -> IO a
withEmptyService act = do
  resOrExc <- try (withEmptyService' act)
  case resOrExc of
    Left ioe ->
      if isPermissionError ioe
        then pendingWith ("Skipping integration test (cannot bind sockets): " <> show ioe) >> pure undefined
        else do
          expectationFailure (show ioe)
          pure undefined
    Right result -> pure result

withEmptyService' :: (String -> Manager -> IO a) -> IO a
withEmptyService' act = withStoreDir "empty" \tmpPath -> do
  store <- initStore tmpPath
  logger <- newLogger False
  registry <- newTVarIO Map.empty
  pendingUpd <- newTVarIO Map.empty
  tasksReg <- newTVarIO Map.empty
  slots <- newBatchSlots
  let env = MkAppEnv registry pendingUpd store Nothing logger testOptions tasksReg slots

  mgr <- newManager defaultManagerSettings
  testWithApplication (pure $ app env) \port -> do
    let baseUrl = "http://localhost:" <> show port
    result <- act baseUrl mgr
    pure result

-- | Evaluate a function via the API.
evalFunction :: String -> Manager -> Text -> Text -> Aeson.Value -> IO (Response LBS.ByteString)
evalFunction baseUrl mgr deployId fnName body = do
  req <- buildJsonPost (baseUrl <> "/deployments/" <> Text.unpack deployId <> "/functions/" <> Text.unpack fnName <> "/evaluation") body
  httpLbs req mgr

-- | The report a response states it carries, if it states one.
reportOf :: Response LBS.ByteString -> Maybe Text
reportOf resp = case Aeson.decode (responseBody resp) of
  Just (Aeson.Object o) | Just (Aeson.String r) <- Aeson.KeyMap.lookup "report" o -> Just r
  _ -> Nothing

-- | The report an MCP tool result's text states, the text being an encoded
-- evaluation response.
reportOfText :: Text -> Maybe Text
reportOfText t = case Aeson.decode (LBS.fromStrict (Text.Encoding.encodeUtf8 t)) of
  Just (Aeson.Object o) | Just (Aeson.String r) <- Aeson.KeyMap.lookup "report" o -> Just r
  _ -> Nothing

-- | Whether an MCP @tools/call@ result is an error, and its first text.
mcpToolText :: LBS.ByteString -> Maybe (Bool, Text)
mcpToolText body = do
  Aeson.Object o <- Aeson.decode body
  Aeson.Object r <- Aeson.KeyMap.lookup "result" o
  Aeson.Array cs <- Aeson.KeyMap.lookup "content" r
  Aeson.Object c : _ <- pure (toList cs)
  Aeson.String t <- Aeson.KeyMap.lookup "text" c
  let isErr = case Aeson.KeyMap.lookup "isError" r of
        Just (Aeson.Bool b) -> b
        _                   -> False
  pure (isErr, t)

-- | Assert a successful evaluation response.
assertSuccess :: Response LBS.ByteString -> (ResponseWithReason -> IO ()) -> IO ()
assertSuccess resp check = do
  statusCode' resp `shouldBe` 200
  case Aeson.decode (responseBody resp) :: Maybe SimpleResponse of
    Nothing -> expectationFailure ("Failed to decode eval response: " <> show (responseBody resp))
    Just (SimpleResponse r) -> check r
    Just (SimpleError e) -> expectationFailure ("Evaluation error: " <> show e)

-- | Assert an evaluation stopped on the placeholder for a missing BOOLEAN input.
assertNotSupplied :: Response LBS.ByteString -> Text -> IO ()
assertNotSupplied resp name =
  case Aeson.decode (responseBody resp) :: Maybe SimpleResponse of
    Just (SimpleError (InterpreterError msg)) ->
      msg `shouldSatisfy` Text.isInfixOf ("`" <> name <> " (not supplied)`")
    other ->
      expectationFailure ("Expected evaluation to stop on " <> show name <> ", got: " <> show other)

-- | Poll a deployment until its status is "ready", with a timeout in seconds.
pollUntilReady :: String -> Manager -> String -> Int -> IO ()
pollUntilReady baseUrl mgr deployId timeoutSec = go timeoutSec
 where
  go 0 = expectationFailure $ "Deployment " <> deployId <> " did not become ready within timeout"
  go remaining = do
    req <- parseRequest (baseUrl <> "/deployments/" <> deployId)
    resp <- httpLbs req mgr
    let mStatus = Aeson.decode (responseBody resp) :: Maybe DeploymentStatusResponse
    case mStatus of
      Just s | s.dsStatus == "ready" -> pure ()
      Just s | s.dsStatus == "failed" ->
        expectationFailure $ "Deployment failed: " <> show s.dsError
      _ -> do
        threadDelay 500_000  -- 0.5 seconds
        go (remaining - 1)

-- | Create a zip archive from a list of (filename, content) pairs.
createZipBundle :: [(FilePath, Text)] -> LBS.ByteString
createZipBundle entries =
  Zip.fromArchive $ foldr addEntry Zip.emptyArchive entries
 where
  addEntry (path, content) archive =
    Zip.addEntryToArchive
      (Zip.toEntry path 0 (LBS.fromStrict $ Text.Encoding.encodeUtf8 content))
      archive

-- | Build a multipart POST request with an "id" field and a "sources" zip file.
buildMultipartRequest :: String -> Text -> LBS.ByteString -> IO Request
buildMultipartRequest url deployId zipBytes = do
  req <- parseRequest url
  let boundary = "----TestBoundary12345" :: BS.ByteString
      crlf = "\r\n" :: BS.ByteString
      dashdash = "--" :: BS.ByteString
      bodyParts =
        [ dashdash <> boundary <> crlf
        , "Content-Disposition: form-data; name=\"id\"" <> crlf <> crlf
        , Text.Encoding.encodeUtf8 deployId <> crlf
        , dashdash <> boundary <> crlf
        , "Content-Disposition: form-data; name=\"sources\"; filename=\"bundle.zip\"" <> crlf
        , "Content-Type: application/zip" <> crlf <> crlf
        ]
      body = LBS.fromChunks bodyParts <> zipBytes <> LBS.fromChunks [crlf, dashdash <> boundary <> dashdash <> crlf]
  pure req
    { method = "POST"
    , requestBody = RequestBodyLBS body
    , requestHeaders = [("Content-Type", "multipart/form-data; boundary=" <> boundary)]
    }

-- | Build a JSON POST request.
buildJsonPost :: String -> Aeson.Value -> IO Request
buildJsonPost url body = do
  req <- parseRequest url
  pure req
    { method = "POST"
    , requestBody = RequestBodyLBS (Aeson.encode body)
    , requestHeaders = [("Content-Type", "application/json")]
    }

-- | Query a function's query-plan via the API.
queryPlan' :: String -> Manager -> Text -> Text -> Aeson.Value -> IO (Response LBS.ByteString)
queryPlan' baseUrl mgr deployId fnName body = do
  req <- buildJsonPost (baseUrl <> "/deployments/" <> Text.unpack deployId <> "/functions/" <> Text.unpack fnName <> "/query-plan") body
  httpLbs req mgr

-- | Fetch a function's ladder diagram via the API.
getLadder :: String -> Manager -> Text -> Text -> IO (Response LBS.ByteString)
getLadder baseUrl mgr deployId fnName = do
  req <- parseRequest (baseUrl <> "/deployments/" <> Text.unpack deployId <> "/functions/" <> Text.unpack fnName <> "/ladder")
  httpLbs req mgr

-- | The @params@ list of a serialised @FunDecl@ object.
ladderParams :: Aeson.Object -> [Aeson.Value]
ladderParams fd =
  case Aeson.KeyMap.lookup "params" fd of
    Just (Aeson.Array xs) -> toList xs
    _ -> []

-- | The @$type@ tag of a serialised @FunDecl@'s body.
ladderBodyType :: Aeson.Object -> Maybe Text
ladderBodyType fd =
  case Aeson.KeyMap.lookup "body" fd of
    Just (Aeson.Object b) ->
      case Aeson.KeyMap.lookup "$type" b of
        Just (Aeson.String t) -> Just t
        _ -> Nothing
    _ -> Nothing

-- | Walk a serialised ladder body, collecting one field from every leaf that
-- carries an @atomId@ (i.e. @UBoolVar@ and @App@ nodes).
ladderLeafField :: Text -> Aeson.Object -> [Text]
ladderLeafField field fd = maybe [] go (Aeson.KeyMap.lookup "body" fd)
 where
  go :: Aeson.Value -> [Text]
  go (Aeson.Object o) =
    let here = case Aeson.KeyMap.lookup (Aeson.Key.fromText field) o of
          Just (Aeson.String t) -> [t]
          Just (Aeson.Object nm) -> case Aeson.KeyMap.lookup "label" nm of
            Just (Aeson.String t) -> [t]
            _ -> []
          _ -> []
        kids = concatMap go (Aeson.KeyMap.elems o)
     in here <> kids
  go (Aeson.Array xs) = concatMap go (toList xs)
  go _ = []

-- | Labels of the ladder's atoms, sorted for a stable comparison.
ladderAtomLabels :: Aeson.Object -> [Text]
ladderAtomLabels = List.sort . ladderLeafField "name"

-- | The @atomId@s embedded in the ladder's leaves.
ladderAtomIds :: Aeson.Object -> [Text]
ladderAtomIds = ladderLeafField "atomId"

-- | Each leaf's @atomId@ with its @unique@ (@name.unique@).
ladderLeafAtoms :: Aeson.Object -> [(Text, Int)]
ladderLeafAtoms fd = maybe [] go (Aeson.KeyMap.lookup "body" fd)
 where
  go :: Aeson.Value -> [(Text, Int)]
  go (Aeson.Object o) =
    let here = case (Aeson.KeyMap.lookup "atomId" o, Aeson.KeyMap.lookup "name" o) of
          (Just (Aeson.String a), Just (Aeson.Object nm))
            | Just (Aeson.Number n) <- Aeson.KeyMap.lookup "unique" nm -> [(a, round n)]
          _ -> []
     in here <> concatMap go (Aeson.KeyMap.elems o)
  go (Aeson.Array xs) = concatMap go (toList xs)
  go _ = []

-- | Decode a JSON response body as an Aeson Object.
decodeObject :: LBS.ByteString -> Maybe Aeson.Object
decodeObject = Aeson.decode

-- | Look up a key in a Maybe Object.
lookupKey :: Text -> Maybe Aeson.Object -> Maybe Aeson.Value
lookupKey k = (>>= Aeson.KeyMap.lookup (Aeson.Key.fromText k))

-- | Look up a JSON array in a Maybe Object, returning its length.
lookupArrayLength :: Text -> Maybe Aeson.Object -> Maybe Int
lookupArrayLength k obj = do
  v <- lookupKey k obj
  arr <- Aeson.decode (Aeson.encode v) :: Maybe [Aeson.Value]
  Just (length arr)

-- | Safe head for lists — avoids partial function warning.
safeHead :: [a] -> a
safeHead (x:_) = x
safeHead [] = error "safeHead: empty list"

-- | Default options for tests.
testOptions :: Options
testOptions = Options
  { port = 0
  , storePath = "/tmp/jl4-service-test"
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
  , checkStore = Nothing
  , checkJson = False
  }

-- | A JSON answer without the numbers the visualizer gave its nodes: the
-- @id@ and @unique@ fields, the per-node @impact@ table keyed by them, and the
-- document version. What is left is the shape of the answer and its atom ids.
withoutNodeIds :: Aeson.Value -> Aeson.Value
withoutNodeIds = \case
  Aeson.Object o ->
    Aeson.Object (Aeson.KeyMap.map withoutNodeIds
      (Aeson.KeyMap.filterWithKey (\k _ -> k `notElem` ["id", "unique", "impact", "verDocId"]) o))
  Aeson.Array xs -> Aeson.Array (fmap withoutNodeIds xs)
  v -> v
