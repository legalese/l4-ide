-- | Which definitions of a module always REFUSE (ruling R7,
-- @specs/todo/IMPLICIT-PROPS-DESIGN.md@ §11.9).
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
-- @IF@, a @BRANCH@ or a @CONSIDER@) is NOT one of them, and stays a question:
-- whether it refuses can turn on what the plan does not see, such as the date
-- the rules are read at. Reporting a refusal there would be a new wrong answer.
-- Names from other modules are not followed.
module L4.Refusal
  ( AlwaysRefusing
  , alwaysRefusing
  , refusalMessage
  ) where

import L4.Syntax

import qualified Data.Map.Strict as Map
import Data.Text (Text)

-- | Each definition of the module, local ones included, that always refuses,
-- with the reason it refuses with. A definition absent from the map does not
-- always refuse.
type AlwaysRefusing = Map.Map Unique Text

-- | The definitions of the module that always refuse.
alwaysRefusing :: Module Resolved -> AlwaysRefusing
alwaysRefusing m = go Map.empty
  where
    -- Every definition, local ones included, with its body.
    bodies :: Map.Map Unique (Expr Resolved)
    bodies =
      Map.fromList
        [ (getUnique n, body)
        | MkDecide _ _ (MkAppForm _ n _ _) body <- foldTopLevelDecides (foldDecides pure) m
        ]

    -- Grow the map until nothing changes: a definition joins it when its body
    -- refuses, or names one already in it. The least fixed point, so a cycle of
    -- definitions that only name each other never joins.
    go known =
      let known' = Map.mapMaybe (refusesWith known) bodies
       in if Map.size known' == Map.size known then known' else go known'

    refusesWith known = \ case
      Refuse _ msg -> Just (refusalMessage msg)
      App _ r []   -> Map.lookup (getUnique r) known
      Where _ e _  -> refusesWith known e
      LetIn _ _ e  -> refusesWith known e
      _            -> Nothing

-- | The message of a @REFUSE@, as evaluation reports it.
--
-- The type checker requires a STRING literal, so the second arm is unreachable
-- from a module that type-checks; it degrades to a placeholder rather than to a
-- partial function. Mirrors 'L4.Dmn.Analysis.refuseMessageText'.
refusalMessage :: Expr Resolved -> Text
refusalMessage = \ case
  Lit _ (StringLit _ t) -> t
  _                     -> "(a refusal message this analysis could not read)"
