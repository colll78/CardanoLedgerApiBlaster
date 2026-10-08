import Lake
open Lake DSL

package CardanoLedgerApiFacts where
  moreLeanArgs := #["--threads=2", "-s65536"]

require Blaster from git "https://github.com/colll78/Lean-blaster" @ "7f7c0248d64a7f52547bf498104f5775cdfb9fbb"
require PlutusCore from git "https://github.com/colll78/PlutusCoreBlaster" @ "08111ad9556efecd8ffe5d8929636e7bbeab3a54"
require PlutusCoreFacts from git "https://github.com/colll78/PlutusCoreBlaster" @ "08111ad9556efecd8ffe5d8929636e7bbeab3a54" / "proofs"
require CardanoLedgerApi from ".."

@[default_target]
lean_lib CardanoLedgerApiFacts

@[test_driver]
lean_lib FactTests
