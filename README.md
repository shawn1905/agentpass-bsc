# AgentPass.ai — Binance Agent ID Intelligence Pass & On-Chain AI Directory

Built for the **Binance Wallet × BNB Chain Agent ID Hackathon** (Nov 18 – Dec 9, 2026).

## What It Does
**AgentPass.ai** turns Binance's non-transferable **Agent ID (`name.ai`)** on BNB Smart Chain into a real, working **zero-custody AI API pass and Sybil-resistant Agent Directory**:

1. **Free 24-Hour Intelligence Pass (`claimPass`)**: Any wallet holding a Binance Agent ID (`0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`) claims a 24h pass on BNB Smart Chain (`0` protocol fee, gas-only) and builds an on-chain streak.
2. **Real Live Utility — 7 Zero-Proxy AI Intelligence APIs Unlocked (`$0.00`)**: Signing a free off-chain EIP-191 message lets the Cloudflare Worker (`https://x402-zero-proxy-api.x402-zero-proxy-api.workers.dev`) verify `hasActivePass(address)` directly against BNB Smart Chain RPC and grant free access to 7 live endpoints (normally billed per-request via x402 Base USDC):
   - `GET /v1/sec/filings` — US SEC EDGAR 10-K/10-Q/8-K filings
   - `GET /v1/markets/odds` — Live Polymarket probabilities & liquidity
   - `GET /v1/markdown` — Webpage to LLM/RAG Markdown (zero headless browser)
   - `GET /v1/website/enrich` — Company emails, socials & 25+ tech stack signals
   - `GET /v1/yc/search` — Search 6,400+ Y Combinator startups
   - `GET /v1/shopify/products` — Live Shopify catalog, discounts & inventory
   - `GET /v1/news/search` — Real-time Google News RSS across 50+ countries
3. **Sybil-Resistant AI Agent Endpoint Directory (`registerAgentEndpoint` + `endorseAgent`)**: Because each KYC-verified Binance user can hold only one non-transferable `name.ai` NFT, every published MCP/x402 endpoint and peer endorsement is naturally Sybil-resistant.
4. **Zero QR-Code Login**: Uses direct EIP-1193 / EIP-6963 injected wallet connections (Binance Wallet Extension, Binance App DApp Browser, MetaMask) plus a pure-CLI Agentic Wallet script (`scripts/call-with-agentpass.mjs`).

## Security Posture & Owner Permissions Disclosure
- **Owner / Admin Role**: **None** (fully ownerless & immutable).
- **Custody / Fees / Pause / Mint**: **None** — the contract does not accept BNB (`receive`/`fallback` omitted), charges zero fees, cannot be paused, and cannot custody user assets.
- **On-Chain Access Control**: Every write function enforces `IAgentID(0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F).balanceOf(msg.sender) > 0`.

## Contracts & Architecture
- **Official Binance / SPACE ID Agent ID (BSC Mainnet)**: `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`
- **Deployed AgentPassRegistry (BSC Mainnet)**: [`0x315fF606193d638A59a5CD58bba83E048c1c4e96`](https://bscscan.com/address/0x315fF606193d638A59a5CD58bba83E048c1c4e96)
- **Compiler**: Solidity `0.8.28`, `evmVersion: paris`, optimizer `200` runs.
- **BscScan Standard JSON Input**: `artifacts/BscScanStandardJsonInput.json`
- **Live Intelligence Gateway**: `https://x402-zero-proxy-api.x402-zero-proxy-api.workers.dev`
- **Live Web App (GitHub Pages)**: `https://shawn1905.github.io/agentpass-bsc/`

## Local Verification
```bash
npm install
node test/run_tests.mjs
```
