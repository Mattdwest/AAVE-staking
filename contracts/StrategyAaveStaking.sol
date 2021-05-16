// SPDX-License-Identifier: MIT

pragma experimental ABIEncoderV2;
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {
    BaseStrategy
} from "@yearnvaults/contracts/BaseStrategy.sol";

import "../../interfaces/aave/IAaveStaking.sol";


interface IName {
    function name() external view returns (string memory);
}

contract StrategyAaveStaking is BaseStrategy{
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public stkAave;

    constructor(
        address _vault,
        address _stkAave
    ) public BaseStrategy(_vault) {
        stkAave = _stkAave;



        IERC20(want).safeApprove(stkAave, type(uint256).max);
    }

    // depositLock of 0 is disabled, 1 is enabled
    // if enabled, all harvests will revert. This stops deposits AND withdrawals.
    int8 public depositLock = 0;
    uint256 MIN_STAKE = 1e18;

    function name() external view override returns (string memory) {
        return
            string(
                abi.encodePacked("Aave Staking ", IName(address(want)).name())
            );
    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](1);
        // (aka want) is already protected by default
        protected[0] = stkAave;
        return protected;
    }

    // returns sum of all assets, realized and unrealized
    function estimatedTotalAssets() public view override returns (uint256) {
        return balanceOfWant().add(balanceOfPool());
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {

        // harvest() will track profit by estimated total assets compared to debt.
        uint256 balanceOfWantBefore = balanceOfWant();
        uint256 balanceOfWantAfter = balanceOfWantBefore;  //see below

        uint256 _rewards = pendingRewards();

        if (_rewards > 0) {
            claimReward(_rewards);
            // we only read balance again if rewards were claimed
           balanceOfWantAfter = balanceOfWant();
        }

        if (balanceOfWantAfter > balanceOfWantBefore) {
            _profit = balanceOfWantAfter.sub(balanceOfWantBefore);
        }

        // We might need to return want to the vault
        if (_debtOutstanding > 0) {
            uint256 _amountFreed = 0;
            (_amountFreed, _loss) = liquidatePosition(_debtOutstanding);
            _debtPayment = Math.min(_amountFreed, _debtOutstanding);

            if (_loss > 0) {
            _profit = 0;
            }
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        //emergency exit is dealt with in prepareReturn
        if (emergencyExit) {
            internalDepositLock(1);
            return;
        }

        if (depositLock == 1) {
            return;
        }


        // do not invest if we have more debt than want
        if (_debtOutstanding > balanceOfWant()) {
            return;
        }

        // Invest the rest of the want
        uint256 _wantAvailable = balanceOfWant().sub(_debtOutstanding);
        if (_wantAvailable > MIN_STAKE) {
            IAaveStaking(stkAave).stake(address(this), _wantAvailable);
        }
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {

        uint256 _balanceOfWant = balanceOfWant();

        if (_balanceOfWant < _amountNeeded) {
            // We need to withdraw to get back more want
            _withdrawSome(_amountNeeded.sub(_balanceOfWant));

            // read again in case of updates
            _balanceOfWant = balanceOfWant();
        }

        if (_balanceOfWant >= _amountNeeded) {
            _liquidatedAmount = _amountNeeded;
        } else {
            _liquidatedAmount = _balanceOfWant;
            _loss = (_amountNeeded.sub(_balanceOfWant));
        }
    }

    // withdraw some want from the vaults
    function _withdrawSome(uint256 _amount) internal returns (uint256) {
        uint256 balanceOfWantBefore = balanceOfWant();
        uint256 timeRemaining = cooldownRemaining();
        require(timeRemaining == 0, "!withdraw cooldown remaining");

        IAaveStaking(stkAave).redeem(address(this), _amount);

        uint256 balanceAfter = balanceOfWant();
        return balanceAfter.sub(balanceOfWantBefore);
    }

    // transfers all tokens to new strategy
    function prepareMigration(address _newStrategy) internal override {
        // want is transferred by the base contract's migrate function
        IERC20(stkAave).transfer(
            _newStrategy,
            IERC20(stkAave).balanceOf(address(this))
        );
    }

    // returns value of total staked aave
    function balanceOfPool() public view returns (uint256) {
        return IERC20(stkAave).balanceOf(address(this));
    }

    // returns balance of want token
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    // claims AAVE from faucet
    function claimReward(uint256 pending) internal {
        IAaveStaking(stkAave).claimRewards(address(this), pending);
    }

    function pendingRewards() internal returns (uint256) {
        return IAaveStaking(stkAave).getTotalRewardsBalance(address(this));
    }

    function startCooldown() external onlyAuthorized {
        IAaveStaking(stkAave).cooldown();
        internalDepositLock(1);
    }

    function cooldownRemaining() internal returns (uint256) {
        uint256 cooldown = IAaveStaking(stkAave).stakersCooldowns(address(this));
        uint256 cooldownSeconds = IAaveStaking(stkAave).COOLDOWN_SECONDS();
        uint256 unstakeSeconds = IAaveStaking(stkAave).UNSTAKE_WINDOW();
        //verify that withdraw window hasn't expired
        require(block.timestamp < cooldown.add(cooldownSeconds).add(unstakeSeconds), "!window expired");
        if (block.timestamp > cooldown.add(cooldownSeconds)) {
            return 0;
        } else {
            uint256 _block = block.timestamp;
            return _block.add(cooldownSeconds).sub(cooldown);}
    }

    // cloning cooldownRemaining but as a public view
    function viewCooldown() public view returns (uint256) {
        uint256 cooldown = IAaveStaking(stkAave).stakersCooldowns(address(this));
        uint256 cooldownSeconds = IAaveStaking(stkAave).COOLDOWN_SECONDS();
        uint256 unstakeSeconds = IAaveStaking(stkAave).UNSTAKE_WINDOW();
        //verify that withdraw window hasn't expired
        require(block.timestamp < cooldown.add(cooldownSeconds).add(unstakeSeconds), "!window expired");
        if (block.timestamp > cooldown.add(cooldownSeconds)) {
            return 0;
        } else {
            uint256 _block = block.timestamp;
            return _block.add(cooldownSeconds).sub(cooldown);}
    }

    // depositLock needs to be zero to deposit OR harvest()
    // if it is set to 1, all harvests() will break
    function setDepositLock(int8 newLock) external onlyAuthorized {
        depositLock = newLock;
    }

    function internalDepositLock(int8 newLock) internal {
        depositLock = newLock;
    }

    function viewDepositLock() public view returns (int8){
        return depositLock;
    }

    function setMinStake(uint256 newMin) external onlyAuthorized {
        MIN_STAKE = newMin;
    }

    function manualClaim() external onlyKeepers {
        uint256 pending = pendingRewards();
        IAaveStaking(stkAave).claimRewards(address(this), pending);
    }

    function setDelegate(address delegatee) external onlyAuthorized {
        IAaveStaking(stkAave).delegate(delegatee);
    }
}
