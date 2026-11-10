# Coby's Dutch CoWs integration guide

Dutch CoWs allows smart contracts to place Dutch Auction orders directly to CoW Protocol. A contract, whether via a hook or a user interaction, can place an order filled by a verified solver without the developer needing to set up any off-chain infrastructure.

The same guide is on the site at `docs/index.html`. This file is the text copy for GitHub.

Author: [@Cobymnun](https://x.com/Cobymnun). Source: [github.com/cobymnun1/DutchCow](https://github.com/cobymnun1/DutchCow).

## Base deployment addresses

Chain id 8453.

| Contract | Address |
| --- | --- |
| Auctioneer (`DutchCoWAuctioneer`) | `0xE105d00b8E13Cb7f33Ea22cA2c2320f40A0E2c63` |
| Handler (`DutchAuction`) | `0xB417180c2FD563bE2fB7833E95908B4D243bB62b` |
| Escrow implementation (`DutchCowEscrow`) | `0x2607A4712ed8C0BE50A92f71f32f0cBE0C366de9` |
| ComposableCoW | `0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74` |
| GPv2Settlement | `0x9008D19f58AAbD9eD0D60971565AA8510560ab41` |
| Vault relayer | `0xC92E8bdf79f0507f65a392b0ab4667716BFE0110` |

`0xe537e7206526486A2b4fBe7679Ee779734462437` is `RealDutchCowTest`. It is not the integration path. It keeps the sell token and any buy token it receives, and `place` reverts unless the call carries ETH.

## Integrate

Call the auctioneer from the contract that already holds the sell token. Do all three steps in one transaction. `receiver` must be that contract. `startBlock` must be `block.number`. The ABI is `src/IDutchCoW.sol`. `AuctionParams` encodes the same way as `Data` in `src/DutchCoWs.sol`.

```solidity
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
```

`predictEscrow` uses `msg.sender` in the CREATE2 salt. The address it returns is only the escrow your contract will deploy. A call from any other address predicts a different escrow.

### Option A: standard approve

Use this when the token's `approve` returns a bool, which covers most ERC-20s.

```solidity
IERC20(sellToken).approve(escrow, sellAmount);
auctioneer.placeOrder(params);
```

### Option B: low-level approve

Some tokens, such as USDT, return nothing from `approve`. Option A reverts on those. Option B accepts a bool return or no return. `0x095ea7b3` is the selector for `approve(address,uint256)`. This is the approve used by `test/realDutchCowTest.sol`.

```solidity
(bool ok, bytes memory data) = sellToken.call(
    abi.encodeWithSelector(0x095ea7b3, escrow, sellAmount)
);
require(ok && (data.length == 0 || abi.decode(data, (bool))), "approve");
auctioneer.placeOrder(params);
```

The allowance must be at least `sellAmount` and less than `2 * sellAmount`. The escrow pulls the whole allowance, then requires its balance to be at least `sellAmount`. Approve more than `sellAmount` only when the token takes a transfer fee, and keep the allowance under twice the sell amount. `sellAmount` must also be at most `type(uint256).max / 2`.

`slippageBps` allows 51 to 9998, which is 0.51% to 99.98%. `validFor` must be at least 25 blocks. `maxAmount * slippageBps / 10_000` must be at least `validFor`, or `placeOrder` reverts with `PreventStepSizeUnderflow`.

## What the call does

`placeOrder` checks the parameters, deploys an escrow clone, and the escrow pulls the sell token from the caller. The escrow then approves the vault relayer for exactly `sellAmount` and registers a single conditional order on ComposableCoW. `placeOrder` returns the conditional-order hash and emits `OrderPlaced`.

The CoW watch tower reads that order and posts a discrete order to the Base orderbook. These contracts do not post it themselves. A solver settles through GPv2Settlement. Settlement pays the buy token to `receiver`. Settlement takes the sell token from the escrow through the vault relayer.

The buy amount starts at `maxAmount` and falls. See `docs/reference.md` for the block-by-block price, the two different 0.1% amounts, and every revert string.

## Fee

Every order this handler produces uses app data `0x09eed5e4a791d7763f86d80bace7aac36a981efa30a39e45b9f65adf28d8b932`. On the Base orderbook, orders with that hash carried this document:

```json
{
  "appCode": "CobysDutchCoW",
  "metadata": {
    "partnerFee": {
      "recipient": "0x785fAA8D709D7CaAD63d5FbDB750D4a22600d30d",
      "volumeBps": 10
    }
  },
  "version": "1.14.0"
}
```

`volumeBps: 10` is 0.1% of volume. The handler does not transfer that fee. It requires the posted order's `appData` to equal the hash above, and CoW applies the partner fee from that document. `verify` rejects a settlement whose `appData` is anything else.
