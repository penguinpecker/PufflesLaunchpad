const ethers = require("ethers");
require("dotenv").config();

async function main() {
  const provider = new ethers.JsonRpcProvider("https://evm.donut.rpc.push.org/");
  const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
  console.log("Deploying with:", wallet.address);

  const FACTORY = "0x6DB965f96D35853Ea7642D77ed945897447aD5b4";
  const REGISTRY = "0xf432bAca7C6CA54a2D02B6b30ccdE9d2cD104538";
  const TREASURY = "0xffD9E66c997391b01E5ca3f36E13ab3e786a8c42";

  const factoryAbi = [
    "function createCollection(string _name, string _symbol, address _owner, string _notRevealedURI, uint256 _maxSupply, uint256 _maxPerWalletWL, uint256 _maxPerWalletPublic, uint256 _maxPerTx, uint256 _wlPrice, uint256 _pubPrice, address _royaltyReceiver, uint96 _royaltyBps) external payable returns (address clone)",
    "function creationFee() view returns (uint256)"
  ];

  const registryAbi = [
    "function register(address collection, string slug, string name) external"
  ];

  const factory = new ethers.Contract(FACTORY, factoryAbi, wallet);
  const registry = new ethers.Contract(REGISTRY, registryAbi, wallet);

  // Check creation fee
  const fee = await factory.creationFee();
  console.log("Creation fee:", ethers.formatEther(fee), "ETH");

  // Deploy collection
  console.log("\nCreating Moleswap x Push Chain collection...");
  const tx = await factory.createCollection(
    "Moleswap x Push Chain",   // name
    "MPC",                      // symbol
    wallet.address,             // owner
    "",                         // notRevealedURI (empty for now)
    10000,                      // maxSupply
    1,                          // maxPerWalletWL
    1,                          // maxPerWalletPublic
    1,                          // maxPerTx
    ethers.parseEther("0.069"), // wlPrice
    ethers.parseEther("0.069"), // pubPrice
    TREASURY,                   // royaltyReceiver
    500,                        // royaltyBps (5%)
    { value: fee }
  );

  console.log("Tx:", tx.hash);
  const receipt = await tx.wait();
  console.log("Confirmed in block:", receipt.blockNumber);

  // Get clone address from logs
  const cloneAddress = receipt.logs
    .map(log => { try { return factory.interface.parseLog(log); } catch { return null; } })
    .find(e => e && e.name === "CollectionCreated")
    ?.args?.clone;

  if (!cloneAddress) {
    // Fallback: get from return data
    console.log("Could not parse event, checking factory...");
    console.log("Check tx on explorer:", `https://donut.push.network/tx/${tx.hash}`);
    return;
  }

  console.log("\nCollection deployed to:", cloneAddress);

  // Register slug
  console.log("\nRegistering slug: moleswap-x-push-chain");
  const regTx = await registry.register(
    cloneAddress,
    "moleswap-x-push-chain",
    "Moleswap x Push Chain"
  );
  await regTx.wait();
  console.log("Registered!");

  console.log("\n========================================");
  console.log("Collection:", cloneAddress);
  console.log("Mint URL:   https://puffles.io/mint/moleswap-x-push-chain");
  console.log("========================================");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
