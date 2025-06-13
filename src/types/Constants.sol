// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

// https://eips.ethereum.org/EIPS/eip-7579
// https://eips.ethereum.org/EIPS/eip-7821
bytes1 constant CALL_TYPE_BATCH = 0x01;
bytes1 constant EXEC_TYPE_DEFAULT = 0x00;
bytes4 constant EXEC_MODE_DEFAULT = 0x00000000;
bytes4 constant EXEC_MODE_OP_DATA = 0x78210001;

// https://github.com/eth-infinitism/account-abstraction/releases
address constant ENTRY_POINT_V8 = 0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108;
address constant ENTRY_POINT_V7 = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

address constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
