// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;


// oracle contract
interface WeatherData {
  function getRainfall() external view returns(uint);
}



contract Insurance {


  // to hold address of insurance company wallet
  address public owner;


  // address of the oracle contract
  address WeatherDataAddr = 0x2B717f348592895258741b02c72CCED7Acb8dd5D;


  // Variable to store the value of the contract.  Updated whenver
  // funds are sent to or from contract.
  uint private contract_value;

  // This allows us to put "onlyOwner" in function signatures.
  // Its functionally the exact same as putting "require(msg.sender
  // == owner);" in the function body.
  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }

  // Default constructor, sets deploying wallet as owner.
  constructor() {
    owner = msg.sender;
  }


  // A deposit function which allows only the insurance wallet to
  // deposit funds into the contract.
  // Function to deposit Ether into this contract.
  // Call this function along with some Ether in msg.data.
  // The balance of this contract will be automatically updated.
  // This is the proper way for depositing from the owner to contract.
  // The only address that can call this is the insurers
  function insurerDeposit() onlyOwner public payable {
    // Update contract_value with the amount that was sent to the contract.
    contract_value += msg.value;
  }


  // Policy struct to hold policy owner's address, size of the policy
  // payout, and the policy premium paid by the owner (equal to 10%
  // of size) isValid is for cancelling policies.  When referencing
  // any policy we have to check or change isValid.
  struct Policy {
    address owner;
    uint size;
    uint premium;
    bool isValid;
  }


  // array for holding a list of all policies
  Policy[] private _policies;


  // returns the Policy given the owner
  // used like: Policy thisPolicy = _ownerToPolicy[_ownerAddress]
  mapping(address=>Policy) private _ownerToPolicy;


  // A way for new users create policies for themselves.
  function newPolicy(uint _size) public payable{

    // make sure user doesn't have existing policy
    require(!hasPolicy(msg.sender), "User already has an active policy");

    // Only allows function to continue if there are enough funds to
    // cover potential payout.
    require((_overhead() > _size), "Not enough funds in contract to cover potential payout.");

    // Solidity doesn't support floats or doubles and rounds down on
    // anything that would result in a float or double.
    // the default ether denomination is in wei (1e18 wei = 1 ether
    // so this will give us enough decimals of precision in terms of
    // ether.
    uint _premium = _size/10;

    // Makes sure that the user has at least paid the premium
    require(msg.value >= _premium, "User did not send enough funds to cover premium (10% of payout size).");

    // updates global contract_value variable
    contract_value += _premium;

    // Creates a new policy and adds it to the _policies array
    Policy memory _newPolicy = Policy(msg.sender, _size, _premium, true);
    _policies.push(_newPolicy);

    // Ties the new policy to the owner's address.
    // This way we can be given just an address and return its policy
    // ex: Policy bobsPolicy = _ownerToPolicy[bobsAddress];
    _ownerToPolicy[msg.sender] = _newPolicy;

  }

  // A private helper function to make sure the insurance company
  // should always have enough assets to cover the worst-case
  // scenario.
  // Returns the amount of money the contract would have left if all
  // policies were claimed.
  function _overhead() private view returns (uint) {

    uint _sizeSum;

    for (uint i = 0; i < _policies.length; i++){
      // only adds the _size to the _sizeSum if the policy is active
      if(_policies[i].isValid){
        _sizeSum += _policies[i].size;
      }
    }

    return (contract_value - _sizeSum);
  }


  // checks if policy is active or not by returning the policy's
  // "isValid" bool
  function hasPolicy(address checkOwner) public view returns (bool) {
    bool valid = _ownerToPolicy[checkOwner].isValid;
    return valid;
  }


  // A way for users to close out their policies. They should not
  // receive any refund on their premium for doing so.
  function closePolicy() public {

    // make sure caller actually has a policy
    require(hasPolicy(msg.sender), "User does not have a policy");

    // sets the policy's "isValid" to false indicating a cancelled policy
    Policy storage _cancelPolicy = _ownerToPolicy[msg.sender];
    _cancelPolicy.isValid = false;

  }


  // A way for the insurance company to cancel an existing policy. In
  // this case, the user should be refunded their premium.
  // Only the insurer is allowed to call this function.
  function cancelPolicy(address _user) onlyOwner public {

    // make sure _user address actually has a policy
    require(hasPolicy(_user), "User does not have a policy");

    // Get a reference of the policy we are going to cancel.
    // Using "storage" here because we want to change a value in
    // _cancelpolicy.
    // Use "memory" when we want to associate something but not
    // change the underlying structure.
    Policy storage _cancelPolicy = _ownerToPolicy[_user];

    // Makes sure the policy is valid
    require(_cancelPolicy.isValid, "Policy is not valid");

    // set the policy's isValid to false
    _cancelPolicy.isValid = false;

    // transfer _cancelPolicy.premium to _cancelPolicy.owner
    bool sent = payable(_cancelPolicy.owner).send(_cancelPolicy.premium);
    require(sent, "Failed to cancel policy");

    // We're moving funds out of the contract so we have to update
    // contract_value.
    contract_value -= _cancelPolicy.premium;

  }


  // A way for the insurance company to withdraw profits from the
  // contract and return them to their wallet.
  // Be careful with this function, the insurer should never be
  // over-exposed to existing policies.
  // Only the insurer can call this function.
  function collectProfit() onlyOwner public {

    // The amount of profit is equal to the amount of funds in the
    // contract - the sum of the size of all active policies.
    uint profit = _overhead();

    // Send profit from this contract to msg.sender
    bool sent = payable(owner).send(profit);
    require(sent, "Failed to collect profit");

    // Updates contract value because we are sending funds out of the contract.
    contract_value -= profit;

  }


  // emit event any time a policy claim is paid out
  event Payout(address indexed holder, uint amount);


  // A way for users to submit a claim. Users should only be able to
  // submit claims for their own accounts.
  // need to get their policy given the owner address.
  function claim() public {
    claimForUser(msg.sender);
  }


  // A function which submits a claim on behalf of another user. This
  // is the function we will call while grading your submission.
  function claimForUser(address _user) public{

    // Creates an instance of the WeatherData contract
    WeatherData w = WeatherData(WeatherDataAddr);

    // calls the getRainfall() function from WeatherData
    uint rainfall = w.getRainfall();

    // function will only execute if rainfall is below 50
    require((rainfall < 50), "Rainfall is not below 50mm, claim denied");

    // requires that user has a policy
    require(hasPolicy(_user), "User does not have a policy");

    // Gets a reference to the policy.
    // referencing using storage because we will have to update
    // "isValid".
    Policy storage _payoutPolicy = _ownerToPolicy[_user];

    // payout is triggered and funds are paid out to policy owner
    uint _amount = _payoutPolicy.size;
    bool sent = payable(_user).send(_amount);
    require(sent, "Failed to process claim");

    // updtate contract_value since we're sending funds out of the
    // contract.
    contract_value -= _amount;

    // emit Payout event since policy was claimed.
    emit Payout(_user, _amount);

    // updates isValid to indicate that the policy is paid out and no
    // longer active.
    _payoutPolicy.isValid = false;

  }

}
