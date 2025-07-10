// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Delegation} from "../Delegation.sol";

contract Simulation is Delegation {
    function simulateExecute(bytes32 mode, bytes calldata executionData) external payable {
        _execute(mode, executionData, true);
    }
}
