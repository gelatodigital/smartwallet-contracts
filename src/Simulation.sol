// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Delegation} from "./Delegation.sol";
import {NATIVE_TOKEN} from "./types/Constants.sol";
import {IERC20} from "./interfaces/IERC20.sol";

contract Simulation is Delegation {
    function simulateExecute(bytes32 mode, bytes calldata executionData) external payable {
        _execute(mode, executionData, true);
    }

    function getBalanceAfterExecute(bytes32 mode, bytes calldata executionData, address token)
        external
        payable
        returns (uint256)
    {
        _execute(mode, executionData, true);

        if (token == NATIVE_TOKEN) {
            return address(this).balance;
        }

        return IERC20(token).balanceOf(address(this));
    }
}
