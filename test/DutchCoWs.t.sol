// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "cowprotocol/contracts/interfaces/IERC20.sol";
import {GPv2Order} from "cowprotocol/contracts/libraries/GPv2Order.sol";
import {IConditionalOrder} from "composable-cow/src/interfaces/IConditionalOrder.sol";
import {DutchAuction} from "../DutchCoWs.sol";

contract DutchCoWsTest is Test {
    DutchAuction internal handler;
    DutchAuction.Data internal data;

    bytes32 internal constant DOMAIN_SEPARATOR =
        0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa;
    address internal constant SELL_TOKEN = 0x0000000000000000000000000000000000001001;
    address internal constant BUY_TOKEN = 0x0000000000000000000000000000000000001002;
    address internal constant RECEIVER = 0x0000000000000000000000000000000000001003;

    function setUp() public {
        handler = new DutchAuction();
        data = DutchAuction.Data({
            sellToken: IERC20(SELL_TOKEN),
            buyToken: IERC20(BUY_TOKEN),
            sellAmount: 13 ether,
            maxAmount: 11_200_000,
            receiver: RECEIVER,
            startBlock: block.number,
            validFor: 100,
            slippageBps: 300
        });
    }

    function test_priceDecaysLinearly() public {
        GPv2Order.Data memory startOrder = _orderAtCurrentBlock();
        uint256 minAmount = data.maxAmount * (10_000 - data.slippageBps) / 10_000;

        assertEq(startOrder.buyAmount, data.maxAmount);

        vm.roll(data.startBlock + data.validFor / 2);
        GPv2Order.Data memory halfwayOrder = _orderAtCurrentBlock();
        uint256 expectedHalfway =
            data.maxAmount - ((data.maxAmount - minAmount) * (data.validFor / 2)) / data.validFor;

        assertEq(halfwayOrder.buyAmount, expectedHalfway);
        assertLt(halfwayOrder.buyAmount, startOrder.buyAmount);
        assertGt(halfwayOrder.buyAmount, minAmount);

        vm.roll(data.startBlock + data.validFor - 1);
        GPv2Order.Data memory finalOrder = _orderAtCurrentBlock();
        uint256 expectedFinal =
            data.maxAmount - ((data.maxAmount - minAmount) * (data.validFor - 1)) / data.validFor;
        assertEq(finalOrder.buyAmount, expectedFinal);
        assertGt(finalOrder.buyAmount, minAmount);
    }

    function test_revertsBeforeStart() public {
        data.startBlock = block.number + 10;
        bytes memory staticInput = abi.encode(data);

        vm.roll(data.startBlock - 1);
        vm.expectRevert(
            abi.encodeWithSelector(IConditionalOrder.PollTryAtBlock.selector, data.startBlock, "NotStarted")
        );
        handler.getTradeableOrder(address(0), address(0), bytes32(0), staticInput, "");
    }

    function test_revertsAtAuctionEnd() public {
        bytes memory staticInput = abi.encode(data);

        vm.roll(data.startBlock + data.validFor);
        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.PollNever.selector, "AuctionEnded"));
        handler.getTradeableOrder(address(0), address(0), bytes32(0), staticInput, "");
    }

    function test_validToTracksRemainingAuctionBlocks() public {
        vm.roll(data.startBlock + 25);
        GPv2Order.Data memory order = _orderAtCurrentBlock();
        uint256 remainingBlocks = data.startBlock + data.validFor - block.number;
        uint256 expectedValidTo = block.timestamp + remainingBlocks * 2;

        assertEq(order.validTo, expectedValidTo);
        assertGe(order.validTo, block.timestamp);
        assertLe(order.validTo, block.timestamp + data.validFor * 2);
    }

    function test_verifyPassesAtTheBlockTheOrderWasGenerated() public view {
        GPv2Order.Data memory order = _orderAtCurrentBlock();
        bytes32 orderHash = GPv2Order.hash(order, DOMAIN_SEPARATOR);

        handler.verify(
            address(this),
            address(this),
            orderHash,
            DOMAIN_SEPARATOR,
            bytes32(0),
            abi.encode(data),
            "",
            order
        );
    }

    function test_verifyAcceptsAnOldOrderWhileItIsStillAboveTheFloor() public {
        GPv2Order.Data memory oldOrder = _orderAtCurrentBlock();
        bytes32 oldOrderHash = GPv2Order.hash(oldOrder, DOMAIN_SEPARATOR);

        vm.roll(block.number + 1);
        handler.verify(
            address(this),
            address(this),
            oldOrderHash,
            DOMAIN_SEPARATOR,
            bytes32(0),
            abi.encode(data),
            "",
            oldOrder
        );
    }

    function test_verifyRejectsTamperedReceiverAndBuyAmount() public {
        GPv2Order.Data memory order = _orderAtCurrentBlock();
        bytes memory staticInput = abi.encode(data);

        GPv2Order.Data memory changedReceiver = order;
        changedReceiver.receiver = address(0xBEEF);
        vm.expectRevert(bytes("FieldMismatch"));
        handler.verify(
            address(this),
            address(this),
            GPv2Order.hash(changedReceiver, DOMAIN_SEPARATOR),
            DOMAIN_SEPARATOR,
            bytes32(0),
            staticInput,
            "",
            changedReceiver
        );

        GPv2Order.Data memory changedBuyAmount = _orderAtCurrentBlock();
        changedBuyAmount.buyAmount -= 1;
        vm.expectRevert(bytes("BelowFloor"));
        handler.verify(
            address(this),
            address(this),
            GPv2Order.hash(changedBuyAmount, DOMAIN_SEPARATOR),
            DOMAIN_SEPARATOR,
            bytes32(0),
            staticInput,
            "",
            changedBuyAmount
        );
    }

    function _orderAtCurrentBlock() internal view returns (GPv2Order.Data memory order) {
        return handler.getTradeableOrder(address(0), address(0), bytes32(0), abi.encode(data), "");
    }
}
