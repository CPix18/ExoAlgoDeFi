//SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { StableValueCoin } from "../../src/StableValueCoin.sol";
import { Test, console2 } from "forge-std/Test.sol";
import { StdCheats } from "forge-std/StdCheats.sol";

contract StableValueCoinTest is StdCheats, Test {
    StableValueCoin svc;

    function setUp() public {
        svc = new StableValueCoin();
    }

    function testMustMintMoreThanZero() public {
        vm.prank(svc.owner());
        vm.expectRevert();
        svc.mint(address(this), 0);
    }

    function testMustBurnMoreThanZero() public {
        vm.startPrank(svc.owner());
        svc.mint(address(this), 420);
        vm.expectRevert();
        svc.burn(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanYouHave() public {
        vm.startPrank(svc.owner());
        svc.mint(address(this), 420);
        vm.expectRevert();
        svc.burn(500);
        vm.stopPrank();
    }

    function testCantMintToZeroAddress() public {
        vm.startPrank(svc.owner());
        vm.expectRevert();
        svc.mint(address(0), 420);
        vm.stopPrank();
    }
}
