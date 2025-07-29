// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC20} from "../interfaces/IERC20.sol";
import {NATIVE_TOKEN} from "../types/Constants.sol";

contract TransactionSimulation {
    receive() external payable {}

    function simulateTransaction(
        address target,
        bytes calldata data,
        address paymentToken,
        address feeCollector,
        bool revertOnFailure
    ) external payable returns (bool success, bytes memory returnData) {
        (success, returnData) = target.call{value: msg.value}(data);
        if (!success && revertOnFailure) {
            assembly {
                revert(add(returnData, 32), mload(returnData))
            }
        }

        if (paymentToken != address(0) && paymentToken != NATIVE_TOKEN) {
            IERC20(paymentToken).transfer(feeCollector, 0);
        }
    }
}
