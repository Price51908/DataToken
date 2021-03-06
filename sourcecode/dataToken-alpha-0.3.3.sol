pragma solidity ^0.4.18;

contract DataTokenAlpha {
    address owner;
    //contract (token) properties
    string public tokenName = "dataToken";
    //
    uint public decimals = 9;
    uint256 initialSupply = 666;
    //the possible bigest number of coins (including non-integer valued coins)i.e. number of coins express by the smallest unit of this token
    uint256 totalSupply = initialSupply * 10 ** decimals;
    //APID counter, each new provider will be given this number. It's value updates by +1 after each give out (implemented in surProvider function).
    uint256 APID_counter = 1;
    //ethereum users can be receiver or provider. By defualt they are all receivers. by a successful call of surProvider, a user can be recognized as a provider.
    enum role {ISRECEIVER, ISPROVIDER, PAIRED}
    //token balance of each ethereum account. counted in totalSupply
    mapping (address => uint256) public balance;
    //role of an account, by default is role.ISRECEIVER
    mapping (address => role) public identification;
    //SSID format: DataToken_########; this mapping holds the suffix number shown as #####
    mapping (address => uint256) public APID;
    //find a provider by ssid it uses to share data service (SSID format: DataToken_########, ######## represents numerical ID of that provider)
    //This mapping can be private in release versions.
    mapping (uint256 => address) public providerBehind;
    //number of users under a provider
    mapping (address => uint) public numberOfUsers;
    //Receiver thus knows which address they should pay token.
    mapping (address => address) public providerOf;
    //pricing: value per MB
    mapping (address => uint256) public priceOf;
    //data usage recorded by provider and receiver
    mapping (address => mapping (address => uint256)) public usageOf;
    //provider's pocket// used in link() function
    //receiver has a 'ticket with number' and provider knows the number since a receiver connects to it
    //when a receiver try to connect the provider
    //provider with compare the number from receiver and the number corresponding to such receiver
    //if match, let the receiver in (WLAN)
    //this is using a white name list
    //this kind of login is more like nonce rather than token based authentication
    mapping (address => mapping(address => bytes32)) internal providerPocket;     
    //transfer event infomation. value is 
    event LogTransfer(
        address _from,
        address _to,
        uint256 value
    );
    //switch user role event
    event LogSur(
        address _user,
        role _newrole,
        bool success
    );
    //provider on line
    event LogProviderArchive(
        address _provider,
        uint256 _price
    );
    /**
    *Constructor function
    *@constructor
    *contract has defaultly a provider for convenience of test
    */
    function DataTokenAlpha() public {
        owner = msg.sender;
        balance[owner] = totalSupply;
    }

    /**
    * A getter function.
    * Show Ether balance of this contract (DataToken) in terms of wei
    * This balance is a result of buyToken() function
    * Other addresses buy token will pay Ether to this contract address
    * And owner address distributs token to the buyer
    * However, if the owner address call buyToken function
    * the result is equivalent to depositing an amount of Ether into the contract nothing else will happen
    */
    function contractBalance() 
    public
    constant
    returns(uint256 value)
    {
        value = address(this).balance;
        return value;
    }

    /**
    * core of transfer()
    * it manipulates tokenbalance of addresses and it is rebust to errors. 
    * (on error, revert)
    *
    *internally defined transfer operation
    *transfer certain amount of token from one address to another address
    *this function is so powerful that it should not be accessable externally.
    *param {address} _from value sender
    *param {address} _to value receiver
    *param {uint256} _value value to be sent
    * _to is not 0x0 address
    * _from doesn't have enough token to transfer
    * token of _to will overflow after receiving the transfer
    * total balance of _to and _from has changed after this transfer operation will throw
    */
    function _transfer(address _from, address _to, uint256 _value)
    internal
    returns(bool success)
    {
        //transfer to 0x0 means destroy such amount of token.
        require(_to != 0x0);
        //check if the sender has enough token
        require(balance[_from] >= _value);
        //check if balance of the recipient overflows (don't want overflow)
        require(balance[_to] + _value >= balance[_to]);
        //take a snapshot on total balance of both sides for assert check
        uint256 totalBalance = balance[_from] + balance[_to];
        //transfer operation
        balance[_from] -= _value;
        balance[_to] += _value;
        //assert function is used to check bugs during transfer operation. assert(false) will throw such tranfer.
        assert(balance[_from] + balance[_to] == totalBalance);
        return true;
    }

    /**
    *function to tranfer tokens.
    * Can be called publicly
    * no requirement on caller's identification mapping value
    *
    *_to receiver of _value
    *_value value of token to transfer
    * 
    *_transfer will check whether the operation succeeded or not
    * if _transfer succeeded, transfer will return value of token that has been transfered as success message
    */
    function transfer(address _to, uint256 _value)
    public
    //returns(uint256 value)
    {
        //if _transfer() succeeds, emit the event
        if (_transfer(msg.sender, _to, _value)) {
            // emit the fact of a successful transfer
            emit LogTransfer(msg.sender, _to, _value);
        } else {
            //if not, emit the event saying nothing is sent.
            emit LogTransfer(msg.sender, _to, 0);
        }
        // Whether to keep the return value or not, you need to give it a think
        // return _value;
        //

    }

    /**
    *token seller function
    *
    *msg.sender buy token from owner address using Ether by naming value of the transaction when calling this function
    *this function is payable
    * 
    *requires input Ethereum value
    * 
    * returns amount of tokens bought as a success message
    */
    function buyToken()
    payable
    public
    {
        // msg.value is in wei, DataToken has 9 decimals, msg.value / 10 ** 9 converts wei value to DataToken value.
        _transfer(owner, msg.sender, msg.value / 10 ** 9);
        // emit the fact of a successful transfer
        emit LogTransfer(owner, msg.sender, msg.value / 10 ** 9);
    }

    /**
    * Safe to call directly (maybe...)
    *internally defined switch user role function
    *
    *has built-in check whether current role is allowed to switch
    *
    *param {address} _user address to make change on
    *param {role} _oldrole expected current role of message sender
    *param {role} _newrole targeted new role after a success call of this function
    *
    * current user role is not the required _oldrole
    */
    function _sur(address _user, role _oldrole, role _newrole)
    internal
    returns(bool success)
    {
        // safety concern
        require(identification[_user] == _oldrole);
        // assign new identification mapping value
        identification[_user] = _newrole;
        // safety concern
        assert(identification[_user] == _newrole);
        // on success return success so that caller can trigger event log
        return true;
    }

    /**
    *public function
    *
    *a receiver is switched to be a provider after a success call of this function
    *
    *param {uint256} _price price of wifi service in terms of DataToken per 1 MB data
    *
    *@return {bool} success whether the function has finished successfully
    *@return {address} provider address of the function caller
    *
    * priceOf mapping is not changed by this function throw
    */
    function surProvider (uint256 _price)
    public
    {
        //_sur() has safety check
        if (_sur(msg.sender,role.ISRECEIVER,role.ISPROVIDER)) {
            //if _sur() succeeds, emit role switch true event
            emit LogSur(msg.sender, role.ISPROVIDER, true);
        } else {
            //if not (bool type is false by default), emit false event and function will revert
            emit LogSur(msg.sender, role.ISPROVIDER, false);
        }
        //assign price unit: DataToken per MB
        priceOf[msg.sender] = _price;
        //assign provider ID to be shown in SSID in physical layer
        if (APID[msg.sender] == 0) {
            //if APID is default, the caller has never been a provider
            //assign new provider an APID
            APID[msg.sender] = APID_counter;
            //with providerBehind[APID] user can find provider address with the APID 
            providerBehind[APID_counter] = msg.sender;
            APID_counter += 1;
        }
        // safety check, APID_counter is counting right, provider address is correct, pricing is correct
        assert(providerBehind[APID_counter - 1] == msg.sender && priceOf[msg.sender] == _price);
        // provider buil complete, emit event
        emit LogProviderArchive(msg.sender, _price);
    }

    /**
    *public function
    *
    *a provider in idle is switched to be a receiver after a success call
    *
    *priceOf mapping is intackt from this function
    *
    *param {uint} _numberOfUsers current number of users under this provider's hot spot 
    *
    *@return {bool} success whether this fucntion has succeeded
    *
    * _numberOfUsers is not 0 i.e. this provider is not in idle
    */
    function surReceiver ()
    public
    {
        //caller has to be provider
        require(identification[msg.sender] == role.ISPROVIDER);
        //provider has to have no linked user
        //numberOfUsers only increment by 1 after a successful link() call
        //and it only decrement by 1 after a successful payAndLeave() call
        require(numberOfUsers[msg.sender] == 0);
        //_sur() will revert if no success
        if (_sur(msg.sender, role.ISPROVIDER, role.ISRECEIVER)) {
            emit LogSur(msg.sender, role.ISRECEIVER, true);
        } else {
            emit LogSur(msg.sender, role.ISRECEIVER, false);
        }
    }

    /**
    * Calculate max volume can be payed by function caller
    * internally defined estimation function
    */
    function _affordableData (address _wallet)
    internal
    view
    returns (uint256 maxVolume)
    {
        //estimated max data usage in MB
        return balance[_wallet] / priceOf[providerOf[_wallet]];
    }

    /**
    *
    *public function that links message sender to the chosen provider
    * _providerID:= input APID of the provider which is available to physical frontend receiver
    * _yourkey:= input a key that you want to use to make a stamp on the real key you put in provider's pocket
    *
    *message sender must be receiver
    *
    *providerBehind[_providerID] is the address of provider
    *
    *(Suppose user interface can translate SSID to be address of provider and use that address as argument)
    *
    *affordable data is estimated in this function and the estimation is required to be larger than 1 (MB)
    *
    *role of message sender is changed to be PAIRED which means can call no function but payandleave()
    *
    *return messagesender address and estimation of it's max possible data usage
    *
    *when provider address is not assigned to message sender successfully, throw.
    *
    *when message sender role is not changed to be role.PAIRED, throw.
    * 
    * *************************potential issue*********************************
    * There is possibility that the receiver drop the physical link between it and the provider
    * In that case, the receiver has called link() once and pass through doorkeeper() once
    * role.PAIRER can't call link() and No password to knock doorkeeper() again
    * In current version, the user must call payAndLeave() to reset it's identification as role.ISRECEIVER
    * 
    */
    function link (uint256 _providerID, uint256 _yourkey)
    public
    returns(bytes32 pwd)
    {
        // target identification check; caller identification is checked in _sur() call
        require(identification[providerBehind[_providerID]] == role.ISPROVIDER);
        //balance check, more than 20 MB affordable data volume is required. (currently no reason for the min affordable threshold)
        require(_affordableData(msg.sender) >= 20);
        //change receiver identity to PAIRED
        if (_sur(msg.sender, role.ISPROVIDER, role.PAIRED)) {
            //if _sur() success
            emit LogSur(msg.sender, role.PAIRED, true);
            //assign the provider address to receiver's mapping to establish the link
            providerOf[msg.sender] = providerBehind[_providerID];
            //add one use count to provider
            numberOfUsers[providerBehind[_providerID]] += 1;  
            //put a key in provider's pocket for frontend handshake, _yourkey is to shift block.timestamp, maybe there are some better ways
            providerPocket[providerBehind[_providerID]][msg.sender] = keccak256(block.timestamp + _yourkey);
            // safety: caller has been correctly linked to provider address, caller role.PAIRED is guaranteed by _sur()
            assert(providerOf[msg.sender] == providerBehind[_providerID]);
            // pwd is the same as providerPocket[providerBehind[_providerID]][msg.sender] 
            // doorKeeper() will check this value when providers frontend detects connection request (when doorKeeper() is called) 
            return providerPocket[providerBehind[_providerID]][msg.sender];
        } else {
            emit LogSur(msg.sender, role.PAIRED, false);
        }
        

    }

    /**
    doorkeeper for providers
    _knocker is whichever address delivered by front end as provider to backend doorkeeper function
    _pwd is the bytes32 type number input from provider's front end where the physical knocker show this value to the provider's front end
     */
    function doorKeeper (address _knocker, bytes32 _pwd)
    public
    returns(bool letIn)
    {
        //prerequiest
        require(identification[msg.sender] == role.ISPROVIDER && identification[_knocker] == role.PAIRED);
        //guarentee the knocker is connected to some address (it has called link function) without knowing whether the provider is msg.sender
        
        //retreive the nonce like one-time key put link() as a result of the receiver's call
        letIn = providerPocket[msg.sender][_knocker] == _pwd;
        //reset mapping value. this one-time password (token) is used and expired after this function
        //i.e. once any one try to connect the provider with the identity of the paired receiver
        //and the provider front checked with the contract via this only function
        //the password set by the paired receiver will be expired no matter the _knocker has provided the correct password or not.
        //to hijack a paired receiver address, the malicious user must send   
        delete providerPocket[msg.sender][_knocker];
        return letIn;
    }

    /**
    *function to record data usage
    *
    *Designed to be called frequently by fontend of both sides to update data traffic volume 
    *
    *param _volRecord data usage 
    *data usage is in terms of MB
    */
    function traVolRecord (address _theOtherSide, uint256 _volRecord) 
    public
    returns (bool success)
    {
        usageOf[msg.sender][_theOtherSide] = _volRecord;
        // tell the caller "status logged"
        return true;
    }

    /**
    *internal function
    *compare data usage record by both provider and receiver's devices
    *difference is smaller than tolerance will return true
    *
    *A problem is left for front implementation:
    *To let two devices send information to the contract about data usage.
    */
    function _tolerance (uint256 _range, uint256 _usageLimit)
    internal
    view
    returns (bool success)
    {
        uint256 _urPro = usageOf[providerOf[msg.sender]][msg.sender];
        uint256 _urRec = usageOf[msg.sender][providerOf[msg.sender]];
        require(_usageLimit > usageOf[providerOf[msg.sender]][msg.sender]);
        if (_urRec < _urPro) {
            return (_urPro - _urRec < _range);
        } else {
            return (_urRec - _urPro <= _range);
        }
    }

    /**
    *internally defined fee collector
    *has high authority
    *role.PAIRED will be recovered to be role.ISRECEIVER on succeed.
    */
    function _cashier (address _payer, uint256 _volume)
    internal
    returns (uint256 payValue)
    {
        //transfer fee from receiver to provider, _transfer will throw if error occurs, no need to check transfer result
        _transfer(_payer, providerOf[_payer], _volume * priceOf[providerOf[_payer]]);
        //_sur PAIRED back to receiver
        _sur(msg.sender, role.PAIRED, role.ISRECEIVER);
        //if the payer has payed successfully, it's role should be receiver again after execution of this function
        //if user role is not changed as designed, throw.
        assert(identification[_payer] == role.ISRECEIVER);
        //tell the caller how many tokens transfered, implying transfer succeeded.
        return (_volume * priceOf[providerOf[_payer]]);
    }

    /**
    *normal case used data < datalimit
    *pay function. 
    *
    *assume that tolerance of data usage error obtained by comparing both records is always satisfied (otherwise this function will never succeed)
    *
    * _range is the range of tolerance
    * _usageLimit could be removed in the next version, it is not necessary to be a input, a mapping can replace it
    * 
    * on payment success, this function will return value of token that msg.sender has paid.
    */
    function payAndLeave (uint256 _range, uint256 _usageLimit)
    public
    //returns (uint256 value)
    {
        //compare both sides' data usage record
        require(_tolerance(_range, _usageLimit));
        //pay the provider according to data usage recorded by the provider if tolerance is succeeded.
        // value = _cashier (msg.sender, usageOf[providerOf[msg.sender]][msg.sender]);
        emit LogTransfer(msg.sender, providerOf[msg.sender], _cashier (msg.sender, usageOf[providerOf[msg.sender]][msg.sender]));
        //clear data usage record on both sides
        usageOf[providerOf[msg.sender]][msg.sender] = 0;
        usageOf[msg.sender][providerOf[msg.sender]] = 0;
        //reasonably decrease number of users of the provider by 1
        numberOfUsers[providerOf[msg.sender]] -= 1;
        //check if the clear operation if successful
        assert(usageOf[providerOf[msg.sender]][msg.sender] == usageOf[msg.sender][providerOf[msg.sender]]);
        //return how many tokens are paid (in wei) implying payment success
        //return value;
    }
}