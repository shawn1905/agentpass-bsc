#!/usr/bin/env node
/**
 * Autonomous AI Agent / Agentic Wallet CLI client for AgentPass.ai on BNB Smart Chain.
 * Usage:
 *   AGENT_PRIVATE_KEY=0x... REGISTRY=0x... node scripts/call-with-agentpass.mjs /v1/sec/filings "ticker=NVDA&form=10-K&limit=3"
 */
import { ethers } from "ethers";

const BSC_RPC = process.env.BSC_RPC || "https://bsc-dataseed.binance.org/";
const API_BASE = process.env.API_BASE || "https://x402-zero-proxy-api.x402-zero-proxy-api.workers.dev";
const REGISTRY = process.env.REGISTRY || "";
const PK = process.env.AGENT_PRIVATE_KEY || "";

if (!PK) {
  console.error("Set AGENT_PRIVATE_KEY=0x... (your Agent ID wallet private key) to run.");
  process.exit(1);
}

const endpoint = process.argv[2] || "/v1/sec/filings";
const query = process.argv[3] || "ticker=NVDA&form=10-K&limit=3";

const provider = new ethers.JsonRpcProvider(BSC_RPC);
const wallet = new ethers.Wallet(PK, provider);

if (REGISTRY) {
  const reg = new ethers.Contract(
    REGISTRY,
    ["function hasActivePass(address) view returns (bool)", "function claimPass(string)"],
    wallet,
  );
  const active = await reg.hasActivePass(wallet.address);
  if (!active) {
    console.log("No active 24h pass — claiming on BNB Smart Chain...");
    const tx = await reg.claimPass(process.env.AGENT_LABEL || "");
    console.log("Tx:", tx.hash);
    await tx.wait();
  }
}

const ts = String(Math.floor(Date.now() / 1000));
const msg = [
  "AgentPass.ai Intelligence Access",
  `Address: ${wallet.address.toLowerCase()}`,
  `Timestamp: ${ts}`,
  "Chain: BNB Smart Chain (56)",
].join("\n");
const sig = await wallet.signMessage(msg);

const url = `${API_BASE}${endpoint}?${query}`;
const res = await fetch(url, {
  headers: {
    "x-agentpass-address": wallet.address,
    "x-agentpass-timestamp": ts,
    "x-agentpass-signature": sig,
  },
});

console.log("HTTP:", res.status, "Auth-Rail:", res.headers.get("x-auth-rail"));
console.log(await res.text());
