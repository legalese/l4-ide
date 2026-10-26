-- | The registry of surfaces: every door through which a program of this
-- repository gives a result, read from the program or from its source, and
-- the row that says which surface of "Agreement.Surface" it is, or why it
-- gives no verdict.
--
-- The test fails for a door with no row and for a row with no door. So a
-- new door (an l4 verb, a REPL command, a route of the service, a method of
-- the language server, a function of the browser's WASM module, a method of
-- the MCP door, an executable) fails the test until a row says what it is.
-- A new constructor of "Agreement.Surface" fails the build until it has a
-- runner, because Main's evalRunner, readsDirectives, planRunner and asks
-- match on the closed types with no wildcard.
--
-- The registry reads the routes of jl4-service from its ServiceApi, so it
-- does not see a path that a middleware of Application answers outside that
-- API: the raw text of a deployment's .l4 files, and the explorer page,
-- whose script reads a deployment through a route. It reads the MCP door by its methods, and
-- the door's tools that list, read and search a deployment's files give no
-- verdict. The TypeScript apps under ts-apps are clients of these doors and
-- give no verdict of their own.
module Agreement.Registry
  ( Entry (..)
  , Family (..)
  , families
  , serviceRouteTable
  , doorsOf
  , allSurfaces
  ) where

import Control.Exception (IOException, try)
import Control.Monad (filterM, forM)
import qualified Data.ByteString as BS
import qualified Data.Char as Char
import Data.List (nub, sort)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath (takeExtension, (</>))

import Agreement.Process (runIn)
import Agreement.Surface

-- | What a door is: one through which the test runs a surface, a program
-- whose doors another table lists, one that gives no verdict, or one that
-- gives a verdict this test does not read, and why.
data Entry
  = Door [Surface]
  | Listed T.Text
  | NotResult T.Text
  | NotRunHere T.Text
  deriving stock (Eq, Show)

-- | A kind of door: how to list the doors there are, and the table of rows.
data Family = MkFamily
  { title :: T.Text
  , enumerate :: IO (Either T.Text [T.Text])
  , table :: [(T.Text, Entry)]
  }

allSurfaces :: [Surface]
allSurfaces = map Eval [minBound .. maxBound] <> map Plan [minBound .. maxBound]

-- | The paths of the service's routes that are doors of the surface.
doorsOf :: Surface -> [T.Text]
doorsOf s = [p | (p, Door ss) <- serviceRouteTable, s `elem` ss]

families :: FilePath -> FilePath -> [T.Text] -> [Family]
families root l4 routes =
  [ MkFamily "the verbs of l4" (l4Verbs l4) l4VerbTable
  , MkFamily "the inputs jl4-repl reads" (replInputs root) replTable
  , MkFamily "the routes of jl4-service" (pure (Right routes)) serviceRouteTable
  , MkFamily "the methods of jl4-lsp" (lspMethods root) lspMethodTable
  , MkFamily "the custom methods and commands of jl4-lsp" (lspCustom root) lspCustomTable
  , MkFamily "the functions the browser's WASM module exports" (wasmExports root) wasmTable
  , MkFamily "the methods of jl4-service's MCP door" (mcpMethods root) mcpTable
  , MkFamily "the executables of this repository" (executables root) executableTable
  ]

l4VerbTable :: [(T.Text, Entry)]
l4VerbTable =
  [ ("run", Door [Eval RunText, Eval RunJson])
  , ("batch", Door [Eval Batch])
  , ("trace", Door [Eval Trace])
  , ("check", NotResult "type-checks a file, and evaluates nothing")
  , ("format", NotResult "prints a file as written")
  , ("ast", NotResult "prints a file's syntax tree")
  , ("state-graph", NotResult "draws the states of a module's regulative rules, from its type check")
  , ("render", NotResult "renders a module as a document, from its type check; its plan format is the document's export plan")
  , ("deploy", NotResult "sends a module to a service")
  , ("redeploy", NotResult "sends a module to a service")
  , ("undeploy", NotResult "removes a deployment from a service")
  , ("deployments", NotResult "lists a service's deployments")
  , ("install", NotResult "installs a companion tool")
  , ("nlg", NotResult "writes a module's directives as prose, from its type check")
  ]

