const BigNumber = require('bignumber.js');

require('chai')
  .use(require('chai-as-promised'))
  .should();

const Crowdsale = artifacts.require('./BLSCrowdSaleTest.sol');

const {timeTo, increaseTime, revert, snapshot} = require('./evmMethods');
const {web3async} = require('./web3Utils');

const DECIMALS_MULTIPLIER = 10 ** 4;
const DAY = 24 * 3600;

let NOW, TOMORROW, DAY_AFTER_TOMORROW;

const initTime = (now) => {
  NOW = now;
  TOMORROW = now + DAY;
  DAY_AFTER_TOMORROW = TOMORROW + DAY;
};

contract('Crowdsale', accounts => {
  const startTime = new Date("2018-05-28T00:00:00-05:00").getTime() / 1000;
  const endTime = new Date("2018-06-28T00:00:00-05:00").getTime() / 1000;
  const roundTwoTime = new Date("2018-06-01T00:00:00-05:00").getTime() / 1000;
  const roundThreeTime = new Date("2018-06-02T00:00:00-05:00").getTime() / 1000;
  const roundFourTime = new Date("2018-06-08T00:00:00-05:00").getTime() / 1000;
  const roundFiveTime = new Date("2018-06-14T00:00:00-05:00").getTime() / 1000;
  const kycSigners = [];

  const admin1 = accounts[0];
  const admin2 = accounts[1];
  const buyer1 = accounts[3];

  const createCrowdsale = () => Crowdsale.new(
    startTime,
    endTime,
    roundTwoTime,
    roundThreeTime,
    roundFourTime,
    roundFiveTime,
    admin1,
    admin2,
    kycSigners,
    {value: web3.toWei(1, 'ether')}
  );

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

  it('1. Deployment', async () => {
    await createCrowdsale();
  });

  it('2. Buy before ICO start', async () => {
    const crowdsale = await createCrowdsale();
    await crowdsale.updatePrice("700.00");
    await crowdsale.buyTokens({from: buyer1, value: web3.toWei(1, 'ether')})
      .should.eventually.be.rejected;
  });

  it('3. Simple buy and check tokens amount', async () => {
    const crowdsale = await createCrowdsale();
    await timeTo(startTime);
    await crowdsale.updatePrice("700.00");
    await crowdsale.buyTokens({from: buyer1, value: web3.toWei(1, 'ether')});
    String(await crowdsale.balanceOf(buyer1)).should.equals(String(700 / 0.5 * DECIMALS_MULTIPLIER));
    String(await crowdsale.totalSupply()).should.equals(String(700 / 0.5 * DECIMALS_MULTIPLIER));
  });

  it('4. Buy less than for $25', async () => {
    const crowdsale = await createCrowdsale();
    await timeTo(startTime);
    await crowdsale.updatePrice("700.00");
    await crowdsale.buyTokens({from: buyer1, value: web3.toWei(0.03, 'ether')}) // less than $25
      .should.eventually.be.rejected;
  });

  it('5. Check calculations accuracy', async () => {
    const crowdsale = await createCrowdsale();
    await timeTo(startTime);

    const ethPriceInUsd = 700.12;
    const ethToSend = 1.13;
    const tokenPriceInUSD = 0.5;

    const usdToSend = ethToSend * ethPriceInUsd;
    const tokensWillBeReceived = Math.floor(usdToSend * DECIMALS_MULTIPLIER / tokenPriceInUSD);

    await crowdsale.updatePrice(String(ethPriceInUsd));
    await crowdsale.buyTokens({from: buyer1, value: web3.toWei(1.13, 'ether')});

    String(await crowdsale.balanceOf(buyer1)).should.equals(String(tokensWillBeReceived));
  });

  it('6. Buy tokens in 2nd-5th rounds and check token price', async () => {
    async function buyTokensWithPriceAtTime(roundTokenPriceInUsd, roundStartTime) {
      await revert(snapshotId);
      snapshotId = (await snapshot()).result;

      const crowdsale = await createCrowdsale();
      await timeTo(roundStartTime);

      const ethPriceInUsd = roundTokenPriceInUsd * 1000;
      const ethToSend = 1;

      const usdToSend = ethToSend * ethPriceInUsd;
      const tokensWillBeReceived = Math.floor(usdToSend * DECIMALS_MULTIPLIER / roundTokenPriceInUsd);

      await crowdsale.updatePrice(ethPriceInUsd.toFixed(2));
      await crowdsale.buyTokens({from: buyer1, value: web3.toWei(ethToSend, 'ether')});

      String(await crowdsale.balanceOf(buyer1)).should.equals(String(tokensWillBeReceived));
    }

    const data = [
      {price: 0.50, time: startTime},
      {price: 0.66, time: roundTwoTime},
      {price: 0.71, time: roundThreeTime},
      {price: 0.77, time: roundFourTime},
      {price: 0.83, time: roundFiveTime},
    ];

    for (let i = 0; i < data.length; i++) {
      await buyTokensWithPriceAtTime(data[i].price, data[i].time);
    }
  });
});