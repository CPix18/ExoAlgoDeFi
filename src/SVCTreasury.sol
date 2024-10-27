// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract SVCTreasury is Ownable {
    constructor() Ownable(msg.sender) { }

    // Deposit funds into the wallet
    function deposit() external payable { }

    // Allow wallet to receive ETH
    receive() external payable { }

    // Execute a transaction from the wallet
    function executeTransaction(address payable to, uint256 value, bytes calldata data) public onlyOwner {
        require(to != address(0), "Invalid address");
        (bool success,) = to.call{ value: value }(data);
        require(success, "Transaction failed");
    }

    // Withdraw ERC20 tokens from the wallet
    function withdrawERC20Token(IERC20 token, address to, uint256 amount) public onlyOwner {
        require(to != address(0), "Invalid address");
        require(token.transfer(to, amount), "Token transfer failed");
    }

    // Approve an allowance for an ERC20 token
    function approveToken(IERC20 token, address spender, uint256 amount) public onlyOwner {
        require(spender != address(0), "Invalid address");
        require(token.approve(spender, amount), "Token approve failed");
    }

    // Function to check the treasury balance for a specific token
    function getTokenBalance(IERC20 token) public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    // Function to get the ETH balance of the wallet
    function getETHBalance() public view returns (uint256) {
        return address(this).balance;
    }
}