replTable :: [(T.Text, Entry)]
replTable =
  [ ("otherwise", Door [Eval ReplEval])
  , (":queryplan", Door [Plan ReplPlan])
  , (":qp", Door [Plan ReplPlan])
  , (":trace", Door [Eval ReplTraceDot])
  , (":tr", Door [Eval ReplTraceDot])
  , (":traceascii", Door [Eval ReplTraceAscii])
  , (":tra", Door [Eval ReplTraceAscii])
  , (":tracefile", NotRunHere "writes the trace of each later call to a file, whose header l4-cli-test's \"names a refusal as one in the header of a trace saved with :tracefile\" reads")
  , (":quit", NotResult "ends the session")
  , (":q", NotResult "ends the session")
  , (":help", NotResult "lists the commands")
  , (":h", NotResult "lists the commands")
  , (":decides", NotResult "lists the module's rules")
  , (":load", NotResult "loads a file")
  , (":l", NotResult "loads a file")
  , (":reload", NotResult "loads the file again")
  , (":r", NotResult "loads the file again")
  , (":reset", NotResult "loads the file again and drops the imports")
  , (":type", NotResult "gives the type of an expression")
  , (":t", NotResult "gives the type of an expression")
  , (":import", NotResult "adds an import")
  , (":i", NotResult "adds an import")
  , ("IMPORT", NotResult "adds an import")
  , (":imports", NotResult "lists the imports")
  , (":info", NotResult "describes a name, from the type check")
  , (":env", NotResult "lists the names in scope")
  , (":e", NotResult "lists the names in scope")
  , (":", NotResult "answers that the command is unknown")
  ]

serviceRouteTable :: [(T.Text, Entry)]
serviceRouteTable =
  [ ("/deployments/{deploymentId}/functions/{name}/evaluation", Door [Eval ServiceDirect, Eval ServiceWrapper])
  , ("/{deploymentId}/{name}/evaluation", Door [Eval ServiceDirect, Eval ServiceWrapper])
  , ("/deployments/{deploymentId}/functions/{name}/evaluation/batch", Door [Eval ServiceBatchDirect, Eval ServiceBatchWrapper])
  , ("/{deploymentId}/{name}/evaluation/batch", Door [Eval ServiceBatchDirect, Eval ServiceBatchWrapper])
  , ("/deployments/{deploymentId}/functions/{name}/query-plan", Door [Plan ServicePlan])
  , ("/{deploymentId}/{name}/query-plan", Door [Plan ServicePlan])
  , ("/.mcp", Door [Eval McpDirect, Eval McpWrapper])
  , ("/{deploymentId}/.mcp", Door [Eval McpDirect, Eval McpWrapper])
  , ("/deployments/{deploymentId}/.mcp", Door [Eval McpDirect, Eval McpWrapper])
  , ("/.webmcp/embed.js", NotRunHere "the WebMCP page's script, whose tools call the evaluation endpoint from a browser; no test drives a browser")
  , ("/health", NotResult "reports that the service is up")
  , ("/.well-known/mcp", NotResult "describes the MCP door")
  , ("/.well-known/mcp/manifest", NotResult "describes the MCP door")
  , ("/.well-known/webmcp", NotResult "describes the WebMCP page")
  , ("/openapi.json", NotResult "describes the functions")
  , ("/deployments", NotResult "creates and lists deployments")
  , ("/deployments/{deploymentId}", NotResult "reads, replaces and removes a deployment")
  , ("/deployments/{deploymentId}/updates/{updateId}", NotResult "reports how an update stands")
  , ("/deployments/{deploymentId}/files", NotResult "reads a deployment's files")
  , ("/deployments/{deploymentId}/functions", NotResult "lists the functions")
  , ("/deployments/{deploymentId}/functions/{name}", NotResult "describes a function")
  , ("/deployments/{deploymentId}/functions/{name}/state-graphs", NotResult "lists the state graphs of a module's regulative rules")
  , ("/deployments/{deploymentId}/functions/{name}/state-graphs/{graphName}", NotResult "draws a state graph")
  , ("/deployments/{deploymentId}/openapi.json", NotResult "describes a deployment's functions")
  , ("/{deploymentId}", NotResult "reads, replaces and removes a deployment")
  , ("/{deploymentId}/files", NotResult "reads a deployment's files")
  , ("/{deploymentId}/functions", NotResult "lists the functions")
  , ("/{deploymentId}/openapi.json", NotResult "describes a deployment's functions")
  , ("/{deploymentId}/{name}", NotResult "describes a function")
  , ("/{deploymentId}/{name}/state-graphs", NotResult "lists the state graphs of a module's regulative rules")
  , ("/{deploymentId}/{name}/state-graphs/{graphName}", NotResult "draws a state graph")
  ]

