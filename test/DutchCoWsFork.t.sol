// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Test} from "forge-std/Test.sol";
import {ComposableCoW} from "composable-cow/src/ComposableCoW.sol";
import {GPv2Settlement} from "cowprotocol/contracts/GPv2Settlement.sol";
import {GPv2Order} from "cowprotocol/contracts/libraries/GPv2Order.sol";
import {DutchAuction, Data} from "../src/DutchCoWs.sol";
import {DutchCoWAuctioneer} from "../src/Aunctioneer.sol";
import {IConditionalOrder} from "composable-cow/src/interfaces/IConditionalOrder.sol";
import {IERC20} from "cowprotocol/contracts/interfaces/IERC20.sol";
import {ZooToken} from "./tokens/Zoo.sol";

/// @notice Runs only when forge is pointed at a fork where the CoW settlement has code.
contract DutchCoWsForkTest is Test {
    address constant SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address constant CANON = 0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74;

    function test_fork_quotes_through_canonical_composable_cow() public {
        if (SETTLEMENT.code.length == 0) vm.skip(true);
        if (CANON.code.length == 0) {
            ComposableCoW fresh = new ComposableCoW(SETTLEMENT);
            vm.etch(CANON, address(fresh).code);
        }
        DutchAuction handler = new DutchAuction();
        DutchCoWAuctioneer auctioneer = new DutchCoWAuctioneer(address(handler), ComposableCoW(CANON), GPv2Settlement(payable(SETTLEMENT)));
        ZooToken sell = new ZooToken("FORK", 18);
        ZooToken buy = new ZooToken("FORKBUY", 18);
        sell.mint(address(this), 1 ether);
        Data memory p = Data({
            sellToken: IERC20(address(sell)),
            buyToken: IERC20(address(buy)),
            sellAmount: 1 ether,
            maxAmount: 100 ether,
            receiver: address(this),
            startBlock: block.number,
            validFor: 25,
            slippageBps: 500
        });
        address escrow = auctioneer.predictEscrow(p);
        sell.approve(escrow, 1 ether);
        bytes32 id = auctioneer.placeOrder(p);
        assertTrue(id != bytes32(0));
        (GPv2Order.Data memory order,) = ComposableCoW(CANON).getTradeableOrderWithSignature(
            escrow,
            _params(handler, p),
            "",
            new bytes32[](0)
        );
        assertEq(order.buyAmount, 100 ether);
        assertEq(order.receiver, address(this));
    }

    function _params(DutchAuction handler, Data memory p)
        internal view returns (IConditionalOrder.ConditionalOrderParams memory params)
    {
        params = IConditionalOrder.ConditionalOrderParams({
            handler: IConditionalOrder(address(handler)),
            salt: keccak256(abi.encode(address(this), p)),
            staticInput: abi.encode(p)
        });
    }
}
