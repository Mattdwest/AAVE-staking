// SPDX-License-Identifier: MIT

pragma experimental ABIEncoderV2;
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {
    BaseStrategyInitializable
} from "@yearnvaults/contracts/BaseStrategy.sol";

import "../../interfaces/aave/IAaveStaking.sol";


interface IName {
    function name() external view returns (string memory);
}

contract StrategyAaveStaking is BaseStrategyInitializable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public stkAave;

    constructor(address _vault) public BaseStrategyInitializable(_vault) {}

    function _initialize(
        address _stkAave
    ) internal {
        stkAave = _stkAave;

        IERC20(want).safeApprove(stkAave, uint256(-1));
    }

    function initializeParent(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper
    ) public {
        super._initialize(_vault, _strategist, _rewards, _keeper);
    }

    function initialize(
        address _stkAave
    ) external {
        _initialize(
            _stkAave
        );
    }

    function clone(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper,
        address _stkAave
    ) external returns (address newStrategy) {
        // Copied from https://github.com/optionality/clone-factory/blob/master/contracts/CloneFactory.sol
        bytes20 addressBytes = bytes20(address(this));

        assembly {
            // EIP-1167 bytecode
            let clone_code := mload(0x40)
            mstore(
                clone_code,
                0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000
            )
            mstore(add(clone_code, 0x14), addressBytes)
            mstore(
                add(clone_code, 0x28),
                0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000
            )
            newStrategy := create(0, clone_code, 0x37)
        }

        StrategyAaveStaking(newStrategy).initializeParent(
            _vault,
            _strategist,
            _rewards,
            _keeper
        );
        StrategyAaveStaking(newStrategy).initialize(
            _stkAave
        );
    }

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
        // We might need to return want to the vault
        if (_debtOutstanding > 0) {
            uint256 _amountFreed = 0;
            (_amountFreed, _loss) = liquidatePosition(_debtOutstanding);
            _debtPayment = Math.min(_amountFreed, _debtOutstanding);
        }

        // harvest() will track profit by estimated total assets compared to debt.
        uint256 balanceOfWantBefore = balanceOfWant();

        uint256 rewards = pendingRewards();

        if (rewards > 0) {
            claimReward();
        }

        uint256 balanceOfWantAfter = balanceOfWant();

        if (balanceOfWantAfter > balanceOfWantBefore) {
            _profit = balanceOfWantAfter.sub(balanceOfWantBefore);
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        //emergency exit is dealt with in prepareReturn
        if (emergencyExit) {
            return;
        }

        // do not invest if we have more debt than want
        if (_debtOutstanding > balanceOfWant()) {
            return;
        }

        // Invest the rest of the want
        uint256 _wantAvailable = balanceOfWant().sub(_debtOutstanding);
        if (_wantAvailable > 0) {
            IAaveStaking(stkAave).stake(address(this), _wantAvailable);
        }
    }

    //v0.3.0 - liquidatePosition is emergency exit. Supplants exitPosition
    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        if (balanceOfWant() < _amountNeeded) {
            // We need to withdraw to get back more want
            _withdrawSome(_amountNeeded.sub(balanceOfWant()));
        }

        uint256 balanceOfWant = balanceOfWant();

        if (balanceOfWant >= _amountNeeded) {
            _liquidatedAmount = _amountNeeded;
        } else {
            _liquidatedAmount = balanceOfWant;
            _loss = (_amountNeeded.sub(balanceOfWant));
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

    // claims POOL from faucet
    function claimReward() internal {
        uint256 pending = pendingRewards();
        IAaveStaking(stkAave).claimRewards(address(this), pending);
    }

    function pendingRewards() internal returns (uint256) {
        return IAaveStaking(stkAave).getTotalRewardsBalance(address(this));
    }

    function startCooldown() external onlyKeepers {
        IAaveStaking(stkAave).cooldown();
    }

    function cooldownRemaining() internal returns (uint256) {
        uint256 cooldown = IAaveStaking(stkAave).stakersCooldowns(address(this));
        uint256 cooldownSeconds = IAaveStaking(stkAave).COOLDOWN_SECONDS();
        if (block.timestamp > cooldown.add(cooldownSeconds)) {
            return 0;
        } else {
            uint256 _block = block.timestamp;
            return _block.sub(cooldown).sub(cooldownSeconds);}
    }

}
