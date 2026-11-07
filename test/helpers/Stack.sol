// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Test} from "forge-std/Test.sol";
import {ComposableCoW} from "composable-cow/src/ComposableCoW.sol";
import {GPv2Settlement} from "cowprotocol/contracts/GPv2Settlement.sol";
import {IERC20} from "cowprotocol/contracts/interfaces/IERC20.sol";
import {GPv2Order} from "cowprotocol/contracts/libraries/GPv2Order.sol";
import {IConditionalOrder} from "composable-cow/src/interfaces/IConditionalOrder.sol";
import {DutchAuction, Data} from "../../src/DutchCoWs.sol";
import {DutchCoWAuctioneer} from "../../src/Aunctioneer.sol";
import {DutchCowEscrow} from "../../src/escrow.sol";
import {ZooToken} from "../tokens/Zoo.sol";

contract MiniSettlement {
    address public vaultRelayer;
    constructor(address relayer) { vaultRelayer = relayer; }
    function domainSeparator() external pure returns (bytes32) { return keccak256("dutchcow-test-domain"); }
}

contract StackTest is Test {
    ComposableCoW internal cow;
    DutchAuction internal handler;
    DutchCoWAuctioneer internal auctioneer;
    address internal relayer = address(0xC92E);

    function setUp() public virtual {
        MiniSettlement mini = new MiniSettlement(relayer);
        cow = new ComposableCoW(address(mini));
        handler = new DutchAuction();
        auctioneer = new DutchCoWAuctioneer(address(handler), cow, GPv2Settlement(payable(address(mini))));
    }

    function _place(ZooToken token, Data memory p, uint256 allowance)
        internal returns (address escrow, bytes32 id)
    {
        token.mint(address(this), allowance > p.sellAmount ? allowance : p.sellAmount);
        p.receiver = address(this);
        p.startBlock = block.number;
        escrow = auctioneer.predictEscrow(p);
        (bool ok, bytes memory data) = address(token).call(
            abi.encodeWithSelector(token.approve.selector, escrow, allowance)
        );
        require(ok, "approve");
        if (data.length > 0) require(abi.decode(data, (bool)), "approve false");
        id = auctioneer.placeOrder(p);
    }

    function _params(Data memory p, address placer)
        internal view returns (IConditionalOrder.ConditionalOrderParams memory params)
    {
        params = IConditionalOrder.ConditionalOrderParams({
            handler: IConditionalOrder(address(handler)),
            salt: keccak256(abi.encode(placer, p)),
            staticInput: abi.encode(p)
        });
    }

    function _quote(address escrow, Data memory p, address placer)
        internal view returns (GPv2Order.Data memory order, bytes memory signature)
    {
        escrow;
        (order, signature) = cow.getTradeableOrderWithSignature(escrow, _params(p, placer), "", new bytes32[](0));
    }

    function _data(address sell, address buy, uint256 sellAmount, uint256 maxAmount, uint32 validFor, uint32 slippage)
        internal view returns (Data memory p)
    {
        p = Data({
            sellToken: IERC20(sell),
            buyToken: IERC20(buy),
            sellAmount: sellAmount,
            maxAmount: maxAmount,
            receiver: address(this),
            startBlock: block.number,
            validFor: validFor,
            slippageBps: slippage
        });
    }
}
