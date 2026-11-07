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

    function _takeFunds(Data calldata params) internal {
        IERC20OZ token = IERC20OZ(address(params.sellToken));
        uint256 approvalAmnt = token.allowance(params.receiver, address(this));
        require(approvalAmnt >= params.sellAmount && approvalAmnt < 2 * params.sellAmount && params.sellAmount <= type(uint256).max / 2, "BadApproval");
        token.safeTransferFrom(address(params.receiver), address(this), approvalAmnt);
        require(token.balanceOf(address(this)) >= params.sellAmount, "ShortAfterFee");
        token.forceApprove(vaultRelayer, params.sellAmount);
    }

    function _setOwner(Data calldata params) internal {
        _owner = params.receiver;
    }

    function initialize(
        Data calldata params,  
        address handler,
        bytes32 salt) external initializer onlyAuctioneer() returns(bytes32) 
        {
            _verifyParams(params);
            _takeFunds(params);
            _setOwner(params);
            
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
        require(block.number > (params.startBlock + params.validFor), "AuctionInProgress");
        IERC20OZ token = IERC20OZ(address(params.sellToken));
        uint256 balance = token.balanceOf(address(this));

        composableCoW.remove(CowOrder);
        try this.pay(address(token), _owner, msg.sender, balance) {} catch {}
    }

    /// @dev Token calls live here so a blacklist or pause cannot undo `remove`.
    function pay(address token, address owner, address tipTo, uint256 balance) external {
        require(msg.sender == address(this), "NotSelf");
        IERC20OZ(token).forceApprove(vaultRelayer, 0);
        uint256 refundFee = balance / 1000;
        if (refundFee == 0) {
            IERC20OZ(token).safeTransfer(owner, balance);
        } else {
            IERC20OZ(token).safeTransfer(owner, balance - refundFee);
            IERC20OZ(token).safeTransfer(tipTo, refundFee);
        }
    }
}