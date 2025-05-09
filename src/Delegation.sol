// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC7821} from "./interfaces/IERC7821.sol";
import {IERC1271} from "./interfaces/IERC1271.sol";
import {IERC4337} from "./interfaces/IERC4337.sol";
import {
    CALL_TYPE_BATCH,
    EXEC_TYPE_DEFAULT,
    EXEC_MODE_DEFAULT,
    EXEC_MODE_OP_DATA,
    ENTRY_POINT_V8
} from "./types/Constants.sol";
import {EIP712} from "solady/utils/EIP712.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";

contract Delegation is IERC7821, IERC1271, IERC4337, EIP712 {
    error UnsupportedExecutionMode();
    error InvalidCaller();
    error Unauthorized();
    error InvalidNonce();
    error ExcessiveInvalidation();

    // https://eips.ethereum.org/EIPS/eip-7201
    /// @custom:storage-location erc7201:gelato.delegation.storage
    struct Storage {
        mapping(uint192 => uint64) nonceSequenceNumber;
    }

    // keccak256(abi.encode(uint256(keccak256("gelato.delegation.storage")) - 1)) &
    // ~bytes32(uint256(0xff));
    bytes32 private constant STORAGE_LOCATION =
        0x1581abf533ae210f1ff5d25f322511179a9a65d8d8e43c998eab264f924af900;

    // keccak256("Execute(bytes32 mode,Call[] calls,uint256 nonce)Call(address to,uint256
    // value,bytes data)")
    bytes32 private constant EXECUTE_TYPEHASH =
        0xdf21343e200fb58137ad2784f9ea58605ec77f388015dc495486275b8eec47da;

    // keccak256("Call(address to,uint256 value,bytes data)")
    bytes32 private constant CALL_TYPEHASH =
        0x9085b19ea56248c94d86174b3784cfaaa8673d1041d6441f61ff52752dac8483;

    modifier onlyThis() {
        if (msg.sender != address(this)) {
            revert InvalidCaller();
        }
        _;
    }

    receive() external payable {}

    function execute(bytes32 mode, bytes calldata executionData) external payable {
        _execute(mode, executionData, false);
    }

    function supportsExecutionMode(bytes32 mode) external pure returns (bool) {
        (bytes1 callType, bytes1 execType, bytes4 modeSelector,) = _decodeExecutionMode(mode);

        if (callType != CALL_TYPE_BATCH || execType != EXEC_TYPE_DEFAULT) {
            return false;
        }

        if (modeSelector != EXEC_MODE_DEFAULT && modeSelector != EXEC_MODE_OP_DATA) {
            return false;
        }

        return true;
    }

    function isValidSignature(bytes32 digest, bytes calldata signature)
        external
        view
        returns (bytes4)
    {
        // https://eips.ethereum.org/EIPS/eip-1271
        return _verifySignature(digest, signature) ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
    }

    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256)
        external
        view
        returns (uint256)
    {
        // https://eips.ethereum.org/EIPS/eip-4337
        return _verifySignature(userOpHash, userOp.signature) ? 0 : 1;
    }

    function getNonce(uint192 key) external view returns (uint256) {
        Storage storage s = _getStorage();
        return _encodeNonce(key, s.nonceSequenceNumber[key]);
    }

    function invalidateNonce(uint256 newNonce) external onlyThis {
        (uint192 key, uint64 targetSeq) = _decodeNonce(newNonce);
        uint64 currentSeq = _getStorage().nonceSequenceNumber[key];

        if (targetSeq <= currentSeq) {
            revert InvalidNonce();
        }

        // Limit how many nonces can be invalidated at once
        unchecked {
            uint64 delta = targetSeq - currentSeq;
            if (delta > type(uint16).max) revert ExcessiveInvalidation();
        }

        _getStorage().nonceSequenceNumber[key] = targetSeq;
    }

    function _execute(bytes32 mode, bytes calldata executionData, bool allowUnauthorized)
        internal
    {
        (bytes1 callType, bytes1 execType, bytes4 modeSelector,) = _decodeExecutionMode(mode);

        if (callType != CALL_TYPE_BATCH || execType != EXEC_TYPE_DEFAULT) {
            revert UnsupportedExecutionMode();
        }

        Call[] calldata calls = _decodeCalls(executionData);

        if (modeSelector == EXEC_MODE_DEFAULT) {
            // https://eips.ethereum.org/EIPS/eip-7821
            // If `opData` is empty, the implementation SHOULD require that `msg.sender ==
            // address(this)`.
            // If `msg.sender` is an authorized entry point, then `execute` MAY accept calls from
            // the entry point.
            if (msg.sender != address(this) && msg.sender != ENTRY_POINT_V8 && !allowUnauthorized) {
                revert Unauthorized();
            }

            _executeCalls(calls);
        } else {
            bytes calldata opData = _decodeOpData(executionData);
            bytes calldata signature = _decodeSignature(opData);

            uint256 nonce = _getAndUseNonce(_decodeNonceKey(opData));
            bytes32 digest = _computeDigest(mode, calls, nonce);

            // If `opData` is not empty, the implementation SHOULD use the signature encoded in
            // `opData` to determine if the caller can perform the execution.
            if (!_verifySignature(digest, signature) && !allowUnauthorized) {
                revert Unauthorized();
            }

            _executeCalls(calls);
        }
    }

    function _executeCalls(Call[] calldata calls) internal {
        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory data) =
                calls[i].to.call{value: calls[i].value}(calls[i].data);

            if (!success) {
                assembly {
                    revert(add(data, 0x20), mload(data))
                }
            }
        }
    }

    function _decodeCalls(bytes calldata executionData)
        internal
        pure
        returns (Call[] calldata calls)
    {
        // If `opData` is empty, `executionData` is simply `abi.encode(calls)`.
        // We decode this from calldata rather than abi.decode which avoids a memory copy
        assembly {
            let offset := add(executionData.offset, calldataload(executionData.offset))
            calls.offset := add(offset, 0x20)
            calls.length := calldataload(offset)
        }
    }

    function _decodeOpData(bytes calldata executionData)
        internal
        pure
        returns (bytes calldata opData)
    {
        // If `opData` is not empty, `executionData` is `abi.encode(calls, opData)`.
        // We decode this from calldata rather than abi.decode which avoids a memory copy
        assembly {
            let offset := add(executionData.offset, calldataload(add(executionData.offset, 0x20)))
            opData.offset := add(offset, 0x20)
            opData.length := calldataload(offset)
        }
    }

    function _decodeNonceKey(bytes calldata opData) internal pure returns (uint192 nonceKey) {
        assembly {
            nonceKey := shr(64, calldataload(opData.offset))
        }
    }

    function _decodeSignature(bytes calldata opData)
        internal
        pure
        returns (bytes calldata signature)
    {
        assembly {
            signature.offset := add(opData.offset, 24)
            signature.length := sub(opData.length, 24)
        }
    }

    function _verifySignature(bytes32 digest, bytes calldata signature)
        internal
        view
        returns (bool)
    {
        return ECDSA.recoverCalldata(digest, signature) == address(this);
    }

    function _computeDigest(bytes32 mode, Call[] calldata calls, uint256 nonce)
        internal
        view
        returns (bytes32)
    {
        bytes32[] memory callsHashes = new bytes32[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            callsHashes[i] = keccak256(
                abi.encode(CALL_TYPEHASH, calls[i].to, calls[i].value, keccak256(calls[i].data))
            );
        }

        bytes32 executeHash = keccak256(
            abi.encode(EXECUTE_TYPEHASH, mode, keccak256(abi.encodePacked(callsHashes)), nonce)
        );

        return _hashTypedData(executeHash);
    }

    function _getAndUseNonce(uint192 key) internal returns (uint256) {
        uint64 seq = _getStorage().nonceSequenceNumber[key];
        _getStorage().nonceSequenceNumber[key]++;
        return _encodeNonce(key, seq);
    }

    function _encodeNonce(uint192 key, uint64 seq) internal pure returns (uint256) {
        return (uint256(key) << 64) | seq;
    }

    function _decodeNonce(uint256 nonce) internal pure returns (uint192 key, uint64 seq) {
        key = uint192(nonce >> 64);
        seq = uint64(nonce);
    }

    function _getStorage() internal pure returns (Storage storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }

    function _decodeExecutionMode(bytes32 mode)
        internal
        pure
        returns (bytes1 calltype, bytes1 execType, bytes4 modeSelector, bytes22 modePayload)
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

    function _domainNameAndVersion()
        internal
        pure
        override
        returns (string memory name, string memory version)
    {
        name = "GelatoDelegation";
        version = "0.0.1";
    }
}
