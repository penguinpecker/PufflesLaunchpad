// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/// @title PuffleCall
/// @notice Multicall aggregator for the Puffles Launchpad ecosystem on Push Chain
/// @dev Based on Multicall3 — batches multiple read/write calls into a single request
/// @author Puffles Team

contract PuffleCall {
    struct Call3 {
        address target;
        bool allowFailure;
        bytes callData;
    }

    struct Result {
        bool success;
        bytes returnData;
    }

    function aggregate3(Call3[] calldata calls)
        external
        payable
        returns (Result[] memory results)
    {
        uint256 length = calls.length;
        results = new Result[](length);

        for (uint256 i = 0; i < length; ) {
            Result memory result = results[i];
            Call3 calldata call = calls[i];

            (result.success, result.returnData) = call.target.call(call.callData);

            if (!call.allowFailure && !result.success) {
                assembly {
                    let ptr := mload(add(mload(add(results, add(32, mul(i, 32)))), 64))
                    let size := mload(ptr)
                    revert(add(ptr, 32), size)
                }
            }

            unchecked { ++i; }
        }
    }

    function aggregateStrict(Call3[] calldata calls)
        external
        payable
        returns (bytes[] memory results)
    {
        uint256 length = calls.length;
        results = new bytes[](length);

        for (uint256 i = 0; i < length; ) {
            (bool success, bytes memory ret) = calls[i].target.call(calls[i].callData);
            require(success, "PuffleCall: call failed");
            results[i] = ret;
            unchecked { ++i; }
        }
    }

    function getBlockNumber() external view returns (uint256) {
        return block.number;
    }

    function getBlockTimestamp() external view returns (uint256) {
        return block.timestamp;
    }

    function getChainId() external view returns (uint256) {
        return block.chainid;
    }

    function getEthBalance(address addr) external view returns (uint256) {
        return addr.balance;
    }
}
