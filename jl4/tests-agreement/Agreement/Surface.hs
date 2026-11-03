-- | The surfaces that give a verdict, and the planners that may plan a
-- rule. Each is a constructor of a closed type, and the test runs each
-- through a function that matches on it with no wildcard, so under
-- -Wall -Werror a surface added here and given no runner fails the build.
module Agreement.Surface
  ( EvalSurface (..)
  , PlanSurface (..)
  , Surface (..)
  , surfaceName
  ) where

import qualified Data.Text as T

data EvalSurface
  = RunText
  -- ^ @l4 run@, the text it prints for each directive
  | RunJson
  -- ^ @l4 run --json@
  | Batch
  -- ^ @l4 batch@, a row for each case
  | Trace
  -- ^ @l4 trace@, the root of each #EVALTRACE's graph
  | ReplEval
  -- ^ jl4-repl, the reply to a call
  | ReplTraceAscii
  -- ^ jl4-repl's @:traceascii@, the reply above the trace
  | ReplTraceDot
  -- ^ jl4-repl's @:trace@, the root of the graph
  | ServiceDirect
  -- ^ jl4-service's evaluation endpoint, on its direct path
  | ServiceWrapper
  -- ^ jl4-service's evaluation endpoint, through its generated wrapper
  | ServiceBatchDirect
  -- ^ jl4-service's batch endpoint, on its direct path
  | ServiceBatchWrapper
  -- ^ jl4-service's batch endpoint, through its generated wrapper
  | McpDirect
  -- ^ jl4-service's MCP door, a tool call on the direct path
  | McpWrapper
  -- ^ jl4-service's MCP door, a tool call through the wrapper
  | LspDiagnostics
  -- ^ jl4-lsp's diagnostics for each directive
  | LspDirectiveResult
  -- ^ jl4-lsp's l4/evalDirectiveResult
  | LspDirectiveResultsUpdated
  -- ^ jl4-lsp's l4/directiveResultsUpdated notification
  | BrowserEval
  -- ^ L4.API's l4Eval, the browser editor's evaluation
  | BrowserEvalDirective
  -- ^ L4.API's l4EvalDirective
  deriving stock (Eq, Ord, Show, Enum, Bounded)

data PlanSurface
  = ServicePlan
  -- ^ jl4-service's query-plan endpoint
  | ReplPlan
  -- ^ jl4-repl's @:queryplan@
  | LspPlan
  -- ^ jl4-lsp's l4/queryPlan, for the decision graph drawn from a rule's lens
  | EditorPlan
  -- ^ L4.Decision.EditorQueryPlan's l4QueryPlan, the browser editor's planner
  deriving stock (Eq, Ord, Show, Enum, Bounded)

data Surface = Eval EvalSurface | Plan PlanSurface
  deriving stock (Eq, Ord, Show)

surfaceName :: Surface -> T.Text
surfaceName = \case
  Eval s -> T.pack (show s)
  Plan s -> T.pack (show s)
