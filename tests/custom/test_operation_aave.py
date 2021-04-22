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
):

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

    # First harvest
    strategy.harvest({"from": gov})

    assert stake.balanceOf(strategy) > 0
    chain.sleep(3600 * 24 * 28)
    chain.mine(1)
    pps_after_first_harvest = vault.pricePerShare()

    # 6 hours for pricepershare to go up, there should be profit
    strategy.harvest({"from": gov})
    chain.sleep(3600 * 6)
    chain.mine(1)
    pps_after_second_harvest = vault.pricePerShare()
    assert pps_after_second_harvest > pps_after_first_harvest

    # 6 hours for pricepershare to go up
    strategy.harvest({"from": gov})
    chain.sleep(3600 * 6)
    chain.mine(1)

    strategy.startCooldown({"from": gov})
    chain.sleep(3600*24*11)
    chain.mine(1)

    alice_vault_balance = vault.balanceOf(alice)
    vault.withdraw(alice_vault_balance, alice, 75, {"from": alice})
    assert aave.balanceOf(alice) > 0
    assert aave.balanceOf(bob) == 0
    assert stake.balanceOf(strategy) > 0

    bob_vault_balance = vault.balanceOf(bob)
    vault.withdraw(bob_vault_balance, bob, 75, {"from": bob})
    assert aave.balanceOf(bob) > 0
    assert aave.balanceOf(strategy) == 0

    tt_vault_balance = vault.balanceOf(tinytim)
    vault.withdraw(tt_vault_balance, tinytim, 75, {"from": tinytim})
    assert aave.balanceOf(tinytim) > 0
    assert aave.balanceOf(strategy) == 0

    # We should have made profit
    assert vault.pricePerShare() > 1e18
