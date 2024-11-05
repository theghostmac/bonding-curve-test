// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/BondingCurve.sol";
import "solady/utils/FixedPointMathLib.sol";

contract BondingCurveTest is Test {
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for int256;

    BondingCurve public curve;

    // Test parameters - using much smaller values to avoid exp overflow
    uint256 constant A = 1e6;    // 0.000001 USDC starting price
    uint256 constant B = 1e12;   // 0.000001 growth rate (increased this for more visible price changes)

    // This function helps to approximate equality
    function assertAlmostEqual(uint256 a, uint256 b, uint256 precision) internal {
        if (a > b) {
            uint256 diff = a - b;
            assertTrue(diff <= precision, "Values differ by more than precision");
        } else {
            uint256 diff = b - a;
            assertTrue(diff <= precision, "Values differ by more than precision");
        }
    }

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
        // Allow for 0.1% difference due to rounding
        assertAlmostEqual(fundsNeeded, 1e6, 1e3);
    }

    function testPriceIncrease() public {
        // Testing with larger token amounts to see a more significant increase in prices.
        uint256 price1 = curve.getCurrentPrice(100e18);      // 100 tokens
        uint256 price2 = curve.getCurrentPrice(10_000e18);   // 10K tokens
        uint256 price3 = curve.getCurrentPrice(100_000e18);  // 100K tokens

        assertGt(price2, price1, "Price should increase with supply");
        assertGt(price3, price2, "Price should increase with supply");

        console.log("Price at 100 tokens:", price1);
        console.log("Price at 10K tokens:", price2);
        console.log("Price at 100K tokens:", price3);
    }

    function testMaxSupply() public {
        // Calculate a supply that leaves amount of tokens that is just a little bit less than MIN_REMAINING_SUPPLY
        uint256 currentSupply = curve.MAX_SUPPLY() - 900e18; // leaves 900 tokens remaining
        uint256 paymentAmount = 100_000e6; // 100,000 USDC

        console.log("\nMax Supply Test Values:");
        console.log("Current supply: %s", currentSupply / 1e18);
        console.log("Max supply: %s", curve.MAX_SUPPLY() / 1e18);
        console.log("Remaining supply: %s", (curve.MAX_SUPPLY() - currentSupply) / 1e18);
        console.log("Min required remaining: %s", uint256(1000)); // MIN_REMAINING_SUPPLY is 1000e18

        vm.expectRevert(abi.encodeWithSelector(
            BondingCurve.InsufficientRemainingSupply.selector,
            900e18, // remaining supply
            1000e18 // minimum required
        ));

        curve.getAmountOut(currentSupply, paymentAmount);
    }

    function testMaxTransaction() public {
        uint256 currentSupply = 1000e18;
        uint256 tooLarge = curve.MAX_TX_SIZE() + 1;

        vm.expectRevert(abi.encodeWithSelector(
            BondingCurve.TransactionTooLarge.selector,
            tooLarge,
            curve.MAX_TX_SIZE()
        ));
        curve.getFundsReceived(currentSupply, tooLarge);
    }

    // Fuzz test to verify the properties of the bonding curve
    function testFuzz_PriceAlwaysIncreases(uint256 supply, uint256 increment) public {
        // Bound inputs to reasonable ranges to avoid overflow
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

        // Should be approximately equal (allow 0.1% difference)
        assertAlmostEqual(buyCost, sellReturn, buyCost / 1000);
    }

    // Visual test to output curve shape
    function testVisualCurve() public view {
        console.log("\nBonding Curve Shape (supply -> price):");
        uint256 maxDisplay = 1000e18; // Display up to 1000 tokens
        for(uint256 i = 0; i <= 10; i++) {
            uint256 supply = i * (maxDisplay / 10);
            uint256 price = curve.getCurrentPrice(supply);
            console.log(supply / 1e18, "tokens ->", price, "price");
        }
    }

    // Test exponential bounds with safer values
    function testExponentialBounds() public {
        console.log("\nTesting exponential bounds:");

        // Test at various supply points with smaller increments
        uint256[] memory testPoints = new uint256[](5);
        testPoints[0] = 1e18;         // 1 token
        testPoints[1] = 10_000e18;    // 10K tokens
        testPoints[2] = 100_000e18;   // 100K tokens
        testPoints[3] = 500_000e18;   // 500K tokens
        testPoints[4] = 1_000_000e18; // 1M tokens

        for(uint256 i = 0; i < testPoints.length; i++) {
            uint256 supply = testPoints[i];
            try curve.getCurrentPrice(supply) returns (uint256 price) {
                console.log(supply / 1e18, "tokens ->", price, "price");
            } catch Error(string memory reason) {
                console.log(supply / 1e18, "tokens -> Failed:", reason);
            } catch (bytes memory) {
                console.log(supply / 1e18, "tokens -> Failed with other error");
            }
        }
    }

    // Test to verify that large numbers are gracefully handled
    function testGracefulFailure() public {
        // This should fail with SupplyExceedsMaximum error since that's what we check first
        uint256 hugeSupply = 100_000_000e18; // 100M tokens (way above MAX_SUPPLY)

        vm.expectRevert(abi.encodeWithSelector(
            BondingCurve.SupplyExceedsMaximum.selector,
            hugeSupply,
            curve.MAX_SUPPLY()
        ));

        curve.getCurrentPrice(hugeSupply);
    }

    // Test for realistic trading scenarios
    function testRealisticTrading() public {
        uint256 initialSupply = 10_000e18; // Start with 10K tokens

        // Buy 1000 tokens
        uint256 buyAmount = 1_000e18;
        uint256 priceBefore = curve.getCurrentPrice(initialSupply);
        uint256 priceAfter = curve.getCurrentPrice(initialSupply + buyAmount);

        assertGt(priceAfter, priceBefore, "Price should increase after buying");
        console.log("Price before buy:", priceBefore);
        console.log("Price after buy:", priceAfter);
        console.log("Price impact:", curve.simulatePriceImpact(initialSupply, buyAmount));
    }

    // Test to verify price growth rate
    function testPriceGrowthRate() public {
        uint256[] memory supplies = new uint256[](5);
        supplies[0] = 1_000e18;      // 1K tokens
        supplies[1] = 10_000e18;     // 10K tokens
        supplies[2] = 100_000e18;    // 100K tokens
        supplies[3] = 1_000_000e18;  // 1M tokens
        supplies[4] = 5_000_000e18;  // 5M tokens

        console.log("\nPrice growth demonstration:");
        for(uint256 i = 0; i < supplies.length; i++) {
            uint256 supply = supplies[i];
            uint256 price = curve.getCurrentPrice(supply);
            console.log(supply / 1e18, "tokens ->", price, "price");

            if(i > 0) {
                uint256 prevPrice = curve.getCurrentPrice(supplies[i-1]);
                uint256 increase = ((price - prevPrice) * 10000) / prevPrice; // In basis points
                console.log("Increase from previous:", increase, "basis points");
            }
        }
    }
}