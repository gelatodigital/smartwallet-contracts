// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Counter} from "./Counter.sol";
import {ECDSASignature} from "./ECDSASignature.sol";
import {Delegation} from "../src/Delegation.sol";
import {Simulation} from "../src/Simulation.sol";
import {Test} from "forge-std/Test.sol";

contract DelegationTest is ECDSASignature, Test {
    Counter counter;
    Delegation delegation;

    uint256 privateKey = 0xbd332231782779917708cab38f801e41b47a1621b8270226999e8e6ea344b61c;
    address payable eoa = payable(vm.addr(privateKey)); // 0xD1fa593A9cc041e1CB82492B9CE17f2187fEdB72

    function setUp() public {
        counter = new Counter();
        delegation = new Delegation();

        // set EIP-7702 delegation
        vm.etch(eoa, abi.encodePacked(hex"ef0100", address(delegation)));
    }

    function testExecute() public {
        bytes32 mode = 0x0100000000000000000000000000000000000000000000000000000000000000;

        Delegation.Call[] memory calls = new Delegation.Call[](1);
        calls[0].to = address(counter);
        calls[0].data = abi.encodeWithSelector(counter.increment.selector);

        vm.prank(eoa);
        Delegation(eoa).execute(mode, abi.encode(calls));

        assertEq(counter.value(), 1);
    }

    function testExecuteRevert() public {
        bytes32 mode = 0x0100000000000000000000000000000000000000000000000000000000000000;

        Delegation.Call[] memory calls = new Delegation.Call[](1);
        calls[0].to = address(counter);
        calls[0].data = abi.encodeWithSelector(counter.increment.selector);

        vm.expectRevert(Delegation.Unauthorized.selector);
        Delegation(eoa).execute(mode, abi.encode(calls));
    }

    function testExecuteECDSA() public {
        bytes32 mode = 0x0100000000007821000100000000000000000000000000000000000000000000;

        Delegation.Call[] memory calls = new Delegation.Call[](1);
        calls[0].to = address(counter);
        calls[0].data = abi.encodeWithSelector(counter.increment.selector);

        uint192 key = 0;
        uint256 nonce = delegation.getNonce(key);

        bytes memory sig = _generateECDSASig(vm, delegation, privateKey, mode, calls, nonce);
        bytes memory opData = abi.encodePacked(key, sig);

        Delegation(eoa).execute(mode, abi.encode(calls, opData));

        assertEq(counter.value(), 1);
    }

    function testExecuteECDSARevert() public {
        bytes32 mode = 0x0100000000007821000100000000000000000000000000000000000000000000;

        Delegation.Call[] memory calls = new Delegation.Call[](1);
        calls[0].to = address(counter);
        calls[0].data = abi.encodeWithSelector(counter.increment.selector);

        uint192 key = 0;
        uint256 nonce = delegation.getNonce(key);

        uint256 invalidPrivateKey =
            vm.deriveKey("test test test test test test test test test test test junk", 0);
        bytes memory sig = _generateECDSASig(vm, delegation, invalidPrivateKey, mode, calls, nonce);
        bytes memory opData = abi.encodePacked(key, sig);

        vm.expectRevert(Delegation.Unauthorized.selector);
        Delegation(eoa).execute(mode, abi.encode(calls, opData));
    }

    function testSimulateExecuteECDSA() public {
        bytes32 mode = 0x0100000000007821000100000000000000000000000000000000000000000000;

        Delegation.Call[] memory calls = new Delegation.Call[](1);
        calls[0].to = address(counter);
        calls[0].data = abi.encodeWithSelector(counter.increment.selector);

        uint192 key = 0;
        uint256 nonce = delegation.getNonce(key);

        uint256 invalidPrivateKey =
            vm.deriveKey("test test test test test test test test test test test junk", 0);
        bytes memory sig = _generateECDSASig(vm, delegation, invalidPrivateKey, mode, calls, nonce);
        bytes memory opData = abi.encodePacked(key, sig);

        vm.etch(eoa, vm.getCode("Simulation.sol:Simulation"));
        Simulation(eoa).simulateExecute(mode, abi.encode(calls, opData));
    }

    function testParallelNonceOrders() public {
        bytes32 mode = 0x0100000000007821000100000000000000000000000000000000000000000000;

        Delegation.Call[] memory calls = new Delegation.Call[](1);
        calls[0].to = address(counter);
        calls[0].data = abi.encodeWithSelector(counter.increment.selector);

        uint192 key1 = 0;
        uint192 key2 = 11111;

        uint256 nonce1 = Delegation(eoa).getNonce(key1);
        uint256 nonce2 = Delegation(eoa).getNonce(key2);

        bytes memory sig1 = _generateECDSASig(vm, delegation, privateKey, mode, calls, nonce1);
        bytes memory sig2 = _generateECDSASig(vm, delegation, privateKey, mode, calls, nonce2);

        bytes memory opData1 = abi.encodePacked(key1, sig1);
        bytes memory opData2 = abi.encodePacked(key2, sig2);

        uint256 expectedNonce1 = (uint256(key1) << 64) | uint64(1);
        uint256 expectedNonce2 = (uint256(key2) << 64) | uint64(1);

        uint256 snapshot = vm.snapshot();

        // Test first order
        Delegation(eoa).execute(mode, abi.encode(calls, opData1));
        Delegation(eoa).execute(mode, abi.encode(calls, opData2));

        assertEq(counter.value(), 2);
        assertEq(Delegation(eoa).getNonce(key1), expectedNonce1);
        assertEq(Delegation(eoa).getNonce(key2), expectedNonce2);

        vm.revertTo(snapshot);

        // Test second order
        Delegation(eoa).execute(mode, abi.encode(calls, opData2));
        Delegation(eoa).execute(mode, abi.encode(calls, opData1));

        assertEq(counter.value(), 2);
        assertEq(Delegation(eoa).getNonce(key1), expectedNonce1);
        assertEq(Delegation(eoa).getNonce(key2), expectedNonce2);
    }
}
