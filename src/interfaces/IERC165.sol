// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

// https://eips.ethereum.org/EIPS/eip-165
interface IERC165 {
    function supportsInterface(bytes4 interfaceID) external view returns (bool);
}
