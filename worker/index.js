/**
 * Puffles Faucet Relay Worker
 * 
 * Gasless faucet relay for Push Chain testnet.
 * User signs a free message → Worker verifies → calls dripTo() on contract.
 * 
 * Secrets (set via `wrangler secret put`):
 *   FAUCET_RELAYER_KEY - Private key of the relayer wallet
 * 
 * Vars (set in wrangler.toml):
 *   FAUCET_ADDRESS  - PufflesFaucetV2 contract address
 *   RPC_URL         - Push Chain testnet RPC
 *   ALLOWED_ORIGIN  - CORS origin (https://puffles.io)
 */

import { ethers } from "ethers";

const FAUCET_ABI = [
  "function dripTo(address recipient) external",
  "function timeUntilNextRequest(address wallet) external view returns (uint256)",
  "function dripAmount() external view returns (uint256)",
  "function totalDrips() external view returns (uint256)",
  "function totalDistributed() external view returns (uint256)"
];

// CORS headers helper
function corsHeaders(origin, allowedOrigin) {
  // Allow both production and local dev
  const allowed = origin === allowedOrigin || origin === "http://localhost:8080" || origin === "http://127.0.0.1:8080";
  return {
    "Access-Control-Allow-Origin": allowed ? origin : allowedOrigin,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Max-Age": "86400",
  };
}

function jsonResponse(data, status, origin, allowedOrigin) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...corsHeaders(origin, allowedOrigin),
    },
  });
}

export default {
  async fetch(request, env, ctx) {
    const origin = request.headers.get("Origin") || "";
    const allowed = env.ALLOWED_ORIGIN || "https://puffles.io";

    // Handle CORS preflight
    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: corsHeaders(origin, allowed),
      });
    }

    // Only POST
    if (request.method !== "POST") {
      return jsonResponse({ error: "Method not allowed" }, 405, origin, allowed);
    }

    try {
      const body = await request.json();
      const { address, signature, message } = body;

      // ── Validate input ──────────────────────────────────────
      if (!address || !signature || !message) {
        return jsonResponse(
          { error: "Missing required fields: address, signature, message" },
          400, origin, allowed
        );
      }

      // Validate address format
      if (!ethers.isAddress(address)) {
        return jsonResponse({ error: "Invalid address" }, 400, origin, allowed);
      }

      // ── Verify signature ────────────────────────────────────
      // Message must match expected format
      const expectedMessage = `Puffles Faucet: Request PC for ${address}`;
      if (message !== expectedMessage) {
        return jsonResponse({ error: "Invalid message format" }, 400, origin, allowed);
      }

      // Recover signer from signature
      const recoveredAddress = ethers.verifyMessage(message, signature);
      if (recoveredAddress.toLowerCase() !== address.toLowerCase()) {
        return jsonResponse(
          { error: "Signature does not match address" },
          403, origin, allowed
        );
      }

      // ── Connect to chain ────────────────────────────────────
      const provider = new ethers.JsonRpcProvider(env.RPC_URL);
      const wallet = new ethers.Wallet(env.FAUCET_RELAYER_KEY, provider);
      const faucet = new ethers.Contract(env.FAUCET_ADDRESS, FAUCET_ABI, wallet);

      // ── Check cooldown first (saves gas on revert) ──────────
      const remaining = await faucet.timeUntilNextRequest(address);
      if (remaining > 0n) {
        const hours = Math.floor(Number(remaining) / 3600);
        const mins = Math.floor((Number(remaining) % 3600) / 60);
        return jsonResponse(
          { error: `Cooldown active. Try again in ${hours}h ${mins}m.` },
          429, origin, allowed
        );
      }

      // ── Send dripTo transaction ─────────────────────────────
      const tx = await faucet.dripTo(address);
      const receipt = await tx.wait();

      return jsonResponse(
        {
          success: true,
          txHash: receipt.hash,
          recipient: address,
          message: "0.1 PC sent! Welcome to Push Chain.",
        },
        200, origin, allowed
      );

    } catch (err) {
      console.error("Faucet relay error:", err);

      // Parse contract revert reasons
      const errorMsg = err.message || String(err);
      if (errorMsg.includes("CooldownActive")) {
        return jsonResponse(
          { error: "Cooldown active. Please try again later." },
          429, origin, allowed
        );
      }
      if (errorMsg.includes("InsufficientBalance")) {
        return jsonResponse(
          { error: "Faucet is empty. Please notify the team." },
          503, origin, allowed
        );
      }

      return jsonResponse(
        { error: "Relay failed. Please try again." },
        500, origin, allowed
      );
    }
  },
};
