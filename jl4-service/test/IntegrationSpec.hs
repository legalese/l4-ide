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

import Control.Monad (forM, forM_, guard, unless, when)
import Control.Concurrent (threadDelay)
import Control.Concurrent.STM (newTVarIO)
import Control.Exception (bracket, try)
import System.Timeout (timeout)
import Data.Foldable (for_, toList)
import Data.IORef (newIORef, readIORef, writeIORef)
import qualified Data.List as List
import Data.Time.Clock.POSIX (getPOSIXTime)
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
import qualified Data.Text.Encoding as Text.Encoding
import Network.HTTP.Client (defaultManagerSettings, newManager, httpLbs, parseRequest, requestBody, requestHeaders, method, Request, RequestBody (..), Response, responseStatus, responseBody, Manager)
import Network.HTTP.Types.Status (statusCode)
import Network.Wai.Handler.Warp (testWithApplication)
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, getTemporaryDirectory, removeDirectoryRecursive, removePathForcibly, withCurrentDirectory)
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.FilePath ((</>))
import System.IO (Handle, IOMode (..), hClose, openFile, withFile)
import TestData (deonticDeadlineJL4, deonticShapesJL4, deonticValueActionJL4)
import System.IO.Error (isPermissionError)
import TestData (inputThenInputJL4, synonymKindsJL4, synonymParamJL4, synonymWrapperJL4)

