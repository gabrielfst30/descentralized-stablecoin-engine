// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    // Arrays to hold token and price feed addresses
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {

        // Get network configuration
        HelperConfig helperConfig = new HelperConfig();

        // Extract relevant addresses from the configuration
        (address wethUsdPriceFeed, address wbtcUsdPriceFeed, address weth, address wbtc, uint256 deployerKey) = helperConfig
            .activeNetworkConfig();

        // Populate the arrays with token and price feed addresses
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        // Broadcast transactions using the resolved deployer key to ensure ownership calls succeed
        vm.startBroadcast(deployerKey);

        // Resolve EOA address from deployerKey for proper ownership during broadcast
        address ownerEOA = vm.addr(deployerKey);

        // Deploy the Decentralized Stable Coin with the EOA as the initial owner
        DecentralizedStableCoin dsc = new DecentralizedStableCoin(ownerEOA);

        // Deploy the DSCEngine with the address of the DSC
        DSCEngine dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

        // Transfer ownership of the DSC to the DSCEngine
        dsc.transferOwnership(address(dscEngine));

        // End broadcast before returning so tests can use prank
        vm.stopBroadcast();

        return (dsc, dscEngine, helperConfig);
    }
}