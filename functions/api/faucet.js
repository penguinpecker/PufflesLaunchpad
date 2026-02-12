import { ethers } from "ethers";

const RPC = "https://evm.donut.rpc.push.org/";
const FAUCET_ABI = ["function dripTo(address recipient) external"];

// CORS headers
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

export async function onRequestOptions() {
  return new Response(null, { headers: corsHeaders });
}

export async function onRequestPost(context) {
  try {
    const { address, signature, message } = await context.request.json();

    // Validate inputs
    if (!address || !signature || !message) {
      return jsonResponse(400, { error: "Missing address, signature, or message" });
    }

    // Verify the expected message format
    const expectedMessage = `Puffles Faucet: Request PC for ${address.toLowerCase()}`;
    if (message.toLowerCase() !== expectedMessage.toLowerCase()) {
      return jsonResponse(400, { error: "Invalid message format" });
    }

    // Recover signer from signature and verify it matches claimed address
    let recoveredAddress;
    try {
      recoveredAddress = ethers.verifyMessage(message, signature);
    } catch (e) {
      return jsonResponse(400, { error: "Invalid signature" });
    }

    if (recoveredAddress.toLowerCase() !== address.toLowerCase()) {
      return jsonResponse(403, { error: "Signature does not match address" });
    }

    // Get relayer key from environment
    const relayerKey = context.env.FAUCET_RELAYER_KEY;
    if (!relayerKey) {
      return jsonResponse(500, { error: "Relayer not configured" });
    }

    // Get faucet address from environment
    const faucetAddress = context.env.FAUCET_ADDRESS;
    if (!faucetAddress) {
      return jsonResponse(500, { error: "Faucet address not configured" });
    }

    // Setup provider and relayer wallet
    const provider = new ethers.JsonRpcProvider(RPC);
    const relayer = new ethers.Wallet(relayerKey, provider);
    const faucet = new ethers.Contract(faucetAddress, FAUCET_ABI, relayer);

    // Call dripTo on behalf of the user
    const tx = await faucet.dripTo(address);
    const receipt = await tx.wait();

    return jsonResponse(200, {
      success: true,
      txHash: receipt.hash,
      recipient: address,
    });

  } catch (e) {
    console.error("Faucet relay error:", e);

    // Parse contract errors
    let errorMsg = "Transaction failed";
    const msg = e.message || "";
    if (msg.includes("CooldownActive")) {
      errorMsg = "Cooldown active. Try again in 24 hours.";
    } else if (msg.includes("InsufficientBalance")) {
      errorMsg = "Faucet is empty. Please try again later.";
    } else if (msg.includes("NotRelayer")) {
      errorMsg = "Relayer not authorized.";
    }

    return jsonResponse(500, { error: errorMsg });
  }
}

function jsonResponse(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}
