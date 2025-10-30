// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC20} from "../interfaces/IERC20.sol";
import {ZERO_ADDRESS} from "../types/Constants.sol";

contract PaymentSimulation {
    receive() external payable {}

    function simulateWithPayment(
        address to,
        bytes calldata data,
        address beneficiary,
        address token
    ) external returns (uint256) {
        uint256 balanceBefore = _getBalance(beneficiary, token);

        (bool success, bytes memory result) = to.call(data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }

        uint256 balanceAfter = _getBalance(beneficiary, token);
        return balanceAfter - balanceBefore;
    }

    function _getBalance(address beneficiary, address token) internal view returns (uint256) {
        if (token == ZERO_ADDRESS) {
            return beneficiary.balance;
        }
        return IERC20(token).balanceOf(beneficiary);
    }
}
