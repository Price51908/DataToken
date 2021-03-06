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
//ethereum users can be receiver or provider. By defualt they are all receivers. by a successful call of surProvider, a user can be recognized as a provider.
enum role {ISRECEIVER, ISPROVIDER, UNDERSERVICE}
//token balance of each ethereum account. counted in totalSupply
mapping (address => uint256) public balance;
//role of an account, by default is role.ISRECEIVER
mapping (address => role) public identification;
//find a provider by ssid it uses to share data service
//mapping (string => address) providerBehind;

//SSID is generated based on provider's address on the front
mapping (address => address) public providerOf;
//pricing: value per MB
mapping (address => uint256) public priceOf;
//data usage recorded by provider and receiver
mapping (address => mapping (address => uint256)) public usageOf;
//transfer event infomation. value is 
event Transfer(address _from, address _to, uint256 value);
//switch user role event
event Sur(address _user, role _newrole, bool success);
/**
*Constructor function
*@constructor
*contract has defaultly a provider for convenience of test
*/
function DataTokenAlpha() public {
    owner = msg.sender;
    balance[owner] = totalSupply;
    identification[0xdd870fa1b7c4700f2bd7f44238821c26f7392148] = role.ISPROVIDER;
    //1 totalSupply per MB
    priceOf[0xdd870fa1b7c4700f2bd7f44238821c26f7392148] = 1;
}

/**
*internally defined transfer operation
*/
function _transfer(address _from, address _to, uint256 _value)
internal
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
}

/**
*tranfer that is called publicly
*/
function transfer(address _to, uint256 _value)
public
{
    _transfer(msg.sender, _to, _value);
}

/**
*token seller function
*/
function buyToken()
payable
public
returns(bool success)
{
    _transfer(owner, msg.sender, msg.value / 10 ** 9);
    return true;
}

/**
*internally defined switch user role function
*has built-in check whether current role is allowed to switch
*@param _oldrole expected current role of message sender
*@param _newrole targeted new role after a success call of this function
*/
function _sur(address _user, role _oldrole, role _newrole)
internal
{
    if (identification[_user] == _oldrole) {
        identification[_user] = _newrole;
        if (identification[_user] == _newrole) {
            Sur(_user, _newrole, true);
        } else {
            Sur(_user, _newrole, false);
        }
    } else {
        Sur(_user, _newrole, false);
    }
}

/**
*switch to provider
*set price of wifi service
*set provider address behind wifi service
*only a receiver can call this i.e. provider or underservice cannot
*Deploy Wi-Fi hot spot and input SSID
*a failed call could be due to duplicated SSID
*or
*wrong initial role of message sender
*or
*mapping of provider and SSID has failed
*/
function surProvider (uint256 _price)
public
returns(bool success, address provider)
{
    _sur(msg.sender,role.ISRECEIVER,role.ISPROVIDER);
    priceOf[msg.sender] = _price;
    assert(priceOf[msg.sender] == _price);
    return (true, msg.sender);
}
/**
*switch to receiver
*delete price of SSID
*delete provider address behind SSID
*only provider with no user connected can call this 
*a failed call could be due to non-zero number of connected users
*or
*fail to delete infromation
*or
*wrong initial role of message sender
*/
function surReceiver (uint _numberOfUsers)
public
returns(bool success)
{
    require(_numberOfUsers == 0);
    _sur(msg.sender, role.ISPROVIDER, role.ISRECEIVER);
    return true;
}

/**
*link receiver to a provider
*/
//verify a ssid sent from front and tell the front whether there is a provider behind such ssid
//estimate balance of receiver => affordable data and tell front end ot set a counter
//when front end tell data limit is acheived, stop the service

/**
*internally defined estimation function
*/
function _affordableData (address _wallet, uint256 _price)
internal
view
returns (uint256 _volume)
{
    return balance[_wallet] / _price;
}

/**
*function that links message sender to the chosen provider
*
*/
function link (address _provider)
public
returns(address receiver, uint256 usageLimit)
{
    require(identification[_provider] == role.ISPROVIDER);
    require(identification[msg.sender] == role.ISRECEIVER);
    require(_affordableData(msg.sender, priceOf[_provider]) >= 1);
    identification[msg.sender] = role.UNDERSERVICE;
    providerOf[msg.sender] = _provider;
    return (msg.sender, _affordableData(msg.sender, priceOf[_provider]));
}

/**
*function to record data usage
*
*@param _usage data usage 
*data usage is in terms of MB
*/
function usageRecord (address _theOtherSide, uint256 _usage) 
public
returns (bool success)
{
    usageOf[msg.sender][_theOtherSide] = _usage;
    return true;
}

/**
*internal function
*compare data usage record by both provider and receiver's devices
*difference is smaller than tolerance will return true
*
*A problem is left for front implementation:
*How to let two devices send information to the contract.
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

//suspebd receiver (message sender)
//_sur(role.ISRECEIVER, role.UNDERSERVICE);

/**
*internally defined fee collector
*/
function _cashier (address _payer, uint256 _volume)
internal
returns (bool success)
{
    //_sur underservice back to receiver
    _transfer(_payer, providerOf[_payer], _volume * priceOf[providerOf[_payer]]);
    _sur(msg.sender, role.UNDERSERVICE, role.ISRECEIVER);
    //if the payer has payed successfully, it's role should be receiver again after execution of this function
    assert(identification[_payer] == role.ISRECEIVER);
    return true;
}

/**
*normal case used data < datalimit
*pay function. 
*
*
*/
function payAndLeave (uint256 _range, uint256 _usageLimit)
public
returns (bool success)
{
    //compare both sides' data usage record
    require(_tolerance(_range, _usageLimit));
    //pay the provider according to data usage recorded by the provider if tolerance is succeeded.
    _cashier (msg.sender, usageOf[providerOf[msg.sender]][msg.sender]);
    //clear data usage record on both sides
    usageOf[providerOf[msg.sender]][msg.sender] = 0;
    usageOf[msg.sender][providerOf[msg.sender]] = 0;
    //check if the clear operation if successful
    assert(usageOf[providerOf[msg.sender]][msg.sender] == usageOf[msg.sender][providerOf[msg.sender]]);
    //return on function success 
    return true;
}


}