 // SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {IERC20} from "cowprotocol/contracts/interfaces/IERC20.sol";
import {GPv2Order} from "cowprotocol/contracts/libraries/GPv2Order.sol";
import {IConditionalOrder, IConditionalOrderGenerator} from "composable-cow/src/interfaces/IConditionalOrder.sol";
import {IERC165} from "@openzeppelin/utils/introspection/IERC165.sol";
import {IDutchCoWEscrow} from "./IDutchCoW.sol";

// TEST DEPLOYMENT 
// Author: @cobymnun on x, inspired by @kayibal's original Dutch CoWs.
// block times are set for base. 
// maxAmount is what you want to start the auction at. reciever is you, validFor is auction duration measured in blocks. 
// A 0.1% by volume fee is taken on each auction from CoW returned surplus value, integrated as a CoW partner fee. 
// This software comes with no warranty.

struct Data {
    IERC20 sellToken;
    IERC20 buyToken;
    uint256 sellAmount;
    uint256 maxAmount;
    address receiver;
    uint256 startBlock;
    uint32 validFor;
    uint32 slippageBps;
}

contract DutchAuction is IConditionalOrderGenerator {
    
    bytes32 public constant APP_DATA = 0x09eed5e4a791d7763f86d80bace7aac36a981efa30a39e45b9f65adf28d8b932;

    function supportsInterface(bytes4 id) external pure override returns (bool) {
        return id == type(IConditionalOrderGenerator).interfaceId
            || id == type(IERC165).interfaceId;
    }
    
    function _floor(Data memory params) internal pure returns (uint256 floor, uint256 stepSize) {
        floor = params.maxAmount * (10_000 - params.slippageBps) / 10_000;
        stepSize = (params.maxAmount - floor) / params.validFor;
    }

    function _currentPrice(Data memory params) internal view returns (uint256 currentBuy) {
        if (block.number < params.startBlock + 5) return params.maxAmount;
        (, uint256 stepSize) = _floor(params);
        uint256 currentStep = (block.number - params.startBlock - 4) * stepSize;  
        currentBuy = params.maxAmount - currentStep;
    }

    function verify(
        address owner, 
        address, 
        bytes32 _hash, 
        bytes32 domainSeparator, 
        bytes32,
        bytes calldata staticInput, 
        bytes calldata, 
        GPv2Order.Data calldata order
    ) external view override {
        Data memory params = abi.decode(staticInput, (Data));

        require(params.validFor > 0, "AuctionTooShort");  
        require(params.slippageBps <= 10_000, "BadSlippage");
        require(GPv2Order.hash(order, domainSeparator) == _hash, "BadHash");
        require(block.number >= params.startBlock && block.number < params.startBlock + params.validFor, "OutsideWindow");
        require(
            params.sellToken.balanceOf(owner) >= params.sellAmount &&
            params.sellToken.allowance(owner, IDutchCoWEscrow(owner).vaultRelayer()) >= params.sellAmount,
            "Filled"
        );

        require(
            order.sellToken == params.sellToken &&
            order.buyToken == params.buyToken &&
            order.receiver == params.receiver &&
            order.sellAmount == params.sellAmount &&
            order.appData == APP_DATA &&
            order.feeAmount == 0 &&
            order.kind == GPv2Order.KIND_SELL &&
            !order.partiallyFillable &&
            order.sellTokenBalance == GPv2Order.BALANCE_ERC20 &&
            order.buyTokenBalance == GPv2Order.BALANCE_ERC20,
            "FieldMismatch"
        );

        require(order.buyAmount >= _currentPrice(params), "BelowFloor");
    } 

    function getTradeableOrder(
        address owner, 
        address, 
        bytes32, 
        bytes calldata staticInput, 
        bytes calldata)
        public view override returns (GPv2Order.Data memory order)
    {
        Data memory params = abi.decode(staticInput, (Data));

        if (params.sellToken.balanceOf(owner) < params.sellAmount ||
            params.sellToken.allowance(owner, IDutchCoWEscrow(owner).vaultRelayer()) < params.sellAmount) {
            revert IConditionalOrder.PollNever("Filled");
        }
        
        if (block.number < params.startBlock) revert IConditionalOrder.PollTryAtBlock(params.startBlock, "NotStarted");

        uint256 endBlock = params.startBlock + params.validFor;

        uint256 priceAtStep;

        if (block.number >= endBlock) { 
            revert IConditionalOrder.PollNever("AuctionEnded");
        } else {
            priceAtStep = _currentPrice(params);
        }

        uint256 validTime = ((endBlock - block.number) * 2) / 10;
        if (validTime == 0 ) validTime = 1;
        uint32 validTo = uint32(block.timestamp + validTime);

        order = GPv2Order.Data(
            params.sellToken,
            params.buyToken,
            params.receiver,
            params.sellAmount,
            priceAtStep,
            validTo,
            APP_DATA,
            0,
            GPv2Order.KIND_SELL, 
            false,
            GPv2Order.BALANCE_ERC20,
            GPv2Order.BALANCE_ERC20
        );
    }
}