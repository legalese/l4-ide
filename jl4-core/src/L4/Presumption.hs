-- | What happens to one input, or one field of an input, that a request
-- supplies, sends as @null@, or leaves out: the decision T3, T4 and T1b of
-- @specs\/todo\/TYPICALLY-ONE-BEHAVIOUR-SPEC.md@ rule, written once.
--
-- Three fill sites take it: the JSON decoder ('L4.EvaluateLazy.Machine',
-- which @l4 batch@ and the service's wrapper path go through), the service's
-- direct path (@jl4-service@ @Backend.Jl4@), and @l4 batch --validate-only@.
-- Their mechanisms differ (a decoder, AST root fills, a schema check), so only
-- the decision and the words for it are shared; each site says in its own
-- terms what it does with the result.
module L4.Presumption
  ( Supplied (..)
  , FillDecision (..)
  , Withheld (..)
  , NullDefault (..)
  , fillDecision
  , withheldText
  , nullRefusalText
  , unrecognisedMessage
  , nearestName
  , editDistance
  , requestRecordName
  ) where

import Data.List (sortOn)
import Data.Maybe (isJust, listToMaybe)
import Data.Text (Text)
import qualified Data.Text as Text

-- | What a request said about an input or a field: nothing (the key is
-- absent), "not known" (@null@, or @{}@, which T3 reads as @null@), or a
-- value. The 'Text' is how the not-known was spelled, for the message.
data Supplied v
  = Absent
  | SuppliedNull Text
  | Supplied v

-- | What a fill site does with one input or field.
data FillDecision d
  = UseValue
    -- ^ a value was supplied
  | UseDefault d
    -- ^ absent, with a declared @TYPICALLY@, presumption on (T1b: a declared
    -- default wins over the MAYBE fallback)
  | UseNothing
    -- ^ absent, a MAYBE with no default, presumption on (D7.3)
  | NullIsNothing
    -- ^ @null@ on a MAYBE: a value, not an omission
  | RefuseMissing Withheld
    -- ^ absent, and nothing fills it
  | RefuseNull Text NullDefault
    -- ^ not known (spelled as the 'Text') on a non-MAYBE; the 'NullDefault'
    -- says whether it has a default it may not take, and whether leaving the
    -- input out would take it (T3)

-- | What a refusal of a not-known value says about the input's @TYPICALLY@
-- default. The refusal may point at leaving the input out only where that would
-- take the default, which is only so while presumption is soft: under hard an
-- input left out is refused too (documentation review, round 1, C10).
data NullDefault
  = NoDefaultToTake
    -- ^ the input has no default
  | LeavingOutTakesIt
    -- ^ it has one, and presumption is soft: leaving the input out takes it
  | LeavingOutRefusedToo
    -- ^ it has one, and presumption is hard: leaving the input out is refused

-- | Why an absent input is refused, beyond "nothing supplies it".
data Withheld
  = NothingWithheld
    -- ^ it has no default and is not a MAYBE
  | DefaultWithheld
    -- ^ presumption is off, so its @TYPICALLY@ is not used (T4)
  | MaybeWithheld
    -- ^ presumption is off, so a MAYBE is not NOTHING (T1b)

-- | The decision. @isMaybe@ must be decided on the type with its synonyms
-- expanded, so that a synonym for MAYBE keeps its fallback.
fillDecision :: Bool -> Bool -> Maybe d -> Supplied v -> FillDecision d
fillDecision presume isMaybe mDefault = \ case
  Supplied _ -> UseValue
  SuppliedNull spelling
    | isMaybe   -> NullIsNothing
    | otherwise -> RefuseNull spelling $ case mDefault of
        Nothing -> NoDefaultToTake
        Just _ | presume   -> LeavingOutTakesIt
               | otherwise -> LeavingOutRefusedToo
  Absent
    | presume, Just d <- mDefault -> UseDefault d
    | presume, isMaybe            -> UseNothing
    | isJust mDefault             -> RefuseMissing DefaultWithheld
    | isMaybe                     -> RefuseMissing MaybeWithheld
    | otherwise                   -> RefuseMissing NothingWithheld

-- | What a "missing" refusal adds after its own lead phrase.
withheldText :: Withheld -> Text
withheldText = \ case
  NothingWithheld -> ""
  DefaultWithheld -> " (it has a TYPICALLY default, but presumption is hard, so the default is not used)"
  MaybeWithheld   -> " (a MAYBE left out is NOTHING only while presumption is soft)"

-- | The refusal of a not-known value on a non-MAYBE, after the thing's name
-- (@Field 'x' …@, @Parameter 'x': …@).
nullRefusalText :: Text -> NullDefault -> Text
nullRefusalText spelling hasDefault =
  "is " <> spelling <> ", which means the value is not known"
    <> case hasDefault of
         NoDefaultToTake      -> ": supply a value"
         LeavingOutTakesIt    -> ", and that never takes the TYPICALLY default: supply a value, or leave it out to use the default"
         LeavingOutRefusedToo -> ", and that never takes the TYPICALLY default: supply a value (leaving it out is refused too, because presumption is hard)"

-- | The refusal of names that match nothing a request may supply, in an
-- object where something left out took its default (review M1, decided
-- overnight 2026-10-02, pending Meng's review: spec §4.1). A misspelled key
-- used to be loud, because the input it misspelled was then missing; once
-- that input has a default, ignoring the key makes the misspelling take the
-- default with status success. So where a default is filled, a name that
-- matches nothing is refused, naming it and the nearest declared name; where
-- none is, an unknown name is ignored as before (Postel).
--
-- Each name comes with the nearest declared one ('nearestName'), both as the
-- message should show them (a path, for a field).
unrecognisedMessage :: Text -> [(Text, Maybe Text)] -> Text
unrecognisedMessage noun names =
  "Unknown " <> noun <> (case names of [_] -> ""; _ -> "s") <> " "
    <> Text.intercalate ", " (map one names)
    <> ". Something left out beside it takes its TYPICALLY default, so a name"
    <> " that matches nothing is refused rather than ignored, in case it misspells"
    <> " the one left out"
  where
    one (k, near) = "'" <> k <> "'" <> maybe "" (\ n -> " (did you mean '" <> n <> "'?)") near

-- | The declared name nearest to an unknown one, by edit distance ignoring
-- case; the earlier-declared on a tie. 'Nothing' only when nothing is declared.
nearestName :: Text -> [Text] -> Maybe Text
nearestName k candidates =
  fst <$> listToMaybe (sortOn snd [ (c, editDistance (Text.toLower k) (Text.toLower c)) | c <- candidates ])

editDistance :: Text -> Text -> Int
editDistance a b = last (foldl' step [0 .. length bs] (Text.unpack a))
  where
    bs = Text.unpack b
    step prev x = case prev of
      p : ps -> scanl (cell x) (p + 1) (zip3 bs prev ps)
      []     -> []
    cell x left (y, diag, up) = minimum [left + 1, up + 1, diag + (if x == y then 0 else 1)]

-- | The record the request's own arguments are decoded into, by every
-- wrapper that decodes them (@l4 batch@'s and the service's). The decoder
-- treats a decode at this type as the REQUEST's (T4b: the presumption switch
-- reaches only what a request can supply) when the evaluation says it has one
-- ('L4.EvaluateLazy.EvalConfig'.@requestRecord@).
requestRecordName :: Text
requestRecordName = "InputArgs"
