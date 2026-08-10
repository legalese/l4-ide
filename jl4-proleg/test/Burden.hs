-- | Exercises the burden-of-proof monad on the @examples/lease.pl@ judgement:
-- the plaintiff proves @contract_end@, the defendant's two defences fail (one
-- unproven, one defeated by the plaintiff's exception-of-exception), and the
-- accumulated obligation ledger attributes each fact to the right party.
module Main (main) where

import Control.Monad (unless)
import System.Exit (exitFailure)

import L4.Proleg.Burden

main :: IO ()
main = do
  results <- mapM report checks
  unless (and results) exitFailure

report :: (String, Bool) -> IO Bool
report (label, ok) = do
  putStrLn ((if ok then "PASS " else "FAIL ") ++ label)
  pure ok

checks :: [(String, Bool)]
checks =
  [ ("lease: plaintiff proves contract_end", resolve contractEnd)
  , ("lease: cancellation_due_to_sublease holds", resolve cancellation)
  , ("lease: get_approval_of_sublease fails (not plausible)", not (resolve getApproval))
  , ("lease: nonabuse_of_confidence defeated by abuse", not (resolve nonabuse))
  , ("ledger: abuse borne by plaintiff", Obligation Plaintiff "fact_of_abuse_of_confidence" `elem` obligations contractEnd)
  , ("ledger: nonabuse borne by defendant", Obligation Defendant "fact_of_nonabuse_of_confidence" `elem` obligations contractEnd)
  , ("flipBurden is an involution", obligations (flipBurden (flipBurden abuse)) == obligations abuse)
  , ("flipBurden swaps subject", Obligation Defendant "fact_of_abuse_of_confidence" `elem` obligations (flipBurden abuse))
  ]
  where
    -- Factbase from examples/lease.pl. The six constitutive facts are the
    -- *plaintiff's* burden (requirements of the cancellation claim) yet were
    -- established here via the defendant's admission: bearer and establishment
    -- are independent, which is exactly what Provable keeps apart.
    constitutive =
      [ established Plaintiff "agreement_of_lease_contract"
      , established Plaintiff "handover_to_lessee"
      , established Plaintiff "agreement_of_sublease_contract"
      , established Plaintiff "handover_to_sublessee"
      , established Plaintiff "using_leased_thing"
      , established Plaintiff "manifestation_cancellation"
      ]

    getApproval =
      conj
        [ unestablished Defendant "approval_of_sublease"
        , unestablished Defendant "approval_before_cancellation"
        ]

    abuse = conj [established Plaintiff "fact_of_abuse_of_confidence"]

    nonabuse =
      conj
        [ established Defendant "fact_of_nonabuse_of_confidence"
        , notProven abuse -- exception(nonabuse_of_confidence, abuse_of_confidence)
        ]

    cancellation =
      conj
        ( constitutive
            ++ [ notProven getApproval -- exception(cancellation, get_approval_of_sublease)
               , notProven nonabuse -- exception(cancellation, nonabuse_of_confidence)
               ]
        )

    contractEnd = disj [cancellation]
