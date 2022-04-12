# Security Tests

The contracts in this folder are the fuzz scripts for the ESM Threshold Setter.

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

### 1. Fuzzing for overflows (FuzzBounds)

In this test we want failures, as they will show us what are the bounds in which the contract operates safely.

Failures flag where overflows happen, and should be compared to expected inputs (to avoid overflows frm causing DoS).

```
Analyzing contract: /geb-debt-auction-param-setter/src/test/fuzz/DebtAuctionInitialParameterSetterFuzz.sol:FuzzBounds
assertion in fuzzParams: passed! 🎉
assertion in rmultiply: failed!💥
  Call sequence:
    rmultiply(28971974183700717198133561576005808833067612272986024813814704589644466466752,4)

assertion in ray: failed!💥
  Call sequence:
    ray(115803291720791786427016273174304739853495027005688396797583203310505)

assertion in bidTargetValue: passed! 🎉
assertion in multiply: failed!💥
  Call sequence:
    multiply(29492270757129847153665399930248771487704,3983848162684860125383528567312755148)

assertion in protocolTokenPremium: passed! 🎉
assertion in baseUpdateCallerReward: passed! 🎉
assertion in maxRewardIncreaseDelay: passed! 🎉
assertion in bidValueTargetInflation: passed! 🎉
assertion in authorizedAccounts: passed! 🎉
assertion in treasuryAllowance: passed! 🎉
assertion in addAuthorization: passed! 🎉
assertion in bidValueInflationDelay: passed! 🎉
assertion in wmultiply: failed!💥
  Call sequence:
    wmultiply(134137546425601903947998217589029642350929471882051626905330564091057,875065459)

assertion in subtract: failed!💥
  Call sequence:
    subtract(0,1)

assertion in perSecondCallerRewardIncrease: passed! 🎉
assertion in rad: failed!💥
  Call sequence:
    rad(115827289193071616379750236709304001777566556776711)

assertion in manualSetDebtAuctionParameters: passed! 🎉
assertion in minProtocolTokenAmountOffered: passed! 🎉
assertion in getPremiumAdjustedProtocolTokenAmount: failed!💥
  Call sequence:
    fuzzParams(1,8247033257577298424841193704764702989946094170792054,115916124072881473777761095198103688197028324753088733884,12000006208066549569160135435157839388525266005044840860)
    getPremiumAdjustedProtocolTokenAmount()

assertion in addition: failed!💥
  Call sequence:
    addition(57066055929598326918927770990027946100759745325363788120377958589210043032603,59133792078265679946471570336627139715876201240534088827674953286981011427078)

assertion in RAY: passed! 🎉
assertion in updateDelay: passed! 🎉
assertion in treasury: passed! 🎉
assertion in modifyParameters: passed! 🎉
assertion in maxUpdateCallerReward: passed! 🎉
assertion in WAD: passed! 🎉
assertion in getRawProtocolTokenAmount: failed!💥
  Call sequence:
    fuzzParams(121609007092568402667892095950252345623017361151644323,4868079165227210083351840175148275587384438468680720,115792463961207694416348047844849418645661382995790851987224,3571268670493592899280273429154942285712648283418006)
    getRawProtocolTokenAmount()

assertion in removeAuthorization: passed! 🎉
assertion in accountingEngine: passed! 🎉
assertion in protocolTokenOrcl: passed! 🎉
assertion in rdivide: failed!💥
  Call sequence:
    rdivide(0,0)

assertion in getNewDebtBid: failed!💥
  Call sequence:
    fuzzParams(72813283120370033648754779918995290776515232154087576523523349,1,115938373829125902908815451242838,1541396)
    getNewDebtBid()

assertion in setDebtAuctionInitialParameters: failed!💥
  Call sequence:
    fuzzParams(1,65420027170655039081360344209791999,115931464698479065099103839094464,13470748741614903125065236219538)
    setDebtAuctionInitialParameters(0x0)

assertion in systemCoinOrcl: passed! 🎉
assertion in lastUpdateTime: passed! 🎉
assertion in bidValueLastInflationUpdateTime: passed! 🎉
assertion in range: passed! 🎉
assertion in rpower: failed!💥
  Call sequence:
    rpower(2,256,1)

assertion in minimum: passed! 🎉
assertion in getCallerReward: passed! 🎉
assertion in wdivide: failed!💥
  Call sequence:
    wdivide(0,0)

assertion in MAX_INFLATION: passed! 🎉
assertion in modifyParameters: passed! 🎉

Seed: -2174556962154849124
```

