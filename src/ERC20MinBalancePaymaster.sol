// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ERC1155Supply} from "openzeppelin-contracts/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {ERC1155} from "openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

import "./GeneralPaymaster.sol";
import "./AaveFundsManager.sol";
import "./interfaces/IOracle.sol";

contract ERC721OwnershipPaymaster is GeneralPaymaster, Ownable {
    IERC20 public membershipToken;
    uint256 public minBalance;

    error InsufficentMembershipFunds();

    constructor(IEntryPoint _entryPoint, address _owner, address _membershipToken, uint256 _minBalance) {
        transferOwnership(_owner);
        GeneralPaymaster(_entryPoint);
        membershipToken = IERC20(_membershipToken);
        minBalance = _minBalance;
    }

    /// @notice Validate the request:
    /// The sender should have enough deposit to pay the max possible cost.
    /// Note that the sender's balance is not checked. If it fails to pay from its balance,
    /// this deposit will be used to compensate the paymaster for the transaction.
    function _validatePaymasterUserOp(UserOperation calldata userOp, bytes32 userOpHash, uint256 maxCost)
        internal
        view
        override
        returns (bytes memory context, uint256 validationData)
    {
        (userOpHash);
        // verificationGasLimit is dual-purposed, as gas limit for postOp. make sure it is high enough
        if (userOp.verificationGasLimit <= COST_OF_POST) revert GasTooLow();

        bytes calldata paymasterAndData = userOp.paymasterAndData;
        if (paymasterAndData.length != 20 + 20) revert TokenNotSpecified();
        IERC20 token = IERC20(address(bytes20(paymasterAndData[20:])));
        address account = userOp.getSender();
        if (membershipToken.balanceOf(account) < minBalance) revert InsufficentMembershipFunds();
        uint256 maxTokenCost = getTokenValueOfEth(token, maxCost);
        uint256 gasPriceUserOp = userOp.gasPrice();
        if (tokenETHBalance[address(token)] < maxCost) revert InsufficientETH();
        return (abi.encode(account, token, gasPriceUserOp, maxTokenCost, maxCost), 0);
    }
}