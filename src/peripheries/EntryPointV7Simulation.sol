// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {EntryPointSimulation} from "./EntryPointSimulation.sol";
import {SenderCreator} from "account-abstraction-v0.7/core/SenderCreator.sol";

address constant SENDER_CREATOR = 0xEFC2c1444eBCC4Db75e7613d20C6a62fF67A167C;

contract EntryPointV7Simulation is EntryPointSimulation {
    function senderCreator() internal view virtual override returns (SenderCreator) {
        return SenderCreator(SENDER_CREATOR);
    }
}
