# Auction (Plinth) example

Formal verification of the English-auction validator from the Plutus documentation
([*Auction smart contract* tutorial](https://plutus.cardano.intersectmbo.org/docs/auction-smart-contract/on-chain-code)).
The verified artifact is the compiled PlutusV3 UPLC, not the Haskell source. The proofs are
about the script bytes that would run on chain.

| File                | Content                                                                        |
|---------------------|--------------------------------------------------------------------------------|
| `auction.cbor_hex`  | The compiled, parameter-applied validator (hex-encoded CBOR-wrapped flat UPLC) |
| `Auction.lean`      | Lean mirror of the contract types (`AuctionParams`, `Bid`, `AuctionDatum`, `AuctionRedeemer`) with their `IsData` instances; imports the script as `auction` |
| `Properties.lean`   | The transaction scenarios, the proven properties and the vulnerability audit     |

## The contract

The source is
[`doc/docusaurus/static/code/AuctionValidator.hs`](https://github.com/IntersectMBO/plutus/blob/1.64.0.0/doc/docusaurus/static/code/AuctionValidator.hs)
in the Plutus repository. A seller locks an NFT in a script UTxO. Bidders then replace that UTxO
with ever-higher bids until a deadline, after which anyone can close the auction.

### Parameters

`auctionValidatorScript :: AuctionParams -> CompiledCode (BuiltinData -> BuiltinUnit)` applies the
parameters to the compiled validator (`unsafeApplyCode … liftCodeDef params`). The CBOR in this
directory is the result of that application, so the script takes only the `ScriptContext`. The
parameters used by `QuickStart.hs` are baked in, and `Properties.lean` repeats them as constants:

| Parameter          | Value                              | Lean constant   |
|--------------------|------------------------------------|-----------------|
| `apSeller`         | 40 zero bytes                      | `sellerPKH`     |
| `apCurrencySymbol` | 28 zero bytes                      | `policyId`      |
| `apTokenName`      | `"MY_TOKEN"`                       | `nftName`       |
| `apMinBid`         | `100` lovelace                     | `bakedMinBid`   |
| `apEndTime`        | `1725227091000` ms (POSIX time)    | `bakedEndTime`  |

### Datum and redeemer

- **Datum**: `AuctionDatum = Maybe Bid`, the highest bid so far (`Nothing` before the first bid).
  `Bid = Bid { bAddr, bPkh, bAmount }`.
- **Redeemer**: `NewBid Bid` (constructor 0) or `Payout` (constructor 1).

The script must be run as a `SpendingScript` with a datum. Otherwise it fails with
`"Expected SpendingScript with a datum"`.

### `NewBid bid` succeeds iff all of the following hold

1. **`sufficientBid`**: with a previous highest bid, `bid.amount > previous.amount`. For the first
   bid, `bid.amount ≥ apMinBid`.
2. **`validBidTime`**: the transaction validity range is contained in `(-∞, apEndTime]`.
3. **`refundsPreviousHighestBid`**: if there was a previous bid, some output pays exactly
   `previous.amount` lovelace to the previous bidder's public key hash.
4. **`correctOutput`**: there is **exactly one** continuing output (an output to the address of
   the spent script input), and
   - it carries an **inline** datum that decodes to `Just bid'` with `bid == bid'`, and
   - it holds exactly `bid.amount` lovelace and exactly `1` unit of `apCurrencySymbol.apTokenName`.

### `Payout` succeeds iff all of the following hold

1. **`validPayoutTime`**: the transaction validity range is contained in `[apEndTime, +∞)`.
2. **`sellerGetsHighestBid`**: if there was a bid, some output pays exactly `bid.amount` lovelace
   to `apSeller`.
3. **`highestBidderGetsAsset`**: some output gives exactly `1` unit of the auctioned token to the
   highest bidder, or to `apSeller` if there were no bids.

### Details that affect the proofs

- `Bid`'s `Eq` instance compares only `bPkh` and `bAmount`. The `bAddr` field of the continuing
  datum is not checked.
- Outputs are matched with `toPubKeyHash (txOutAddress o)`, which reads only the payment
  credential. The staking part of the seller/bidder outputs is unconstrained. The continuing
  output is matched on the full address.
- Outputs are found with `List.find` (some matching output exists). Nothing counts the script
  inputs or reserves an output per input.
- The validator never checks that the spent input holds the NFT, and never reads `txInfoMint`.
- `unsafeFromBuiltinData` decodes the whole `ScriptContext` eagerly, so every `TxInfo` field in a
  test context must be well-formed. For example, `Nothing` for the treasury fields is `Constr 1 []`.

## Reproducing `auction.cbor_hex`

The CBOR is the output of the `quickstart` executable of the `docusaurus-examples` package in the
Plutus repository, at release `1.64.0.0`. It is built with the default Nix dev shell (GHC 9.6).
Different GHC major versions may produce different UPLC, so use that shell.

Prerequisites: [Nix](https://nixos.org/download/) with flakes enabled and the IOG binary caches
configured (see the
[IOGX Nix setup guide](https://github.com/input-output-hk/iogx/blob/main/doc/nix-setup-guide.md)).
Without the caches, Nix builds GHC and the dependencies from source.

```sh
# 1. Check out the Plutus repository at the release used for this example
git clone https://github.com/IntersectMBO/plutus.git
cd plutus
git checkout 1.64.0.0        # commit 61b1eedf082050d89cde8db89d73aae65bc95a65

# 2. Enter the development shell (default = GHC 9.6)
nix develop

# 3. Inside the shell: build and run the quickstart executable.
#    It compiles AuctionValidator.hs with the Plinth plugin (target UPLC 1.1.0),
#    applies the AuctionParams from QuickStart.hs, and writes ./validator.uplc.hex
cabal update
cabal run quickstart

# 4. Copy the result into this repository
cp validator.uplc.hex <path-to>/CardanoLedgerApiBlaster/Tests/Scripts/Auction/auction.cbor_hex
```

The file contains `serialiseCompiledCode` output (flat-encoded UPLC wrapped in a CBOR bytestring),
hex-encoded, with no trailing newline. This is the `single_cbor_hex` format that `Auction.lean`
loads with:

```lean4
#import_uplc auction PlutusV3 single_cbor_hex "Tests/Scripts/Auction/auction.cbor_hex"
```

To check the result, compare it with the committed file (a GHC 9.6.7 build reproduces it byte
for byte):

```sh
$ sha256sum Tests/Scripts/Auction/auction.cbor_hex
98f91eeb5a95036e96969fecbb7db2ad5745847363807447341ee4d965f7f925  Tests/Scripts/Auction/auction.cbor_hex
```

If you change any parameter in `QuickStart.hs`, also update the matching constants in
`Properties.lean` (see [Parameters](#parameters)). The properties refer to the baked-in values.

## Checking the proofs

From the repository root:

```sh
lake build Tests.Scripts.Auction.Properties
```

This file is also part of `make build_tests` (`lake test`). Goals are discharged by
[Blaster](https://github.com/input-output-hk/Lean-blaster) with an SMT solver, so the results
trust Blaster's translation and the solver. `set_option warn.sorry false` hides the resulting
warnings.

## Verification approach

A fully symbolic `ScriptContext` is out of reach: the validator decodes unbounded input and output
lists and a 16-field `TxInfo`. Each scenario therefore fixes a **concrete transaction skeleton**
and keeps only the economically relevant fields symbolic (all are `Integer`). `#prep_uplc`
symbolically runs the CEK machine on the script applied to that context. It produces a residual
predicate (`appliedX.prop`) that the theorems reason about. `succeedsX … := isSuccessful (appliedX.prop …)`
means the script halts, i.e. accepts the transaction.

| Scenario                       | Symbolic arguments                                                | Fixed skeleton |
|--------------------------------|-------------------------------------------------------------------|----------------|
| `appliedNewBid`                | `oldBidAmt newBidAmt outAda refundAda outTok hi`                  | One script input. Datum is `Nothing` if `oldBidAmt ≤ 0`, else the previous bid. Redeemer `NewBid ⟨"cc","dd",newBidAmt⟩`. Outputs: a refund of `refundAda` to the previous bidder (only if `refundAda > 0`), and the continuing output with `outAda` lovelace, `outTok` NFTs and inline datum `Just newBid`. Validity range `(-∞, hi]` |
| `appliedPayout`                | `bidAmt sellerAda assetTok lo`                                    | One script input. Datum is `Nothing` if `bidAmt ≤ 0`, else a bid of `bidAmt`. Redeemer `Payout`. Outputs: `sellerAda` lovelace to the seller (only if `bidAmt > 0`) and `assetTok` NFTs to the highest bidder (or the seller). Validity range `[lo, +∞)` |
| `appliedNewBidAttack`          | as `appliedNewBid`, plus `junkTok mintTok`                        | As `appliedNewBid`, plus `junkTok` units of a foreign token in the continuing output and a `mintTok` mint of it |
| `appliedPayoutDoubleSat`       | as `appliedPayout`                                                | As `appliedPayout`, but **two** auction script inputs are spent |

Properties that vary `Data`/`ByteString` structure (token names, datum shape, redeemer tag,
staking credentials) are outside Blaster's integer reasoning. They are checked on **concrete**
contexts by running the compiled UPLC with `cekExecuteProgram` (budget 50000). `accepts c` means
the script halts on `c`.

## Proven properties

### Satisfiability

| Check                                                        | Meaning |
|--------------------------------------------------------------|---------|
| `#blaster (solve-result: 1) [newBidScriptAlwaysFails]`        | "NewBid always fails" is **refuted**: some bid is accepted |
| `#blaster (solve-result: 1) [payoutScriptAlwaysFails]`        | "Payout always fails" is **refuted**: some payout is accepted |

### `NewBid`

| Theorem                                      | Statement |
|----------------------------------------------|-----------|
| `newBid_success_requires_sufficient_bid`     | First bid (no previous bid, no refund): success → `bakedMinBid ≤ newBidAmt` |
| `newBid_success_requires_bigger_bid`         | success → `oldBidAmt < newBidAmt` |
| `newBid_success_requires_before_deadline`    | success → `hi ≤ bakedEndTime` |
| `newBid_success_requires_output_locks_bid`   | success → `outAda = newBidAmt`: the continuing output locks exactly the bid, no more and no less |
| `newBid_success_requires_single_nft`         | success → `outTok = 1` |
| `newBid_success_positive_bid`                | success → `0 < newBidAmt` |
| `valid_newBid_succeeds`                      | **Converse**: `bakedMinBid ≤ newBidAmt`, `oldBidAmt < newBidAmt`, `hi ≤ bakedEndTime`, `outAda = newBidAmt`, `refundAda = oldBidAmt`, `outTok = 1` → success |
| `newBid_accepts_minimal_increment`           | Outbidding by `+1` lovelace is accepted. This makes front-running and concurrency griefing cheap |

The refund condition is covered only by the converse (`valid_newBid_succeeds`). No theorem states
that a successful bid implies `refundAda = oldBidAmt`.

### `Payout`

| Theorem                                      | Statement |
|----------------------------------------------|-----------|
| `payout_success_requires_after_deadline`     | success → `bakedEndTime ≤ lo` |
| `payout_success_pays_seller_highest_bid`     | success ∧ `0 < bidAmt` → `sellerAda = bidAmt` |
| `payout_success_transfers_asset`             | success → `assetTok = 1` |
| `payout_success_positive_asset`              | success → `0 < assetTok` |
| `payout_success_positive_seller_payment`     | success ∧ `0 < bidAmt` → `0 < sellerAda` |
| `valid_payout_with_bid_succeeds`             | **Converse** (with a bid): `bakedEndTime ≤ lo`, `sellerAda = bidAmt`, `assetTok = 1` → success |
| `valid_payout_no_bid_succeeds`               | **Converse** (no bid): `bakedEndTime ≤ lo`, `assetTok = 1` → success (the NFT returns to the seller) |

### Weaknesses shown by accepting witnesses

| Theorem                          | What is accepted |
|----------------------------------|------------------|
| `newBid_accepts_dust_tokens`     | A valid bid whose continuing output also holds an arbitrary amount of a foreign token. Junk assets can be locked in the auction UTxO |
| `newBid_ignores_minting`         | A valid bid in a transaction that mints/burns an arbitrary amount of an unrelated token |
| `payout_double_satisfaction`     | A payout that spends **two** auction inputs but pays the seller and the winner only once |
| `payout_staked_outputs_accepted` | A payout whose seller/winner outputs carry an attacker-chosen staking credential (concrete evaluation) |

### Structural checks (concrete evaluation)

| Theorem                          | Context | Result |
|----------------------------------|---------|--------|
| `demo_valid_bid_accepted`        | Correct `NewBid` (baseline) | accepted |
| `nb_wrong_token_name_rejected`   | NFT under the right policy but the wrong token name | rejected |
| `nb_wrong_policy_rejected`       | NFT with the right name under the wrong policy | rejected |
| `nb_datum_hash_rejected`         | Continuing output uses a datum hash instead of an inline datum | rejected |
| `nb_datum_missing_rejected`      | Continuing output has no datum | rejected |
| `nb_datum_wrong_bid_rejected`    | Continuing datum records a different bid amount than the redeemer | rejected |
| `nb_other_redeemer_rejected`     | Undefined redeemer constructor (`Constr 2 []`) | rejected |

### Vulnerability audit summary

The header of `Properties.lean` classifies the validator against the
[Anastasia Labs common-vulnerabilities list](https://github.com/Anastasia-Labs/audits#common-vulnerabilities-list),
citing the theorem for each verdict:

- **Defended**: business logic, unauthorized datum modification, other token name, incorrect
  parameterization, other redeemer, locked ADA, script output datum, arbitrary UTxO datum,
  timestamp manipulation, calculations, sign checking.
- **Present**: token dust / UTxO value-size spam, foreign UTxO tokens, locked non-ADA values,
  unconstrained (infinite) minting, double satisfaction, missing UTxO authentication (the spent
  input need not hold the NFT; this is left to the minting policy), lack of staking control.
- **Design / economic** (not a single-validator property): UTxO concurrency DoS, cheap spam and
  front-running (all enabled by the `+1` minimal increment on a single auction UTxO), and min-ADA
  requirements (`bakedMinBid = 100` lovelace is below the ledger's min-ADA).
- **Not applicable**: unbounded datum, multisig, oracle attacks.
