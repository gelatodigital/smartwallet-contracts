import { Address } from "viem";

export const SALT = "gelato.deployer";

export const DETERMINISTIC_DEPLOYER: Address =
  "0x4e59b44847b379578588920cA78FbF26c0B4956C";

export const TASK_POLL_INTERVAL = 2_000;

export const CONTRACTS = [
	"Delegation",
  "SessionValidator"
];
