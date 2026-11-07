// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {ComposableCoW} from "composable-cow/src/ComposableCoW.sol";
import {GPv2Settlement} from "cowprotocol/contracts/GPv2Settlement.sol";
import {Data} from "./DutchCoWs.sol";
import {Clones} from "@openzeppelin/proxy/Clones.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {DutchCowEscrow} from "./escrow.sol";

// TEST DEPLOYMENT 
// Author: @cobymnun on x, inspired by @kayibal's original Dutch CoWs.
// This software comes with no warranty.

contract DutchCoWAuctioneer is ReentrancyGuard {
    
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
        require(params.sellAmount > 0, "NothingToSell");
        require(params.maxAmount <= type(uint256).max / 10_000, "PricePanicPreventer");
        require(params.sellToken.allowance(msg.sender, escrowAddress) >= params.sellAmount, "BadApproval");
        require(params.slippageBps < 9999 && params.slippageBps > 50, "BadSlippage");
        require(params.maxAmount > 0, "SellingForNothing");
        require(block.number == params.startBlock, "BadStart");
        require(params.validFor >= 25, "AuctionTooShort");
        require(params.receiver == msg.sender, "BeneficiaryOrdersNotAllowed");
        require(params.maxAmount * params.slippageBps / 10_000 >= params.validFor, "PreventStepSizeUnderflow");
    }
    
    function _predictEscrow(
        Data calldata params
        ) internal view returns 
            ( address escrowAddress, 
            bytes32 salt,    
            bytes memory args) 
        {                
            salt = keccak256(abi.encode(msg.sender, params));
            args = abi.encode(params);
            escrowAddress = Clones.predictDeterministicAddressWithImmutableArgs(
                    implementation, 
                    args, 
                    salt, 
                    address(this));
        }

    function predictEscrow(Data calldata params) external view returns (address escrowAddress) {
        (escrowAddress, , ) = _predictEscrow(params);
    }

    function _makeEscrow(Data calldata params) internal returns (address) {
        (, bytes32 salt, bytes memory args) = _predictEscrow(params);
        return Clones.cloneDeterministicWithImmutableArgs(implementation, args, salt);
    }

    function placeOrder(Data calldata params) external nonReentrant returns (bytes32) {
        
        (address escrowAddress, bytes32 salt, ) = _predictEscrow(params);

        validateParams(params, escrowAddress);     

        _makeEscrow(params);

        bytes32 CowOrder = DutchCowEscrow(escrowAddress).initialize(params, handler, salt);

        emit OrderPlaced(CowOrder, msg.sender, params, escrowAddress);

        return CowOrder;
    }

}