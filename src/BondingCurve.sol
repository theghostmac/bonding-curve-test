// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "solady/utils/FixedPointMathLib.sol";

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
    uint256 public constant MAX_SUPPLY = 10_000_000e18; // 10M tokens

    /// @notice Maximum transaction size to prevent price manipulation.
    uint256 public constant MAX_TX_SIZE = 1_000_000e18; // 1M tokens

    /// @dev Maximum exponent allowed to prevent overflow
    int256 public constant MAX_EXP_VALUE = 50e18; // Maximum safe value for expWad

    /// @dev Minimum remaining supply before all purchases are rejected
    uint256 public constant MIN_REMAINING_SUPPLY = 1000e18;

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

    /// @notice Thrown when an exponent calculation would exceed safe bounds
    /// @param value The exponent value that exceeded the maximum
    /// @param maximum The maximum allowed exponent value
    error ExponentTooLarge(int256 value, int256 maximum);

    /// @notice Thrown when remaining supply is below minimum threshold for purchases
    /// @param remaining Current remaining supply
    /// @param minimum Minimum required remaining supply
    error InsufficientRemainingSupply(uint256 remaining, uint256 minimum);

    /*
     * @notice Creating a new bonding curve with specified parameters.
     * @param _a Initial price factor
     * @param _b Exponential growth facto
     */
    constructor(uint256 _a, uint256 _b) {
        require(_a > 0, "A must be positive");
        require(_b > 0, "B must be positive");
        A = _a;
        B = _b;
    }

    /// @notice Validates that an exponent value is within safe calculation bounds
    /// @param value The exponent value to check
    /// @dev Reverts with ExponentTooLarge if value exceeds MAX_EXP_VALUE
    function _checkExponent(int256 value) internal pure {
        if (value > MAX_EXP_VALUE) {
            revert ExponentTooLarge(value, MAX_EXP_VALUE);
        }
    }

    /*
     * @notice Calculates how many payment tokens would be received for selling tokens.
     * @dev Formula: deltaY = (A/B) * (e^(B*x0) - e^(B*x1))
     *  - where x1 = x0 - deltaX
     * @param x0 Current token supply
     * @param deltaX Number of tokens to sell
     * @param deltaY Amount of payment tokens to receive.
     */
    function getFundsReceived(
        uint256 x0,
        uint256 deltaX
    ) public view returns (uint256 deltaY) {
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
        int256 exp_b_x0 = int256(B.mulWad(x0));

        // Calculate e^(B*x1) where x1 = x0 - deltaX
        int256 exp_b_x1 = int256(B.mulWad(x0 - deltaX));

        // Check exponentiation
        _checkExponent(exp_b_x0);
        _checkExponent(exp_b_x1);

        // Calculate e^(B*x0) - e^(B*x1)
        uint256 delta = uint256(exp_b_x0.expWad() - exp_b_x1.expWad());

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
    function getAmountOut(
        uint256 x0,
        uint256 deltaY
    ) public view returns (uint256 deltaX) {
        // Check remaining supply first
        uint256 remainingSupply = MAX_SUPPLY - x0;
        if (remainingSupply < MIN_REMAINING_SUPPLY) {
            revert InsufficientRemainingSupply(
                remainingSupply,
                MIN_REMAINING_SUPPLY
            );
        }

        // Base validations
        if (x0 >= MAX_SUPPLY) {
            revert SupplyExceedsMaximum(x0, MAX_SUPPLY);
        }

        // Calculate e^(B*x0)
        int256 exp_b_x0 = int256(B.mulWad(x0));
        _checkExponent(exp_b_x0);

        // Calculate e^(B*x0) + (deltaY*B/A)
        uint256 exp_b_x1 = uint256(exp_b_x0.expWad()) + deltaY.fullMulDiv(B, A);

        // Calculate (ln(exp_b_x1)/B) - x0
        deltaX = uint256(int256(exp_b_x1).lnWad()).divWad(B) - x0;

        // Validate size
        if (deltaX > MAX_TX_SIZE) {
            revert TransactionTooLarge(deltaX, MAX_TX_SIZE);
        }

        // Final supply check
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
        if (x > MAX_SUPPLY) {
            revert SupplyExceedsMaximum(x, MAX_SUPPLY);
        }

        // Calculate e^(B+x)
        int256 exp_b_x = int256(B.mulWad(x));
        _checkExponent(exp_b_x);

        // Calculate A * e^(B*x)
        price = A.mulWad(uint256(exp_b_x.expWad()));
    }

    /**
     * @notice Simulates the price impact of a buy order
     * @param x0 Current token supply
     * @param deltaX Size of potential purchase
     * @return priceImpact Percentage price increase (in basis points)
     */
    function simulatePriceImpact(
        uint256 x0,
        uint256 deltaX
    ) external view returns (uint256 priceImpact) {
        uint256 initialPrice = getCurrentPrice(x0);
        uint256 finalPrice = getCurrentPrice(x0 + deltaX);

        // Calculate price impact in basis points (1 bp = 0.01%)
        priceImpact = ((finalPrice - initialPrice) * 10000) / initialPrice;
    }
}