Most of these failures are well known (math functions), we will focus on the ones specific to this contract:

```
assertion in getRawProtocolTokenAmount: failed!💥
  Call sequence:
    fuzzParams(121609007092568402667892095950252345623017361151644323,4868079165227210083351840175148275587384438468680720,115792463961207694416348047844849418645661382995790851987224,3571268670493592899280273429154942285712648283418006)
    getRawProtocolTokenAmount()
```

Prot price of 12363724300, bid target value of 1157998202302582545322303197744827203045317.72204312158718461. Here the fuzzer also made it's best to reduce prot price, ended up with a large bitTarget, if we balance the two (up to 1mm prot price):

prot price 1,216,090.07...
bid target value 11579982023025825453223031977.4482720304531772204312158718461

```
assertion in getNewDebtBid: failed!💥
  Call sequence:
    fuzzParams(72813283120370033648754779918995290776515232154087576523523349,1,115938373829125902908815451242838,1541396)
    getNewDebtBid()
````

A Bid target price of ~115,804,424,984,310.826176615835225343 alone makes the function revert due to an overflow.

```
assertion in setDebtAuctionInitialParameters: failed!💥
  Call sequence:
    fuzzParams(1,65420027170655039081360344209791999,115931464698479065099103839094464,13470748741614903125065236219538)
    setDebtAuctionInitialParameters(0x0)
```
Will overflow only for Prot price in the trillion range, coin price over 20mm, and bidTargetVlue in the Trillion Range. (tokenPremium set to 1).


#### Conclusion: Bounds are plentyful and should not affect the system in normal conditions.


### Fuzz Properties (Fuzz)

In this case we setup the setter, and check properties.

Here we are not looking for bounds, but instead checking the properties that either should remain constant:

- initial debt auction minted tokens bounds and value
- bid size bounds and value

These properties are verified in between all calls.

```
Analyzing contract: /geb-debt-auction-param-setter/src/test/fuzz/DebtAuctionInitialParameterSetterFuzz.sol:Fuzz
echidna_debt_auction_bid_size_bound: passed! 🎉
echidna_initial_debt_auction_minted_tokens: passed! 🎉
echidna_initial_debt_auction_minted_tokens_bound: passed! 🎉
echidna_debt_auction_bid_size: passed! 🎉

Seed: -6046975607749330481
```

#### Conclusion: No exceptions found

# Results (Multi adjuster)

### 1. Fuzzing for overflows (FuzzBounds)

In this test we want failures, as they will show us what are the bounds in which the contract operates safely.

Failures flag where overflows happen, and should be compared to expected inputs (to avoid overflows frm causing DoS).

```
Analyzing contract: /geb-debt-auction-param-setter/src/test/fuzz/MultiDebtAuctionInitialParameterSetterFuzz.sol:FuzzBounds
assertion in fuzzParams: passed! 🎉
assertion in rmultiply: failed!💥
  Call sequence:
    rmultiply(5296010125604787305934140746494999878303,21880849740152917077239705205574488300)

assertion in ray: failed!💥
  Call sequence:
    ray(115797912551175366478193393678979037007781402703929204061767121710753)

assertion in bidTargetValue: passed! 🎉
assertion in multiply: failed!💥
  Call sequence:
    multiply(1089399801763412435674885034345836875521,107475386134023416963727867041833866201)

assertion in protocolTokenPremium: passed! 🎉
assertion in baseUpdateCallerReward: passed! 🎉
assertion in maxRewardIncreaseDelay: passed! 🎉
assertion in bidValueTargetInflation: passed! 🎉
assertion in authorizedAccounts: passed! 🎉
assertion in treasuryAllowance: passed! 🎉
assertion in addAuthorization: passed! 🎉
assertion in bidValueInflationDelay: passed! 🎉
assertion in wmultiply: failed!💥
  Call sequence:
    wmultiply(7,16544254168651711712566435186726416693509829079054748746914097419191347697398)

assertion in subtract: failed!💥
  Call sequence:
    subtract(0,1)

assertion in perSecondCallerRewardIncrease: passed! 🎉
assertion in rad: failed!💥
  Call sequence:
    rad(115818289091381897901484232977769260915052183141869)

assertion in manualSetDebtAuctionParameters: passed! 🎉
assertion in minProtocolTokenAmountOffered: passed! 🎉
assertion in getPremiumAdjustedProtocolTokenAmount: failed!💥
  Call sequence:
    fuzzParams(3660963262839602722503226867857743843868710785297549611213054,0,115802527983974896064915219886256473869647749243956631638495,0)
    getPremiumAdjustedProtocolTokenAmount()

