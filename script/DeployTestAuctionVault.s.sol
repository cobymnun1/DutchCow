// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Script} from "forge-std/Script.sol";
import {TestAuctionVault} from "../src/TestAuctionVault.sol";

contract DeployTestAuctionVault is Script {
    address private constant COMPOSABLE_COW = 0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74;
    address private constant COW_VAULT_RELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;

    function run() external returns (TestAuctionVault vault) {
        address vaultOwner = vm.envAddress("VAULT_OWNER");

        vm.startBroadcast();
        vault = new TestAuctionVault(vaultOwner, COMPOSABLE_COW, COW_VAULT_RELAYER);
        vm.stopBroadcast();
    }
}
