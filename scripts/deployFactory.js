const ethers = require("ethers");
require("dotenv").config();
const fs = require("fs");

async function main() {
  const provider = new ethers.JsonRpcProvider("https://evm.donut.rpc.push.org/");
  const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
  console.log("Deployer:", wallet.address);

  const balance = await provider.getBalance(wallet.address);
  console.log("Balance:", ethers.formatEther(balance), "PC\n");

  // --- Deploy PufflesNFT Implementation ---
  console.log("1. Deploying PufflesNFT implementation...");
  const nftArtifact = JSON.parse(
    fs.readFileSync("artifacts/contracts/PufflesNFT.sol/PufflesNFT.json", "utf8")
  );
  const nftFactory = new ethers.ContractFactory(nftArtifact.abi, nftArtifact.bytecode, wallet);
  const impl = await nftFactory.deploy();
  await impl.waitForDeployment();
  const implAddr = await impl.getAddress();
  console.log("   PufflesNFT implementation:", implAddr);

  // --- Deploy PufflesFactory ---
  console.log("\n2. Deploying PufflesFactory...");
  const factoryArtifact = JSON.parse(
    fs.readFileSync("artifacts/contracts/PufflesFactory.sol/PufflesFactory.json", "utf8")
  );

  const TREASURY = wallet.address;  // use deployer for testnet
  const FEE_BPS = 500;              // 5% platform fee
  const CREATION_FEE = 0;           // free for testnet

  const factoryFactory = new ethers.ContractFactory(factoryArtifact.abi, factoryArtifact.bytecode, wallet);
  const factory = await factoryFactory.deploy(implAddr, TREASURY, FEE_BPS, CREATION_FEE);
  await factory.waitForDeployment();
  const factoryAddr = await factory.getAddress();
  console.log("   PufflesFactory:", factoryAddr);

  console.log("\n✅ Deployment complete!");
  console.log("   Implementation:", implAddr);
  console.log("   Factory:", factoryAddr);
  console.log("   Treasury:", TREASURY);
  console.log("   Platform Fee:", FEE_BPS / 100, "%");
  console.log("   Creation Fee:", CREATION_FEE, "wei");
}

main().catch(console.error);
