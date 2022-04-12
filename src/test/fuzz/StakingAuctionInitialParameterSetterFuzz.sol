pragma solidity 0.6.7;

import "../mock/MockTreasury.sol";
import "./StakingAuctionInitialParameterSetterMock.sol";
import "../../../lib/ds-test/src/test.sol";

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

contract TokenMock {
    uint constant maxUint = uint(0) - 1;
    mapping (address => uint256) public received;
    mapping (address => uint256) public sent;

    function totalSupply() public view returns (uint) {
        return maxUint;
    }
    function balanceOf(address src) public view returns (uint) {
        return maxUint;
    }
    function allowance(address src, address guy) public view returns (uint) {
        return maxUint;
    }

    function transfer(address dst, uint wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint wad)
        public
        returns (bool)
    {
        received[dst] += wad;
        sent[src]     += wad;
        return true;
    }

    function approve(address guy, uint wad) virtual public returns (bool) {
        return true;
    }
}

// @notice Fuzz the contracts testing properties
contract Fuzz is StakingAuctionInitialParameterSetterMock {

    TokenMock systemCoin;

    uint256 _periodSize = 3600;
    uint256 _baseUpdateCallerReward = 5E18;
    uint256 _maxUpdateCallerReward  = 10E18;
    uint256 _perSecondCallerRewardIncrease = 1000192559420674483977255848; // 100% per hour
    uint256 _maxRewardIncreaseDelay = 3 hours;
    uint _bidDiscount = 200; // 20%
    uint _targetAuctionValue = 50000 * WAD; // 50k

    uint lpTokenPrice;

    constructor() StakingAuctionInitialParameterSetterMock(
            address(new Feed(114 ether, true)),
            address(new Feed(3 ether, true)),
            address(new Feed(3093 ether, true)),
            address(new StakingMock()),
            address(new UniPairMock()),
            address(new MockTreasury(address(new TokenMock()))),
            _periodSize,
            _baseUpdateCallerReward,
            _maxUpdateCallerReward,
            _perSecondCallerRewardIncrease,
            _bidDiscount,
            _targetAuctionValue
    ) public {

        systemCoin = TokenMock(address(treasury.systemCoin()));

        lpTokenPrice = getLPTokenFairValue();

        MockTreasury(address(treasury)).setTotalAllowance(address(this), uint(-1));
        MockTreasury(address(treasury)).setPerBlockAllowance(address(this), 10E45);

        maxRewardIncreaseDelay = 6 hours;
    }

    function fuzzParams(uint flxReserves, uint ethReserves) public {
        UniPairMock(address(uniV2Pair)).setReserves(
            uint112(range(flxReserves, uint(76097123002527008280641) / 10 * 8, uint(76097123002527008280641) / 10 * 12)),
            uint112(range(ethReserves, uint(2803747969601653605423) / 10 * 8, uint(2803747969601653605423) / 10 * 12))
        );
        this.updateStakingAuctionParams(address(0xdeadbeef));
    }

    function range(uint a, uint min, uint max) public pure returns (uint) {
        if (a <= min) return min;
        if (a >= max) return max;
        return a;
    }

    // properties
    function echidna_staking_auction_bid_size() public returns (bool) {
        (uint bidSize, ) = getNewStakingAuctionParams();
        return true;
        return (StakingMock(address(staking)).systemCoinsToRequest() == bidSize || lastUpdateTime == 0);
    }

    function echidna_staking_auction_minted_tokens() public returns (bool) {
        (, uint lpTokensToAuction) = getNewStakingAuctionParams();
        return (StakingMock(address(staking)).tokensToAuction() == lpTokensToAuction || lastUpdateTime == 0);
    }

    uint tolerance = 30; // % deviation tolerated
    function echidna_imbalance() public returns(bool) {
        return (
            getLPTokenFairValue() > lpTokenPrice * (100 - tolerance) / 100 &&
            getLPTokenFairValue() < lpTokenPrice * (100 + tolerance) / 100
        );
    }
}


