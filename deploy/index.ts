import { GelatoRelay, TaskState } from "@gelatonetwork/relay-sdk-viem";
import { execSync } from "child_process";
import { setTimeout } from "timers";
import {
  Address,
  concatHex,
  createPublicClient,
  getCreate2Address,
  Hex,
  http,
  keccak256,
  toHex,
} from "viem";
import { mainnets, testnets } from "./chains.js";

const SALT: string = "gelato.deployer";
const CONTRACT: string = "Delegation";
const DETERMINISTIC_DEPLOYER: Address =
  "0x4e59b44847b379578588920cA78FbF26c0B4956C";
const TASK_POLL_INTERVAL = 2_000;

const SPONSOR_API_KEY = process.env["SPONSOR_API_KEY"];
if (!SPONSOR_API_KEY) throw new Error("Missing 'SPONSOR_API_KEY' in env");

const TARGET_ENV = process.env["TARGET_ENV"];
if (!TARGET_ENV || (TARGET_ENV !== "testnet" && TARGET_ENV !== "mainnet"))
  throw new Error("'TARGET_ENV' in env must be either 'testnet' or 'mainnet'");

const main = async () => {
  // mute warning to avoid having it in output
  process.env["FOUNDRY_DISABLE_NIGHTLY_WARNING"] = "true";

  const salt = keccak256(toHex(SALT));

  const bytecode = execSync(`forge inspect ${CONTRACT} bytecode`)
    .toString()
    .trim() as Hex;

  const address = getCreate2Address({
    bytecode,
    from: DETERMINISTIC_DEPLOYER,
    salt,
  });

  const relay = new GelatoRelay();

  const chains = TARGET_ENV === "testnet" ? testnets : mainnets;

  console.log(
    `Deploying '${CONTRACT}' to ${chains.length} chain/s, address: ${address}`,
  );

  for (const chain of chains) {
    const client = createPublicClient({
      chain,
      transport: http(),
    });

    const code = await client.getCode({
      address,
    });

    if (code) {
      console.log(`[skipping] already deployed on ${chain.name}`);
      continue;
    }

    const response = await relay
      .sponsoredCall(
        {
          chainId: BigInt(chain.id),
          target: DETERMINISTIC_DEPLOYER,
          data: concatHex([salt, bytecode]),
        },
        SPONSOR_API_KEY,
      )
      .catch((e) => {
        console.log(`[failure] chain: ${chain.name}, error: ${e.toString()}`);
        return undefined;
      });

    if (!response) continue;

    while (true) {
      await new Promise((r) => setTimeout(r, TASK_POLL_INTERVAL));

      const status = await relay.getTaskStatus(response.taskId);
      if (!status) continue;

      if (status.taskState === TaskState.ExecSuccess) {
        console.log(
          `[success] deployed to ${chain.name}, hash: ${status.transactionHash}`,
        );
        break;
      }

      if (
        status.taskState === TaskState.Cancelled ||
        status.taskState === TaskState.ExecReverted
      ) {
        console.log(
          `[failure] chain: ${chain.name}, taskId: ${response.taskId}`,
        );
        break;
      }
    }
  }
};

main();
