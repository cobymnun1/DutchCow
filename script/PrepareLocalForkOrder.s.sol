// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "cowprotocol/contracts/interfaces/IERC20.sol";
import {IConditionalOrder} from "composable-cow/src/interfaces/IConditionalOrder.sol";
import {DutchAuction} from "../DutchCoWs.sol";
import {TestAuctionVault} from "../src/TestAuctionVault.sol";

contract PrepareLocalForkOrder is Script {
    address private constant COMPOSABLE_COW = 0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74;
    address private constant COW_VAULT_RELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;

    event LocalAuctionConfigured(
        address indexed handler,
        address indexed vault,
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 maxAmount,
        uint256 startBlock,
        uint32 validFor,
        uint32 slippageBps,
        bytes32 salt,
        bytes staticInput
    );

    function run() external returns (DutchAuction handler, TestAuctionVault vault) {
        address vaultOwner = vm.envAddress("VAULT_OWNER");
        IERC20 sellToken = IERC20(vm.envAddress("SELL_TOKEN"));
        IERC20 buyToken = IERC20(vm.envAddress("BUY_TOKEN"));
        address receiver = vm.envAddress("RECEIVER");
        uint256 sellAmount = vm.envUint("SELL_AMOUNT");
        uint256 maxAmount = vm.envUint("MAX_AMOUNT");
        uint32 validFor = uint32(vm.envUint("VALID_FOR"));
        uint32 slippageBps = uint32(vm.envUint("SLIPPAGE_BPS"));
        bytes32 salt = vm.envBytes32("SALT");
        uint256 startBlock = block.number + 5;

        vm.startBroadcast();
        handler = new DutchAuction();
        vault = new TestAuctionVault(vaultOwner, COMPOSABLE_COW, COW_VAULT_RELAYER);
        vault.approveCow(sellToken, sellAmount);

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
        bytes memory staticInput = abi.encode(data);
        vault.createOrder(
            address(handler),
            salt,
            staticInput
        );
        vm.stopBroadcast();

        emit LocalAuctionConfigured(
            address(handler),
            address(vault),
            address(sellToken),
            address(buyToken),
            sellAmount,
            maxAmount,
            startBlock,
            validFor,
            slippageBps,
            salt,
            staticInput
        );
    }
}
