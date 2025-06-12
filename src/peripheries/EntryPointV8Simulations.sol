// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {PackedUserOperation} from "account-abstraction-v0.8/interfaces/PackedUserOperation.sol";
import {EntryPoint} from "account-abstraction-v0.8/core/EntryPoint.sol";

contract EntryPointV8Simulations is EntryPoint {
    function simulateHandleOps(PackedUserOperation[] calldata ops, address payable beneficiary)
        public
    {
        uint256 opslen = ops.length;
        UserOpInfo[] memory opInfos = new UserOpInfo[](opslen);

        unchecked {
            for (uint256 i = 0; i < opslen; i++) {
                _validatePrepayment(0, ops[i], opInfos[i]);
            }

            uint256 collected = 0;
            emit BeforeExecution();

            for (uint256 i = 0; i < opslen; i++) {
                collected += _executeUserOp(0, ops[i], opInfos[i]);
            }

            _compensate(beneficiary, collected);
        }
    }
}
