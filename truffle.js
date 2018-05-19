var HDWalletProvider = require("truffle-hdwallet-provider");
var infura_apikey = ""; //add api key
var mnemonic = "approve jump once scare cereal lens key aim silent limb twenty rose";

module.exports = {
  solc: {
    optimizer: {
      enabled: true,
      runs: 200
    }
  },
  networks: {
    development: {
      host: "localhost",
      port: 8545,
      gas: 4600000,
      gasPrice: 65000000000,
      network_id: "*" // Match any network id
    },
    "ropsten": {
      provider: function() {
        return new HDWalletProvider(mnemonic, "https://ropsten.infura.io/"+infura_apikey)
      },
      gas: 4700000,
      gasPrice: 65000000000,
      network_id: 3
    }
  }
}
