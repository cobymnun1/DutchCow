 // SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {IERC20} from "cowprotocol/contracts/interfaces/IERC20.sol";
import {GPv2Order} from "cowprotocol/contracts/libraries/GPv2Order.sol";
import {BaseConditionalOrder} from "composable-cow/src/BaseConditionalOrder.sol";
import {IConditionalOrder} from "composable-cow/src/interfaces/IConditionalOrder.sol";

// TEST DEPLOYMENT 
// Author: @cobymnun on x, inspired by @kayibal's original Dutch CoWs.
// block times are set for base. 
// maxAmount is what you want to start the auction at. reciever is you, validFor is auction duration measured in blocks. 
// A 0.1% by volume fee is taken on each auction from CoW returned surplus value, integrated as a CoW partner fee. 
// This software comes with no warranty.

contract DutchAuction is BaseConditionalOrder {
    struct Data {
        IERC20 sellToken;
        IERC20 buyToken;
        uint256 sellAmount;
        uint256 maxAmount;
        address receiver;
        uint256 startBlock;
        uint32 validFor;
        uint32 slippageBps;
    }

    bytes32 public constant APP_DATA = 0x09eed5e4a791d7763f86d80bace7aac36a981efa30a39e45b9f65adf28d8b932;

    function getTradeableOrder(address, address, bytes32, bytes calldata staticInput, bytes calldata)
        public
        view
        override
        returns (GPv2Order.Data memory order)
    {
        Data memory data = abi.decode(staticInput, (Data));

        if (data.slippageBps > 10_000) revert IConditionalOrder.OrderNotValid("BadSlippage");
        if (block.number < data.startBlock) revert IConditionalOrder.PollTryAtBlock(data.startBlock, "NotStarted");

        uint256 endBlock = data.startBlock + data.validFor;
        if (block.number >= endBlock) revert IConditionalOrder.PollNever("AuctionEnded");

        uint256 minAmount = data.maxAmount * (10_000 - data.slippageBps) / 10_000 ;
        uint256 priceAtStep = data.maxAmount - ((data.maxAmount - minAmount) * (block.number - data.startBlock)) / data.validFor;

        uint32 validTo = uint32(block.timestamp + (endBlock - block.number) * 2);

        order = GPv2Order.Data(
            data.sellToken,
            data.buyToken,
            data.receiver,
            data.sellAmount,
            priceAtStep,
            validTo,
            APP_DATA,
            0,
            GPv2Order.KIND_SELL, 
            false,
            GPv2Order.BALANCE_ERC20,
            GPv2Order.BALANCE_ERC20
        );
    }
}