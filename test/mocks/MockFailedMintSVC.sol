// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { ERC20Burnable, ERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract MockFailedMintSVC is ERC20Burnable, Ownable {
    error StableValueCoin__AmountMustBeMoreThanZero();
    error StableValueCoin__BurnAmountExceedsBalance();
    error StableValueCoin__NotZeroAddress();

    constructor() ERC20("Stable Value Coin", "SVC") Ownable(msg.sender) { }

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert StableValueCoin__AmountMustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert StableValueCoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert StableValueCoin__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert StableValueCoin__AmountMustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return false;
    }
}
