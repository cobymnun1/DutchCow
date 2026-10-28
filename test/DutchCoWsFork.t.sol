// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "cowprotocol/contracts/interfaces/IERC20.sol";
import {GPv2Order} from "cowprotocol/contracts/libraries/GPv2Order.sol";
import {IConditionalOrder} from "composable-cow/src/interfaces/IConditionalOrder.sol";
import {DutchAuction} from "../DutchCoWs.sol";
import {TestAuctionVault} from "../src/TestAuctionVault.sol";

interface IComposableCoWFork {
    struct PayloadStruct {
        bytes32[] proof;
        IConditionalOrder.ConditionalOrderParams params;
        bytes offchainInput;
    }

    function create(IConditionalOrder.ConditionalOrderParams calldata params, bool dispatch) external;

    function getTradeableOrderWithSignature(
        address owner,
        IConditionalOrder.ConditionalOrderParams calldata params,
        bytes calldata offchainInput,
        bytes32[] calldata proof
    ) external view returns (GPv2Order.Data memory order, bytes memory signature);

    function isValidSafeSignature(
        address safe,
        address sender,
        bytes32 hash,
        bytes32 domainSeparator,
        bytes32 typeHash,
        bytes calldata encodeData,
        bytes calldata payload
    ) external view returns (bytes4);
}

interface ISettlementDomain {
    function domainSeparator() external view returns (bytes32);
}

contract DutchCoWsForkTest is Test {
    uint256 internal constant BASE_CHAIN_ID = 8453;
    address internal constant COMPOSABLE_COW = 0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74;
    address internal constant SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address internal constant VAULT_RELAYER = 0xC92E8bdf79f0507f65a392b0ab4667716BFE0110;
    address internal constant SELL_TOKEN = 0x0C03Ce270B4826Ec62e7DD007f0B716068639F7B;
    address internal constant RECEIVER = 0x000000000000000000000000000000000000bEEF;

    IComposableCoWFork internal composable;
    DutchAuction internal handler;
    TestAuctionVault internal vault;
    IConditionalOrder.ConditionalOrderParams internal params;
    DutchAuction.Data internal data;
    bytes32 internal constant SALT =
        0x1234567890123456789012345678901234567890123456789012345678901234;

    modifier onBaseFork() {
        if (block.chainid != BASE_CHAIN_ID) vm.skip(true);
        _;
    }

    function setUp() public {
        if (block.chainid != BASE_CHAIN_ID) return;

        composable = IComposableCoWFork(COMPOSABLE_COW);
        handler = new DutchAuction();
        vault = new TestAuctionVault(address(this), COMPOSABLE_COW, VAULT_RELAYER);
        data = DutchAuction.Data({
            sellToken: IERC20(SELL_TOKEN),
            buyToken: IERC20(address(0x0000000000000000000000000000000000001002)),
            sellAmount: 1 ether,
            maxAmount: 1000 ether,
            receiver: RECEIVER,
            startBlock: block.number,
            validFor: 100,
            slippageBps: 500
        });
        params = IConditionalOrder.ConditionalOrderParams({
            handler: IConditionalOrder(address(handler)),
            salt: SALT,
            staticInput: abi.encode(data)
        });

        deal(SELL_TOKEN, address(vault), data.sellAmount);
        vault.approveCow(IERC20(SELL_TOKEN), data.sellAmount);
    }

    function test_createAndSignatureValidationOnBaseFork() public onBaseFork {
        vault.createOrder(address(handler), SALT, params.staticInput);

        bytes32[] memory proof = new bytes32[](0);
        (GPv2Order.Data memory generatedOrder,) =
            composable.getTradeableOrderWithSignature(address(vault), params, "", proof);

        vm.roll(data.startBlock + 3);
        bytes32 domainSeparator = ISettlementDomain(SETTLEMENT).domainSeparator();
        bytes memory payload = abi.encode(
            IComposableCoWFork.PayloadStruct({proof: proof, params: params, offchainInput: ""})
        );
        bytes4 magic = composable.isValidSafeSignature(
            address(vault),
            address(this),
            GPv2Order.hash(generatedOrder, domainSeparator),
            domainSeparator,
            GPv2Order.TYPE_HASH,
            abi.encode(generatedOrder),
            payload
        );

        assertEq(bytes32(magic), bytes32(uint256(0x1626ba7e)));
    }

    function test_tamperedReceiverRevertsOnBaseFork() public onBaseFork {
        vault.createOrder(address(handler), SALT, params.staticInput);

        bytes32[] memory proof = new bytes32[](0);
        (GPv2Order.Data memory order,) =
            composable.getTradeableOrderWithSignature(address(vault), params, "", proof);
        order.receiver = address(0xCAFE);

        vm.roll(data.startBlock + 3);
        bytes32 domainSeparator = ISettlementDomain(SETTLEMENT).domainSeparator();
        bytes memory payload = abi.encode(
            IComposableCoWFork.PayloadStruct({proof: proof, params: params, offchainInput: ""})
        );

        vm.expectRevert(bytes("FieldMismatch"));
        composable.isValidSafeSignature(
            address(vault),
            address(this),
            GPv2Order.hash(order, domainSeparator),
            domainSeparator,
            GPv2Order.TYPE_HASH,
            abi.encode(order),
            payload
        );
    }
}
