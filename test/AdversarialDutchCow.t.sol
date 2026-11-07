// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {IConditionalOrder} from "composable-cow/src/interfaces/IConditionalOrder.sol";
import {DutchCowEscrow} from "../src/escrow.sol";
import {Data} from "../src/DutchCoWs.sol";
import {StackTest} from "./helpers/Stack.sol";
import {ZooToken} from "./tokens/Zoo.sol";

contract AdversarialDutchCowTest is StackTest {
    ZooToken internal buy;

    function setUp() public override {
        super.setUp();
        buy = new ZooToken("BUY", 18);
    }

    function test_decimals_usdt_and_sender_extra_tax_place() public {
        uint8[4] memory decs = [uint8(18), 8, 6, 0];
        for (uint256 i; i < 4; i++) {
            ZooToken token = new ZooToken("PLAIN", decs[i]);
            _placeOk(token, 1_000_000, 1_000_000);
        }

        ZooToken usdt = new ZooToken("USDT", 6);
        usdt.setFlags(true, false, true, false, false, false);
        _placeOk(usdt, 1_000_000, 1_000_000);

        ZooToken extra = new ZooToken("EXTRA", 18);
        extra.configureTax(ZooToken.TaxMode.SenderExtra, 500, address(0), address(0));
        extra.mint(address(this), 2 ether);
        Data memory p = _data(address(extra), address(buy), 1 ether, 10 ether, 25, 500);
        p.receiver = address(this);
        p.startBlock = block.number;
        address escrow = auctioneer.predictEscrow(p);
        extra.approve(escrow, 1 ether);
        auctioneer.placeOrder(p);
        assertEq(extra.balanceOf(escrow), 1 ether);
    }

    function test_false_return_reverts() public {
        ZooToken token = new ZooToken("FALSE", 18);
        token.setFlags(false, true, false, false, false, false);
        token.mint(address(this), 1 ether);
        Data memory p = _data(address(token), address(buy), 1 ether, 10 ether, 25, 500);
        p.receiver = address(this);
        p.startBlock = block.number;
        address escrow = auctioneer.predictEscrow(p);
        token.approve(escrow, 1 ether);
        vm.expectRevert();
        auctioneer.placeOrder(p);
    }

    function test_recipient_tax_and_burn_need_a_cushion() public {
        _taxPlaces(ZooToken.TaxMode.Recipient, 100);
        _taxPlaces(ZooToken.TaxMode.Recipient, 500);
        _taxPlaces(ZooToken.TaxMode.Recipient, 1000);
        _taxPlaces(ZooToken.TaxMode.Burn, 1000);
    }

    function test_vault_only_tax_does_not_tax_the_escrow_pull() public {
        ZooToken token = new ZooToken("VAULT", 18);
        token.configureTax(ZooToken.TaxMode.VaultOnly, 1000, address(0x5E771E), relayer);
        (address escrow) = _placeOk(token, 1 ether, 1 ether);
        assertEq(token.balanceOf(escrow), 1 ether);
        vm.prank(relayer);
        token.transferFrom(escrow, address(0x5E771E), 1 ether);
        assertEq(token.balanceOf(address(0x5E771E)), 0.9 ether);
    }

    function test_uint96_rejects_unlimited_and_accepts_a_fit() public {
        ZooToken token = new ZooToken("UNI", 18);
        token.setFlags(false, false, false, true, false, false);
        token.mint(address(this), 100);
        Data memory p = _data(address(token), address(buy), 100, 1_000, 25, 500);
        p.receiver = address(this);
        p.startBlock = block.number;
        address escrow = auctioneer.predictEscrow(p);
        vm.expectRevert(bytes("Uint96"));
        token.approve(escrow, type(uint256).max);
        token.approve(escrow, 100);
        auctioneer.placeOrder(p);
        assertEq(token.balanceOf(escrow), 100);
    }

    function test_blacklist_and_pause_brick_release() public {
        ZooToken blocked = new ZooToken("BLACK", 18);
        (address escrow, Data memory p) = _open(blocked, 1 ether);
        blocked.setBlocked(escrow, true);
        vm.roll(p.startBlock + p.validFor + 1);
        DutchCowEscrow(escrow).releaseFunds();
        assertEq(blocked.balanceOf(escrow), 1 ether);
        blocked.setBlocked(escrow, false);
        DutchCowEscrow(escrow).releaseFunds();
        assertEq(blocked.balanceOf(escrow), 0);

        ZooToken paused = new ZooToken("PAUSE", 18);
        (escrow, p) = _open(paused, 1 ether);
        paused.setPaused(true);
        vm.roll(p.startBlock + p.validFor + 1);
        DutchCowEscrow(escrow).releaseFunds();
        assertEq(paused.balanceOf(escrow), 1 ether);
        paused.setPaused(false);
        DutchCowEscrow(escrow).releaseFunds();
        assertEq(paused.balanceOf(escrow), 0);
    }

    function test_rebase_down_marks_filled_rebase_up_keeps_quoting() public {
        ZooToken token = new ZooToken("REBASE", 18);
        (address escrow, Data memory p) = _open(token, 1 ether);
        token.setRebaseBps(-2000);
        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.PollNever.selector, "Filled"));
        this.quote(escrow, p);
        token.setRebaseBps(1000);
        this.quote(escrow, p);
    }

    function test_lying_balance_hides_a_fill_or_blocks_placement() public {
        ZooToken token = new ZooToken("LIE", 18);
        token.mint(address(this), 1 ether);
        Data memory p = _data(address(token), address(buy), 1 ether, 10 ether, 25, 500);
        p.receiver = address(this);
        p.startBlock = block.number;
        address escrow = auctioneer.predictEscrow(p);
        token.approve(escrow, 1 ether);
        token.setFlags(false, false, false, false, false, true);
        vm.expectRevert(bytes("ShortAfterFee"));
        auctioneer.placeOrder(p);

        token.setFlags(false, false, false, false, true, false);
        auctioneer.placeOrder(p);
        vm.prank(relayer);
        token.transferFrom(escrow, address(0xB0B), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IConditionalOrder.PollNever.selector, "Filled"));
        this.quote(escrow, p);
    }

    function _taxPlaces(ZooToken.TaxMode mode, uint256 bps) internal {
        ZooToken token = new ZooToken("TAX", 18);
        token.configureTax(mode, bps, address(0), address(0));
        uint256 sellAmount = 1 ether;
        uint256 bare = sellAmount;
        token.mint(address(this), bare);
        Data memory p = _data(address(token), address(buy), sellAmount, 10 ether, 25, 500);
        p.receiver = address(this);
        p.startBlock = block.number;
        address escrow = auctioneer.predictEscrow(p);
        token.approve(escrow, bare);
        vm.expectRevert(bytes("ShortAfterFee"));
        auctioneer.placeOrder(p);

        uint256 cushion = (sellAmount * 10_000 + (10_000 - bps - 1)) / (10_000 - bps);
        _placeOk(token, sellAmount, cushion);
    }

    function _placeOk(ZooToken token, uint256 sellAmount, uint256 allowance) internal returns (address escrow) {
        Data memory p = _data(address(token), address(buy), sellAmount, 10 ether, 25, 500);
        (escrow,) = _place(token, p, allowance);
        assertGe(token.balanceOf(escrow), sellAmount);
    }

    function _open(ZooToken token, uint256 amount) internal returns (address escrow, Data memory p) {
        p = _data(address(token), address(buy), amount, 10 ether, 25, 500);
        (escrow,) = _place(token, p, amount);
    }

    function quote(address escrow, Data calldata p) external view {
        cow.getTradeableOrderWithSignature(escrow, _params(p, address(this)), "", new bytes32[](0));
    }
}
