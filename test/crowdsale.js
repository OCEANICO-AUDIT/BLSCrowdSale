
const chai = require("chai");
const chaiAsPromised = require("chai-as-promised");
chai.use(chaiAsPromised);
chai.use(require('chai-bignumber')(web3.BigNumber));
chai.should();
const {timeTo, increaseTime, revert, snapshot, mine} = require('./evmMethods');
const {web3async, estimateConstructGas} = require('./web3Utils');


const BitLumensCrowdsale = artifacts.require('./BitLumensCrowdsale.sol');
const BLS = artifacts.require('./BLS.sol');


const DECIMALS_MULTIPLIER = 10 ** 18;
const DAY = 24 * 3600;

let NOW, TOMORROW, DAY_AFTER_TOMORROW;

const initTime = (now) => {
  NOW = now;
  TOMORROW = now + DAY;
  DAY_AFTER_TOMORROW = TOMORROW + DAY;
};

const _ = require('lodash')
const {
  ecsign
} = require('ethereumjs-util')
const abi = require('ethereumjs-abi')
const BN = require('bn.js')
const MAX_AMOUNT = '150000000000000000000' // 50 ether

const getKycData = (userAddr, userid, icoAddr, pk) => {
  const hash = abi.soliditySHA256(
    ['string', 'address', 'address', 'uint64', 'uint'], ['Eidoo icoengine authorization', icoAddr, userAddr, new BN(userid), new BN(MAX_AMOUNT)]
  )
  const sig = ecsign(hash, pk)
  return {
    id: userid,
    max: MAX_AMOUNT,
    v: sig.v,
    r: '0x' + sig.r.toString('hex'),
    s: '0x' + sig.s.toString('hex')
  }
}
const SIGNER_ADDR = '0x627306090abaB3A6e1400e9345bC60c78a8BEf57'.toLowerCase()
const SIGNER_PK = Buffer.from('c87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3', 'hex')
const OTHER_PK = Buffer.from('0dbbe8e4ae425a6d2687f1a7e3ba17bc98c673636790f1b8ad91193c05875ef1', 'hex')
const BITLUMENSACCOUNT = '0xa9e295a6fc80d93be8fb54d946212228b0377ea8'.toLowerCase();
const TEAMACCOUNT = '0xe3868fd3e3af480a8af08ca3d5c06cdd136c2e14'.toLowerCase();
const BOUNTYACCOUNT = '0x27875879e1ec293ea578bf695856c735642288ad'.toLowerCase();

