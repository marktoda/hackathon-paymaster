// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

/* solhint-disable reason-string */

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../core/BasePaymaster.sol";
import "./AaveFundsManager.sol";
import "./IOracle.sol";

/**
 * A token-based paymaster that accepts token deposits
 * The deposit is only a safeguard: the user pays with his token balance.
 *  only if the user didn't approve() the paymaster, or if the token balance is not enough, the deposit will be used.
 *  thus the required deposit is to cover just one method call.
 * The deposit is locked for the current block: the user must issue unlockTokenDeposit() to be allowed to withdraw
 *  (but can't use the deposit for this or further operations)
 *
 * paymasterAndData holds the paymaster address followed by the token address to use.
 * @notice This paymaster will be rejected by the standard rules of EIP4337, as it uses an external oracle.
 * (the standard rules ban accessing data of an external contract)
 * It can only be used if it is "whitelisted" by the bundler.
 * (technically, it can be used by an "oracle" which returns a static value, without accessing any storage)
 */
contract GeneralPaymaster is BasePaymaster, ERC1155, AaveFundsManager {
    using UserOperationLib for UserOperation;
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

    constructor(IEntryPoint _entryPoint) BasePaymaster(_entryPoint) {}

    function depositETH(address token) external payable {
        tokenETHBalance[token] += msg.value;
        _depositETH(msg.value);
        _mint(msg.sender, uint256(uint160(token)), msg.value);
    }

    function withdrawLP(address token) external payable {
        uint256 balance = ERC20(token).balanceOf(address(this));
        uint256 ethBalance = tokenETHBalance[token];
        uint256 liquidity = balanceOf(uint256(uint160(token)), msg.sender);

        uint256 amount = liquidity * balance / totalSupply(uint256(uint160(token)));
        uint256 amountInEth = liquidity * ethBalance / totalSupply(uint256(uint160(token)));
        _burn(msg.sender, uint256(uint160(token)), liquidity);

        // withdraw from aave
        _withdraw(token, amount, msg.sender);

        // try to withdraw from aave
        // if not enough, then withdraw from entrypoint
        _withdrawETH(amountInETH, msg.sender);
    }

    /**
     * owner of the paymaster should add supported tokens
     */
    function addToken(IERC20 token, IOracle tokenPriceOracle) external onlyOwner {
        if (oracles[token] != NULL_ORACLE) revert TokenAlreadySet();
        oracles[token] = tokenPriceOracle;
    }

    /**
     * translate the given eth value to token amount
     * @param token the token to use
     * @param ethBought the required eth value we want to "buy"
     * @return requiredTokens the amount of tokens required to get this amount of eth
     * TODO: use a TWAP oracle.
     */
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

    /**
     * Validate the request:
     * The sender should have enough deposit to pay the max possible cost.
     * Note that the sender's balance is not checked. If it fails to pay from its balance,
     * this deposit will be used to compensate the paymaster for the transaction.
     */
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
        if (tokenETHBalance[token] < maxCost) revert InsufficientETH();
        if (token.balanceOf(this) < maxTokenCost) revert InsufficientDeposit();
        return (abi.encode(account, token, gasPriceUserOp, maxTokenCost, maxCost), 0);
    }

    /**
     * perform the post-operation to charge the sender for the gas.
     * in normal mode, use transferFrom to withdraw enough tokens from the sender's balance.
     * in case the transferFrom fails, the _postOp reverts and the entryPoint will call it again,
     * this time in *postOpReverted* mode.
     * In this mode, we use the deposit to pay (which we validated to be large enough)
     */
    function _postOp(PostOpMode mode, bytes calldata context, uint256 actualGasCost) internal override {
        (address account, IERC20 token, uint256 gasPricePostOp, uint256 maxTokenCost, uint256 maxCost) =
            abi.decode(context, (address, IERC20, uint256, uint256, uint256));
        //use same conversion rate as used for validation.
        uint256 actualTokenCost = (actualGasCost + COST_OF_POST * gasPricePostOp) * maxTokenCost / maxCost;

        tokenETHBalance[token] -= actualGasCost + COST_OF_POST * gasPricePostOp;

        if (mode != PostOpMode.postOpReverted) {
            // attempt to pay with tokens:
            token.safeTransferFrom(account, address(this), actualTokenCost);
        } else {
            // TODO: what does ERC4337 spec say about the error code here?
            revert PostOpError();
        }
        _deposit(token, actualTokenCost);
    }
}
