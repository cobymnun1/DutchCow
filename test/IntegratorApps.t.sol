// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {IDutchCoWAuctioneer} from "../src/IDutchCoW.sol";
import {DutchCowEscrow} from "../src/escrow.sol";
import {StackTest} from "./helpers/Stack.sol";
import {ZooToken} from "./tokens/Zoo.sol";
import {
    TreasurySeller, DcaBot, ProtocolFeeSeller, VaultRebalancer, SmartWallet, SweepWallet, Keeper,
    BadUnlimited, BadLowApproval, BadReceiver, BadStart, DuplicatePlacer, MultiAuction, ReentrantPlacer
} from "./apps/Integrators.sol";

contract IntegratorAppsTest is StackTest {
    ZooToken internal sell;
    ZooToken internal buy;

    function setUp() public override {
        super.setUp();
        sell = new ZooToken("SELL", 18);
        buy = new ZooToken("BUY", 6);
    }

    function test_treasury_dca_fee_rebalance_wallet_sweep_keeper() public {
        TreasurySeller treasury = new TreasurySeller(address(auctioneer), address(sell));
        sell.mint(address(treasury), 2 ether);
        treasury.sell(address(buy), 1 ether, 100 ether, 25, 500, 1.2 ether);
        assertGt(treasury.lastEscrow().code.length, 0);
        assertEq(sell.balanceOf(treasury.lastEscrow()), 1.2 ether);

        DcaBot dca = new DcaBot(address(auctioneer), address(sell));
        sell.mint(address(dca), 3 ether);
        address first = dca.slice(address(buy), 1 ether, 10 ether, 25, 200, 1 ether);
        address second = dca.slice(address(buy), 1 ether, 10 ether, 25, 200, 1 ether);
        assertTrue(first != second);
        assertEq(dca.slices(), 2);

        ProtocolFeeSeller fees = new ProtocolFeeSeller(address(auctioneer), address(sell), address(0xFEE), 100);
        sell.mint(address(this), 1 ether);
        sell.approve(address(fees), 1 ether);
        fees.sellWithFee(address(this), address(buy), 1 ether, 50 ether, 25, 500);
        assertEq(sell.balanceOf(address(0xFEE)), 0.01 ether);

        VaultRebalancer vault = new VaultRebalancer(address(auctioneer), address(sell), address(buy), 1_000_000);
        sell.mint(address(vault), 1 ether);
        assertGt(vault.rebalance(1 ether, 25, 500).code.length, 0);

        SmartWallet wallet = new SmartWallet(address(this), address(auctioneer));
        sell.mint(address(wallet), 1 ether);
        assertGt(wallet.place(address(sell), address(buy), 1 ether, 10 ether, 25, 500, 1 ether).code.length, 0);
        vm.prank(address(0xBAD));
        vm.expectRevert(bytes("not owner"));
        wallet.place(address(sell), address(buy), 1 ether, 10 ether, 25, 500, 1 ether);

        SweepWallet sweeper = new SweepWallet(address(auctioneer), address(0xE0D));
        sell.mint(address(sweeper), 1 ether);
        sweeper.place(address(sell), address(buy), 1 ether, 10 ether, 30, 500, 1 ether);
        buy.mint(address(sweeper), 42);
        sweeper.sweep(address(buy));
        assertEq(buy.balanceOf(address(0xE0D)), 42);

        Keeper keeper = new Keeper();
        vm.roll(block.number + 26);
        uint256 ownerBefore = sell.balanceOf(address(treasury));
        keeper.releaseAndForward(treasury.lastEscrow(), address(sell), address(0x71B));
        assertGt(sell.balanceOf(address(treasury)), ownerBefore);
        assertGt(sell.balanceOf(address(0x71B)), 0);
        assertEq(IDutchCoWAuctioneer(address(auctioneer)).handler(), address(handler));
    }

    function test_bad_integrators_are_blocked() public {
        sell.mint(address(this), 100 ether);

        BadUnlimited unlimited = new BadUnlimited(address(auctioneer));
        sell.mint(address(unlimited), 1 ether);
        vm.expectRevert(bytes("BadApproval"));
        unlimited.place(address(sell), address(buy), 1 ether, 10 ether);

        BadLowApproval low = new BadLowApproval(address(auctioneer));
        sell.mint(address(low), 1 ether);
        vm.expectRevert(bytes("BadApproval"));
        low.place(address(sell), address(buy), 1 ether, 10 ether);

        BadReceiver wrongRecv = new BadReceiver(address(auctioneer));
        sell.mint(address(wrongRecv), 1 ether);
        vm.expectRevert(bytes("BeneficiaryOrdersNotAllowed"));
        wrongRecv.place(address(sell), address(buy), address(0xBEEF));

        BadStart late = new BadStart(address(auctioneer));
        sell.mint(address(late), 2 ether);
        vm.expectRevert(bytes("BadStart"));
        late.place(address(sell), address(buy), int256(1));
        vm.expectRevert(bytes("BadStart"));
        late.place(address(sell), address(buy), int256(-1));

        DuplicatePlacer dup = new DuplicatePlacer(address(auctioneer));
        sell.mint(address(dup), 2 ether);
        vm.expectRevert(bytes("BadApproval"));
        dup.placeTwice(address(sell), address(buy));

        MultiAuction multi = new MultiAuction(address(auctioneer));
        sell.mint(address(multi), 2 ether);
        (address a, address b) = multi.placeTwo(address(sell), address(buy));
        assertTrue(a != b);
        assertEq(sell.balanceOf(a), 1 ether);
        assertEq(sell.balanceOf(b), 1 ether);

        ZooToken hook = new ZooToken("HOOK", 18);
        ReentrantPlacer attacker = new ReentrantPlacer(address(auctioneer));
        attacker.arm(address(hook), address(buy));
        hook.setReenter(address(attacker));
        hook.mint(address(attacker), 3 ether);
        vm.expectRevert(abi.encodeWithSignature("ReentrancyGuardReentrantCall()"));
        attacker.place();
    }

    function test_release_is_permissionless_noop_the_second_time() public {
        TreasurySeller treasury = new TreasurySeller(address(auctioneer), address(sell));
        sell.mint(address(treasury), 1500);
        treasury.sell(address(buy), 800, 1_000, 25, 500, 1500);
        vm.roll(block.number + 26);
        Keeper keeper = new Keeper();
        keeper.release(treasury.lastEscrow());
        uint256 left = sell.balanceOf(address(treasury));
        keeper.release(treasury.lastEscrow());
        assertEq(sell.balanceOf(address(treasury)), left);
        assertEq(DutchCowEscrow(treasury.lastEscrow())._owner(), address(treasury));
    }
}
