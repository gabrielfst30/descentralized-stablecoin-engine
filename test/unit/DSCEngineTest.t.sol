// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer; // DeployDSC contract reference
    DecentralizedStableCoin dsc; // DecentralizedStableCoin contract reference
    DSCEngine dscEngine; // DSCEngine contract reference
    HelperConfig helperConfig; // HelperConfig contract reference
    address ethUsdPriceFeed; // ETH/USD price feed address
    address weth; // WETH token address

    // A user address for testing
    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether; // 10 ETH as collateral
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether; // Initial ERC20 balance for USER

    // Setup function to initialize the deployer
    function setUp() external {
        // Create a new instance of the DeployDSC contract
        deployer = new DeployDSC();

        // Deploy the DSC and DSCEngine contracts
        (dsc, dscEngine, helperConfig) = deployer.run(); 

        // Get the WETH/USD price feed and WETH address
        (ethUsdPriceFeed, , weth, , ) = helperConfig.activeNetworkConfig(); 

        if (block.chainid == 31337) {
            vm.deal(USER, STARTING_ERC20_BALANCE);
        }
        // Mint some WETH tokens to the USER for testing (as the deployer/contract owner)
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    /** @dev Price Tests */
    function testGetUsdValue() public {
        uint256 ethAmount = 15e18; // 15 ETH in wei
        uint256 expectedUsdValue = 30000e18; // Expected USD value
        uint256 actualUsdValue = dscEngine.getUsdValue(weth, ethAmount); // Get actual USD value
    
        assertEq(actualUsdValue, expectedUsdValue);
    }

    /** @dev depositCollateral Tests */
    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);

        /// @dev Approves dscEngine to spend up to AMOUNT_COLLATERAL of WETH tokens from USER
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);

        // Expect the depositCollateral function to revert with the DSCEngine__NeedsMoreThanZero error
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);

        // Attempt to deposit zero collateral, which should trigger the revert
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }   
}