# DutchAuction test UI

This static page targets Base mainnet and uses the deployed contracts:

- Handler: `0xEA0dF15691b8bF7A9FBf304Fc1A21193a5C5b11a`
- ComposableCoW: `0xfdaFc9d1902f4e0b84f65F49f244b32b31013b74`

Run it locally:

```bash
python3 -m http.server 8080 --directory test-ui
```

Open <http://127.0.0.1:8080>.

Deploy `TestAuctionVault` first. The page then encodes the handler's
`staticInput`, the vault's `createOrder` transaction, and its `approveCow`
transaction. Submit both from the vault controller EOA. The vault owns the
tokens and authorizes the order; it approves CoW's Base vault relayer, not
ComposableCoW.
