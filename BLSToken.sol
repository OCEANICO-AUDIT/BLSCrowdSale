pragma solidity ^0.4.15;

import "./StandardToken.sol";
import "./usingOraclize.sol";

/**
 * @title The BLSToken Token contract.
 /*is StandardToken */
contract BLSCrowdSale is StandardToken, usingOraclize {

    // Token metadata
    string public constant name = "BITLUMENS";
    string public constant symbol = "BLS";
    uint256 public constant decimals = 4;
    string public constant version = "0.9";

    // Fundraising goals: minimums and maximums
    uint256 public constant TOKEN_CREATION_CAP = 25 * (10**6) * 10**decimals;  // 25 million token
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
    address public tokBLSendor; // Account delivering Tokens purchased with credit card

    // Contracts current state (Fundraising, Finalized, Paused) and the saved state (if currently paused)
    ContractState public state;       // Current state of the contract
    ContractState private savedState; // State of the contract before pause

    //@dev Usecase related: Purchasing Tokens with Credit card
    //@dev Usecase related: Canceling purchases done with credit card
    mapping (string => Purchase) purchases;                 // in case CC payments get charged back, admins shall only be allowed to kill the exact amount of tokens associated with this payment
    mapping (address => uint256) public ccLockedUpBalances; // tracking the total amount of tokens users have bought via CC - locked up until ccReleasetime
    string[] public purchaseArray;                          // holding the IDs of all CC purchases

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
    uint256 public allUnKycedEth; // total amount of ETH we have no KYC for yet

    // store the hashes of admins' msg.data
    mapping (address => bytes32) private multiSigHashes;

    // KYC
    mapping (address => bool) public isKycTeam;   // to determine, if a user belongs to the KYC team or not
    mapping (address => bool) public kycVerified; // to check if user has already undergone KYC or not, to lock up his tokens until then

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

    // Credit Card Purchase Parameters
    //@dev Usecase related: Purchase Tokens with Credit card
    //@dev Usecase related: Cancel purchase done with credit card
    struct Purchase {
        address buyer;
        uint256 tokenAmount;
        bool active;
    }

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

    modifier onlyKycTeam(){
        require(isKycTeam[msg.sender] == true);
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
            // if not (yet), return.
            return;
        }
    }

    modifier onlyVendor() {
        require(msg.sender == tokBLSendor);
        _;
    }

    modifier minimumReached() {
        uint256 totalKycedAndUnKycEdEth = SafeMath.add(allUnKycedEth, allReceivedEth);
        uint256 total_cap = SafeMath.mul(totalKycedAndUnKycEdEth, ETH_USD_EXCHANGE_RATE_IN_CENTS);
        require(total_cap >= USD_SOFT_CAP*100);
      //  require(allReceivedEth >= ETH_RECEIVED_MIN);
        require(totalSupply >= TOKEN_CREATED_MIN);
        _;
    }

    modifier isKycVerified(address _user) {
        // if token transferring user acquired the tokens through the ICO...
        if (isIcoBuyer[_user] == true) {
            // ...check if user is already unlocked
            require (kycVerified[_user] == true);
        }
        _;
    }

    modifier hasEnoughUnlockedTokens(address _user, uint256 _value) {
        // check if the user was a CC buyer and if the lockup period is not over,
        if (ccLockedUpBalances[_user] > 0 && now < ccReleaseTime) {
            // allow to only transfer the not-locked up tokens
            require ((SafeMath.sub(balances[_user], _value)) >= ccLockedUpBalances[_user]);
        }
        _;
    }

    /**
     * @dev Create a new BLSToken contract.
     *
     */

    function BLSCrowdSale(
        uint256 _fundingStartTime,
        uint256 _fundingEndTime,
        uint256 _roundTwoTime, // time number that triggers the first exchange rate change
        uint256 _roundThreeTime, // time number that triggers the second exchange rate change
        uint256 _roundFourTime,
        uint256 _roundFiveTime,
        address _admin1,
        address _admin2,
        address _tokBLSendor,
        uint256 _ccReleaseTime)
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

        // time when tokens bought with CC will be released must be in the future
        require (_fundingEndTime < _ccReleaseTime);

        // admin1 and admin2 address must be set and must be different
        require (_admin1 != 0x0);
        require (_admin2 != 0x0);
        require (_admin1 != _admin2);

        // tokBLSendor must be set and be different from admin1 and admin2
        require (_tokBLSendor != 0x0);
        require (_tokBLSendor != _admin1);
        require (_tokBLSendor != _admin2);

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
        ccReleaseTime = _ccReleaseTime;

        totalSupply = 0;
        totalSupplyForCalculation = 0;

        admin1 = _admin1;
        admin2 = _admin2;
        tokBLSendor = _tokBLSendor;

        //oraclize
        oraclize_setCustomGasPrice(100000000000 wei); // set the gas price a little bit higher, so the pricefeed definitely works
        updatePrice();
        oraclizeQueryCost = oraclize_getPrice("URL");
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
    isKycVerified(msg.sender)
    hasEnoughUnlockedTokens(msg.sender, _value)
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
    isKycVerified(msg.sender)
    hasEnoughUnlockedTokens(msg.sender, _value)
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

     // getting purchase details by ID - workaround, mappings with dynamically sized keys can't be made public yet.
    function getPurchaseById(string _id)
    constant
    returns (address _buyer, uint256 _tokenAmount, bool _active){
        _buyer = purchases[_id].buyer;
        _tokenAmount = purchases[_id].tokenAmount;
        _active = purchases[_id].active;
    }

    // Allows to figure out the amount of known token holders
    function getHolderCount()
    public
    constant
    returns (uint256 _holderCount)
    {
        return holders.length;
    }

    // Allows to figure out the amount of purchases
    function getPurchaseCount()
    public
    constant
    returns (uint256 _purchaseCount)
    {
        return purchaseArray.length;
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
    function createTokens()
    payable
    external
    isFundraising
    {
      //check if the ico time is valid
        require(now >= fundingStartTime);
        require(now <= fundingEndTime);
      //check if the user send funds to the contract
        require(msg.value > 0);
        uint256 cents = SafeMath.mul(msg.value, ETH_USD_EXCHANGE_RATE_IN_CENTS);
        dollars = cents / 100;
        require(dollars >= USD_MIN_DEP);
        // First we check the ETH cap: would adding this amount to the total unKYCed eth and the already KYCed eth exceed the eth cap?
        // return the contribution if the cap has been reached already
        uint256 totalKycedAndUnKycEdEth = SafeMath.add(allUnKycedEth, allReceivedEth);
        uint256 checkedReceivedEth = SafeMath.add(totalKycedAndUnKycEdEth, msg.value);
        uint256 total_cap = SafeMath.mul(checkedReceivedEth, ETH_USD_EXCHANGE_RATE_IN_CENTS);
        require(total_cap <= USD_HARD_CAP*100);

        // calculate the token amount
       // divide by 100 to turn ETH_USD_EXCHANGE_RATE_IN_CENTS into full USD
       // apply discount multiplier
       tokens = safeMulPercentage(dollars, getCurrentRoundPrice());
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

        // Only when all the checks have passed, then we check if the address is already KYCEd and then
        // update the state (noKycEthBalances, allReceivedEth, totalSupply, and balances) of the contract

        if (kycVerified[msg.sender] == false) {
            // @dev The unKYCed eth balances are moved to ethBalances in unlockKyc()
            noKycEthBalances[msg.sender] = SafeMath.add(noKycEthBalances[msg.sender], msg.value);
            // add the contributed eth to the total unKYCed eth amount
            allUnKycedEth = SafeMath.add(allUnKycedEth, msg.value);
        } else {
            // if buyer is already KYC unlocked...
            ethBalances[msg.sender] = SafeMath.add(ethBalances[msg.sender], msg.value);
            allReceivedEth = SafeMath.add(allReceivedEth, msg.value);
        }

        totalSupply = checkedSupply;

        balances[msg.sender] += tokens;  // safeAdd not needed; bad semantics to use here

        trackHolder(msg.sender);
        // to force the check for KYC Status upon the user when he tries transferring tokens
        // and exclude every later token owner
        isIcoBuyer[msg.sender] = true;
        // Log the creation of these tokens
        LogCreateBLS(msg.sender, tokens);
    }

    //add a user to the KYC team
    function addToKycTeam(address _teamMember)
    onlyOwner
    onlyPayloadSize(1){
        isKycTeam[_teamMember] = true;
    }

    //remove a user from the KYC team
    function removeFromKycTeam(address _teamMember)
    onlyOwner
    onlyPayloadSize(1){
        isKycTeam[_teamMember] = false;
    }

    //called by KYC team
    function unlockKyc(address _owner)
    external
    onlyKycTeam {
        require(kycVerified[_owner] == false);
        //unlock the owner to allow transfer of tokens
        kycVerified[_owner] = true;
        // we leave the ccLockedUpBalances[_owner] as is, because also KYCed users could cancel their CC payments
        if (noKycEthBalances[_owner] > 0) { // check if the user was an ETH buyer
            // now move the unKYCed eth balance to the regular ethBalance.
            ethBalances[_owner] = noKycEthBalances[_owner];
            // add the now KYCed eth to the total received eth
            allReceivedEth = SafeMath.add(allReceivedEth, noKycEthBalances[_owner]);
            // subtract the now KYCed eth from total amount of unKYCed eth
            allUnKycedEth = SafeMath.sub(allUnKycedEth, noKycEthBalances[_owner]);
            // and set the user's unKYCed eth balance to 0
            noKycEthBalances[_owner] = 0; // preventing replay attacks
        }
    }

    // Refusing KYC of a user, who only contributed in ETH.
    // We must pay close attention here for the case that a user contributes in ETH AND(!) CC !
    // in this case, he must only kill the tokens he received through ETH, the ones bought in fiat will be
    // killed by canceling his payments and subsequently calling cancelDelivery() with the according payment id.
    function refuseKyc(address _user)
    external
    onlyKycTeam
    {
        // once a user is verified, you can't kick him out.
        require (kycVerified[_user] == false);

        // immediately stop, if a user has none or only CC contributions.
        // we're managing kyc refusing of CC contributors off-chain
        require(noKycEthBalances[_user]>0);

        uint256 BLSVal = balances[_user];
        require(BLSVal > 0);

        uint256 ethVal = noKycEthBalances[_user]; // refund un-KYCd eth
        require(ethVal > 0);
        // Update the state only after all the checks have passed
        allUnKycedEth = SafeMath.sub(allUnKycedEth, noKycEthBalances[_user]); // or if there was any unKYCed Eth, subtract it from the total unKYCed eth balance.
        balances[_user] = ccLockedUpBalances[_user]; // assign user only the token amount he has bought through CC, if there are any.
        noKycEthBalances[_user] = 0;
        totalSupply = SafeMath.sub(totalSupply, BLSVal); // Extra safe
        // Log this refund
        LogKycRefused(_user, ethVal);
        // Send the contributions only after we have updated all the balances
        // If you're using a contract, make sure it works with .transfer() gas limits
        _user.transfer(ethVal);
    }

    // Called in case a buyer cancels his CC payment.
    // @param The payment ID from payment provider
    function cancelDelivery(string _purchaseID)
    external
    onlyKycTeam{

        // CC payments are only cancelable until ccReleaseTime
        require (now < ccReleaseTime);
        // check if the purchase to cancel is still active
        require (purchases[_purchaseID].active == true);
        // now withdraw the canceled purchase's token amount from the user's balance
        balances[purchases[_purchaseID].buyer] = SafeMath.sub(balances[purchases[_purchaseID].buyer], purchases[_purchaseID].tokenAmount);
        // and withdraw the canceled purchase's token amount from the lockedUp token balance
        ccLockedUpBalances[purchases[_purchaseID].buyer] = SafeMath.sub(ccLockedUpBalances[purchases[_purchaseID].buyer], purchases[_purchaseID].tokenAmount);
        // set the purchase's status to inactive
        purchases[_purchaseID].active = false;
        //correct th amount of tokens generated
        totalSupply = SafeMath.sub(totalSupply, purchases[_purchaseID].tokenAmount);
        LogCancelDelivery(purchases[_purchaseID].buyer, _purchaseID);
    }

    // @dev Deliver tokens sold for CC/fiat and BTC
    // @dev param _tokens in Cents, e.g. 1 Token == 1$, passed as 100 cents
    // @dev param _btcBuyer Boolean to determine if the delivered tokens need to be locked (not the case for BTC buyers, their payment is final)
    // @dev discount multipliers are applied off-contract in this case
    function deliverTokens(address _to, uint256 _tokens, string _purchaseId, bool _btcBuyer)
    external
    isFundraising
    onlyVendor
    {
        require(_to != 0x0);
        require(_tokens > 0);
        require(bytes(_purchaseId).length>0);
        require(now >= fundingStartTime);
        require(now <= fundingEndTime + 168000); // allow delivery of tokens sold for fiat for 28 days after end of ICO for safety reasons

        // calculate the total amount of tokens and cut out the extra two decimal units,
        // because _tokens was in cents.
        uint256 tokens = SafeMath.mul(_tokens, (10**(decimals) / 10**2));

        // continue to check for how many tokens
        // have been generated so far
        uint256 checkedSupply = SafeMath.add(totalSupply, tokens);
        require(checkedSupply <= TOKEN_CREATION_CAP);

        // Only when all the checks have passed, then we update the state (totalSupply, and balances) of the contract
        totalSupply = checkedSupply;

        // prevent from adding a delivery multiple times
        require(purchases[_purchaseId].buyer==0x0);

        // Log this information in order to be able to cancel token deliveries (on CC refund) by the payment ID
        purchases[_purchaseId] = Purchase({
            buyer: _to,
            tokenAmount: tokens,
            active: true
        });
        purchaseArray.push(_purchaseId);

        // if tokens were not paid with BTC (but credit card), they need to be locked up
        if (_btcBuyer == false) {
        ccLockedUpBalances[_to] = SafeMath.add(ccLockedUpBalances[_to], tokens); // update user's locked up token balance
        }

        balances[_to] = SafeMath.add(balances[_to], tokens);                     // safeAdd not needed; bad semantics to use here
        trackHolder(_to);                                                        // log holder's address
        // to force the check for KYC Status upon the user when he tries transferring tokens
        // and exclude every later token owner
        isIcoBuyer[_to] = true;
        // Log the creation of these tokens
        LogDeliverBLS(_to, tokens);
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
        require(SafeMath.sub(this.balance, _value) >= allUnKycedEth); // make sure unKYCed eth cannot be withdrawn
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
        // Allow refunds only a week after end of funding to give KYC-team time to verify contributors
        // and thereby move un-KYC-ed ETH over into allReceivedEth as well as deliver the tokens paid with CC
        require(now > (fundingEndTime + 42000));

        // No refunds if the minimum has been reached or minimum of 1 Million Tokens have been generated
        require(allReceivedEth < ETH_RECEIVED_MIN || totalSupply < TOKEN_CREATED_MIN);

        // to prevent CC buyers from accidentally calling refund and burning their tokens
        require (ethBalances[msg.sender] > 0 || noKycEthBalances[msg.sender] > 0);

        // Only refund if there are BLS tokens
        uint256 BLSVal = balances[msg.sender];
        require(BLSVal > 0);

        // refunds either KYCed eth or un-KYCd eth
        uint256 ethVal = SafeMath.add(ethBalances[msg.sender], noKycEthBalances[msg.sender]);
        require(ethVal > 0);

        allReceivedEth = SafeMath.sub(allReceivedEth, ethBalances[msg.sender]);    // subtract only the KYCed ETH from allReceivedEth, because the latter is what admins will only be able to withdraw
        allUnKycedEth = SafeMath.sub(allUnKycedEth, noKycEthBalances[msg.sender]); // or if there was any unKYCed Eth, subtract it from the total unKYCed eth balance.

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
        newValue = newValue / 10**5;
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
}
