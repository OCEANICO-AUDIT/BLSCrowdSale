pragma solidity ^0.4.19;

import './BLSCrowdSale.sol';
import './SafeMath.sol';

contract BLSCrowdSaleTest is BLSCrowdSale {
    constructor(
        uint256 _fundingStartTime,
        uint256 _fundingEndTime,
        uint256 _roundTwoTime,
        uint256 _roundThreeTime,
        uint256 _roundFourTime,
        uint256 _roundFiveTime,
        address _admin1,
        address _admin2,
        address [] kycSigner
    ) payable BLSCrowdSale(
        _fundingStartTime,
        _fundingEndTime,
        _roundTwoTime,
        _roundThreeTime,
        _roundFourTime,
        _roundFiveTime,
        _admin1,
        _admin2,
        kycSigner
    ) {}

    function buyTokens() payable returns (bool) {
        return releaseTokensTo(msg.sender);
    }

    function updatePrice(string result) {
        ETH_USD_EXCHANGE_RATE_IN_CENTS = SafeMath.parse(result);
        updatedPrice(result);
    }
}