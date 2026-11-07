// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Script, console} from "forge-std/Script.sol";
import {ZooToken} from "../test/tokens/Zoo.sol";

/// @notice Deploys a plain or taxed zoo token and mints it to the broadcaster.
contract DeployMockToken is Script {
    function run() external returns (ZooToken token) {
        address recipient = vm.envAddress("CLIENT");
        uint256 amount = vm.envUint("SELL_AMOUNT");
        uint256 taxBps = vm.envOr("TAX_BPS", uint256(0));
        uint8 decimals_ = uint8(vm.envOr("DECIMALS", uint256(18)));
        vm.startBroadcast();
        token = new ZooToken(taxBps == 0 ? "SELL" : "TAXED", decimals_);
        if (taxBps > 0) {
            token.configureTax(ZooToken.TaxMode.Recipient, taxBps, vm.envAddress("SETTLEMENT"), vm.envAddress("VAULT_RELAYER"));
        }
        token.mint(recipient, amount);
        vm.stopBroadcast();
        console.log("token", address(token));
    }
}
