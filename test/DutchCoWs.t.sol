// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {GPv2Order} from "cowprotocol/contracts/libraries/GPv2Order.sol";
import {IConditionalOrder} from "composable-cow/src/interfaces/IConditionalOrder.sol";
import {ComposableCoW} from "composable-cow/src/ComposableCoW.sol";
import {ERC1271Forwarder} from "composable-cow/src/ERC1271Forwarder.sol";
import {StackTest} from "./helpers/Stack.sol";
import {Data} from "../src/DutchCoWs.sol";
import {DutchCowEscrow} from "../src/escrow.sol";
import {ZooToken} from "./tokens/Zoo.sol";

contract DutchCoWsTest is StackTest {
    ZooToken internal sell;
    ZooToken internal buy;
    uint256 internal constant MAX = 100 ether;

    function setUp() public override {
        super.setUp();
        sell = new ZooToken("SELL", 18);
        buy = new ZooToken("BUY", 18);
    }

    function _open() internal returns (Data memory p, address escrow) {
        p = _data(address(sell), address(buy), 1 ether, MAX, 25, 500);
        (escrow,) = _place(sell, p, 1.5 ether);
    }

    function test_price_holds_then_decays_without_underflow() public {
        (Data memory p, address escrow) = _open();
        uint256 floor = MAX * 9500 / 10_000;
        uint256 step = (MAX - floor) / 25;
        assertEq(_buy(escrow, p, p.startBlock + 4), MAX);
        assertEq(_buy(escrow, p, p.startBlock + 5), MAX - step);
        assertEq(_buy(escrow, p, p.startBlock + 6), MAX - 2 * step);
        uint256 last = p.startBlock + p.validFor - 1;
        uint256 elapsed = last - p.startBlock - 4;
        assertEq(_buy(escrow, p, last), MAX - elapsed * step);
        assertGt(_buy(escrow, p, last), floor);
    }

    function test_validTo_rounds_up_in_the_last_four_blocks() public {
        (Data memory p, address escrow) = _open();
        vm.warp(1_000_000);
        vm.roll(p.startBlock);
        (, GPv2Order.Data memory order) = _at(escrow, p);
        assertEq(order.validTo, uint32(block.timestamp + 5));

        vm.roll(p.startBlock + 21);
        (, order) = _at(escrow, p);
        assertEq(order.validTo, uint32(block.timestamp + 1));

        vm.roll(p.startBlock + p.validFor);
        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.PollNever.selector, "AuctionEnded"));
        this.quote(escrow, p);
    }

    function test_signature_accepts_at_and_above_floor_rejects_below_and_tamper() public {
        (Data memory p, address escrow) = _open();
        (bytes memory sig, GPv2Order.Data memory order) = _at(escrow, p);
        bytes32 digest = GPv2Order.hash(order, cow.domainSeparator());
        assertEq(DutchCowEscrow(escrow).isValidSignature(digest, sig), bytes4(0x1626ba7e));

        GPv2Order.Data memory above = abi.decode(abi.encode(order), (GPv2Order.Data));
        above.buyAmount = order.buyAmount + 1;
        assertEq(
            DutchCowEscrow(escrow).isValidSignature(GPv2Order.hash(above, cow.domainSeparator()), _swap(sig, above)),
            bytes4(0x1626ba7e)
        );

        GPv2Order.Data memory below = abi.decode(abi.encode(order), (GPv2Order.Data));
        below.buyAmount = order.buyAmount - 1;
        bytes memory belowSig = _swap(sig, below);
        bytes32 belowHash = GPv2Order.hash(below, cow.domainSeparator());
        vm.expectRevert(bytes("BelowFloor"));
        DutchCowEscrow(escrow).isValidSignature(belowHash, belowSig);

        GPv2Order.Data memory tampered = abi.decode(abi.encode(order), (GPv2Order.Data));
        tampered.feeAmount = 1;
        bytes memory tamperedSig = _swap(sig, tampered);
        bytes32 tamperedHash = GPv2Order.hash(tampered, cow.domainSeparator());
        vm.expectRevert(bytes("FieldMismatch"));
        DutchCowEscrow(escrow).isValidSignature(tamperedHash, tamperedSig);

        vm.expectRevert(ERC1271Forwarder.InvalidHash.selector);
        DutchCowEscrow(escrow).isValidSignature(bytes32(uint256(1)), sig);
    }

    function test_signature_from_another_escrow_is_rejected() public {
        (Data memory p1, address escrow1) = _open();
        Data memory p2 = abi.decode(abi.encode(p1), (Data));
        p2.validFor = 40;
        (address escrow2,) = _place(sell, p2, 1.5 ether);
        (bytes memory sig1, GPv2Order.Data memory order1) = _at(escrow1, p1);
        (bytes memory sig2, GPv2Order.Data memory order2) = _at(escrow2, p2);
        sig2;
        order2;
        bytes32 digest1 = GPv2Order.hash(order1, cow.domainSeparator());
        vm.expectRevert(ComposableCoW.SingleOrderNotAuthed.selector);
        DutchCowEscrow(escrow2).isValidSignature(digest1, sig1);
    }

    function test_fill_stops_polling_until_tokens_are_donated_back() public {
        (Data memory p, address escrow) = _open();
        (bytes memory sig, GPv2Order.Data memory order) = _at(escrow, p);
        vm.prank(relayer);
        sell.transferFrom(escrow, address(0xB0B), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.PollNever.selector, "Filled"));
        this.quote(escrow, p);
        bytes32 digest = GPv2Order.hash(order, cow.domainSeparator());
        vm.expectRevert(bytes("Filled"));
        DutchCowEscrow(escrow).isValidSignature(digest, sig);

        sell.mint(escrow, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.PollNever.selector, "Filled"));
        this.quote(escrow, p);
    }

    function _buy(address escrow, Data memory p, uint256 blockNo) internal returns (uint256) {
        vm.roll(blockNo);
        (, GPv2Order.Data memory order) = _at(escrow, p);
        return order.buyAmount;
    }

    function _at(address escrow, Data memory p) internal view returns (bytes memory sig, GPv2Order.Data memory order) {
        (order, sig) = _quote(escrow, p, address(this));
    }

    function quote(address escrow, Data calldata p) external view {
        cow.getTradeableOrderWithSignature(escrow, _params(p, address(this)), "", new bytes32[](0));
    }

    function _swap(bytes memory sig, GPv2Order.Data memory order) internal pure returns (bytes memory) {
        (, ComposableCoW.PayloadStruct memory payload) = abi.decode(sig, (GPv2Order.Data, ComposableCoW.PayloadStruct));
        return abi.encode(order, payload);
    }
}
