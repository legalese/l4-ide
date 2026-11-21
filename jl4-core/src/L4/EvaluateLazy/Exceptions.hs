-- | Evaluation exceptions, extracted into a leaf module so that both the
-- machine ('L4.EvaluateLazy.Machine') and the trace machinery
-- ('L4.EvaluateLazy.Trace') can depend on them without an import cycle.
module L4.EvaluateLazy.Exceptions
( EvalException (..)
, InternalEvalException (..)
, UserEvalException (..)
, Budget (..)
, BudgetSite (..)
, stopsTheRun
, isLimitStop
, LimitStopped (..)
, Refusal (..)
, prettyEvalException
, prettyRefusal
, maximumStackSize
, maximumFrameDepth
, maximumUnknownSteps
, maximumOpenObligations
, maximumClosureApplications
)
where

import Base
import qualified Base.Text as Text
import Control.Exception (Exception)
import L4.Evaluate.ValueLazy
import L4.Evaluate.Operators
import L4.Print
import L4.Annotation (emptyAnno)
import L4.Parser.SrcSpan (SrcRange, prettySrcRangeM)
import L4.Syntax
import L4.Utils.Ratio

data EvalException =
    InternalEvalException InternalEvalException
  | UserEvalException UserEvalException
  | RefusalException Refusal
    -- ^ The program REFUSED: it declined to answer, with the reason the author
    -- wrote. This is a THIRD TOP-LEVEL ARM rather than another
    -- 'UserEvalException' constructor, and deliberately so: it makes every
    -- total match over 'EvalException' a compile error until it decides
    -- whether a refusal is an error, and it keeps refusals out of
    -- 'prettyEvalException'\'s internal-error banner. A refusal is not a
    -- defect in the program and not an unknown fact the boundary can supply;
    -- it is a determinate outcome of its own kind.
  deriving stock (Generic, Show)
  deriving anyclass NFData

-- | The payload of a refusal: the author's reason for declining to answer.
--
-- The reason is a string literal in the source ('L4.Syntax.Refuse'), so it is
-- statically known and can be reported without running the program.
newtype Refusal =
  MkRefusal
    { message :: Text
    }
  deriving stock (Generic, Show)
  deriving anyclass NFData

-- | Render a refusal for a user. Deliberately does NOT say \"error\".
prettyRefusal :: Refusal -> [Text]
prettyRefusal r = [ "The model refuses to answer:", indentSingle r.message ]

-- | Thrown as a (synchronous) IO exception by the evaluation machine and
-- caught at directive boundaries; see 'L4.EvaluateLazy.Machine'.
instance Exception EvalException

data InternalEvalException =
    RuntimeScopeError Resolved -- internal
  | RuntimeTypeError Text -- internal
  | PrematureGC -- internal
  | DanglingPointer -- internal
  | UnhandledPatternMatch -- internal
  deriving stock (Generic, Show)
  deriving anyclass NFData

