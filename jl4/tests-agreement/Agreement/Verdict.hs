-- | Core's verdict on a directive, what a surface is seen to give, and when
-- the two agree. A verdict is an answer, a refusal with its reason, an
-- evaluation that raises, or a holding assertion; the wire shape a surface
-- writes it in is the surface's own, and is read off here.
module Agreement.Verdict
  ( CoreVerdict (..)
  , Expect (..)
  , Seen (..)
  , Flag (..)
  , coreVerdict
  , agrees
  , expectAgrees
  , refusalText
  , seenOfPretty
  , replReply
  , PlanSeen (..)
  , firstLine
  , hasNull
  ) where

import qualified Data.Aeson as Aeson
import Data.Foldable (toList)
import qualified Data.Text as T

import qualified L4.EvaluateLazy as EL
import L4.Evaluate.ValueLazy (NF (..))
import L4.Print (ConstructorFieldNames, prettyLayoutNF)
import L4.EvaluateLazy (Refusal (..))

-- | Core's verdict: an answer (its text, its JSON, and whether it stops
-- anywhere at the depth a directive reads), a refusal, an evaluation that
-- raises (the exception's text), a holding assertion, or any other outcome
-- of an assertion (its text).
data CoreVerdict
  = CoreAnswers T.Text Aeson.Value Bool
  | CoreRefuses T.Text
  | CoreRaises T.Text
  | CoreHolds
  | CoreAssertion T.Text
  deriving stock (Eq, Show)

-- | The verdict a case's header names.
data Expect = Answers Aeson.Value | AnswersCutShort | Refuses T.Text | Raises
  deriving stock (Eq, Show)

-- | What a surface gives: a text, a JSON value, a refusal with its reason,
-- an error with its text, or a holding assertion; or one of these with the
-- flag the surface writes beside it to say whether the result succeeded.
data Seen
  = SeenText T.Text
  | SeenJson Aeson.Value
  | SeenRefused T.Text
  | SeenRaised T.Text
  | SeenHolds
  | SeenFlagged Flag Seen
  deriving stock (Eq, Show)

-- | The flag a surface writes beside a result: the "success" of L4.API and
-- of the language server's Inspector (true, false, or null, as which an
-- absent one is read), the severity of a diagnostic or of an L4.API result
-- (1 for an error, 2 for a warning, 3 for information), the isError of an
-- MCP tool's result (false when it is absent), or the HTTP status of the
-- service's evaluation endpoint.
data Flag
  = Success Aeson.Value
  | Severity Aeson.Value
  | IsError Bool
  | HttpStatus Int
  deriving stock (Eq, Show)

coreVerdict :: ConstructorFieldNames -> EL.EvalDirectiveValue -> CoreVerdict
coreVerdict fields = \case
  EL.Reduction (EL.Reduced nf) -> CoreAnswers (prettyLayoutNF fields nf) (Aeson.toJSON nf) (hasOmitted nf)
  EL.Reduction (EL.ReducedRefused r) -> CoreRefuses r.message
  EL.Reduction (EL.ReducedErrored e) -> CoreRaises (T.unlines (EL.prettyEvalException e))
  EL.Assertion EL.Holds -> CoreHolds
  EL.Assertion a -> CoreAssertion (EL.prettyAssertionOutcome a)
 where
  hasOmitted = \case
    Omitted -> True
    MkNF v -> any hasOmitted v

-- | Whether a surface gives core's verdict.
--
-- A refusal agrees with a refusal for the same reason, and with nothing
-- else. An evaluation that raises agrees with an error, or a text, that
-- holds the first line of the exception's text, and with an error that
-- carries no text, which is all a trace's node writes ("<error>"). An
-- answer agrees with its text or its JSON, and an answer that stops at the
-- depth a directive reads agrees with a text that ends the answer short
-- ("..." or "…") and a JSON value that holds a null where it stops. That
-- last holds only because no answer in the corpus holds NOTHING, which a
-- JSON value also writes as null.
--
-- A result with a flag agrees when the flag gives core's verdict too (see
-- 'flagAgrees'), so a refusal written with a failure's flag agrees with
-- nothing.
agrees :: CoreVerdict -> Seen -> Bool
agrees core seen = case (core, seen) of
  (_, SeenFlagged f s) -> flagAgrees core f && agrees core s
  (CoreRefuses r, SeenRefused s) -> r == s
  (CoreRaises m, SeenRaised s) -> T.null s || firstLine m `T.isInfixOf` s
  (CoreRaises m, SeenText t) -> firstLine m `T.isInfixOf` t
  (CoreAnswers txt _ cut, SeenText t) -> t == txt || (cut && ("..." `T.isInfixOf` t || "…" `T.isInfixOf` t))
  (CoreAnswers _ j cut, SeenJson v) -> v == j || (cut && hasNull v)
  (CoreHolds, SeenHolds) -> True
  (CoreHolds, SeenText t) -> t == "assertion satisfied"
  _ -> False

