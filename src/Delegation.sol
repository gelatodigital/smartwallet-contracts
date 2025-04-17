// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC7821} from "./interfaces/IERC7821.sol";
import {IERC1271} from "./interfaces/IERC1271.sol";
import {CALL_TYPE_BATCH, EXEC_TYPE_DEFAULT, EXEC_MODE_DEFAULT, EXEC_MODE_OP_DATA, ENTRY_POINT_V8} from "./types/Constants.sol";

// TODO: also implement IERC4337 for `validateUserOperation`.
contract Delegation is IERC7821, IERC1271 {
    // TODO: use namespaced storage layout.
    // https://eips.ethereum.org/EIPS/eip-7201

    error UnsupportedExecutionMode();
    error Unauthorized();

    function execute(
        bytes32 mode,
        bytes calldata executionData
    ) external payable {
        (
            bytes1 callType,
            bytes1 execType,
            bytes4 modeSelector,

        ) = _decodeExecutionMode(mode);

        if (callType != CALL_TYPE_BATCH || execType != EXEC_TYPE_DEFAULT) {
            revert UnsupportedExecutionMode();
        }

        if (modeSelector == EXEC_MODE_DEFAULT) {
            // https://eips.ethereum.org/EIPS/eip-7821
            // If `opData` is empty, the implementation SHOULD require that `msg.sender ==
            // address(this)`.
            // If `msg.sender` is an authorized entry point, then `execute` MAY accept calls from
            // the entry point.
            if (msg.sender != address(this) && msg.sender != ENTRY_POINT_V8) {
                revert Unauthorized();
            }

            // If `opData` is empty, `executionData` is simply `abi.encode(calls)`.
            Call[] memory calls = abi.decode(executionData, (Call[]));
            _execute(calls);
        } else {
            // If `opData` is not empty, the implementation SHOULD use the signature encoded in
            // `opData` to determine if the caller can perform the execution.
            // If `opData` is not empty, `executionData` is `abi.encode(calls, opData)`.

            /*(Call[] memory calls, bytes memory opData) = abi.decode(
                executionData,
                (Call[], bytes)
            );*/

            // TODO: Check passkey, for now we just revert.
            revert Unauthorized();
        }
    }

    // TODO: add methods for adding/removing authorized passkeys.
    // These methods should be gated by `onlyThis` but can be invoked through `execute` calling back into this.

    // TODO: add test for this method.
    function supportsExecutionMode(bytes32 mode) external pure returns (bool) {
        (
            bytes1 callType,
            bytes1 execType,
            bytes4 modeSelector,

        ) = _decodeExecutionMode(mode);

        if (callType != CALL_TYPE_BATCH || execType != EXEC_TYPE_DEFAULT) {
            return false;
        }

        if (
            modeSelector != EXEC_MODE_DEFAULT &&
            modeSelector != EXEC_MODE_OP_DATA
        ) {
            return false;
        }

        return true;
    }

    function isValidSignature(
        bytes32 hash,
        bytes memory signature
    ) external view returns (bytes4) {
        // TODO
    }

    function _execute(Call[] memory calls) private {
        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory data) = calls[i].to.call{
                value: calls[i].value
            }(calls[i].data);

            if (!success) {
                assembly {
                    revert(add(data, 0x20), mload(data))
                }
            }
        }
    }

    function _decodeExecutionMode(
        bytes32 mode
    )
        private
        pure
        returns (
            bytes1 calltype,
            bytes1 execType,
            bytes4 modeSelector,
            bytes22 modePayload
        )
    {
        // https://eips.ethereum.org/EIPS/eip-7579
        // https://eips.ethereum.org/EIPS/eip-7821
        assembly {
            calltype := mode
            execType := shl(8, mode)
            modeSelector := shl(48, mode)
            modePayload := shl(80, mode)
        }
    }
}
