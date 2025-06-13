// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ENTRY_POINT_V7} from "../types/Constants.sol";

contract EntryPointV7Proxy {
    fallback() external payable {
        (bool success, bytes memory data) = ENTRY_POINT_V7.call{value: msg.value}(msg.data);

        if (!success) {
            assembly {
                revert(add(data, 32), mload(data))
            }
        }
    }
}
