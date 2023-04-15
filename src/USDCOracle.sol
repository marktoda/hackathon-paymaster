// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.7.6;

import {OracleLibrary} from "v3-periphery/libraries/OracleLibrary.sol";

contract USDCOracle {
    // WETH-USDC pool
    address public immutable pool;
    uint32 public constant secondsAgo = 12;
    address public immutable inputToken;
    address public immutable quoteToken;

    constructor(address _pool, address _inputToken, address _quoteToken) {
        // weth-usdc pool 0x88e6a0c2ddd26feeb64f039a2c41296fcb3f5640;
        pool = _pool;
        inputToken = _inputToken; // weth 0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2;
        quoteToken = _quoteToken; // usdc 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    }

    function getTokenValueOfEth(uint256 ethOutput) external view returns (uint256 tokenInput) {
        (int24 arithmeticMeanTick,) = OracleLibrary.consult(pool, secondsAgo);
        tokenInput = OracleLibrary.getQuoteAtTick(arithmeticMeanTick, uint128(ethOutput), inputToken, quoteToken);
    }
}