assertion in addition: failed!💥
  Call sequence:
    addition(104374429682827184457869523262456285365012752389299590342658593504989100083722,11617809195113182995487357847857622516958736373849875398721141501908437364710)

assertion in RAY: passed! 🎉
assertion in updateDelay: passed! 🎉
assertion in treasury: passed! 🎉
assertion in modifyParameters: passed! 🎉
assertion in maxUpdateCallerReward: passed! 🎉
assertion in WAD: passed! 🎉
assertion in getRawProtocolTokenAmount: failed!💥
  Call sequence:
    fuzzParams(1452294779741699629926137698653959757621594728813273001992819,0,115817039747086610340942819791424075048582837760794627982429,0)
    getRawProtocolTokenAmount()

assertion in removeAuthorization: passed! 🎉
assertion in accountingEngine: passed! 🎉
assertion in protocolTokenOrcl: passed! 🎉
assertion in rdivide: failed!💥
  Call sequence:
    rdivide(115809551418878070094764575552516132544241050408014,22353702283118512059136123816222979686985199936590)

assertion in coinName: passed! 🎉
assertion in getNewDebtBid: failed!💥
  Call sequence:
    fuzzParams(0,3505817268555737296503305425,115819928748048086428778966514854,375358237774604334721875609744908)
    getNewDebtBid()

assertion in setDebtAuctionInitialParameters: failed!💥
  Call sequence:
    fuzzParams(4205866790503807498041109316489,1,115889310092999218279056831463799,0)
    setDebtAuctionInitialParameters(0x0)

assertion in systemCoinOrcl: passed! 🎉
assertion in lastUpdateTime: passed! 🎉
assertion in bidValueLastInflationUpdateTime: passed! 🎉
assertion in range: passed! 🎉
assertion in rpower: passed! 🎉
assertion in minimum: passed! 🎉
assertion in getCallerReward: passed! 🎉
assertion in wdivide: failed!💥
  Call sequence:
    wdivide(115847127642723553817780200520440200241013864483392365977193,2673060822101058539030018939169915577281158160720727522619)

assertion in MAX_INFLATION: passed! 🎉
assertion in modifyParameters: passed! 🎉

Seed: 8754037211233656649
```

Most of these failures are well known (math functions), we will focus on the ones specific to this contract:

```
assertion in getRawProtocolTokenAmount: failed!💥
  Call sequence:
    fuzzParams(1452294779741699629926137698653959757621594728813273001992819,0,115817039747086610340942819791424075048582837760794627982429,0)
    getRawProtocolTokenAmount()
```

Prot price of 12363724300, bid target value of 1157998202302582545322303197744827203045317.72204312158718461. Here the fuzzer also made it's best to reduce prot price, ended up with a large bitTarget, if we balance the two (up to 1mm prot price):

prot price 1,216,090.07...
bid target value 11579982023025825453223031977.4482720304531772204312158718461

```
assertion in getNewDebtBid: failed!💥
  Call sequence:
    fuzzParams(0,3505817268555737296503305425,115819928748048086428778966514854,375358237774604334721875609744908)
    getNewDebtBid()
````

A Bid target price of ~115,804,424,984,310.826176615835225343 alone makes the function revert due to an overflow.

```
assertion in setDebtAuctionInitialParameters: failed!💥
  Call sequence:
    fuzzParams(4205866790503807498041109316489,1,115889310092999218279056831463799,0)
    setDebtAuctionInitialParameters(0x0)
```
Will overflow only for Prot price in the trillion range, coin price over 20mm, and bidTargetVlue in the Trillion Range. (tokenPremium set to 1).


#### Conclusion: Bounds are plentyful and should not affect the system in normal conditions.


### Fuzz Properties (Fuzz)

In this case we setup the setter, and check properties.

Here we are not looking for bounds, but instead checking the properties that either should remain constant:

- initial debt auction minted tokens bounds and value
- bid size bounds and value

These properties are verified in between all calls.

```
Analyzing contract: /geb-debt-auction-param-setter/src/test/fuzz/MultiDebtAuctionInitialParameterSetterFuzz.sol:Fuzz
echidna_debt_auction_bid_size_bound: passed! 🎉
echidna_initial_debt_auction_minted_tokens: passed! 🎉
echidna_initial_debt_auction_minted_tokens_bound: passed! 🎉
echidna_debt_auction_bid_size: passed! 🎉

Seed: 1241139309574273542
```

#### Conclusion: No exceptions found
