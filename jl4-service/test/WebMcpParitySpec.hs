{-# LANGUAGE OverloadedStrings #-}

-- | The WebMCP script and the MCP endpoint name a rule's inputs the same way.
--
-- The script is a second copy of the tool surface, in JavaScript, and the names
-- it gives the inputs of a rule must be the names @tools/list@ gives them: a
-- client that follows one schema is read by the rule through the other's reverse
-- map. The two sanitisers are written twice and differed for a letter outside the
-- Basic Multilingual Plane (the script cut a name at 60 UTF-16 units where the
-- endpoint cuts at 60 characters, and hashed the units, so a name came out
-- different, or with a lone surrogate).
--
-- This runs the generated script under @node@ against a stub of the browser's
-- @modelContext@ and of @fetch@, and compares the property names of each tool it
-- registers with 'Shared.sanitizeParameters', which @tools/list@ uses. It is
-- skipped (pending) where @node@ is not on the PATH, unless the environment
-- variable @CI@ is set: a CI run without @node@ would otherwise skip it silently,
-- so there it fails and says why.
module WebMcpParitySpec (spec) where

import Test.Hspec

import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as Aeson.Key
import qualified Data.Aeson.KeyMap as Aeson.KeyMap
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.Lazy.Char8 as LBS8
import Data.Char (toLower)
import Data.Foldable (toList)
import qualified Data.List as List
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text.Encoding
import System.Directory (findExecutable)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Environment (lookupEnv)
import System.Process (readProcessWithExitCode)

import L4.FunctionSchema (Parameter (..), Parameters (..))
import Shared (sanitizeParameters)
import WebMCPPage (RawJs (..), renderOrgWebMCPScript)

-- | Runs the script against the deployments it is given, and prints, for each tool
-- it registers, its name and the property names of its input schema. Output is
-- ASCII (non-ASCII is written as \u escapes), so that the locale cannot change it.
harness :: Text
harness = Text.unlines
  [ "import fs from 'node:fs';"
  , "import vm from 'node:vm';"
  , "const [scriptPath, depsPath] = process.argv.slice(2);"
  , "const src = fs.readFileSync(scriptPath, 'utf8');"
  , "const deployments = JSON.parse(fs.readFileSync(depsPath, 'utf8'));"
  , "const tools = [];"
  , "const doc = {"
  , "  modelContext: { registerTool(def) { tools.push(def); } },"
  , "  currentScript: { src: 'http://localhost:1/.webmcp/embed.js', getAttribute: (k) => ({ 'data-tools': 'rules' })[k] ?? null },"
  , "  createElement: () => ({}), head: { appendChild() {} }, documentElement: { appendChild() {} }, querySelector: () => null,"
  , "};"
  , "let done; const ready = new Promise((r) => { done = r; });"
  , "const win = { location: { origin: 'http://localhost:1' }, dispatchEvent: (e) => { if (e.type === 'webmcp-ready' || e.type === 'webmcp-error') done(e); } };"
  , "const sandbox = {"
  , "  document: doc, window: win, navigator: {}, URL, console: { error() {}, log() {} },"
  , "  CustomEvent: class { constructor(t, o) { this.type = t; this.detail = o && o.detail; } },"
  , "  encodeURIComponent, setTimeout,"
  , "  fetch: async () => ({ ok: true, status: 200, json: async () => deployments }),"
  , "};"
  , "const guard = setTimeout(() => { console.log('{\"error\":\"timeout\"}'); process.exit(0); }, 20000);"
  , "guard.unref();"
  , "vm.createContext(sandbox);"
  , "vm.runInContext(src, sandbox);"
  , "const ev = await ready;"
  , "const ascii = (s) => s.replace(/[\\u0080-\\uffff]/g, (c) => '\\\\u' + c.charCodeAt(0).toString(16).padStart(4, '0'));"
  , "if (ev.type !== 'webmcp-ready') { console.log(ascii(JSON.stringify({ error: String(ev.detail && ev.detail.error) }))); process.exit(0); }"
  , "console.log(ascii(JSON.stringify(tools.map((t) => ({ name: t.name, properties: Object.keys(t.inputSchema.properties) })))));"
  ]

-- | A rule's inputs, spelt as given: all strings, all optional.
paramsOf :: [Text] -> Parameters
paramsOf names = MkParameters
  { parameterMap = Map.fromList [ (n, strParam) | n <- names ]
  , required = []
  }
 where
  strParam = Parameter "string" Nothing Nothing [] "" Nothing Nothing Nothing Nothing Nothing Nothing

-- | The names that stress the two sanitisers: a letter outside the BMP (U+20000)
-- placed where the 60-character cut falls, two names that collide once cut (so that
-- both are given a hash suffix), a non-ASCII BMP letter, a dot, and plain names.
trickyNames :: [Text]
trickyNames =
  [ Text.replicate 58 "a" <> "\x20000" <> "b"     -- 60 characters, 61 UTF-16 units
  , Text.replicate 59 "a" <> "\x20000"            -- cut inside the pair, in UTF-16 units
  , Text.replicate 59 "x" <> "\x20000" <> "1"     -- these two are the same name once cut,
  , Text.replicate 59 "x" <> "\x20000" <> "2"     -- and each takes a hash of its own spelling
  , "presumption\x03A9"
  , "\x03A9mega"
  , "dotted.name."
  , "has capacity"
  ]

-- | Whether the environment says this is a CI run: @CI@ set to anything but empty,
-- @false@ or @0@ (GitHub Actions sets it to @true@).
ciIsSet :: IO Bool
ciIsSet = do
  v <- lookupEnv "CI"
  pure $ case v of
    Just s -> map toLower s `notElem` ["", "false", "0"]
    Nothing -> False

spec :: Spec
spec = describe "WebMCP script and MCP endpoint (property names)" do
  it "name a rule's inputs the same way, including letters outside the BMP and hash suffixes" do
    mNode <- findExecutable "node"
    inCI <- ciIsSet
    case mNode of
      Nothing
        | inCI -> expectationFailure
            "node is not on the PATH, and CI is set: this test runs the generated WebMCP script under node, and a CI run without it would skip the check silently. Install node (actions/setup-node) in the job."
        | otherwise -> pendingWith "node is not on the PATH"
      Just node -> withSystemTempDirectory "webmcp-parity" \dir -> do
        let params = paramsOf trickyNames
            RawJs js = renderOrgWebMCPScript
            deployments = Aeson.toJSON
              [ Aeson.object
                  [ "id" Aeson..= ("d" :: Text)
                  , "status" Aeson..= ("ready" :: Text)
                  , "metadata" Aeson..= Aeson.object
                      [ "functions" Aeson..=
                          [ Aeson.object
                              [ "name" Aeson..= ("fa" :: Text)
                              , "description" Aeson..= ("" :: Text)
                              , "parameters" Aeson..= params
                              , "returnType" Aeson..= ("BOOLEAN" :: Text)
                              , "isDeontic" Aeson..= False
                              ]
                          ]
                      ]
                  ]
              ]
            expected = case sanitizeParameters params of
              Aeson.Object o | Just (Aeson.Object ps) <- Aeson.KeyMap.lookup "properties" o ->
                List.sort (map Aeson.Key.toText (Aeson.KeyMap.keys ps) <> ["presumption"])
              _ -> []
        LBS.writeFile (dir </> "embed.js") js
        LBS.writeFile (dir </> "deployments.json") (Aeson.encode deployments)
        LBS.writeFile (dir </> "harness.mjs") (LBS.fromStrict (Text.Encoding.encodeUtf8 harness))
        (code, out, err) <- readProcessWithExitCode node [dir </> "harness.mjs", dir </> "embed.js", dir </> "deployments.json"] ""
        code `shouldBe` ExitSuccess
        case Aeson.decode (LBS8.pack out) :: Maybe [Aeson.Value] of
          Just [Aeson.Object tool] -> do
            Aeson.KeyMap.lookup "name" tool `shouldBe` Just (Aeson.String "fa")
            let got = case Aeson.KeyMap.lookup "properties" tool of
                  Just (Aeson.Array ps) -> List.sort [ t | Aeson.String t <- toList ps ]
                  _ -> []
            -- every name the endpoint lists, the script lists; and no more
            got `shouldBe` expected
            -- and each is a whole string: no lone surrogate (which Aeson reads back as U+FFFD)
            filter (Text.any (== '\xFFFD')) got `shouldBe` []
          other -> expectationFailure ("the script registered no single tool: " <> show other <> "\nstderr: " <> err)
