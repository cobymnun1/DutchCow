# Dutch CoWs reference

This is the behavior of the contracts in `src/`, as deployed on Base (chain id 8453). The site copy is `docs/reference.html`. The integration steps are in `docs/guide.md` and `docs/index.html`.

The source comments say the software comes with no warranty.

Author: [@Cobymnun](https://x.com/Cobymnun). Source: [github.com/cobymnun1/DutchCow](https://github.com/cobymnun1/DutchCow).

## Contracts

| Name | Source | Base address |
| --- | --- | --- |
| `DutchCoWAuctioneer` | `src/Aunctioneer.sol` | `0xE105d00b8E13Cb7f33Ea22cA2c2320f40A0E2c63` |
| `DutchAuction` (handler) | `src/DutchCoWs.sol` | `0xB417180c2FD563bE2fB7833E95908B4D243bB62b` |
| `DutchCowEscrow` implementation | `src/escrow.sol` | `0x2607A4712ed8C0BE50A92f71f32f0cBE0C366de9` |
| ComposableCoW | CoW Protocol | `0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74` |
| GPv2Settlement | CoW Protocol | `0x9008D19f58AAbD9eD0D60971565AA8510560ab41` |
| Vault relayer | read from settlement in the auctioneer constructor | `0xC92E8bdf79f0507f65a392b0ab4667716BFE0110` |

Each auction is a new clone of the escrow implementation. The implementation itself holds no auction and its initializers are disabled.

`RealDutchCowTest` at `0xe537e7206526486A2b4fBe7679Ee779734462437` is a separate test contract. `place` on it reverts unless `msg.value > 0`. It does not forward tokens. Buy tokens and refunds that name it as `receiver` stay there. Do not integrate against it.

## Who calls what

The integrator's contract must already hold the sell token. It calls `DutchCoWAuctioneer.placeOrder`. The auctioneer deploys the escrow and the escrow calls `ComposableCoW.create` with the single-order flag set. The conditional-order handler is `DutchAuction`.

These contracts do not post to the orderbook and do not run a solver. A CoW watch tower watches `ConditionalOrderCreated` on ComposableCoW and posts the discrete order `getTradeableOrder` returns. A solver then calls `GPv2Settlement.settle`. Settlement asks the escrow for an EIP-1271 signature. The escrow forwards that check to ComposableCoW, which calls `DutchAuction.verify`.

Settlement pays `order.buyAmount` of the buy token to `order.receiver` from its own balance. It pulls the sell token from the escrow through the vault relayer. Dutch CoWs does not forward the buy token. `receiver` is the contract that called `placeOrder`.

## Parameters

`AuctionParams` in `src/IDutchCoW.sol` is ABI-identical to `Data` in `src/DutchCoWs.sol`.

| Field | Rule enforced by `placeOrder` |
| --- | --- |
| `sellToken`, `buyToken` | No extra check beyond the later token calls. |
| `sellAmount` | Greater than 0 (`NothingToSell`). At most `type(uint256).max / 2`, checked when the escrow pulls (`BadApproval`). |
| `maxAmount` | Greater than 0 (`SellingForNothing`). At most `type(uint256).max / 10_000` (`PricePanicPreventer`). |
| `receiver` | Must equal `msg.sender` (`BeneficiaryOrdersNotAllowed`). This address receives the buy token and any refund. |
| `startBlock` | Must equal `block.number` (`BadStart`). |
| `validFor` | At least 25 (`AuctionTooShort`). |
| `slippageBps` | Greater than 50 and less than 9999, so 51 through 9998 (`BadSlippage`). That is 0.51% through 99.98% of `maxAmount`. |

One more place-time check: `maxAmount * slippageBps / 10_000 >= validFor` (`PreventStepSizeUnderflow`). It exists so the per-block price step cannot round to zero. It rejects dust prices over long auctions. It does not otherwise relate the three numbers.

`placeOrder` is `nonReentrant`.

## Predicting and funding the escrow

```text
salt = keccak256(abi.encode(msg.sender, params))
args = abi.encode(params)
escrow = cloneDeterministicWithImmutableArgs(implementation, args, salt)
```

`predictEscrow` is a view and uses the caller's address. Call it from the same contract that will call `placeOrder`, in the same transaction, after `startBlock` is set to `block.number`.

The auctioneer requires `sellToken.allowance(msg.sender, escrow) >= sellAmount`. The escrow then requires:

```text
allowance >= sellAmount
allowance < 2 * sellAmount
sellAmount <= type(uint256).max / 2
```

or it reverts `BadApproval`. It transfers the full allowance from `receiver` to itself, not just `sellAmount`. If the balance after that transfer is below `sellAmount`, it reverts `ShortAfterFee`. It then approves the vault relayer for exactly `sellAmount`.

A normal ERC-20 `approve` is enough when the token returns a bool. Tokens that return no data from `approve` need the low-level call in `docs/guide.md`. The allowance has to be set in the same transaction as `placeOrder`, because a different `startBlock` is a different escrow.

## Price

```text
floor = maxAmount * (10_000 - slippageBps) / 10_000
stepSize = (maxAmount - floor) / validFor
```

While `block.number < startBlock + 5`, the quoted buy amount is `maxAmount`. That is blocks `startBlock` through `startBlock + 4`.

From `startBlock + 5` onward:

```text
buyAmount = maxAmount - (block.number - startBlock - 4) * stepSize
```

`getTradeableOrder` reverts `PollNever("AuctionEnded")` when `block.number >= startBlock + validFor`. The last block that still quotes is `startBlock + validFor - 1`. On that block the formula has taken `validFor - 5` steps, so the quoted price is five steps above `floor`, plus whatever the integer division left in `maxAmount - floor`. The auction does not quote the floor itself.

`verify` accepts a settlement whose `buyAmount` is greater than or equal to that current price. The revert string for a smaller buy amount is `BelowFloor`. A solver can pay more than the current price. It cannot pay less.

## The order the watch tower posts

`getTradeableOrder` returns a fill-or-kill sell order:

- `sellToken`, `buyToken`, `receiver`, and `sellAmount` are the auction parameters
- `buyAmount` is the current price above
- `feeAmount` is 0
- `kind` is sell
- `partiallyFillable` is false
- both balance markers are ERC-20
- `appData` is the handler constant below

`validTo` is a unix timestamp:

```text
validTime = ((startBlock + validFor - block.number) * 2) / 10
if validTime == 0, validTime = 1
validTo = block.timestamp + validTime
```

That is 0.2 seconds per block still left in the auction, and at least 1 second. It matches a 200ms block time. The watch tower posts a new discrete order when the quoted order changes. Each posted order's `validTo` lands near the end of the on-chain window.

Before `startBlock`, `getTradeableOrder` reverts `PollTryAtBlock(startBlock, "NotStarted")`. `placeOrder` cannot create that state, because it requires `startBlock == block.number`.

## When the handler stops quoting

`getTradeableOrder` reverts `PollNever("Filled")` if either of these is true:

- the escrow's sell-token balance is below `sellAmount`
- the escrow's allowance to the vault relayer is below `sellAmount`

A real fill spends the vault allowance, so donating the sell token back to the escrow does not make the order quotable again. A balance that falls below `sellAmount`, including a rebase down, also stops quoting. A token that reports both a high balance and a high allowance after the tokens are gone will still look open. `verify` uses the same two checks and reverts `Filled`.

After the window, the revert is `PollNever("AuctionEnded")`.

## What a settlement must match

`verify` also requires:

- the order hash matches the hash passed in
- `startBlock <= block.number < startBlock + validFor` (`OutsideWindow`)
- sell token, buy token, receiver, and sell amount equal the auction
- `appData` equals `APP_DATA`
- `feeAmount` is 0
- kind is sell, the order is not partially fillable, and both balances are ERC-20 (`FieldMismatch` if any of these differ)
- `buyAmount >=` the current price

`verify` itself only checks `validFor > 0` and `slippageBps <= 10_000`. The tighter bounds are enforced by `placeOrder` before an escrow exists.

## Fees

There are two different 0.1% amounts.

The fill fee is a CoW partner fee. The handler sets `appData` to:

```text
0x09eed5e4a791d7763f86d80bace7aac36a981efa30a39e45b9f65adf28d8b932
```

Orders posted from this handler on the Base orderbook carried:

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

`volumeBps: 10` is 0.1% of volume. The handler does not move those tokens. CoW reads the partner fee from the app-data document. `verify` rejects any other `appData`.

The refund tip is separate and only runs if the auction is not filled. `releaseFunds` pays `balance / 1000` of the escrow's current sell-token balance to `msg.sender`, and the rest to `_owner` (the `receiver` stored at placement). If `balance < 1000`, the tip is zero and the whole balance goes to the owner.

## Getting the sell token back

`releaseFunds` is permissionless. It reverts `AuctionInProgress` until `block.number > startBlock + validFor`.

The auction stops quoting at `startBlock + validFor`. The first block that can release is `startBlock + validFor + 1`. The block `startBlock + validFor` itself can neither quote nor release.

`releaseFunds` removes the conditional order first. It then calls `pay` on itself. `pay` clears the vault-relayer allowance and does the split above. If the token blacklist or pause makes `pay` revert, the removal still stands, and the tokens stay in the escrow. A later `releaseFunds` tries the payout again. `pay` can only be called by the escrow.

## Revert strings

| String | Where | Meaning |
| --- | --- | --- |
| `NothingToSell` | `placeOrder` | `sellAmount` is 0. |
| `SellingForNothing` | `placeOrder` | `maxAmount` is 0. |
| `PricePanicPreventer` | `placeOrder` | `maxAmount` is above `type(uint256).max / 10_000`. |
| `BadSlippage` | `placeOrder` | `slippageBps` is outside 51..9998. |
| `BadStart` | `placeOrder` | `startBlock` is not the current block. |
| `AuctionTooShort` | `placeOrder` | `validFor` is below 25. |
| `BeneficiaryOrdersNotAllowed` | `placeOrder` | `receiver` is not the caller. |
| `PreventStepSizeUnderflow` | `placeOrder` | `maxAmount * slippageBps / 10_000` is below `validFor`. |
| `BadApproval` | `placeOrder` or escrow | Allowance is below `sellAmount`, or the escrow sees an allowance outside `[sellAmount, 2 * sellAmount)`, or `sellAmount` exceeds `type(uint256).max / 2`. |
| `ShortAfterFee` | escrow | Balance after pulling the full allowance is below `sellAmount`. |
| `Param Mismatch` | escrow | The params passed into `initialize` do not match the clone args. |
| `NotAuctioneer` | escrow | Something other than the auctioneer called `initialize`. |
| `Filled` | `verify` | Escrow balance or vault allowance is below `sellAmount`. |
| `PollNever("Filled")` | `getTradeableOrder` | Same condition. The watch tower should stop polling. |
| `PollNever("AuctionEnded")` | `getTradeableOrder` | `block.number >= startBlock + validFor`. |
| `PollTryAtBlock` | `getTradeableOrder` | Called before `startBlock`. |
| `OutsideWindow` | `verify` | Settlement block is outside `[startBlock, startBlock + validFor)`. |
| `BelowFloor` | `verify` | `buyAmount` is below the current Dutch price. |
| `FieldMismatch` | `verify` | A fixed order field does not match the auction. |
| `BadHash` | `verify` | The order hash does not match. |
| `AuctionInProgress` | `releaseFunds` | `block.number` is not yet greater than `startBlock + validFor`. |
| `NotSelf` | `pay` | The caller is not the escrow. |