lspMethodTable :: [(T.Text, Entry)]
lspMethodTable =
  [ ("SMethod_TextDocumentPublishDiagnostics", Door [Eval LspDiagnostics])
  , ("SMethod_CustomMethod", Listed "the custom methods and commands of jl4-lsp")
  , ("SMethod_WorkspaceExecuteCommand", Listed "the custom methods and commands of jl4-lsp")
  , ("SMethod_TextDocumentCodeLens", NotResult "labels each directive and rule; the labels hold no result")
  , ("SMethod_TextDocumentHover", NotResult "gives a name's type")
  , ("SMethod_TextDocumentCompletion", NotResult "completes a name")
  , ("SMethod_TextDocumentDefinition", NotResult "finds a definition")
  , ("SMethod_TextDocumentReferences", NotResult "finds references")
  , ("SMethod_TextDocumentDocumentSymbol", NotResult "lists the outline")
  , ("SMethod_TextDocumentSemanticTokensFull", NotResult "colours the text")
  , ("SMethod_TextDocumentSemanticTokensFullDelta", NotResult "colours the text")
  , ("SMethod_TextDocumentCodeAction", NotResult "offers edits")
  , ("SMethod_TextDocumentDidOpen", NotResult "a document opens")
  , ("SMethod_TextDocumentDidChange", NotResult "a document changes")
  , ("SMethod_TextDocumentDidSave", NotResult "a document is saved")
  , ("SMethod_TextDocumentDidClose", NotResult "a document closes")
  , ("SMethod_WorkspaceDidChangeConfiguration", NotResult "the settings change")
  , ("SMethod_WorkspaceDidChangeWatchedFiles", NotResult "files change on disk")
  , ("SMethod_ClientRegisterCapability", NotResult "registers for a notification")
  , ("SMethod_Initialized", NotResult "the session starts")
  , ("SMethod_Shutdown", NotResult "the session ends")
  , ("SMethod_Exit", NotResult "the session ends")
  , ("SMethod_CancelRequest", NotResult "cancels a request")
  , ("SMethod_SetTrace", NotResult "sets the protocol's logging")
  , ("SMethod_WindowLogMessage", NotResult "logs a message")
  , ("SMethod_WindowShowMessage", NotResult "shows a message")
  ]

lspCustomTable :: [(T.Text, Entry)]
lspCustomTable =
  [ ("l4/evalDirectiveResult", Door [Eval LspDirectiveResult])
  , ("l4/directiveResultsUpdated", Door [Eval LspDirectiveResultsUpdated])
  , ("l4/queryPlan", Door [Plan LspPlan])
  , ("l4.visualize", Door [Plan LspPlan])
  , ("l4/evalApp", NotRunHere "the ladder's evaluation of a call, which a client asks with a checked module, its environment and a drawn ladder; no test drives it")
  , ("l4/directiveResultsNotif", NotResult "the name of the action that gathers l4/directiveResultsUpdated")
  , ("l4/evalDirectiveResult/#CHECK", NotResult "the name of the action that checks a #CHECK for l4/evalDirectiveResult")
  , ("l4.renderResult", NotResult "the client command a directive's lens names")
  , ("l4.resetvisualization", NotResult "clears the drawn decision graph")
  , ("l4/inlineExprs", NotResult "draws a decision graph with definitions inlined")
  , ("l4/embeddedLibrary", NotResult "reads a library's text")
  , ("l4/exportDocument", NotResult "renders a module as a document")
  , ("l4/exportPlan", NotResult "gives a document's export plan")
  , ("l4/getExportedFunctions", NotResult "lists the exported functions")
  ]

