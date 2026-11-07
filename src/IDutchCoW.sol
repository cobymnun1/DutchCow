// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

/// @notice Minimal interfaces for integrating with Dutch CoWs. Token fields are `address`;
///         the ABI encoding is identical to `Data` in DutchCoWs.sol.

/// @param sellToken   Token sold.
/// @param buyToken    Token bought.
/// @param sellAmount  Amount of sellToken the order sells.
/// @param maxAmount   Starting (highest) buyToken amount.
/// @param receiver    Must equal the caller of `placeOrder`. Receives buyToken and refunds.
/// @param startBlock  Must equal `block.number` when `placeOrder` is called.
/// @param validFor    Auction length in blocks (min 25).
/// @param slippageBps Total decay in bps of maxAmount (51..9998).
struct AuctionParams {
    address sellToken;
    address buyToken;
    uint256 sellAmount;
    uint256 maxAmount;
    address receiver;
    uint256 startBlock;
    uint32 validFor;
    uint32 slippageBps;
}

interface IDutchCoWAuctioneer {
    event OrderPlaced(
        bytes32 indexed orderId, address indexed owner, AuctionParams params, address indexed escrowAddress
    );

    /// @notice Create the escrow, pull sellToken into it and register the order.
    /// @dev In one transaction: set `startBlock = block.number` and `receiver = address(this)`,
    ///      `escrow = predictEscrow(params)`, approve the escrow for at least `sellAmount` and
    ///      less than `2 * sellAmount` (the extra covers token transfer fees), then call this.
    function placeOrder(AuctionParams calldata params) external returns (bytes32 orderId);

    /// @notice Escrow address for `params` when called by `msg.sender`. Valid before deployment.
    function predictEscrow(AuctionParams calldata params) external view returns (address escrow);

    function handler() external view returns (address);
    function implementation() external view returns (address);
    function vaultRelayer() external view returns (address);
}

interface IDutchCoWEscrow {
    /// @notice After `startBlock + validFor`, cancel the order and refund the balance to the owner.
    ///         The caller gets 0.1% of the balance as a tip. Permissionless.
    function releaseFunds() external;

    function CowOrder() external view returns (bytes32);
    function _owner() external view returns (address);
    function auctioneer() external view returns (address);
    function vaultRelayer() external view returns (address);
}