import TestData (qualifiesJL4, recordJL4, maybeParamJL4, saleContractJL4, deonticExportJL4, deonticRecordPartyJL4, spacedFieldsJL4, assumeParamJL4, importedRecordDeclJL4, importedRecordMainJL4, wireProbeJL4, declineLabelsJL4, twoDatesJL4, lineBreakJL4, clauseGroupEnumJL4, handEnumJL4, letEnumJL4, clauseGroupMixedJL4, handMixedJL4, clauseGroupSingleJL4, handSingleJL4, clauseGroupCallJL4, handCallJL4, clauseTableJL4, handTableJL4, clauseTable2JL4, handTable2JL4, clauseNewNameJL4, handNewNameJL4, clauseGroupNoGivethJL4, clauseGroupLetResultJL4, letChainJL4, longClausesJL4, longNumberClausesJL4, catchAllHugeJL4, handCatchAllHugeJL4, newNameHugeJL4, newNameDnfJL4, maybeTableJL4, exactlyNameDnfJL4, exactlyHugeJL4, dnfClauseJL4, handDnfJL4, jsonDecodePersonJL4, taxpayerJL4, implicitFlagJL4, nameClashJL4, partialClausesJL4)

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

    -- A synonym for a MAYBE is a MAYBE: the service read only a type written
    -- as MAYBE itself, so a value given for `MaybeYear` reached the rule as a
    -- bare number ("reached a CONSIDER that has no branch for it") and a null
    -- or an omitted one was "missing required parameter", both a 422.
    it "reads a synonym for a MAYBE as a MAYBE: a value, a null and an omitted one" do
      withServiceFromSources "maybe-synonym" [("synonym.l4", synonymParamJL4)] \baseUrl mgr ->
        forM_ ["year maybe", "optional number" :: Text] \fn -> do
          let answer args = do
                resp <- evalFunction baseUrl mgr "maybe-synonym" fn
                  (Aeson.object [ "arguments" Aeson..= Aeson.object args ])
                pure ( statusCode' resp
                     , case Aeson.decode (responseBody resp) of
                         Just (SimpleResponse r) -> Map.lookup "value" r.fnResult
                         _ -> Nothing )
          answer [ "y" Aeson..= (2020 :: Int) ] >>= (`shouldBe` (200, Just (FnLitInt 2021)))
          answer [ "y" Aeson..= Aeson.Null ]    >>= (`shouldBe` (200, Just (FnLitInt 0)))
          answer []                             >>= (`shouldBe` (200, Just (FnLitInt 0)))

    -- Three kinds of request go through the generated wrapper and not the direct
    -- path: an input whose value is `{}`, a batch case with a `null`, and an MCP
    -- call with a `null`. The wrapper read the head of an input's type only, so
    -- it took a synonym for a MAYBE as a required input and refused the null as
    -- "missing required parameter" (for `Optional OF NUMBER`, with a parser
    -- error). `plain maybe` is the control that always answered.
    describe "a synonym for a MAYBE, on the wrapper path" do
      let deployId = "maybe-synonym-wrapper"
          withSynonyms = withServiceFromSources deployId [("synonym.l4", synonymParamJL4)]
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

    -- Every kind these examples cover is answered on the wrapper path. The JSON
    -- decoder expands a synonym for a record, an enum or a DATE, which is why
    -- those answer (stop it expanding and only those examples fail); a synonym for
    -- a LIST, a TIME, a DATETIME or a BOOLEAN answers because the wrapper leaves
    -- its name alone. Only a synonym for a MAYBE is expanded in the wrapper
    -- ('Backend.Jl4.maybeSynonymHeads', pinned above). Expanding every head would
    -- break the LIST, TIME and DATETIME ones, because the wrapper fails each
    -- written out, so these examples fail if a later change does that.
    -- Each request below has a spare MAYBE input, pad, that is @null@ or @{}@,
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

    -- A synonym for a BOOLEAN answers when the host has no copy of the standard
    -- library in the places this example controls: a bundle's import of the
    -- standard library is served from the one built into the service
    -- (StdlibResolutionSpec). So this passes whatever the host holds, and with
    -- every head expanded too: it pins the answer, and does not tell the rules
    -- apart, and it fails in no state of `Backend/Jl4.hs`. Around its call it drops
    -- JL4_LIBRARY_PATH and puts XDG_DATA_HOME and the working directory in an empty
    -- directory; the path beside the executable, which the service also searches,
    -- it does not touch.
    it "answers a synonym for a BOOLEAN when the host has no library to import" do
      withNoLibraryOnTheHost $
        withServiceFromSources "wrapper-synonym-bool" [("synonym.l4", synonymWrapperJL4)] \baseUrl mgr -> do
          resp <- evalFunction baseUrl mgr "wrapper-synonym-bool" "flag code"
            (Aeson.object [ "arguments" Aeson..= Aeson.object [ "b" Aeson..= True, "pad" Aeson..= Aeson.object [] ] ])
          let value = case Aeson.decode (responseBody resp) of
                Just (SimpleResponse r) -> Map.lookup "value" r.fnResult
                _ -> Nothing
          (statusCode' resp, value) `shouldBe` (200, Just (FnLitInt 1))

    -- The same fault showed on a synonym for a record, an enum and a list: the
    -- service looked for each by the synonym's own name, and answered
    -- "FnObject but expected type is not a known record", "check equality on
    -- types that do not support it" and "FnArray but expected type is not LIST".
    it "reads a synonym for a record, an enum and a list as the type it stands for" do
      withServiceFromSources "kinds-synonym" [("kinds.l4", synonymKindsJL4)] \baseUrl mgr -> do
        let answer fn args = do
              resp <- evalFunction baseUrl mgr "kinds-synonym" fn
                (Aeson.object [ "arguments" Aeson..= Aeson.object args ])
              pure ( statusCode' resp
                   , case Aeson.decode (responseBody resp) of
                       Just (SimpleResponse r) -> Map.lookup "value" r.fnResult
                       _ -> Nothing )
        answer "point x" [ "p" Aeson..= Aeson.object [ "x" Aeson..= (5 :: Int) ] ]
          >>= (`shouldBe` (200, Just (FnLitInt 5)))
        answer "hue code" [ "h" Aeson..= ("Red" :: Text) ] >>= (`shouldBe` (200, Just (FnLitInt 1)))
        answer "hue code" [ "h" Aeson..= ("Green" :: Text) ] >>= (`shouldBe` (200, Just (FnLitInt 2)))
        answer "first year" [ "ys" Aeson..= [2020, 2021 :: Int] ] >>= (`shouldBe` (200, Just (FnLitInt 2020)))

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
      -- the wrapper; and a case that errors comes back with its @error, the
      -- batch still answering 200.
      it "batch, where null takes the wrapper: cap, single and twice" \(baseUrl, mgr) -> do
        let batch fn cases = do
              req <- buildJsonPost (baseUrl <> "/deployments/wire/functions/" <> fn <> "/evaluation/batch")
                (Aeson.object ["outcomes" Aeson..= ([] :: [Text]), "cases" Aeson..= cases])
              httpLbs req mgr
            input :: Int -> [(Aeson.Key, Aeson.Value)] -> Aeson.Value
            input caseId kvs = Aeson.object (("@id" Aeson..= caseId) : ("pad" Aeson..= Aeson.Null) : kvs)
            n :: Int -> [(Aeson.Key, Aeson.Value)]
            n v = ["n" Aeson..= v]
            answers resp = do
              Aeson.Array cs <- either (const Nothing) Just (wireAt resp ["cases"])
              Aeson.Number ignored <- either (const Nothing) Just (wireAt resp ["summary", "casesIgnored"])
              pure ([ Aeson.KeyMap.lookup "value" c | Aeson.Object c <- toList cs ], ignored)
        cap <- batch "cap" [input 1 (n 5), input 2 (n 15)]
        answers cap `shouldBe` Just ([Just Aeson.Null, Just (Aeson.Number 15)], 0)
        single <- batch "single" [input 1 (n 5)]
        answers single `shouldBe` Just ([Just (Aeson.toJSON [5 :: Int])], 0)
        -- Case 1 has no n. It used to come back answered "NOTHING", and then
        -- not at all, counted only in casesIgnored.
        twice <- batch "twice" [input 1 [], input 2 (n 4)]
        answers twice `shouldBe` Just ([Nothing, Just (Aeson.Number 8)], 1)
        caseKeys twice ["@id", "@error"] `shouldBe`
          Just [ [Just (Aeson.Number 1), Just (Aeson.String "Parameter 'n': missing required parameter")]
               , [Just (Aeson.Number 2), Nothing] ]

    describe "when the wrapper cannot call the function" do
      it "quotes a DATE it could not read, and names a missing one" do
        withServiceFromSources "decline-date" [("labels.l4", declineLabelsJL4)] \baseUrl mgr -> do
          let call d = evalFunction baseUrl mgr "decline-date" "date%20first" $ Aeson.object
                [ "arguments" Aeson..= Aeson.object (("pad" Aeson..= Aeson.object []) : d) ]
          unread <- call ["end date" Aeson..= ("garbage" :: Text)]
          unread `shouldCarry` Refuses "Parameter 'end date': could not read \"garbage\" as a DATE"
          missing <- call []
          missing `shouldCarry` Refuses "Parameter 'end date': missing required parameter"

      it "names the DATE TODATE could not read, not one it could" do
        withServiceFromSources "decline-dates" [("dates.l4", twoDatesJL4)] \baseUrl mgr -> do
          let call one two = evalFunction baseUrl mgr "decline-dates" "later" $ Aeson.object
                [ "arguments" Aeson..= Aeson.object
                    [ "d one" Aeson..= (one :: Text), "d two" Aeson..= (two :: Text), "pad" Aeson..= Aeson.object [] ] ]
          readable <- call "2026/01/31" "2026-02-28"
          readable `shouldCarry` Answers (Aeson.Number 1)
          declined <- call "2026/01/31" "2026-02-30"
          declined `shouldCarry` Refuses "Parameter 'd two': could not read \"2026-02-30\" as a DATE"

      -- On batch a null takes the wrapper, which refuses "garbage" as a DATE.
      -- The direct path would answer it as text, so an errored case shows the
      -- wrapper ran. The case comes back with the wrapper's message as its
      -- @error, where it used to be dropped and only counted. A single request
      -- gets that message only on the wrapper path, with a {} in an input; with
      -- this null it stays direct and answers "garbage".
      it "returns a batch case the wrapper declines with its @error, and counts it" do
        withServiceFromSources "decline-batch" [("labels.l4", declineLabelsJL4)] \baseUrl mgr -> do
          req <- buildJsonPost (baseUrl <> "/deployments/decline-batch/functions/date%20first/evaluation/batch")
            (Aeson.object
              [ "outcomes" Aeson..= ([] :: [Text])
              , "cases" Aeson..=
                  [ Aeson.object ["@id" Aeson..= (1 :: Int), "end date" Aeson..= ("garbage" :: Text), "pad" Aeson..= Aeson.Null]
                  , Aeson.object ["@id" Aeson..= (2 :: Int), "end date" Aeson..= ("2026-01-31" :: Text), "pad" Aeson..= Aeson.Null]
                  ]
              ])
          resp <- httpLbs req mgr
          statusCode' resp `shouldBe` 200
          wireAt resp ["summary", "casesIgnored"] `shouldBe` Right (Aeson.Number 1)
          wireAt resp ["summary", "casesProcessed"] `shouldBe` Right (Aeson.Number 1)
          caseKeys resp ["@id", "@error", "value"] `shouldBe`
            Just [ [ Just (Aeson.Number 1)
                   , Just (Aeson.String "Parameter 'end date': could not read \"garbage\" as a DATE")
                   , Nothing ]
                 , [Just (Aeson.Number 2), Nothing, Just (Aeson.String "2026-01-31")] ]
          -- and a client decoding the body reads the same outcomes
          fmap (map (.outcome) . (.cases)) (Aeson.decode (responseBody resp) :: Maybe BatchResponse)
            `shouldBe` Just [CaseErrored "Parameter 'end date': could not read \"garbage\" as a DATE", CaseAnswered]

      it "names a missing ASSUME as the direct path does" do
        withServiceFromSources "decline-assume" [("labels.l4", declineLabelsJL4)] \baseUrl mgr -> do
          let call rate = evalFunction baseUrl mgr "decline-assume" "plus%20rate" $
                Aeson.object ["arguments" Aeson..= Aeson.object (("n" Aeson..= (1 :: Int)) : rate)]
          wrapped <- call ["rate" Aeson..= Aeson.object []]
          wrapped `shouldCarry` Refuses "ASSUME 'rate': missing required parameter"
          direct <- call []
          direct `shouldCarry` Refuses "ASSUME 'rate': missing required parameter"

      it "names a missing input of a deontic rule" do
        withServiceFromSources "decline-deontic" [("seatbelt.l4", deonticRecordPartyJL4)] \baseUrl mgr -> do
          resp <- evalFunction baseUrl mgr "decline-deontic" "Seatbelt Requirement"
            (Aeson.object
              [ "arguments" Aeson..= Aeson.object
                  [ "car" Aeson..= Aeson.object ["number of wheels" Aeson..= (4 :: Int)] ]
              , "startTime" Aeson..= (0 :: Int)
              , "events" Aeson..= ([] :: [Aeson.Value])
              ])
          resp `shouldCarry` Refuses "Parameter 'driver': missing required parameter"

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
      -- A timeout of zero is over before the plan is computed. A plan left to
      -- be computed while the response was sent was under no limit of ours,
      -- and one that took too long lost its connection without a reason.
      withServicesRestartedOpts testOptions {evalTimeout = 0}
        [("qp-timeout", [("qualifies.l4", qualifiesJL4)])] (const (pure ())) \_ baseUrl mgr -> do
          status <- deploymentStatus baseUrl mgr "qp-timeout"
          fmap (.dsStatus) status `shouldBe` Just "ready"
          resp <- queryPlan' baseUrl mgr "qp-timeout" "compute_qualifies"
            (Aeson.object ["arguments" Aeson..= Aeson.object []])
          statusCode' resp `shouldBe` 500
          lookupKey "error" (decodeObject (responseBody resp))
            `shouldBe` Just (Aeson.String "Query plan timed out")

    it "returns 404 for unknown function" do
      withServiceFromSources "qp-404" [("qualifies.l4", qualifiesJL4)] \baseUrl mgr -> do
        resp <- queryPlan' baseUrl mgr "qp-404" "no_such_fn"
          (Aeson.object ["arguments" Aeson..= Aeson.object []])
        statusCode' resp `shouldBe` 404

    -- A rule written as DECIDE clauses is the same rule as the CONSIDER it
    -- stands for, so its plan, with the ladder the plan carries, must be the
    -- same: the same inputs, the same questions, the same atoms. Compared
    -- whole, modulo the numbering of nodes ('withoutNodeIds'), so that a clause
    -- group drawn as one leaf that asks nothing (or one that names a generated
    -- binding) fails. This ladder draws a CONSIDER as one box, whose atomId
    -- hashes its printed text, so the hand-written forms below are written as
    -- the CONSIDER the clauses read through to, nested where a table's rows are.
    describe "a BOOLEAN rule written as DECIDE clauses" do
      let noArguments = Aeson.object ["arguments" Aeson..= Aeson.object []]
          sameAsHandWritten :: Text -> Text -> Text -> SpecWith ()
          sameAsHandWritten name clauses hand =
            it (Text.unpack ("has the plan and the ladder of its hand-written CONSIDER: " <> name)) do
              withServiceFromSources ("cg-" <> name) [("rule.l4", clauses)] \baseUrl mgr -> do
                withServiceFromSources ("hw-" <> name) [("rule.l4", hand)] \baseUrl' mgr' -> do
                  qpC <- queryPlan' baseUrl mgr ("cg-" <> name) "rule" noArguments
                  qpH <- queryPlan' baseUrl' mgr' ("hw-" <> name) "rule" noArguments
                  statusCode' qpC `shouldBe` 200
                  statusCode' qpH `shouldBe` 200
                  let planC = withoutNodeIds <$> (Aeson.decode (responseBody qpC) :: Maybe Aeson.Value)
                      planH = withoutNodeIds <$> (Aeson.decode (responseBody qpH) :: Maybe Aeson.Value)
                  planC `shouldBe` planH
                  -- the plan asks something
                  lookupArrayLength "inputs" (decodeObject (responseBody qpC)) `shouldSatisfy` maybe False (> 0)
                  -- and no name the desugarer made up reaches a label, an ask or an input
                  let text = Text.pack (show (responseBody qpC))
                  for_ ["the result of", "input 1", "__pm_", "LET"] \g ->
                    (g, g `Text.isInfixOf` text) `shouldBe` (g, False)

          -- The plans above are compared whole, atomIds included. This compares
          -- the atomIds alone, so that a failure names them: the ladder's, and the
          -- plan's. The two are not compared with each other: here the plan names
          -- an atom's inputs by their labels and the ladder by their numbers, so
          -- they differ for every rule with inputs, however it is written.
          sameAtomIds :: Text -> Text -> Text -> SpecWith ()
          sameAtomIds name clauses hand =
            it (Text.unpack ("names every atom as its hand-written CONSIDER does: " <> name)) do
              withServiceFromSources ("cga-" <> name) [("rule.l4", clauses)] \baseUrl mgr -> do
                withServiceFromSources ("hwa-" <> name) [("rule.l4", hand)] \baseUrl' mgr' -> do
                  qpC <- queryPlan' baseUrl mgr ("cga-" <> name) "rule" noArguments
                  qpH <- queryPlan' baseUrl' mgr' ("hwa-" <> name) "rule" noArguments
                  for_ [qpC, qpH] \r -> statusCode' r `shouldBe` 200
                  let ladderIds r = case lookupKey "ladder" (decodeObject (responseBody r)) of
                        Just (Aeson.Object l) | Just (Aeson.Object fd) <- Aeson.KeyMap.lookup "funDecl" l ->
                          List.sort (List.nub (ladderLeafField "atomId" fd))
                        _ -> []
                      planIds r = case lookupKey "impactByAtomId" (decodeObject (responseBody r)) of
                        Just (Aeson.Object m) -> List.sort (map Aeson.Key.toText (Aeson.KeyMap.keys m))
                        _ -> []
                  -- both are non-empty, so the equalities below mean something
                  ladderIds qpC `shouldSatisfy` (not . null)
                  planIds qpC `shouldSatisfy` (not . null)
                  ladderIds qpC `shouldBe` ladderIds qpH
                  planIds qpC `shouldBe` planIds qpH

      sameAsHandWritten "enum" clauseGroupEnumJL4 handEnumJL4
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

      sameAtomIds "enum" clauseGroupEnumJL4 handEnumJL4
      sameAtomIds "mixed" clauseGroupMixedJL4 handMixedJL4
      sameAtomIds "single" clauseGroupSingleJL4 handSingleJL4
      sameAtomIds "nogiveth" clauseGroupNoGivethJL4 handEnumJL4
      sameAtomIds "call" clauseGroupCallJL4 handCallJL4
      sameAtomIds "table" clauseTableJL4 handTableJL4
      sameAtomIds "table2" clauseTable2JL4 handTable2JL4
      sameAtomIds "newname" clauseNewNameJL4 handNewNameJL4

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

      -- A clause whose result is a LET the drafter wrote: the group around it is
      -- read through, and the LET inside the clause stays as written.
      it "answers a clause group whose clause result is a LET" do
        withServiceFromSources "cg-let-result" [("rule.l4", clauseGroupLetResultJL4)] \baseUrl mgr -> do
          resp <- queryPlan' baseUrl mgr "cg-let-result" "rule" noArguments
          statusCode' resp `shouldBe` 200
          -- the colour is asked: the group's CONSIDER is read through
          lookupArrayLength "inputs" (decodeObject (responseBody resp)) `shouldSatisfy` maybe False (> 0)

      -- Only the LETs the desugarer generated are read through. A LET the
      -- drafter wrote stays as written, so a chain of LETs that each use the one
      -- before twice (which doubles for each LET when written out) is the one
      -- atom it always was, however long.
      it "answers a LET the drafter wrote as written" do
        withServiceFromSources "let-enum" [("rule.l4", letEnumJL4)] \baseUrl mgr -> do
          resp <- queryPlan' baseUrl mgr "let-enum" "rule" noArguments
          statusCode' resp `shouldBe` 200
          LBS.toStrict (responseBody resp) `shouldSatisfy` BS.isInfixOf "LET"
      for_ [3 :: Int, 7] \n ->
        it ("answers a chain of " <> show n <> " doubling LETs fast, as written") do
          withServiceFromSources "chain" [("rule.l4", letChainJL4 n)] \baseUrl mgr -> do
            resp <- queryPlan' baseUrl mgr "chain" "rule" noArguments
            statusCode' resp `shouldBe` 200
            LBS.toStrict (responseBody resp) `shouldSatisfy` BS.isInfixOf "LET"

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
      -- `main` plans such a rule however long or large its result, and so does the
      -- service. The service simplifies the ladder, and a disjunction of
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
      -- answer, so the group is read through and limited like any other. `main`
      -- answers such a group with 400 "Can only visualize, as a ladder diagram, a
      -- DECIDE that returns a boolean" (it cannot plan a clause group at all), so
      -- these say what this branch answers; they pass with and without the guard
      -- that exempts the own-name first clause.
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
      it "new names: still plans the same table at 8 clauses, as it plans it with the GIVEN's names" do
        withServiceFromSources "maybe-new-8" [("rule.l4", maybeTableJL4 False 8)] \baseUrl mgr -> do
          withServiceFromSources "maybe-own-8" [("rule.l4", maybeTableJL4 True 8)] \baseUrl' mgr' -> do
            qpN <- timeout 8_000_000 (queryPlan' baseUrl mgr "maybe-new-8" "rule" noArguments)
            qpO <- timeout 8_000_000 (queryPlan' baseUrl' mgr' "maybe-own-8" "rule" noArguments)
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

    -- A rule written as clauses words an input that no clause matches in the
    -- drafter's terms, from a mark on the CONSIDERs the clauses compile to. The
    -- mark is on their annotations, which bundle.cbor used to drop, so a
    -- restarted service reported a CONSIDER the drafter never wrote (review of
    -- legalese/l4-ide#545). A restart now compiles the sources again.
    it "words a rule written as clauses as it did before the restart" do
      let probe baseUrl mgr deployId = do
            resp <- evalFunction baseUrl mgr deployId "price" blue
            assertNoClauseForBlue resp
            pure (answerOf baseUrl deployId resp)
      (fresh, restarted) <- beforeAndAfterRestart "clauses-restart" [("price.l4", partialClausesJL4)] probe
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
    -- raw line break, and with it `l4 trace`. `explanation` prints a VALUE, and
    -- keeps the line break. Ruled 2026-10-12: printed string literals stay
    -- escaped on every surface, as the valid spelling of the source.
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

  -- One party and one action were spelled two ways in the same answer. A
  -- BREACH's `eventParty` and `eventAction` are a constructor's name, plain,
  -- but an OBLIGATION's `party` and `action`, and a BREACH's `obligationAction`,
  -- were L4 source, so a name with a space in it came back in backticks. A
  -- client asking "is the party who acted the party who was obliged?" by
  -- comparing the two strings got a false no. The README's rule for an enum
  -- answer is the plain name, and a party or an action NAME is an enum answer.
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
              stringAt "obligationAction" fields `shouldBe` Just delivery
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

    -- an action that carries a value is not a name: it is rule source
    it "keeps an action that carries a value as rule source" do
      withServiceFromSources "deontic-names-value" [("contract.l4", deonticValueActionJL4)] \baseUrl mgr -> do
        resp <- evalFunction baseUrl mgr "deontic-names-value" "the contract" (sale [])
        assertSuccess resp \r ->
          case Map.lookup "value" r.fnResult of
            Just (FnObject [("OBLIGATION", FnObject fields)]) -> do
              stringAt "party" fields `shouldBe` Just "Alice"
              stringAt "action" fields `shouldBe` Just "say \"pay now\""
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
      removePathForcibly logPath
      case result of
        Left err -> do
          err `shouldSatisfy` ("broken.l4" `Text.isInfixOf`)
          err `shouldSatisfy` ("unexpected (" `Text.isInfixOf`)
        Right _ -> expectationFailure "A source that does not parse was compiled"
      errorsLoggedFor "test" "broken.l4" logLines `shouldSatisfy` any ("unexpected (" `Text.isInfixOf`)

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

-- | What 'partialClausesJL4' says when called with Blue, which no clause matches.
noClauseForBlue :: Text
noClauseForBlue = "No clause of `price` matches these inputs."

blue :: Aeson.Value
blue = Aeson.object ["arguments" Aeson..= Aeson.object ["c" Aeson..= ("Blue" :: Text)]]

assertNoClauseForBlue :: Response LBS.ByteString -> IO ()
assertNoClauseForBlue resp = case Aeson.decode (responseBody resp) :: Maybe SimpleResponse of
  Just (SimpleError (InterpreterError msg)) -> msg `shouldSatisfy` Text.isInfixOf noClauseForBlue
  other -> expectationFailure ("Expected " <> show noClauseForBlue <> ", got: " <> show other)

-- | Run an action with no copy of the standard library in the places a test can
-- control, and put everything back afterwards: JL4_LIBRARY_PATH is dropped,
-- XDG_DATA_HOME points at an empty directory (the service looks in its
-- jl4/libraries), and the working directory is that empty directory too. The
-- path beside the executable is not touched. CI exports JL4_LIBRARY_PATH for the
-- whole run, and a developer's host can hold a library under
-- ~/.local/share/jl4/libraries, so either would hide a wrapper that reached for
-- the host's library.
withNoLibraryOnTheHost :: IO a -> IO a
withNoLibraryOnTheHost act = bracket acquire release (\(_, _, empty) -> withCurrentDirectory empty act)
  where
    acquire = do
      savedLibrary <- lookupEnv "JL4_LIBRARY_PATH"
      savedXdg <- lookupEnv "XDG_DATA_HOME"
      tmp <- getTemporaryDirectory
      stamp <- (floor . (* 1000000)) <$> getPOSIXTime :: IO Integer
      let empty = tmp </> ("jl4-service-no-library-" <> show stamp)
      createDirectoryIfMissing True empty
      unsetEnv "JL4_LIBRARY_PATH"
      setEnv "XDG_DATA_HOME" empty
      pure (savedLibrary, savedXdg, empty)
    release (savedLibrary, savedXdg, empty) = do
      restore "JL4_LIBRARY_PATH" savedLibrary
      restore "XDG_DATA_HOME" savedXdg
      removeDirectoryRecursive empty
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

-- | Some keys of each case of a batch response, in order; 'Nothing' when the
-- body has no @cases@ array.
caseKeys :: Response LBS.ByteString -> [Aeson.Key] -> Maybe [[Maybe Aeson.Value]]
caseKeys resp keys = case wireAt resp ["cases"] of
  Right (Aeson.Array cs) -> Just [ [ Aeson.KeyMap.lookup k c | k <- keys ] | Aeson.Object c <- toList cs ]
  _ -> Nothing

-- | Requests against 'wireProbeJL4': the 28 measured for smucclaw/l4-ide#1003,
-- then B7, B8, D3d and E1-E4. A pad of 1 keeps a request on the direct path
-- and a pad of {} sends it through the wrapper; on this endpoint a JSON null
-- is a missing input, and stays direct. Every 200 answer on the wrapper path
-- is the direct path's. Before legalese/l4-ide#162's encoding came to this
-- branch, A1-A7, B7, B8, C1 and C2 answered "NOTHING", {"JUST": [x]} or a
-- backticked enum name, and D3 answered "NOTHING" as if the rule had.
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
  , ("D1", "twice", args ["n" Aeson..= ("abc" :: Text), wrapper], Refuses "Expected JSON number but got: String")
    -- The direct path does not check that a scalar matches its parameter's
    -- type, so this stops on an internal type error. That is the answer this
    -- change found, pinned as such, not a good one.
  , ("D2", "twice", args ["n" Aeson..= ("abc" :: Text), direct], Refuses "type error")
  , ("D3", "twice", args [wrapper], Refuses "Parameter 'n': missing required parameter")
  , ("D3d", "twice", args [direct], Refuses "Parameter 'n': missing required parameter")
  , ("D4", "twice", args ["n" Aeson..= [1, 2 :: Int], wrapper], Refuses "Expected JSON number but got: Array")
  , ("D5", "twice", args ["n" Aeson..= Aeson.object ["a" Aeson..= (1 :: Int)], wrapper], Refuses "Expected JSON number but got: Object")
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
withPendingService' deployId sources act = do
  let tmpPath = "/tmp/jl4-service-test-" <> Text.unpack deployId
  cleanDir tmpPath
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
  let env = MkAppEnv registry pendingUpd store Nothing logger testOptions tasksReg

  mgr <- newManager defaultManagerSettings
  testWithApplication (pure $ app env) \port -> do
    let baseUrl = "http://localhost:" <> show port
    result <- act baseUrl mgr
    cleanDir tmpPath
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
withFailedService' deployId sources act = do
  let tmpPath = "/tmp/jl4-service-test-" <> Text.unpack deployId
  cleanDir tmpPath
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
  let env = MkAppEnv registry pendingUpd store Nothing logger testOptions tasksReg

  mgr <- newManager defaultManagerSettings
  testWithApplication (pure $ app env) \port -> do
    let baseUrl = "http://localhost:" <> show port
    result <- act baseUrl mgr
    cleanDir tmpPath
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
withServiceFromSources' deployId sources act = do
  let tmpPath = "/tmp/jl4-service-test-" <> Text.unpack deployId
  cleanDir tmpPath
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
  let env = MkAppEnv registry pendingUpd store Nothing logger testOptions tasksReg

  mgr <- newManager defaultManagerSettings
  testWithApplication (pure $ app env) \port -> do
    let baseUrl = "http://localhost:" <> show port
    result' <- act baseUrl mgr
    cleanDir tmpPath
    pure result'

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
withServicesRestarted' opts deployments editStore act = do
  -- Like the other helpers in this file, a fixed place under /tmp, named for
  -- the deployments so that tests with different ones do not share it.
  let tmpPath = "/tmp/jl4-service-test-restarted-" <> Text.unpack (Text.intercalate "-" (map fst deployments))
      logPath = tmpPath <> ".restart.log"
  cleanDir tmpPath
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

  -- The restart. Nothing survives it but the store on disk. The log goes
  -- beside the store. The file is closed, and read, before the service is up:
  -- a handle that is open for writing locks the file against being read.
  registry <- newTVarIO Map.empty
  withFile logPath WriteMode \h -> do
    restartLogger <- newLoggerTo h False
    DeploymentLoader.loadAllAndRegister restartLogger opts registry store (map fst deployments)
  logLines <- Maybe.mapMaybe Aeson.decodeStrict . BS8.lines <$> BS.readFile logPath

  pendingUpd <- newTVarIO Map.empty
  tasksReg <- newTVarIO Map.empty
  let env = MkAppEnv registry pendingUpd store Nothing logger opts tasksReg

  mgr <- newManager defaultManagerSettings
  testWithApplication (pure $ app env) \port -> do
    let baseUrl = "http://localhost:" <> show port
    result <- act logLines baseUrl mgr
    cleanDir tmpPath
    removePathForcibly logPath
    pure result

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

-- | A file under /tmp, open for writing, for a test to log into.
openTempFile' :: String -> IO (FilePath, Handle)
openTempFile' name = do
  let path = "/tmp/" <> name <> ".jsonl"
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
withEmptyService' act = do
  let tmpPath = "/tmp/jl4-service-test-empty"
  cleanDir tmpPath
  store <- initStore tmpPath
  logger <- newLogger False
  registry <- newTVarIO Map.empty
  pendingUpd <- newTVarIO Map.empty
  tasksReg <- newTVarIO Map.empty
  let env = MkAppEnv registry pendingUpd store Nothing logger testOptions tasksReg

  mgr <- newManager defaultManagerSettings
  testWithApplication (pure $ app env) \port -> do
    let baseUrl = "http://localhost:" <> show port
    result <- act baseUrl mgr
    cleanDir tmpPath
    pure result

-- | Evaluate a function via the API.
evalFunction :: String -> Manager -> Text -> Text -> Aeson.Value -> IO (Response LBS.ByteString)
evalFunction baseUrl mgr deployId fnName body = do
  req <- buildJsonPost (baseUrl <> "/deployments/" <> Text.unpack deployId <> "/functions/" <> Text.unpack fnName <> "/evaluation") body
  httpLbs req mgr

-- | Assert a successful evaluation response.
assertSuccess :: Response LBS.ByteString -> (ResponseWithReason -> IO ()) -> IO ()
assertSuccess resp check = do
  statusCode' resp `shouldBe` 200
  case Aeson.decode (responseBody resp) :: Maybe SimpleResponse of
    Nothing -> expectationFailure ("Failed to decode eval response: " <> show (responseBody resp))
    Just (SimpleResponse r) -> check r
    Just (SimpleError e) -> expectationFailure ("Evaluation error: " <> show e)

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

-- | Clean/remove a directory if it exists.
cleanDir :: FilePath -> IO ()
cleanDir path = do
  exists <- doesDirectoryExist path
  if exists then removeDirectoryRecursive path else pure ()

-- | Query a function's query-plan via the API.
queryPlan' :: String -> Manager -> Text -> Text -> Aeson.Value -> IO (Response LBS.ByteString)
queryPlan' baseUrl mgr deployId fnName body = do
  req <- buildJsonPost (baseUrl <> "/deployments/" <> Text.unpack deployId <> "/functions/" <> Text.unpack fnName <> "/query-plan") body
  httpLbs req mgr

-- | Decode a JSON response body as an Aeson Object.
decodeObject :: LBS.ByteString -> Maybe Aeson.Object
decodeObject = Aeson.decode

-- | Look up a key in a Maybe Object.
lookupKey :: Text -> Maybe Aeson.Object -> Maybe Aeson.Value
lookupKey k = (>>= Aeson.KeyMap.lookup (Aeson.Key.fromText k))

-- | The text of an MCP tool call's answer, and whether the call was an error.
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

-- | A field of every node of a ladder's body: the text if it is a string, or
-- the @label@ if it is a name.
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
