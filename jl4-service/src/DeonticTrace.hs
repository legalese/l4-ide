-- | Evaluating a DEONTIC export against a trace, for every surface that does it.
--
-- A function that returns a DEONTIC is not asked a question, it is replayed: it
-- is evaluated against a @startTime@ and a list of @events@, and the answer is
-- the verdict or the residual obligation after them. A call that leaves the
-- trace out would get the contract's initial obligation, whatever happened,
-- which reads as an answer and is not one.
--
-- So the one place that runs a DEONTIC export against a trace is
-- 'runDeonticLimited', and the one place that says what a request must carry
-- for it is 'requireTrace'. @POST .../evaluation@, MCP @tools/call@ (and the
-- background task it spawns for a deployment still compiling) and
-- @POST .../evaluation/batch@ all call them. Before this module only the first
-- did: the other two evaluated a DEONTIC export "like any other" and dropped the
-- trace without an error.
module DeonticTrace (
  isDeonticFunction,
  requireTrace,
  traceFromJSON,
  noTraceForOtherFunctions,
  isStrayTraceField,
  noDeonticModule,
  presentDeonticOutcome,
  runDeonticLimited,
) where

import Backend.Api
  ( EvaluatorError (..)
  , FnLiteral
  , LimitHit
  , Presumption
  , ResponseWithReason (..)
  , TraceEvent
  , TraceLevel
  , emptyReasoning
  )
import Backend.Jl4 (evaluateWithCompiledDeontic)
import Compiler (toDecl)
import EvalLimits (withEvalLimits)
import L4.FunctionSchema (Parameters (..))
import Options (Options)
import Types

import Control.Monad.Trans.Except (runExceptT, throwE)
import qualified Data.Aeson as Aeson
import Data.Int (Int64)
import qualified Data.Map.Strict as Map
import Data.Scientific (Scientific)
import Data.Text (Text)
import qualified Data.Text as Text
import System.FilePath ((<.>))

-- | Whether a function is evaluated against a trace: the one test, for every
-- surface.
--
-- It reads the function's type, as the compiler did when it exported it
-- (@Compiler.exportToFunction@, from @isDeonticType@, which compares the type
-- constructor's unique, so @PROVISION@, the deprecated alias of @DEONTIC@, is
-- the same type and answers the same). The compiler adds @startTime@ and
-- @events@ to the parameters of exactly the functions it flags, but the
-- parameters are not the test: a function that is not DEONTIC and has inputs of
-- both those names is an ordinary function. @/evaluation@ used to take it for a
-- DEONTIC one, because it read the parameter names; since 2026-10-26 it does
-- not.
--
-- The summary side of the same flag is 'FunctionSummary.fsIsDeontic', which the
-- metadata cache holds for a deployment that is not compiled yet.
isDeonticFunction :: ValidatedFunction -> Bool
isDeonticFunction vf = vf.fnImpl.isDeontic

-- | What a request to a DEONTIC function must carry. Both fields are required,
-- and the refusal names the first that is missing, as @/evaluation@ has always
-- worded it.
requireTrace :: Maybe Scientific -> Maybe [TraceEvent] -> Either Text (Scientific, [TraceEvent])
requireTrace mStart mEvents = case (mStart, mEvents) of
  (Nothing, _) -> Left "startTime is required for functions returning DEONTIC"
  (_, Nothing) -> Left "events is required for functions returning DEONTIC"
  (Just st, Just evts) -> Right (st, evts)

-- | 'requireTrace' for a trace that arrived as JSON values rather than as the
-- typed fields of @FnArguments@: an MCP call's arguments, and a batch case's
-- attributes. A @null@ is a field left out, as it is on @/evaluation@.
-- A field that is there but is not a number, or not a list of events, is
-- refused with the field's name, ahead of a field that is missing.
traceFromJSON :: Maybe Aeson.Value -> Maybe Aeson.Value -> Either Text (Scientific, [TraceEvent])
traceFromJSON mStart mEvents = do
  st <- field "startTime" mStart
  evts <- field "events" mEvents
  requireTrace st evts
 where
  field :: Aeson.FromJSON a => Text -> Maybe Aeson.Value -> Either Text (Maybe a)
  field _ Nothing = Right Nothing
  field _ (Just Aeson.Null) = Right Nothing
  field name (Just v) = case Aeson.fromJSON v of
    Aeson.Success a -> Right (Just a)
    Aeson.Error err -> Left (name <> ": " <> Text.pack err)

-- | What a request that carries a trace is refused with when the function it
-- is for does not return a DEONTIC: a trace has nothing to be replayed against.
-- It is the message @/evaluation@ has always given, on every surface now.
noTraceForOtherFunctions :: Text
noTraceForOtherFunctions = "startTime and events are only valid for functions returning DEONTIC"

