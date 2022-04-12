# Security Tests

The contracts in this folder are the fuzz scripts for the Staking Auciton Parameter Setter.

To run the fuzzer, set up Echidna (https://github.com/crytic/echidna) on your machine.

Then run
```
echidna-test src/test/fuzz/<name of file>.sol --contract <Name of contract> --config src/test/fuzz/echidna.yaml
```

Configs are in this folder (echidna.yaml).

The contracts in this folder are modified versions of the originals in the _src_ folder. They have assertions added to test for invariants, visibility of functions modified. Running the Fuzz against modified versions without the assertions is still possible, general properties on the Fuzz contract can be executed against unmodified contracts.

Tests should be run one at a time because they interfere with each other.

For all contracts being fuzzed, we tested the following:

1. Writing assertions and/or turning "requires" into "asserts" within the smart contract itself. This will cause echidna to fail fuzzing, and upon failures echidna finds the lowest value that causes the assertion to fail. This is useful to test bounds of functions (i.e.: modifying safeMath functions to assertions will cause echidna to fail on overflows, giving insight on the bounds acceptable). This is useful to find out when these functions revert. Although reverting will not impact the contract's state, it could cause a denial of service (or the contract not updating state when necessary and getting stuck). We check the found bounds against the expected usage of the system.
2. For contracts that have state, we also force the contract into common states and fuzz common actions.

Echidna will generate random values and call all functions failing either for violated assertions, or for properties (functions starting with echidna_) that return false. Sequence of calls is limited by seqLen in the config file. Calls are also spaced over time (both block number and timestamp) in random ways. Once the fuzzer finds a new execution path, it will explore it by trying execution with values close to the ones that opened the new path.

# Results (Single adjuster)

### Fuzz Properties (Fuzz)

In this case we setup the setter, and check properties.

On all interactions with the setter the following properties are tested

- initial staking auction minted tokens value
- bid size value
- checking the LP Fair value calculation

The contract will allow the fuzzer to set different inbalances in the pool (staritng from the correct balance in the day of testing, the balance agrees with the oracle prices), and then will test if the outputs are correct and if the correct changes to the Staking contract state were made.

The properties are verified in between all calls.

```
Analyzing contract: /Users/fabio/Documents/reflexer/geb-surplus-auction-initial-param-setter/src/test/fuzz/StakingAuctionInitialParameterSetterFuzz.sol:Fuzz
echidna_staking_auction_minted_tokens: passed! 🎉
echidna_staking_auction_bid_size: passed! 🎉
echidna_imbalance: passed! 🎉
```

#### Conclusion: No exceptions found

Note: The Alpha Homora formula for fair LP pricing is more resistant to pool imbalances, but it is also prone to oracle manipulations (flash loans), unlike what they stated in the article. In this case it does not pose risk to the system (as it is just defining an initial bid for an auction), but if used as a main price source within systems it could lead vulnerabilities. In case of Alpha they will not allow a call from a contract, effectively mitigating this risk.