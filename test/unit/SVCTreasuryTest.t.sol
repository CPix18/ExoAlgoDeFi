// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test, console2 } from "lib/forge-std/src/Test.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { SVCTreasury } from "../../src/SVCTreasury.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { DeploySVC } from "../../script/DeploySVC.s.sol";
import { SVCEngine } from "../../src/SVCEngine.sol";
import { HelperConfig } from "../../script/HelperConfig.s.sol";
import { StableValueCoin } from "../../src/StableValueCoin.sol";

contract SVCTreasuryTest is StdCheats, Test {
    address public owner;
    StableValueCoin public svc;
    SVCEngine public svce;
    HelperConfig public helperConfig;
    SVCTreasury public svct;
    address public user = address(1);
    address public ethUsdPriceFeed;
    address public weth;
    address public cbethUsdPriceFeed;
    address public cbeth;
    address public cbbtcUsdPriceFeed;
    address public cbbtc;
    uint256 public deployerKey;
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() public {
        DeploySVC deployer = new DeploySVC();
        (svc, svce, helperConfig, svct) = deployer.run();
        (ethUsdPriceFeed, cbethUsdPriceFeed, cbbtcUsdPriceFeed, weth, cbeth, cbbtc, deployerKey) =
            helperConfig.activeNetworkConfig();
        owner = vm.addr(deployerKey);
        console2.log("Owner address", owner);
        if (block.chainid == 84_532) {
            vm.deal(user, STARTING_USER_BALANCE);
        }
        ERC20Mock(weth).mint(user, STARTING_USER_BALANCE);
        ERC20Mock(weth).mint(owner, STARTING_USER_BALANCE);
    }

    function testDepositETH() public {
        vm.startPrank(user);
        vm.deal(user, STARTING_USER_BALANCE);
        svct.deposit{ value: 1 ether }();
        assertEq(address(svct).balance, 1 ether);
    }

    function testGetBalance() public {
        vm.startPrank(owner);
        // Deposit some tokens into the treasury first
        ERC20Mock(weth).approve(owner, STARTING_USER_BALANCE);
        ERC20Mock(weth).transfer(address(svct), STARTING_USER_BALANCE);
        vm.stopPrank();

        uint256 balance = svct.getTokenBalance(IERC20(weth));
        assertEq(balance, STARTING_USER_BALANCE);
    }
}
