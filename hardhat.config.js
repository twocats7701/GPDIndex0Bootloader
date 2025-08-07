require("@nomiclabs/hardhat-waffle");

module.exports = {
  solidity: "0.8.20",
  networks: {
    hardhat: {},
    avalanche: {
      url: "https://api.avax.network/ext/bc/C/rpc",
      accounts: ["<YOUR_PRIVATE_KEY>"]
    }
  }
};
