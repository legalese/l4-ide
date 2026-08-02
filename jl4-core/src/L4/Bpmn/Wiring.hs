-- | The one place the process backend reads the decision backend.
--
-- @specs\/todo\/lexipedia-superset\/PROCESS-TRACK.md@ §6 keeps the two tracks
-- independent; §8.3 then rules that the emitted BPMN __must__ wire to the
-- emitted DMN, which is a coupling. This module is where the whole of that
-- coupling lives, and it is deliberately one direction and one function wide:
-- 'L4.Bpmn.IR' and 'L4.Bpmn.Lower' import nothing from @L4.Dmn@, and @L4.Dmn@
-- imports nothing from here.
--
-- == Why the table is built from the DRG and not from the module
--
-- The alternative — have the BPMN side re-derive @decision_\<sanitised name\>@
-- from the L4 source — is the defect this design exists to make impossible.
-- The DMN backend's ids are not a function of one decide's name: they pass
-- through a module-wide @uniquifyIn@ (so a sibling's name can change yours),
-- and the population filter can drop a decide entirely (@R6@ / @FIXTURE(d)@).
-- A re-derived id is therefore a guess that is usually right, which is the
-- worst kind — it dangles only on the corpora nobody tested.
--
-- Reading 'drgDecisions' inverts that. A decision absent from the emitted graph
-- is absent from this table, so its gateway is simply not wired and says so
-- (@P-NODMN@). __A dangling @decisionRef@ is unrepresentable, not merely
-- unlikely.__
module L4.Bpmn.Wiring
  ( wiringFromDrg
  ) where

import Base
import qualified Data.Map.Strict as Map

import L4.Bpmn.IR
import L4.Dmn.IR

-- | Index an emitted decision graph by the @DECIDE@ each decision came from.
--
-- Decisions only. A tier-2 decide is emitted as a @\<businessKnowledgeModel\>@,
-- which is a /function/: it has no @\<variable\>@ for a gateway condition to
-- read and no @(namespace, model, decision)@ triple for a @businessRuleTask@ to
-- name, so a guard backed by one is correctly left unwired. Hydrators
-- ('LogicContext') have no source decide at all and carry 'Nothing', which
-- excludes them here for free.
wiringFromDrg :: Drg -> DmnWiring
wiringFromDrg drg =
  MkDmnWiring
    { dwNamespace = drg.drgNamespace
    , dwModel = drg.drgName
    , dwDecisions =
        Map.fromList
          [ (u, wired d)
          | d <- drgDecisions drg
          , Just u <- [d.dcnDecide]
          ]
    }
 where
  wired d =
    MkWiredDecision
      { wdId = d.dcnId
      , wdName = d.dcnName
      , wdFeelName = d.dcnFeelName
      , wdBoolean = dmnTypeBase d.dcnType == DmnBoolean
      , wdVerdict = verdictRows d
      }

  -- The R13 verdict shape, recognised by what it /is/ rather than by a flag:
  -- a decision table whose output is a string with an enumerated domain. That
  -- is exactly the interface DMN-EXPORT-PROGRAM-MODEL-SPEC.md §16 says the
  -- verdict lowering exists to present, and nothing else in the backend emits
  -- it, so recognising it needs no second channel that could disagree.
  --
  -- The rows, not the @\<outputValues\>@, are what comes back. The values are a
  -- de-duplicated /domain/; the rows are per-arm and in arm order, which is
  -- what a gateway with n outgoing flows needs.
  verdictRows d = case d.dcnLogic of
    LogicTable t
      | t.dtOutput.ocType == DmnString
      , isJust t.dtOutput.ocValues ->
          Just
            [ MkVerdictRow {vrGuard = r.drDescription, vrOutput = r.drOutput.feText}
            | r <- t.dtRules
            ]
    _ -> Nothing
