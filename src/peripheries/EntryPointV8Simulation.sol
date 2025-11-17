// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {PackedUserOperation} from "account-abstraction-v0.8/interfaces/PackedUserOperation.sol";
import {EntryPoint} from "account-abstraction-v0.8/core/EntryPoint.sol";
import {ISenderCreator} from "account-abstraction-v0.8/core/SenderCreator.sol";

address constant SENDER_CREATOR = 0x449ED7C3e6Fee6a97311d4b55475DF59C44AdD33;

contract EntryPointV8Simulation is EntryPoint {
    function senderCreator() public view virtual override returns (ISenderCreator) {
        return ISenderCreator(SENDER_CREATOR);
    }

    function simulateHandleOps(
        PackedUserOperation[] calldata userOps,
        address payable beneficiary
    ) external {
        uint256 opslen = userOps.length;
        UserOpInfo[] memory opInfos = new UserOpInfo[](opslen);

        unchecked {
            for (uint256 i = 0; i < opslen; i++) {
                UserOpInfo memory opInfo = opInfos[i];
                _validatePrepayment(i, userOps[i], opInfo);
            }

            uint256 collected = 0;
            emit BeforeExecution();

            for (uint256 i = 0; i < opslen; i++) {
                collected += _executeUserOp(i, userOps[i], opInfos[i]);
            }

            _compensate(beneficiary, collected);
        }
    }

    function validateAccountPrepayment(PackedUserOperation calldata userOp)
        public
        returns (UserOpInfo memory outOpInfo)
    {
        uint256 preGas = gasleft();
        MemoryUserOp memory mUserOp = outOpInfo.mUserOp;
        _copyUserOpToMemory(userOp, mUserOp);

        // getUserOpHash uses temporary allocations, no required after it returns
        uint256 freePtr = _getFreePtr();
        outOpInfo.userOpHash = getUserOpHash(userOp);
        _restoreFreePtr(freePtr);

        // Validate all numeric values in userOp are well below 128 bit, so they can safely be added
        // and multiplied without causing overflow.
        uint256 verificationGasLimit = mUserOp.verificationGasLimit;
        uint256 maxGasValues = mUserOp.preVerificationGas | verificationGasLimit
            | mUserOp.callGasLimit | mUserOp.paymasterVerificationGasLimit
            | mUserOp.paymasterPostOpGasLimit | mUserOp.maxFeePerGas | mUserOp.maxPriorityFeePerGas;
        require(maxGasValues <= type(uint120).max, FailedOp(0, "AA94 gas values overflow"));

        uint256 requiredPreFund = _getRequiredPrefund(mUserOp);
        outOpInfo.prefund = requiredPreFund;
        _validateAccountPrepayment(0, userOp, outOpInfo, requiredPreFund);

        require(
            _validateAndUpdateNonce(mUserOp.sender, mUserOp.nonce),
            FailedOp(0, "AA25 invalid account nonce")
        );

        unchecked {
            if (preGas - gasleft() > verificationGasLimit) {
                revert FailedOp(0, "AA26 over verificationGasLimit");
            }
        }
    }

    function validatePaymasterPrepayment(PackedUserOperation calldata userOp) external {
        (UserOpInfo memory outOpInfo) = validateAccountPrepayment(userOp);

        _validatePaymasterPrepayment(0, userOp, outOpInfo);
    }

    function executeUserOp(PackedUserOperation calldata userOp) external {
        (UserOpInfo memory outOpInfo) = validateAccountPrepayment(userOp);

        if (userOp.paymasterAndData.length > 0) {
            _validatePaymasterPrepayment(0, userOp, outOpInfo);
        }

        if (userOp.callData.length > 0) {
            (bool success, bytes memory data) = userOp.sender.call(userOp.callData);
            if (!success) {
                assembly {
                    revert(add(data, 32), mload(data))
                }
            }
        }
    }
}
