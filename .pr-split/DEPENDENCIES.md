# Measured dependencies between the aug2026 PRs

Derived mechanically by `depcheck.mjs`: for every Haskell module a theme ships, resolve its
imports against the modules the other themes ship, ignoring anything `main` already has.
Five edges exist. Everything not listed here has no compile-time dependency on a sibling.

    ladder-viz  <--  dmn-export  <--  bpmn-export  <--  service-cli
                          ^                                 |
                          +---------------------------------+
                     openfisca-export  <--------------------+

| edge | why |
| --- | --- |
| `dmn-export` needs `ladder-viz` | `L4.Dmn.Lower` imports `L4.Viz.GuardedRows`, the guarded-chain normaliser |
| `bpmn-export` needs `dmn-export` | `L4.Bpmn.Wiring` imports `L4.Dmn.IR`; `L4.Bpmn.IR`/`Lower` import `L4.Interchange.Fidelity`; the BPMN test imports the DMN test module. This is the "BPMN delegates decisions to DMN" mandate, not an accident of packaging. |
| `service-cli` needs `dmn-export`, `bpmn-export`, `openfisca-export` | `l4 export` is the CLI surface over all three back ends |

Suggested merge order: `ladder-viz` -> `dmn-export` -> `bpmn-export` / `openfisca-export` -> `service-cli`.
Every other PR may merge in any order.

`ci-build` should merge **last**: the workflow it ships references check scripts that arrive
with the feature PRs, so landing it early would redden `main` for checks whose subjects are
not there yet.
