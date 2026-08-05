import Lake
open Lake DSL

package «CardanoLedgerApi» where
  -- add package configuration options here
  moreGlobalServerArgs := #["--threads=4"]
  moreLeanArgs := #["--threads=4"]
  -- Investigation branch (#138 telemetry): local paths for fast iteration.
  -- Originals: PlutusCore @ git main; Blaster @ git beta-lambda-cache-optimization
  require PlutusCore from "/Users/romainsoulat/PlutusCoreBlaster"
  require Blaster from "/Users/romainsoulat/Lean-blaster"

@[default_target]
lean_lib «CardanoLedgerApi» where
   -- add library configuration options here

@[test_driver]
lean_lib «Tests» where
  -- add library configuration options here
