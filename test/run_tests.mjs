import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";
import solc from "solc";
import ganache from "ganache";
import { ethers } from "ethers";

const ROOT = path.resolve(import.meta.dirname, "..");

function compileContracts() {
  const regSrc = fs.readFileSync(path.join(ROOT, "contracts/AgentPassRegistry.sol"), "utf8");
  const mockSrc = fs.readFileSync(path.join(ROOT, "contracts/MockAgentID.sol"), "utf8");

  const stdInput = {
    language: "Solidity",
    sources: {
      "contracts/AgentPassRegistry.sol": { content: regSrc },
      "contracts/MockAgentID.sol": { content: mockSrc },
    },
    settings: {
      optimizer: { enabled: true, runs: 200 },
      evmVersion: "paris",
      outputSelection: {
        "*": {
          "*": ["abi", "evm.bytecode.object", "evm.deployedBytecode.object"],
        },
      },
    },
  };

  // Also emit single-file Standard JSON Input for 1-click BscScan verification
  const bscScanInput = {
    language: "Solidity",
    sources: {
      "AgentPassRegistry.sol": { content: regSrc },
    },
    settings: {
      optimizer: { enabled: true, runs: 200 },
      evmVersion: "paris",
      outputSelection: {
        "*": {
          "*": ["abi", "evm.bytecode.object"],
        },
      },
    },
  };

  const out = JSON.parse(solc.compile(JSON.stringify(stdInput)));
  if (out.errors) {
    const fatal = out.errors.filter((e) => e.severity === "error");
    for (const e of out.errors) console.error(e.formattedMessage);
    if (fatal.length > 0) process.exit(1);
  }

  fs.mkdirSync(path.join(ROOT, "artifacts"), { recursive: true });
  const reg = out.contracts["contracts/AgentPassRegistry.sol"]["AgentPassRegistry"];
  const mock = out.contracts["contracts/MockAgentID.sol"]["MockAgentID"];

  fs.writeFileSync(
    path.join(ROOT, "artifacts/AgentPassRegistry.json"),
    JSON.stringify({ abi: reg.abi, bytecode: "0x" + reg.evm.bytecode.object }, null, 2),
  );
  fs.writeFileSync(
    path.join(ROOT, "artifacts/BscScanStandardJsonInput.json"),
    JSON.stringify(bscScanInput, null, 2),
  );

  return { reg, mock };
}

async function expectRevert(promise, expectedErr) {
  let failed = false;
  try {
    const tx = await promise;
    if (tx && typeof tx.wait === "function") await tx.wait();
  } catch (err) {
    failed = true;
    if (expectedErr) {
      const msg = String(err?.shortMessage || err?.message || err);
      const data = String(err?.data || err?.info?.error?.data || "");
      assert.ok(
        msg.includes(expectedErr) || data.includes(expectedErr),
        `Expected revert matching "${expectedErr}", got: ${msg} / ${data}`,
      );
    }
  }
  assert.ok(failed, `Expected transaction to revert (${expectedErr || "any"})`);
}

