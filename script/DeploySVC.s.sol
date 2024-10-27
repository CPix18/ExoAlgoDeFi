//SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { Script, console2 } from "lib/forge-std/src/Script.sol";
import { StableValueCoin } from "../src/StableValueCoin.sol";
import { HelperConfig } from "./HelperConfig.s.sol";
import { SVCEngine } from "../src/SVCEngine.sol";
import { SVCTreasury } from "../src/SVCTreasury.sol";

contract DeploySVC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (StableValueCoin, SVCEngine, HelperConfig, SVCTreasury) {
        HelperConfig helperConfig = new HelperConfig();
        (
            address wethUsdPriceFeed,
            address cbethUsdPriceFeed,
            address cbbtcUsdPriceFeed,
            address weth,
            address cbeth,
            address cbbtc,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();
        tokenAddresses = [weth, cbeth, cbbtc];
        priceFeedAddresses = [wethUsdPriceFeed, cbethUsdPriceFeed, cbbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        SVCTreasury svct = new SVCTreasury();
        StableValueCoin svc = new StableValueCoin();
        SVCEngine svcEngine = new SVCEngine(tokenAddresses, priceFeedAddresses, address(svc), payable(address(svct)));
        svc.transferOwnership(address(svcEngine));
        //svct.transferOwnership(address(svcEngine));
        vm.stopBroadcast();
        return (svc, svcEngine, helperConfig, svct);
    }
}
