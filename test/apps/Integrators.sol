// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {IDutchCoWAuctioneer, IDutchCoWEscrow, AuctionParams} from "../../src/IDutchCoW.sol";

interface IZooLike {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

/// @dev Approve that accepts both standard bool returns and USDT-style empty returns.
function approveToken(address token, address spender, uint256 amount) {
    (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(bytes4(0x095ea7b3), spender, amount));
    require(ok, "approve failed");
    if (data.length > 0) require(abi.decode(data, (bool)), "approve false");
}

contract TreasurySeller {
    IDutchCoWAuctioneer public immutable auctioneer;
    address public immutable sellToken;
    bytes32 public lastOrder;
    address public lastEscrow;

    constructor(address auctioneer_, address sellToken_) {
        auctioneer = IDutchCoWAuctioneer(auctioneer_);
        sellToken = sellToken_;
    }

    function sell(address buyToken, uint256 sellAmount, uint256 maxAmount, uint32 validFor, uint32 slippage, uint256 allowance) external {
        AuctionParams memory p = _params(buyToken, sellAmount, maxAmount, validFor, slippage);
        address escrow = auctioneer.predictEscrow(p);
        approveToken(sellToken, escrow, allowance);
        lastOrder = auctioneer.placeOrder(p);
        lastEscrow = escrow;
    }

    function _params(address buyToken, uint256 sellAmount, uint256 maxAmount, uint32 validFor, uint32 slippage)
        internal view returns (AuctionParams memory)
    {
        return AuctionParams({
            sellToken: sellToken,
            buyToken: buyToken,
            sellAmount: sellAmount,
            maxAmount: maxAmount,
            receiver: address(this),
            startBlock: block.number,
            validFor: validFor,
            slippageBps: slippage
        });
    }
}

contract DcaBot {
    IDutchCoWAuctioneer public immutable auctioneer;
    address public immutable sellToken;
    uint256 public slices;

    constructor(address auctioneer_, address sellToken_) {
        auctioneer = IDutchCoWAuctioneer(auctioneer_);
        sellToken = sellToken_;
    }

    function slice(address buyToken, uint256 sellAmount, uint256 maxAmount, uint32 validFor, uint32 slippage, uint256 allowance) external returns (address escrow) {
        slices += 1;
        AuctionParams memory p = AuctionParams({
            sellToken: sellToken,
            buyToken: buyToken,
            sellAmount: sellAmount,
            maxAmount: maxAmount,
            receiver: address(this),
            startBlock: block.number,
            validFor: validFor + uint32(slices),
            slippageBps: slippage
        });
        escrow = auctioneer.predictEscrow(p);
        approveToken(sellToken, escrow, allowance);
        auctioneer.placeOrder(p);
    }
}

contract ProtocolFeeSeller {
    IDutchCoWAuctioneer public immutable auctioneer;
    address public immutable sellToken;
    address public immutable feeRecipient;
    uint256 public feeBps;

    constructor(address auctioneer_, address sellToken_, address feeRecipient_, uint256 feeBps_) {
        auctioneer = IDutchCoWAuctioneer(auctioneer_);
        sellToken = sellToken_;
        feeRecipient = feeRecipient_;
        feeBps = feeBps_;
    }

    function sellWithFee(address payer, address buyToken, uint256 amount, uint256 maxAmount, uint32 validFor, uint32 slippage) external {
        IZooLike(sellToken).transferFrom(payer, address(this), amount);
        uint256 fee = amount * feeBps / 10_000;
        if (fee > 0) IZooLike(sellToken).transfer(feeRecipient, fee);
        uint256 sellAmount = amount - fee;
        AuctionParams memory p = AuctionParams({
            sellToken: sellToken,
            buyToken: buyToken,
            sellAmount: sellAmount,
            maxAmount: maxAmount,
            receiver: address(this),
            startBlock: block.number,
            validFor: validFor,
            slippageBps: slippage
        });
        address escrow = auctioneer.predictEscrow(p);
        approveToken(sellToken, escrow, sellAmount);
        auctioneer.placeOrder(p);
    }
}

contract VaultRebalancer {
    IDutchCoWAuctioneer public immutable auctioneer;
    address public immutable sellToken;
    address public immutable buyToken;
    uint256 public targetBuy;

    constructor(address auctioneer_, address sellToken_, address buyToken_, uint256 targetBuy_) {
        auctioneer = IDutchCoWAuctioneer(auctioneer_);
        sellToken = sellToken_;
        buyToken = buyToken_;
        targetBuy = targetBuy_;
    }

    function rebalance(uint256 sellAmount, uint32 validFor, uint32 slippage) external returns (address escrow) {
        uint256 held = IZooLike(buyToken).balanceOf(address(this));
        uint256 want = held >= targetBuy ? 1 : targetBuy - held;
        AuctionParams memory p = AuctionParams({
            sellToken: sellToken,
            buyToken: buyToken,
            sellAmount: sellAmount,
            maxAmount: want,
            receiver: address(this),
            startBlock: block.number,
            validFor: validFor,
            slippageBps: slippage
        });
        escrow = auctioneer.predictEscrow(p);
        approveToken(sellToken, escrow, sellAmount);
        auctioneer.placeOrder(p);
    }
}

contract SmartWallet {
    address public owner;
    IDutchCoWAuctioneer public immutable auctioneer;
    constructor(address owner_, address auctioneer_) {
        owner = owner_;
        auctioneer = IDutchCoWAuctioneer(auctioneer_);
    }
    function place(address sellToken, address buyToken, uint256 sellAmount, uint256 maxAmount, uint32 validFor, uint32 slippage, uint256 allowance) external returns (address escrow) {
        require(msg.sender == owner, "not owner");
        AuctionParams memory p = AuctionParams({
            sellToken: sellToken, buyToken: buyToken, sellAmount: sellAmount, maxAmount: maxAmount,
            receiver: address(this), startBlock: block.number, validFor: validFor, slippageBps: slippage
        });
        escrow = auctioneer.predictEscrow(p);
        approveToken(sellToken, escrow, allowance);
        auctioneer.placeOrder(p);
    }
}

contract SweepWallet {
    IDutchCoWAuctioneer public immutable auctioneer;
    address public endUser;
    constructor(address auctioneer_, address endUser_) {
        auctioneer = IDutchCoWAuctioneer(auctioneer_);
        endUser = endUser_;
    }
    function place(address sellToken, address buyToken, uint256 sellAmount, uint256 maxAmount, uint32 validFor, uint32 slippage, uint256 allowance) external returns (address escrow) {
        AuctionParams memory p = AuctionParams({
            sellToken: sellToken, buyToken: buyToken, sellAmount: sellAmount, maxAmount: maxAmount,
            receiver: address(this), startBlock: block.number, validFor: validFor, slippageBps: slippage
        });
        escrow = auctioneer.predictEscrow(p);
        approveToken(sellToken, escrow, allowance);
        auctioneer.placeOrder(p);
    }
    function sweep(address token) external {
        uint256 bal = IZooLike(token).balanceOf(address(this));
        IZooLike(token).transfer(endUser, bal);
    }
}

contract Keeper {
    function release(address escrow) external {
        IDutchCoWEscrow(escrow).releaseFunds();
    }
    function releaseAndForward(address escrow, address token, address beneficiary) external {
        uint256 beforeBal = IZooLike(token).balanceOf(address(this));
        IDutchCoWEscrow(escrow).releaseFunds();
        uint256 tip = IZooLike(token).balanceOf(address(this)) - beforeBal;
        if (tip > 0) IZooLike(token).transfer(beneficiary, tip);
    }
}

contract BadUnlimited {
    IDutchCoWAuctioneer public immutable auctioneer;
    constructor(address a) { auctioneer = IDutchCoWAuctioneer(a); }
    function place(address sellToken, address buyToken, uint256 sellAmount, uint256 maxAmount) external {
        AuctionParams memory p = AuctionParams({
            sellToken: sellToken, buyToken: buyToken, sellAmount: sellAmount, maxAmount: maxAmount,
            receiver: address(this), startBlock: block.number, validFor: 25, slippageBps: 500
        });
        approveToken(sellToken, auctioneer.predictEscrow(p), type(uint256).max);
        auctioneer.placeOrder(p);
    }
}

contract BadLowApproval {
    IDutchCoWAuctioneer public immutable auctioneer;
    constructor(address a) { auctioneer = IDutchCoWAuctioneer(a); }
    function place(address sellToken, address buyToken, uint256 sellAmount, uint256 maxAmount) external {
        AuctionParams memory p = AuctionParams({
            sellToken: sellToken, buyToken: buyToken, sellAmount: sellAmount, maxAmount: maxAmount,
            receiver: address(this), startBlock: block.number, validFor: 25, slippageBps: 500
        });
        approveToken(sellToken, auctioneer.predictEscrow(p), sellAmount - 1);
        auctioneer.placeOrder(p);
    }
}

contract BadReceiver {
    IDutchCoWAuctioneer public immutable auctioneer;
    constructor(address a) { auctioneer = IDutchCoWAuctioneer(a); }
    function place(address sellToken, address buyToken, address receiver) external {
        AuctionParams memory p = AuctionParams({
            sellToken: sellToken, buyToken: buyToken, sellAmount: 1 ether, maxAmount: 100 ether,
            receiver: receiver, startBlock: block.number, validFor: 25, slippageBps: 500
        });
        approveToken(sellToken, auctioneer.predictEscrow(p), 1 ether);
        auctioneer.placeOrder(p);
    }
}

contract BadStart {
    IDutchCoWAuctioneer public immutable auctioneer;
    constructor(address a) { auctioneer = IDutchCoWAuctioneer(a); }
    function place(address sellToken, address buyToken, int256 delta) external {
        AuctionParams memory p = AuctionParams({
            sellToken: sellToken, buyToken: buyToken, sellAmount: 1 ether, maxAmount: 100 ether,
            receiver: address(this), startBlock: uint256(int256(block.number) + delta), validFor: 25, slippageBps: 500
        });
        approveToken(sellToken, auctioneer.predictEscrow(p), 1 ether);
        auctioneer.placeOrder(p);
    }
}

contract DuplicatePlacer {
    IDutchCoWAuctioneer public immutable auctioneer;
    constructor(address a) { auctioneer = IDutchCoWAuctioneer(a); }
    function placeTwice(address sellToken, address buyToken) external {
        AuctionParams memory p = AuctionParams({
            sellToken: sellToken, buyToken: buyToken, sellAmount: 1 ether, maxAmount: 100 ether,
            receiver: address(this), startBlock: block.number, validFor: 25, slippageBps: 500
        });
        address escrow = auctioneer.predictEscrow(p);
        approveToken(sellToken, escrow, 1.5 ether);
        auctioneer.placeOrder(p);
        auctioneer.placeOrder(p);
    }
}

contract MultiAuction {
    IDutchCoWAuctioneer public immutable auctioneer;
    constructor(address a) { auctioneer = IDutchCoWAuctioneer(a); }
    function placeTwo(address sellToken, address buyToken) external returns (address a, address b) {
        AuctionParams memory p1 = AuctionParams({
            sellToken: sellToken, buyToken: buyToken, sellAmount: 1 ether, maxAmount: 100 ether,
            receiver: address(this), startBlock: block.number, validFor: 25, slippageBps: 500
        });
        AuctionParams memory p2 = AuctionParams({
            sellToken: sellToken,
            buyToken: buyToken,
            sellAmount: 1 ether,
            maxAmount: 100 ether,
            receiver: address(this),
            startBlock: block.number,
            validFor: 40,
            slippageBps: 500
        });
        a = auctioneer.predictEscrow(p1);
        b = auctioneer.predictEscrow(p2);
        approveToken(sellToken, a, 1 ether);
        approveToken(sellToken, b, 1 ether);
        auctioneer.placeOrder(p1);
        auctioneer.placeOrder(p2);
    }
}

contract ReentrantPlacer {
    IDutchCoWAuctioneer public immutable auctioneer;
    address public sellToken;
    address public buyToken;
    bool public entered;
    constructor(address a) { auctioneer = IDutchCoWAuctioneer(a); }
    function arm(address sell, address buy) external { sellToken = sell; buyToken = buy; }
    function place() external {
        AuctionParams memory p = AuctionParams({
            sellToken: sellToken, buyToken: buyToken, sellAmount: 1 ether, maxAmount: 100 ether,
            receiver: address(this), startBlock: block.number, validFor: 25, slippageBps: 500
        });
        approveToken(sellToken, auctioneer.predictEscrow(p), 1 ether);
        auctioneer.placeOrder(p);
    }
    function onToken(address, address, uint256) external {
        if (entered) return;
        entered = true;
        AuctionParams memory p = AuctionParams({
            sellToken: sellToken, buyToken: buyToken, sellAmount: 1 ether, maxAmount: 50 ether,
            receiver: address(this), startBlock: block.number, validFor: 30, slippageBps: 500
        });
        approveToken(sellToken, auctioneer.predictEscrow(p), 1 ether);
        auctioneer.placeOrder(p);
    }
}
