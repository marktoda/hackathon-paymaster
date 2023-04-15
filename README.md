# Public Paymaster

A public paymaster smart contract that allows anyone to deposit ETH and cover the gas costs of ERC-4337 transactions. Users (sub-paymasters) specify which token they are willing to receive, and a Uniswap V3 price oracle is used to determine the number of tokens needed to cover the gas.

# Why
There is a market of demand (ERC-4337 wallet users) and supply (paymaster operators) for ERC-4337 paymasters. Users may want to pay with a wide range of assets, and each paymaster operator will only be willing to support a small subset of them. It may become quite difficult to search the full space of paymasters to find one that supports the proper token, and to ensure that they are offering a fair price.

The public paymaster matches the sides of this market by acting as a single source of liquidity for ERC-20 gas payments.

# Future Extensions

## Pricing market
Sub-paymasters should be able to specify a "spread" above the oracle price at which they are willing to fulfill transactions. This would create a competitive price market for gas payment rates.

This could be implemented using discrete intervals of price spread, at which sub-paymasters can deposit ETH. Transactions will be fulfilled by the lowest-spread sub-paymasters first until they are exhausted, and then iteratively use higher (worse) spreads.

This is useful for example for tokens which may be riskier or more volatile so a higher spread can make up for the extra risk. The market also adds competition among sub-paymasters to offer the best possible price for users.
