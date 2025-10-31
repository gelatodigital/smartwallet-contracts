// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

// https://eips.ethereum.org/EIPS/eip-20
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);
}
