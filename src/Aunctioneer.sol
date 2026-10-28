// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {IERC20 as IERC20OZ} from "@openzeppelin/token/ERC20/IERC20.sol";
import {ComposableCoW} from "composable-cow/src/ComposableCoW.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {GPv2Settlement} from "cowprotocol/contracts/GPv2Settlement.sol";
import {Data} from "./DutchCoWs.sol";
import {Clones} from "@openzeppelin/proxy/Clones.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {DutchCowEscrow} from "./escrow.sol";

// TEST DEPLOYMENT 
// Author: @cobymnun on x, inspired by @kayibal's original Dutch CoWs.
// This software comes with no warranty.

contract DutchCoWAuctioneer is ReentrancyGuard {
    using SafeERC20 for IERC20OZ;
    
    ComposableCoW public immutable composableCow;
    GPv2Settlement public immutable settlement;
    address public immutable handler;
    address public immutable vaultRelayer;
    address public immutable implementation; 

    constructor(address _handler, ComposableCoW _cow, GPv2Settlement _settlement) {
        handler = _handler;
        composableCow = _cow;
        settlement = _settlement;
        vaultRelayer = address(_settlement.vaultRelayer());
        implementation = address(new DutchCowEscrow(_cow, vaultRelayer, address(this)));
    }

    event OrderPlaced(bytes32 indexed orderId, address indexed owner, Data params, address indexed escrowAddress);

    function validateParams(Data calldata params, address escrowAddress) internal view {     
        bool approved = params.sellAmount > 0 && IERC20OZ(address(params.sellToken)).allowance(msg.sender, escrowAddress) >= params.sellAmount;
        bool slippageValid = params.slippageBps < 9999 && params.slippageBps > 50;
        require(params.maxAmount > 0, "SellingForNothing");
        require(block.number >= params.startBlock && 
            block.number < params.startBlock + params.validFor, "badDuration");
        require(params.validFor >= 50, "AuctionTooShort");
        require(approved, "zero-sell or ApprovalTooLow");
        require(slippageValid, "BadSlippage");
        require(params.receiver != address(0), "NoReciever");
    }

    
    function _predictEscrow(
        Data calldata params, 
        address owner) 
        internal view returns (
            address escrowAddress, 
            bytes32 salt,    
            bytes memory args) 
        {                
            salt = keccak256(abi.encode(owner, params));
            args = abi.encode(params);
            escrowAddress = Clones.predictDeterministicAddressWithImmutableArgs(
                    implementation, 
                    args, 
                    salt, 
                    address(this));
        }

    function predictEscrow(Data calldata params, address owner) external view returns (address escrowAddress) {
        (escrowAddress, , ) = _predictEscrow(params, owner);
    }

    function _makeEscrow(Data calldata params, address owner) internal returns (address) {
        (, bytes32 salt, bytes memory args) = _predictEscrow(params, owner);
        return Clones.cloneDeterministicWithImmutableArgs(implementation, args, salt);
    }

    function placeOrder(Data calldata params) external nonReentrant returns (bytes32) {
        
        (address escrowAddress, bytes32 salt, ) = _predictEscrow(params, msg.sender);

        validateParams(params, escrowAddress);     

        require(_makeEscrow(params, msg.sender) == escrowAddress, "address mismatch");

        bytes32 CowOrder = DutchCowEscrow(escrowAddress).initialize(params, msg.sender, handler, salt);

        emit OrderPlaced(CowOrder, msg.sender, params, escrowAddress);

        return CowOrder;
    }

}