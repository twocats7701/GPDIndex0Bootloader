# GPD Index 0 Bootloader & Yield System

This repository contains a Hardhat project that bootstraps the **GPD Index 0** ecosystem and implements a suite of yield vaults, strategies and governance contracts.

## Major Contracts

### GPDIndex0Bootloader
* Orchestrates the initial bootstrap of TWOCATS and GERZA liquidity.
* Manages emission schedule, bonding curve purchases and router interactions.
* Enables governance once the initial epoch completes.

### GPDYieldVault0
* ERC4626 compliant vault used for user deposits.
* Applies withdrawal fees that decay over four weeks and harvests strategy rewards with a 5% performance fee.
* Optional `autoCompoundEnabled` flag runs `compound` after every deposit or withdrawal.

### Strategies
* **BenqiStrategy** – Supplies assets to BENQI lending markets and compounds QI rewards back into the underlying.
* **GPDIndex0LpStrategy** – Stakes GPDINDEX0 LP tokens in MasterChef style farms and auto‑compounds farm rewards.
* **BlackholeDexStrategy** – Deposits assets into Blackhole DEX pools and forwards claimed rewards to the vault.
* **SimpleStakingStrategy** – Lightweight strategy used for simulations and testing scenarios.
* **VaporDexStrategy** – Stakes LP tokens in VaporDex or compatible farms and compounds rewards back into the vault.
* **AaveV3Strategy** – Supplies assets to Aave v3 lending pools, harvests protocol incentives and can optionally leverage positions using flash loans.

### Boosting & Gauges
* **GPDBoostVault** – Aggregates TWOCATS and GERZA stakes, routes them to strategies and distributes rewards boosted by vote‑escrow balances. When `autoCompoundEnabled` is true the vault harvests rewards after each deposit or withdrawal.
* **GPDGauge** – Gauge contract that attaches to Blackhole pools and distributes rewards proportional to ve voting power.

### Governance & Tokens
* **GPDIndex0EmissionSchedule** – Stores emission constants and weighting multipliers for governance.
* **GPDIndex0Token** – Governance token supporting time‑locked staking to obtain vote‑escrow power.
* **GPDVeToken** – Minimal vote‑escrow token with linear decay and non‑transferable voting power.

### Keeper System
* **KeeperSlasher** – Registers keepers and lets governance ban misbehaving actors.
* **TipVault** – Pays registered keepers a configurable token tip with cooldown enforcement.
* **RewardEscrow** – Escrows reward tokens with timelocked vesting schedules.
* **DAOTreasury** – Holds DAO funds and allows operators to fund TipVault and RewardEscrow.


## Environment & Setup

1. Install dependencies
   ```bash
   npm install
   ```
2. Create `.env` with deployment parameters:
   ```dotenv
   # Avalanche mainnet
   PRIVATE_KEY=0x...
   QI_TOKEN=0x5C0401e81Bc07Ca70fAD469b451682c0d747Ef1c
   QI_CONTROLLER=0x486Af39519B4Dc9A7fCcD318217352830E8AD9b4
   QI_REWARD_TOKEN=0x8729438Eb15e2C8B576fCc6AEcDA6A14877668bF

   # Fuji testnet
   FUJI_PRIVATE_KEY=0x...
   FUJI_QI_TOKEN=0x...
   FUJI_QI_CONTROLLER=0x...
   FUJI_QI_REWARD_TOKEN=0x...

   # optional
   SLIPPAGE_BPS=50
   ```
   * **Avalanche** – `PRIVATE_KEY`, `QI_TOKEN`, `QI_CONTROLLER`, `QI_REWARD_TOKEN`
   * **Fuji** – `FUJI_PRIVATE_KEY`, `FUJI_QI_TOKEN`, `FUJI_QI_CONTROLLER`, `FUJI_QI_REWARD_TOKEN`
   * `SLIPPAGE_BPS` – optional global swap slippage tolerance (basis points).

### Per-call Slippage Override

