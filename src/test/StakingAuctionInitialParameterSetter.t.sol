// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.7;

import "ds-test/test.sol";
import "ds-token/token.sol";

import "./mock/MockTreasury.sol";
import "../StakingAuctionInitialParameterSetter.sol";

abstract contract Hevm {
    function warp(uint256) virtual public;
}

// using data from FLX/ETH pair, 24/03/2022
// current prices are ETH 3093, FLX 114
contract UniPairMock {
    uint public totalSupply = 12774337082263451061941;
    uint public totalPoolValue = 17367888 * 10**18; // from uniswap.info, brought in for sanity checks
    uint112 flxReserves = 76097123002527008280641;
    uint112 ethReserves = 2803747969601653605423;

    function getReserves() external returns (uint112, uint112, uint32) {
        return (flxReserves, ethReserves, uint32(now));
    }

    function setReserves(uint112 flx, uint112 eth) public {
        flxReserves = flx;
        ethReserves = eth;
    }
}

contract StakingMock {
    uint public tokensToAuction = 100 * 10**18;
    uint public systemCoinsToRequest = 16000 * 10**18;

    function modifyParameters(bytes32 param, uint val) external {
        if (param == "systemCoinsToRequest") systemCoinsToRequest = val;
        if (param == "tokensToAuction") tokensToAuction = val;
    }

}

contract Feed {
    uint256 public priceFeedValue;
    bool public hasValidValue;
    constructor(uint256 initPrice, bool initHas) public {
        priceFeedValue = uint(initPrice);
        hasValidValue = initHas;
    }
    function set_val(uint newPrice) external {
        priceFeedValue = newPrice;
    }
    function set_has(bool newHas) external {
        hasValidValue = newHas;
    }
    function getResultWithValidity() external returns (uint256, bool) {
        return (priceFeedValue, hasValidValue);
    }

    function read() external returns (uint) {
        require(hasValidValue);
        return priceFeedValue;
    }
}

