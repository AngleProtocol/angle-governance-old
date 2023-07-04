// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { IGovernor } from "oz/governance/IGovernor.sol";
import { IVotes } from "oz/governance/utils/IVotes.sol";

import { Governor, SafeCast } from "oz/governance/Governor.sol";
import { GovernorSettings } from "oz/governance/extensions/GovernorSettings.sol";
import { GovernorVotes } from "oz/governance/extensions/GovernorVotes.sol";
import { TimelockController } from "oz/governance/TimelockController.sol";

import { GovernorCountingFractional } from "./external/GovernorCountingFractional.sol";

import "./utils/Errors.sol";

/// @title AngleGovernor
/// @author Angle Labs, Inc
/// @dev Core of Angle governance system, extending various OpenZeppelin modules
/// @dev This contract overrides some OpenZeppelin function, like those in `GovernorSettings` to introduce
/// the `onlyExecutor` modifier which ensures that only the Timelock contract can update the system's parameters
/// @dev The time parameters (`votingDelay`, `votingPeriod`, ...) are expressed here in block number units which
///  means that this implementation is only suited for an Ethereum deployment
/// @custom:security-contact contact@angle.money
contract AngleGovernor is Governor, GovernorSettings, GovernorCountingFractional, GovernorVotes {
    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        EVENTS                                                      
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    event TimelockChange(address oldTimelock, address newTimelock);
    event QuorumChange(uint256 oldQuorum, uint256 newQuorum);

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       VARIABLES                                                    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    TimelockController private _timelock;
    uint256 private _quorum;

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       MODIFIER                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Checks whether the sender is the system's executor
    modifier onlyExecutor() {
        if (msg.sender != _executor()) revert NotExecutor();
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                      CONSTRUCTOR                                                   
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    constructor(
        IVotes _token,
        TimelockController timelockAddress
    )
        Governor("AngleGovernor")
        GovernorSettings(1800 /* 6 hours */, 36000 /* 5 days */, 100000e18)
        GovernorVotes(_token)
    {
        _updateTimelock(timelockAddress);
        _updateQuorum(10000000e18);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    VIEW FUNCTIONS                                                  
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Timelock address that owns this contract and can change the system's parameters
    function timelock() public view returns (address) {
        return address(_timelock);
    }

    /// @notice Will not be accurate if the quorum is changed will other proposals are running.
    function quorum(uint256) public view override returns (uint256) {
        return _quorum;
    }

    function _executor() internal view override(Governor) returns (address) {
        return address(_timelock);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                        SETTERS                                                     
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @notice Public endpoint to update the underlying timelock instance. Restricted to the timelock itself,
    /// so updates must be proposed, scheduled, and executed through governance proposals.
    /// @dev It is not recommended to change the timelock while there are other queued governance proposals.
    function updateTimelock(TimelockController newTimelock) external virtual onlyExecutor {
        _updateTimelock(newTimelock);
    }

    /// @notice Public endpoint to update the quorum. Restricted to the timelock, so updates must be proposed,
    /// scheduled, and executed through governance proposals.
    /// @dev It is not recommended to change the quorum while there are other queued governance proposals.
    function updateQuorum(uint256 newQuorum) external virtual onlyExecutor {
        _updateQuorum(newQuorum);
    }

    function _updateTimelock(TimelockController newTimelock) private {
        emit TimelockChange(address(_timelock), address(newTimelock));
        _timelock = newTimelock;
    }

    function _updateQuorum(uint256 newQuorum) private {
        emit QuorumChange(_quorum, newQuorum);
        _quorum = newQuorum;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       OVERRIDES                                                    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc GovernorSettings
    function setVotingDelay(uint256 newVotingDelay) public override onlyExecutor {
        _setVotingDelay(newVotingDelay);
    }

    /// @inheritdoc GovernorSettings
    function setVotingPeriod(uint256 newVotingPeriod) public override onlyExecutor {
        _setVotingPeriod(newVotingPeriod);
    }

    /// @inheritdoc GovernorSettings
    function setProposalThreshold(uint256 newProposalThreshold) public override onlyExecutor {
        _setProposalThreshold(newProposalThreshold);
    }

    /// @inheritdoc GovernorSettings
    function votingDelay() public view override(IGovernor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    /// @inheritdoc GovernorSettings
    function votingPeriod() public view override(IGovernor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    /// @inheritdoc GovernorSettings
    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold();
    }

    /// @inheritdoc GovernorVotes
    function clock() public view override(IGovernor, GovernorVotes) returns (uint48) {
        return SafeCast.toUint48(block.number);
    }
}
