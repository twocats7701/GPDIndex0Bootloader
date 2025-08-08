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

### Strategies
* **BenqiStrategy** – Supplies assets to BENQI lending markets and compounds QI rewards back into the underlying.
* **GPDIndex0LpStrategy** – Stakes GPDINDEX0 LP tokens in MasterChef style farms and auto‑compounds farm rewards.
* **BlackholeDexStrategy** – Deposits assets into Blackhole DEX pools and forwards claimed rewards to the vault.
* **SimpleStakingStrategy** – Lightweight strategy used for simulations and testing scenarios.
* **VaporDexStrategy** – Stakes LP tokens in VaporDex or compatible farms and compounds rewards back into the vault.

### Boosting & Gauges
* **GPDBoostVault** – Aggregates TWOCATS and GERZA stakes, routes them to strategies and distributes rewards boosted by vote‑escrow balances.
* **GPDGauge** – Gauge contract that attaches to Blackhole pools and distributes rewards proportional to ve voting power.

### Governance & Tokens
* **GPDINDEX0EmissionSchedule** – Stores emission constants and weighting multipliers for governance.
* **GPDINDEX0Token** – Governance token supporting time‑locked staking to obtain vote‑escrow power.
* **GPDVeToken** – Minimal vote‑escrow token with linear decay and non‑transferable voting power.

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


## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

