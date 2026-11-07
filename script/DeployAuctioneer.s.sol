// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Script, console} from "forge-std/Script.sol";
import {ComposableCoW} from "composable-cow/src/ComposableCoW.sol";
import {GPv2Settlement} from "cowprotocol/contracts/GPv2Settlement.sol";
import {DutchAuction} from "../src/DutchCoWs.sol";
import {DutchCoWAuctioneer} from "../src/Aunctioneer.sol";

/// @notice Deploys the handler and auctioneer against an existing ComposableCoW and settlement.
contract DeployAuctioneer is Script {
    function run() external returns (DutchAuction handler, DutchCoWAuctioneer auctioneer) {
        address cow = vm.envAddress("COMPOSABLE_COW");
        address payable settlement = payable(vm.envAddress("SETTLEMENT"));
        vm.startBroadcast();
        handler = new DutchAuction();
        auctioneer = new DutchCoWAuctioneer(address(handler), ComposableCoW(cow), GPv2Settlement(settlement));
        vm.stopBroadcast();
        console.log("handler", address(handler));
        console.log("auctioneer", address(auctioneer));
        console.log("implementation", auctioneer.implementation());
        console.log("vaultRelayer", auctioneer.vaultRelayer());
    }
}

/// @notice Deploys ComposableCoW bound to the fork settlement. The runtime is then copied
///         to the canonical address with anvil_setCode.
contract DeployComposableCoW is Script {
    function run() external returns (ComposableCoW cow) {
        address settlement = vm.envAddress("SETTLEMENT");
        vm.startBroadcast();
        cow = new ComposableCoW(settlement);
        vm.stopBroadcast();
        console.log("composableCow", address(cow));
    }
}
