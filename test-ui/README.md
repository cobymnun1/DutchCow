# Real auction page

Base mainnet. The page calls the deployed `RealDutchCowTest` contract, which predicts the escrow, approves it, and calls `placeOrder` on the deployed auctioneer.

```bash
python3 -m http.server 4174 --bind 127.0.0.1 --directory test-ui
```

Open <http://127.0.0.1:4174> in Chrome. Connect MetaMask on Base.

The default sells the USDC amount in the form for WETH. CoinGecko supplies both token prices. The auction starts at that mid and decays 5% over 1000 blocks, so the floor asks for less WETH than the USDC is worth. Change the USDC amount and the quote updates. Edit the other fields to leave the default.

Sell tokens are transferred to `RealDutchCowTest` before `place`. Buy tokens are paid to that contract. It has no withdraw.
