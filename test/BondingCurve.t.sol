// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/BondingCurve.sol";

contract BondingCurveTest is Test {
    BondingCurve public curve;

    // Test parameters
    uint256 constant A = 1e6;  // 0.000001 USDC starting price
    uint256 constant B = 1e12; // 0.000001 growth rate

    function setUp() public {
        curve = new BondingCurve(A, B);
    }

    function testInitialPrice() public {
        uint256 price = curve.getCurrentPrice(0);
        assertEq(price, A, "Initial price should equal A");
    }

    function testSimpleBuy() public {
        // Try to buy with 1 USDC (1e6 units) at 0 supply
        uint256 tokensOut = curve.getAmountOut(0, 1e6);
        assertGt(tokensOut, 0, "Should get tokens for 1 USDC");

        // Calculate price impact
        uint256 impact = curve.simulatePriceImpact(0, tokensOut);
        console.log("Price impact (basis points):", impact);

        // Get funds needed to buy these tokens
        uint256 fundsNeeded = curve.getFundsReceived(tokensOut, tokensOut);
        assertApproxEqualRel(fundsNeeded, 1e6, 1e16, "Should cost ~1 USDC");
    }

    function testPriceIncrease() public {
        uint256 price1 = curve.getCurrentPrice(1e18);    // 1 token
        uint256 price2 = curve.getCurrentPrice(10e18);   // 10 tokens
        uint256 price3 = curve.getCurrentPrice(100e18);  // 100 tokens

        assertGt(price2, price1, "Price should increase with supply");
        assertGt(price3, price2, "Price should increase with supply");

        console.log("Price at 1 token:", price1);
        console.log("Price at 10 tokens:", price2);
        console.log("Price at 100 tokens:", price3);
    }

    function testMaxSupply() public {
        // Try to calculate buy amount that would exceed max supply
        vm.expectRevert(abi.encodeWithSelector(BondingCurve.SupplyExceedsMaximum.selector, 1e27 + 1, 1e27));
        curve.getAmountOut(1e27, 1e6);
    }

    function testMaxTransaction() public {
        // Try to sell more than max transaction size
        vm.expectRevert(abi.encodeWithSelector(BondingCurve.TransactionTooLarge.selector, 11e24, 10e24));
        curve.getFundsReceived(100e24, 11e24);
    }

    // Fuzz test to verify curve properties
    function testFuzz_PriceAlwaysIncreases(uint256 supply, uint256 increment) public {
        // Bound inputs to reasonable ranges
        supply = bound(supply, 0, 1e24);
        increment = bound(increment, 1e6, 1e12);

        uint256 price1 = curve.getCurrentPrice(supply);
        uint256 price2 = curve.getCurrentPrice(supply + increment);

        assertGe(price2, price1, "Price must increase with supply");
    }

    // Test selling mechanism
    function testSellTokens() public {
        uint256 initialSupply = 1000e18;
        uint256 sellAmount = 100e18;

        uint256 fundsReceived = curve.getFundsReceived(initialSupply, sellAmount);
        assertGt(fundsReceived, 0, "Should receive funds for tokens");

        // Verify price impact
        uint256 price1 = curve.getCurrentPrice(initialSupply);
        uint256 price2 = curve.getCurrentPrice(initialSupply - sellAmount);
        assertLt(price2, price1, "Price should decrease after sell");
    }

    // Test buy/sell symmetry
    function testBuySellSymmetry() public {
        uint256 initialSupply = 1000e18;
        uint256 buyAmount = 100e18;

        // Calculate cost to buy tokens
        uint256 buyCost = curve.getFundsReceived(initialSupply + buyAmount, buyAmount);

        // Calculate funds received from selling same amount
        uint256 sellReturn = curve.getFundsReceived(initialSupply + buyAmount, buyAmount);

        // Should be approximately equal (small difference due to precision)
        assertApproxEqualRel(buyCost, sellReturn, 1e16, "Buy/sell should be symmetric");
    }

    // Visual test to output curve shape
    function testVisualCurve() public view {
        console.log("\nBonding Curve Shape (supply -> price):");
        for(uint256 i = 0; i <= 10; i++) {
            uint256 supply = i * 100e18;  // 0 to 1000 tokens
            uint256 price = curve.getCurrentPrice(supply);
            console.log(supply / 1e18, "tokens ->", price, "price");
        }
    }
}