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

    event SessionAdded(address indexed signer, uint256 expiry);
    event SessionRemoved(address indexed signer);

    struct AccountStorage {
        mapping(address => uint256) expiry;
    }

    mapping(address => AccountStorage) account;

    function addSession(address signer, uint256 expiry) external {
        if (expiry == 0) {
            revert InvalidExpiry();
        }
        _getAccountStorage().expiry[signer] = expiry;
        emit SessionAdded(signer, expiry);
    }

    function removeSession(address signer) external {
        delete _getAccountStorage().expiry[signer];
        emit SessionRemoved(signer);
    }

    function getSessionExpiry(address signer) external view returns (uint256) {
        return _getAccountStorage().expiry[signer];
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
        (address signer, bytes calldata innerSignature) = _decodeData(signature);

        uint256 expiry = _getAccountStorage().expiry[signer];

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

        address recovered = ecrecover(digest, v, r, s);

        if (recovered == address(0)) {
            revert InvalidSignature();
        }

        return recovered == signer;
    }

    function _decodeData(bytes calldata data)
        internal
        pure
        returns (address signer, bytes calldata signature)
    {
        // `data` is `abi.encodePacked(signer, signature)`.
        // We decode this from calldata rather than abi.decode which avoids a memory copy.
        assembly {
            signer := shr(96, calldataload(data.offset))

            signature.offset := add(data.offset, 20)
            signature.length := sub(data.length, 20)
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
