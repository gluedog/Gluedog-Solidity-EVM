pragma solidity ^0.6.0;
/* SPDX-License-Identifier: MIT */

contract xSafeMath 
{
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "xSafeMath: addition overflow.");
        return c;}

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "xSafeMath: subtraction overflow.");}

    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;
        return c;}

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {return 0;}
        uint256 c = a * b;
        require(c / a == b, "xSafeMath: multiplication overflow.");
        return c;}

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "xSafeMath: division by zero.");}

    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        return c;}

    function percent(uint numerator, uint denominator, uint precision) internal pure returns(uint quotient) 
    {   uint _numerator  = numerator * 10 ** (precision+1);
        uint _quotient =  ((_numerator / denominator) + 5) / 10;
        return ( _quotient);}
}

interface XIERC20
{
    function transfer(address _to, uint _value) external returns (bool success);
    function balanceOf(address _owner) external returns (uint256 balance);
}

contract StableDOGAirdrop is xSafeMath
{
    XIERC20 private DOG_CALL;
    XIERC20 private STABLEDOG_CALL;

    bool public is_frozen = false;

    mapping(address => bool)    public registered;
    mapping(address => bool)    public has_claimed;

    mapping(address => uint256) public claimed_airdrop_rewards;

    mapping(uint256 => address) public registered_addresses_counter_map;

    mapping(address => uint256) public dog_snapshot;
    mapping(uint256 => address) public dog_snapshot_addresses_counter;

    mapping(address => uint256) public unclaimed_airdrop_rewards;

    address public owner_addr;

    uint256 public address_counter = 0;
    uint256 public dog_snapshot_counter = 0;

    uint8   public snapshot_run_state = 0;
    uint256 public ending_timestamp = 1646917200; // Thursday, 10 March 2022 13:00:00

    uint256 public minimum_dog_required = 2500000000000000000000; /* 2500 DOG */
    uint256 public total_dog_registered_supply; /* How many dogs are actually registered for the airdrop? */
    uint256 public total_airdrop_rewards; /* How much are we actually giving out of the 15,000 StableDOGs ? */

    address public stabledog_contract; /* Needs to be set. */
    address public dog_contract;       /* Needs to be set. */
    address public airdrop_contract;

    constructor() public 
    {   
        owner_addr = msg.sender;
        airdrop_contract = address(this); /* Own address. */
    }

    modifier onlyOwner() {require (msg.sender == owner_addr);_;}

    receive() external payable 
    {
        require(!is_frozen,"error: contract is frozen");
        require(now < ending_timestamp, "error: snapshot deadline has passed.");
        require(msg.value >= 0.1 ether, "error: please send at least 0.1 TLOS.");
        require(registered[msg.sender] == false, "error: user is already registered.");

        registered_addresses_counter_map[address_counter] = msg.sender;
        registered[msg.sender] = true;

        address_counter++;
    }

    function get_snapshot_balances() public onlyOwner
    {
        require(stabledog_contract != address(0), "error: no StableDOG contract is set.");
        require(snapshot_run_state == 0, "error: balances snapshot was already taken.");
        for (uint i = 0; i < address_counter; i++)
        {   
            uint256 balance = DOG_CALL.balanceOf(registered_addresses_counter_map[i]);

            if (balance >= minimum_dog_required)
            {   /* -_- */
                dog_snapshot[registered_addresses_counter_map[i]] = balance;
                dog_snapshot_addresses_counter[dog_snapshot_counter] = registered_addresses_counter_map[i];
                dog_snapshot_counter++;
                total_dog_registered_supply += balance;
            }
        }
        snapshot_run_state = 1; /* Balances are done. */
    }

    function get_snapshot_rewards() public onlyOwner
    {
        require(stabledog_contract != address(0), "error: no StableDOG contract is set.");
        require(snapshot_run_state == 1, "error: snapshot run state must be 1.");
        uint256 total_airdropped_stabledog = 15000000000000000000000; /* 15,000 stabledogs */

        for (uint i = 0; i < dog_snapshot_counter; i++)
        {   /* A work-around because solidity does not allow floating point numbers. */
            uint256 user_share_of_pool = percent(dog_snapshot[dog_snapshot_addresses_counter[i]],total_dog_registered_supply,4);
            uint256 user_stabledog_reward = div(mul(user_share_of_pool,total_airdropped_stabledog),10000);
            unclaimed_airdrop_rewards[dog_snapshot_addresses_counter[i]] = user_stabledog_reward;
            total_airdrop_rewards += user_stabledog_reward;
        }
        snapshot_run_state = 2; /* Snapshot rewards are done. */
    }

    function withdraw() public onlyOwner
    {
        address payable owner = address(uint160(msg.sender));
        owner.transfer(address(this).balance);
    }

    function claim() public /* Much requirements here, wow */
    {   require(!is_frozen, "error: contract is frozen");
        require(stabledog_contract != address(0), "error: no StableDOG contract is set.");
        require(now > ending_timestamp, "error: can't claim yet, come back later.");
        require(has_claimed[msg.sender] == false, "error: already claimed.");
        require(unclaimed_airdrop_rewards[msg.sender] > 0, "error: nothing to claim.");
        require(snapshot_run_state == 2, "error: can't claim before the snapshot is taken.");
        require(STABLEDOG_CALL.balanceOf(airdrop_contract) >= unclaimed_airdrop_rewards[msg.sender], "error: not enough tokens left to give out, contact an administrator.");

        /* All good! Send the user his StableDOG. */
        STABLEDOG_CALL.transfer(msg.sender, unclaimed_airdrop_rewards[msg.sender]);
        claimed_airdrop_rewards[msg.sender] = unclaimed_airdrop_rewards[msg.sender];
        has_claimed[msg.sender] = true;
        unclaimed_airdrop_rewards[msg.sender] = 0;
    }

    function SET_SNAPSHOT_STATE(uint8 new_state) public onlyOwner {snapshot_run_state = new_state;}
    function SET_STABLEDOG(address stabledog) public onlyOwner {stabledog_contract = stabledog; STABLEDOG_CALL = XIERC20(stabledog);}
    function SET_DOG(address dog) public onlyOwner {dog_contract = dog; DOG_CALL = XIERC20(dog);}
    function SET_FREEZE(bool frozen) public onlyOwner {is_frozen = frozen;}
    function SET_ENDING_TIMESTAMP(uint256 timestamp) public onlyOwner {ending_timestamp = timestamp;}
}
