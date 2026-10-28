// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Data} from "./DutchCoWs.sol";
import {IERC20 as IERC20OZ} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/proxy/utils/Initializable.sol";
import {ReentrancyGuard} from "@openzeppelin/utils/ReentrancyGuard.sol";
import {Clones} from "@openzeppelin/proxy/Clones.sol";
import {IConditionalOrder} from "composable-cow/src/interfaces/IConditionalOrder.sol";
import {ComposableCoW} from "composable-cow/src/ComposableCoW.sol";
import {ERC1271Forwarder} from "composable-cow/src/ERC1271Forwarder.sol";

// TEST DEPLOYMENT 
// Author: @cobymnun on x, inspired by @kayibal's original Dutch CoWs.
// This software comes with no warranty.

contract DutchCowEscrow is Initializable, ReentrancyGuard, ERC1271Forwarder {
    using SafeERC20 for IERC20OZ;

    address public immutable auctioneer;
    address public immutable vaultRelayer;
    address public _owner;
    bytes32 public CowOrder;
    
    constructor(ComposableCoW _cow, address _vaultRelayer, address _auctioneer) 
    ERC1271Forwarder(_cow) 
    {
        vaultRelayer = _vaultRelayer;
        auctioneer = _auctioneer;
        _disableInitializers();
    }

    modifier onlyAuctioneer() {
        require(msg.sender == auctioneer, "NotAuctioneer");
        _;
    }

    function _verifyParams(Data calldata params) internal view {
        require (keccak256(Clones.fetchCloneArgs(address(this))) == keccak256(abi.encode(params)), "Param Mismatch");
    }

    function _takeFunds(Data calldata params, address owner) internal {
        IERC20OZ token = IERC20OZ(address(params.sellToken));
        token.safeTransferFrom(address(owner), address(this), params.sellAmount);
        token.forceApprove(vaultRelayer, params.sellAmount);
    }

    function _setOwner(address owner) internal {
        _owner = owner;
    }

    function initialize(
        Data calldata params, 
        address owner, 
        address handler,
        bytes32 salt) external initializer onlyAuctioneer() returns(bytes32) 
        {
            _verifyParams(params);
            _takeFunds(params, owner);
            _setOwner(owner);
            
            IConditionalOrder.ConditionalOrderParams memory CowParams = IConditionalOrder.ConditionalOrderParams({
                handler: IConditionalOrder(handler),
                salt: salt,
                staticInput: abi.encode(params)
            });

            CowOrder = composableCoW.hash(CowParams);
            composableCoW.create(CowParams, true);
            return CowOrder;
    }

    function releaseFunds() external nonReentrant {
        Data memory params = abi.decode(Clones.fetchCloneArgs(address(this)), (Data)); 
        require(block.number > (params.startBlock + params.validFor), "Auction not ended");
        IERC20OZ token = IERC20OZ(address(params.sellToken));
        uint256 refundFee = (token.balanceOf(address(this)) * 10 ) / 10_000;
        
        composableCoW.remove(CowOrder);
        token.forceApprove(vaultRelayer, 0);
        IERC20OZ(address(token)).safeTransfer(_owner, token.balanceOf(address(this)) - refundFee);
        IERC20OZ(address(token)).safeTransfer(msg.sender, refundFee);
    }
}