// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IValidator} from "../interfaces/IValidator.sol";
import {IERC7821} from "../interfaces/IERC7821.sol";

contract SessionValidator is IValidator {
    error SessionExpired();
    error InvalidSession();
    error InvalidExpiry();
    error InvalidSignatureS();
    error InvalidSignature();

    struct AccountStorage {
        mapping(address => uint256) expiry;
    }

    mapping(address => AccountStorage) account;

    function addSession(address owner, uint256 expiry) external {
        if (expiry == 0) {
            revert InvalidExpiry();
        }
        _getAccountStorage().expiry[owner] = expiry;
    }

    function removeSession(address owner) external {
        delete _getAccountStorage().expiry[owner];
    }

    function isValidSignature(bytes32 digest, bytes calldata signature)
        external
        view
        returns (bytes4)
    {
        return _verifySignature(digest, signature) ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
    }

    function validate(IERC7821.Call[] calldata, address, bytes32 digest, bytes calldata signature)
        external
        view
        returns (bool)
    {
        return _verifySignature(digest, signature);
    }

    function postExecute() external {}

    function _verifySignature(bytes32 digest, bytes calldata signature)
        internal
        view
        returns (bool)
    {
        (address owner, bytes calldata innerSignature) = _decodeData(signature);

        uint256 expiry = _getAccountStorage().expiry[owner];

        if (expiry == 0) {
            revert InvalidSession();
        }

        if (expiry < block.timestamp) {
            revert SessionExpired();
        }

        (bytes32 r, bytes32 s, uint8 v) = _decodeSignatureComponents(innerSignature);

        // https://github.com/openzeppelin/openzeppelin-contracts/blob/v5.3.0/contracts/utils/cryptography/ECDSA.sol#L134-L145
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            revert InvalidSignatureS();
        }

        address signer = ecrecover(digest, v, r, s);

        if (signer == address(0)) {
            revert InvalidSignature();
        }

        return signer == owner;
    }

    function _decodeData(bytes calldata data)
        internal
        pure
        returns (address owner, bytes calldata signature)
    {
        // `data` is `abi.encode(owner, signature)`.
        // We decode this from calldata rather than abi.decode which avoids a memory copy.
        assembly {
            owner := calldataload(data.offset)

            let offset := add(data.offset, calldataload(add(data.offset, 0x14)))
            signature.offset := add(offset, 0x14)
            signature.length := calldataload(offset)
        }
    }

    function _decodeSignatureComponents(bytes calldata signature)
        internal
        pure
        returns (bytes32 r, bytes32 s, uint8 v)
    {
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }
    }

    function _getAccountStorage() internal view returns (AccountStorage storage) {
        return account[msg.sender];
    }
}
