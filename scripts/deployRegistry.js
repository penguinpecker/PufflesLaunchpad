const ethers = require("ethers");
require("dotenv").config();
const fs = require("fs");

async function main() {
  const provider = new ethers.JsonRpcProvider(process.env.PUSH_RPC || "https://evm.donut.rpc.push.org/");
  const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
  console.log("Deploying PufflesRegistry with:", wallet.address);

  const artifact = JSON.parse(
    fs.readFileSync("artifacts/contracts/PufflesRegistry.sol/PufflesRegistry.json", "utf8")
  );

  const FACTORY = "0x6DB965f96D35853Ea7642D77ed945897447aD5b4";

  const Factory = new ethers.ContractFactory(artifact.abi, artifact.bytecode, wallet);
  const registry = await Factory.deploy(FACTORY);
  await registry.waitForDeployment();

  const addr = await registry.getAddress();
  console.log("PufflesRegistry deployed to:", addr);

  console.log("\nRegistering TestPuffles...");
  const tx = await registry.register(
    "0xe21d6cC6f5A23c82F4f1ADdfC65Dc7fED438f613",
    "test-puffles",
    "TestPuffles"
  );
  await tx.wait();
  console.log("Registered: test-puffles -> 0xe21d6cC6f5A23c82F4f1ADdfC65Dc7fED438f613");
  console.log("\nDone! Registry address:", addr);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
