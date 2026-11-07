// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "cowprotocol/contracts/interfaces/IERC20.sol";
import {GPv2Settlement} from "cowprotocol/contracts/GPv2Settlement.sol";
import {GPv2Trade} from "cowprotocol/contracts/libraries/GPv2Trade.sol";
import {GPv2Interaction} from "cowprotocol/contracts/libraries/GPv2Interaction.sol";
import {ZooToken} from "../test/tokens/Zoo.sol";

/// @notice Settles one posted EIP-1271 order through the forked GPv2 settlement.
///         Clearing prices are [buyAmount, sellAmount], so the receiver is paid exactly buyAmount.
contract SettlePostedOrder is Script {
    function run() external {
        GPv2Settlement settlement = GPv2Settlement(payable(vm.envAddress("SETTLEMENT")));
        IERC20 sellToken = IERC20(vm.envAddress("SELL_TOKEN"));
        IERC20 buyToken = IERC20(vm.envAddress("BUY_TOKEN"));
        uint256 sellAmount = vm.envUint("SELL_AMOUNT");
        uint256 buyAmount = vm.envUint("BUY_AMOUNT");

        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = sellToken;
        tokens[1] = buyToken;

        uint256[] memory prices = new uint256[](2);
        prices[0] = buyAmount;
        prices[1] = sellAmount;

        GPv2Trade.Data[] memory trades = new GPv2Trade.Data[](1);
        trades[0] = GPv2Trade.Data({
            sellTokenIndex: 0,
            buyTokenIndex: 1,
            receiver: vm.envAddress("RECEIVER"),
            sellAmount: sellAmount,
            buyAmount: buyAmount,
            validTo: uint32(vm.envUint("VALID_TO")),
            appData: vm.envBytes32("APP_DATA"),
            feeAmount: 0,
            flags: uint256(2) << 5,
            executedAmount: sellAmount,
            signature: vm.envBytes("SIGNATURE")
        });

        GPv2Interaction.Data[][3] memory interactions;
        interactions[0] = new GPv2Interaction.Data[](0);
        interactions[1] = new GPv2Interaction.Data[](0);
        interactions[2] = new GPv2Interaction.Data[](0);

        vm.startBroadcast();
        ZooToken(address(buyToken)).mint(address(settlement), buyAmount);
        settlement.settle(tokens, prices, trades, interactions);
        vm.stopBroadcast();
        console.log("settled", vm.envAddress("RECEIVER"));
    }
}
