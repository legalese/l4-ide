-- | The reference page for REFUSE, and the table on it that says what each
-- surface shows for a refusal. The page has one table, with one row for
-- each place a refusal shows up, and every surface is given its row by a
-- function that matches on it with no wildcard, so a surface added to
-- "Agreement.Surface" fails the build until it has a row here.
module Agreement.Page
  ( pagePath
  , examplePath
  , exampleRule
  , pageRow
  , pageQuote
  , pageTables
  ) where

import qualified Data.Text as T

import Agreement.Cli (traceRefusalPrefix)
import Agreement.Surface
import Agreement.Verdict (refusalHeading, replRefusalPrefix)

-- | The page, from the repository's root.
pagePath :: FilePath
pagePath = "doc/reference/control-flow/REFUSE.md"

-- | The page's example file, from the repository's root.
examplePath :: FilePath
examplePath = "doc/reference/control-flow/refuse-example.l4"

-- | The rule of the example file whose query plan the page quotes.
exampleRule :: T.Text
exampleRule = "covered"

-- | The first cell of the surface's row, as the page writes it.
pageRow :: Surface -> T.Text
pageRow = \case
  Eval s -> case s of
    RunText -> "`l4 run`"
    RunJson -> "`l4 run --json`"
    Batch -> "`l4 batch`"
    Trace -> trace
    ReplTraceDot -> trace
    ReplEval -> repl
    ReplTraceAscii -> repl
    LspDiagnostics -> "The editor"
    BrowserEval -> "The editor"
    LspDirectiveResult -> inspector
    LspDirectiveResultsUpdated -> inspector
    BrowserEvalDirective -> inspector
    ServiceDirect -> "The service's `/evaluation`"
    ServiceWrapper -> "The service's `/evaluation`"
    ServiceBatchDirect -> "The service's `/evaluation/batch`"
    ServiceBatchWrapper -> "The service's `/evaluation/batch`"
    McpDirect -> "The service's MCP tools"
    McpWrapper -> "The service's MCP tools"
  Plan s -> case s of
    ServicePlan -> plan
    ReplPlan -> plan
    LspPlan -> plan
    EditorPlan -> plan
 where
  trace = "`l4 trace`, and the REPL's `:trace`"
  repl = "The REPL, and its `:traceascii`"
  inspector = "The editor's Inspector"
  plan = "A query plan"

-- | The text the surface's row quotes, where the surface prints one: the
-- text by which this test reads a refusal from that surface, so that the
-- page quotes what the surface is tested to print. A query planner's row
-- quotes the sentence it is given, the decline core gives the example's
-- rule. A surface that answers in JSON has no such text.
pageQuote :: T.Text -> Surface -> Maybe T.Text
pageQuote decline = \case
  Eval s -> case s of
    RunText -> Just refusalHeading
    RunJson -> Nothing
    Batch -> Nothing
    Trace -> Just (T.strip traceRefusalPrefix)
    ReplTraceDot -> Just (T.strip traceRefusalPrefix)
    ReplEval -> Just (T.strip replRefusalPrefix)
    ReplTraceAscii -> Just (T.strip replRefusalPrefix)
    LspDiagnostics -> Just refusalHeading
    BrowserEval -> Just refusalHeading
    LspDirectiveResult -> Just refusalHeading
    LspDirectiveResultsUpdated -> Just refusalHeading
    BrowserEvalDirective -> Just refusalHeading
    ServiceDirect -> Nothing
    ServiceWrapper -> Nothing
    ServiceBatchDirect -> Nothing
    ServiceBatchWrapper -> Nothing
    McpDirect -> Nothing
    McpWrapper -> Nothing
  Plan s -> case s of
    ServicePlan -> Just decline
    ReplPlan -> Just decline
    LspPlan -> Just decline
    EditorPlan -> Just decline

-- | The tables of a markdown text, outside its code fences: each a list of
-- rows, each row its cells, without the header and the line under it.
pageTables :: T.Text -> [[[T.Text]]]
pageTables = go False [] . T.lines
 where
  go _ acc [] = flush acc []
  go fenced acc (l : ls)
    | "```" `T.isPrefixOf` T.stripStart l = flush acc (go (not fenced) [] ls)
    | not fenced, "|" `T.isPrefixOf` T.stripStart l = go fenced (l : acc) ls
    | otherwise = flush acc (go fenced [] ls)
  flush acc rest = case reverse acc of
    _header : _rule : rows -> map cells rows : rest
    _ -> rest
  cells l =
    let inner = drop 1 (T.splitOn "|" (T.strip l))
     in map T.strip (take (length inner - 1) inner)
