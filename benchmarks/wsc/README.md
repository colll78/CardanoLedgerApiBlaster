# WSC containment tractability benchmark

This opt-in benchmark gives Blaster optimization branches the same WSC
containment goal to attempt. It is copied from the WSC reference implementation,
with the statement, helper definitions, script bytes, and 10,000-step CEK fuel
preserved. It does not impose an input-size bound or supply a custom invariant.
The repository's ordinary library and test targets do not run this benchmark.

The goal is: for an accepted, valid V3 script context, an asset that is not
exempt satisfies

```text
quantity at the published base payment credential in inputs + signed mint
  ≤ quantity at that payment credential in outputs
```

The second theorem gives the bound or the asset's exemption. The complete
quantifiers and premises are visible in both proof files:

- `WscContainment/Script.lean`: import the pinned original UPLC script.
- `WscContainment/Specification.lean`: quantities, parameter decoding, exemptions.
- `WscContainment/Plain.lean`: both theorems using ordinary `blaster`.
- `WscContainment/Auto.lean`: the original `(induction: auto)` proof invocation.
- `fixtures/wsc-poc/README.md`: script provenance and SHA-256.

## Run an optimization branch

On Linux, install the repository's Lean toolchain, Z3 (the reference uses
4.15.2), GNU `time`, and GNU `timeout`. From the repository root:

```sh
cd benchmarks/wsc
./check.sh plain -KblasterRev=beta-lambda-cache-optimization

# Test a different upstream branch or a commit:
./check.sh plain -KblasterRev=YOUR_OPTIMIZATION_BRANCH_OR_COMMIT

# Test a branch in another fork:
./check.sh plain -KblasterUrl=https://github.com/OWNER/Lean-blaster \
  -KblasterRev=YOUR_BRANCH_OR_COMMIT

# Reuse an existing local checkout and its compiled artifacts:
./check.sh plain -KblasterPath=/absolute/path/to/Lean-blaster
```

The package pins the original compatible upstream library model: ledger
`5dab3c4` and PlutusCore `d85df05` (from `value-builtins`, needed for CIP-153).
Keeping these fixed isolates solver-branch comparisons and preserves the
original statement's ledger model. Current ledger `main` expects a bytestring
ordering instance absent from that older PlutusCore branch, so mixing those
defaults would fail before the proof attempt.

Override the libraries with `-KledgerRev=REF`, `-KplutusUrl=URL`, and
`-KplutusRev=REF` if needed; use a compatible pair and hold them fixed when
comparing solver branches. Every run refreshes selected git refs and saves the
resolved manifest. `-KblasterPath` takes precedence over solver URL/ref settings;
the local checkout's commit and tracked diff summary are recorded too.

The default wall-clock budget is **30 minutes**, including dependency setup.
`WSC_TIMEOUT_SECONDS=600 ./check.sh plain ...` changes it. Each SMT query uses
the original 15-second solver timeout. The runner applies an **8 GiB** memory
scope where a user systemd manager is available; elsewhere, run inside an
equivalent container limit to make resource comparisons meaningful.

Results are written to `.lake/tractability.MODE.XXXXXX/`: dependency revisions,
tool versions, logs, per-stage elapsed time and maximum RSS, and a result file.
Compare `proof.time` separately from dependency/build time and use equally warm
caches. A pass requires both theorems to compile and their printed axiom lists
to contain no `sorryAx`. A timeout or unsuccessful proof remains a failure;
there is no expected-`Undetermined` escape hatch. Blaster's existing
`blasterProven` SMT trust mechanism is retained.

For preparation without an expensive proof attempt:

```sh
lake -R -KblasterRev=YOUR_BRANCH_OR_COMMIT update
lake -KblasterRev=YOUR_BRANCH_OR_COMMIT build WscContainment
```

## Compare upstream branches with only Fin compatibility

The general-purpose UPLC constant datatype includes BLS field elements backed
by `Fin`, even though this validator contains no BLS constants or builtin calls.
The upstream solver revisions below cannot translate those fields. To attempt
the full goal using their own optimizations, opt into the same small patch:

```sh
WSC_FIN_COMPAT=1 ./check.sh plain -KblasterRev=beta-lambda-cache-optimization
WSC_FIN_COMPAT=1 ./check.sh plain -KblasterRev=refs/pull/283/head
WSC_FIN_COMPAT=1 ./check.sh plain -KblasterRev=refs/pull/255/head
WSC_FIN_COMPAT=1 ./check.sh plain -KblasterRev=refs/pull/223/head

# Local checkouts work too; use an isolated checkout because this changes it:
WSC_FIN_COMPAT=1 ./check.sh plain -KblasterPath=/absolute/path/to/Lean-blaster
```