data UserEvalException =
    BlackholeForced (Expr Resolved)
  | EqualityOnUnsupportedType WHNF WHNF
  | NonExhaustivePatterns (Maybe PmGroup) (Either Reference WHNF)
    -- ^ A CONSIDER had no branch for its scrutinee. The group, when the
    -- CONSIDER was generated from the clauses of a multi-clause definition
    -- ('PmConsider'), so that the message is about the clauses the drafter
    -- wrote. 'Right' the forced scrutinee value when available, 'Left' the
    -- raw reference otherwise.
  | StackOverflow
  | DivisionByZero BinOp
  | NotAnInteger BinOp Rational
  | Stuck (NonEmpty Term)
    -- ^ what evaluation needed and nobody supplied: each input, or field of
    -- one, once, in the order evaluation reached it (UNKNOWN-EVALUATION-SPEC
    -- §4.7.4's default report names every one, U7b)
  | RanOutOfSteps
    -- ^ evaluation over an unknown took more steps than the limit allows
    -- (§4.5, build step 3). Never reported as such: the connective whose
    -- right operand ran out, or the directive boundary, rewrites it into
    -- 'Stuck' naming the inputs that started the count.
  | UserError Text -- ^ general user-facing error (e.g. missing TIMEZONE declaration)
  | OverBudget Budget
    -- ^ smucclaw/l4-ide#1075: the directive went over one of the machine's
    -- budgets ('Budget'). Raised as any user exception is, so
    -- 'tryEval' makes it that directive's result. After a counted budget
    -- the next directive still runs; after time or memory ('stopsTheRun')
    -- none does.
  | NotEvaluated Budget (Maybe SrcRange)
    -- ^ the directive was not evaluated, because an earlier one went over
    -- the opt-in time or memory limit, which stops the run (ruling L2 of
    -- the Recursion Limits bench): the limit, and the directive that went
    -- over it
  deriving stock (Generic, Show)
  deriving anyclass NFData

-- | Which budget a directive went over, with the limit it went over. The
-- first two count something the machine does, never time or memory, so the
-- same program stops at the same place on every machine; every @l4@
-- command that evaluates, the REPL and the editor set them
-- ('L4.EvaluateLazy.withCountedBudgets'), and the shared configuration does
-- not. They carry the site that took the
-- directive over. The last two are opt-in, are not deterministic, and stop
-- the run (smucclaw/l4-ide#1075; ruling L2).
data Budget
  = OpenObligations Int BudgetSite
    -- ^ more obligations armed and not yet handed on, breached or left
    -- waiting at the end of the events than the limit: a HENCE or LEST that
    -- arms two obligations and leads back to itself doubles this each time
    -- round. The site is the action of the obligation whose arming went over.
  | JoinedBreaches Int BudgetSite
    -- ^ a RAND, an ROR or a barrier would join more failures into one breach
    -- than the limit, which is the same open number as 'OpenObligations''s
    -- (L2's numbers, ruled by Meng 2026-11-21, amending L5). A breach that is shared
    -- and joined with itself doubles its list at each join with no new
    -- work. The site is the compound's operands, or the EVERY
    -- ('L4.EvaluateLazy.Machine.noteJoin').
  | ClosureApplications Int BudgetSite
    -- ^ more work than the limit, counting applications of functions written
    -- in L4 and deontic hand-offs in one total (L2's numbers, ruled by Meng 2026-11-21): a
    -- function that calls itself with new inputs and never stops pushes no
    -- frame, so the frame limit never sees it, and a HENCE that leads back to
    -- itself through a shared value applies no function at all. The site is
    -- where the step that went over is in the source: for an application,
    -- its function's body, or that function's GIVEN, or the first part of the
    -- body that has a place ('L4.EvaluateLazy.Machine.noteApplication'); for
    -- a hand-off, the action, the EVERY, or the compound's operands
    -- ('L4.EvaluateLazy.Machine.noteHandoff').
  | TimeLimit Int
    -- ^ the directive ran longer than the opt-in @--eval-timeout@, in
    -- seconds of wall-clock time. Not deterministic: it depends on the
    -- machine and its load.
  | MemoryLimit Int
    -- ^ the directive allocated more than the opt-in @--max-eval-memory-mb@,
    -- in megabytes: every byte allocated while working, not what is held.
  deriving stock (Generic, Show)
  deriving anyclass NFData

-- | Where a counted budget went over: the source of the obligation armed or
-- the function applied, and the name of the definition that source is in,
-- when it is one of the module's own (ruling L2: the hit names the rule).
data BudgetSite = MkBudgetSite
  { siteRange :: Maybe SrcRange
  , siteRule :: Maybe Text
  }
  deriving stock (Generic, Show)
  deriving anyclass NFData

-- | Whether going over this budget stops the whole run: time and memory do,
-- the counted budgets stop only their own directive (ruling L2).
stopsTheRun :: Budget -> Bool
stopsTheRun = \ case
  TimeLimit {}   -> True
  MemoryLimit {} -> True
  _              -> False

-- | Whether an evaluation ended at a limit (a count, time or memory), or
-- was not done because the run had stopped at one, rather than in an error
-- of the program's own. A command that reads an answer off an evaluation
-- must not read one off this: it says nothing about the program's answer
-- (ruled by Meng 2026-11-21, extending L2).
isLimitStop :: EvalException -> Bool
isLimitStop = \ case
  UserEvalException (OverBudget _)     -> True
  UserEvalException (NotEvaluated _ _) -> True
  _                                    -> False

-- | Raised out of a command that tries many inputs or traces (@l4
-- explore@, @l4 coverage@) when the evaluator stopped one of them at a
-- limit and the command has no honest way to go on without it: it carries
-- the stop's message, and the command reports that instead of an answer
-- read off the stopped evaluation.
newtype LimitStopped = LimitStopped Text
  deriving stock Show

instance Exception LimitStopped

prettyEvalException :: EvalException -> [Text]
prettyEvalException (InternalEvalException exc) = wrapInternal (prettyInternalEvalException exc)
  where
    wrapInternal :: [Text] -> [Text]
    wrapInternal msgs = [ "Internal error:" ] <> msgs <> [ "Please report this as a bug." ]
prettyEvalException (UserEvalException exc)     = prettyUserEvalException exc
prettyEvalException (RefusalException r)       = prettyRefusal r

prettyInternalEvalException :: InternalEvalException -> [Text]
prettyInternalEvalException = \ case
  RuntimeScopeError r ->
    indentMany r
    <> [ "is not in scope." ]
  RuntimeTypeError err ->
    [ "I encountered a type error during evaluation:" ]
    <> [ indentSingle err ]
  PrematureGC ->
    [ "Trying to access an address that has already been garbage-collected." ]
  DanglingPointer ->
    [ "Trying to access an address that is not on the abstract machine heap." ]
  UnhandledPatternMatch ->
    [ "Unhandled pattern match failure." ]

indentSingle :: Text -> Text
indentSingle = ("  " <>)

indentMany :: LayoutPrinter a => a -> [Text]
indentMany = map ind . Text.lines .  prettyLayout
  where
    ind = ("  " <>)

prettyUserEvalException :: UserEvalException -> [Text]
prettyUserEvalException = \ case
  BlackholeForced expr ->
    [ "Infinite loop detected while trying to evaluate:"
    , prettyLayout expr ]
  EqualityOnUnsupportedType v1 v2 ->
    [ "Trying to check equality on types that do not support it"
    , "These were the values you tried to compare:" ]
    <> indentMany v1
    <> indentMany v2
  NonExhaustivePatterns Nothing val ->
    [ "The value" ]
    <> either indentMany indentMany val
    <> [ "reached a CONSIDER that has no branch for it."
       , "Add a WHEN branch for this case, or a catch-all OTHERWISE branch."
       , "The typechecker's exhaustiveness warning lists all missing branches."
       ]
  -- Only the last clause's generated CONSIDERs have no OTHERWISE, so a
  -- generated CONSIDER that runs out of branches is always in the last
  -- clause, after every earlier clause has failed to match.
  NonExhaustivePatterns (Just g) val
    | g.clauseCount == 1 ->
        [ "The only clause of " <> h <> " does not match these inputs."
        , "The value it could not match is" ]
        <> either indentMany indentMany val
        <> [ "Add a clause for this case." ]
    | otherwise ->
        [ "No clause of " <> h <> " matches these inputs."
        , "The value that the last clause could not match is" ]
        <> either indentMany indentMany val
        <> [ "Add a clause for this case, or end the clauses with one that matches every input." ]
    where
      h = quotedName (MkName emptyAnno g.groupHead)
  StackOverflow ->
    [ "Stack overflow: "
    , "Recursion depth of " <> Text.textShow maximumFrameDepth
    , "exceeded." ]
  DivisionByZero op ->
    [ "Division by zero in the operation:"
    , prettyLayout op
    ]
  NotAnInteger op num ->
    [ "Expected an Integer but got the fractional number: " ]
    <> [ prettyRatio num ]
    <> [ "During the evaluation of the operation:"
       , prettyLayout op
       ]
  Stuck (t :| []) ->
    [ "I could not continue evaluating, because I needed to know the value of" ]
    <> indentStuckName t
    <> [ "but it is an assumed term." ]
  -- Several names: the same message, in the plural (decided by Claude
  -- overnight 2026-10-03, pending Meng's review; UNKNOWN-EVALUATION-SPEC §8
  -- step 3). The one-name message above is unchanged, so every page that
  -- quotes it stays true.
  Stuck ts ->
    [ "I could not continue evaluating, because I needed to know the values of" ]
    <> concatMap indentStuckName (toList ts)
    <> [ "but they are assumed terms." ]
  RanOutOfSteps ->
    [ "I gave up evaluating: working this out over an unknown took more than "
      <> Text.textShow maximumUnknownSteps <> " steps." ]
  UserError msg ->
    [ msg ]
  -- Wording decided by Claude 2026-11-21, pending Meng's review; the flag names are provisional.
  OverBudget (OpenObligations limit site) ->
    [ "I stopped evaluating: more than " <> Text.textShow limit <> " obligations were open at once."
    , "The last one was armed in " <> siteName site <> "."
    , "A HENCE or LEST that names more than one obligation adds to what is open,"
    , "and a chain of them that leads back to where it started multiplies it each time round."
    , "The l4 commands that evaluate, and the REPL, take --max-open N to change the limit, and --max-open none to remove it." ]
  OverBudget (JoinedBreaches limit site) ->
    [ "I stopped evaluating: a RAND, an ROR or an EVERY would have joined more than " <> Text.textShow limit <> " failures into one breach."
    , "The join was in " <> siteName site <> "."
    , "A breach that is shared, and joined with itself again and again, doubles its list of failures at each join."
    , "The l4 commands that evaluate, and the REPL, take --max-open N to change the limit, and --max-open none to remove it." ]
  OverBudget (ClosureApplications limit site) ->
    [ "I stopped evaluating: it took more than " <> Text.textShow limit <> " steps, counting each function applied and each contract handed the events."
    , "The last step was in " <> siteName site <> "."
    , "A function that calls itself with new inputs, or a HENCE or LEST that leads back to itself, never ends unless something stops it."
    , "The l4 commands that evaluate, and the REPL, take --max-steps N to change the limit, and --max-steps none to remove it." ]
  OverBudget b@(TimeLimit _) ->
    [ "I stopped the run: this took longer than " <> limitText b <> ", so nothing after it was evaluated." ]
  OverBudget b@(MemoryLimit _) ->
    [ "I stopped the run: this allocated more than " <> limitText b <> ", so nothing after it was evaluated."
    , "That counts every byte allocated while working it out, not only what is kept." ]
  NotEvaluated b at ->
    [ "I did not evaluate this: the run stopped at " <> prettySrcRangeM at <> ", which "
      <> (case b of
            MemoryLimit _ -> "allocated more than "
            TimeLimit _   -> "took longer than "
            _             -> "went over ")
      <> limitText b <> "." ]

-- | A budget's site as its message prints it: the definition by name, then
-- where in the source.
siteName :: BudgetSite -> Text
siteName site = case site.siteRule of
  Just rule -> rule <> ", at " <> prettySrcRangeM site.siteRange
  Nothing   -> "the definition at " <> prettySrcRangeM site.siteRange

-- | An opt-in limit with its flag.
limitText :: Budget -> Text
limitText = \ case
  TimeLimit n   -> Text.textShow n <> (if n == 1 then " second" else " seconds") <> " (--eval-timeout)"
  MemoryLimit n -> Text.textShow n <> " MB (--max-eval-memory-mb)"
  OpenObligations n _ -> Text.textShow n <> " obligations open at once (--max-open)"
  JoinedBreaches n _ -> Text.textShow n <> " failures joined into one breach (--max-open)"
  ClosureApplications n _ -> Text.textShow n <> " steps (--max-steps)"

-- | A name a 'Stuck' carries, as its message prints it. An input prints
-- exactly as it always has, so the one-input message is unchanged.
indentStuckName :: Term -> [Text]
indentStuckName = \ case
  TInput r _ -> indentMany r
  t          -> indentMany t

-- | The step limit of UNKNOWN-EVALUATION-SPEC §4.5: once a site has received
-- a term, evaluation may take this many more machine steps before it gives
-- up. Set from §7's measurement on build step 3's branch (2026-10-03): the
-- most any directive of the workload took was 59; a machine step allocates
-- about 290 bytes, so this many is about 73 MB, under the service's default
-- 256 MB per evaluation, and takes about 10 ms. Build step 5, whose joins can
-- take far more, measures it again.
maximumUnknownSteps :: Int
maximumUnknownSteps = 250_000

-- | The open number (smucclaw/l4-ide#1075; L2's numbers, ruled by Meng 2026-11-21):
-- how many obligations one directive may have open at once before the
-- machine stops it with 'OpenObligations', and how many failures one join
-- may gather before it stops with 'JoinedBreaches'. A level, not a total.
-- Over the corpus (2026-11-21) the most open at once was 8 and the longest
-- joined list 9. A rent rule that re-arms itself holds one open; #1075's
-- rule holds 16,384 at WAITUNTIL 30.
maximumOpenObligations :: Int
maximumOpenObligations = 10_000

-- | The work number (L2's numbers, ruled by Meng 2026-11-21): how many function applications and
-- deontic hand-offs, in all, one directive may make before the machine stops
-- it with 'ClosureApplications'. A running total. Over the corpus
-- (2026-11-21) the most was 164,898 (both counts together, in
-- @ok/closing-the-loop/fristberechnung.l4@); a tight loop makes about ten
-- million in 12 seconds.
maximumClosureApplications :: Int
maximumClosureApplications = 10_000_000

-- | Depth cutoff when converting WHNF results to normal form (deeper parts
-- of the result are 'Omitted').
maximumStackSize :: Int
maximumStackSize = 200

-- | Maximum number of frames on the abstract machine's stack, as a backstop
-- against runaway recursion. (The historical 200-frame limit was never
-- actually enforced due to an accounting bug, so legitimate deeply-recursive
-- programs relied on an effectively unbounded stack; this bound is therefore
-- deliberately generous.)
maximumFrameDepth :: Int
maximumFrameDepth = 1_000_000
