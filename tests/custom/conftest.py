import pytest
from brownie import config, Contract


@pytest.fixture(scope="function", autouse=True)
def shared_setup(fn_isolation):
    pass

@pytest.fixture
def gov(accounts):
    yield accounts[0]


@pytest.fixture
def rewards(accounts):
    yield accounts[1]


@pytest.fixture
def guardian(accounts):
    yield accounts[2]


@pytest.fixture
def management(accounts):
    yield accounts[3]


@pytest.fixture
def strategist(accounts):
    yield accounts[4]


@pytest.fixture
def keeper(accounts):
    yield accounts[5]


@pytest.fixture
def alice(accounts):
    yield accounts[6]


@pytest.fixture
def bob(accounts):
    yield accounts[7]


@pytest.fixture
def tinytim(accounts):
    yield accounts[8]


@pytest.fixture
def aave_liquidity(accounts):
    yield accounts.at("0xbe0eb53f46cd790cd13851d5eff43d12404d33e8", force=True)


@pytest.fixture
def aave():
    token_address = "0x7fc66500c84a76ad7e9c93437bfc5ac33e2ddae9"
    proxy = "0xC13eac3B4F9EED480045113B7af00F7B5655Ece8"
    yield Contract.from_explorer(token_address,as_proxy_for=proxy)

@pytest.fixture
def stake():
    token_address = "0x4da27a545c0c5b758a6ba100e3a049001de870f5"
    proxy = "0xc0d503b341868a6f6b6e21e0780aa57fdbbca53a"
    yield Contract.from_explorer(token_address,as_proxy_for=proxy)

@pytest.fixture
def vault(pm, gov, rewards, guardian, management, aave):
    Vault = pm(config["dependencies"][0]).Vault
    vault = guardian.deploy(Vault)
    vault.initialize(aave, gov, rewards, "", "", guardian)
    vault.setDepositLimit(2 ** 256 - 1, {"from": gov})
    vault.setManagement(management, {"from": gov})
    yield vault


@pytest.fixture
def strategy(
    strategist,
    guardian,
    keeper,
    vault,
    StrategyAaveStaking,
    gov,
    stake,
):
    strategy = guardian.deploy(StrategyAaveStaking, vault, stake)
    strategy.setKeeper(keeper)
    vault.addStrategy(strategy, 10_000, 0, 2 ** 256 - 1, 1_000, {"from": gov})
    yield strategy

@pytest.fixture
def newstrategy(
    strategist,
    guardian,
    keeper,
    vault,
    StrategyAaveStaking,
    gov,
    stake,
):
    newstrategy = guardian.deploy(StrategyAaveStaking, vault, stake)
    newstrategy.setKeeper(keeper)
    yield newstrategy