// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {EntryPoint} from "account-abstraction-v0.8/core/EntryPoint.sol";
import {ISenderCreator} from "account-abstraction-v0.8/interfaces/ISenderCreator.sol";
import {PackedUserOperation} from "account-abstraction-v0.8/interfaces/PackedUserOperation.sol";

address constant SENDER_CREATOR = 0x449ED7C3e6Fee6a97311d4b55475DF59C44AdD33;

contract EntryPointV8Simulation is EntryPoint {
    function senderCreator() public view virtual override returns (ISenderCreator) {
        return ISenderCreator(SENDER_CREATOR);
    }

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

    function createSenderAndCall(address to, bytes calldata data, bytes calldata initCode)
        external
    {
        senderCreator().createSender(initCode);

        if (to != address(0)) {
            (bool success, bytes memory result) = to.call(data);

            if (!success) {
                assembly {
                    revert(add(result, 32), mload(result))
                }
            }
        }
    }
}
