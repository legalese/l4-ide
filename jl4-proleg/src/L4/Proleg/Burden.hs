-- | A burden-of-proof monad: a truth value paired with an accumulating ledger
-- of evidential obligations (which party must establish which claim).
--
-- The construction and its theory are written up in @docs\/burden-of-proof.md@.
-- In brief: \"a value carrying its evidential subject\" is the coreader\/env
-- comonad @(Subject, a)@; it becomes a /monad/ exactly when the subject carries
-- a 'Monoid'. We do not merge subjects (there is no sensible
-- @plaintiff \<> defendant@); instead we accumulate them into a ledger — the
-- free monoid, i.e. a 'Writer'. Stacked over the truth dimension @Maybe@, in the
-- order that keeps the ledger even on a failed proof (so blame survives), this is
-- @'MaybeT' ('Writer' ['Obligation'])@.
module L4.Proleg.Burden
  ( Subject (..)
  , opposite
  , Obligation (..)
  , Provable
  , prove
  , established
  , unestablished
  , conj
  , disj
  , notProven
  , flipBurden
  , absent
  , resolve
  , obligations
  , runProvable
  ) where

import Control.Monad.Trans.Maybe (MaybeT (..))
import Control.Monad.Trans.Writer.Strict (Writer, censor, runWriter, writer)
import Data.Maybe (isJust)
import Data.Text (Text)

-- | A litigation party / evidential subject.
data Subject = Plaintiff | Defendant
  deriving stock (Eq, Show)

-- | The adversary. Models PROLEG's @opposite(P)@.
opposite :: Subject -> Subject
opposite Plaintiff = Defendant
opposite Defendant = Plaintiff

-- | One elementary burden: the party who must establish a named claim.
data Obligation = Obligation {onWhom :: Subject, what :: Text}
  deriving stock (Eq, Show)

-- | The burden-of-proof monad: @Maybe@ truth + a ledger of obligations, keeping
-- the ledger even when the claim is not established (@MaybeT@ outside @Writer@).
--
-- @Provable a@ ≅ @Writer [Obligation] (Maybe a)@ ≅ @([Obligation], Maybe a)@.
type Provable = MaybeT (Writer [Obligation])

-- | Inject a primitive evidential value under a bearer: record who must
-- establish @claim@, and whether it is in fact established (@Just@ \/ @Nothing@).
prove :: Subject -> Text -> Maybe a -> Provable a
prove p claim mx = MaybeT (writer (mx, [Obligation p claim]))

-- | A claim its bearer has established (admitted, or proven to standard).
established :: Subject -> Text -> Provable ()
established p claim = prove p claim (Just ())

-- | A claim its bearer has /not/ established (alleged but unproven, or unraised).
unestablished :: Subject -> Text -> Provable ()
unestablished p claim = prove p claim Nothing

-- | Conjunction of a rule body. Deliberately /accumulating/, not short-circuit:
-- every conjunct's obligation is recorded (building the full responsibility map),
-- and the body holds iff all conjuncts hold.
conj :: [Provable a] -> Provable ()
conj ps = MaybeT do
  ms <- traverse runMaybeT ps
  pure (sequence_ ms)

-- | Disjunction (alternative grounds). Accumulating; holds iff any disjunct does.
disj :: [Provable a] -> Provable ()
disj ps = MaybeT do
  ms <- traverse runMaybeT ps
  pure (if any isJust ms then Just () else Nothing)

-- | Negation as failure: holds iff its argument is /not/ established. The
-- argument's obligations are still recorded. How an @exception@ enters a rule
-- body (usually via 'absent').
notProven :: Provable a -> Provable ()
notProven (MaybeT w) = MaybeT do
  m <- w
  pure (if isJust m then Nothing else Just ())

-- | Relabel every obligation in a sub-derivation to the opposite party. An
-- involution (@flipBurden . flipBurden = id@). Models PROLEG descending into an
-- exception by proving it for @opposite(P)@.
flipBurden :: Provable a -> Provable a
flipBurden (MaybeT w) = MaybeT (censor (map flip1) w)
  where
    flip1 (Obligation s c) = Obligation (opposite s) c

-- | An exception\/defeater borne by the opposite party: the rule survives unless
-- the defeater is established. @absent = notProven . flipBurden@.
absent :: Provable a -> Provable ()
absent = notProven . flipBurden

-- | Resolve to a closed-world boolean: established ⇒ True, otherwise the burden's
-- default (the bearer loses) ⇒ False. The 'L4.Proleg.Burden'-level reading of the
-- earlier @Default@ fallback.
resolve :: Provable a -> Bool
resolve = isJust . fst . runProvable

-- | The accumulated responsibility ledger.
obligations :: Provable a -> [Obligation]
obligations = snd . runProvable

-- | Run: the (possibly unestablished) value together with its obligation ledger.
runProvable :: Provable a -> (Maybe a, [Obligation])
runProvable = runWriter . runMaybeT