-- | Whether a field of a request to a function that is not DEONTIC is a trace
-- the function has no use for: a field named @startTime@ or @events@ that is
-- not one of the function's inputs. A function that is not DEONTIC may declare
-- inputs of those names, and then they are inputs. MCP and a batch case put a
-- function's inputs and its trace on one level, so this is how they tell them
-- apart; @/evaluation@ has the trace as its own fields and does not need it.
isStrayTraceField :: Parameters -> Text -> Bool
isStrayTraceField params field =
  field `elem` ["startTime", "events"] && Map.notMember field params.parameterMap

-- | What a DEONTIC function that has no compiled module reports. The compiler
-- falls back to a per-file session for a function whose module did not
-- precompile, and that session has no trace to give.
noDeonticModule :: Text
noDeonticModule = "No compiled module available for deontic evaluation"

-- | THE seam: what of a DEONTIC outcome leaves the service. Every surface gets
-- its outcome from 'runDeonticLimited', which passes it through here before it
-- returns, so a change here changes REST, MCP @tools/call@, the MCP task path
-- and a batch case together, and the verdict cannot differ between them.
--
-- An outcome is an answer or an error, and both pass through. An error can
-- carry the contract too: the evaluator's message prints the values and names
-- it stopped on, and an error that reaches a client unfiltered would hand over
-- what a withheld answer withholds. A limit hit carries no contract and is
-- reported by the caller; so is the refusal of a request with no trace.
--
-- It is the identity today. It is one function so that a runtime that does not
-- want a client to see the residual contract (Meng, 2026-10-26: "we may
-- optionally not want to return the residual contract because certain runtimes
-- may say that some clients don't have a right to know the contract details --
-- it's a black box to them", DEONTIC-TRACE-API-SPEC Q6) can have that in one
-- place. Not ruled, and not built here: who decides, what a withheld answer
-- looks like, and whether FULFILLED and BREACH stay visible.
--
-- What is the residual, as the service emits it: the fields of an OBLIGATION and
-- the operands of an AND or OR in 'fnResult', and, with a trace, the 'reasoning'
-- tree and the 'graphviz' source. All of them are fields of the one value this
-- takes, so they pass through together; the response shapes are unchanged.
--
-- What is outside it: @GET .../state-graphs@ and the source-browse tools (@list_files@,
-- @read_file@, @search_identifier@, @search_text@) also expose a contract's
-- structure, and a setting that withholds must gate them too.
presentDeonticOutcome :: Either EvaluatorError ResponseWithReason -> Either EvaluatorError ResponseWithReason
presentDeonticOutcome = id

-- | Replay a trace against a DEONTIC function, under the service's time and
-- allocation limits.
--
-- The result is the shape of 'EvalLimits.withEvalLimits': a limit hit, or the
-- evaluation's answer and the bytes it allocated. Each surface reports a limit
-- hit its own way (a 500 on @/evaluation@, an error result on MCP, an errored
-- case in a batch), so the choice stays with the caller. It runs in 'IO' so
-- that the MCP task worker, which has the options and no request, can call it.
--
-- The party and action types come from the function, never from the caller:
-- they spell the events in the generated wrapper, and the caller has no better
-- source for them than the function has.
runDeonticLimited
  :: Options
  -> ValidatedFunction
  -> [(Text, Maybe FnLiteral)]
  -> Scientific       -- ^ start time
  -> [TraceEvent]
  -> TraceLevel
  -> Bool             -- ^ include GraphViz output
  -> Presumption
  -> Bool             -- ^ keep the reasoning tree; a batch case does not send it
  -> IO (Either (LimitHit, Int64) (Either EvaluatorError ResponseWithReason, Int64))
runDeonticLimited cfg vf args startTime events traceLevel includeGraphViz presumption keepReasoning =
  withEvalLimits cfg $ fmap (dropReasoning . presentDeonticOutcome) $ runExceptT $ case vf.fnCompiled of
    Nothing -> throwE (InterpreterError noDeonticModule)
    Just compiled ->
      evaluateWithCompiledDeontic
        (Text.unpack vf.fnImpl.name <.> "l4")
        (toDecl vf.fnImpl)
        compiled
        vf.fnSourceText
        vf.fnModuleContext
        args
        startTime
        events
        vf.fnImpl.deonticPartyType
        vf.fnImpl.deonticActionType
        traceLevel
        includeGraphViz
        presumption

 where
  -- Dropped here, before 'withEvalLimits' forces the outcome, so that a traced
  -- batch is not charged for a tree it never sends. After the seam, which sees
  -- the whole outcome.
  dropReasoning
    | keepReasoning = id
    | otherwise = fmap (\r -> r { reasoning = emptyReasoning })
