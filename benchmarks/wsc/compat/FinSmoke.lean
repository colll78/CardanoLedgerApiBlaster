import Blaster

/-! Exercise datatypes containing finite types and guard against an unbounded-Int
encoding. The three implications have satisfiable hypotheses in Lean, so none
may be proved valid by translating those hypotheses as false. -/

#blaster (timeout: 10) (solve-result: 1)
  [∀ (x y : Option (Fin 2)), x = y]

#blaster (timeout: 10) (solve-result: 1)
  [∀ (x y : Option (BitVec 2)), x = y]

#blaster (timeout: 10) (solve-result: 1)
  [∀ (x y : Option Char), x = y]

#blaster (timeout: 10) (solve-result: 1)
  [(∀ x y z : Fin 2, x = y ∨ y = z ∨ x = z) → False]

#blaster (timeout: 10) (solve-result: 1)
  [(∀ x : Fin 0, x ≠ x) → False]

#blaster (timeout: 10) (solve-result: 1)
  [(∀ x y z : BitVec 1, x = y ∨ y = z ∨ x = z) → False]
