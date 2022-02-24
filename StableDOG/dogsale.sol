pragma solidity ^0.6.2;
/* SPDX-License-Identifier: UNLICENSED */

contract StableDOGSale
{
    mapping(address => uint256) public telos_map;
    mapping(uint256 => address) public addr_counter_map;
    address public owner_addr;

    uint256 private minutes_in_a_week = 10080;
    uint256 public total_received_amount = 0;
    uint256 public address_counter = 0;
    uint256 public ending_timestamp;

    constructor() public 
    {
        owner_addr = msg.sender;
        ending_timestamp = now + minutes_in_a_week * 2 minutes;
    }

    modifier onlyOwner()
    {
        require (msg.sender == owner_addr);
        _;
    }

    receive() external payable 
    {
        require(now < ending_timestamp, "Sale has ended.");
        require(msg.value >= 50 ether, "Please send at least 50 TLOS.");
        require(total_received_amount+msg.value <= 15001 ether, "Your contribution would send the total over 15,001 TLOS. Try sending less." );

        telos_map[msg.sender] += msg.value;
        addr_counter_map[address_counter] = msg.sender;
        total_received_amount += msg.value;

        address_counter++;
    }

    function withdraw() public onlyOwner
    {
        address payable owner = address(uint160(msg.sender));
        owner.transfer(address(this).balance);
    }
}
