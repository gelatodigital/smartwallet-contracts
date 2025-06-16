// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ENTRY_POINT_V8} from "../types/Constants.sol";

contract EntryPointV8Proxy {
    fallback() external payable {
        bytes calldata data;
        assembly {
            data.offset := 1
            data.length := sub(calldatasize(), 1)
        }

        (bool success, bytes memory result) = ENTRY_POINT_V8.call(data);

        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }
}
