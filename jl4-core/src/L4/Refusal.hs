-- | Which definitions of a module REFUSE, always or on only some paths (ruling
-- R7; see @specs/as-built/refuse.md@).
--
-- A refusal is a throw at force, never a value, and it cannot be caught. A
-- definition always refuses when evaluating it can only end in a refusal: its
-- body is a @REFUSE@, or names a definition that always refuses, perhaps under
-- a @WHERE@ or a @LET@. House style writes each refusal as such a definition,
-- one per reason (R7).
--
-- The query plan reads it: a reference to one is not a question a user can
-- answer, since evaluation never takes an answer for it, it forces the
-- definition and refuses ('L4.Decision.BooleanDecisionQuery.BRefuse').
--
-- A definition that refuses on only some paths (a @REFUSE@ on one arm of an
-- @IF@, a @BRANCH@ or a @CONSIDER@) is NOT one of them: whether it refuses can
-- turn on what the plan does not see, such as the date the rules are read at.
-- The plan cannot ask it as a question, since evaluation does not take an answer
-- for it, and cannot report its refusal, since there may be none. A leaf that
-- reaches one is a refusal the plan cannot read ('refusalWithin'), and the plan
-- says so instead of guessing ('sometimesRefusing').
-- Names from other modules are not followed.
module L4.Refusal
  ( AlwaysRefusing
  , alwaysRefusing
  , SometimesRefusing
  , sometimesRefusing
  , refusalWithin
  , unreadableRefusalError
  , refusalMessage
  ) where

import L4.Syntax

import qualified Data.Map.Strict as Map
import Control.Applicative ((<|>))
import Data.Maybe (listToMaybe, mapMaybe)
import Data.Text (Text)
import qualified Data.Text as Text
import Optics (gplate, toListOf)

-- | Each definition of the module, local ones included, that always refuses,
-- with the reason it refuses with. A definition absent from the map does not
-- always refuse.
type AlwaysRefusing = Map.Map Unique Text

-- | Each definition of the module, local ones included, that refuses on only
-- some paths, with the reason it refuses with. A definition absent from the map
-- either always refuses or holds no refusal.
type SometimesRefusing = Map.Map Unique Text

-- | The definitions of the module that always refuse.
alwaysRefusing :: Module Resolved -> AlwaysRefusing
alwaysRefusing m = go Map.empty
  where
    bodies = definitionBodies m

    -- Grow the map until nothing changes: a definition joins it when its body
    -- refuses, or names one already in it. The least fixed point, so a cycle of
    -- definitions that only name each other never joins.
    go known =
      let known' = Map.mapMaybe (refusesWith known) bodies
       in if Map.size known' == Map.size known then known' else go known'

    refusesWith known = \case
      Refuse _ msg -> Just (refusalMessage msg)
      App _ r []   -> Map.lookup (getUnique r) known
      Where _ e _  -> refusesWith known e
      LetIn _ _ e  -> refusesWith known e
      _            -> Nothing

-- | Every definition of the module, local ones included, with its body.
definitionBodies :: Module Resolved -> Map.Map Unique (Expr Resolved)
definitionBodies m =
  Map.fromList
    [ (getUnique n, body)
    | MkDecide _ _ (MkAppForm _ n _ _) body <- foldTopLevelDecides (foldDecides pure) m
    ]

-- | The definitions of the module that refuse on only some paths, with the
-- reason each refuses with: a @REFUSE@ anywhere under the body, or a reference,
-- with or without arguments, to a definition that refuses, always or on some
-- path. The least fixed point, so a cycle of definitions that only name each
-- other never joins. The definitions that always refuse are left out; they are
-- the first argument.
--
-- It over-approximates: a @REFUSE@ under the body counts whether or not
-- evaluation reaches it, since that turns on the inputs and on rules the plan
-- does not read.
sometimesRefusing :: AlwaysRefusing -> Module Resolved -> SometimesRefusing
sometimesRefusing always m = Map.difference (go Map.empty) always
  where
    bodies = definitionBodies m

    -- Grow the map until its size stops changing. A definition's reason is the
    -- first refusal under it, so for a cycle of definitions it can differ between
    -- rounds; the set of definitions only grows.
    go found =
      let found' = Map.mapMaybe (refusalWithin always found) bodies
       in if Map.size found' == Map.size found then found' else go found'

-- | The reason of the first refusal inside an expression, if there is one: a
-- @REFUSE@, or a reference to a definition that refuses, always or on some
-- path, with or without arguments, anywhere under it.
--
-- The query plan asks it of a leaf that is none of those itself, such as a
-- @CONSIDER@ or a comparison, and of a call. A refusal there is reached or not
-- as the data decides, which the plan cannot order the questions around.
refusalWithin :: AlwaysRefusing -> SometimesRefusing -> Expr Resolved -> Maybe Text
refusalWithin always sometimes = listToMaybe . mapMaybe here . universe
  where
    universe e = e : concatMap universe (toListOf (gplate @(Expr Resolved)) e)

    reason r = Map.lookup (getUnique r) always <|> Map.lookup (getUnique r) sometimes

    here = \case
      Refuse _ msg        -> Just (refusalMessage msg)
      App _ r _           -> reason r
      AppNamed _ r _ _    -> reason r
      _                   -> Nothing

-- | What the query plan answers with, in place of a plan, for a rule that holds
-- a refusal it cannot read: one sentence that says where the first one may be
-- reached from and that the plan cannot order the questions for such a rule.
-- "May", because the map of rules that refuse on some path counts a refusal
-- whether or not evaluation reaches it ('sometimesRefusing'). @Nothing@ for a
-- rule that holds none. Takes what the ladder recorded: what each such leaf says,
-- and the reason it refuses with.
unreadableRefusalError :: [(Text, Text)] -> Maybe Text
unreadableRefusalError = \case
  [] -> Nothing
  (leaf, reason) : _ ->
    Just $
      "The query plan cannot order the questions for this rule, because a refusal (\""
        <> reason
        <> "\") may be reached from this part of it: "
        <> shorten (Text.unwords (Text.words leaf))
  where
    shorten t
      | Text.length t > 100 = Text.take 97 t <> "..."
      | otherwise = t

-- | The message of a @REFUSE@, as evaluation reports it.
--
-- The type checker requires a STRING literal, so the second arm is unreachable
-- from a module that type-checks; it degrades to a placeholder rather than to a
-- partial function.
refusalMessage :: Expr Resolved -> Text
refusalMessage = \case
  Lit _ (StringLit _ t) -> t
  _                     -> "(a refusal message this analysis could not read)"