wasmTable :: [(T.Text, Entry)]
wasmTable =
  [ ("l4_eval", Door [Eval BrowserEval])
  , ("l4_eval_directive", Door [Eval BrowserEvalDirective])
  , ("l4_query_plan", Door [Plan EditorPlan])
  , ("l4_check", NotResult "type-checks the text")
  , ("l4_hover", NotResult "gives a name's type")
  , ("l4_completions", NotResult "completes a name")
  , ("l4_semantic_tokens", NotResult "colours the text")
  , ("l4_visualize_by_name", NotResult "draws a rule's decision graph")
  , ("l4_code_lenses", NotResult "labels each directive and rule")
  , ("l4_definition", NotResult "finds a definition")
  , ("l4_references", NotResult "finds references")
  ]

mcpTable :: [(T.Text, Entry)]
mcpTable =
  [ ("tools/call", Door [Eval McpDirect, Eval McpWrapper])
  , ("tasks/get", NotRunHere "answers a tool called as a task with the answer the call gives; jl4-service-test's \"answers an MCP tool called as a task, while its deployment compiles, as a call is answered, a refusal among them\" pins it")
  , ("initialize", NotResult "starts the session")
  , ("notifications/initialized", NotResult "the session starts")
  , ("tools/list", NotResult "lists the tools")
  , ("tasks/update", NotResult "updates a task")
  , ("tasks/cancel", NotResult "cancels a task")
  ]

executableTable :: [(T.Text, Entry)]
executableTable =
  [ ("l4", Listed "the verbs of l4")
  , ("jl4-repl", Listed "the inputs jl4-repl reads")
  , ("jl4-lsp", Listed "the methods of jl4-lsp")
  , ("jl4-service", Listed "the routes of jl4-service")
  , ("jl4-wasm", Listed "the functions the browser's WASM module exports")
  , ("jl4-mlir", NotRunHere "compiles a module to WASM and runs it; `jl4-mlir run` declines a function that may refuse, which jl4-mlir-test's \"jl4-mlir run declines an unsupported export\" pins")
  , ("jl4-schema", NotResult "writes the JSON schema of a module's exports")
  , ("jl4-websessions", NotResult "stores the browser editor's sessions")
  ]

-- The doors there are -------------------------------------------------------

l4Verbs :: FilePath -> IO (Either T.Text [T.Text])
l4Verbs l4 = do
  (_, out, err) <- runIn "." l4 ["--help"] ""
  let after = drop 1 (dropWhile (/= "Available commands:") (T.lines (out <> err)))
      verbs = [v | l <- after, Just rest <- [T.stripPrefix "  " l], let v = T.takeWhile (not . Char.isSpace) rest, not (T.null v)]
  pure (if null verbs then Left ("no commands in l4 --help: " <> out <> err) else Right (nub verbs))

-- | The string literals of the guards of processInput (the lines that start
-- with "|" at the indentation of its first guard), each guard the part of
-- its line before " = ", and "otherwise" for the guard that evaluates the
-- input.
replInputs :: FilePath -> IO (Either T.Text [T.Text])
replInputs root = readSource (root </> "jl4-repl" </> "app" </> "Main.hs") \src ->
  let body = takeWhile (\l -> T.null l || " " `T.isPrefixOf` l) (drop 1 (dropWhile (not . ("processInput st input" `T.isPrefixOf`)) (T.lines src)))
      indentOf = T.length . T.takeWhile (== ' ')
      guardLines = [l | l <- body, "| " `T.isPrefixOf` T.stripStart l]
      guards = case guardLines of
        first : _ -> [T.drop 2 (T.stripStart l) | l <- guardLines, indentOf l == indentOf first]
        [] -> []
      condition g = case T.breakOn " = " g of
        (c, rest) | not (T.null rest) -> c
        _ -> fromMaybe' g (T.stripSuffix " =" g)
      items = concat [map T.strip (literals (condition g)) <> ["otherwise" | T.strip (condition g) == "otherwise"] | g <- guards]
   in if null items then Left "no guards found in processInput" else Right (nub items)
 where
  fromMaybe' d = maybe d id

