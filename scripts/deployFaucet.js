const ethers = require("ethers");
require("dotenv").config();
const fs = require("fs");

async function main() {
  const provider = new ethers.JsonRpcProvider("https://evm.donut.rpc.push.org/");
  const wallet = new ethers.Wallet(process.env.PRIVATE_KEY, provider);
  console.log("Deploying PufflesFaucet with:", wallet.address);

  const artifact = JSON.parse(
    fs.readFileSync("artifacts/contracts/PufflesFaucet.sol/PufflesFaucet.json", "utf8")
  );

  const DRIP_AMOUNT = ethers.parseEther("0.1");  // 0.1 PC per request
  const COOLDOWN = 86400;                         // 24 hours in seconds

  const Factory = new ethers.ContractFactory(artifact.abi, artifact.bytecode, wallet);
  const faucet = await Factory.deploy(DRIP_AMOUNT, COOLDOWN);
  await faucet.waitForDeployment();

  const addr = await faucet.getAddress();
  console.log("PufflesFaucet deployed to:", addr);

  // Fund the faucet with some initial PC
  console.log("\nFunding faucet with 10 PC...");
  const tx = await wallet.sendTransaction({
    to: addr,
    value: ethers.parseEther("10")
  });
  await tx.wait();
  console.log("Funded!");

  const balance = await provider.getBalance(addr);
  console.log("Faucet balance:", ethers.formatEther(balance), "PC");

  console.log("\n========================================");
  console.log("Faucet Contract:", addr);
  console.log("Drip Amount:    0.1 PC");
  console.log("Cooldown:       24 hours");
  console.log("Balance:        " + ethers.formatEther(balance) + " PC");
  console.log("========================================");
  console.log("\nIMPORTANT: Update FAUCET_ADDRESS in frontend/faucet.html with:", addr);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
