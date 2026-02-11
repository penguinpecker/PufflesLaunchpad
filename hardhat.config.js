require('dotenv').config();
require('@nomicfoundation/hardhat-verify');

module.exports = {
  solidity: {
    version: '0.8.22',
    settings: {
      optimizer: { enabled: true, runs: 200 },
      viaIR: true,
    },
  },
  networks: {
    push_testnet: {
      url: 'https://evm.donut.rpc.push.org/',
      chainId: 42101,
      accounts: [process.env.PRIVATE_KEY],
    },
  },
  etherscan: {
    apiKey: { push_testnet: 'blockscout' },
    customChains: [{
      network: 'push_testnet',
      chainId: 42101,
      urls: {
        apiURL: 'https://donut.push.network/api',
        browserURL: 'https://donut.push.network/',
      },
    }],
  },
};
