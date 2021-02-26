import pytest

from brownie import Wei, accounts, Contract, config
from brownie import StrategyAaveStaking


def test_revoke_strategy_from_vault(
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
):
    # Deposit to the vault and harvest
    # Funding and vault approvals
    # Can be also done from the conftest and remove dai_liquidity from here
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

    deposit_amount = aave.balanceOf(vault)

    # First harvest
    strategy.harvest({"from": gov})

    assert stake.balanceOf(strategy) > 0
    chain.sleep(3600 * 24 * 7)
    chain.mine(1)

    vault.revokeStrategy(strategy, {"from": gov})
    strategy.startCooldown({"from": gov})
    chain.sleep(3600*24*11)
    chain.mine(1)
    strategy.harvest({"from": gov})
    assert aave.balanceOf(vault) > deposit_amount

    pass