Each strategy function `deposit`, `withdraw`, and `harvest` accepts an optional
`slippageBpsOverride` value. Supply `0` to use the global `slippageBps`
configured above, or provide a non-zero basis-point value for that specific
call. When invoking the overloaded `deposit` or `withdraw` from tests or
scripts, you may need to specify the full function signature, e.g.:

```ts
await strategy["deposit(uint256,uint256)"](amount, 100); // 1% slippage
await strategy.harvest(200); // 2% slippage
```

## Network Configuration

Hardhat is pre‑configured for the Avalanche C‑Chain and Fuji testnet in `hardhat.config.js`:

```js
avalanche: {
  url: "https://api.avax.network/ext/bc/C/rpc",
  accounts: [PRIVATE_KEY],
  qiToken: QI_TOKEN,
  qiController: QI_CONTROLLER,
  rewardToken: QI_REWARD_TOKEN,
  slippageBps: Number(SLIPPAGE_BPS) || 50,
},
fuji: {
  url: "https://api.avax-test.network/ext/bc/C/rpc",
  accounts: [FUJI_PRIVATE_KEY],
  qiToken: FUJI_QI_TOKEN,
  qiController: FUJI_QI_CONTROLLER,
  rewardToken: FUJI_QI_REWARD_TOKEN,
  slippageBps: Number(SLIPPAGE_BPS) || 50,
},
```

Additional EVM chains (Ethereum, BSC, etc.) can be added in the same manner by providing an RPC URL, deployer key and any strategy specific addresses.

## Deployment

Update placeholder addresses in `scripts/deploy.js` for the target network and run:

```bash
npx hardhat compile
npx hardhat run scripts/deploy.js --network avalanche
```

Replace `avalanche` with the desired network name defined in your Hardhat configuration.

## VaporDexStrategy Vault

### Example Configuration

```dotenv
# example addresses
FARM_ADDRESS=0x1111111111111111111111111111111111111111
PID=0
ROUTER_ADDRESS=0x2222222222222222222222222222222222222222
```

### Deploying a Vault

1. Import `VaporDexStrategy` and configure the farm, pool id and router in `scripts/deploy.js`.
2. Deploy the vault and strategy:
   ```bash
   npx hardhat run scripts/deploy.js --network avalanche
   ```
3. After deployment, call `setStrategy` on the vault with the deployed strategy address.

### Adding/Removing Liquidity and Claiming Rewards

1. Use the router to add liquidity for the target token pair and receive LP tokens.
2. Approve the vault to transfer your LP tokens and call `deposit` to add liquidity.
3. To exit, call `withdraw` to retrieve LP tokens and then `removeLiquidity` on the router.
4. Vault owners can trigger `compound` to harvest farm rewards and reinvest them; claimed rewards accrue to vault depositors.

### Pangolin Compatibility

`VaporDexStrategy` relies on MasterChef and router interfaces shared by Pangolin. Supplying Pangolin farm and router addresses allows
the same deployment and liquidity flow on Pangolin without modification.

## AaveV3Strategy Setup

The `AaveV3Strategy` supplies assets to Aave v3 and can optionally perform a flash‑loan loop to increase exposure.

```dotenv
# example addresses
AAVE_POOL=0x1111111111111111111111111111111111111111
AAVE_REWARDS_CONTROLLER=0x2222222222222222222222222222222222222222
AAVE_REWARD_TOKEN=0x3333333333333333333333333333333333333333
AAVE_ROUTER=0x4444444444444444444444444444444444444444
```

Flash loans use `flashLoanSimple` and incur a premium (Aave mainnet is typically 9 bps). The included `FlashLoanExecutor` supplies the borrowed
funds, borrows the same asset and returns it to the pool within the transaction.

**Risk Warning:** Leveraged positions amplify gains and losses. Sudden rate changes, collateral shortfalls or unavailable flash‑loan liquidity
may cause leverage attempts to revert. Always monitor health factors and ensure adequate collateral buffers before enabling the leverage loop.

