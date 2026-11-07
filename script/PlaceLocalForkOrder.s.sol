// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Script} from "forge-std/Script.sol";
import {DutchCoWAuctioneer} from "../src/Aunctioneer.sol";
import {TreasurySeller} from "../test/apps/Integrators.sol";
import {ZooToken} from "../test/tokens/Zoo.sol";

/// @notice Places one auction from a treasury contract so startBlock is set in the same transaction.
contract PlaceLocalForkOrder is Script {
    function run() external returns (bytes32 orderId, address escrow, address treasury) {
        DutchCoWAuctioneer auctioneer = DutchCoWAuctioneer(vm.envAddress("AUCTIONEER"));
        address sellToken = vm.envAddress("SELL_TOKEN");
        address buyToken = vm.envAddress("BUY_TOKEN");
        uint256 sellAmount = vm.envUint("SELL_AMOUNT");
        uint256 maxAmount = vm.envUint("MAX_AMOUNT");
        uint32 validFor = uint32(vm.envUint("VALID_FOR"));
        uint32 slippageBps = uint32(vm.envUint("SLIPPAGE_BPS"));
        uint256 allowance = vm.envOr("ALLOWANCE", sellAmount);
        uint256 fund = vm.envOr("FUND", allowance);

        vm.startBroadcast();
        TreasurySeller app = new TreasurySeller(address(auctioneer), sellToken);
        ZooToken(sellToken).transfer(address(app), fund);
        app.sell(buyToken, sellAmount, maxAmount, validFor, slippageBps, allowance);
        vm.stopBroadcast();
        orderId = app.lastOrder();
        escrow = app.lastEscrow();
        treasury = address(app);
    }
}
