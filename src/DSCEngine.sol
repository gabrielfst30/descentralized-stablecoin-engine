// SPDX-License-Identifier: MIT

// Layout of the contract file:
// version
// imports
// errors
// interfaces, libraries, contract

// Inside Contract:
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.20;

/**
 * @title Decentralized Stable Coin
 * @author Gabriel Santa Ritta
 * 
 * Peg: 1 DSC = 1 USD
 * This stablecoin has the properties:
 * - Collateral: Exogenous stable coin (ETH and BTC)
 * - Minting: Algorithmic
 * - Dollar Pegged
 * 
 * It is similar to DAI if DAI had no governance, no fees, and only used ETH and BTC as collateral.
 * 
 * Our DSC system should always be overcollateralized. At no point, should the value of 
   all the collateral <= the value of all the DSC.
 * 
 * @notice This contract is the core of the DSC System.
 */

contract DSCEngine {
    // deposit collateral and mint DSC
    function depositCollateralAndMintDsc() external {}

    // deposit collateral only
    function depositCollateral() external {}

    function redeemCollateral() external {}

    function mintDsc() external {}

    // redeem collateral by burning DSC
    function redeemCollateralForDsc() external {}

    // burn DSC tokens
    function burnDsc() external {}

    // liquidate undercollateralized users
    function liquidate() external {}

    function getHealthFactor() external view {}

}