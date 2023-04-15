// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

/* solhint-disable reason-string */

import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "./ERC721OwnershipPaymaster.sol";
import "./ERC20BalancePaymaster.sol";
import "./interfaces/IPaymaster.sol";
import "./interfaces/IPaymasterFactory.sol";

/**
 * Factory for creating paymasters.
 */

contract PaymasterFactory is IPaymasterFactory {
    function deploy(
        IEntryPoint entryPoint,
        address owner,
        address token
    ) external override returns (address paymaster) {
        return address(new ERC721OwnershipPaymaster{salt: keccak256(abi.encode(address(entryPoint, owner, token)))}(entryPoint, owner, token));
    }

    function deploy(
        IEntryPoint entryPoint,
        address owner,
        address requiredToken,
        uint256 minBalance
    ) external override returns (address paymaster) {
        return address(new ERC20BalancePaymaster{salt: keccak256(abi.encode(address(entryPoint, owner, requiredToken)))}(entryPoint, owner, requiredToken, minBalance));
    }
}

