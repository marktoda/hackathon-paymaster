// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

/* solhint-disable reason-string */

import {WETH} from "solmate/src/tokens/WETH.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/IEntryPoint.sol";
import {IPool} from "../../interfaces/IAavePool.sol";

import "../core/BasePaymaster.sol";
import "./IOracle.sol";

abstract contract AaveFundsManager {
    address public immutable manager;
    IPool public immutable pool;
    WETH public immutable weth;
    IPaymaster private immutable paymaster;

    constructor(address _manager, address _pool, address _weth, address _paymaster) {
        manager = _manager;
        pool = IPool(_pool);
        weth = WETH(_weth);
        paymaster = IPaymaster(_paymaster);
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
        entryPoint.depositTo{value: amount}(address(this));
    }
}
