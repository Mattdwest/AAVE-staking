# TODO: Add tests here that show the normal operation of this strategy
#       Suggestions to include:
#           - strategy loading and unloading (via Vault addStrategy/revokeStrategy)
#           - change in loading (from low to high and high to low)
#           - strategy operation at different loading levels (anticipated and "extreme")

import pytest

from brownie import Wei, accounts, Contract, config
from brownie import StrategyAaveStaking


@pytest.mark.require_network("mainnet-fork")
def test_operation(
    chain,
    vault,
    strategy,
    aave,
    stake,
    aave_liquidity,
    gov,
    rewards,
    guardian,
    strategist,
    alice,
    bob,
    tinytim,
    newstrategy,
):

    aave.approve(aave_liquidity, Wei("1000000 ether"), {"from": aave_liquidity})
    aave.transferFrom(aave_liquidity, gov, Wei("3000 ether"), {"from": aave_liquidity})
    aave.approve(gov, Wei("1000000 ether"), {"from": gov})
    aave.transferFrom(gov, bob, Wei("100 ether"), {"from": gov})
    aave.transferFrom(gov, alice, Wei("400 ether"), {"from": gov})
    aave.transferFrom(gov, tinytim, Wei("1 ether"), {"from": gov})
    aave.approve(vault, Wei("1000000 ether"), {"from": bob})
    aave.approve(vault, Wei("1000000 ether"), {"from": alice})
    aave.approve(vault, Wei("1000000 ether"), {"from": tinytim})

    # users deposit to vault
    vault.deposit(Wei("100 ether"), {"from": bob})
    vault.deposit(Wei("400 ether"), {"from": alice})
    vault.deposit(Wei("1 ether"), {"from": tinytim})

    # first harvest
    chain.mine(1)
    strategy.harvest({"from": gov})

    # one week passes & profit is generated
    assert stake.balanceOf(strategy) > 0
    chain.sleep(3600 * 24 * 7)
    chain.mine(1)
    strategy.harvest({"from": gov})
    chain.mine(1)

    # 6 hours for pricepershare to go up
    chain.sleep(3600 * 6)
    chain.mine(1)

    newstrategy.setStrategist(strategist)
    vault.migrateStrategy(strategy, newstrategy, {"from": gov})

    assert stake.balanceOf(strategy) == 0
    assert stake.balanceOf(newstrategy) > 0

    pass