-- | Whether a surface's flag gives core's verdict. An answer and a holding
-- assertion succeed, an evaluation that raises does not, and a refusal does
-- neither: its success is null and its severity a warning's. An MCP tool's
-- result is an error, and the evaluation endpoint answers 422, for every
-- result that is not an answer, a refusal among them. An assertion that
-- does not hold agrees with no surface ('agrees'), so its flag decides
-- nothing.
flagAgrees :: CoreVerdict -> Flag -> Bool
flagAgrees core = \case
  Success v -> v == maybe Aeson.Null Aeson.Bool outcome
  Severity v -> v == Aeson.Number (case outcome of Just True -> 3; Just False -> 1; Nothing -> 2)
  IsError b -> b == (outcome /= Just True)
  HttpStatus n -> n == (if outcome == Just True then 200 else 422)
 where
  outcome = case core of
    CoreAnswers {} -> Just True
    CoreHolds -> Just True
    CoreRefuses _ -> Nothing
    CoreRaises _ -> Just False
    CoreAssertion _ -> Just False

-- | Whether core gives the verdict a case's header names.
expectAgrees :: Expect -> CoreVerdict -> Bool
expectAgrees ex core = case (ex, core) of
  (Answers j, CoreAnswers _ v False) -> j == v
  (AnswersCutShort, CoreAnswers _ _ True) -> True
  (Refuses r, CoreRefuses s) -> r == s
  (Raises, CoreRaises _) -> True
  _ -> False

firstLine :: T.Text -> T.Text
firstLine = T.takeWhile (/= '\n')

hasNull :: Aeson.Value -> Bool
hasNull = \case
  Aeson.Null -> True
  Aeson.Array xs -> any hasNull (toList xs)
  Aeson.Object o -> any hasNull (toList o)
  _ -> False

-- | The reason of a refusal as core prints one ("The model refuses to
-- answer:", then each line of the reason two columns in), from a text whose
-- lines are all indented by the given number of columns.
refusalText :: Int -> T.Text -> Maybe T.Text
refusalText indent t = case T.lines t of
  h : rest
    | T.strip h == "The model refuses to answer:" ->
        Just (T.intercalate "\n" (map (T.drop (indent + 2)) (dropTrailingBlank rest)))
  _ -> Nothing
 where
  dropTrailingBlank = reverse . dropWhile (T.null . T.strip) . reverse

-- | A directive's result as core prints it: a refusal, a holding assertion,
-- an error (when the surface says the evaluation failed), or an answer.
seenOfPretty :: Bool -> T.Text -> Seen
seenOfPretty raised t
  | Just r <- refusalText 0 t' = SeenRefused r
  | t' == "assertion satisfied" = SeenHolds
  | raised = SeenRaised t'
  | otherwise = SeenText t'
 where
  t' = T.dropWhileEnd (== '\n') t

-- | What a query planner gives for a rule: a plan, which settles the rule's
-- answer or does not; a decline, as JSON or as a sentence; or no plan, for a
-- reason of the planner's own.
data PlanSeen
  = Planned (Maybe Bool)
  | Declined Aeson.Value
  | DeclinedText T.Text
  | NoPlan T.Text
  deriving stock (Eq, Show)

-- | A reply of the REPL: "Refused: " and a reason whose later lines are
-- indented to line up under its first, "Error: " and the error's text, or
-- the answer's text.
replReply :: T.Text -> Seen
replReply t
  | Just r <- T.stripPrefix "Refused: " t =
      SeenRefused (T.intercalate "\n" (case T.lines r of
        l : ls -> l : map (T.drop (T.length "Refused: ")) ls
        [] -> []))
  | Just e <- T.stripPrefix "Error: " t = SeenRaised e
  | otherwise = SeenText t
