#!/usr/bin/env node
/**
 * Settle the newest posted order for one escrow (or the newest order overall)
 * through the forked GPv2 settlement. Reads local/orders.jsonl.
 *
 *   node local/solve.js [escrowAddress]
 */
const fs = require("node:fs");
const { spawnSync } = require("node:child_process");
const path = require("node:path");

const root = path.resolve(__dirname, "..");
const logPath = process.env.ORDER_LOG || path.join(root, "local/orders.jsonl");
const want = (process.argv[2] || "").toLowerCase();

const lines = fs.readFileSync(logPath, "utf8").split("\n").filter(Boolean);
const orders = [];
for (const line of lines) {
  let row;
  try { row = JSON.parse(line); } catch { continue; }
  const body = row.body;
  if (!body || !body.signature || !body.sellToken) continue;
  if (want && String(body.from || "").toLowerCase() !== want) continue;
  if (Number(body.validTo) <= Math.floor(Date.now() / 1000)) continue;
  orders.push(body);
}
if (orders.length === 0) {
  console.error("no posted order found");
  process.exit(1);
}
const order = orders[orders.length - 1];
function eip1271Signature(owner, signature) {
  const raw = signature.toLowerCase().replace(/^0x/, "");
  const who = owner.toLowerCase().replace(/^0x/, "");
  if (raw.startsWith(who)) return "0x" + raw;
  return "0x" + who + raw;
}
const env = {
  ...process.env,
  PATH: `${process.env.HOME}/.foundry/bin:${process.env.PATH}`,
  SELL_TOKEN: order.sellToken,
  BUY_TOKEN: order.buyToken,
  RECEIVER: order.receiver,
  SELL_AMOUNT: order.sellAmount,
  BUY_AMOUNT: order.buyAmount,
  VALID_TO: String(order.validTo),
  APP_DATA: order.appData,
  SIGNATURE: eip1271Signature(order.from, order.signature),
};
console.log(JSON.stringify({
  from: order.from,
  sellAmount: order.sellAmount,
  buyAmount: order.buyAmount,
  validTo: order.validTo,
  receiver: order.receiver,
}, null, 2));
const result = spawnSync(
  "forge",
  ["script", "script/SettlePostedOrder.s.sol:SettlePostedOrder", "--rpc-url", process.env.ANVIL_RPC || "http://127.0.0.1:8545", "--private-key", process.env.ANVIL_PRIVATE_KEY || "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80", "--broadcast"],
  { cwd: root, env, encoding: "utf8" }
);
process.stdout.write(result.stdout || "");
process.stderr.write(result.stderr || "");
process.exit(result.status ?? 1);
