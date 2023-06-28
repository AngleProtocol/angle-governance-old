// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import { IGovernor } from "oz/governance/IGovernor.sol";
import { TimelockController } from "oz/governance/TimelockController.sol";

import { IVotes } from "oz/governance/utils/IVotes.sol";

import { Governor } from "./oz/Governor.sol";
import { GovernorCountingSimple } from "./oz/GovernorCountingSimple.sol";
import { GovernorSettings } from "./oz/GovernorSettings.sol";
import { GovernorVotes } from "./oz/GovernorVotes.sol";

/// @custom:security-contact contact@angle.money
contract AngleGovernor is Governor, GovernorSettings, GovernorCountingSimple, GovernorVotes {
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
                                                      CONSTRUCTOR                                                   
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    constructor(
        IVotes _token,
        TimelockController timelockAddress
    )
        Governor("AngleGovernor")
        GovernorSettings(1800 /* 6 hours */, 36000 /* 5 days */, 500000e18)
        GovernorVotes(_token)
    {
        _updateTimelock(timelockAddress);
        _updateQuorum(30000000e18);
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                    TIMELOCK LOGIC                                                  
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function _executor() internal view override(Governor) returns (address) {
        return address(_timelock);
    }

    function timelock() public view returns (address) {
        return address(_timelock);
    }

    /**
     * @dev Public endpoint to update the underlying timelock instance. Restricted to the timelock itself, so updates
     * must be proposed, scheduled, and executed through governance proposals.
     *
     * CAUTION: It is not recommended to change the timelock while there are other queued governance proposals.
     */
    function updateTimelock(TimelockController newTimelock) external virtual onlyGovernance {
        _updateTimelock(newTimelock);
    }

    function _updateTimelock(TimelockController newTimelock) private {
        emit TimelockChange(address(_timelock), address(newTimelock));
        _timelock = newTimelock;
    }

    /**
     * @dev Public endpoint to update the quorum. Restricted to the timelock, so updates
     * must be proposed, scheduled, and executed through governance proposals.
     *
     * CAUTION: It is not recommended to change the quorum while there are other queued governance proposals.
     */
    function updateQuorum(uint256 newQuorum) external virtual onlyGovernance {
        _updateQuorum(newQuorum);
    }

    function _updateQuorum(uint256 newQuorum) private {
        emit QuorumChange(_quorum, newQuorum);
        _quorum = newQuorum;
    }

    /**
     * @dev Will not be accurate if the quorum is changed will other proposals are running.
     */
    function quorum(uint256) public view override returns (uint256) {
        return _quorum;
    }

    /*//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
                                                       OVERRIDES                                                    
    //////////////////////////////////////////////////////////////////////////////////////////////////////////////////*/

    function votingDelay() public view override(IGovernor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    function votingPeriod() public view override(IGovernor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold();
    }
}
