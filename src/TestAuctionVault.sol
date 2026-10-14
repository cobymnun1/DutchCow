// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {IERC20} from "cowprotocol/contracts/interfaces/IERC20.sol";
import {GPv2Order} from "cowprotocol/contracts/libraries/GPv2Order.sol";
import {IConditionalOrder} from "composable-cow/src/interfaces/IConditionalOrder.sol";
import {ISignatureVerifierMuxer} from "safe/handler/extensible/SignatureVerifierMuxer.sol";
import {Safe} from "safe/Safe.sol";
import {IERC165} from "safe/interfaces/IERC165.sol";

interface IComposableCoW {
    function create(IConditionalOrder.ConditionalOrderParams calldata params, bool dispatch) external;

    function isValidSafeSignature(
        Safe safe,
        address sender,
        bytes32 hash,
        bytes32 domainSeparator,
        bytes32 typeHash,
        bytes memory encodeData,
        bytes memory payload
    ) external view returns (bytes4);
}

/**
 * @notice Minimal contract owner for testing contract-owned ComposableCoW orders.
 * @dev This is not a production wallet. It intentionally centralizes test funds
 *      and gives the deployer permission to approve tokens, create orders, and withdraw.
 */
contract TestAuctionVault {
    bytes4 private constant SAFE_SIGNATURE_SELECTOR = 0x5fd7e97d;
    address public immutable composableCoW;
    address public immutable cowVaultRelayer;
    address public owner;

    error NotOwner();
    error InvalidSignature();
    error TokenTransferFailed();

    constructor(address _owner, address _composableCoW, address _cowVaultRelayer) {
        owner = _owner;
        composableCoW = _composableCoW;
        cowVaultRelayer = _cowVaultRelayer;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function approveCow(IERC20 token, uint256 amount) external onlyOwner {
        if (!token.approve(cowVaultRelayer, amount)) revert TokenTransferFailed();
    }

    function createOrder(address handler, bytes32 salt, bytes calldata staticInput) external onlyOwner {
        IComposableCoW(composableCoW).create(
            IConditionalOrder.ConditionalOrderParams({
                handler: IConditionalOrder(handler),
                salt: salt,
                staticInput: staticInput
            }),
            true
        );
    }

    function withdraw(IERC20 token, address to, uint256 amount) external onlyOwner {
        if (!token.transfer(to, amount)) revert TokenTransferFailed();
    }

    /**
     * @dev ComposableCoW checks this interface before producing its contract signature.
     */
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(ISignatureVerifierMuxer).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /**
     * @dev Decodes ComposableCoW's safeSignature payload and delegates validation
     *      back to ComposableCoW, using this vault as the contract owner.
     */
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
        if (signature.length < 4 || bytes4(signature[:4]) != SAFE_SIGNATURE_SELECTOR) {
            revert InvalidSignature();
        }

        (bytes32 domainSeparator, bytes32 typeHash, bytes memory encodeData, bytes memory payload) =
            abi.decode(signature[4:], (bytes32, bytes32, bytes, bytes));

        return IComposableCoW(composableCoW).isValidSafeSignature(
            Safe(payable(address(this))),
            msg.sender,
            hash,
            domainSeparator,
            typeHash,
            encodeData,
            payload
        );
    }

    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }
}
