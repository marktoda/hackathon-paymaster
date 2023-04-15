// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import "./IEntryPoint.sol";
interface IPaymasterFactory {
    function deploy(
        IEntryPoint entryPoint,
        address owner,
        address token
    )

    function deploy(
        IEntryPoint entryPoint,
        address owner,
        address token,
        uint256 minBalance
    )
}