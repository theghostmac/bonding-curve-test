// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { FixedPointMathLib } from "@solady/src/utils/FixedPointMathLib.sol";

/*
 * @title BondingCurve
 * @notice Implements an exponential bonding curve for token pricing.
 * @dev Uses the formula P = Ae^(Bx) where:
 * - P is the token price
 * - A is the initial price factor
 * - B is the exponential growth factor
 * - x is the current supply.
*/
contract BondingCurve {
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for int256;

    /// @notice Initial price factor (A in the formula)
    uint256 public immutable A;

    /// @notice Exponential growth factor (B in the formula)
    uint256 public immutable B;

    /// @notice Maximum allowed supply to prevent numerical overflow.
    uint public constant MAX_SUPPLY = 1_000_000_000e18; //  1 billion tokens.

    /// @notice Maximum transaction size to prevent price manipulation.
    uint256 public constant MAX_TX_SIZE = 10_000_000e18; // 10 million tokens.

    /// @dev Minimum price factor to ensure non-zero pricing.
    uint256 private constant MIN_A = 1e6; // 0.000001 USDC per token minimum start price.

    /// @dev Maximum price factor to prevent excessive pricing.
    uint256 private constant MAX_A = 1e12; // 1 USDC per token maximum start price.

    /// @dev Minimum growth factor to ensure price growth.
    uint256 private constant MIN_B = 1e12; // 0.000001 exponential growth minimum.

    /// @dev Maximum growth factor to prevent excessive growth
    uint256 private constant MAX_B = 1e15; // 0.001 exponential growth maximum

    /*
     * @notice Thrown when supply would exceed maximum
     * @param supply The requested supply amount
     * @param maximum The maximum allowed supply
    */
    error SupplyExceedsMaximum(uint256 supply, uint256 maximum);

    /*
     * @notice Thrown when transaction size exceeds maximum
     * @param size1 The requested transaction size
     * @param maximum The maximum allowed size
    */
    error TransactionTooLarge(uint256 size, uint256 maximum);

    /*
     * @notice Thrown when parameter is outside allowed range
     * @param value The provided value
     * @param minimum The minimum allowed value
     * @param maximum The maximum allowed value
    */
    error ParameterOutOfRange(uint256 value, uint256 minimum, uint256 maximum);

    /*
     * @notice Creating a new bonding curve with specified parameters.
     * @param _a Initial price factor
     * @param _b Exponential growth facto
    */
    constructor(uint256 _a, uint256 _b) {
        // Validate A is within safe range
        if (_a < MIN_A || _a > MAX_A) {
            revert ParameterOutOfRange(_a, MIN_A, MAX_A);
        }

        // Validate B is within safe range
        if (_b < MIN_B || _b > MAX_B) {
            revert ParameterOutOfRange(_b, MIN_B, MAX_B);
        }

        A = _a;
        B = _b;
    }

    /*
     * @notice Calculates how many payment tokens would be received for selling tokens.
     * @dev Formula: deltaY = (A/B) * (e^(B*x0) - e^(B*x1))
     *  - where x1 = x0 - deltaX
     * @param x0 Current token supply
     * @param deltaX Number of tokens to sell
     * @param deltaY Amount of payment tokens to receive.
    */
    function getFundsReceived(uint256 x0, uint256 deltaX) public view returns (uint256 deltaY) {
        // Validate maximum supply
        if (x0 > MAX_SUPPLY) {
            revert SupplyExceedsMaximum(x0, MAX_SUPPLY);
        }

        // Validate transaction size.
        if (deltaX > MAX_TX_SIZE) {
            revert TransactionTooLarge(deltaX, MAX_TX_SIZE);
        }

        // Ensure selling amount doesn't exceed supply
        require(x0 >= deltaX, "Cannot sell more than exists");

        // Calculate e^(B*x0)
        int256 exp_b_x0 = (int256(B.mulWad(x0))).expWad();

        // Calculate e^(B*x1) where x1 = x0 - deltaX
        int256 exp_b_x1 = (int256(B.mulWad(x0 - deltaX))).expWad();

        // Calculate e^(B*x0) - e^(B*x1)
        uint256 delta = uint256(exp_b_x0 - exp_b_x1);

        // Calculate final amount: (A/B) * delta
        deltaY = A.fullMulDiv(delta, B);
    }

    /**
     * @notice Calculates how many tokens can be purchased with given payment amount
     * @dev Formula: deltaX = (ln(e^(B*x0) + (deltaY*B/A)))/B - x0
     * @param x0 Current token supply
     * @param deltaY Amount of payment tokens to spend
     * @return deltaX Number of tokens that can be purchased
     */
    function getAmountOut(uint256 x0, uint256 deltaY) public view returns (uint256 deltaX) {
        // Validate maximum supply
        if (x0 > MAX_SUPPLY) {
            revert SupplyExceedsMaximum(x0, MAX_SUPPLY);
        }

        // Calculate e^(B*x0)
        uint256 exp_b_x0 = uint256((int256(B.mulWad(x0))).expWad());

        // Calculate e^(B*x0) + (deltaY*B/A)
        uint256 exp_b_x1 = exp_b_x0 + deltaY.fullMulDiv(B, A);

        // Calculate (ln(exp_b_x1)/B) - x0
        deltaX = uint256(int256(exp_b_x1).lnWad()).divWad(B) - x0;

        // Validate transaction size
        if (deltaX > MAX_TX_SIZE) {
            revert TransactionTooLarge(deltaX, MAX_TX_SIZE);
        }

        // Validate final supply doesn't exceed maximum
        if (x0 + deltaX > MAX_SUPPLY) {
            revert SupplyExceedsMaximum(x0 + deltaX, MAX_SUPPLY);
        }
    }

    /**
     * @notice Calculates the current token price at a given supply point
     * @dev Formula: P = Ae^(Bx)
     * @param x Current token supply
     * @return price Current token price
     */
    function getCurrentPrice(uint256 x) public view returns (uint256 price) {
        // Calculate e^(B+x)
        int256 exp_b_x = (int256(B.mulWad(x))).expWad();

        // Calculate A * e^(B*x)
        price = A.mulWad(uint256(exp_b_x));
    }

    /**
     * @notice Simulates the price impact of a buy order
     * @param x0 Current token supply
     * @param deltaX Size of potential purchase
     * @return priceImpact Percentage price increase (in basis points)
     */
    function simulatePriceImpact(uint256 x0, uint256 deltaX) external view returns (uint256 priceImpact) {
        uint256 initialPrice = getCurrentPrice(x0);
        uint256 finalPrice = getCurrentPrice(x0 + deltaX);

        // Calculate price impact in basis points (1 bp = 0.01%)
        priceImpact = ((finalPrice - initialPrice) * 10000) / initialPrice;
    }
}
