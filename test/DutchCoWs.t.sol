// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "cowprotocol/contracts/interfaces/IERC20.sol";
import {GPv2Order} from "cowprotocol/contracts/libraries/GPv2Order.sol";
import {IConditionalOrder, IConditionalOrderGenerator} from "composable-cow/src/interfaces/IConditionalOrder.sol";
import {IERC165} from "@openzeppelin/utils/introspection/IERC165.sol";
import {DutchAuction} from "../DutchCoWs.sol";

contract DutchCoWsTest is Test {
    DutchAuction internal handler;
    DutchAuction.Data internal data;

    bytes32 internal constant DOMAIN_SEPARATOR =
        0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa;
    address internal constant SELL_TOKEN = 0x1111111111111111111111111111111111111111;
    address internal constant BUY_TOKEN = 0x2222222222222222222222222222222222222222;
    address internal constant RECEIVER = 0x3333333333333333333333333333333333333333;

    function setUp() public {
        handler = new DutchAuction();
        data = DutchAuction.Data({
            sellToken: IERC20(SELL_TOKEN),
            buyToken: IERC20(BUY_TOKEN),
            sellAmount: 1 ether,
            maxAmount: 1000 ether,
            receiver: RECEIVER,
            startBlock: block.number,
            validFor: 100,
            slippageBps: 500
        });
    }

    function test_priceDecaysLinearly() public {
        GPv2Order.Data memory startOrder = _get();
        uint256 minAmount = data.maxAmount * (10_000 - data.slippageBps) / 10_000;

        assertEq(startOrder.buyAmount, data.maxAmount);

        vm.roll(data.startBlock + data.validFor / 2);
        GPv2Order.Data memory halfwayOrder = _get();
        uint256 expectedHalfway =
            data.maxAmount - ((data.maxAmount - minAmount) * (data.validFor / 2)) / data.validFor;

        assertEq(halfwayOrder.buyAmount, expectedHalfway);
        assertLt(halfwayOrder.buyAmount, startOrder.buyAmount);
        assertGt(halfwayOrder.buyAmount, minAmount);

        vm.roll(data.startBlock + data.validFor - 1);
        GPv2Order.Data memory finalOrder = _get();
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

    function test_verifyRevertsAtEndBlock() public {
        GPv2Order.Data memory order = _get();

        vm.roll(data.startBlock + data.validFor);
        vm.expectRevert(bytes("OutsideWindow"));
        _verify(order);
    }

    function test_verifyRevertsBeforeStart() public {
        data.startBlock = block.number + 10;
        GPv2Order.Data memory order = _manualOrder(data.maxAmount);

        vm.expectRevert(bytes("OutsideWindow"));
        _verify(order);
    }

    function test_validToTracksRemainingAuctionBlocks() public {
        vm.roll(data.startBlock + 25);
        GPv2Order.Data memory order = _get();
        uint256 remainingBlocks = data.startBlock + data.validFor - block.number;
        uint256 expectedValidTo = block.timestamp + remainingBlocks * 2;

        assertEq(order.validTo, expectedValidTo);
        assertGe(order.validTo, block.timestamp);
        assertLe(order.validTo, block.timestamp + data.validFor * 2);
    }

    function test_verifyAtStartBlock() public view {
        _verify(_get());
    }

    function test_oldOrderStillVerifiesAfterRoll() public {
        GPv2Order.Data memory oldOrder = _get();

        vm.roll(data.startBlock + 3);
        _verify(oldOrder);
    }

    function test_revertsBelowFloor() public {
        GPv2Order.Data memory order = _get();
        order.buyAmount = _floor() - 1;

        vm.expectRevert(bytes("BelowFloor"));
        _verify(order);
    }

    function test_tamperSellTokenRevertsFieldMismatch() public {
        GPv2Order.Data memory order = _get();
        order.sellToken = IERC20(address(0x4444));
        _expectFieldMismatch(order);
    }

    function test_tamperBuyTokenRevertsFieldMismatch() public {
        GPv2Order.Data memory order = _get();
        order.buyToken = IERC20(address(0x5555));
        _expectFieldMismatch(order);
    }

    function test_tamperReceiverRevertsFieldMismatch() public {
        GPv2Order.Data memory order = _get();
        order.receiver = address(0xBEEF);
        _expectFieldMismatch(order);
    }

    function test_tamperSellAmountRevertsFieldMismatch() public {
        GPv2Order.Data memory order = _get();
        order.sellAmount += 1;
        _expectFieldMismatch(order);
    }

    function test_tamperAppDataRevertsFieldMismatch() public {
        GPv2Order.Data memory order = _get();
        order.appData = bytes32(uint256(1));
        _expectFieldMismatch(order);
    }

    function test_tamperFeeAmountRevertsFieldMismatch() public {
        GPv2Order.Data memory order = _get();
        order.feeAmount = 1;
        _expectFieldMismatch(order);
    }

    function test_tamperKindRevertsFieldMismatch() public {
        GPv2Order.Data memory order = _get();
        order.kind = GPv2Order.KIND_BUY;
        _expectFieldMismatch(order);
    }

    function test_tamperPartialFillRevertsFieldMismatch() public {
        GPv2Order.Data memory order = _get();
        order.partiallyFillable = true;
        _expectFieldMismatch(order);
    }

    function test_tamperSellTokenBalanceRevertsFieldMismatch() public {
        GPv2Order.Data memory order = _get();
        order.sellTokenBalance = bytes32("external");
        _expectFieldMismatch(order);
    }

    function test_tamperBuyTokenBalanceRevertsFieldMismatch() public {
        GPv2Order.Data memory order = _get();
        order.buyTokenBalance = bytes32("external");
        _expectFieldMismatch(order);
    }

    function test_badHashReverts() public {
        GPv2Order.Data memory order = _get();
        vm.expectRevert(bytes("BadHash"));
        handler.verify(
            address(0),
            address(0),
            bytes32(uint256(1)),
            DOMAIN_SEPARATOR,
            bytes32(0),
            abi.encode(data),
            "",
            order
        );
    }

    function test_buyAmountAboveFloorPasses() public view {
        GPv2Order.Data memory order = _get();
        order.buyAmount = data.maxAmount * 2;
        _verify(order);
    }

    function test_slippageOver10000() public {
        data.slippageBps = 10_001;
        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.OrderNotValid.selector, "BadSlippage"));
        handler.getTradeableOrder(address(0), address(0), bytes32(0), abi.encode(data), "");

        GPv2Order.Data memory order = _manualOrder(data.maxAmount);
        vm.expectRevert(bytes("BadSlippage"));
        _verify(order);
    }

    function test_supportsInterface() public view {
        assertTrue(handler.supportsInterface(type(IConditionalOrderGenerator).interfaceId));
        assertTrue(handler.supportsInterface(type(IERC165).interfaceId));
        assertFalse(handler.supportsInterface(0xffffffff));
    }

    function test_priceMonotonicallyDecreases() public {
        uint256 previous = type(uint256).max;
        uint256 minAmount = data.maxAmount * (10_000 - data.slippageBps) / 10_000;

        for (uint256 i = 0; i < data.validFor; i++) {
            vm.roll(data.startBlock + i);
            uint256 current = _get().buyAmount;
            assertLe(current, previous);
            previous = current;
        }

        assertGt(previous, minAmount);
    }

    function _expectFieldMismatch(GPv2Order.Data memory order) internal {
        vm.expectRevert(bytes("FieldMismatch"));
        _verify(order);
    }

    function _get() internal view returns (GPv2Order.Data memory order) {
        return handler.getTradeableOrder(address(0), address(0), bytes32(0), abi.encode(data), "");
    }

    function _verify(GPv2Order.Data memory order) internal view {
        handler.verify(
            address(0),
            address(0),
            GPv2Order.hash(order, DOMAIN_SEPARATOR),
            DOMAIN_SEPARATOR,
            bytes32(0),
            abi.encode(data),
            "",
            order
        );
    }

    function _manualOrder(uint256 buyAmount) internal view returns (GPv2Order.Data memory order) {
        return GPv2Order.Data(
            data.sellToken,
            data.buyToken,
            data.receiver,
            data.sellAmount,
            buyAmount,
            uint32(block.timestamp + data.validFor * 2),
            handler.APP_DATA(),
            0,
            GPv2Order.KIND_SELL,
            false,
            GPv2Order.BALANCE_ERC20,
            GPv2Order.BALANCE_ERC20
        );
    }

    function _floor() internal view returns (uint256) {
        uint256 minAmount = data.maxAmount * (10_000 - data.slippageBps) / 10_000;
        return data.maxAmount
            - ((data.maxAmount - minAmount) * (block.number - data.startBlock)) / data.validFor;
    }
}
