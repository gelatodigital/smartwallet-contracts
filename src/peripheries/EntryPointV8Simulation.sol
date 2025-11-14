// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {EntryPointSimulation} from "./EntryPointSimulation.sol";
import {SenderCreator} from "account-abstraction-v0.7/core/SenderCreator.sol";

address constant SENDER_CREATOR = 0x449ED7C3e6Fee6a97311d4b55475DF59C44AdD33;

contract EntryPointV8Simulation is EntryPointSimulation {
    function senderCreator() internal view virtual override returns (SenderCreator) {
        return SenderCreator(SENDER_CREATOR);
    }
}
