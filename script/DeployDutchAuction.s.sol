// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Script} from "forge-std/Script.sol";
import {DutchAuction} from "../DutchCoWs.sol";

contract DeployDutchAuction is Script {
    function run() external returns (DutchAuction deployed) {
        vm.startBroadcast();
        deployed = new DutchAuction();
        vm.stopBroadcast();
    }
}
