import { keccak256, toHex } from "viem";
import { CONTRACTS, SALT } from "./constants.js";
import { deploy } from "./deploy.js";

const main = async () => {
  const SPONSOR_API_KEY = process.env["SPONSOR_API_KEY"];
  if (!SPONSOR_API_KEY) throw new Error("Missing 'SPONSOR_API_KEY' in env");

  const TARGET_ENV = process.env["TARGET_ENV"];
  if (!TARGET_ENV || (TARGET_ENV !== "testnet" && TARGET_ENV !== "mainnet"))
    throw new Error("'TARGET_ENV' in env must be either 'testnet' or 'mainnet'");

  // mute warning to avoid having it in output
  process.env["FOUNDRY_DISABLE_NIGHTLY_WARNING"] = "true";

  const salt = keccak256(toHex(SALT));

  for (const contract of CONTRACTS) {
    await deploy(contract, SPONSOR_API_KEY, TARGET_ENV, salt);
  }
};

main();
