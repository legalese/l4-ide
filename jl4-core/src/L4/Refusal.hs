-- | Whether a definition may refuse to answer, and with which reasons, read
-- from what is written; and the one answer a query planner gives for a rule
-- that may refuse.
module L4.Refusal (
  refusalReasons,
  PlanDecline (..),
  planDecline,
  declineMessage,
) where

import Base

import qualified Data.Aeson as Aeson
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import L4.Print (prettyLayout)
import L4.Syntax
import Optics

-- | The reason of every @REFUSE@ that evaluating the definition may reach. It
-- holds each one written in the definition's body, every clause of it and
-- every WHERE or LET definition in it included, and each one written in a
-- top-level definition the body names, or one that names, and so on through
-- the given modules. Pass the module and every module it imports, directly or
-- not: a name defined in a module that is not passed is not followed.
--
-- It reads what is written and evaluates nothing, so it holds the reason of a
-- @REFUSE@ that no input reaches, and an empty set means that no @REFUSE@ can
-- be reached through what is written. It follows each name once, so it ends on
-- recursion, and a module passed twice changes nothing.
refusalReasons :: [Module Resolved] -> Decide Resolved -> Set Text
refusalReasons mods = reasonsOf
 where
  -- Every top-level definition, under the Unique of its name, which each of
  -- its AKA names shares, with its body; a clause group is one definition,
  -- its clauses one CONSIDER. A WHERE or LET definition needs no entry: a
  -- name that calls it sits in the expression that defines it, which
  -- 'refusesIn' reads whole.
  bodies :: Map Unique (Expr Resolved)
  bodies = Map.fromList
    [ (getUnique h, body)
    | m <- mods
    , MkDecide _ _ (MkAppForm _ h _ _) body <- foldTopLevelDecides (: []) m
    ]

  reasonsOf :: Decide Resolved -> Set Text
  reasonsOf (MkDecide _ _ (MkAppForm _ h _ _) body) =
    go (Set.singleton (getUnique h)) Set.empty [body]

  go :: Set Unique -> Set Text -> [Expr Resolved] -> Set Text
  go _ acc [] = acc
  go seen acc (e : es) =
    let named = Set.fromList [u | Ref _ u _ <- toList e] `Set.difference` seen
    in go (seen <> named) (acc <> refusesIn e) ([b | u <- Set.toList named, Just b <- [Map.lookup u bodies]] <> es)

-- | The reason of every @REFUSE@ written in the expression.
refusesIn :: Expr Resolved -> Set Text
refusesIn =
  foldMapOf (cosmosOf (gplate @(Expr Resolved))) \case
    Refuse _ (Lit _ (StringLit _ reason)) -> Set.singleton reason
    -- The parser admits only a string literal here; any other message is
    -- still a refusal, so it is kept, printed as its reason.
    Refuse _ message -> Set.singleton (prettyLayout message)
    _ -> Set.empty

-- | A query planner's answer for a rule that may refuse to answer: no plan,
-- because a plan would say which inputs settle an answer the rule may not
-- give. It names the rule as L4 writes it, and every reason the rule may
-- refuse with, in order.
data PlanDecline = MkPlanDecline
  { rule :: !Text
  , reasons :: ![Text]
  }
  deriving stock (Eq, Show, Generic)

-- | The decline for the definition, if it may refuse to answer
-- ('refusalReasons'); 'Nothing' if it cannot.
planDecline :: [Module Resolved] -> Decide Resolved -> Maybe PlanDecline
planDecline mods = decline
 where
  reasonsOf = refusalReasons mods
  decline d@(MkDecide _ _ (MkAppForm _ h _ _) _) =
    let reasons = reasonsOf d
    in if Set.null reasons
        then Nothing
        else Just MkPlanDecline {rule = prettyLayout (getActual h), reasons = Set.toList reasons}

-- | The sentence that says why there is no plan, naming the rule and every
-- reason.
declineMessage :: PlanDecline -> Text
declineMessage d =
  "No query plan for " <> d.rule <> ": it may refuse to answer, with the reason " <> orList (map quoted d.reasons) <> "."
 where
  quoted r = "\"" <> r <> "\""
  orList = \case
    [] -> ""
    [r] -> r
    [r1, r2] -> r1 <> " or " <> r2
    r : rs -> r <> ", " <> orList rs

-- | The sentence under @error@, so that a client that reads only @error@ shows
-- it, beside @kind@ (always @declined@), the rule and its reasons.
instance Aeson.ToJSON PlanDecline where
  toJSON d =
    Aeson.object
      [ "error" Aeson..= declineMessage d
      , "kind" Aeson..= ("declined" :: Text)
      , "rule" Aeson..= d.rule
      , "reasons" Aeson..= d.reasons
      ]
