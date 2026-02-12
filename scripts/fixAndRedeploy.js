const ethers = require("ethers");
require("dotenv").config();

async function main() {
  const provider = new ethers.JsonRpcProvider("https://evm.donut.rpc.push.org/");
  const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
  const treasuryWallet = new ethers.Wallet(process.env.TREASURY_KEY, provider);
  console.log("Deployer:", wallet.address);
  console.log("Treasury:", treasuryWallet.address);

  const FACTORY = "0x6DB965f96D35853Ea7642D77ed945897447aD5b4";
  const REGISTRY = "0xf432bAca7C6CA54a2D02B6b30ccdE9d2cD104538";
  const TREASURY = "0xffD9E66c997391b01E5ca3f36E13ab3e786a8c42";
  const OLD_MOLESWAP = "0x9CF73651738bB774F720F92DcC6296F0cF605004";

  // --- Step 0: Transfer factory ownership to deployer ---
  console.log("\n[0/5] Transferring factory ownership to deployer...");
  const factoryAsTreasury = new ethers.Contract(FACTORY, [
    "function transferOwnership(address) external"
  ], treasuryWallet);
  let tx = await factoryAsTreasury.transferOwnership(wallet.address);
  await tx.wait();
  console.log("Factory ownership transferred to", wallet.address);

  // --- Step 1: Deploy fixed implementation ---
  console.log("\n[1/5] Deploying fixed PufflesNFT implementation...");
  const artifact = require("../artifacts/contracts/PufflesNFT.sol/PufflesNFT.json");
  const Factory = new ethers.ContractFactory(artifact.abi, artifact.bytecode, wallet);
  const impl = await Factory.deploy();
  await impl.waitForDeployment();
  const implAddr = await impl.getAddress();
  console.log("New implementation:", implAddr);

  // --- Step 2: Update factory ---
  console.log("\n[2/5] Updating factory implementation...");
  const factory = new ethers.Contract(FACTORY, [
    "function setImplementation(address) external",
    "function createCollection(string,string,address,string,uint256,uint256,uint256,uint256,uint256,uint256,address,uint96) external payable returns (address)",
    "function creationFee() view returns (uint256)"
  ], wallet);
  tx = await factory.setImplementation(implAddr);
  await tx.wait();
  console.log("Factory updated");

  // --- Step 3: Remove old Moleswap registration ---
  console.log("\n[3/5] Removing old Moleswap registration...");
  const registry = new ethers.Contract(REGISTRY, [
    "function remove(address) external",
    "function register(address,string,string) external"
  ], wallet);
  tx = await registry.remove(OLD_MOLESWAP);
  await tx.wait();
  console.log("Old registration removed");

  // --- Step 4: Deploy new Moleswap collection ---
  console.log("\n[4/5] Creating new Moleswap x Push Chain collection...");
  const fee = await factory.creationFee();
  tx = await factory.createCollection(
    "Moleswap x Push Chain",
    "MPC",
    wallet.address,
    "",
    10000,
    1,
    1,
    1,
    ethers.parseEther("0.069"),
    ethers.parseEther("0.069"),
    TREASURY,
    500,
    { value: fee }
  );
  const receipt = await tx.wait();
  console.log("Tx:", tx.hash);

  // Get new clone address
  const totalAbi = ["function totalCollections() view returns (uint256)", "function collections(uint256) view returns (address)"];
  const factoryRead = new ethers.Contract(FACTORY, totalAbi, provider);
  const total = await factoryRead.totalCollections();
  const newClone = await factoryRead.collections(Number(total) - 1n);
  console.log("New Moleswap clone:", newClone);

  // --- Step 5: Register slug ---
  console.log("\n[5/5] Registering slug...");
  tx = await registry.register(newClone, "moleswap-x-push-chain", "Moleswap x Push Chain");
  await tx.wait();
  console.log("Slug registered!");

  // --- Enable public mint ---
  console.log("\nEnabling public mint...");
  const nft = new ethers.Contract(newClone, ["function setSalePhase(uint8) external"], wallet);
  tx = await nft.setSalePhase(2);
  await tx.wait();
  console.log("Public mint LIVE!");

  console.log("\n========================================");
  console.log("Implementation:", implAddr);
  console.log("Collection:    ", newClone);
  console.log("Mint URL:       https://puffles.io/mint/moleswap-x-push-chain");
  console.log("========================================");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
