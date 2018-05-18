pragma solidity ^0.4.15;

import "./ICOEngineInterface.sol";
import "./KYCBase.sol";
import "./SafeMath.sol";
import "./StandardToken.sol";
import "./usingOraclize.sol";

/**
 * @title The BLSToken Token contract.
 /*is StandardToken */
contract BLSCrowdSale is StandardToken, usingOraclize, KYCBase {

    // Token metadata
    string public constant name = "BITLUMENS";
    string public constant symbol = "BLS";
    uint256 public constant decimals = 4;
    string public constant version = "0.1";

//the ico terminated if minimum 25m usd preIcoRaise


    uint public constant TOKEN_CREATION_CAP = 25 * (10**6) * 10**decimals;  // 25 million token
    uint256 public constant TOKEN_CREATED_MIN = 10 * (10**6) * 10**decimals;

    uint256 public constant USD_SOFT_CAP = 1 * (10**6);
    uint256 public constant USD_HARD_CAP = 25 * (10**6);

    uint256 public constant ETH_RECEIVED_MIN = 3 * (10**3) * 10**decimals;

    uint256 public constant TOKEN_MIN = 1 * 10**decimals;
    uint256 public constant USD_MIN_DEP = 25;

    // Discount multipliers , we will divide by 10 later
    uint256 public constant TOKEN_FIRST_PRICE_RATE  = 20;
    uint256 public constant TOKEN_SECOND_PRICE_RATE = 15;
    uint256 public constant TOKEN_THIRD_PRICE_RATE  = 14;
    uint256 public constant TOKEN_FOURTH_PRICE_RATE  = 13;
    uint256 public constant TOKEN_FIFTH_PRICE_RATE = 12;


    // Fundraising parameters provided when creating the contract
    uint256 public fundingStartTime;
    uint256 public fundingEndTime;
    uint256 public roundTwoTime;
    uint256 public roundThreeTime;
    uint256 public roundFourTime;
    uint256 public roundFiveTime;
    uint256 public ccReleaseTime;


    address public admin1;      // First administrator for multi-sig mechanism
    address public admin2;      // Second administrator for multi-sig mechanism


    // Contracts current state (Fundraising, Finalized, Paused) and the saved state (if currently paused)
    ContractState public state;       // Current state of the contract
    ContractState private savedState; // State of the contract before pause


    // Keep track of holders and icoBuyers
    mapping (address => bool) public isHolder; // track if a user is a known token holder to the smart contract - important for payouts later
    address[] public holders;                  // array of all known holders - important for payouts later
    mapping (address => bool) isIcoBuyer;      // for tracking if user has to be kyc verified before being able to transfer tokens

    // ETH balance per user
    // Since we have different exchange rates at different stages, we need to keep track
    // of how much ether each contributed in case that we need to issue a refund
    mapping (address => uint256) private ethBalances;
    mapping (address => uint256) private noKycEthBalances;

    // Total received ETH balances
    // We need to keep track of how much ether have been contributed, since we have a cap for ETH too
    uint256 public allReceivedEth;
    // store the hashes of admins' msg.data
    mapping (address => bytes32) private multiSigHashes;

    // to track if team members already got their tokens
    bool public teamTokensDelivered;
    bool public bountyDelivered;
    bool public bitlumensDelivered;

    // Current ETH/USD exchange rate
    uint256 public ETH_USD_EXCHANGE_RATE_IN_CENTS; // set by oraclize

    // Everything oraclize related
    event updatedPrice(string price);
    event newOraclizeQuery(string description);
    uint public oraclizeQueryCost;

    // Events used for logging
    event LogRefund(address indexed _to, uint256 _value);
    event LogCreateBLS(address indexed _to, uint256 _value);
    event LogDeliverBLS(address indexed _to, uint256 _value);
    event LogCancelDelivery(address indexed _to, string _id);
    event LogKycRefused(address indexed _user, uint256 _value);
    event LogTeamTokensDelivered(address indexed distributor, uint256 _value);
    event LogBountyTokensDelivered(address indexed distributor, uint256 _value);
    event LogBitluTokensDelivered(address indexed distributor, uint256 _value);

    // Additional helper structs
    enum ContractState { Fundraising, Finalized, Paused }

    // Modifiers
    modifier isFinalized() {
        require(state == ContractState.Finalized);
        _;
    }

    modifier isFundraising() {
        require(state == ContractState.Fundraising);
        _;
    }

    modifier isPaused() {
        require(state == ContractState.Paused);
        _;
    }

    modifier notPaused() {
        require(state != ContractState.Paused);
        _;
    }

    modifier isFundraisingIgnorePaused() {
        require(state == ContractState.Fundraising || (state == ContractState.Paused && savedState == ContractState.Fundraising));
        _;
    }


    modifier onlyOwner() {
        // check if transaction sender is admin.
        require (msg.sender == admin1 || msg.sender == admin2);
        // if yes, store his msg.data.
        multiSigHashes[msg.sender] = keccak256(msg.data);
        // check if his stored msg.data hash equals to the one of the other admin
        if ((multiSigHashes[admin1]) == (multiSigHashes[admin2])) {
            // if yes, both admins agreed - continue.
            _;
            // Reset hashes after successful execution
            multiSigHashes[admin1] = 0x0;
            multiSigHashes[admin2] = 0x0;
        } else {
            return;
        }
    }

    modifier minimumReached() {
        uint256 total_cap = SafeMath.mul(allReceivedEth, ETH_USD_EXCHANGE_RATE_IN_CENTS);
        require(total_cap >= USD_SOFT_CAP*100);
      //  require(allReceivedEth >= ETH_RECEIVED_MIN);
        require(totalSupply >= TOKEN_CREATED_MIN);
        _;
    }



  constructor(
        uint256 _fundingStartTime,
        uint256 _fundingEndTime,
        uint256 _roundTwoTime,
        uint256 _roundThreeTime,
        uint256 _roundFourTime,
        uint256 _roundFiveTime,
        address _admin1,
        address _admin2,
        address [] kycSigner) public KYCBase(kycSigner)
        payable
    {
        // Check that the parameters make sense

        // The start of the fundraising should happen in the future
        require ( now <= _fundingStartTime);
        // The discount rate changes and ending should follow in their subsequent order
        require (_fundingStartTime < _roundTwoTime);
        require (_roundTwoTime < _roundThreeTime);
        require (_roundThreeTime < _roundFourTime);
        require (_roundFourTime < _roundFiveTime);
        require (_roundFiveTime < _fundingEndTime);


        // admin1 and admin2 address must be set and must be different
        require (_admin1 != 0x0);
        require (_admin2 != 0x0);
        require (_admin1 != _admin2);


        // provide some ETH for oraclize price feed
        require (msg.value > 0);

        // Init contract state
        state = ContractState.Fundraising;
        savedState = ContractState.Fundraising;
        fundingStartTime = _fundingStartTime;
        fundingEndTime = _fundingEndTime;
        roundTwoTime = _roundTwoTime;
        roundThreeTime = _roundThreeTime;
        roundFourTime = _roundFourTime;
        roundFiveTime = _roundFiveTime;

        totalSupply = 0;
        totalSupplyForCalculation = 0;

        admin1 = _admin1;
        admin2 = _admin2;


        //oraclize
//        oraclize_setCustomGasPrice(100000000000 wei); // set the gas price a little bit higher, so the pricefeed definitely works
//        updatePrice();
//        oraclizeQueryCost = oraclize_getPrice("URL");
    }

    //// oraclize START

    // @dev oraclize is called recursively here - once a callback fetches the newest ETH price, the next callback is scheduled for the next hour again
    function __callback(bytes32 myid, string result) {
        require(msg.sender == oraclize_cbAddress());
        // setting the token price here
        ETH_USD_EXCHANGE_RATE_IN_CENTS = SafeMath.parse(result);
        updatedPrice(result);
        // fetch the next price
        updatePrice();
    }

    function updatePrice() payable {    // can be left public as a way for replenishing contract's ETH balance, just in case
        if (msg.sender != oraclize_cbAddress()) {
            require(msg.value >= 200 finney);
        }
        if (oraclize_getPrice("URL") > this.balance) {
            newOraclizeQuery("Oraclize query was NOT sent, please add some ETH to cover for the query fee");
        } else {
            newOraclizeQuery("Oraclize sent, wait..");
            // Schedule query in 1 hour. Set the gas amount to 220000, as parsing in __callback takes around 70000 - we play it safe.
            oraclize_query(3600, "URL", "json(https://min-api.cryptocompare.com/data/price?fsym=ETH&tsyms=USD).USD", 220000);
        }
    }
    //// oraclize END

    // Overridden method to check for end of fundraising before allowing transfer of tokens
    function transfer(address _to, uint256 _value)
    public
    isFinalized // Only allow token transfer after the fundraising has ended
    onlyPayloadSize(2)
    returns (bool success)
    {
        bool result = super.transfer(_to, _value);
        if (result) {
            trackHolder(_to); // track the owner for later payouts
        }
        return result;
    }

    // Overridden method to check for end of fundraising before allowing transfer of tokens
    function transferFrom(address _from, address _to, uint256 _value)
    public
    isFinalized // Only allow token transfer after the fundraising has ended
    onlyPayloadSize(3)
    returns (bool success)
    {
        bool result = super.transferFrom(_from, _to, _value);
        if (result) {
            trackHolder(_to); // track the owner for later payouts
        }
        return result;
    }

    // Allow for easier balance checking
    function getBalanceOf(address _owner)
    constant
    returns (uint256 _balance)
    {
        return balances[_owner];
    }


    // Allows to figure out the amount of known token holders
    function getHolderCount()
    public
    constant
    returns (uint256 _holderCount)
    {
        return holders.length;
    }

    // Allows for easier retrieval of holder by array index
    function getHolder(uint256 _index)
    public
    constant
    returns (address _holder)
    {
        return holders[_index];
    }

    function trackHolder(address _to)
    private
    returns (bool success)
    {
        // Check if the recipient is a known token holder
        if (isHolder[_to] == false) {
            // if not, add him to the holders array and mark him as a known holder
            holders.push(_to);
            isHolder[_to] = true;
        }
        return true;
    }


    /// @dev Accepts ether and creates new BLS tokens
    function releaseTokensTo(address buyer) internal isFundraising returns(bool) {
      //check if the ico time is valid
        require(now >= fundingStartTime);
        require(now <= fundingEndTime);
      //check if the user send funds to the contract
        require(msg.value > 0);
        uint256 cents = SafeMath.mul(msg.value, ETH_USD_EXCHANGE_RATE_IN_CENTS) / 1 ether;
        uint256 dollars = cents / 100;
        require(dollars >= USD_MIN_DEP);
        // return the contribution if the cap has been reached already
        uint256 checkedReceivedEth = SafeMath.add(allReceivedEth, msg.value);
        uint256 total_cap = SafeMath.mul(checkedReceivedEth, ETH_USD_EXCHANGE_RATE_IN_CENTS) / 1 ether;
        require(total_cap <= USD_HARD_CAP*100);

        // calculate the token amount
       // divide by 100 to turn ETH_USD_EXCHANGE_RATE_IN_CENTS into full USD
       // apply discount multiplier
       uint256 tokens = safeMulPercentage(dollars, getCurrentRoundPrice());
       //check if number of tokes is greater or equal minium allowed tokens
       tokens = tokens/10;
       require(tokens >= TOKEN_MIN);
       uint256 checkedSupply = SafeMath.add(totalSupply, tokens);

        if (now < roundTwoTime) {
            uint256 preIcoRaisedCheck = SafeMath.add(preIcoRaised, tokens);
            require(preIcoRaisedCheck <= TOKEN_CREATED_MIN);
        }
        else{
          require((checkedSupply - preIcoRaised) <= (TOKEN_CREATION_CAP));
        }

        // if buyer is already KYC unlocked...
        ethBalances[buyer] = SafeMath.add(ethBalances[buyer], msg.value);
        allReceivedEth = SafeMath.add(allReceivedEth, msg.value);

        totalSupply = checkedSupply;
        totalSupplyForCalculation = totalSupply;
        balances[buyer] += tokens;  // safeAdd not needed; bad semantics to use here
        trackHolder(buyer);
        // to force the check for KYC Status upon the user when he tries transferring tokens
        // and exclude every later token owner
        isIcoBuyer[buyer] = true;
        // Log the creation of these tokens
        LogCreateBLS(buyer, tokens);
    }



    /// @dev Returns the current token price
    function getCurrentRoundPrice()
    private
    constant
    returns (uint256 currentPrice)
    {
        // determine which discount to apply
        if (now < roundTwoTime) {
            // first round
            return TOKEN_FIRST_PRICE_RATE;
        } else if (now < roundThreeTime){
            // second round
            return TOKEN_SECOND_PRICE_RATE;
        } else if (now < roundFourTime) {
            // third round
            return TOKEN_THIRD_PRICE_RATE;
        }else if (now < roundFiveTime) {
            // third round
            return TOKEN_FOURTH_PRICE_RATE;
        } else {
            // fourth round, no discount
            return TOKEN_FIFTH_PRICE_RATE;
        }
    }

    /// @dev Allows to transfer ether from the contract as soon as the minimum is reached
    function retrieveEth(uint256 _value, address _safe)
    external
    minimumReached
    onlyOwner
    {
        // make sure a recipient was defined !
        require (_safe != 0x0);
        // send the eth to where admins agree upon
        _safe.transfer(_value);
    }


    /// @dev Ends the fundraising period and sends the ETH to wherever the admins agree upon
    function finalize(address _safe)
    external
    isFundraising
    minimumReached
    onlyOwner  // Only the admins calling this method exactly the same way can finalize the sale.
    {
        // Only allow to finalize the contract before the ending Time if we already reached any of the two caps
        require(now > fundingEndTime || allReceivedEth >= ETH_RECEIVED_MIN);
        // make sure a recipient was defined !
        require (_safe != 0x0);
        // Move the contract to Finalized state
        state = ContractState.Finalized;
        savedState = ContractState.Finalized;
        totalSupplyForCalculation = totalSupply;
        // Send the KYCed ETH to where admins agree upon.
        _safe.transfer(allReceivedEth);
    }


    /// @dev Pauses the contract
    function pause()
    external
    notPaused   // Prevent the contract getting stuck in the Paused state
    onlyOwner   // Only both admins calling this method can pause the contract
    {
        // Move the contract to Paused state
        savedState = state;
        state = ContractState.Paused;
    }


    /// @dev Proceeds with the contract
    function proceed()
    external
    isPaused
    onlyOwner   // Only both admins calling this method can proceed with the contract
    {
        // Move the contract to the previous state
        state = savedState;
    }

    /// @dev Allows contributors to recover their ether in case the minimum funding goal is not reached
    function refund()
    external
    {
        require(now > (fundingEndTime + 432000)); // 5 days after ico finished to refund
        // No refunds if the minimum has been reached or minimum of 1 Million Tokens have been generated
        require(allReceivedEth < ETH_RECEIVED_MIN || totalSupply < TOKEN_CREATED_MIN);

        // to prevent CC buyers from accidentally calling refund and burning their tokens
        require (ethBalances[msg.sender] > 0);

        // Only refund if there are BLS tokens
        uint256 BLSVal = balances[msg.sender];
        require(BLSVal > 0);

        uint256 ethVal = ethBalances[msg.sender];
        require(ethVal > 0);

        allReceivedEth = SafeMath.sub(allReceivedEth, ethBalances[msg.sender]);
        // Update the state only after all the checks have passed.
        // reset everything to zero, no replay attacks.
        balances[msg.sender] = 0;
        ethBalances[msg.sender] = 0;
        noKycEthBalances[msg.sender] = 0;
        totalSupply = SafeMath.sub(totalSupply, BLSVal); // Extra safe
        // Log this refund
        LogRefund(msg.sender, ethVal);
        // Send the contributions only after we have updated all the balances
        // If you're using a contract, make sure it works with .transfer() gas limits
        msg.sender.transfer(ethVal);
    }

    // @dev Deliver tokens to be distributed to team members
    function deliverTeamTokens(address _to)
    external
    isFinalized
    onlyOwner
    {
      require(teamTokensDelivered == false);
      require(_to != 0x0);
      uint256 unpurchasedTokens=getUnpurchasedTokens();
      uint256 tokens=safeMulPercentage(unpurchasedTokens,46000);
      balances[_to] = tokens;
      teamTokensDelivered = true;
      totalSupply += tokens;
      trackHolder(_to);
      // Log the creation of these tokens
      LogTeamTokensDelivered(_to, tokens);
    }

    function deliverBountyTokens(address _to)
    external
    isFinalized
    onlyOwner
    {
        require(bountyDelivered == false);
        require(_to != 0x0);
        uint256 unpurchasedTokens=getUnpurchasedTokens();
        uint256 tokens=safeMulPercentage(unpurchasedTokens,4000);
        balances[_to] = tokens;
        //update state
        bountyDelivered = true;
        totalSupply += tokens;
        trackHolder(_to);
        // Log the creation of these tokens
        LogBountyTokensDelivered(_to, tokens);
    }

    function deliverBitlumensTokens(address _to)
    external
    isFinalized
    onlyOwner
    {
      require(bitlumensDelivered == false);
      require(_to != 0x0);
      uint256 unpurchasedTokens=getUnpurchasedTokens();
      uint256 tokens=safeMulPercentage(unpurchasedTokens,500000);
      balances[_to] = tokens;
      //update state
      bitlumensDelivered = true;
      totalSupply += tokens;
      trackHolder(_to);
      // Log the creation of these tokens
      LogBitluTokensDelivered(_to, tokens);
    }


    function getUnpurchasedTokens()
    internal
    constant
    returns (uint256 resultValue)
    {
      uint256 newTotalSupply = safeMulPercentage(totalSupplyForCalculation, 200000);
      uint256 tokens = SafeMath.sub(newTotalSupply, totalSupply);
      return tokens;
    }

    function safeMulPercentage(uint256 value, uint256 percentage)
    internal
    constant
    returns (uint256 resultValue)
    {
        // Multiply with percentage
        uint256 newValue = SafeMath.mul(value, percentage);
        // Remove the 5 extra decimals
        newValue = newValue * 10**decimals;
        return newValue;
    }

    // customizing the gas price for oraclize calls during "ICO Rush hours"
    function setOraclizeGas(uint256 _option)
    external
    onlyOwner
    {
        if (_option <= 30) {
            oraclize_setCustomGasPrice(30000000000 wei);
        } else if (_option <= 50) {
            oraclize_setCustomGasPrice(50000000000 wei);
        } else if (_option <= 70) {
            oraclize_setCustomGasPrice(70000000000 wei);
        } else if (_option <= 100) {
            oraclize_setCustomGasPrice(100000000000 wei);
        }
    }


    // from ICOEngineInterface
    function started() public view returns(bool) {
        return now >= fundingStartTime;
    }

    // from ICOEngineInterface
    function ended() public view returns(bool) {
      uint remainingTokens = SafeMath.sub(TOKEN_CREATION_CAP, totalSupplyForCalculation);
      return now >= fundingEndTime || remainingTokens == 0;
    }

    function totalTokens() public view returns(uint){
      return TOKEN_CREATION_CAP;
    }

    // returns the number of the tokens available for the ico. At the moment that the ico starts it must be equal to totalTokens(),
    // then it will decrease. It is used to calculate the percentage of sold tokens as remainingTokens() / totalTokens()
    function remainingTokens() public view returns(uint){
      uint remainingTokens = SafeMath.sub(TOKEN_CREATION_CAP, totalSupplyForCalculation);
      return remainingTokens;
    }

    // return the price as number of tokens released for each ether
    function price() public view returns(uint){
       uint price = getCurrentRoundPrice();
       return price/10;
    }


}
