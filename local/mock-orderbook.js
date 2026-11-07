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
    let parsed = null;
    if (body) {
      try {
        parsed = JSON.parse(body);
      } catch {
        parsed = body;
      }
    }

    writeJsonLine({
      receivedAt: new Date().toISOString(),
      method: request.method,
      path: request.url,
      body: parsed
    });

    const path = request.url.split("?")[0];
    if (request.method === "GET" && (path.endsWith("/version") || path === "/api/version")) {
      response.writeHead(200, { "content-type": "application/json" });
      response.end(JSON.stringify({ version: "local-mock-orderbook" }));
      return;
    }

    if (request.method === "POST") {
      const uid = `0x${crypto.randomBytes(56).toString("hex")}`;
      response.writeHead(201, { "content-type": "application/json" });
      response.end(JSON.stringify(uid));
      return;
    }

    response.writeHead(200, { "content-type": "application/json" });
    response.end(JSON.stringify({ ok: true }));
  });
});

server.listen(port, "127.0.0.1", () => {
  console.log(`Mock orderbook listening on http://127.0.0.1:${port}`);
  console.log(`Writing request bodies to ${logPath}`);
});
