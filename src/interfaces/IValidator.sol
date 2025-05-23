// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

interface IValidator {
    function validate(bytes32 digest, bytes calldata data) external view returns (bool);
}
