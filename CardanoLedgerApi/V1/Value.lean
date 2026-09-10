import CardanoLedgerApi.IsData.Class
import PlutusCore

namespace CardanoLedgerApi.V1.Value
open IsData.Class
open PlutusCore.Data (Data)
open PlutusCore.ByteString (ByteString)
open PlutusCore.Integer (Integer)

abbrev CurrencySymbol := ByteString
abbrev TokenName := ByteString

/-- The currency symbol for `Ada` -/
def adaSymbol : CurrencySymbol := ""

/-- The token name for `Ada` -/
def adaToken : TokenName := ""

/-- The 'Value' type is keep at the builtin level and is assumed to satisfy:
     - predicate validTxOutValue when is specified in a TxOut
     - predicate validMintValue when is specified in txInfoMint
-/
abbrev Value := List (Data × Data)

/-- BEq instance for Value -/
instance : BEq Value := ⟨List.beq⟩

/-- DecidableEq instance for Value -/
instance : DecidableEq Value := inferInstanceAs (DecidableEq Value)

/-! LawfulBEq instance for Value -/
instance : LawfulBEq Value := inferInstanceAs (LawfulBEq Value)

/-- IsData instance for ScriptHash -/
instance : IsData Value where
  toData v := Data.Map v
  fromData
  | Data.Map v => some v
  | _ => none


/-! Helpers -/

/-- Construct a null `Value` with nothing in it -/
def null : Value := []

/-- Return a `Value` containing only the given quantity for the
    given currency symbol `cs` and token name `n`
-/
def singleton (cs : CurrencySymbol) (tn : TokenName) (n : Integer) : Value :=
  [(Data.B cs, Data.Map [(Data.B tn, Data.I n)])]

/-- return a `Value` containing only the given quantity of Lovelace -/
def lovelaceValue (n : Integer) : Value :=
  singleton adaSymbol adaToken n


/-- Return the quantity of Lovelace in Value `v`.
    Assume that value satisfies either `validTxOutValue` or `validMintValue`.
-/
def lovelaceOf (v : Value) : Integer :=
  match v with
  | (Data.B "", Data.Map [(Data.B "", Data.I n)]) :: _ => n
  | _ => 0

/-- Return a Value containing only Ada, if any.
    Assume that value satisfies either `validTxOutValue` or `validMintValue`.
-/
def onlyLovelace (v : Value) : Value :=
  match v with
  | p@(Data.B "", Data.Map [(Data.B "", Data.I _)]) :: _ => [p]
  | _ => null

/-- Return a Value excluding Ada.
    Assume that value satisfies either `validTxOutValue` or `validMintValue`.
-/
def withoutLovelace (v : Value) : Value :=
  match v with
  | (Data.B "", Data.Map [(Data.B "", Data.I _)]) :: rest => rest
  | _ => v

/-- Return the quantity for the given currency symbol `cs` and the
    given token name `tn` in Value `v`.
-/
def valueOf (cs : CurrencySymbol) (tn : TokenName) (v : Value) : Integer :=
  let rec find_token (tns : List (Data × Data)) : Integer :=
    match tns with
    | [] => 0
    | (r_tn, r_price) :: xs =>
        if Data.B tn = r_tn then
           match r_price with
           | Data.I price => price
           | _ => 0
        else find_token xs
  let rec visit (v : Value) : Integer :=
    match v with
    | [] => 0
    | (r_cs, Data.Map tokens) :: xs =>
         if Data.B cs == r_cs
         then find_token tokens
         else visit xs
    | _ => 0
  visit v


/-- Add a (positive or negative) quantity of a single token to Value `v`.
    If the token is already present in `v` the quantity is incremented/decremented accordingly.
    The token is removed from `v` if the resulting quantity is zero.
    Assume that value satisfies either `validTxOutValue` or `validMintValue`.
-/
def add (cs : CurrencySymbol) (tn : TokenName) (n : Integer) (v : Value) : Value :=
  let rec tn_visit (tns : List (Data × Data)) : List (Data × Data) :=
    match tns with
    | [] => [(Data.B tn, Data.I n)]
    | p@(Data.B tn', Data.I n') :: xs =>
         if tn < tn' then (Data.B tn, Data.I n) :: tns
         else if tn == tn' then
           let qty := n' + n
           if qty == 0 then xs
           else (Data.B tn, Data.I qty) :: xs
         else p :: (tn_visit xs)
    | _ => tns -- unreachable, i.e., token map is well-formed
  let rec cs_visit (v : Value) : Value :=
   match v with
   | [] => singleton cs tn n
   | p@(Data.B cs', Data.Map tokens) :: xs =>
       if cs < cs' then (Data.B cs, Data.Map [(Data.B tn, Data.I n)]) :: v
       else if cs == cs' then (Data.B cs', Data.Map (tn_visit tokens)) :: xs
       else p :: cs_visit xs
   | _ => v -- unreachable case, i.e., Value is well-formed
  if n == 0 then v
  else cs_visit v

/-- Combine two `Value` together
    Assume that the `Value` instances satisfy either `validTxOutValue` or `validMintValue`.
