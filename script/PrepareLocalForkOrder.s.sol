// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Script} from "forge-std/Script.sol";
import {ComposableCoW} from "composable-cow/src/ComposableCoW.sol";
import {GPv2Settlement} from "cowprotocol/contracts/GPv2Settlement.sol";
import {DutchAuction} from "../src/DutchCoWs.sol";
import {DutchCoWAuctioneer} from "../src/Aunctioneer.sol";

contract PrepareLocalForkOrder is Script {
    address private constant COMPOSABLE_COW = 0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74;
    address private constant SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;

    event LocalAuctioneerConfigured(address indexed handler, address indexed auctioneer, address indexed implementation);

    function run() external returns (DutchAuction handler, DutchCoWAuctioneer auctioneer) {
        vm.startBroadcast();
        handler = new DutchAuction();
        auctioneer = new DutchCoWAuctioneer(address(handler), ComposableCoW(COMPOSABLE_COW), GPv2Settlement(payable(SETTLEMENT)));
        vm.stopBroadcast();

        emit LocalAuctioneerConfigured(address(handler), address(auctioneer), auctioneer.implementation());
    }
}
