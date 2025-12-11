// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {PackedUserOperation} from "account-abstraction-v0.9/interfaces/PackedUserOperation.sol";
import {EntryPoint} from "account-abstraction-v0.9/core/EntryPoint.sol";
import {ISenderCreator} from "account-abstraction-v0.9/core/SenderCreator.sol";
import {IAccountExecute} from "account-abstraction-v0.9/interfaces/IAccountExecute.sol";
import {IPaymaster} from "account-abstraction-v0.9/interfaces/IPaymaster.sol";
import {Exec} from "account-abstraction-v0.9/utils/Exec.sol";

/* solhint-disable avoid-low-level-calls */
/* solhint-disable no-inline-assembly */
/* solhint-disable use-natspec */
/* solhint-disable gas-increment-by-one */
/* solhint-disable gas-strict-inequalities */

address constant SENDER_CREATOR = 0x0A630a99Df908A81115A3022927Be82f9299987e;

contract EntryPointV9Simulation is EntryPoint {
    bytes32 private constant INNER_OUT_OF_GAS = hex"deaddead";
    bytes32 private constant INNER_REVERT_LOW_PREFUND = hex"deadaa51";

    uint256 private constant REVERT_REASON_MAX_LEN = 2048;

    function senderCreator() public view virtual override returns (ISenderCreator) {
        return ISenderCreator(SENDER_CREATOR);
    }

    function simulateHandleOps(PackedUserOperation[] calldata userOps, address payable beneficiary)
        external
    {
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
                collected += _simulateExecuteUserOp(i, userOps[i], opInfos[i]);
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

    function validateAndExecuteUserOp(PackedUserOperation calldata userOp) external {
        (UserOpInfo memory outOpInfo) = validateAccountPrepayment(userOp);

        if (userOp.paymasterAndData.length > 0) {
            _validatePaymasterPrepayment(0, userOp, outOpInfo);
        }

        bytes calldata callData = userOp.callData;
        if (callData.length > 0) {
            bytes4 selector;
            assembly {
                let len := callData.length
                if gt(len, 3) { selector := calldataload(callData.offset) }
            }

            if (selector == IAccountExecute.executeUserOp.selector) {
                bytes memory executeUserOpCallData =
                    abi.encodeCall(IAccountExecute.executeUserOp, (userOp, outOpInfo.userOpHash));

                (bool success, bytes memory data) = userOp.sender.call(executeUserOpCallData);
                if (!success) {
                    assembly {
                        revert(add(data, 32), mload(data))
                    }
                }
            } else {
                (bool success, bytes memory data) = userOp.sender.call(callData);
                if (!success) {
                    assembly {
                        revert(add(data, 32), mload(data))
                    }
                }
            }
        }
    }

    function simulateInnerHandleOp(
        bytes memory callData,
        UserOpInfo memory opInfo,
        bytes calldata context
    ) external returns (uint256 actualGasCost) {
        uint256 preGas = gasleft();
        require(msg.sender == address(this), InternalFunction());
        MemoryUserOp memory mUserOp = opInfo.mUserOp;

        IPaymaster.PostOpMode mode = IPaymaster.PostOpMode.opSucceeded;
        if (callData.length > 0) {
            bool success = Exec.call(mUserOp.sender, 0, callData, mUserOp.callGasLimit);
            if (!success) {
                uint256 freePtr = _getFreePtr();
                bytes memory result = Exec.getReturnData(REVERT_REASON_MAX_LEN);
                if (result.length > 0) {
                    emit UserOperationRevertReason(
                        opInfo.userOpHash, mUserOp.sender, mUserOp.nonce, result
                    );
                }
                _restoreFreePtr(freePtr);
                mode = IPaymaster.PostOpMode.opReverted;
            }
        }

        unchecked {
            uint256 actualGas = preGas - gasleft() + opInfo.preOpGas;
            return _postExecution(mode, opInfo, context, actualGas);
        }
    }

    function _simulateExecuteUserOp(
        uint256 opIndex,
        PackedUserOperation calldata userOp,
        UserOpInfo memory opInfo
    ) internal returns (uint256 collected) {
        uint256 preGas = gasleft();
        bytes memory context = _getMemoryBytesFromOffset(opInfo.contextOffset);
        bool success;
        {
            uint256 saveFreePtr = _getFreePtr();
            bytes calldata callData = userOp.callData;
            bytes memory innerCall;
            bytes4 methodSig;
            assembly ("memory-safe") {
                let len := callData.length
                if gt(len, 3) { methodSig := calldataload(callData.offset) }
            }
            if (methodSig == IAccountExecute.executeUserOp.selector) {
                bytes memory executeUserOp =
                    abi.encodeCall(IAccountExecute.executeUserOp, (userOp, opInfo.userOpHash));
                innerCall =
                    abi.encodeCall(this.simulateInnerHandleOp, (executeUserOp, opInfo, context));
            } else {
                innerCall = abi.encodeCall(this.simulateInnerHandleOp, (callData, opInfo, context));
            }
            assembly ("memory-safe") {
                success := call(gas(), address(), 0, add(innerCall, 0x20), mload(innerCall), 0, 32)
                collected := mload(0)
            }
            _restoreFreePtr(saveFreePtr);
        }
        if (!success) {
            bytes32 innerRevertCode;
            assembly ("memory-safe") {
                let len := returndatasize()
                if eq(32, len) {
                    returndatacopy(0, 0, 32)
                    innerRevertCode := mload(0)
                }
            }
            if (innerRevertCode == INNER_OUT_OF_GAS) {
                // handleOps was called with gas limit too low. abort entire bundle.
                // can only be caused by bundler (leaving not enough gas for inner call)
                revert FailedOp(opIndex, "AA95 out of gas");
            } else if (innerRevertCode == INNER_REVERT_LOW_PREFUND) {
                // innerCall reverted on prefund too low. treat entire prefund as "gas cost"
                uint256 actualGas = preGas - gasleft() + opInfo.preOpGas;
                uint256 actualGasCost = opInfo.prefund;
                _emitPrefundTooLow(opInfo);
                _emitUserOperationEvent(opInfo, false, actualGasCost, actualGas);
                collected = actualGasCost;
            } else {
                uint256 freePtr = _getFreePtr();
                emit PostOpRevertReason(
                    opInfo.userOpHash,
                    opInfo.mUserOp.sender,
                    opInfo.mUserOp.nonce,
                    Exec.getReturnData(REVERT_REASON_MAX_LEN)
                );
                _restoreFreePtr(freePtr);

                uint256 actualGas = preGas - gasleft() + opInfo.preOpGas;
                collected =
                    _postExecution(IPaymaster.PostOpMode.postOpReverted, opInfo, context, actualGas);
            }
        }
    }
}
