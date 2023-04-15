// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ERC1155Supply} from "openzeppelin-contracts/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import {ERC1155} from "openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import "./BasePaymaster.sol";
import "./AaveFundsManager.sol";
import "./interfaces/IOracle.sol";

/// @notice GeneralPaymaster
/// A shared public token-based paymaster that accepts token payments
/// sub-paymasters lock ETH for each token they are willing to accept
contract GeneralPaymaster is BasePaymaster, ERC1155Supply, AaveFundsManager {
    using UserOperationLib for UserOperation;
    using FixedPointMathLib for uint256;
    using SafeERC20 for IERC20;

    error TokenAlreadySet();
    error UnsupportedToken();
    error NotUnlocked();
    error GasTooLow();
    error TokenNotSpecified();
    error InsufficientETH();
    error NotLocked();
    error InsufficientDeposit();
    error PostOpError();

    // eth for gas by token
    mapping(address token => uint256) public tokenETHBalance;

    // calculated cost of the postOp
    uint256 public constant COST_OF_POST = 35000;

    IOracle private constant NULL_ORACLE = IOracle(address(0));
    mapping(IERC20 => IOracle) public oracles;

    constructor(IEntryPoint _entryPoint)
        BasePaymaster(_entryPoint)
        AaveFundsManager(msg.sender, _entryPoint)
        ERC1155("")
    {}

    /// @notice Deposit ETH to participate as a Sub-Paymaster for the given token
    /// @param token The token to accept in return for ETH
    function depositSubpaymaster(address token) external payable {
        tokenETHBalance[token] += msg.value;
        _depositETH(msg.value);
        _mint(msg.sender, uint256(uint160(token)), msg.value, "");
    }

    /// @notice Withdraw tokens and ETH as a sub-paymaster for the given token
    /// @dev burns LP tokens for the given sub-paymaster pool and return
    /// any accrued tokens and leftover ETH
    /// @param token The token to withdraw sub-paymaster assets for
    function withdrawSubpaymaster(address token) external payable {
        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 tokenId = uint256(uint160(token));
        uint256 liquidity = balanceOf(msg.sender, tokenId);
        uint256 lpSupply = totalSupply(tokenId);

        _burn(msg.sender, tokenId, liquidity);

        // withdraw from aave
        _withdraw(token, liquidity.mulDivDown(balance, lpSupply), msg.sender);

        // try to withdraw from aave
        // if not enough, then withdraw from entrypoint
        _withdrawETH(liquidity.mulDivDown(tokenETHBalance[token], lpSupply), msg.sender);
    }

    /// @notice owner of the paymaster should add supported tokens
    function addToken(IERC20 token, IOracle tokenPriceOracle) external onlyOwner {
        if (oracles[token] != NULL_ORACLE) revert TokenAlreadySet();
        oracles[token] = tokenPriceOracle;
    }

    /// @notice translate the given eth value to token amount
    /// @param token the token to use
    /// @param ethBought the required eth value we want to "buy"
    /// @return requiredTokens the amount of tokens required to get this amount of eth
    function getTokenValueOfEth(IERC20 token, uint256 ethBought)
        internal
        view
        virtual
        returns (uint256 requiredTokens)
    {
        IOracle oracle = oracles[token];
        if (oracle == NULL_ORACLE) revert UnsupportedToken();
        return oracle.getTokenValueOfEth(ethBought);
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
        uint256 maxTokenCost = getTokenValueOfEth(token, maxCost);
        uint256 gasPriceUserOp = userOp.gasPrice();
        if (tokenETHBalance[address(token)] < maxCost) revert InsufficientETH();
        return (abi.encode(account, token, gasPriceUserOp, maxTokenCost, maxCost), 0);
    }

    /// @notice perform the post-operation to charge the sender for the gas.
    /// in normal mode, use transferFrom to withdraw enough tokens from the sender's balance.
    /// in case the transferFrom fails, the _postOp reverts and the entryPoint will call it again,
    /// this time in *postOpReverted* mode.
    /// In this mode, we use the deposit to pay (which we validated to be large enough)
    function _postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost) internal override {
        (address account, IERC20 token, uint256 gasPricePostOp, uint256 maxTokenCost, uint256 maxCost) =
            abi.decode(context, (address, IERC20, uint256, uint256, uint256));
        // use same conversion rate as used for validation.
        uint256 actualTokenCost = (actualGasCost + COST_OF_POST * gasPricePostOp) * maxTokenCost / maxCost;

        tokenETHBalance[address(token)] -= actualGasCost + COST_OF_POST * gasPricePostOp;

        if (mode != PostOpMode.postOpReverted) {
            // attempt to pay with tokens:
            token.safeTransferFrom(account, address(this), actualTokenCost);
        } else {
            revert PostOpError();
        }
        _deposit(address(token), actualTokenCost);
    }
}
