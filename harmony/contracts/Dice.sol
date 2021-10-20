// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./6_Babilu.sol";

/**
 * @title Dice
 * A Dice machine that will spin a randomised dice
 */
contract Dice {

    event DiceRolled(address indexed player, uint tokensBet, uint256 result);
    event Winner(address indexed player, uint256 tokensBet, uint256 tokensWon);
    event Loser(address indexed player, uint256 tokensBet);



    BabiluToken public token;

    address private owner;

    uint256 currentJackpot = 0;
    uint256 private timesPlayed = 0;
    uint256 private playCost = 1;
    uint public diceSides = 0;

    constructor(uint _diceSides, uint256 _playCost, address _tokenContract) {
        token = BabiluToken(_tokenContract);
        diceSides = _diceSides;
        playCost = _playCost;
        owner = msg.sender;
    }

    function getTimesPlayed() public view returns (uint256) {
        return timesPlayed;
    }

    function getCostToPlay() public view returns (uint256) {
        return playCost;
    }

    function play(uint256 amountToBet) public payable {
        require(amountToBet > playCost, "Not enough to play");
        require(token.transferFrom(msg.sender, address(this), amountToBet));

        //Play game
        timesPlayed += 1;

        bytes32 _vrf = vrf();
        uint256 _res = expandValue(_vrf, 1) % diceSides;


        emit DiceRolled(msg.sender, amountToBet, _res);

        if(_res >= getWinNumber()) {
            win(msg.sender, amountToBet);
        } else {
            loss(msg.sender, amountToBet);
        }
    }

    function win(address winner, uint256 amountBet) private {
        uint256 amountToTransfer = amountBet * 2; //Double up
        uint256 contractBalance = token.balanceOf(address(this));
        if(contractBalance < amountToTransfer) {
            amountToTransfer = contractBalance;
        }

        token.transfer(winner, amountToTransfer);
        emit Winner(winner, amountBet, amountToTransfer);
        currentJackpot = currentJackpot - amountToTransfer; //Update jackpot
    }

    function loss(address loser, uint256 amountBet) private {
        emit Loser(loser, amountBet);
        currentJackpot = currentJackpot + amountBet; //Update jackpot
    }

    function getWinNumber() public view returns (uint256) {
        return diceSides/2;
    }

    function addFunds(uint256 amountToTransfer) public {
        require(token.transferFrom(msg.sender, address(this), amountToTransfer));
        currentJackpot = currentJackpot + amountToTransfer;
    }

    function removeFunds(uint256 amountToTransfer) public {
        require(msg.sender == owner, "Owner only");

        token.transfer(owner, amountToTransfer);
        currentJackpot = currentJackpot - amountToTransfer; //Update jackpot
    }


    function vrf() public view returns (bytes32 result) {
        uint[1] memory bn;
        bn[0] = block.number;
        assembly {
            let memPtr := mload(0x40)
            if iszero(staticcall(not(0), 0xff, bn, 0x20, memPtr, 0x20)) {
                invalid()

            }
            result := mload(memPtr)
        }
    }

    function expand(bytes32 randomValue, uint256 n) public pure returns (uint256[] memory expandedValues) {
        expandedValues = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            expandedValues[i] = expandValue(randomValue, i);
        }
        return expandedValues;
    }

    function expandValue(bytes32 randomValue, uint256 i) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(randomValue, i)));
    }

}