contract('BitLumensCrowdsale', accounts => {
  const startTime = new Date("2018-05-28T00:00:00-05:00").getTime() / 1000;
  const endTime = new Date("2018-06-28T00:00:00-05:00").getTime() / 1000;
  const roundTwoTime = new Date("2018-06-01T00:00:00-05:00").getTime() / 1000;
  const roundThreeTime = new Date("2018-06-02T00:00:00-05:00").getTime() / 1000;
  const roundFourTime = new Date("2018-06-08T00:00:00-05:00").getTime() / 1000;
  const roundFiveTime = new Date("2018-06-14T00:00:00-05:00").getTime() / 1000;
  const afterEndTime = new Date("2018-06-30T00:00:00-05:00").getTime() / 1000;
  const kycSigners = [accounts[2], accounts[3]];

  const ETHUSDEXCHANGE = 1000 * 100;
  const BLS_PRE_ICO =   100000 * 1000000000000000000;
  const BLS_TOTAL_CAP = 250000 * 1000000000000000000;
  const USD_SOFT_CAP = 10 * 1000;
  const USD_HARD_CAP = 250 * 1000;

  const wallet = accounts[1];
  const buyer1 = accounts[4];

  const createCrowdsale = async () => {
      const BLSToken = await BLS.new();
      const BLSCrowdsale = await BitLumensCrowdsale.new(
          [SIGNER_ADDR],
          BLSToken.address,
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
          {from: accounts[0], value: web3.toWei(3, 'ether')}
      );
      await BLSToken.transferOwnership(BLSCrowdsale.address);
      return BLSCrowdsale;
  };

  const getBlockchainTimestamp = async () => {
    const latestBlock = await web3async(web3.eth, web3.eth.getBlock, 'latest');
    return latestBlock.timestamp;
  };

  let snapshotId;

  beforeEach(async () => {
    snapshotId = (await snapshot()).result;
    initTime(await getBlockchainTimestamp());
  });

  afterEach(async () => {
    await revert(snapshotId);
  });

  describe('Initial tests:', async () => {
      it('should create crowdsale with correct parameters', async () => {
          const crowdsale = await createCrowdsale();
          await crowdsale.token().should.eventually.have.length(42);
          
          const ICOstartTime = await crowdsale.startTime();
          const ICOendTime = await crowdsale.endTime();
          const ICOroundTwoTime = await crowdsale.roundTwoTime();
          const ICOroundThreeTime = await crowdsale.roundThreeTime();
          const ICOroundFourTime = await crowdsale.roundFourTime();
          const ICOroundFiveTime = await crowdsale.roundFiveTime();
          const ICOblsPreIco = await crowdsale.BLS_PRE_ICO();
          const ICOblsTotalCap = await crowdsale.BLS_TOTAL_CAP();
          const ICOusdSofCap = await crowdsale.USD_SOFT_CAP();
          const ICOusdHardCap = await crowdsale.USD_HARD_CAP();
          const ICOexchangeRate = await crowdsale.ETH_USD_EXCHANGE_CENTS();
          const ICOwalletAddress = await crowdsale.wallet();

          ICOstartTime.should.be.bignumber.equal(startTime);
          ICOendTime.should.be.bignumber.equal(endTime);
          ICOroundTwoTime.should.be.bignumber.equal(roundTwoTime);
          ICOroundThreeTime.should.be.bignumber.equal(roundThreeTime);
          ICOroundFourTime.should.be.bignumber.equal(roundFourTime);
          ICOroundFiveTime.should.be.bignumber.equal(roundFiveTime);
          ICOblsPreIco.should.be.bignumber.equal(BLS_PRE_ICO);
          ICOblsTotalCap.should.be.bignumber.equal(BLS_TOTAL_CAP);
          ICOusdSofCap.should.be.bignumber.equal(USD_SOFT_CAP);
          ICOusdHardCap.should.be.bignumber.equal(USD_HARD_CAP);
          ICOexchangeRate.should.be.bignumber.equal(ETHUSDEXCHANGE);
          ICOwalletAddress.should.be.equal(wallet);

      });

      it('should be token owner', async () => {
          const crowdsale = await createCrowdsale();
          const token = BLS.at(await crowdsale.token());
          const owner = await token.owner();
          owner.should.equal(await crowdsale.address);
      });

      it('should fail the default callback', async () => {
          const crowdsale = await createCrowdsale();
          await crowdsale.sendTransaction({from: buyer1, value: web3.toWei(1, 'ether')})
          .should.eventually.be.rejected
      });

      it('should be ended only after end', async () => {
          const crowdsale = await createCrowdsale();
          let ended =  await crowdsale.ended()
          ended.should.be.equals(false);
          await timeTo(afterEndTime);
          ended =  await crowdsale.ended()
          ended.should.be.equals(true);
      });

      it('shoud have total tokens correct', async () => {
          const crowdsale = await createCrowdsale();
          const totalTokens = await crowdsale.totalTokens();
          totalTokens.should.be.bignumber.equal(BLS_TOTAL_CAP);
      });
  });

  describe('Prices', () => {
    it('shoud mach price rates', async () => {
        const crowdsale = await createCrowdsale();

        await timeTo(await crowdsale.startTime());
        var price = await crowdsale.price();
        const firstRate = await crowdsale.TOKEN_FIRST_PRICE_RATE();
        price.should.be.bignumber.equal(firstRate);


        await timeTo(roundTwoTime);
        var price = await crowdsale.price();
        const secondRate = await crowdsale.TOKEN_SECOND_PRICE_RATE();
        price.should.be.bignumber.equal(secondRate);


        await timeTo(roundThreeTime);
        var price = await crowdsale.price();
        const thirdRate = await crowdsale.TOKEN_THIRD_PRICE_RATE();
        price.should.be.bignumber.equal(thirdRate);

        await timeTo(roundFourTime);
        var price = await crowdsale.price();
        const fourthRate = await crowdsale.TOKEN_FOURTH_PRICE_RATE();
        price.should.be.bignumber.equal(fourthRate);

        await timeTo(roundFiveTime);
        var price = await crowdsale.price();
        const fiveRate = await crowdsale.TOKEN_FIFTH_PRICE_RATE();
        price.should.be.bignumber.equal(fiveRate);

        await timeTo(endTime);
        var price = await crowdsale.price();
        price.should.be.bignumber.equal(fiveRate);
    });
  });


  describe('Payments tests', () => {
    it('should reject payments before start', async () => {
        const crowdsale = await createCrowdsale();
        const started =  await crowdsale.started()
        started.should.be.equals(false);

        const d = getKycData(buyer1, 1, crowdsale.address, SIGNER_PK);

        await crowdsale.buyTokens(d.id, d.max, d.v, d.r, d.s,
                                  {from: buyer1, value: web3.toWei(1, 'ether')})
                                  .should.be.rejected;
    });

    it('should accept valid payments after start', async () => {
        const crowdsale = await createCrowdsale();
        const d = getKycData(buyer1, 1, crowdsale.address, SIGNER_PK);
        await timeTo(startTime);
        const started = await crowdsale.started();
        started.should.be.equals(true);
        await crowdsale.buyTokens(d.id, d.max, d.v, d.r, d.s, {
          from: buyer1,
          value: web3.toWei(1, 'ether')
        }).should.be.fulfilled;

        const d2 = getKycData(buyer1, 1, crowdsale.address, OTHER_PK);
        await crowdsale.buyTokens(d2.id, d2.max, d2.v, d2.r, d2.s, {
          from: buyer1,
          value: web3.toWei(1, 'ether')
        }).should.be.rejected;
    });

    it('should reject payments after end', async () => {
        const crowdsale = await createCrowdsale();
        const d = getKycData(buyer1, 1, crowdsale.address, SIGNER_PK);
        await timeTo(endTime);
        const ended = await crowdsale.ended();
        ended.should.be.all.equal(true);
        await crowdsale.buyTokens(d.id, d.max, d.v, d.r, d.s, {
          from: buyer1,
          value: web3.toWei(1, 'ether')
        }).should.be.rejected;
    });
  });

  describe('ICO', () => {
    it('TEST ICO', async () => {
        const crowdsale = await createCrowdsale();
        const token = BLS.at(await crowdsale.token());
        const d = getKycData(buyer1, 1, crowdsale.address, SIGNER_PK);
  
        var started = await crowdsale.started();
        started.should.be.false;
        var ended = await crowdsale.ended();
        ended.should.be.false;
  
        // increase time to start
        await timeTo(startTime);
  
        started = await crowdsale.started();
        started.should.be.true;
        ended = await crowdsale.ended();
        ended.should.be.false;
  
  
        //checking presale
        var WEI = web3.toWei(1, 'ether');
        await crowdsale.buyTokens(d.id, d.max, d.v, d.r, d.s, {
          from: buyer1,
          value: WEI
        });
  
        var userBalance = await token.balanceOf(buyer1);
        userBalance.should.be.bignumber.equal(web3.toWei(2000, 'ether'));
  
        //checking presale
        var WEI = web3.toWei(50, 'ether');
        await crowdsale.buyTokens(d.id, d.max, d.v, d.r, d.s, {
          from: buyer1,
          value: WEI
        }).should.be.rejected;
  
        var userBalance = await token.balanceOf(buyer1);
        userBalance.should.be.bignumber.equal(web3.toWei(2000, 'ether'));
    });
    //it('test presale', async () => {});
  });

  describe('ICO sale', () => {
    it('Test rounds token buy', async () => {
        const crowdsale = await createCrowdsale();
        const token = BLS.at(await crowdsale.token());
  
        const d = getKycData(buyer1, 1, crowdsale.address, SIGNER_PK);
        var weiAmmount = 0;
        //first price
        var price = await crowdsale.price();
        price.should.be.bignumber.equal(20);
  
        var started = await crowdsale.started();
        started.should.be.false;
        var ended = await crowdsale.ended();
        ended.should.be.false;
  
        // increase time to start
        await timeTo(startTime);
  
        started = await crowdsale.started();
        started.should.be.true;
        ended = await crowdsale.ended();
        ended.should.be.false;
  
        price = await crowdsale.price();
        price.should.be.bignumber.equal(20);
        const WEI = web3.toWei(1, 'ether');
        await crowdsale.buyTokens(d.id, d.max, d.v, d.r, d.s, {
          from: buyer1,
          value: WEI
        });
  
        var balanceUser = await token.balanceOf(buyer1);

        balanceUser.should.be.bignumber.equal(web3.toWei(2000,'ether'));
  
  //  get second round ----------------------
        await timeTo(roundTwoTime);
        // price should be updated to phase 2
        price = await crowdsale.price();
        price.should.be.bignumber.equal(15);
  
        ended = await crowdsale.ended();
        ended.should.be.false;
  
        const WEI_2 = web3.toWei(1, 'ether');
        await crowdsale.buyTokens(d.id, d.max, d.v, d.r, d.s, {
          from: buyer1,
          value: WEI_2
        });
        var balanceUser = await token.balanceOf(buyer1);
        balanceUser.should.be.bignumber.equal(web3.toWei(3500,'ether'));
  //  get thrid round ----------------------
        await timeTo(roundThreeTime);
  
        price = await crowdsale.price();
        price.should.be.bignumber.equal(14);
  
        ended = await crowdsale.ended();
        ended.should.be.false;
  
        const WEI_3 = web3.toWei(1, 'ether');
        await crowdsale.buyTokens(d.id, d.max, d.v, d.r, d.s, {
          from: buyer1,
          value: WEI_3
        });
        var balanceUser = await token.balanceOf(buyer1);
        balanceUser.should.be.bignumber.equal(web3.toWei(4900,'ether'));
  
  //  get fourth round ----------------------
        await timeTo(roundFourTime);
  
        price = await crowdsale.price();
        price.should.be.bignumber.equal(13);
  
        ended = await crowdsale.ended();
        ended.should.be.false;
  
        const wei_4 = web3.toWei(1, 'ether');
        await crowdsale.buyTokens(d.id, d.max, d.v, d.r, d.s, {
          from: buyer1,
          value: wei_4
        });
        var balanceuser = await token.balanceOf(buyer1);
        balanceuser.should.be.bignumber.equal(web3.toWei(6200,'ether'));
  
  //  get fourth round ----------------------
        await timeTo(roundFiveTime);
  
        price = await crowdsale.price();
        price.should.be.bignumber.equal(12);
  
        ended = await crowdsale.ended();
        ended.should.be.false;
  
        const WEI_5 = web3.toWei(1, 'ether');
        await crowdsale.buyTokens(d.id, d.max, d.v, d.r, d.s, {
          from: buyer1,
          value: WEI_5
        });
        var balanceUser = await token.balanceOf(buyer1);
        balanceUser.should.be.bignumber.equal(web3.toWei(7400,'ether'));
  
  
        await timeTo(endTime);
        ended = await crowdsale.ended();
        ended.should.be.true;
  
    });
  
    it('Test soft cap failure', async () => {
          const crowdsale = await createCrowdsale();
          const token = BLS.at(await crowdsale.token());

          const d = getKycData(buyer1, 1, crowdsale.address, SIGNER_PK);

          var price = await crowdsale.price();
          price.should.be.bignumber.equal(20);

          var started = await crowdsale.started();
          started.should.be.false;
          var ended = await crowdsale.ended();
          ended.should.be.false;

          // increase time to start
          await timeTo(startTime);

          started = await crowdsale.started();
          started.should.be.true;
          ended = await crowdsale.ended();
          ended.should.be.false;

          // buy not enough token
          const WEI =  web3.toWei(1, 'ether');;
          await crowdsale.buyTokens(d.id, d.max, d.v, d.r, d.s, {
            from: buyer1,
            value: WEI
          });

          // increase time to start
          await timeTo(endTime);
          ended = await crowdsale.ended();
          ended.should.be.true;

          // state should be running (=0)
          var state = await crowdsale.state();
          state.should.be.bignumber.equal(0);

          // get refund should be rejected before finalize is called
          await crowdsale.claimRefund({
            from: buyer1
          }).should.be.rejected;

//       call finalize
          await crowdsale.finalize(BITLUMENSACCOUNT,TEAMACCOUNT,BOUNTYACCOUNT,{from:accounts[0]});

          // state should be failure (=2)
          state = await crowdsale.state();
          state.should.be.bignumber.equal(2);

          // get refund
          const GAS_PRICE = web3.toWei(1, 'ether');
          //const INVESTOR_BALANCE_PRIOR = web3.eth.getBalance(buyer1);
          //console.log(INVESTOR_BALANCE_PRIOR.toString());

          const receipt = await crowdsale.claimRefund({
            from: buyer1,
            gasPrice: GAS_PRICE
          }).should.be.fulfilled;

//    console.log(account);
//  await crowdsale.finalize(BITLUMENSACCOUNT,TEAMACCOUNT,BOUNDYACCOUNT);


    });
    it('Test soft cap success', async () => {
        const crowdsale = await createCrowdsale();
        const token = BLS.at(await crowdsale.token());

        const d = getKycData(buyer1, 1, crowdsale.address, SIGNER_PK);
        // price should be the price with RATE_1
        var price = await crowdsale.price();
        price.should.be.bignumber.equal(20);


        var started = await crowdsale.started();
        started.should.be.false;
        var ended = await crowdsale.ended();
        ended.should.be.false;

        // increase time to start
        await timeTo(startTime);

        started = await crowdsale.started();
        started.should.be.true;
        ended = await crowdsale.ended();
        ended.should.be.false;

        // buy just enough token
        const WEI = web3.toWei(10, 'ether');;
        await crowdsale.buyTokens(d.id, d.max, d.v, d.r, d.s, {
          from: buyer1,
          value: WEI
        });

        // increase time to end
        await timeTo(endTime);
        ended = await crowdsale.ended();
        ended.should.be.true;

        // state should be running (=0)
        var state = await crowdsale.state();
        state.should.be.bignumber.equal(0);

        // get refund should be rejected
        await crowdsale.claimRefund({
          from: buyer1
        }).should.be.rejected;

        // call finalize
        await crowdsale.finalize(BITLUMENSACCOUNT,TEAMACCOUNT,BOUNTYACCOUNT,{from:accounts[0]});

        var bitlumensTokens = await token.balanceOf(BITLUMENSACCOUNT);
        //console.log(web3.fromWei(bitlumensTokens,'ether'));
        bitlumensTokens.should.be.bignumber.equal(web3.toWei(10000, 'ether'));

        var teamTokens = await token.balanceOf(TEAMACCOUNT);
        //console.log(web3.fromWei(teamTokens,'ether'));
        teamTokens.should.be.bignumber.equal(web3.toWei(9600, 'ether'));


        var bountyTokens = await token.balanceOf(BOUNTYACCOUNT);
        //consle.log(web3.fromWei(bountyTokens,'ether'));
        bountyTokens.should.be.bignumber.equal(web3.toWei(400, 'ether'));

        // state should be success (=1)
        state = await crowdsale.state();
        state.should.be.bignumber.equal(1);

        // get refund should be rejected
        const receipt = await crowdsale.claimRefund({
          from: buyer1
        }).should.be.rejected;

        // const WALLET_BALANCE_POST = web3.eth.getBalance(wallet);
        // console.log(web3.fromWei(WALLET_BALANCE_POST - walletPreBalance,'ether'));
    });
  });

  describe('Math and calculations', () => {
    it('Check calculations accuracy', async () => {
        const crowdsale = await createCrowdsale();
        const token = BLS.at(await crowdsale.token());
        const d = getKycData(buyer1, 1, crowdsale.address, SIGNER_PK);
        await timeTo(startTime);

        const ethToSend = 1.13;
        const ethPriceInUsd = 1000;

        const tokenPriceInUSD = 0.5;
        const DECIMALS_MULTIPLIER = 10 ** 18;

        const usdToSend = ethToSend * ethPriceInUsd;
        const tokensWillBeReceived = Math.floor(usdToSend * DECIMALS_MULTIPLIER / tokenPriceInUSD);


        price = await crowdsale.price();
        realPrice = await crowdsale.TOKEN_FIRST_PRICE_RATE();
        price.should.be.bignumber.equal(realPrice);
    
        await crowdsale.buyTokens(d.id, d.max, d.v, d.r, d.s, {
          from: buyer1,
          value: web3.toWei(1.13, 'ether')
        });
        var balanceUser = await token.balanceOf(buyer1);
        balanceUser.should.be.bignumber.equal(tokensWillBeReceived);
    });

  });
});

