// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {IDutchCoWAuctioneer, AuctionParams} from "../src/IDutchCoW.sol";

/// @notice Holds the sell token. Sending ETH calls the real predict, approve, placeOrder path.
contract RealDutchCowTest {
    IDutchCoWAuctioneer public immutable auctioneer;

    constructor(IDutchCoWAuctioneer auctioneer_) {
        auctioneer = auctioneer_;
    }

    function place(
        address sellToken,
        address buyToken,
        uint256 sellAmount,
        uint256 maxAmount,
        uint32 validFor,
        uint32 slippageBps
    ) external payable {
        require(msg.value > 0, "NoMoney");
        AuctionParams memory params = AuctionParams({
            sellToken: sellToken,
            buyToken: buyToken,
            sellAmount: sellAmount,
            maxAmount: maxAmount,
            receiver: address(this),
            startBlock: block.number,
            validFor: validFor,
            slippageBps: slippageBps
        });
        address escrow = auctioneer.predictEscrow(params);
        (bool ok, bytes memory data) = sellToken.call(abi.encodeWithSelector(0x095ea7b3, escrow, sellAmount));
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve");
        auctioneer.placeOrder(params);
    }
}
