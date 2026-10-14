-- | Evaluation exceptions, extracted into a leaf module so that both the
-- machine ('L4.EvaluateLazy.Machine') and the trace machinery
-- ('L4.EvaluateLazy.Trace') can depend on them without an import cycle.
module L4.EvaluateLazy.Exceptions
( EvalException (..)
, InternalEvalException (..)
, UserEvalException (..)
, prettyEvalException
, maximumStackSize
, maximumFrameDepth
)
where

import Base
import qualified Base.Text as Text
import Control.Exception (Exception)
import L4.Evaluate.ValueLazy
import L4.Evaluate.Operators
import L4.Print
import L4.Annotation (emptyAnno)
import L4.Syntax
import L4.Utils.Ratio

data EvalException =
    InternalEvalException InternalEvalException
  | UserEvalException UserEvalException
  deriving stock (Generic, Show)
  deriving anyclass NFData

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
  | Stuck Resolved -- ^ stores the term we got stuck on
  | UserError Text -- ^ general user-facing error (e.g. missing TIMEZONE declaration)
  deriving stock (Generic, Show)
  deriving anyclass NFData

prettyEvalException :: EvalException -> [Text]
prettyEvalException (InternalEvalException exc) = wrapInternal (prettyInternalEvalException exc)
  where
    wrapInternal :: [Text] -> [Text]
    wrapInternal msgs = [ "Internal error:" ] <> msgs <> [ "Please report this as a bug." ]
prettyEvalException (UserEvalException exc)     = prettyUserEvalException exc

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
  Stuck r ->
    [ "I could not continue evaluating, because I needed to know the value of" ]
    <> indentMany r
    <> [ "but it is an assumed term." ]
  UserError msg ->
    [ msg ]

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