contract StakingAuctionInitialParameterSetterTest is DSTest {
    Hevm hevm;

    DSToken systemCoin;

    Feed sysCoinFeed;
    Feed protocolTokenFeed;
    Feed ethFeed;

    StakingMock staking;
    UniPairMock uniV2Pair;
    MockTreasury treasury;

    StakingAuctionInitialParameterSetter setter;

    uint256 periodSize = 3600;
    uint256 baseUpdateCallerReward = 5E18;
    uint256 maxUpdateCallerReward  = 10E18;
    uint256 perSecondCallerRewardIncrease = 1000192559420674483977255848; // 100% per hour
    uint256 maxRewardIncreaseDelay = 3 hours;

    uint RAY = 10 ** 27;
    uint WAD = 10 ** 18;

    uint bidDiscount = 200; // 20%
    uint targetAuctionValue = 50000 * WAD; // 50k

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        systemCoin = new DSToken("RAI", "RAI");
        treasury = new MockTreasury(address(systemCoin));
        staking = new StakingMock();
        uniV2Pair = new UniPairMock();

        sysCoinFeed = new Feed(3 ether, true);
        protocolTokenFeed = new Feed(114 ether, true);
        ethFeed = new Feed(3093 ether, true);

        setter = new StakingAuctionInitialParameterSetter(
            address(protocolTokenFeed),
            address(sysCoinFeed),
            address(ethFeed),
            address(staking),
            address(uniV2Pair),
            address(treasury),
            periodSize,
            baseUpdateCallerReward,
            maxUpdateCallerReward,
            perSecondCallerRewardIncrease,
            bidDiscount,
            targetAuctionValue
        );

        systemCoin.mint(address(treasury), 4e6 * WAD);

        treasury.setTotalAllowance(address(setter), uint(-1));
        treasury.setPerBlockAllowance(address(setter), 10E45);
    }

    function test_setup() public {
        assertEq(setter.authorizedAccounts(address(this)), 1);

        assertTrue(address(setter.protocolTokenOrcl()) == address(protocolTokenFeed));
        assertTrue(address(setter.systemCoinOrcl()) == address(sysCoinFeed));
        assertTrue(address(setter.ethOrcl()) == address(ethFeed));
        assertTrue(address(setter.staking()) == address(staking));
        assertTrue(address(setter.uniV2Pair()) == address(uniV2Pair));
        assertTrue(address(setter.treasury()) == address(treasury));

        assertEq(setter.updateDelay(), periodSize);
        assertEq(setter.baseUpdateCallerReward(), baseUpdateCallerReward);
        assertEq(setter.maxUpdateCallerReward(), maxUpdateCallerReward);

        assertEq(setter.bidDiscount(), bidDiscount);
    }

    function testFail_setup_invalid_prot_feed() public {
        setter = new StakingAuctionInitialParameterSetter(
            address(0),
            address(sysCoinFeed),
            address(ethFeed),
            address(staking),
            address(uniV2Pair),
            address(treasury),
            periodSize,
            baseUpdateCallerReward,
            maxUpdateCallerReward,
            perSecondCallerRewardIncrease,
            bidDiscount,
            targetAuctionValue
        );
    }

    function testFail_setup_invalid_coin_feed() public {
        setter = new StakingAuctionInitialParameterSetter(
            address(protocolTokenFeed),
            address(0),
            address(ethFeed),
            address(staking),
            address(uniV2Pair),
            address(treasury),
            periodSize,
            baseUpdateCallerReward,
            maxUpdateCallerReward,
            perSecondCallerRewardIncrease,
            bidDiscount,
            targetAuctionValue
        );
    }

    function testFail_setup_invalid_eth_feed() public {
        setter = new StakingAuctionInitialParameterSetter(
            address(protocolTokenFeed),
            address(sysCoinFeed),
            address(0),
            address(staking),
            address(uniV2Pair),
            address(treasury),
            periodSize,
            baseUpdateCallerReward,
            maxUpdateCallerReward,
            perSecondCallerRewardIncrease,
            bidDiscount,
            targetAuctionValue
        );
    }

    function testFail_setup_invalid_staking() public {
        setter = new StakingAuctionInitialParameterSetter(
            address(protocolTokenFeed),
            address(sysCoinFeed),
            address(ethFeed),
            address(0),
            address(uniV2Pair),
            address(treasury),
            periodSize,
            baseUpdateCallerReward,
            maxUpdateCallerReward,
            perSecondCallerRewardIncrease,
            bidDiscount,
            targetAuctionValue
        );
    }

    function testFail_setup_invalid_uni_pair() public {
        setter = new StakingAuctionInitialParameterSetter(
            address(protocolTokenFeed),
            address(sysCoinFeed),
            address(ethFeed),
            address(staking),
            address(0),
            address(treasury),
            periodSize,
            baseUpdateCallerReward,
            maxUpdateCallerReward,
            perSecondCallerRewardIncrease,
            bidDiscount,
            targetAuctionValue
        );
    }

    function testFail_setup_invalid_update_delay() public {
        setter = new StakingAuctionInitialParameterSetter(
            address(protocolTokenFeed),
            address(sysCoinFeed),
            address(ethFeed),
            address(staking),
            address(uniV2Pair),
            address(treasury),
            0,
            baseUpdateCallerReward,
            maxUpdateCallerReward,
            perSecondCallerRewardIncrease,
            bidDiscount,
            targetAuctionValue
        );
    }

    function testFail_setup_invalid_discount() public {
        setter = new StakingAuctionInitialParameterSetter(
            address(protocolTokenFeed),
            address(sysCoinFeed),
            address(ethFeed),
            address(staking),
            address(uniV2Pair),
            address(treasury),
            periodSize,
            baseUpdateCallerReward,
            maxUpdateCallerReward,
            perSecondCallerRewardIncrease,
            1000,
            targetAuctionValue
        );
    }

    function testFail_setup_invalid_target_auction_value() public {
        setter = new StakingAuctionInitialParameterSetter(
            address(protocolTokenFeed),
            address(sysCoinFeed),
            address(ethFeed),
            address(staking),
            address(uniV2Pair),
            address(treasury),
            periodSize,
            baseUpdateCallerReward,
            maxUpdateCallerReward,
            perSecondCallerRewardIncrease,
            bidDiscount,
            0
        );
    }

    function test_modify_parameters_address() public {
        setter.modifyParameters("protocolTokenOrcl", address(0x1));
        assertEq(address(setter.protocolTokenOrcl()), address(0x1));

        setter.modifyParameters("systemCoinOrcl", address(0x2));
        assertEq(address(setter.systemCoinOrcl()), address(0x2));

        setter.modifyParameters("ethOrcl", address(0x3));
        assertEq(address(setter.ethOrcl()), address(0x3));

        setter.modifyParameters("staking", address(0x4));
        assertEq(address(setter.staking()), address(0x4));

        setter.modifyParameters("uniV2Pair", address(0x5));
        assertEq(address(setter.uniV2Pair()), address(0x5));

        treasury = new MockTreasury(address(systemCoin));

        setter.modifyParameters("treasury", address(treasury));
        assertEq(address(setter.treasury()), address(treasury));
    }

    function testFail_modify_parameters_address_invalid() public {
        setter.modifyParameters("protocolTokenOrcl", address(0));
    }

    function testFail_modify_parameters_address_unauthed() public {
        setter.removeAuthorization(address(this));
        setter.modifyParameters("protocolTokenOrcl", address(2));
    }

    function test_modify_parameters_uint() public {
        setter.modifyParameters("baseUpdateCallerReward", 1);
        assertEq(setter.baseUpdateCallerReward(), 1);

        setter.modifyParameters("maxUpdateCallerReward", 10);
        assertEq(setter.maxUpdateCallerReward(), 10);

        setter.modifyParameters("perSecondCallerRewardIncrease", RAY);
        assertEq(setter.perSecondCallerRewardIncrease(), RAY);

        setter.modifyParameters("maxRewardIncreaseDelay", 1 hours);
        assertEq(setter.maxRewardIncreaseDelay(), 1 hours);

        setter.modifyParameters("updateDelay", 2);
        assertEq(setter.updateDelay(), 2);

        setter.modifyParameters("bidDiscount", 100);
        assertEq(setter.bidDiscount(), 100);

        setter.modifyParameters("tokensToSellTargetValue", 1 ether);
        assertEq(setter.tokensToSellTargetValue(), 1 ether);

        setter.modifyParameters("lastUpdateTime", now + 1 hours);
        assertEq(setter.lastUpdateTime(), now + 1 hours);
    }

    function testFail_modify_parameters_uint_invalid_base_reward() public {
        setter.modifyParameters("baseUpdateCallerReward", setter.maxUpdateCallerReward() + 1);
    }

    function testFail_modify_parameters_uint_invalid_max_reward() public {
        setter.modifyParameters("maxUpdateCallerReward", setter.baseUpdateCallerReward() - 1);
    }

    function testFail_modify_parameters_uint_invalid_per_second_reaward_increase() public {
        setter.modifyParameters("perSecondCallerRewardIncrease", RAY - 1);
    }

    function testFail_modify_parameters_uint_invalid_max_reward_increase_delay() public {
        setter.modifyParameters("maxRewardIncreaseDelay", 0);
    }

    function testFail_modify_parameters_uint_invalid_update_delay() public {
        setter.modifyParameters("updateDelay", 0);
    }

    function testFail_modify_parameters_uint_invalid_bid_discount() public {
        setter.modifyParameters("bidDiscount", 1000);
    }

    function testFail_modify_parameters_uint_invalid_tokens_to_sell_target() public {
        setter.modifyParameters("tokensToSellTargetValue", 0);
    }

    function testFail_modify_parameters_uint_invalid_last_update_time() public {
        setter.modifyParameters("lastUpdateTime", 0);
    }

    function testFail_modify_parameters_uint_unauthed() public {
        setter.removeAuthorization(address(this));
        setter.modifyParameters("lastUpdateTime", now + 1 hours);
    }

    function test_getLPTokenFairValue() public {
        uint actualPoolValue = (uniV2Pair.totalPoolValue() * WAD) / uniV2Pair.totalSupply();
        uint onePercent = actualPoolValue / 100;
        assertTrue(
            setter.getLPTokenFairValue() > actualPoolValue - onePercent &&
            setter.getLPTokenFairValue() < actualPoolValue + onePercent
        );
    }

    function test_getLPTokenFairValue_inbalanced() public {
        uint actualPoolValue = (uniV2Pair.totalPoolValue() * WAD) / uniV2Pair.totalSupply();
        uint tenPercent = actualPoolValue / 10;

        // reducing flx amount in 15%
        (uint112 r0, uint112 r1, ) = uniV2Pair.getReserves();
        uniV2Pair.setReserves(r0 / 100 * 85, r1);

        assertTrue(
            setter.getLPTokenFairValue() > actualPoolValue - tenPercent &&
            setter.getLPTokenFairValue() < actualPoolValue + tenPercent
        );
    }

    function testFail_getLPTokenFairValue_null_eth_price() public {
        ethFeed.set_val(0);
        setter.getLPTokenFairValue();
    }

    function testFail_getLPTokenFairValue_invalid_eth_price() public {
        ethFeed.set_has(false);
        setter.getLPTokenFairValue();
    }

    function testFail_getLPTokenFairValue_null_flx_price() public {
        protocolTokenFeed.set_val(0);
        setter.getLPTokenFairValue();
    }

    function testFail_getLPTokenFairValue_invalid_flx_price() public {
        protocolTokenFeed.set_has(false);
        setter.getLPTokenFairValue();
    }

    function test_getNewStakingAuctionParams() public {
        (uint256 bidSize, uint256 tokensToAuction) = setter.getNewStakingAuctionParams();

        uint256 lpTokenFairValue = setter.getLPTokenFairValue();

        assertEq(tokensToAuction, 50000 ether * WAD / lpTokenFairValue);
        assertEq(bidSize, (lpTokenFairValue * tokensToAuction / sysCoinFeed.read()) * (1000 - bidDiscount) / 1000);
    }

    function testFail_getNewStakingAuctionParams_null_coin_price() public {
        sysCoinFeed.set_val(0);
        (uint256 bidSize, uint256 tokensToAuction) = setter.getNewStakingAuctionParams();
    }

    function testFail_getNewStakingAuctionParams_invalid_coin_price() public {
        sysCoinFeed.set_has(false);
        (uint256 bidSize, uint256 tokensToAuction) = setter.getNewStakingAuctionParams();
    }

    function test_updateStakingAuctionParams() public {
        (uint256 bidSize, uint256 tokensToAuction) = setter.getNewStakingAuctionParams(); // tested above

        setter.updateStakingAuctionParams(address(0xabc));
        assertEq(setter.lastUpdateTime(), now);
        assertEq(staking.tokensToAuction(), tokensToAuction);
        assertEq(staking.systemCoinsToRequest(), bidSize);
        assertGt(treasury.systemCoin().balanceOf(address(0xabc)), 0);
    }

    function testFail_updateStakingAuctionParams_before_delay() public {
        setter.updateStakingAuctionParams(address(0xabc));
        assertEq(setter.lastUpdateTime(), now);

        hevm.warp(now + setter.updateDelay() - 1);
        setter.updateStakingAuctionParams(address(0xabc));
    }
}
