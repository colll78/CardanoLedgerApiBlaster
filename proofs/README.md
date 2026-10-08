# Optional CardanoLedgerApi library facts

This package supplies Blaster summaries for asset lookup, conversion to/from
PlutusCore Value, valid output values, valid mint values, inline datums, and V3
context observers. Import `CardanoLedgerApiFacts`, or a specific module under
that namespace. The ordinary ledger library imports and sources are unchanged.

From the repository root:

```sh
cd proofs
lake build
lake test
```

CI uses Lean 4.24.0 and Z3 4.15.2. The package pins the supporting Lean-blaster
and PlutusCore fact commits in `lakefile.lean`. Those forks supply functional
induction, explicit theorem summaries, `@[blaster_library]`, and the Value
builtin implementation (upstream PlutusCore PR #15). This is an opt-in package
pending those upstream dependencies.

Facts retain their validity, sortedness, and successful-decoding premises.
In particular, output quantities are nonnegative only for valid output values;
mint quantities can be negative. Tests check downstream summary use, reject
unconditional nonnegativity, and check malformed lookup behavior.

## Trust boundary

These are SMT-verified facts, admitted by Blaster's `blasterProven` axiom;
they are not Lean kernel proof terms. Solver soundness and the Lean-to-SMT
translation are trusted. See the dependency's `WSC_PROOF_SUPPORT.md` for its
validation and the proof-registration restrictions.
