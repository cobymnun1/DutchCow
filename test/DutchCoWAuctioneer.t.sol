// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {GPv2Order} from "cowprotocol/contracts/libraries/GPv2Order.sol";
import {StackTest} from "./helpers/Stack.sol";
import {Data} from "../src/DutchCoWs.sol";
import {DutchCowEscrow} from "../src/escrow.sol";
import {ZooToken} from "./tokens/Zoo.sol";

contract DutchCoWAuctioneerTest is StackTest {
    ZooToken internal sell;
    ZooToken internal buy;

    function setUp() public override {
        super.setUp();
        sell = new ZooToken("SELL", 18);
        buy = new ZooToken("BUY", 18);
    }

    function _base() internal view returns (Data memory) {
        return _data(address(sell), address(buy), 1 ether, 100 ether, 25, 500);
    }

    function test_place_happy_and_pulls_allowance() public {
        Data memory p = _base();
        (address escrow, bytes32 id) = _place(sell, p, 1.5 ether);
        assertEq(sell.balanceOf(escrow), 1.5 ether);
        assertEq(sell.allowance(escrow, relayer), 1 ether);
        assertEq(DutchCowEscrow(escrow).CowOrder(), id);
        assertEq(DutchCowEscrow(escrow)._owner(), address(this));
        assertTrue(id != bytes32(0));
    }

    function test_start_off_either_side() public {
        Data memory p = _base();
        p.startBlock = block.number + 1;
        sell.mint(address(this), 1 ether);
        address escrow = auctioneer.predictEscrow(p);
        sell.approve(escrow, 1 ether);
        vm.expectRevert(bytes("BadStart"));
        auctioneer.placeOrder(p);

        p.startBlock = block.number - 1;
        escrow = auctioneer.predictEscrow(p);
        sell.approve(escrow, 1 ether);
        vm.expectRevert(bytes("BadStart"));
        auctioneer.placeOrder(p);
    }

    function test_validFor_24_reverts_25_places() public {
        Data memory p = _base();
        p.validFor = 24;
        sell.mint(address(this), 2 ether);
        address escrow = auctioneer.predictEscrow(p);
        sell.approve(escrow, 1 ether);
        vm.expectRevert(bytes("AuctionTooShort"));
        auctioneer.placeOrder(p);

        p.validFor = 25;
        (escrow,) = _place(sell, p, 1 ether);
        assertGt(escrow.code.length, 0);
    }

    function test_slippage_bounds() public {
        uint32[4] memory bps = [uint32(50), 51, 9998, 9999];
        bool[4] memory ok = [false, true, true, false];
        for (uint256 i; i < 4; i++) {
            Data memory p = _base();
            p.slippageBps = bps[i];
            sell.mint(address(this), 1 ether);
            address escrow = auctioneer.predictEscrow(p);
            sell.approve(escrow, 1 ether);
            if (!ok[i]) vm.expectRevert(bytes("BadSlippage"));
            auctioneer.placeOrder(p);
        }
    }

    function test_receiver_must_be_sender() public {
        Data memory p = _base();
        p.receiver = address(0xBEEF);
        sell.mint(address(this), 1 ether);
        address escrow = auctioneer.predictEscrow(p);
        sell.approve(escrow, 1 ether);
        vm.expectRevert(bytes("BeneficiaryOrdersNotAllowed"));
        auctioneer.placeOrder(p);
    }

    function test_zero_amounts() public {
        Data memory p = _base();
        p.sellAmount = 0;
        vm.expectRevert(bytes("NothingToSell"));
        auctioneer.placeOrder(p);

        p = _base();
        p.maxAmount = 0;
        sell.mint(address(this), 1 ether);
        address escrow = auctioneer.predictEscrow(p);
        sell.approve(escrow, 1 ether);
        vm.expectRevert(bytes("SellingForNothing"));
        auctioneer.placeOrder(p);
    }

    function test_allowance_ladder() public {
        uint256 sellAmount = 1 ether;
        _expectAllowance(sellAmount - 1, true, 1);
        _expectAllowance(sellAmount, false, 2);
        _expectAllowance(2 * sellAmount - 1, false, 3);
        _expectAllowance(2 * sellAmount, true, 4);
    }

    function _expectAllowance(uint256 amount, bool bad, uint256 tag) internal {
        Data memory p = _base();
        p.maxAmount = 100 ether + tag;
        sell.mint(address(this), amount);
        p.receiver = address(this);
        p.startBlock = block.number;
        address escrow = auctioneer.predictEscrow(p);
        sell.approve(escrow, amount);
        if (bad) vm.expectRevert(bytes("BadApproval"));
        auctioneer.placeOrder(p);
    }

    function test_max_approval_rejected_by_escrow() public {
        Data memory p = _base();
        sell.mint(address(this), 1 ether);
        p.receiver = address(this);
        p.startBlock = block.number;
        address escrow = auctioneer.predictEscrow(p);
        sell.approve(escrow, type(uint256).max);
        vm.expectRevert(bytes("BadApproval"));
        auctioneer.placeOrder(p);
    }

    function test_double_sell_overflow_panics() public {
        Data memory p = _base();
        p.sellAmount = type(uint256).max;
        sell.mint(address(this), type(uint256).max);
        p.receiver = address(this);
        p.startBlock = block.number;
        address escrow = auctioneer.predictEscrow(p);
        sell.approve(escrow, type(uint256).max);
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", uint256(0x11)));
        auctioneer.placeOrder(p);
    }

    function test_step_size_zero_never_decays() public {
        Data memory p = _base();
        p.maxAmount = 10;
        p.slippageBps = 51;
        p.validFor = 25;
        p.receiver = address(this);
        p.startBlock = block.number;
        sell.mint(address(this), 1 ether);
        address escrow = auctioneer.predictEscrow(p);
        sell.approve(escrow, 1 ether);
        vm.expectRevert(bytes("PreventStepSizeUnderflow"));
        auctioneer.placeOrder(p);
    }

    function test_huge_max_overflows_floor_after_hold() public {
        Data memory p = _base();
        p.maxAmount = type(uint256).max;
        p.receiver = address(this);
        p.startBlock = block.number;
        sell.mint(address(this), 1 ether);
        address escrow = auctioneer.predictEscrow(p);
        sell.approve(escrow, 1 ether);
        vm.expectRevert(bytes("PricePanicPreventer"));
        auctioneer.placeOrder(p);
    }

    function test_release_dust_and_tip() public {
        _checkRelease(999, 600, 999, 0);
        _checkRelease(1000, 600, 999, 1);
        _checkRelease(1001, 600, 1000, 1);
    }

    function test_release_window_and_second_call() public {
        Data memory p = _base();
        (address escrow,) = _place(sell, p, 1.5 ether);
        vm.roll(p.startBlock + p.validFor);
        vm.expectRevert(bytes("AuctionInProgress"));
        DutchCowEscrow(escrow).releaseFunds();
        vm.roll(p.startBlock + p.validFor + 1);
        DutchCowEscrow(escrow).releaseFunds();
        uint256 ownerAfter = sell.balanceOf(address(this));
        DutchCowEscrow(escrow).releaseFunds();
        assertEq(sell.balanceOf(address(this)), ownerAfter);
        assertEq(sell.balanceOf(escrow), 0);
    }

    function test_tax_shortfall_and_cushion_refund() public {
        ZooToken taxed = new ZooToken("TAX", 18);
        taxed.configureTax(ZooToken.TaxMode.Recipient, 1000, address(0), address(0));
        Data memory p = _data(address(taxed), address(buy), 1 ether, 100 ether, 25, 500);
        taxed.mint(address(this), 1 ether);
        p.receiver = address(this);
        p.startBlock = block.number;
        address escrow = auctioneer.predictEscrow(p);
        taxed.approve(escrow, 1 ether);
        vm.expectRevert(bytes("ShortAfterFee"));
        auctioneer.placeOrder(p);

        uint256 cushion = (uint256(1 ether) * 10_000 + 8999) / 9000;
        assertLt(cushion, 2 ether);
        (escrow,) = _place(taxed, p, cushion);
        assertGe(taxed.balanceOf(escrow), 1 ether);
        vm.roll(p.startBlock + p.validFor + 1);
        uint256 beforeBal = taxed.balanceOf(address(this));
        DutchCowEscrow(escrow).releaseFunds();
        assertEq(taxed.balanceOf(escrow), 0);
        assertGt(taxed.balanceOf(address(this)), beforeBal);
    }

    function quote(address escrow, Data calldata p) external view {
        cow.getTradeableOrderWithSignature(escrow, _params(p, address(this)), "", new bytes32[](0));
    }

    function _checkRelease(uint256 pulled, uint256 sellAmount, uint256 ownerGets, uint256 tip) internal {
        ZooToken token = new ZooToken("DUST", 0);
        Data memory p = _data(address(token), address(buy), sellAmount, 500, 25, 500);
        token.mint(address(this), pulled);
        p.receiver = address(this);
        p.startBlock = block.number;
        address escrow = auctioneer.predictEscrow(p);
        token.approve(escrow, pulled);
        auctioneer.placeOrder(p);
        vm.roll(p.startBlock + p.validFor + 1);
        address tipper = address(0x71B);
        uint256 ownerBefore = token.balanceOf(address(this));
        vm.prank(tipper);
        DutchCowEscrow(escrow).releaseFunds();
        assertEq(token.balanceOf(address(this)) - ownerBefore, ownerGets);
        assertEq(token.balanceOf(tipper), tip);
    }
}
