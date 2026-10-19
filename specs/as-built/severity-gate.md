# Severity gate: a warning is not a failed check (as built)

As built on unstable at 73a953821. Source spec: specs/todo/IMPLICIT-PROPS-DESIGN.md (on unstable only, not on main or in this PR; §11.1.3, the paragraph that begins `**"Never an error" had to be made true`, at `:837`; the rest of the file is other features). Differences from the source spec: the paragraph says "three gates" and then lists four sites, three in `jl4-core` and one copy in `jl4-wasm`; it motivates the fix by the ASSUME deprecation warning and names `DeprecatedAssumeSpec.hs` as the test that pins it, and both of those belong to the rest of #358, which is not in this PR.

Scope: the first commit of #358 only, `fcee7e298d` ("fix(api): a warning is not a failed check at checkWithImports, l4Eval, or the visualizers").
The rest of #358, the ASSUME deprecation warning and its tests, is a separate change on unstable and is described elsewhere.

## What it does

Three API entry points and one WASM export decided "did this module check?" without counting only errors: three of them ignored severity, so a warning or even a `#CHECK` info made a module fail through them alone, and `l4Eval` failed on any warning.
They now count only `SError` diagnostics, as the Shake typecheck rule, `l4 check` and jl4-service already did.

## Where it lives

- `jl4-core/src/L4/Import/Resolution.hs:343 @ 73a953821`: `tcdSuccess = not (any ((== TypeCheck.SError) . TypeCheck.severity) result.errors)`, in `typecheckWithDependencies`; it was `null result.errors`.
- `jl4-core/src/L4/API.hs:240 @ 73a953821`: `l4Eval` keeps `severity e == SError` as its failures; it was `severity e /= SInfo`, which made every warning fatal.
- `jl4-core/src/L4/API.hs:621 @ 73a953821`: `l4VisualizeByName` reports "Type check error" only if `any ((== SError) . severity) result.tcdErrors`; it was `not (null result.tcdErrors)`.
- `jl4-wasm/app/QueryPlanWasm.hs:46 @ 73a953821`: `l4QueryPlan`, the same test as `l4VisualizeByName`, with new imports of `severity` and `Severity (..)`.

## Behaviour and rules

- `severity` (`jl4-core/src/L4/TypeCheck/Types.hs:672-679 @ 73a953821`) maps `CheckWarning` to `SWarn`, `CheckInfo` (and, on unstable, `SuspiciousBinderPattern` and `ActionPatternReference`) to `SInfo`, and everything else to `SError`; only `SError` blocks at these four gates.
- `tcdErrors` still carries infos and warnings, and `l4Check` still returns them.
  `l4Eval`'s failure payload now carries the `SError` diagnostics only (it carried `SWarn` and `SError`), and its success payload carries no diagnostics.
- The Shake typecheck rule already decided success this way on main (`jl4-lsp/src/LSP/L4/Rules.hs:568 @ 66c30f987`; on unstable the partition is at `Rules.hs:886-890`), so the LSP and these APIs now agree on success.
- On main the warnings that exist are the exhaustiveness warnings (`PatternMatchesMissing`, `PatternMatchRedundant`; read on main at `66c30f987`) and `#CHECK` infos.

## Diagnostics

None added or changed.

## Tests and fixtures that pin it

- This commit adds no test, and changes no golden.
- On unstable the gate is pinned by `jl4-core/test/DeprecatedAssumeSpec.hs:33-42 @ 73a953821` (a warning-bearing module has `tcdSuccess = True`, asserted at `:38`), which came with the rest of #358 on unstable.
- The commit message reports that two `UnifySpec` cases (tc-soundness's; they carry `ASSUME mystery`) went red only once #358's next commit, `d86d17350`, made every ASSUME warn; no test on main fails without the fix (main's suites pass with and without it).
- `jl4-wasm` is not in `cabal.project`, so `QueryPlanWasm.hs` is compiled only by the WASM CI job; the commit message says so.

## Limits and known defects on unstable (verified)

- On unstable the new code comments at all four sites name "the ASSUME deprecation" as an existing warning (`API.hs:236-237,619-620`, `Resolution.hs:338-342`, `QueryPlanWasm.hs:44-45`, all `@ 73a953821`).
  That warning is not on main, so in this PR the four comments say "exhaustiveness, for example" instead.
- `l4Check` (`API.hs:92-102 @ 73a953821`) and `l4StateGraphByName` (`API.hs:657 @ 73a953821`, a later feature) do not gate on `tcdErrors` at all; `l4Check` returns every diagnostic, which is its job.
