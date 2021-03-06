const ether = 10 ** 18;
const ganache = require("ganache-cli");
require('./utils/revertTime');

module.exports = {
  networks: {
    ganache: {
      network_id: "*",
      provider: ganache.provider({
        accounts: [10 ** 100, 10 ** 100, 10 ** 100, 10 ** 100, 100 ** 100, 1].map(function (v) {
          return {balance: v * ether};
        }),
        mnemonic: "oceanico",
        time: new Date("2017-10-10T15:00:00Z"),
        debug: false
        // ,logger: console
      })
    },
    localhost: {
      host: "localhost",
      port: 8545,
      network_id: "*" // Match any network id
    }
  },
  solc: {
    optimizer: {
      enabled: true,
      runs: 200
    }
  },
  network: 'ganache',
};