-- | The string literals of a text.
literals :: T.Text -> [T.Text]
literals t = case T.breakOn "\"" t of
  (_, rest) | T.null rest -> []
  (_, rest) ->
    let (lit, after) = T.breakOn "\"" (T.drop 1 rest)
     in lit : literals (T.drop 1 after)

lspMethods :: FilePath -> IO (Either T.Text [T.Text])
lspMethods root = do
  srcs <- hsSources [root </> "jl4-lsp" </> "app", root </> "jl4-lsp" </> "src"]
  pure (nonEmpty "SMethod_" (sort (nub (concatMap (occurrences "SMethod_" Char.isAlphaNum) srcs))))
 where
  nonEmpty what xs = if null xs then Left ("no " <> what <> " found") else Right (map ("SMethod_" <>) xs)

lspCustom :: FilePath -> IO (Either T.Text [T.Text])
lspCustom root = do
  srcs <- hsSources [root </> "jl4-lsp" </> "app", root </> "jl4-lsp" </> "src"]
  let items = sort (nub (concat [map (p <>) (occurrences ("\"" <> p) (/= '"') s) | s <- srcs, p <- ["l4/", "l4."]]))
  pure (if null items then Left "no custom method found" else Right items)

wasmExports :: FilePath -> IO (Either T.Text [T.Text])
wasmExports root = do
  srcs <- hsSources [root </> "jl4-core" </> "src", root </> "jl4-wasm"]
  let items = sort (nub (concatMap (occurrences "foreign export javascript \"" (/= '"')) srcs))
  pure (if null items then Left "no foreign export found" else Right items)

mcpMethods :: FilePath -> IO (Either T.Text [T.Text])
mcpMethods root = readSource (root </> "jl4-service" </> "src" </> "McpServer.hs") \src ->
  let items = nub [lit | l <- T.lines src, "handleMethod " `T.isPrefixOf` l, lit : _ <- [literals l]]
   in if null items then Left "no method found" else Right items

executables :: FilePath -> IO (Either T.Text [T.Text])
executables root = do
  pkgs <- listDirectory root
  cabals <- fmap concat $ forM (sort pkgs) \p -> do
    isDir <- doesDirectoryExist (root </> p)
    if not isDir then pure [] else do
      fs <- listDirectory (root </> p)
      pure [root </> p </> f | f <- fs, takeExtension f == ".cabal"]
  srcs <- mapM (fmap TE.decodeUtf8Lenient . BS.readFile) cabals
  let items = sort (nub [T.strip e | s <- srcs, l <- T.lines s, Just e <- [T.stripPrefix "executable " l]])
  pure (if null items then Left "no executable found" else Right items)

-- | Every text after an occurrence of the marker, as far as the test allows.
occurrences :: T.Text -> (Char -> Bool) -> T.Text -> [T.Text]
occurrences marker ok src = filter (not . T.null) [T.takeWhile ok chunk | chunk <- drop 1 (T.splitOn marker src)]

hsSources :: [FilePath] -> IO [T.Text]
hsSources dirs = concat <$> mapM go dirs
 where
  go d = do
    isDir <- doesDirectoryExist d
    if not isDir then pure [] else do
      entries <- sort <$> listDirectory d
      subdirs <- filterM (doesDirectoryExist . (d </>)) entries
      here <- mapM (fmap TE.decodeUtf8Lenient . BS.readFile . (d </>)) [e | e <- entries, takeExtension e == ".hs"]
      below <- concat <$> mapM (go . (d </>)) subdirs
      pure (here <> below)

readSource :: FilePath -> (T.Text -> Either T.Text [T.Text]) -> IO (Either T.Text [T.Text])
readSource path k = do
  r <- try (BS.readFile path) :: IO (Either IOException BS.ByteString)
  pure case r of
    Left e -> Left (T.pack (show e))
    Right bs -> k (TE.decodeUtf8Lenient bs)
