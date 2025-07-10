import { concatHex, createPublicClient, getCreate2Address, Hex, http } from "viem";
import { DETERMINISTIC_DEPLOYER, TASK_POLL_INTERVAL } from "./constants.js";
import { execSync } from "child_process";
import { GelatoRelay, TaskState } from "@gelatonetwork/relay-sdk-viem";
import { MAINNETS, TESTNETS } from "./chains.js";

export const deploy = async (
  contract: string,
  sponsorApiKey: string,
  env: "testnet" | "mainnet",
  salt: Hex,
) => {
  const bytecode = execSync(`forge inspect ${contract} bytecode`)
    .toString()
    .trim() as Hex;

  const address = getCreate2Address({
    bytecode,
    from: DETERMINISTIC_DEPLOYER,
    salt,
  });

  const relay = new GelatoRelay();

  const chains = env === "testnet" ? TESTNETS : MAINNETS;

  console.log(
    `Deploying '${contract}' to ${chains.length} chain/s, address: ${address}`,
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
      console.log(`\t[skipping] already deployed on ${chain.name}`);
      continue;
    }

    const response = await relay
      .sponsoredCall(
        {
          chainId: BigInt(chain.id),
          target: DETERMINISTIC_DEPLOYER,
          data: concatHex([salt, bytecode]),
        },
        sponsorApiKey,
      )
      .catch((e) => {
        console.log(`\t[failure] chain: ${chain.name}, error: ${e.toString()}`);
        return undefined;
      });

    if (!response) continue;

    while (true) {
      await new Promise((r) => setTimeout(r, TASK_POLL_INTERVAL));

      const status = await relay.getTaskStatus(response.taskId);
      if (!status) continue;

      if (status.taskState === TaskState.ExecSuccess) {
        console.log(
          `\t[success] deployed to ${chain.name}, hash: ${status.transactionHash}`,
        );
        break;
      }

      if (
        status.taskState === TaskState.Cancelled ||
        status.taskState === TaskState.ExecReverted
      ) {
        console.log(
          `\t[failure] chain: ${chain.name}, taskId: ${response.taskId}`,
        );
        break;
      }
    }
  }
};