## Testing

Compile and run the test suite:

```bash
npx hardhat test
```

## Additional Notes

The deployment script currently deploys:
* `GPDIndex0Bootloader`
* Two `GPDYieldVault0` instances with `GPDIndex0LpStrategy`
* A BENQI vault using `BenqiStrategy`



## Vapor Dex LP Strategy

`VaporDexStrategy` stakes LP tokens in a Vapor Dex farm and compounds rewards back into the LP token. The contract accepts the farm's `pid`, reward token, and router addresses on deployment, making it compatible with other Uniswap V2 style DEXs such as Pangolin.

=======
Modify the script with real token, LP, farm and router addresses before production use.
=======

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Keeper Deployment & Governance

The keeper system consists of `KeeperSlasher`, `TipVault`, `RewardEscrow` and `DAOTreasury`.
Deployment parameters:

* `tipToken` – ERC20 token paid to keepers.
* `tipAmount` – amount of `tipToken` distributed per upkeep.
* `tipCooldown` – minimum seconds between claims by the same keeper.
* `rewardToken` – token held by `RewardEscrow` for vesting.

Governance controls:

* DAO updates operators on `DAOTreasury` which can fund `TipVault` and `RewardEscrow`.
* Keepers are registered or banned via `KeeperSlasher`.
* Vault maintenance functions (`compound`/`harvest`) are restricted to registered keepers and automatically trigger tip payouts.

Use `scripts/migrate-keeper-system.js` to deploy the keeper contracts and wire them to existing vaults.

## Blackhole Bribe Integration

The Blackhole bribe flow lets external protocols signal APR to gauge depositors.

**Contracts**

* `BlackholeBribeManager` – holds pending bribes and lets strategies harvest them.
* `GPDGauge` – now accepts bribe tokens via `notifyBribe` and distributes them alongside pool rewards.

**Environment Variables**

```dotenv
BRIBE_MANAGER=0x...    # deployed BlackholeBribeManager
BRIBE_TOKEN=0x...      # token used for bribe payments
```

**Keeper/Governance Duties**

* Governance sets the `bribeManager` on each strategy and approves bribe tokens on gauges.
* Keepers call `harvest`/`compound` so vaults claim pool rewards and outstanding bribes.

**APR Signaling Workflow**

1. Governance or partners deposit bribe tokens into `BlackholeBribeManager`.
2. The manager forwards tokens to the appropriate `GPDGauge` using `notifyBribe`.
3. Depositors claim pool rewards and bribes through the gauge's `claim` function.
4. Harvesters relay claimed bribes back into the vault, boosting effective APR.

## Yield Optimization Guide

### Auto‑Compounding, Rebalancing & Emergency Withdraw

Vaults can be configured to auto‑compound rewards after each deposit or withdrawal, letting depositors benefit from continuous reinvestment without manual harvest calls. Strategies expose `rebalance` functions that shift capital between platforms when relative yields change, and all vaults support an `emergencyWithdraw` escape hatch that returns underlying assets without harvesting when markets become unstable.

### Platypus & Aave V3 Integrations

Example strategies for Platypus and Aave V3 can be deployed to diversify yield sources. Platypus pools supply high‑liquidity swaps, while the Aave V3 strategy may optionally draw a flash loan to open a leveraged deposit position before instantly repaying the loan. Flash‑loan hooks enable capital efficient loops without upfront liquidity.

### Risk Tiers & Keeper Settings

Strategies are grouped into three risk tiers:

* **Conservative** – battle‑tested platforms such as Aave; recommended keeper interval: ~1 hour.
* **Moderate** – DEX LP farms like Platypus; keeper interval: ~30 minutes.
* **Aggressive** – experimental farms or leveraged positions; keeper interval: 5–15 minutes.

Tune keeper intervals based on on‑chain gas prices and the vault’s reward emission schedule. Always monitor strategy health and pause vaults via `emergencyWithdraw` if anomalies are detected.

