// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {Counter} from "./Counter.sol";
import {Delegation} from "../src/Delegation.sol";

contract DelegationTest is Test {
    Counter counter;
    Delegation delegation;

    // bd332231782779917708cab38f801e41b47a1621b8270226999e8e6ea344b61c
    address payable eoa = payable(0xD1fa593A9cc041e1CB82492B9CE17f2187fEdB72);

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

        bytes memory sig =
            hex"32ca70ca2f116dd67d1a14db3e331e2ec3f5c7ed503668403d6c3ccc5b4ac9530f91323c99e986c4767bacf75d73788859b5aae5f451441ec848768e870477761c";

        Delegation.Call[] memory calls = new Delegation.Call[](1);
        calls[0].to = address(counter);
        calls[0].data = abi.encodeWithSelector(counter.increment.selector);

        Delegation(eoa).execute(mode, abi.encode(calls, sig));

        assertEq(counter.value(), 1);
    }

    function testExecuteECDSARevert() public {
        bytes32 mode = 0x0100000000007821000100000000000000000000000000000000000000000000;

        bytes memory sig =
            hex"32ca70ca2f116dd67d1a14bb3e331e2ec3f5c7ed503668403d6c3ccc5b4ac9530f91323c99e986c4767bacf75d73788859b5aae5f451441ec848768e870477761c";

        Delegation.Call[] memory calls = new Delegation.Call[](1);
        calls[0].to = address(counter);
        calls[0].data = abi.encodeWithSelector(counter.increment.selector);

        vm.expectRevert(Delegation.Unauthorized.selector);
        Delegation(eoa).execute(mode, abi.encode(calls, sig));
    }

    function testSimulateExecuteECDSA() public {
        bytes32 mode = 0x0100000000007821000100000000000000000000000000000000000000000000;

        bytes memory sig =
            hex"32ca70ca3f116dd67d1a14db3e331e2ec3f5c7ed503668403d6c3ccc5b4ac9530f91323c99e986c4767bacf75d73788859b5aae5f451441ec848768e870477761c";

        Delegation.Call[] memory calls = new Delegation.Call[](1);
        calls[0].to = address(counter);
        calls[0].data = abi.encodeWithSelector(counter.increment.selector);

        vm.expectPartialRevert(Delegation.SimulationResult.selector);
        Delegation(eoa).simulateExecute(mode, abi.encode(calls, sig));
    }
}
