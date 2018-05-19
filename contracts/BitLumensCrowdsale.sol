pragma solidity 0.4.21;

import './SafeMath.sol';
import './Ownable.sol';
import './RefundVault.sol';
import "./ICOEngineInterface.sol";
import "./KYCBase.sol";
import "./BLS.sol";
import "./usingOraclize.sol";


contract BitLumensCrowdsale is Ownable, ICOEngineInterface, KYCBase,usingOraclize {
    using  SafeMath for uint;
    enum State {Running,Success,Failure}


    uint public etherPriceUSD;
    event Log(string text);


    // Current ETH/USD exchange rate
    uint256 public ETH_USD_EXCHANGE_CENTS = 500; // set by oraclize

    uint public USD_SOFT_CAP;
    uint public USD_HARD_CAP;

    uint public BLS_TOTAL_CAP;
    uint public BLS_PRE_ICO;

    State public state;

    BLS public token;

    address public wallet;

    // from ICOEngineInterface
    uint public startTime;
    uint public endTime;
    // Time Rounds for ICO
    uint public roundTwoTime;
    uint public roundThreeTime;
    uint public roundFourTime;
    uint public roundFiveTime;

    // Discount multipliers , we will divide by 10 later -- divede by 10 later
    uint public constant TOKEN_FIRST_PRICE_RATE  = 20;
    uint public constant TOKEN_SECOND_PRICE_RATE = 15;
    uint public constant TOKEN_THIRD_PRICE_RATE  = 14;
    uint public constant TOKEN_FOURTH_PRICE_RATE  = 13;
    uint public constant TOKEN_FIFTH_PRICE_RATE = 12;


    // to track if team members already got their tokens
    bool public teamTokensDelivered = false;
    bool public bountyDelivered = false;
    bool public bitlumensDelivered = false;

    // from ICOEngineInterface
    uint public remainingTokens;
    // from ICOEngineInterface
    uint public totalTokens;

    // amount of wei raised
    uint public weiRaised;

    //amount of $$ raised
    uint public dollarRaised;

    // boolean to make sure preallocate is called only once
    bool public isPreallocated;

    // vault for refunding
    RefundVault public vault;

    /**
     * event for token purchase logging
     * @param purchaser who paid for the tokens
     * @param beneficiary who got the token
     * @param value weis paid for purchase
     * @param amount amount of tokens purchased
     */
    event TokenPurchase(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);

    /* event for ICO successfully finalized */
    event FinalizedOK();

    /* event for ICO not successfully finalized */
    event FinalizedNOK();

    /**
     * event for additional token minting
     * @param to who got the tokens
     * @param amount amount of tokens purchased
     */
    event Preallocated(address indexed to, uint256 amount);

    /**
     *  Constructor
     */
    function BitLumensCrowdsale(
      address [] kycSigner,
      address _token,
      address _wallet,
      uint _startTime,
      uint _roundTwoTime,
      uint _roundThreeTime,
      uint _roundFourTime,
      uint _roundFiveTime,
      uint _endTime,
      uint _BlsPreIco,
      uint _blsTotalCap,
      uint _softCapUsd,
      uint _hardCapUsd,
      uint _ethUsdExchangeCents
      )
        public payable
        KYCBase(kycSigner)
    {
        require(_token != address(0));
        require(_wallet != address(0));

        require(_startTime > now);
        require (_startTime < _roundTwoTime);
        require (_roundTwoTime < _roundThreeTime);
        require (_roundThreeTime < _roundFourTime);
        require (_roundFourTime < _roundFiveTime);
        require (_roundFiveTime < _endTime);


        //OAR = OraclizeAddrResolverI(0x6f485C8BF6fc43eA212E93BBF8ce046C7f1cb475);

        token = BLS(_token);
        wallet = _wallet;

        startTime = _startTime;
        endTime = _endTime;
        roundTwoTime= _roundTwoTime;
        roundThreeTime= _roundThreeTime;
        roundFourTime= _roundFourTime;
        roundFiveTime= _roundFiveTime;

        ETH_USD_EXCHANGE_CENTS = _ethUsdExchangeCents;

        USD_SOFT_CAP = _softCapUsd;
        USD_HARD_CAP = _hardCapUsd;

        BLS_PRE_ICO = _BlsPreIco;
        BLS_TOTAL_CAP = _blsTotalCap;
        totalTokens = _blsTotalCap;
        remainingTokens = _blsTotalCap;

        vault = new RefundVault(_wallet);

        state = State.Running;
        //update();

    }


    //// oraclize START
    function __callback(bytes32 _myid, string _result) {
         require (msg.sender == oraclize_cbAddress());
         Log(_result);
         etherPriceUSD = parseInt(_result, 2);
      }
    function update() payable {
       oraclize_query("URL","json(https://min-api.cryptocompare.com/data/price?fsym=ETH&tsyms=USD).USD");
    }
    //// oraclize END

      function orcPrice()  public view returns(uint){
        return(etherPriceUSD);
      }

    // function that is called from KYCBase
    function releaseTokensTo(address buyer) internal returns(bool) {
        // needs to be started
        require(started());
        // and not ended
        require(!ended());
        uint256 weiAmount = msg.value;
        uint256 WeiDollars = weiAmount.mul(ETH_USD_EXCHANGE_CENTS) / 100;
        uint256 currentPrice = price();
        uint tokens = WeiDollars.mul(currentPrice);
        tokens = tokens.div(10); //correct price rate
        //calculate tokon Raised
        uint tokenRaised = totalTokens - remainingTokens;
        // must be less than hard cap

        if(now < roundTwoTime ){
          require(tokenRaised.add(tokens) <= BLS_PRE_ICO);
        }


        require(tokenRaised.add(tokens) <= BLS_TOTAL_CAP);
        weiRaised = weiRaised + weiAmount;
        // total usd in wallet
        uint centsWeiRaised = weiRaised.mul(ETH_USD_EXCHANGE_CENTS);
        uint goal  = USD_HARD_CAP * (10**18) * (10**2);
        // if 25,000,000 $$ raised stop the ico
        require(centsWeiRaised <= goal);
        remainingTokens = remainingTokens.sub(tokens);
        // mint tokens and transfer funds
        token.mint(buyer, tokens);
        forwardFunds();
        TokenPurchase(msg.sender, buyer, weiAmount, tokens);
        return true;
    }

    function forwardFunds() internal {
      vault.deposit.value(msg.value)(msg.sender);
    }


    function finalize(address bitlumensAccount,address teamAccount,address bountyAccount) onlyOwner public {
      require(state == State.Running);
      require(ended());

      uint centsWeiRaised = weiRaised.mul(ETH_USD_EXCHANGE_CENTS);
      uint goal  = USD_SOFT_CAP * (10**18) * (10**2);

      // Check the soft goal reaching
      if(centsWeiRaised >= goal) {

        //token Raised
        uint tokenRaised = totalTokens - remainingTokens;
        //bitlumes tokes 25% equivelent to (tokenraied / 2) (token raised = 50 %)
        uint bitlumensTokens = tokenRaised.div(2);
        uint bountyTokens = bitlumensTokens.div(100);
        uint TeamTokens = bitlumensTokens.sub(bountyTokens);


        token.mint(bitlumensAccount, bitlumensTokens);
        token.mint(teamAccount, TeamTokens);
        token.mint(bountyAccount, bountyTokens);

        // if goal reached
        // stop the minting
        token.finishMinting();
        // enable token transfers
        token.enableTokenTransfers();
        // close the vault and transfer funds to wallet
        vault.close();
        // ICO successfully finalized
        // set state to Success
        state = State.Success;
        FinalizedOK();
      }
      else {
        // if goal NOT reached
        // ICO not successfully finalized
        FinalizedNOK();
        finalizeNOK();
      }
    }



     function finalizeNOK() onlyOwner public {
       // run checks again because this is a public function
       require(state == State.Running);
       require(ended());
       // enable the refunds
       vault.enableRefunds();
       // ICO not successfully finalised
       // set state to Failure
       state = State.Failure;
       FinalizedNOK();
     }

     // if crowdsale is unsuccessful, investors can claim refunds here
     function claimRefund() public {
       require(state == State.Failure);
       vault.refund(msg.sender);
    }


    // from ICOEngineInterface
    function started() public view returns(bool) {
        return now >= startTime;
    }

    // from ICOEngineInterface
    function ended() public view returns(bool) {
        return now >= endTime || remainingTokens == 0;
    }

    function startTime() public view returns(uint) {
      return(startTime);
    }

    function endTime() public view returns(uint){
      return(endTime);
    }

    function totalTokens() public view returns(uint){
      return(totalTokens);
    }

    function remainingTokens() public view returns(uint){
      return(remainingTokens);
    }

    // return the price as number of tokens released for each ether
    function price() public view returns(uint){
      // determine which discount to apply
      if (now < roundTwoTime) {
          return(TOKEN_FIRST_PRICE_RATE);
      } else if (now < roundThreeTime){
          return (TOKEN_SECOND_PRICE_RATE);
      } else if (now < roundFourTime) {
          return (TOKEN_THIRD_PRICE_RATE);
      }else if (now < roundFiveTime) {
          return (TOKEN_FOURTH_PRICE_RATE);
      } else {
          return (TOKEN_FIFTH_PRICE_RATE);
      }
    }

    // No payable fallback function, the tokens must be buyed using the functions buyTokens and buyTokensFor
    function () public {
        revert();
    }

}
