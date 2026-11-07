# Local Base Sepolia fork

Anvil forks Base Sepolia and overrides the chain id to `8453`, so the unmodified watch tower treats it as Base and polls ComposableCoW at `0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74`. That address has no code on Base Sepolia, so a ComposableCoW built against the Sepolia settlement is copied there with `anvil_setCode`. The settlement domain separator is unchanged by the chain-id override.

The RPC URL stays in `BASE_SEPOLIA_RPC_URL`. It is not written into this repo.

## 1. Fork

```bash
export BASE_SEPOLIA_RPC_URL="https://..."
anvil --fork-url "$BASE_SEPOLIA_RPC_URL" --block-time 0.2 --chain-id 8453 --port 8545 \
  > local/anvil.log 2>&1 &
export ANVIL_RPC=http://127.0.0.1:8545
export SETTLEMENT=0x9008D19f58AAbD9eD0D60971565AA8510560ab41
export COMPOSABLE_COW=0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74
export VAULT_RELAYER=0xC92E8bdf79f0507f65a392b0ab4667716BFE0110
```

Deploy ComposableCoW, copy its runtime onto the canonical address, and authorize anvil account 0 (`0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`) as a solver by impersonating authenticator manager `0x6Fb5916c0f57f88004d5b5EB25f6f4D77353a1eD` and calling `addSolver` on `0x2c4c28DDBdAc9C5E7055b4C863b72eA0149D8aFE`.

```bash
forge script script/DeployAuctioneer.s.sol:DeployComposableCoW \
  --rpc-url "$ANVIL_RPC" --private-key "$ANVIL_PRIVATE_KEY" --broadcast
# anvil_setCode the runtime onto $COMPOSABLE_COW, then:
export COMPOSABLE_COW=0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74
forge script script/DeployAuctioneer.s.sol:DeployAuctioneer \
  --rpc-url "$ANVIL_RPC" --private-key "$ANVIL_PRIVATE_KEY" --broadcast
```

## 2. Mock orderbook and watch tower

```bash
FORK_BLOCK="$(cast block-number --rpc-url "$ANVIL_RPC")"
jq --argjson block "$FORK_BLOCK" \
  '.networks[0].deploymentBlock = $block | .networks[0].orderBookApi = "http://127.0.0.1:3001/api/v1"' \
  local/config.json.example > local/config.json
PORT=3001 ORDER_LOG="$PWD/local/orders.jsonl" node local/mock-orderbook.js \
  > local/mock-orderbook.log 2>&1 &
(cd /mnt/provenant_data/watch-tower && LOG_LEVEL=INFO yarn cli run \
  --config-path /mnt/provenant_data/Dutch_Cow/local/config.json \
  --database-path /mnt/provenant_data/Dutch_Cow/local/watchtower-database \
  --api-port 8080 --silent) > local/watchtower.log 2>&1 &
```

The tower logs chain `8453` and polls about every 0.2s.

## 3. Place and settle

`placeOrder` is same-transaction only: `startBlock == block.number`, `receiver == msg.sender`, `validFor >= 25`, allowance in `[sellAmount, 2 * sellAmount)`. `script/PlaceLocalForkOrder.s.sol` places through `TreasurySeller`.

```bash
export ANVIL_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
export CLIENT=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
node local/solve.js            # newest posted order
node local/solve.js 0xEscrow   # newest order for one escrow
```

`local/solve.js` calls `script/SettlePostedOrder.s.sol`, which mints the buy token to the settlement and settles as the authorized solver with clearing prices `[buyAmount, sellAmount]`.