`compat/fin-sort.patch` adds only 21 lines in
`Blaster/Smt/Translate/Quantifier.lean`. It extracts the `Fin` translation from
[Lean-blaster PR #285](https://github.com/input-output-hk/Lean-blaster/pull/285)
(commit `08002278c0fe6e8042c5e1380a12fb4511c79777`) and extends the same
abstraction to `BitVec` and `Char`: the ordinary proof next reaches `BitVec`,
then the character validity condition attempts to use selectors on abstract
bit vectors. Abstracting characters avoids generating that condition. It includes
no optimizer changes, automatic induction, invariant search, or library facts. The theorem
statements, helpers, script bytes, library revisions, and CEK fuel stay the same.

The patch uses an uninterpreted sort and membership predicate per `Fin n`,
`BitVec w`, or `Char`; it does not encode finite arithmetic or cardinality.
This abstraction permits sound `unsat` proofs, but an abstract `sat` model need not be a concrete Lean
counterexample. It deliberately does not map `Fin` to unbounded integers.
`compat/FinSmoke.lean` checks all three datatype translations and three false
implications that an unbounded-integer encoding would incorrectly prove.

The runner reconfigures Lake for each selection, checks the solver import
path, applies the patch after dependency selection, accepts an already
applied patch, and fails without changing the checkout if it conflicts. It
records the patch, its SHA-256, and the complete solver diff in the result
directory, then runs the smoke checks and the ordinary containment proof.
`WSC_FIN_COMPAT=0` (the default) runs the selected solver without patching it;
use an unmodified checkout for that baseline. To apply or remove it manually:

```sh
bash compat/apply-fin.sh /absolute/path/to/Lean-blaster
git -C /absolute/path/to/Lean-blaster apply --reverse "$PWD/compat/fin-sort.patch"
```

## Automatic-induction reference

`./check.sh auto ...` selects the original tactic. This requires a solver that
supports `(induction: auto)`, proposed in
[Lean-blaster #285](https://github.com/input-output-hk/Lean-blaster/pull/285).
An unsupported tactic option is a compatibility failure, not a timing result;
use `plain` on ordinary upstream optimization branches. Compare branches using
the same proof mode.

The successful reference implementation and checked export are recorded at
[wsc-blaster commit 0984f4e](https://github.com/SeungheonOh/wsc-blaster/blob/0984f4eab44ce565d5c6dd7f4c744e01394bd78e/examples/README.md).
It uses that project's supporting solver and library implementations. An
upstream branch is not assumed to reproduce that result; discovering whether
it can is the purpose of this benchmark.

## Recorded validation

With Lean 4.24.0 and Z3 4.15.2:

- Upstream Blaster `bafdd4f`, ledger `5dab3c4`, and PlutusCore `d85df05` build
  the fixture and specification successfully (349 jobs).
- The upstream `plain` attempt fails at unsupported `Fin` translation after
  96.82 seconds of proof-stage wall time, with maximum RSS 4,471,696 KiB. This
  is a translation failure, not a timeout or a proof of the theorem.
- With the same finite-type patch, beta and PR heads #283, #255, and #223
  build and pass all six smoke checks. All four ordinary containment attempts
  then stop at `translateType: sort type expected ... Lean.Level.zero`,
  before final SMT solving. See [the recorded comparisons](compat/RESULTS.md)
  for exact commits, patch hash, observed metrics, and reproduction inputs.
- Both copied `auto` theorems compile with the WSC reference implementation;
  the case proof was checked at 447 seconds. Their axiom lists contain
  `propext`, `Classical.choice`, `Quot.sound`, and `Blaster.Tactic.blasterProven`,
  with no `sorryAx`.
- A 10-second deadline was exercised: setup and build completed, and the proof
  attempt correctly exited 124 as `TIMEOUT`.
- After adding explicit Lake reconfiguration, distinct local checkouts and
  a remote PR revision were verified through both manifest and import path.
  The 15-second remote-selection check applied the patch and timed out during
  its build. Patch application, idempotence, reversal, and conflict rejection
  were checked; conflicting application left the checkout unchanged.

## Inherited specification details

The ledger-validity premise uses this library's `validScriptContext` model.
Negative reference indices clamp to zero through `Int.toNat`. The conservative
directory exemption checks all reference inputs, including ones not selected
by the redeemer. These details are preserved from the original statement;
successful execution alone is not an unconditional containment claim.
