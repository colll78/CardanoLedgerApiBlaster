# Ordinary WSC proof attempts with finite-type compatibility

Recorded 2026-10-08 with Lean 4.24.0 and Z3 4.15.2. All four isolated solver
checkouts have exactly the same 21-line addition in one translation file.
They use ordinary `blaster`; no optimizer, automatic-induction, invariant-search,
or library-fact changes from Lean-blaster #285 are included.

```sh
WSC_FIN_COMPAT=1 ./check.sh plain -KblasterPath=/path/to/isolated/solver
```

| Solver | Upstream commit | Proof wall time | Maximum RSS (KiB) | Result |
| --- | --- | ---: | ---: | --- |
| beta-lambda-cache-optimization | `bafdd4f7` | 113.98 s | 4,474,252 | Same translation error |
| #283 | `660acae4` | 114.04 s | 4,485,476 | Same translation error |
| #255 | `6ec81471` | 114.06 s | 4,485,496 | Same translation error |
| #223 | `26ec7cc1` | 114.75 s | 4,475,376 | Same translation error |

All fixture/specification builds and all six finite-type smoke checks pass.
Every complete proof attempt exits 1 at the same remaining translation error:

```text
WscContainment/Plain.lean:25:2: error:
translateType: sort type expected but got Lean.Expr.sort (Lean.Level.zero)
```

This is a translation failure, not `Undetermined`, a solver timeout, a concrete
counterexample, or a completed containment proof. Lean prints `sorryAx` after
its failed theorem elaboration; the runner correctly rejects these attempts.
The proof did not reach the final SMT solving stage, so these results do not
establish whether the branches' optimizations can prove containment. Runs
shared a host concurrently; the times are diagnostic observations, not a
performance ranking.

The earlier Fin-only bridge got the beta run past Fin and exposed unsupported
BitVec. Abstracting BitVec then exposed the character validity condition's
undeclared `BitVec.ofFin.0` selector. The final bridge treats Fin, BitVec, and
Char uniformly as abstract finite sorts. General operations and cardinality
reasoning remain outside this compatibility patch.

## Reproduction inputs

- Patch SHA-256: `9347b3a7383d1b326a04e3e61aa76d6f87d3ccf247517a6f545d0e5003e609c4`.
- Plain proof SHA-256: `ea30edb02da1edf4a423a8d06a4ec7670c86646b6379f8b23edc2ef4fb66f624`.
- Ledger: `5dab3c43f042b8735b6d067223baaa8d32ed28a1`.
- PlutusCore: `d85df0512fbc556a095a2d4c6276b528395eb06c`.
- Validator SHA-256: `bbd64b39e8255fceba8c9fe37dbb09841b5a4143f3ce5d853fbdfbf47e5bcffa`.
- Solver commits:
- beta: `bafdd4f7976037cd7bd8e443df04af096dc5b96e`.
- pr283: `660acae45303abd2ed03cca25f97d4a0350be26e`.
- pr255: `6ec814714011cfd42574ec791e4d4c8a02172dd5`.
- pr223: `26ec7cc15723184aedec1000beb4051e56765913`.
- Ordinary proof, 10,000-step CEK fuel, 15-second per-query timeout,
  1,800-second overall deadline, 8 GiB systemd scope.

The runner records the selected solver import path, full solver diff, patch,
manifest, smoke/proof logs, time/RSS, and exit classification for each run.
Cached Lake configuration is explicitly rebuilt with `-R`: local and git
revision selections were verified to select different solver checkouts, and
an incompatible patch is rejected without changes.
