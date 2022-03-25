pragma solidity 0.6.7;

import "geb-treasury-reimbursement/reimbursement/single/IncreasingTreasuryReimbursement.sol";

abstract contract OracleLike {
    function getResultWithValidity() virtual external view returns (uint256, bool);
    function read() virtual external view returns (uint);
}
abstract contract StakingLike {
    function modifyParameters(bytes32, uint256) virtual external;
    function tokensToAuction() virtual view external returns (uint256);
}
abstract contract UniswapV2PairLike {
    function totalSupply() external virtual view returns (uint);
    function getReserves()
        external
        virtual
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );
}

// @notice Adjusts the auction size (in LP tokens) to a set market value, and the initial bid to a dicounted market value.
contract StakingAuctionInitialParameterSetter is IncreasingTreasuryReimbursement {
    // --- Variables ---
    // Delay between updates after which the reward starts to increase
    uint256 public updateDelay;                                                 // [seconds]
    // Last timestamp when the median was updated
    uint256 public lastUpdateTime;                                              // [unix timestamp]
    // Discount in relation to market value of surplus amount to sell, 2000 == 20% discount
    uint256 public bidDiscount;                                                 // [thousand]
    // Value in USD to approximate tokensAmountToSell in staking
    uint256 public tokensToSellTargetValue;                                     // [wad]

    // The protocol token oracle
    OracleLike           public protocolTokenOrcl;
    // The system coin oracle
    OracleLike           public systemCoinOrcl;
    // The ETH oracle
    OracleLike           public ethOrcl;
    // The lender of first resort contract
    StakingLike          public staking;
    // Uniswap pair of LP staked tokens
    UniswapV2PairLike    public uniV2Pair;

    // --- Events ---
    event SetStakingAuctionInitialParameters(uint256 initialBid, uint256 tokensToAuction);

    constructor(
      address protocolTokenOrcl_,
      address systemCoinOrcl_,
      address ethOrcl_,
      address staking_,
      address stakingAncestorToken_,
      address treasury_,
      uint256 updateDelay_,
      uint256 baseUpdateCallerReward_,
      uint256 maxUpdateCallerReward_,
      uint256 perSecondCallerRewardIncrease_,
      uint256 bidDiscount_,
      uint256 tokensToSellTargetValue_
    ) public IncreasingTreasuryReimbursement(treasury_, baseUpdateCallerReward_, maxUpdateCallerReward_, perSecondCallerRewardIncrease_) {
        require(both(
          both(protocolTokenOrcl_ != address(0), systemCoinOrcl_ != address(0)),
          both(staking_ != address(0), ethOrcl_ != address(0))),
          "StakingAuctionInitialParameterSetter/invalid-contract-address");
        require(stakingAncestorToken_ != address(0), "StakingAuctionInitialParameterSetter/invalid-uniswap-pair");
        require(updateDelay_ > 0, "StakingAuctionInitialParameterSetter/null-update-delay");
        require(bidDiscount_ < THOUSAND, "StakingAuctionInitialParameterSetter/invalid-bit-discount");
        require(tokensToSellTargetValue_ > 0, "StakingAuctionInitialParameterSetter/null-tokens-to-sell-target");

        protocolTokenOrcl               = OracleLike(protocolTokenOrcl_);
        systemCoinOrcl                  = OracleLike(systemCoinOrcl_);
        ethOrcl                         = OracleLike(ethOrcl_);
        staking                         = StakingLike(staking_);
        uniV2Pair                       = UniswapV2PairLike(stakingAncestorToken_);

        updateDelay                     = updateDelay_;
        bidDiscount                     = bidDiscount_;
        tokensToSellTargetValue         = tokensToSellTargetValue_;

        emit ModifyParameters(bytes32("protocolTokenOrcl"), protocolTokenOrcl_);
        emit ModifyParameters(bytes32("systemCoinOrcl"), systemCoinOrcl_);
        emit ModifyParameters(bytes32("ethOrcl"), ethOrcl_);
        emit ModifyParameters(bytes32("staking"), staking_);
        emit ModifyParameters(bytes32("bidDiscount"), bidDiscount_);
        emit ModifyParameters(bytes32("tokensToSellTargetValue"), tokensToSellTargetValue_);
        emit ModifyParameters(bytes32("updateDelay"), updateDelay_);
    }

    // --- Boolean Logic ---
    function both(bool x, bool y) internal pure returns (bool z) {
      assembly{ z := and(x, y)}
    }

    // --- Math ---
    uint internal constant HUNDRED  = 100;
    uint internal constant THOUSAND = 10 ** 3;
    function div(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y > 0, "divide-null-y");
        z = x / y;
        require(z <= x);
    }
    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "mul-uint-overflow");
    }
    // implementation from https://github.com/Uniswap/uniswap-lib/commit/99f3f28770640ba1bb1ff460ac7c5292fb8291a0
    // original implementation: https://github.com/abdk-consulting/abdk-libraries-solidity/blob/master/ABDKMath64x64.sol#L687
    function sqrt(uint256 x) internal pure returns (uint) {
        if (x == 0) return 0;
        uint256 xx = x;
        uint256 r = 1;

        if (xx >= 0x100000000000000000000000000000000) {
            xx >>= 128;
            r <<= 64;
        }

        if (xx >= 0x10000000000000000) {
            xx >>= 64;
            r <<= 32;
        }
        if (xx >= 0x100000000) {
            xx >>= 32;
            r <<= 16;
        }
        if (xx >= 0x10000) {
            xx >>= 16;
            r <<= 8;
        }
        if (xx >= 0x100) {
            xx >>= 8;
            r <<= 4;
        }
        if (xx >= 0x10) {
            xx >>= 4;
            r <<= 2;
        }
        if (xx >= 0x8) {
            r <<= 1;
        }

        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1;
        r = (r + x / r) >> 1; // Seven iterations should be enough
        uint256 r1 = x / r;
        return (r < r1 ? r : r1);
    }

    // --- Administration ---
    /*
    * @notice Modify the address of a contract integrated with this setter
    * @param parameter Name of the contract to set a new address for
    * @param addr The new address
    */
    function modifyParameters(bytes32 parameter, address addr) external isAuthorized {
        require(addr != address(0), "StakingAuctionInitialParameterSetter/null-addr");
        if (parameter == "protocolTokenOrcl") protocolTokenOrcl = OracleLike(addr);
        else if (parameter == "systemCoinOrcl") systemCoinOrcl = OracleLike(addr);
        else if (parameter == "ethOrcl") ethOrcl = OracleLike(addr);
        else if (parameter == "staking") staking = StakingLike(addr);
        else if (parameter == "uniV2Pair") uniV2Pair = UniswapV2PairLike(addr);
        else if (parameter == "treasury") {
            require(StabilityFeeTreasuryLike(addr).systemCoin() != address(0), "StakingAuctionInitialParameterSetter/treasury-coin-not-set");
            treasury = StabilityFeeTreasuryLike(addr);
        }
        else revert("StakingAuctionInitialParameterSetter/modify-unrecognized-param");
        emit ModifyParameters(parameter, addr);
    }
    /*
    * @notice Modify a uint256 parameter
    * @param parameter Name of the parameter
    * @param addr The new parameter value
    */
    function modifyParameters(bytes32 parameter, uint256 val) external isAuthorized {
        if (parameter == "baseUpdateCallerReward") {
            require(val <= maxUpdateCallerReward, "StakingAuctionInitialParameterSetter/invalid-base-caller-reward");
            baseUpdateCallerReward = val;
        }
        else if (parameter == "maxUpdateCallerReward") {
            require(val >= baseUpdateCallerReward, "StakingAuctionInitialParameterSetter/invalid-max-reward");
            maxUpdateCallerReward = val;
        }
        else if (parameter == "perSecondCallerRewardIncrease") {
            require(val >= RAY, "StakingAuctionInitialParameterSetter/invalid-reward-increase");
            perSecondCallerRewardIncrease = val;
        }
        else if (parameter == "maxRewardIncreaseDelay") {
            require(val > 0, "StakingAuctionInitialParameterSetter/invalid-max-increase-delay");
            maxRewardIncreaseDelay = val;
        }
        else if (parameter == "updateDelay") {
            require(val > 0, "StakingAuctionInitialParameterSetter/null-update-delay");
            updateDelay = val;
        }
        else if (parameter == "bidDiscount") {
            require(val < THOUSAND, "StakingAuctionInitialParameterSetter/invalid-bid-discount");
            bidDiscount = val;
        }
        else if (parameter == "tokensToSellTargetValue") {
            require(val > 0, "StakingAuctionInitialParameterSetter/null-tokens-to-sell-target");
            tokensToSellTargetValue = val;
        }
        else if (parameter == "lastUpdateTime") {
            require(val > now, "StakingAuctionInitialParameterSetter/invalid-last-update-time");
            lastUpdateTime = val;
        }
        else revert("StakingAuctionInitialParameterSetter/modify-unrecognized-param");
        emit ModifyParameters(parameter, val);
    }

    // --- Setter ---
    /*
    * @notice View function that returns the neew bidSize and lpTokenToAuction
    * @returns bidSize The new, initial staking auction bid
    */
    function getNewStakingAuctionParams() public view returns (uint256 bidSize, uint256 lpTokensToAuction) {
        // Get token price
        uint256 systemCoinPrice = systemCoinOrcl.read();

        // LP token fair value
        uint256 lpTokenFairValue = getLPTokenFairValue();

        // Get amount auctioned
        lpTokensToAuction = div(mul(tokensToSellTargetValue, WAD), lpTokenFairValue);

        // Total USD value for the auction
        uint256 bidPriceUSD = div(mul(lpTokenFairValue, lpTokensToAuction), WAD);
        // Total RAI value for the auction
        uint256 bidSizeRAI = div(mul(bidPriceUSD, WAD), systemCoinPrice);
        // Discounted price
        bidSize = div(mul(bidSizeRAI, THOUSAND - bidDiscount), THOUSAND);
    }

    /// @dev Return the value of the given input as USD per unit (WAD).
    /// @dev Fair LP token pricing originally from Alpha Homora (https://blog.alphafinance.io/fair-lp-token-pricing/)
    function getLPTokenFairValue() internal view returns (uint256) {
        uint px0 = ethOrcl.read();
        uint px1 = protocolTokenOrcl.read();
        require(both(px0 != 0, px1 != 0), "StakingAuctionInitialParameterSetter/invalid_prices");

        uint256 totalSupply = uniV2Pair.totalSupply();
        (uint256 r0, uint256 r1, ) = uniV2Pair.getReserves();

        return mul(2, div(mul(sqrt(mul(r0, r1)), sqrt(mul(px0, px1))), totalSupply));
    }
    /*
    * @notice Set the new debtAuctionBidSize and protocolTokensToSell inside the Staking
    * @param feeReceiver The address that will receive the reward for setting new params
    */
    function updateStakingAuctionParams(address feeReceiver) external {
        // Check delay between calls
        require(either(subtract(now, lastUpdateTime) >= updateDelay, lastUpdateTime == 0), "StakingAuctionInitialParameterSetter/wait-more");
        // Get the caller's reward
        uint256 callerReward = getCallerReward(lastUpdateTime, updateDelay);
        // Store the timestamp of the update
        lastUpdateTime = now;

        // Updates value
        (uint256 newBidSize, uint256 newTokensToAuction) = getNewStakingAuctionParams();
        staking.modifyParameters("systemCoinsToRequest", newBidSize);
        staking.modifyParameters("tokensToAuction", newTokensToAuction);
        emit SetStakingAuctionInitialParameters(newBidSize, newTokensToAuction);

        // Pay the caller for updating the rate
        rewardCaller(feeReceiver, callerReward);
    }
}
