// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {
    // struct to hold all the network configuration
    struct NetworkConfig {
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    // constants for mock price feeds
    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 1000e8;
    uint256 public DEFAULT_ANVIL_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    // defining default values for our struct
    NetworkConfig public activeNetworkConfig;

    // constructor to initialize the network configuration based on the chain ID
    constructor() {
       if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    // Sepolia network configuration
    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return
            NetworkConfig({
                wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
                wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
                weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
                wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
                deployerKey: vm.envUint("PRIVATE_KEY_SEPOLIA")
            });
    }

    // Anvil local network configuration
    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        // if we already have a configuration, return it
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }

        // otherwise, deploy mocks and create a new configuration
        vm.startBroadcast();
        /** @dev WETH/USD */
        // Deploy mock WETH/USD price feed
        MockV3Aggregator wethUsdPriceFeed = new MockV3Aggregator(
            DECIMALS,
            ETH_USD_PRICE
        );
        // Deploy weth token mocks
        ERC20Mock wethMock = new ERC20Mock();

        /** @dev WBTC/USD */
        // Deploy mock WBTC/USD price feed
        MockV3Aggregator wbtcUsdPriceFeed = new MockV3Aggregator(
            DECIMALS,
            BTC_USD_PRICE
        );
        // Deploy wbtc token mocks
        ERC20Mock wbtcMock = new ERC20Mock();
        vm.stopBroadcast();

        return
            NetworkConfig({
                wethUsdPriceFeed: address(wethUsdPriceFeed),
                wbtcUsdPriceFeed: address(wbtcUsdPriceFeed),
                weth: address(wethMock),
                wbtc: address(wbtcMock),
                deployerKey: DEFAULT_ANVIL_KEY
            });
    }
}