-/
def merge (v1 : Value) (v2 : Value) : Value :=
 let rec tn_visit (left : List (Data × Data)) (right : List (Data × Data)) : List (Data × Data) :=
   match left, right with
   | [], _ => right
   | _, [] => left
   | left'@(p1@(Data.B tn, Data.I n) :: xs), right'@(p2@(Data.B tn', Data.I n') :: xs') =>
        if tn < tn' then p1 :: tn_visit xs right'
        else if tn == tn' then
          let qty := n + n'
          if qty == 0 then tn_visit xs xs'
          else (Data.B tn, Data.I qty) :: tn_visit xs xs'
        else p2 :: tn_visit left' xs'
   | _, _ => right -- assume token map is well-formed
   termination_by left.length + right.length
 let rec cs_visit (left : Value) (right : Value) : Value :=
   match left, right with
   | [], _ => right
   | _, [] => left
   | left'@(p1@(Data.B cs, Data.Map tokens) :: xs), right'@(p2@(Data.B cs', Data.Map tokens') :: xs') =>
        if cs < cs' then p1 :: cs_visit xs right'
        else if cs == cs' then
           match tn_visit tokens tokens' with
           | [] => cs_visit xs xs'
           | new_tokens => (Data.B cs, Data.Map new_tokens) :: cs_visit xs xs'
        else p2 :: cs_visit left' xs'
   | _, _ => right -- assume Value is well-formed
   termination_by left.length + right.length
 cs_visit v1 v2


/-- Convert the schema-typed rendering of a `Value` into the `Data`-keyed one
the functions here take.

A CIP-57 blueprint describes a `Value` as a map of currency symbol to a map of
token name to quantity, so code generated from a blueprint types that field as
`List (CurrencySymbol × List (TokenName × Integer))` — the same information as a
`Value`, in a different Lean type. A property that mentions both a blueprint
type and a ledger function needs to cross between them, and this is the
crossing. Total and injective: every typed map denotes exactly one `Value`.

Does not sort or normalise, so the caller keeps the obligation every other
function here places on a `Value`: `validTxOutValue` or `validMintValue`. This
matters downstream — `merge` walks both arguments assuming their currency
symbols and token names are ordered, and falls through to its last branch when
they are not. A typed map whose keys are out of order therefore crosses over
unchanged and merges wrongly, rather than being silently repaired here. -/
def ofTypedValue (v : List (CurrencySymbol × List (TokenName × Integer))) : Value :=
  v.map fun entry =>
    (Data.B entry.1, Data.Map (entry.2.map fun token => (Data.B token.1, Data.I token.2)))

/-! Comparison -/

/-- The `(CurrencySymbol, TokenName)` pairs a `Value` mentions.

Duplicates are possible in a malformed `Value`; every consumer here folds over
the list with a predicate, so a repeated key costs a repeated check and nothing
else. -/
def keys (v : Value) : List (CurrencySymbol × TokenName) :=
  v.flatMap fun entry =>
    match entry with
    | (Data.B cs, Data.Map tokens) =>
        tokens.filterMap fun token =>
          match token with
          | (Data.B tn, _) => some (cs, tn)
          | _ => none
    | _ => []

/-- Compare two `Value`s pointwise, treating an absent token as a quantity of
zero. The counterpart of `PlutusLedgerApi.V1.Value.checkBinRel`.

Absence and zero are the same quantity in a `Value`, so a token present in one
side and missing from the other is compared against `0` rather than skipped.
Comparing two empty values is vacuously true, as it is in the ledger. -/
def checkBinRel (f : Integer → Integer → Bool) (l : Value) (r : Value) : Bool :=
  (keys l ++ keys r).all fun k => f (valueOf k.1 k.2 l) (valueOf k.1 k.2 r)

/-- Is every quantity in `l` at least the corresponding quantity in `r`?
The counterpart of `PlutusLedgerApi.V1.Value.geq`. -/
def geq (l : Value) (r : Value) : Bool := checkBinRel (· >= ·) l r

/-- Is every quantity in `l` at most the corresponding quantity in `r`?
The counterpart of `PlutusLedgerApi.V1.Value.leq`. -/
def leq (l : Value) (r : Value) : Bool := checkBinRel (· <= ·) l r

/-! Predicates -/

/-- Check if the currency symbol `cs` is present in Value `v`. -/
def hasCurrencySymbol (cs : CurrencySymbol) (v : Value) : Bool :=
 match v with
 | [] => false
 | x :: xs => Data.B cs == x.1 || hasCurrencySymbol cs xs

/-- Check if the currency symbol `cs` is present in Value `v`.
    Other assets (other than Ada) are not tolerated.
    Assume that value satisfies either `validTxOutValue` or `validMintValue`.
-/
def hasOnlyCurrencySymbol (cs : CurrencySymbol) (v : Value) : Bool :=
 match v with
 | _ada :: [(Data.B cs', _)] => cs' == cs
 | _ => false

/-- Check if Value only contains non-zero Ada. -/
def hasOnlyNonZeroAda (v : Value) : Bool :=
  match v with
  | [ (Data.B "", Data.Map [(Data.B "", Data.I n)]) ] => n > 0
  | _ => false

end CardanoLedgerApi.V1.Value
