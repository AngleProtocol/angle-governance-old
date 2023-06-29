// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { IGovernor } from "oz/governance/IGovernor.sol";
import { TimelockController } from "oz/governance/TimelockController.sol";
import { IVotes } from "oz/governance/extensions/GovernorVotes.sol";
import { Strings } from "oz/utils/Strings.sol";

import { console } from "forge-std/Console.sol";
import { Test, stdError } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";

import { AngleGovernor } from "contracts/AngleGovernor.sol";
import { ProposalReceiver } from "contracts/ProposalReceiver.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";

import { ILayerZeroEndpoint } from "lz/interfaces/ILayerZeroEndpoint.sol";

contract Build is Test {
    function stringToUint(string memory s) public pure returns (uint) {
        bytes memory b = bytes(s);
        uint result = 0;
        for (uint256 i = 0; i < b.length; i++) {
            uint256 c = uint256(uint8(b[i]));
            if (c >= 48 && c <= 57) {
                result = result * 10 + (c - 48);
            }
        }
        return result;
    }

    function getLZChainId(uint256 chainId) internal returns (uint16) {
        string[] memory cmd = new string[](3);
        cmd[0] = "node";
        cmd[1] = "utils/getLayerZeroChainIds.js";
        cmd[2] = vm.toString(chainId);

        bytes memory res = vm.ffi(cmd);
        console.log(string(res));
        return uint16(stringToUint(string(res)));
    }

    function setUp() public {
        console.log(getLZChainId(137));
    }

    function testSetUp() public {
        console.log(getLZChainId(137));
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        HELPERS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Build the governor proposal based on all the transaction that need to be executed
    function wrapProposal(
        uint256[] memory chainIds, // Has to be consecutive -> (1,2,1) is invalid
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas
    ) internal returns (address[] memory finalTargets, uint256[] memory finalValues, bytes[] memory finalCalldatas) {
        // if (
        //     targets.length == 0 ||
        //     targets.length != values.length ||
        //     targets.length != calldatas.length ||
        //     targets.length != chainIds.length
        // ) {
        //     revert("targets, values, and calldatas must be the same length > 0");
        // }
        // finalTargets = new address[](chainIds.length);
        // uint256 finalTargetsLength = 0;
        // finalValues = new uint256[](chainIds.length);
        // uint256 finalValuesLength = 0;
        // finalCalldatas = new bytes[](chainIds.length);
        // uint256 finalCalldatasLength = 0;
        // for (uint256 i; i < chainIds.length; ++i) {
        //     uint256 chainId = chainIds[i];
        //     // Check the number of same chainId actions
        //     uint256 count = 1;
        //     while (i + count < chainIds.length && chainIds[i + count] == chainId) {
        //         count++;
        //     }
        //     if (chainId == 1) {
        //         vm.selectFork(mainnetFork);
        //         if (count == 1) {
        //             // In case the operation has already been done add a salt
        //             uint256 salt = 0;
        //             while (
        //                 mainnetTimelock.isOperation(
        //                     mainnetTimelock.hashOperation(
        //                         targets[i],
        //                         values[i],
        //                         calldatas[i],
        //                         bytes32(0),
        //                         bytes32(salt)
        //                     )
        //                 )
        //             ) {
        //                 salt++;
        //             }
        //             // Simple schedule on timelock
        //             finalTargets[finalTargetsLength] = address(mainnetTimelock);
        //             finalTargetsLength += 1;
        //             finalValues[finalValuesLength] = 0;
        //             finalValuesLength += 1;
        //             finalCalldatas[finalCalldatasLength] = abi.encodeWithSelector(
        //                 mainnetTimelock.schedule.selector,
        //                 targets[i],
        //                 values[i],
        //                 calldatas[i],
        //                 bytes32(0),
        //                 salt,
        //                 mainnetTimelock.getMinDelay()
        //             );
        //             finalCalldatasLength += 1;
        //         } else {
        //             address[] memory batchTargets = new address[](count);
        //             uint256[] memory batchValues = new uint256[](count);
        //             bytes[] memory batchCalldatas = new bytes[](count);
        //             for (uint256 j; j < count; j++) {
        //                 batchTargets[j] = targets[i + j];
        //                 batchValues[j] = values[i + j];
        //                 batchCalldatas[j] = calldatas[i + j];
        //             }
        //             // In case the operation has already been done add a salt
        //             uint256 salt = 0;
        //             while (
        //                 mainnetTimelock.isOperation(
        //                     mainnetTimelock.hashOperationBatch(
        //                         batchTargets,
        //                         batchValues,
        //                         batchCalldatas,
        //                         bytes32(0),
        //                         bytes32(salt)
        //                     )
        //                 )
        //             ) {
        //                 salt++;
        //             }
        //             finalTargets[finalTargetsLength] = address(mainnetTimelock);
        //             finalTargetsLength += 1;
        //             finalValues[finalValuesLength] = 0;
        //             finalValuesLength += 1;
        //             finalCalldatas[finalCalldatasLength] = abi.encodeWithSelector(
        //                 mainnetTimelock.scheduleBatch.selector,
        //                 batchTargets,
        //                 batchValues,
        //                 batchCalldatas,
        //                 bytes32(0),
        //                 salt,
        //                 mainnetTimelock.getMinDelay()
        //             );
        //             finalCalldatasLength += 1;
        //             i += count;
        //         }
        //     } else if (chainId == 137) {
        //         vm.selectFork(polygonFork);
        //         if (count == 1) {
        //             // In case the operation has already been done add a salt
        //             uint256 salt = 0;
        //             while (
        //                 polygonTimelock.isOperation(
        //                     polygonTimelock.hashOperation(
        //                         targets[i],
        //                         values[i],
        //                         calldatas[i],
        //                         bytes32(0),
        //                         bytes32(salt)
        //                     )
        //                 )
        //             ) {
        //                 salt++;
        //             }
        //             // Simple schedule on timelock
        //             finalTargets[finalTargetsLength] = address(proposalSender);
        //             finalTargetsLength += 1;
        //             finalValues[finalValuesLength] = 0.1 ether; // TODO Customize
        //             finalValuesLength += 1;
        //             address[] memory batchTargets = new address[](1);
        //             batchTargets[0] = address(polygonTimelock);
        //             uint256[] memory batchValues = new uint256[](1);
        //             batchValues[0] = 0;
        //             bytes[] memory batchCalldatas = new bytes[](1);
        //             batchCalldatas[0] = abi.encodeWithSelector(
        //                 polygonTimelock.schedule.selector,
        //                 targets[i],
        //                 values[i],
        //                 calldatas[i],
        //                 bytes32(0),
        //                 salt,
        //                 polygonTimelock.getMinDelay()
        //             );
        //             finalCalldatas[finalCalldatasLength] = abi.encodeWithSelector(
        //                 proposalSender.execute.selector,
        //                 getLZChainId(chainId),
        //                 abi.encode(batchTargets, batchValues, new string[](1), batchCalldatas),
        //                 abi.encodePacked(uint16(1), uint256(300000))
        //             );
        //             finalCalldatasLength += 1;
        //         } else {}
        //     }
        // }
        // assembly ("memory-safe") {
        //     mstore(finalTargets, finalTargetsLength)
        //     mstore(finalValues, finalValuesLength)
        //     mstore(finalCalldatas, finalCalldatasLength)
        // }
        // vm.selectFork(mainnetFork); // Set back the fork to mainnet
    }
}
