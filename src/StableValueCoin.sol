//SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { ERC20Burnable, ERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol"; // centralization risk
import { console2 } from "lib/forge-std/src/Script.sol";

contract StableValueCoin is ERC20Burnable, Ownable {
    ///////////////////
    // Errors
    ///////////////////
    error StableValueCoin__MustBeMoreThanZero();
    error StableValueCoin__BurnAmountExceedsBalance();
    error StableValueCoin__NotZeroAddress();

    ///////////////////
    // Functions
    ///////////////////
    constructor() ERC20("Stable Value Coin", "SVC") Ownable(msg.sender) { }
    //change Ownable(0x00...) to address owner (anvil vs testnet addy)

    /*
     * @title Stable Value Coin
     * @author Collin Pixley
     * Collateral: Exogenous (ETH)
     * Minting: Algorithmic
     * Relative Stability: Soft Peg to Grocery Index
     * Governed by SVCEngine
     * Based on Code Audited by CodeHawks on 8-25-23
     * @disclaimer THIS CODE IS NOT AUDITED
     */

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert StableValueCoin__MustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert StableValueCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        console2.log("Minting to:", _to);
        console2.log("Minting amount:", _amount);

        if (_to == address(0)) {
            revert StableValueCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert StableValueCoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
