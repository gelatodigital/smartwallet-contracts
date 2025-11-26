// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {PackedUserOperation} from "account-abstraction-v0.7/interfaces/PackedUserOperation.sol";
import {EntryPoint} from "account-abstraction-v0.7/core/EntryPoint.sol";
import {SenderCreator} from "account-abstraction-v0.7/core/SenderCreator.sol";
import {IAccountExecute} from "account-abstraction-v0.7/interfaces/IAccountExecute.sol";
import {IPaymaster} from "account-abstraction-v0.7/interfaces/IPaymaster.sol";
import {Exec} from "account-abstraction-v0.7/utils/Exec.sol";

/* solhint-disable avoid-low-level-calls */
/* solhint-disable no-inline-assembly */
/* solhint-disable use-natspec */
/* solhint-disable gas-increment-by-one */
/* solhint-disable gas-strict-inequalities */

address constant SENDER_CREATOR = 0xEFC2c1444eBCC4Db75e7613d20C6a62fF67A167C;

contract EntryPointV7Simulation is EntryPoint {
    bytes32 private constant INNER_OUT_OF_GAS = hex"deaddead";
    bytes32 private constant INNER_REVERT_LOW_PREFUND = hex"deadaa51";

    uint256 private constant REVERT_REASON_MAX_LEN = 2048;
    uint256 private constant PENALTY_PERCENT = 10;

    function senderCreator() internal view virtual override returns (SenderCreator) {
        return SenderCreator(SENDER_CREATOR);
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
        returns (uint256 requiredPreFund, UserOpInfo memory outOpInfo)
    {
        uint256 preGas = gasleft();
        MemoryUserOp memory mUserOp = outOpInfo.mUserOp;
        _copyUserOpToMemory(userOp, mUserOp);
        outOpInfo.userOpHash = getUserOpHash(userOp);

        // Validate all numeric values in userOp are well below 128 bit, so they can safely be added
        // and multiplied without causing overflow.
        uint256 verificationGasLimit = mUserOp.verificationGasLimit;
        uint256 maxGasValues = mUserOp.preVerificationGas | verificationGasLimit
            | mUserOp.callGasLimit | mUserOp.paymasterVerificationGasLimit
            | mUserOp.paymasterPostOpGasLimit | mUserOp.maxFeePerGas | mUserOp.maxPriorityFeePerGas;
        require(maxGasValues <= type(uint120).max, "AA94 gas values overflow");

        requiredPreFund = _getRequiredPrefund(mUserOp);
        _validateAccountPrepayment(0, userOp, outOpInfo, requiredPreFund, verificationGasLimit);

        if (!_validateAndUpdateNonce(mUserOp.sender, mUserOp.nonce)) {
            revert FailedOp(0, "AA25 invalid account nonce");
        }

        unchecked {
            if (preGas - gasleft() > verificationGasLimit) {
                revert FailedOp(0, "AA26 over verificationGasLimit");
            }
        }
    }

    function validatePaymasterPrepayment(PackedUserOperation calldata userOp) external {
        (uint256 requiredPreFund, UserOpInfo memory outOpInfo) = validateAccountPrepayment(userOp);

        _validatePaymasterPrepayment(0, userOp, outOpInfo, requiredPreFund);
    }

    function validateAndExecuteUserOp(PackedUserOperation calldata userOp) external {
        (uint256 requiredPreFund, UserOpInfo memory outOpInfo) = validateAccountPrepayment(userOp);

        if (userOp.paymasterAndData.length > 0) {
            _validatePaymasterPrepayment(0, userOp, outOpInfo, requiredPreFund);
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
        require(msg.sender == address(this), "AA92 internal call only");
        MemoryUserOp memory mUserOp = opInfo.mUserOp;

        IPaymaster.PostOpMode mode = IPaymaster.PostOpMode.opSucceeded;
        if (callData.length > 0) {
            bool success = Exec.call(mUserOp.sender, 0, callData, mUserOp.callGasLimit);
            if (!success) {
                bytes memory result = Exec.getReturnData(REVERT_REASON_MAX_LEN);
                if (result.length > 0) {
                    emit UserOperationRevertReason(
                        opInfo.userOpHash, mUserOp.sender, mUserOp.nonce, result
                    );
                }
                mode = IPaymaster.PostOpMode.opReverted;
            }
        }

        unchecked {
            uint256 actualGas = preGas - gasleft() + opInfo.preOpGas;
            return _simulatePostExecution(mode, opInfo, context, actualGas); // TODO?
        }
    }

    function _simulateExecuteUserOp(
        uint256 opIndex,
        PackedUserOperation calldata userOp,
        UserOpInfo memory opInfo
    ) internal returns (uint256 collected) {
        uint256 preGas = gasleft();
        bytes memory context = getMemoryBytesFromOffset(opInfo.contextOffset);
        bool success;
        {
            uint256 saveFreePtr;
            assembly ("memory-safe") {
                saveFreePtr := mload(0x40)
            }
            bytes calldata callData = userOp.callData;
            bytes memory innerCall;
            bytes4 methodSig;
            assembly {
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
                mstore(0x40, saveFreePtr)
            }
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
                //can only be caused by bundler (leaving not enough gas for inner call)
                revert FailedOp(opIndex, "AA95 out of gas");
            } else if (innerRevertCode == INNER_REVERT_LOW_PREFUND) {
                // innerCall reverted on prefund too low. treat entire prefund as "gas cost"
                uint256 actualGas = preGas - gasleft() + opInfo.preOpGas;
                uint256 actualGasCost = opInfo.prefund;
                emitPrefundTooLow(opInfo);
                emitUserOperationEvent(opInfo, false, actualGasCost, actualGas);
                collected = actualGasCost;
            } else {
                emit PostOpRevertReason(
                    opInfo.userOpHash,
                    opInfo.mUserOp.sender,
                    opInfo.mUserOp.nonce,
                    Exec.getReturnData(REVERT_REASON_MAX_LEN)
                );

                uint256 actualGas = preGas - gasleft() + opInfo.preOpGas;
                collected = _simulatePostExecution(
                    IPaymaster.PostOpMode.postOpReverted, opInfo, context, actualGas
                );
            }
        }
    }

    function _simulatePostExecution(
        IPaymaster.PostOpMode mode,
        UserOpInfo memory opInfo,
        bytes memory context,
        uint256 actualGas
    ) internal returns (uint256 actualGasCost) {
        uint256 preGas = gasleft();
        unchecked {
            address refundAddress;
            MemoryUserOp memory mUserOp = opInfo.mUserOp;
            uint256 gasPrice = getUserOpGasPrice(mUserOp);

            address paymaster = mUserOp.paymaster;
            if (paymaster == address(0)) {
                refundAddress = mUserOp.sender;
            } else {
                refundAddress = paymaster;
                if (context.length > 0) {
                    actualGasCost = actualGas * gasPrice;
                    if (mode != IPaymaster.PostOpMode.postOpReverted) {
                        try IPaymaster(paymaster).postOp{gas: mUserOp.paymasterPostOpGasLimit}(
                            mode, context, actualGasCost, gasPrice
                        ) {
                            // solhint-disable-next-line no-empty-blocks
                        } catch {
                            bytes memory reason = Exec.getReturnData(REVERT_REASON_MAX_LEN);
                            revert PostOpReverted(reason);
                        }
                    }
                }
            }
            actualGas += preGas - gasleft();

            // Calculating a penalty for unused execution gas
            {
                uint256 executionGasLimit = mUserOp.callGasLimit + mUserOp.paymasterPostOpGasLimit;
                uint256 executionGasUsed = actualGas - opInfo.preOpGas;
                // this check is required for the gas used within EntryPoint and not covered by
                // explicit gas limits
                if (executionGasLimit > executionGasUsed) {
                    uint256 unusedGas = executionGasLimit - executionGasUsed;
                    uint256 unusedGasPenalty = (unusedGas * PENALTY_PERCENT) / 100;
                    actualGas += unusedGasPenalty;
                }
            }

            actualGasCost = actualGas * gasPrice;
            uint256 prefund = opInfo.prefund;
            if (prefund < actualGasCost) {
                if (mode == IPaymaster.PostOpMode.postOpReverted) {
                    actualGasCost = prefund;
                    emitPrefundTooLow(opInfo);
                    emitUserOperationEvent(opInfo, false, actualGasCost, actualGas);
                } else {
                    assembly ("memory-safe") {
                        mstore(0, INNER_REVERT_LOW_PREFUND)
                        revert(0, 32)
                    }
                }
            } else {
                uint256 refund = prefund - actualGasCost;
                _incrementDeposit(refundAddress, refund);
                bool success = mode == IPaymaster.PostOpMode.opSucceeded;
                emitUserOperationEvent(opInfo, success, actualGasCost, actualGas);
            }
        } // unchecked
    }
}
