// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { ERC20Burnable, ERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { MockV3Aggregator } from "./MockV3Aggregator.sol";

/*
 * @title Stable Value Coin
 * @author Collin Pixley
 * Collateral: Exogenous Crypto Collateral
 * Minting (Stability Mechanism): Decentralized (Algorithmic)
 * Value (Relative Stability): Soft Peg to Grocery Index
 *
* This is the contract meant to be owned by SVCEngine. It is a ERC20 token that can be minted and burned by the
SVCEngine smart contract.
 */
contract MockMoreDebtSVC is ERC20Burnable, Ownable {
    error StableValueCoin__AmountMustBeMoreThanZero();
    error StableValueCoin__BurnAmountExceedsBalance();
    error StableValueCoin__NotZeroAddress();

    address mockAggregator;

    constructor(address _mockAggregator) ERC20("Stable Value Coin", "SVC") Ownable(msg.sender) {
        mockAggregator = _mockAggregator;
    }

    function burn(uint256 _amount) public override onlyOwner {
        // crash the price
        MockV3Aggregator(mockAggregator).updateAnswer(0);
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
        return true;
    }
}
