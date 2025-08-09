require("ts-node/register");
require("@nomiclabs/hardhat-waffle");
require("dotenv").config();

/**
 * Environment variables required for deployment:
 *
 * Avalanche (C-Chain):
 * - PRIVATE_KEY: Deployer private key for Avalanche mainnet
 * - QI_TOKEN: BENQI qiToken address on Avalanche
 * - QI_CONTROLLER: BENQI controller contract address on Avalanche
 * - QI_REWARD_TOKEN: BENQI reward token address on Avalanche
 *
 * Fuji (testnet):
 * - FUJI_PRIVATE_KEY: Deployer private key for Avalanche Fuji testnet
 * - FUJI_QI_TOKEN: BENQI qiToken address on Fuji
 * - FUJI_QI_CONTROLLER: BENQI controller contract address on Fuji
 * - FUJI_QI_REWARD_TOKEN: BENQI reward token address on Fuji
 *
 * Optional:
 * - SLIPPAGE_BPS: Global swap slippage tolerance (basis points)
 */

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
const {
  PRIVATE_KEY,
  QI_TOKEN,
  QI_CONTROLLER,
  QI_REWARD_TOKEN,
  SLIPPAGE_BPS,
  FUJI_PRIVATE_KEY,
  FUJI_QI_TOKEN,
  FUJI_QI_CONTROLLER,
  FUJI_QI_REWARD_TOKEN,
} = process.env;

// BENQI contract addresses sourced from environment variables
const BENQI_ADDRESSES = {
  qiToken: QI_TOKEN || ZERO_ADDRESS,
  qiController: QI_CONTROLLER || ZERO_ADDRESS,
  rewardToken: QI_REWARD_TOKEN || ZERO_ADDRESS,
};

module.exports = {
  solidity: "0.8.20",
  networks: {
    hardhat: {
      slippageBps: Number(SLIPPAGE_BPS) || 50,
      allowUnlimitedContractSize: true,
    },
    avalanche: {
      url: "https://api.avax.network/ext/bc/C/rpc",
      accounts: PRIVATE_KEY ? [PRIVATE_KEY] : [],

      qiToken: QI_TOKEN || ZERO_ADDRESS,
      qiController: QI_CONTROLLER || ZERO_ADDRESS,
      rewardToken: QI_REWARD_TOKEN || ZERO_ADDRESS,
      slippageBps: Number(SLIPPAGE_BPS) || 50,

    },
    fuji: {
      url: "https://api.avax-test.network/ext/bc/C/rpc",
      accounts: FUJI_PRIVATE_KEY ? [FUJI_PRIVATE_KEY] : [],

      qiToken: FUJI_QI_TOKEN || ZERO_ADDRESS,
      qiController: FUJI_QI_CONTROLLER || ZERO_ADDRESS,
      rewardToken: FUJI_QI_REWARD_TOKEN || ZERO_ADDRESS,
      slippageBps: Number(SLIPPAGE_BPS) || 50,

    },
  },
  mocha: {
    require: ["ts-node/register"],
    extension: ["ts"],
    spec: "test/**/*.ts",
  },
};
