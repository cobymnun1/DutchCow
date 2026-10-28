// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "cowprotocol/contracts/interfaces/IERC20.sol";
import {DutchAuction} from "../DutchCoWs.sol";
import {TestAuctionVault} from "../src/TestAuctionVault.sol";

contract CreateLocalForkOrder is Script {
    function run() external {
        TestAuctionVault vault = TestAuctionVault(vm.envAddress("VAULT"));
        DutchAuction handler = DutchAuction(vm.envAddress("HANDLER"));
        IERC20 sellToken = IERC20(vm.envAddress("SELL_TOKEN"));
        IERC20 buyToken = IERC20(vm.envAddress("BUY_TOKEN"));
        address receiver = vm.envAddress("RECEIVER");
        uint256 sellAmount = vm.envUint("SELL_AMOUNT");
        uint256 maxAmount = vm.envUint("MAX_AMOUNT");
        uint32 validFor = uint32(vm.envUint("VALID_FOR"));
        uint32 slippageBps = uint32(vm.envUint("SLIPPAGE_BPS"));
        bytes32 salt = vm.envBytes32("SALT");
        uint256 startBlock = block.number + 5;

        DutchAuction.Data memory data = DutchAuction.Data({
            sellToken: sellToken,
            buyToken: buyToken,
            sellAmount: sellAmount,
            maxAmount: maxAmount,
            receiver: receiver,
            startBlock: startBlock,
            validFor: validFor,
            slippageBps: slippageBps
        });

        vm.startBroadcast();
        vault.createOrder(address(handler), salt, abi.encode(data));
        vm.stopBroadcast();
    }
}