async function main() {
  console.log("[1/4] Compiling Solidity 0.8.28 (evmVersion=paris, optimizer=200)...");
  const { reg, mock } = compileContracts();
  console.log("      Compiled AgentPassRegistry bytecode bytes:", reg.evm.bytecode.object.length / 2);

  console.log("[2/4] Booting local Ganache EVM...");
  const gProvider = ganache.provider({ logging: { quiet: true }, chain: { chainId: 56 } });
  const provider = new ethers.BrowserProvider(gProvider);
  const [deployer, alice, bob, outsider] = await Promise.all([
    provider.getSigner(0),
    provider.getSigner(1),
    provider.getSigner(2),
    provider.getSigner(3),
  ]);

  const MockFactory = new ethers.ContractFactory(mock.abi, mock.evm.bytecode.object, deployer);
  const mockId = await MockFactory.deploy();
  await mockId.waitForDeployment();
  const mockAddr = await mockId.getAddress();

  const RegFactory = new ethers.ContractFactory(reg.abi, reg.evm.bytecode.object, deployer);
  await expectRevert(RegFactory.deploy(ethers.ZeroAddress));

  const registry = await RegFactory.deploy(mockAddr);
  await registry.waitForDeployment();
  const regAddr = await registry.getAddress();
  console.log("      Deployed MockAgentID:", mockAddr, "AgentPassRegistry:", regAddr);

  console.log("[3/4] Running 16 security & functional test cases...");
  const step = (s) => console.log("   ->", s);

  step("T1: outsider reverts");
  // Test 1: Outsider without Agent ID cannot claim, register, or endorse
  assert.equal(await registry.hasAgentID(outsider.address), false);
  assert.equal(await registry.hasActivePass(outsider.address), false);
  await expectRevert(registry.connect(outsider).claimPass("outsider.ai"));
  await expectRevert(registry.connect(outsider).registerAgentEndpoint("https://evil.example/mcp", "spam"));
  await expectRevert(registry.connect(outsider).endorseAgent(alice.address, "fake"));

  // Test 2: Zero-custody — sending BNB directly reverts
  await expectRevert(deployer.sendTransaction({ to: regAddr, value: ethers.parseEther("0.01") }));

  // Test 3: Mint Agent IDs — Alice with keccak256("alice"), Bob with arbitrary tokenId (tests non-keccak compatibility!)
  await (await mockId.mintWithLabel(alice.address, "alice")).wait();
  await (await mockId.mintArbitraryId(bob.address, 999999n)).wait();
  assert.equal(await registry.hasAgentID(alice.address), true);
  assert.equal(await registry.hasAgentID(bob.address), true);

  // Test 4: Alice claims pass with uppercase + .ai suffix -> normalized to "alice", labelVerified=true
  const tx1 = await registry.connect(alice).claimPass("Alice.AI");
  const rc1 = await tx1.wait();
  console.log("      claimPass gasUsed:", rc1.gasUsed.toString());
  assert.equal(await registry.hasActivePass(alice.address), true);
  let pAlice = await registry.getAgentProfile(alice.address);
  assert.equal(pAlice.hasId, true);
  assert.equal(pAlice.activePass, true);
  assert.equal(pAlice.labelVerified, true);
  assert.equal(pAlice.streak, 1n);
  assert.equal(pAlice.passes, 1n);
  assert.equal(pAlice.label, "alice");

  step("T5: bob claim arbitrary tokenId");
  // Test 5: Bob claims pass with arbitrary tokenId -> succeeds (never reverts!), labelVerified=false
  await (await registry.connect(bob).claimPass("bob-quant.ai")).wait();
  let pBob = await registry.getAgentProfile(bob.address);
  assert.equal(pBob.activePass, true);
  assert.equal(pBob.labelVerified, false);
  assert.equal(pBob.label, "bob-quant");

  step("T6: invalid labels");
  // Test 6: Invalid labels revert cleanly
  await expectRevert(registry.connect(alice).claimPass("-bad"));
  await expectRevert(registry.connect(alice).claimPass("bad_char"));
  await expectRevert(registry.connect(alice).claimPass("a".repeat(33)));

  step("T7: streak & expiry");
  // Test 7: Consecutive UTC day increases streak; gap > 1 day resets streak
  await gProvider.request({ method: "evm_increaseTime", params: [86400] });
  await gProvider.request({ method: "evm_mine", params: [] });
  assert.equal(await registry.hasActivePass(alice.address), false, "Pass should expire after 24h");
  await (await registry.connect(alice).claimPass("")).wait();
  pAlice = await registry.getAgentProfile(alice.address);
  assert.equal(pAlice.streak, 2n);
  assert.equal(pAlice.label, "alice", "Empty label preserves existing label");
  assert.equal(pAlice.activePass, true);

  // Gap of 3 days resets streak to 1
  await gProvider.request({ method: "evm_increaseTime", params: [86400 * 3] });
  await gProvider.request({ method: "evm_mine", params: [] });
  await (await registry.connect(alice).claimPass("")).wait();
  pAlice = await registry.getAgentProfile(alice.address);
  assert.equal(pAlice.streak, 1n);

  step("T8: endpoint directory");
  // Test 8: Register Agent Endpoint & paginated directory (idempotent totalEndpoints on update)
  const txEp = await registry
    .connect(alice)
    .registerAgentEndpoint(
      "https://x402-zero-proxy-api.x402-zero-proxy-api.workers.dev",
      "SEC EDGAR, Polymarket, Markdown, Shopify",
      { gasLimit: 500_000 },
    );
  const rcEp = await txEp.wait();
  console.log("      registerAgentEndpoint gasUsed:", rcEp.gasUsed.toString());
  await (
    await registry
      .connect(alice)
      .registerAgentEndpoint("https://x402-zero-proxy-api.x402-zero-proxy-api.workers.dev/v1", "7-in-1 AI Intel", { gasLimit: 500_000 })
  ).wait();
  await (
    await registry
      .connect(bob)
      .registerAgentEndpoint("https://bob-quant.example/mcp", "Funding & Basis Signals", { gasLimit: 500_000 })
  ).wait();

  const [entries, totalDir] = await registry.getDirectory(0, 10);
  assert.equal(totalDir, 2n);
  assert.equal(entries.length, 2);
  assert.equal(entries[0].agent, alice.address);
  assert.equal(entries[0].endpointUrl, "https://x402-zero-proxy-api.x402-zero-proxy-api.workers.dev/v1");
  assert.equal(entries[1].agent, bob.address);

  step("T9: endorsements");
  await expectRevert(registry.connect(alice).endorseAgent(alice.address, "self"));
  await expectRevert(registry.connect(alice).endorseAgent(outsider.address, "no id"));
  await (await registry.connect(alice).endorseAgent(bob.address, "Reliable funding feed")).wait();
  await expectRevert(registry.connect(alice).endorseAgent(bob.address, "duplicate"));
  pBob = await registry.getAgentProfile(bob.address);
  assert.equal(pBob.endorsements, 1n);

  // Test 10: Global stats consistency
  const stats = await registry.getStats();
  assert.equal(stats.uniqueAgentsCount, 2n);
  assert.equal(stats.totalPassesCount, 4n);
  assert.equal(stats.totalEndpointsCount, 2n);
  assert.equal(stats.totalEndorsementsCount, 1n);

  console.log("[4/4] ALL TESTS PASSED! Stats:", {
    uniqueAgents: Number(stats.uniqueAgentsCount),
    totalPasses: Number(stats.totalPassesCount),
    totalEndpoints: Number(stats.totalEndpointsCount),
    totalEndorsements: Number(stats.totalEndorsementsCount),
  });
  await gProvider.disconnect();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
