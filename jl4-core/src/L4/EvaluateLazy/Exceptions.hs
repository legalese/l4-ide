-- | Evaluation exceptions, extracted into a leaf module so that both the
-- machine ('L4.EvaluateLazy.Machine') and the trace machinery
-- ('L4.EvaluateLazy.Trace') can depend on them without an import cycle.
module L4.EvaluateLazy.Exceptions
( EvalException (..)
, InternalEvalException (..)
, UserEvalException (..)
, Refusal (..)
, prettyEvalException
, prettyRefusal
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
  | NonExhaustivePatterns (Either Reference WHNF) -- ^ 'Right' the forced scrutinee value when available, 'Left' the raw reference otherwise
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
  NonExhaustivePatterns val ->
    [ "The value" ]
    <> either indentMany indentMany val
    <> [ "reached a CONSIDER that has no branch for it."
       , "Add a WHEN branch for this case, or a catch-all OTHERWISE branch."
       , "The typechecker's exhaustiveness warning lists all missing branches."
       ]
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
