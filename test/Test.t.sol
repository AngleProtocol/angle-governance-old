// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { IGovernor } from "oz/governance/IGovernor.sol";
import { TimelockController } from "oz/governance/TimelockController.sol";
import { IVotes } from "oz/governance/extensions/GovernorVotes.sol";
import { Strings } from "oz/utils/Strings.sol";
import { ILayerZeroEndpoint } from "lz/interfaces/ILayerZeroEndpoint.sol";

import { console } from "forge-std/Console.sol";
import { Test, stdError } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";

import { AngleGovernor } from "contracts/AngleGovernor.sol";
import { ProposalReceiver } from "contracts/ProposalReceiver.sol";
import { ProposalSender } from "contracts/ProposalSender.sol";

contract Fixture is Test {
    event ExecuteRemoteProposal(uint16 indexed remoteChainId, bytes payload);

    uint256 public mainnetFork;
    string public MAINNET_RPC_URL = vm.envString("ETH_NODE_URI_1");
    ILayerZeroEndpoint mainnetLzEndpoint = ILayerZeroEndpoint(0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675);
    AngleGovernor public angleGovernor;
    IVotes public veANGLE = IVotes(0x0C462Dbb9EC8cD1630f1728B2CFD2769d09f0dd5);
    TimelockController public mainnetTimelock;
    address public mainnetMultisig = 0xdC4e6DFe07EFCa50a197DF15D9200883eF4Eb1c8;
    ProposalSender proposalSender;
    address whale = 0xD13F8C25CceD32cdfA79EB5eD654Ce3e484dCAF5;

    uint256 public polygonFork;
    string public POLYGON_RPC_URL = vm.envString("ETH_NODE_URI_137");
    ILayerZeroEndpoint polygonLzEndpoint = ILayerZeroEndpoint(0x3c2269811836af69497E5F486A85D7316753cf62);
    TimelockController public polygonTimelock;
    address public polygonMultisig = 0xdA2D2f638D6fcbE306236583845e5822554c02EA;
    ProposalReceiver proposalReceiver;

    address public alice = vm.addr(1);
    address public bob = vm.addr(2);

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

        return uint16(stringToUint(string(res)));
    }

    function setUp() public {
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Means everyone can execute

        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);
        mainnetTimelock = new TimelockController(1 days, proposers, executors, address(this));
        angleGovernor = new AngleGovernor(veANGLE, mainnetTimelock);
        mainnetTimelock.grantRole(mainnetTimelock.PROPOSER_ROLE(), address(angleGovernor));
        mainnetTimelock.grantRole(mainnetTimelock.CANCELLER_ROLE(), mainnetMultisig);
        mainnetTimelock.renounceRole(mainnetTimelock.TIMELOCK_ADMIN_ROLE(), address(this));
        proposalSender = new ProposalSender(mainnetLzEndpoint);

        polygonFork = vm.createFork(POLYGON_RPC_URL);
        vm.selectFork(polygonFork);
        polygonTimelock = new TimelockController(1 days, proposers, executors, address(this));
        proposalReceiver = new ProposalReceiver(address(polygonLzEndpoint));
        polygonTimelock.grantRole(polygonTimelock.PROPOSER_ROLE(), address(proposalReceiver));
        polygonTimelock.grantRole(polygonTimelock.CANCELLER_ROLE(), polygonMultisig);

        vm.selectFork(mainnetFork);
        proposalSender.setTrustedRemoteAddress(getLZChainId(137), abi.encodePacked(proposalReceiver));
        proposalSender.transferOwnership(address(angleGovernor));

        vm.selectFork(polygonFork);
        proposalReceiver.setTrustedRemoteAddress(getLZChainId(1), abi.encodePacked(proposalSender));
        proposalReceiver.transferOwnership(address(polygonTimelock));
    }

    function testSetup() public {
        vm.selectFork(mainnetFork);
    }

    function testMainnetSimpleVote() public {
        vm.selectFork(mainnetFork);

        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = 1;
        address[] memory targets = new address[](1);
        targets[0] = address(angleGovernor);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(angleGovernor.updateQuorum.selector, 1);
        (
            address[] memory proposalTargets,
            uint256[] memory proposalValues,
            bytes[] memory proposalCalldatas
        ) = wrapProposal(chainIds, targets, values, calldatas);
        string memory description = "Updating Quorum";

        hoax(whale);
        uint256 proposalId = angleGovernor.propose(proposalTargets, proposalValues, proposalCalldatas, description);
        vm.roll(block.number + angleGovernor.votingDelay() + 1);

        hoax(whale);
        angleGovernor.castVote(proposalId, 1);
        vm.roll(block.number + angleGovernor.votingPeriod() + 1);

        angleGovernor.execute(proposalTargets, proposalValues, proposalCalldatas, keccak256(bytes(description)));
        vm.warp(block.timestamp + mainnetTimelock.getMinDelay() + 1);

        assertEq(angleGovernor.quorum(0), 30000000e18);
        mainnetTimelock.execute(targets[0], values[0], calldatas[0], bytes32(0), 0);
        assertEq(angleGovernor.quorum(0), 1);
    }

    function testMainnetBatchVote() public {
        vm.selectFork(mainnetFork);

        uint256[] memory chainIds = new uint256[](2);
        chainIds[0] = 1;
        chainIds[1] = 1;
        address[] memory targets = new address[](2);
        targets[0] = address(angleGovernor);
        targets[1] = address(mainnetTimelock);
        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;
        bytes[] memory calldatas = new bytes[](2);
        calldatas[0] = abi.encodeWithSelector(angleGovernor.updateQuorum.selector, 1);
        calldatas[1] = abi.encodeWithSelector(mainnetTimelock.updateDelay.selector, 1);

        (
            address[] memory proposalTargets,
            uint256[] memory proposalValues,
            bytes[] memory proposalCalldatas
        ) = wrapProposal(chainIds, targets, values, calldatas);
        string memory description = "Updating Quorum and delay";

        hoax(whale);
        uint256 proposalId = angleGovernor.propose(proposalTargets, proposalValues, proposalCalldatas, description);
        vm.roll(block.number + angleGovernor.votingDelay() + 1);

        hoax(whale);
        angleGovernor.castVote(proposalId, 1);
        vm.roll(block.number + angleGovernor.votingPeriod() + 1);

        angleGovernor.execute(proposalTargets, proposalValues, proposalCalldatas, keccak256(bytes(description)));
        vm.warp(block.timestamp + mainnetTimelock.getMinDelay() + 1);

        assertNotEq(angleGovernor.quorum(0), 1);
        assertNotEq(mainnetTimelock.getMinDelay(), 1);
        mainnetTimelock.executeBatch(targets, values, calldatas, bytes32(0), 0);
        assertEq(angleGovernor.quorum(0), 1);
        assertEq(mainnetTimelock.getMinDelay(), 1);
    }

    function testPolygonSimpleVote() public {
        vm.selectFork(mainnetFork);
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = 137;
        address[] memory targets = new address[](1);
        targets[0] = address(polygonTimelock);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(polygonTimelock.updateDelay.selector, 1);

        (
            address[] memory proposalTargets,
            uint256[] memory proposalValues,
            bytes[] memory proposalCalldatas
        ) = wrapProposal(chainIds, targets, values, calldatas);
        string memory description = "Updating Delay on Polygon";
        hoax(whale);
        uint256 proposalId = angleGovernor.propose(proposalTargets, proposalValues, proposalCalldatas, description);
        vm.roll(block.number + angleGovernor.votingDelay() + 1);
        hoax(whale);
        angleGovernor.castVote(proposalId, 1);
        vm.roll(block.number + angleGovernor.votingPeriod() + 1);

        vm.recordLogs();
        angleGovernor.execute{ value: 0.1 ether }(
            proposalTargets,
            proposalValues,
            proposalCalldatas,
            keccak256(bytes(description))
        ); // TODO Optimize value

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes memory payload;
        for (uint256 i; i < entries.length; i++) {
            if (
                entries[i].topics[0] == keccak256("ExecuteRemoteProposal(uint16,bytes)") &&
                entries[i].topics[1] == bytes32(uint256(getLZChainId(137)))
            ) {
                payload = abi.decode(entries[i].data, (bytes));
                break;
            }
        }

        vm.selectFork(polygonFork);
        hoax(address(polygonLzEndpoint));
        proposalReceiver.lzReceive(getLZChainId(1), abi.encodePacked(proposalSender, proposalReceiver), 0, payload);

        // Final test
        vm.warp(block.timestamp + polygonTimelock.getMinDelay() + 1);
        assertNotEq(polygonTimelock.getMinDelay(), 1);
        polygonTimelock.execute(targets[0], values[0], calldatas[0], bytes32(0), 0);
        assertEq(polygonTimelock.getMinDelay(), 1);
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
        if (
            targets.length == 0 ||
            targets.length != values.length ||
            targets.length != calldatas.length ||
            targets.length != chainIds.length
        ) {
            revert("targets, values, and calldatas must be the same length > 0");
        }

        finalTargets = new address[](chainIds.length);
        uint256 finalTargetsLength = 0;
        finalValues = new uint256[](chainIds.length);
        uint256 finalValuesLength = 0;
        finalCalldatas = new bytes[](chainIds.length);
        uint256 finalCalldatasLength = 0;

        for (uint256 i; i < chainIds.length; ++i) {
            uint256 chainId = chainIds[i];

            // Check the number of same chainId actions
            uint256 count = 1;
            while (i + count < chainIds.length && chainIds[i + count] == chainId) {
                count++;
            }

            if (chainId == 1) {
                vm.selectFork(mainnetFork);
                if (count == 1) {
                    // In case the operation has already been done add a salt
                    uint256 salt = 0;
                    while (
                        mainnetTimelock.isOperation(
                            mainnetTimelock.hashOperation(
                                targets[i],
                                values[i],
                                calldatas[i],
                                bytes32(0),
                                bytes32(salt)
                            )
                        )
                    ) {
                        salt++;
                    }

                    // Simple schedule on timelock
                    finalTargets[finalTargetsLength] = address(mainnetTimelock);
                    finalTargetsLength += 1;

                    finalValues[finalValuesLength] = 0;
                    finalValuesLength += 1;

                    finalCalldatas[finalCalldatasLength] = abi.encodeWithSelector(
                        mainnetTimelock.schedule.selector,
                        targets[i],
                        values[i],
                        calldatas[i],
                        bytes32(0),
                        salt,
                        mainnetTimelock.getMinDelay()
                    );
                    finalCalldatasLength += 1;
                } else {
                    address[] memory batchTargets = new address[](count);
                    uint256[] memory batchValues = new uint256[](count);
                    bytes[] memory batchCalldatas = new bytes[](count);

                    for (uint256 j; j < count; j++) {
                        batchTargets[j] = targets[i + j];
                        batchValues[j] = values[i + j];
                        batchCalldatas[j] = calldatas[i + j];
                    }

                    // In case the operation has already been done add a salt
                    uint256 salt = 0;
                    while (
                        mainnetTimelock.isOperation(
                            mainnetTimelock.hashOperationBatch(
                                batchTargets,
                                batchValues,
                                batchCalldatas,
                                bytes32(0),
                                bytes32(salt)
                            )
                        )
                    ) {
                        salt++;
                    }

                    finalTargets[finalTargetsLength] = address(mainnetTimelock);
                    finalTargetsLength += 1;

                    finalValues[finalValuesLength] = 0;
                    finalValuesLength += 1;

                    finalCalldatas[finalCalldatasLength] = abi.encodeWithSelector(
                        mainnetTimelock.scheduleBatch.selector,
                        batchTargets,
                        batchValues,
                        batchCalldatas,
                        bytes32(0),
                        salt,
                        mainnetTimelock.getMinDelay()
                    );
                    finalCalldatasLength += 1;

                    i += count;
                }
            } else if (chainId == 137) {
                vm.selectFork(polygonFork);
                if (count == 1) {
                    // In case the operation has already been done add a salt
                    uint256 salt = 0;
                    while (
                        polygonTimelock.isOperation(
                            polygonTimelock.hashOperation(
                                targets[i],
                                values[i],
                                calldatas[i],
                                bytes32(0),
                                bytes32(salt)
                            )
                        )
                    ) {
                        salt++;
                    }

                    // Simple schedule on timelock
                    finalTargets[finalTargetsLength] = address(proposalSender);
                    finalTargetsLength += 1;

                    finalValues[finalValuesLength] = 0.1 ether; // TODO Customize
                    finalValuesLength += 1;

                    address[] memory batchTargets = new address[](1);
                    batchTargets[0] = address(polygonTimelock);
                    uint256[] memory batchValues = new uint256[](1);
                    batchValues[0] = 0;
                    bytes[] memory batchCalldatas = new bytes[](1);
                    batchCalldatas[0] = abi.encodeWithSelector(
                        polygonTimelock.schedule.selector,
                        targets[i],
                        values[i],
                        calldatas[i],
                        bytes32(0),
                        salt,
                        polygonTimelock.getMinDelay()
                    );

                    finalCalldatas[finalCalldatasLength] = abi.encodeWithSelector(
                        proposalSender.execute.selector,
                        getLZChainId(chainId),
                        abi.encode(batchTargets, batchValues, new string[](1), batchCalldatas),
                        abi.encodePacked(uint16(1), uint256(300000))
                    );

                    finalCalldatasLength += 1;
                } else {}
            }
        }

        assembly ("memory-safe") {
            mstore(finalTargets, finalTargetsLength)
            mstore(finalValues, finalValuesLength)
            mstore(finalCalldatas, finalCalldatasLength)
        }

        vm.selectFork(mainnetFork); // Set back the fork to mainnet
    }
}
