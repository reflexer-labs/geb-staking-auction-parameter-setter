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

    function getReserves() external returns (uint112, uint112, uint32) {
        return (uint112(76097123002527008280641), uint112(2803747969601653605423), uint32(now));
    }
}

contract StakingMock {
    uint public tokensToAuction = 100 * 10**18;
    uint public systemCoinsToRequest = 16000 * 10**18;

    function modifyParameters(bytes32 param, uint val) external {
        if (param == "systemCoinsToRequest") systemCoinsToRequest = val;
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

    function test_getNewStakingAuctionBid() public {
        (uint256 bidSize, uint256 tokensToAuction) = setter.getNewStakingAuctionParams();
        emit log_named_uint("tokensToAuction", tokensToAuction);
        emit log_named_uint("bidSize        ", bidSize);
        emit log_named_uint("actual         ", (uniV2Pair.totalPoolValue() * 10**18) / uniV2Pair.totalSupply());
        emit log_named_uint("bidPrice       ", (bidSize* 3.1 ether / WAD) / 100 );
        // emit log_named_uint("fairTokenValue ", setter.getLPTokenFairValue());
        // revert();
    }
}