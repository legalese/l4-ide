-- | The rungs of a decision: the conditions it branches on, in the order the
-- rest of the system reads them.
--
-- A decision written as a proviso chain (@c AND NOT d1 AND NOT d2@) has the
-- rungs @c@, @d1@, @d2@; a @BRANCH@, an @IF@ or a literal @CONSIDER@ has the
-- condition of each arm; any other BOOLEAN decision is one rung, its body.
-- "L4.Catala.Lower" builds its exception ladders from the first two shapes
-- ('ladderAtoms'), and "L4.Cli.Coverage" counts the leaves of the rungs
-- ('rungsOf'); both read those shapes from here, so they cannot come to
-- disagree about what a rung of them is.
--
-- The coverage report reads one shape more, and the Catala lowering does not:
-- a non-BOOLEAN decision whose body is a @CONSIDER@ whose every @WHEN@ is one
-- condition ('considerRungs'), which takes in the literal @CONSIDER@ of such a
-- decision as well (smucclaw/l4-ide#1094). That shape is kept out of
-- 'ladderAtoms', 'cascadeArms' and 'litConsiderArms', which the lowering
-- reads, so that @l4 export catala@ does not change with it.
module L4.Coverage.Rungs
  ( rungsOf
  , considerRungs
  , ladderAtoms
  , peelProvisos
  , cascadeArms
  , litConsiderArms
  , asAnd
  , asNot
  , isBuiltinNamed
  , plainName
  , rungHolding
  ) where

import Base
import Optics (cosmosOf, gplate, toListOf)
import L4.Annotation (rangeOf)
import L4.Parser.SrcSpan (SrcRange (..))
import L4.Syntax
import qualified L4.TypeCheck.Environment as TC

-- | The rungs of a decision's body: the ladder shapes' conditions, else the
-- whole body when the decision is BOOLEAN, else none (a decision with nothing
-- it branches on). The body of a non-BOOLEAN decision that is a @CONSIDER@
-- is read by 'considerRungs' instead, and has no rungs here when that refuses
-- it ('considerRungs' says why).
rungsOf :: Bool -> Expr Resolved -> Maybe [Expr Resolved]
rungsOf isCondition body
  | not isCondition, Just r <- considerRungs body = either (const Nothing) Just r
  | otherwise = case ladderAtoms isCondition body of
      Just rs -> Just rs
      Nothing | isCondition -> Just [body]
              | otherwise -> Nothing

-- | A @CONSIDER@ as the conditions of its arms, for the coverage report:
-- @WHEN basic@ over @p@ is @p EQUALS basic@, a literal or an @EXACTLY@ arm
-- likewise, which is how "L4.Viz.GuardedRows" reads a pattern. 'Nothing' when
-- the expression is not a @CONSIDER@. @'Left' lhs@ names the first arm that is
-- not one yes-or-no condition: a @WHEN@ that takes an option's fields apart,
-- has a pattern inside a pattern, or gives a new name to what it matches, or
-- an @OTHERWISE@ that is not the last arm, after which the arms are never
-- reached (CONSIDER is first-match). A text arm gets its condition too, but
-- the solver's lowering refuses text ('L4.Prove.Lower.sortOf'), so a decision
-- with one is not covered all the same.
--
-- Each condition carries the span of its @WHEN@ and the type BOOLEAN. The
-- type is what the ladder diagram insists on before it breaks rungs into
-- leaves; 'litConsiderArms' gives its equalities the annotation of the whole
-- @CONSIDER@ instead, whose type in a non-BOOLEAN decision is not BOOLEAN, so
-- the coverage report used to cover such a decision at rung level, every cover
-- point spanning the whole @CONSIDER@. That function is left as it is, because
-- "L4.Catala.Lower" reads it.
considerRungs :: Expr Resolved -> Maybe (Either (BranchLhs Resolved) [Expr Resolved])
considerRungs = \case
  Consider _ scrut branches -> Just (arms scrut branches)
  _ -> Nothing
 where
  arms scrut = \case
    [] -> Right []
    [MkBranch _ (Otherwise _) _] -> Right []
    MkBranch _ lhs@(Otherwise _) _ : _ -> Left lhs
    MkBranch _ lhs@(When wAnn pat) _ : rest -> case pat of
      PatApp pAnn con [] -> (equals wAnn scrut (App pAnn con []) :) <$> arms scrut rest
      PatLit pAnn l      -> (equals wAnn scrut (Lit pAnn l) :) <$> arms scrut rest
      PatExpr _ e        -> (equals wAnn scrut e :) <$> arms scrut rest
      _                  -> Left lhs
  equals wAnn = Equals (set annInfo (Just (TypeInfo TC.boolean Nothing)) wAnn)

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

-- | The rung, by its index, that a leaf of the ladder diagram belongs to: the
-- one whose source span holds the leaf's. The diagram's leaf is not always
-- equal to the rung's subexpression (its annotation can differ), but it keeps
-- the span the author wrote it at. Where several rungs share a span, as the
-- arms of a literal @CONSIDER@ of a BOOLEAN decision do (each spans the whole
-- @CONSIDER@), the first that has the leaf inside it by equality is taken;
-- where none does, or no rung's span holds the leaf, 'Nothing'.
rungHolding :: [Expr Resolved] -> Expr Resolved -> Maybe Int
rungHolding rungs e = case [ i | Just re <- [rangeOf e], (i, r) <- indexed, maybe False (holds re) (rangeOf r) ] of
  [i] -> Just i
  is -> listToMaybe [ i | i <- if null is then map fst indexed else is
                        , e `elem` toListOf (cosmosOf (gplate @(Expr Resolved))) (rungs !! i) ]
 where
  indexed = zip [0 ..] rungs
  holds :: SrcRange -> SrcRange -> Bool
  holds inner outer = inner.moduleUri == outer.moduleUri && outer.start <= inner.start && inner.end <= outer.end
