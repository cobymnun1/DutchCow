#!/usr/bin/env node

const fs = require("node:fs");
const http = require("node:http");
const crypto = require("node:crypto");

const port = Number(process.env.PORT || 3000);
const logPath = process.env.ORDER_LOG || "orders.jsonl";

function writeJsonLine(value) {
  fs.appendFileSync(logPath, `${JSON.stringify(value)}\n`);
}

const server = http.createServer((request, response) => {
  const chunks = [];
  request.on("data", chunk => chunks.push(chunk));
  request.on("end", () => {
    const body = Buffer.concat(chunks).toString();
    let parsed;
    try {
      parsed = body ? JSON.parse(body) : null;
    } catch {
      response.writeHead(400, { "content-type": "application/json" });
      response.end(JSON.stringify({ error: "invalid JSON" }));
      return;
    }

    if (request.method === "POST" && request.url === "/api/v1/orders") {
      writeJsonLine({
        receivedAt: new Date().toISOString(),
        method: request.method,
        path: request.url,
        body: parsed
      });
      const uid = `0x${crypto.randomBytes(56).toString("hex")}`;
      response.writeHead(201, { "content-type": "application/json" });
      response.end(JSON.stringify(uid));
      return;
    }

    if (request.method === "GET" && request.url === "/api/v1/version") {
      response.writeHead(200, { "content-type": "application/json" });
      response.end(JSON.stringify({ version: "local-mock-orderbook" }));
      return;
    }

    response.writeHead(404, { "content-type": "application/json" });
    response.end(JSON.stringify({ error: "not found" }));
  });
});

server.listen(port, "127.0.0.1", () => {
  console.log(`Mock orderbook listening on http://127.0.0.1:${port}`);
  console.log(`Writing POST /api/v1/orders bodies to ${logPath}`);
});
