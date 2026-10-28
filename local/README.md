# Local Base-fork end-to-end test

This test uses:

- `anvil` forked from Base with chain ID `8453`.
- The official watch-tower from `/mnt/provenant_data/watch-tower`.
- A local mock OrderBook API at `http://127.0.0.1:3000`.
- A `TestAuctionVault` contract as the contract owner.

The real CoW OrderBook API is intentionally not used. Orders from this fork
cannot be accepted by the real API because the fork-only owner and handler do
not exist on Base.

## 1. Check prerequisites

Set a Base RPC URL. Do not use a public RPC that cannot serve archive state.

```bash
export BASE_RPC_URL="https://..."
test -n "$BASE_RPC_URL"
```

The checked-in watch-tower repository documents these Base deployments:

```bash
export COMPOSABLE_COW=0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74
export SETTLEMENT=0x9008D19f58AAbD9eD0D60971565AA8510560ab41
export VAULT_RELAYER=0xC92E8bdf79f0507f65a392b0ab4667716BFE0110
```

The local `lib/composable-cow/networks.json` is stale and does not include
chain ID `8453`; the repository README's deployed-contract table does.
Verify the three official addresses before starting:

```bash
for address in "$COMPOSABLE_COW" "$SETTLEMENT" "$VAULT_RELAYER"; do
  code="$(~/.foundry/bin/cast code "$address" --rpc-url "$BASE_RPC_URL")"
  test "$code" != "0x" || { echo "No code at $address"; exit 1; }
  echo "$address has code"
done
```

## 2. Start the fork

```bash
~/.foundry/bin/cast block-number --rpc-url "$BASE_RPC_URL"
anvil --fork-url "$BASE_RPC_URL" --block-time 2 --chain-id 8453 \
  --port 8545 > local/anvil.log 2>&1 &
export ANVIL_PID=$!
export ANVIL_RPC=http://127.0.0.1:8545
sleep 2
export FORK_BLOCK="$(~/.foundry/bin/cast block-number --rpc-url "$ANVIL_RPC")"
echo "Fork block: $FORK_BLOCK"

for address in "$COMPOSABLE_COW" "$SETTLEMENT" "$VAULT_RELAYER"; do
  code="$(~/.foundry/bin/cast code "$address" --rpc-url "$ANVIL_RPC")"
  test "$code" != "0x" || { echo "Fork is missing $address"; exit 1; }
done
```

Keep this terminal running. Stop it later with:

```bash
kill "$ANVIL_PID"
```

## 3. Deploy the fork-only handler and owner

Use one of Anvil's printed private keys:

```bash
export ANVIL_PRIVATE_KEY="0x..."
export VAULT_OWNER="$(~/.foundry/bin/cast wallet address --private-key "$ANVIL_PRIVATE_KEY")"
export SELL_TOKEN=0x0C03Ce270B4826Ec62e7DD007f0B716068639F7B
export BUY_TOKEN=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
export RECEIVER="$VAULT_OWNER"
export SELL_AMOUNT=1000000000000000000
export MAX_AMOUNT=1000000000000000000000
export VALID_FOR=150
export SLIPPAGE_BPS=500
export SALT=0x1234567890123456789012345678901234567890123456789012345678901234

export HANDLER="$(
  ~/.foundry/bin/forge create src/DutchCoWs.sol:DutchAuction \
    --rpc-url "$ANVIL_RPC" \
    --private-key "$ANVIL_PRIVATE_KEY" \
    --broadcast --json | jq -r .deployedTo
)"

export VAULT="$(
  ~/.foundry/bin/forge create src/TestAuctionVault.sol:TestAuctionVault \
    --constructor-args "$VAULT_OWNER" "$COMPOSABLE_COW" "$VAULT_RELAYER" \
    --rpc-url "$ANVIL_RPC" \
    --private-key "$ANVIL_PRIVATE_KEY" \
    --broadcast --json | jq -r .deployedTo
)"

echo "Handler: $HANDLER"
echo "Vault:   $VAULT"
```

## 4. Fund and authorize the vault

Do not guess a token holder. Set `TOKEN_HOLDER` to a holder you verified on
Base, and confirm it has enough `SELL_TOKEN` before impersonating it:

```bash
export TOKEN_HOLDER="0x..."
~/.foundry/bin/cast call "$SELL_TOKEN" \
  "balanceOf(address)(uint256)" "$TOKEN_HOLDER" \
  --rpc-url "$BASE_RPC_URL"
```

Impersonate that holder only on the local fork, give it gas, and transfer
exactly `SELL_AMOUNT`:

```bash
~/.foundry/bin/cast rpc anvil_impersonateAccount "$TOKEN_HOLDER" \
  --rpc-url "$ANVIL_RPC"
~/.foundry/bin/cast rpc anvil_setBalance "$TOKEN_HOLDER" \
  0x3635C9ADC5DEA00000 --rpc-url "$ANVIL_RPC"
~/.foundry/bin/cast send "$SELL_TOKEN" \
  "transfer(address,uint256)" "$VAULT" "$SELL_AMOUNT" \
  --from "$TOKEN_HOLDER" --unlocked --rpc-url "$ANVIL_RPC"
~/.foundry/bin/cast call "$SELL_TOKEN" \
  "balanceOf(address)(uint256)" "$VAULT" \
  --rpc-url "$ANVIL_RPC"
```

Approve the Vault Relayer from the vault, then create the order. The script
sets `startBlock` to the current fork block plus 5 and calls
`ComposableCoW.create(..., true)` through the vault:

```bash
~/.foundry/bin/cast send "$VAULT" \
  "approveCow(address,uint256)" "$SELL_TOKEN" "$SELL_AMOUNT" \
  --private-key "$ANVIL_PRIVATE_KEY" --rpc-url "$ANVIL_RPC"

VAULT="$VAULT" HANDLER="$HANDLER" SELL_TOKEN="$SELL_TOKEN" \
BUY_TOKEN="$BUY_TOKEN" RECEIVER="$RECEIVER" SELL_AMOUNT="$SELL_AMOUNT" \
MAX_AMOUNT="$MAX_AMOUNT" VALID_FOR="$VALID_FOR" \
SLIPPAGE_BPS="$SLIPPAGE_BPS" SALT="$SALT" \
~/.foundry/bin/forge script script/CreateLocalForkOrder.s.sol \
  --rpc-url "$ANVIL_RPC" --private-key "$ANVIL_PRIVATE_KEY" --broadcast
```

## 5. Start the local mock OrderBook

The watch-tower uses `orderBookApi` and posts to
`{orderBookApi}/orders`. The mock logs every request body to JSON Lines and
returns HTTP 201 with a synthetic UID.

```bash
rm -f local/orders.jsonl
ORDER_LOG="$PWD/local/orders.jsonl" node local/mock-orderbook.js \
  > local/mock-orderbook.log 2>&1 &
export MOCK_PID=$!
```

## 6. Configure and start the watch-tower

The watch-tower README uses `deploymentBlock`, `orderBookApi`, `pageSize`, and:
`yarn cli run --config-path ./config.json`. Generate a one-network config using
the fork block, not the production deployment block:

```bash
jq --argjson block "$FORK_BLOCK" \
  '.networks[0].deploymentBlock = $block' \
  local/config.json.example > local/config.json

rm -rf local/watchtower-database
(cd /mnt/provenant_data/watch-tower && \
  LOG_LEVEL=INFO yarn cli run \
    --config-path /mnt/provenant_data/Dutch_Cow/local/config.json \
    --database-path /mnt/provenant_data/Dutch_Cow/local/watchtower-database \
    --api-port 8080) 2>&1 | tee local/watchtower.log
```

In another terminal, mine blocks:

```bash
for i in $(seq 1 5); do
  ~/.foundry/bin/cast rpc evm_mine --rpc-url "$ANVIL_RPC" >/dev/null
done
```

Watch `local/watchtower.log` and `local/orders.jsonl`. The first JSON object
after the auction starts should contain `signature`, `from`, `buyAmount`, and
the handler-generated order fields.

## Current local-run status

The environment where this README was prepared does not have `BASE_RPC_URL`,
so the fork, address-code checks, token funding, deployments, watch-tower
event processing, and end-to-end order capture have not been run here.

Preparation report:

- Official watch-tower clone: PASS (`/mnt/provenant_data/watch-tower`).
- Watch-tower dependency install: PASS, with peer-dependency warnings.
- Watch-tower build: PASS.
- Mock OrderBook implementation: PASS; its POST contract was smoke-tested on
  port 3001. Port 3000 was already occupied in the environment.
- Local Foundry setup scripts: PASS compilation.
- Handler unit tests: PASS, 24 passed.
- Base fork and real-address code checks: NOT RUN; `BASE_RPC_URL` is missing.
- Watch-tower event/poll/order capture: NOT RUN; depends on the fork.
- Stale-order, tamper, and expiry checks: NOT RUN end-to-end; the handler unit
  tests cover the corresponding verification logic.
