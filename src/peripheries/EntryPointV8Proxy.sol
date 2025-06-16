// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ENTRY_POINT_V8} from "../types/Constants.sol";

contract EntryPointV8Proxy {
    fallback() external payable {
        (bool success, bytes memory data) = ENTRY_POINT_V8.call{value: msg.value}(msg.data);

        if (!success) {
            assembly {
                revert(add(data, 32), mload(data))
            }
        }
    }
}
