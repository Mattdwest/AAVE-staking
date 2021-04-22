# Protocol Due Diligence: Aave

## Overview + Links
- **[Site](https://app.aave.com/staking)**
- **[Team](https://aave.com/)**
- **[Docs](https://github.com/aave/aave-protocol)**
- **[More Docs](https://docs.aave.com/portal/)**
- **[Audits and due diligence disclosures](https://aave.com/security)**

## Rug-ability
**Multi-sig:**
- uncertain

**Number of Multi-sig signers / threshold:**
- uncertain
    
**Upgradable Contracts:**
- Yes, but controlled by governance

**Decentralization:**
- Controlled via governance token, but team is centralized.



## Misc Risks

- Aave is a well known company in the DeFi space and is considered trustworthy
- Assets in the Staking module can be burned in case of a [shortfall event](https://docs.aave.com/aavenomics/safety-module#shortfall-events)

### Audit Reports / Key Findings

- [numerous](https://docs.aave.com/developers/security-and-audits)
- Also has a standing bug bounty program

# Path to Prod

## Strategy Details
- **Description:**
    - Strategy stakes the native AAVE token in the safety module to gain inflationary rewards
- **Strategy current APR:**
    - aboout 7.5%
- **Does Strategy delegate assets?:**
    - Unsure what this is asking.
- **Target Prod Vault:**
    - would require new yvAAVE vault
- **BaseStrategy Version #:**
    - 0.3.5
- **Target Prod Vault Version #:**
    - 0.3.5

## Testing Plan
### Ape.tax
- **Will Ape.tax be used?:**
    - if team deems it worthwhile
- **Will Ape.tax vault be same version # as prod vault?:**
    - yes, would likely become the official vault
- **What conditions are needed to graduate? (e.g. number of harvest cycles, min funds, etc):**
    - 3 harvests, disabling the strategy and unstaking from the module, and a second vault strategy (e.g. genlender) 

## Prod Deployment Plan
- **Suggested position in withdrawQueue?:**
    - the very end
- **Does strategy have any deposit/withdraw fees?:**
    - no withdrawal fees, just a timelock
- **Suggested debtRatio?:**
    - ~30%, depending on genlender ROI
- **Suggested max debtRatio to scale to?:**
    - would not recommend exceeding 70% due to withdrawal lock

## Emergency Plan
- **Shutdown Plan:**
    - call emergency shutdown, wait 10 days, harvest
- **Things to know:**
    - the withdrawal lock needs to be respected.
    - the withdrawal lock is a hybrid model.
        - deposits during an unstaking timelock will increase timelock proportionately
- **Scripts / steps needed:*
    - startCooldown()
    - emergency shutdown
    - wait 10 days
    - harvest
- **Is it safe to...**
    - call EmergencyShutdown
        - yes
    - remove from withdrawQueue
        - yes
    - call revoke and then harvest
        - Will revert due to timelock. startCooldown() needed before harvesting.
        - In emergency, can still migrate to a new strategy. stkAave is not locked to addresses.