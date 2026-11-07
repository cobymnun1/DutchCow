// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {GPv2Order} from "cowprotocol/contracts/libraries/GPv2Order.sol";
import {IConditionalOrder} from "composable-cow/src/interfaces/IConditionalOrder.sol";
import {ComposableCoW} from "composable-cow/src/ComposableCoW.sol";
import {Safe} from "safe/Safe.sol";

contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "balance");
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "allowance");
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockSettlement {
    address public vaultRelayer;

    constructor(address vaultRelayer_) {
        vaultRelayer = vaultRelayer_;
    }
}

contract MockComposableCoW {
    mapping(address => mapping(bytes32 => bool)) public singleOrders;

    event ConditionalOrderCreated(address indexed owner, IConditionalOrder.ConditionalOrderParams params);

    function domainSeparator() external pure returns (bytes32) {
        return bytes32(uint256(0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa));
    }

    function hash(IConditionalOrder.ConditionalOrderParams memory params) public pure returns (bytes32) {
        return keccak256(abi.encode(params));
    }

    function create(IConditionalOrder.ConditionalOrderParams calldata params, bool dispatch) external {
        singleOrders[msg.sender][hash(params)] = true;
        if (dispatch) emit ConditionalOrderCreated(msg.sender, params);
    }

    function remove(bytes32 singleOrderHash) external {
        singleOrders[msg.sender][singleOrderHash] = false;
    }

    function isValidSafeSignature(
        Safe safe,
        address sender,
        bytes32 _hash,
        bytes32 domainSep,
        bytes32,
        bytes calldata encodeData,
        bytes calldata payload
    ) external view returns (bytes4) {
        ComposableCoW.PayloadStruct memory decoded = abi.decode(payload, (ComposableCoW.PayloadStruct));
        require(decoded.proof.length == 0, "proof");
        require(singleOrders[address(safe)][hash(decoded.params)], "unauthed");
        GPv2Order.Data memory order = abi.decode(encodeData, (GPv2Order.Data));
        decoded.params.handler.verify(
            address(safe),
            sender,
            _hash,
            domainSep,
            hash(decoded.params),
            decoded.params.staticInput,
            decoded.offchainInput,
            order
        );
        return 0x1626ba7e;
    }
}
