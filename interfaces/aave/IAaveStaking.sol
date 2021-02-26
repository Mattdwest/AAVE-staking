// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IAaveStaking {

    function stake(address, uint256) external;

    function redeem(address, uint256) external;

    function cooldown() external;

    function claimRewards(address, uint256) external;

    function getTotalRewardsBalance(address) external view returns (uint256);

    function COOLDOWN_SECONDS() external view returns (uint256);

    function stakersCooldowns(address) external view returns (uint256);
}
