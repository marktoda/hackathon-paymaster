// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

/* solhint-disable reason-string */

import {WETH} from "solmate/tokens/WETH.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IEntryPoint.sol";
import {IPool} from "./interfaces/IAavePool.sol";

import "./BasePaymaster.sol";
import "./interfaces/IOracle.sol";

abstract contract AaveFundsManager {
    error Unauthorized();

    IPool public constant pool = IPool(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);
    WETH public constant weth = WETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address public immutable manager;
    IEntryPoint private immutable entrypoint;

    modifier onlyManager() {
        if (msg.sender != manager) revert Unauthorized();
        _;
    }

    constructor(address _manager, address _entrypoint) {
        manager = _manager;
        entrypoint = IEntryPoint(_entrypoint);
    }

    function _deposit(IERC20 token, uint256 amount) internal {
        // TODO: only if aave supports it
        if (token.allowance(address(this), address(pool)) < amount) {
            token.approve(address(pool), type(uint256).max);
        }
        pool.supply(token, amount, address(this), 0);
    }

    function _depositETH(uint256 amount) internal {
        weth.deposit{value: amount}();
        if (weth.allowance(address(this), address(pool)) < amount) {
            weth.approve(address(pool), type(uint256).max);
        }
        pool.supply(address(weth), amount, address(this), 0);
    }

    function _withdraw(address token, uint256 amount, address to) internal {
        // TODO: only if aave supports it
        // TODO: if aave doesnt support it assume we have balance locally
        pool.withdraw(token, amount, to);
    }

    function _withdrawETH(uint256 amount, address to) internal {
        pool.withdraw(address(weth), amount, to);
    }

    function moveToEntrypoint(uint256 amount) external onlyManager {
        // TODO: check they dont too much
        pool.withdraw(address(weth), amount, address(this));
        weth.withdraw(amount);
        entrypoint.depositTo{value: amount}(address(this));
    }
}
