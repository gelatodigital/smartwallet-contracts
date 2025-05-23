// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IValidator} from "../interfaces/IValidator.sol";
import {P256} from "solady/utils/P256.sol";
import {WebAuthn} from "solady/utils/WebAuthn.sol";

contract PasskeyValidator is IValidator {
    struct AccountStorage {
        mapping(bytes32 => bytes) pubkey;
    }

    mapping(address => AccountStorage) account;

    function addSigner(bytes calldata pubkey) external {
        bytes32 keyHash = keccak256(pubkey);
        _getAccountStorage().pubkey[keyHash] = pubkey;
    }

    function removeSigner(bytes32 keyHash) external {
        delete _getAccountStorage().pubkey[keyHash];
    }

    function validate(bytes32 digest, bytes calldata data) external view returns (bool) {
        (bytes32 keyHash, bytes calldata signature) = _decodeData(data);

        bytes storage pubkey = _getAccountStorage().pubkey[keyHash];
        (bytes32 x, bytes32 y) = P256.tryDecodePoint(pubkey);

        return WebAuthn.verify(
            abi.encode(digest), false, WebAuthn.tryDecodeAuthCompactCalldata(signature), x, y
        );
    }

    function _decodeData(bytes calldata data)
        internal
        pure
        returns (bytes32 keyHash, bytes calldata signature)
    {
        // `data` is `abi.encode(keyHash, signature)`.
        // We decode this from calldata rather than abi.decode which avoids a memory copy.
        assembly {
            keyHash := calldataload(data.offset)

            let offset := add(data.offset, calldataload(add(data.offset, 0x20)))
            signature.offset := add(offset, 0x20)
            signature.length := calldataload(offset)
        }
    }

    function _getAccountStorage() internal view returns (AccountStorage storage) {
        return account[msg.sender];
    }
}
