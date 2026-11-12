-- | The rungs of a decision: the conditions it branches on, in the order the
-- rest of the system reads them.
--
-- A decision written as a proviso chain (@c AND NOT d1 AND NOT d2@) has the
-- rungs @c@, @d1@, @d2@; a @BRANCH@, an @IF@ or a literal @CONSIDER@ has the
-- condition of each arm; any other BOOLEAN decision is one rung, its body.
-- "L4.Catala.Lower" builds its exception ladders from the first two shapes,
-- and "L4.Cli.Coverage" counts the leaves of these rungs; both read the shape
-- from here, so they cannot come to disagree about what a rung is.
module L4.Coverage.Rungs
  ( rungsOf
  , ladderAtoms
  , peelProvisos
  , cascadeArms
  , litConsiderArms
  , asAnd
  , asNot
  , isBuiltinNamed
  , plainName
  ) where

import Base
import L4.Syntax

-- | The rungs of a decision's body: the ladder shapes' conditions, else the
-- whole body when the decision is BOOLEAN, else none (a decision with nothing
-- it branches on).
rungsOf :: Bool -> Expr Resolved -> Maybe [Expr Resolved]
rungsOf isCondition body = case ladderAtoms isCondition body of
  Just rs -> Just rs
  Nothing | isCondition -> Just [body]
          | otherwise -> Nothing

-- | The defining name with any section qualification dropped: this is what the
-- builtin, prelude-combinator and date recognisers match against, because a
-- prelude function reaches us as @Prelude.Numeric Aggregates.sum@.
plainName :: Resolved -> Text
plainName = unqualifiedRawNameToText . rawName . getOriginal

-- | The L4 atoms of the ladder 'modeBClauses' derives from a body, in its order.
ladderAtoms :: Bool -> Expr Resolved -> Maybe [Expr Resolved]
ladderAtoms isCondition body
  | isCondition, Just (base, provisos) <- peelProvisos body = Just (base : provisos)
  | Just (arms, _) <- cascadeArms body = Just (map fst arms)
  | otherwise = Nothing


-- | @c AND NOT d1 AND NOT d2 …@ → @(c, [d1, d2, …])@, or 'Nothing' when there is
-- no trailing negated conjunct to make a proviso out of.
peelProvisos :: Expr Resolved -> Maybe (Expr Resolved, [Expr Resolved])
peelProvisos e0 = case go e0 of
  (_, []) -> Nothing
  r       -> Just r
 where
  go x = case asAnd x of
    Just (a, b) | Just d <- asNot b -> let (base, ds) = go a in (base, ds <> [d])
    _ -> (x, [])

asAnd :: Expr Resolved -> Maybe (Expr Resolved, Expr Resolved)
asAnd = \case
  And _ a b                              -> Just (a, b)
  App _ r [a, b] | isBuiltinNamed r "__AND__" -> Just (a, b)
  _                                      -> Nothing

asNot :: Expr Resolved -> Maybe (Expr Resolved)
asNot = \case
  Not _ a                             -> Just a
  App _ r [a] | isBuiltinNamed r "__NOT__" -> Just a
  _                                   -> Nothing

isBuiltinNamed :: Resolved -> Text -> Bool
isBuiltinNamed r nm = plainName r == nm || unqualifiedNameToText (getActual r) == nm

-- | The first-match arms of a @BRANCH@, an @IF@, or a literal @CONSIDER@.
cascadeArms :: Expr Resolved -> Maybe ([(Expr Resolved, Expr Resolved)], Expr Resolved)
cascadeArms = \case
  MultiWayIf _ guards oth -> Just ([ (c, b) | MkGuardedExpr _ c b <- guards ], oth)
  IfThenElse _ c t e      -> Just ([(c, t)], e)
  e@(Consider {})         -> litConsiderArms e
  _                       -> Nothing

-- | A @CONSIDER@ whose patterns are all literals is an equality cascade; Catala
-- patterns are constructor-only, so this is the shape §4.3 sends to @if@/@else@.
--
-- The @OTHERWISE@ must be the /last/ branch. L4's @CONSIDER@ is first-match, so
-- an @OTHERWISE@ written before a @WHEN@ shadows it and the whole cascade
-- collapses to that one value; an if\/else chain assembled arms-then-default
-- would answer with the shadowed arm instead. That is a change of denotation
-- rather than of shape, so this returns 'Nothing' and 'lowerConsider' rejects
-- with §4.3's message. (Nothing else catches it: @l4 check@ reports the
-- literal case as clean.)
litConsiderArms :: Expr Resolved -> Maybe ([(Expr Resolved, Expr Resolved)], Expr Resolved)
litConsiderArms (Consider ann scrut branches)
  | (initial, [MkBranch _ (Otherwise _) oth]) <- splitAt (length branches - 1) branches
  , not (null initial)
  , Just whens <- traverse litBranch initial =
      Just ([ (Equals ann scrut (Lit ann l), b) | (l, b) <- whens ], oth)
 where
  litBranch = \case
    MkBranch _ (When _ (PatLit _ l)) b -> Just (l, b)
    _                                  -> Nothing
litConsiderArms _ = Nothing
