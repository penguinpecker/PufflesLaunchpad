const ethers = require("ethers");
require("dotenv").config();
const fs = require("fs");

async function main() {
  const provider = new ethers.JsonRpcProvider("https://evm.donut.rpc.push.org/");
  const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);

  const factoryArtifact = JSON.parse(
    fs.readFileSync("artifacts/contracts/PufflesFactory.sol/PufflesFactory.json", "utf8")
  );
  const factory = new ethers.Contract("0x6DB965f96D35853Ea7642D77ed945897447aD5b4", factoryArtifact.abi, wallet);

  console.log("Creating test collection...\n");

  const tx = await factory.createCollection(
    "TestPuffles",
    "TPUF",
    wallet.address,
    "ipfs://hidden/hidden.json",
    100,
    2,
    5,
    5,
    ethers.parseEther("0.01"),
    ethers.parseEther("0.02"),
    wallet.address,
    750
  );

  const receipt = await tx.wait();
  console.log("✅ Collection created!");
  console.log("   Tx:", receipt.hash);

  const total = await factory.totalCollections();
  const cloneAddr = await factory.collections(total - 1n);
  console.log("   Clone address:", cloneAddr);
  console.log("   Total collections:", total.toString());
}

main().catch(console.error);
