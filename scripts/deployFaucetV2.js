const ethers = require("ethers");
require("dotenv").config();
const fs = require("fs");

async function main() {
  const provider = new ethers.JsonRpcProvider("https://evm.donut.rpc.push.org/");
  const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
  console.log("Deploying PufflesFaucetV2 with:", wallet.address);

  const artifact = JSON.parse(
    fs.readFileSync("artifacts/contracts/PufflesFaucetV2.sol/PufflesFaucetV2.json", "utf8")
  );

  const DRIP_AMOUNT = ethers.parseEther("0.1");  // 0.1 PC per request
  const COOLDOWN = 86400;                         // 24 hours
  const RELAYER = wallet.address;                  // Deployer is also relayer for testnet

  const Factory = new ethers.ContractFactory(artifact.abi, artifact.bytecode, wallet);
  const faucet = await Factory.deploy(DRIP_AMOUNT, COOLDOWN, RELAYER);
  await faucet.waitForDeployment();

  const addr = await faucet.getAddress();
  console.log("\n========================================");
  console.log("PufflesFaucetV2:", addr);
  console.log("Drip Amount:     0.1 PC");
  console.log("Cooldown:        24 hours");
  console.log("Relayer:        ", RELAYER);
  console.log("========================================");
  console.log("\nNext steps:");
  console.log("1. Fund the faucet:  send PC to", addr);
  console.log("2. Update FAUCET_ADDRESS in frontend/faucet.html");
  console.log("3. Set FAUCET_RELAYER_KEY in Cloudflare Pages env vars");
  console.log("   (same as your PRIVATE_KEY for testnet)");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
