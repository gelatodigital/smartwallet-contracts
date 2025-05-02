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
import {P256} from "solady/utils/P256.sol";
import {WebAuthn} from "solady/utils/WebAuthn.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";

contract Delegation is IERC7821, IERC1271, IERC4337, EIP712 {
    error UnsupportedExecutionMode();
    error InvalidCaller();
    error Unauthorized();
    error InvalidNonce();
    error ExcessiveInvalidation();

    // https://eips.ethereum.org/EIPS/eip-7201
    /// @custom:storage-location erc7201:delegation.storage
    struct Storage {
        mapping(uint192 => uint64) nonceSequenceNumber;
        mapping(bytes32 => bytes) pubkey;
    }

    // keccak256(abi.encode(uint256(keccak256("delegation.storage")) - 1)) &
    // ~bytes32(uint256(0xff));
    bytes32 private constant STORAGE_LOCATION =
        0xf2a7602a6b0fea467fdf81ac322504e60523f80eb506a1ca5e0f3e0d2ac70500;

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

    function execute(bytes32 mode, bytes calldata executionData) external payable {
        (bytes1 callType, bytes1 execType, bytes4 modeSelector,) = _decodeExecutionMode(mode);

        if (callType != CALL_TYPE_BATCH || execType != EXEC_TYPE_DEFAULT) {
            revert UnsupportedExecutionMode();
        }

        // If `opData` is empty, `executionData` is simply `abi.encode(calls)`.
        // We decode this from calldata rather than abi.decode which avoids a memory copy
        Call[] calldata calls;
        assembly {
            let offset := add(executionData.offset, calldataload(executionData.offset))
            calls.offset := add(offset, 0x20)
            calls.length := calldataload(offset)
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

            _execute(calls);
        } else {
            // If `opData` is not empty, `executionData` is `abi.encode(calls, opData)`.
            // We decode this from calldata rather than abi.decode which avoids a memory copy
            bytes calldata opData;
            assembly {
                let offset :=
                    add(executionData.offset, calldataload(add(executionData.offset, 0x20)))
                opData.offset := add(offset, 0x20)
                opData.length := calldataload(offset)
            }

            // Extract nonce from opData - first 32 bytes
            uint192 nonceKey;
            assembly {
                nonceKey := shl(64, shr(64, calldataload(opData.offset)))
            }

            uint256 nonce = _getAndUseNonce(nonceKey);
            bytes32 digest = _computeDigest(mode, calls, nonce);

            // Verify signature using the rest of opData (excluding the nonce)
            bytes calldata signature;
            assembly {
                signature.offset := add(opData.offset, 24)
                signature.length := sub(opData.length, 24)
            }

            // If `opData` is not empty, the implementation SHOULD use the signature encoded in
            // `opData` to determine if the caller can perform the execution.
            if (!_verifySignature(digest, signature)) {
                revert Unauthorized();
            }

            _execute(calls);
        }
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

    function addSigner(bytes calldata pubkey) external onlyThis {
        bytes32 keyHash = keccak256(pubkey);
        _getStorage().pubkey[keyHash] = pubkey;
    }

    function removeSigner(bytes32 keyHash) external onlyThis {
        delete _getStorage().pubkey[keyHash];
    }

    function getNonce(uint192 key) external view returns (uint256) {
        Storage storage s = _getStorage();
        return _encodeNonce(key, s.nonceSequenceNumber[key]);
    }

    function invalidateNonce(uint256 newNonce) external onlyThis {
        uint192 key = uint192(newNonce >> 64);
        uint64 targetSeq = uint64(newNonce);
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

    function _execute(Call[] calldata calls) private {
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

    function _verifySignature(bytes32 digest, bytes calldata signature)
        private
        view
        returns (bool)
    {
        // If `signature` length is 64 or 65, treat it as secp256k1 signature
        if (signature.length == 64 || signature.length == 65) {
            return ECDSA.recoverCalldata(digest, signature) == address(this);
        }

        // `data` is `abi.encode(keyHash, signature)`.
        bytes32 keyHash;
        assembly {
            keyHash := calldataload(signature.offset)

            let offset := add(signature.offset, calldataload(add(signature.offset, 0x20)))
            signature.offset := add(offset, 0x20)
            signature.length := calldataload(offset)
        }

        bytes storage pubkey = _getStorage().pubkey[keyHash];

        (bytes32 x, bytes32 y) = P256.tryDecodePoint(pubkey);

        return WebAuthn.verify(
            abi.encode(digest), false, WebAuthn.tryDecodeAuthCompactCalldata(signature), x, y
        );
    }

    function _computeDigest(bytes32 mode, Call[] calldata calls, uint256 nonce)
        private
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

    function _getAndUseNonce(uint192 key) private returns (uint256) {
        uint64 seq = _getStorage().nonceSequenceNumber[key];
        _getStorage().nonceSequenceNumber[key]++;
        return _encodeNonce(key, seq);
    }

    function _encodeNonce(uint192 key, uint64 seq) private pure returns (uint256) {
        return (uint256(key) << 64) | seq;
    }

    function _getStorage() private pure returns (Storage storage $) {
        assembly {
            $.slot := STORAGE_LOCATION
        }
    }

    function _decodeExecutionMode(bytes32 mode)
        private
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
        name = "Delegation";
        version = "0.0.1";
    }
}
