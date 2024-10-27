//SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { MockV3Aggregator } from "../test/mocks/MockV3Aggregator.sol";
import { Script, console2 } from "lib/forge-std/src/Script.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

abstract contract CodeConstants {
    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 10_000e8;
    int256 public constant CBETH_USD_PRICE = 1100e8;
}

contract HelperConfig is CodeConstants, Script {
    error HelperConfig__InvalidChainId();

    NetworkConfig public activeNetworkConfig;

    struct NetworkConfig {
        address wethUsdPriceFeed;
        address cbethUsdPriceFeed;
        address cbbtcUsdPriceFeed;
        address weth;
        address cbeth;
        address cbbtc;
        uint256 deployerKey;
    }

    uint256 public DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    constructor() {
        if (block.chainid == 84_532) {
            activeNetworkConfig = getBaseSepoliaConfig();
        } else if (block.chainid == 1) {
            activeNetworkConfig = getMainnetConfig();
        } else if (block.chainid == 8453) {
            activeNetworkConfig = getBaseMainnetConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getMainnetConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            wethUsdPriceFeed: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419,
            cbethUsdPriceFeed: 0xF017fcB346A1885194689bA23Eff2fE6fA5C483b,
            cbbtcUsdPriceFeed: 0x2665701293fCbEB223D11A08D826563EDcCE423A,
            weth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            cbeth: 0xBe9895146f7AF43049ca1c1AE358B0541Ea49704,
            cbbtc: 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getBaseMainnetConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            wethUsdPriceFeed: 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70,
            cbethUsdPriceFeed: 0xd7818272B9e248357d13057AAb0B417aF31E817d,
            cbbtcUsdPriceFeed: 0x07DA0E54543a844a80ABE69c8A12F22B3aA59f9D,
            weth: 0x4200000000000000000000000000000000000006,
            cbeth: 0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22,
            cbbtc: 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getBaseSepoliaConfig() public view returns (NetworkConfig memory) {
        /* //Use for testing (fork-url stuff)
        vm.startBroadcast();
        console2.log("HC error");
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20Mock wethMock = new ERC20Mock("WETH", "WETH", msg.sender, 1000e8);

        MockV3Aggregator cbethUsdPriceFeed = new MockV3Aggregator(DECIMALS, CBETH_USD_PRICE);
        ERC20Mock cbethMock = new ERC20Mock("cbETH", "cbETH", msg.sender, 1000e8);

        MockV3Aggregator cbbtcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
        ERC20Mock cbbtcMock = new ERC20Mock("cbBTC", "cbBTC", msg.sender, 1000e8);
        vm.stopBroadcast();

        return NetworkConfig({
            wethUsdPriceFeed: address(ethUsdPriceFeed),
            weth: address(wethMock),
            cbethUsdPriceFeed: address(cbethUsdPriceFeed),
            cbeth: address(cbethMock),
            cbbtcUsdPriceFeed: address(cbbtcUsdPriceFeed),
            cbbtc: address(cbbtcMock),
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
        */

        return NetworkConfig({
            wethUsdPriceFeed: 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1,
            cbethUsdPriceFeed: 0x3c65e28D357a37589e1C7C86044a9f44dDC17134,
            cbbtcUsdPriceFeed: 0x0FB99723Aee6f420beAD13e6bBB79b7E6F034298,
            weth: 0x4200000000000000000000000000000000000006,
            cbeth: 0xB6DE1B1748d94046B2A6012259C1E6369e2907d7,
            cbbtc: 0xfAD1726FeAB7ee1f424B1a89B787B6BA3Bbb85d1,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory anvilNetworkConfig) {
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        ERC20Mock wethMock = new ERC20Mock("WETH", "WETH", msg.sender, 1000e8);

        MockV3Aggregator cbethUsdPriceFeed = new MockV3Aggregator(DECIMALS, CBETH_USD_PRICE);
        ERC20Mock cbethMock = new ERC20Mock("cbETH", "cbETH", msg.sender, 1000e8);

        MockV3Aggregator cbbtcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);
        ERC20Mock cbbtcMock = new ERC20Mock("cbBTC", "cbBTC", msg.sender, 1000e8);
        vm.stopBroadcast();

        return NetworkConfig({
            wethUsdPriceFeed: address(ethUsdPriceFeed),
            weth: address(wethMock),
            cbethUsdPriceFeed: address(cbethUsdPriceFeed),
            cbeth: address(cbethMock),
            cbbtcUsdPriceFeed: address(cbbtcUsdPriceFeed),
            cbbtc: address(cbbtcMock),
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
        });
    }
}
