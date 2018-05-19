var SafeMath = artifacts.require('./SafeMath.sol');
var BLS = artifacts.require('./BLS.sol');
var BitLumensCrowdsale = artifacts.require('./BitLumensCrowdsale.sol');
const moment = require('moment');

    module.exports = function(deployer, network, accounts) {
  if (network == 'development') {
    // Wallet
    var wallet = accounts[1];

    var dat = moment.utc('2018-05-20 12:00').toDate().getTime() / 1000;
    //var initialDelay = web3.eth.getBlock(web3.eth.blockNumber).timestamp; //+ (60 * 1);
    var startTime = dat;
    //console.log(startTime);
    //var startTime = initialDelay; // ICO starting 1 hour after the initial deployment
    var roundTwoTime=startTime + (300 * 1);
    var roundThreeTime=roundTwoTime + (300 * 1);
    var roundFourTime=roundThreeTime + (300 * 1);
    var roundFiveTime=roundFourTime + (300 * 1);
    var endTime = roundFiveTime + (300 * 1); // ICO end
    //kyc signers
    // divide caps by 100 for the sake of testing
    var ETHUSDEXCHANGE = 1000 * 100;
    var BLS_PRE_ICO =   100000 * 1000000000000000000;
    var BLS_TOTAL_CAP = 250000 * 1000000000000000000;
    var USD_SOFT_CAP = 1 * 10000;
    var USD_HARD_CAP = 25 * 10000;
    var kycSigners = [accounts[2], accounts[3]];

  }

  else if (network == 'ropsten') {

    // Wallet
    var wallet = accounts[1];

    var dat = moment.utc('2018-05-20 12:00').toDate().getTime() / 1000;
    //var initialDelay = web3.eth.getBlock(web3.eth.blockNumber).timestamp; //+ (60 * 1);
    var startTime = dat;
    //console.log(startTime);
    //var startTime = initialDelay; // ICO starting 1 hour after the initial deployment
    var roundTwoTime=startTime + (3600 * 1);
    var roundThreeTime=roundTwoTime + (3600 * 1);
    var roundFourTime=roundThreeTime + (3600 * 1);
    var roundFiveTime=roundFourTime + (3600 * 1);
    var endTime = roundFiveTime + (3600 * 1); // ICO end
    //kyc signers

    // divide caps by 100 for the sake of testing
    var ETHUSDEXCHANGE = 1000 * 100;
    var BLS_PRE_ICO =   100000 * 1000000000000000000;
    var BLS_TOTAL_CAP = 250000 * 1000000000000000000;
    var USD_SOFT_CAP = 1 * 10000;
    var USD_HARD_CAP = 25 * 10000;
    var kycSigners = ["0x353BEA5712f54f4bb1B477cC054f918eaE602F08","0x831B3A08c44Ffe48C6E5e601ef4fb92405efdE79"] ;
  }
  else if (network == 'mainnet') {}


  deployer.deploy(SafeMath);
  deployer.link(SafeMath, BitLumensCrowdsale);
  deployer.deploy(BitLumensCrowdsale,
    kycSigners,
    BLS.address,
    wallet,
    startTime,
    roundTwoTime,
    roundThreeTime,
    roundFourTime,
    roundFiveTime,
    endTime,
    BLS_PRE_ICO,
    BLS_TOTAL_CAP,
    USD_SOFT_CAP,
    USD_HARD_CAP,
    ETHUSDEXCHANGE,
    {from:wallet, value:200000000000000000}
  );
};
