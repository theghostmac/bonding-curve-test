# Bonding Curve Test

## Review
Analyzing the original BondingCurve, I could say that It is minimal and gas-efficient.
It can handle larger numbers, although at the risk of overflows for them.
Exponential operations `expWad` can easily overflow with large numbers, and
the contract didn't protect against this.

More stuff:
- High: No bounds on exponential calculations
- Medium: No transaction size limits
- Medium: No supply caps
- Low: No event emissions for important state changes

```solidity
// Original - more flexible but dangerous
function getAmountOut(uint256 x0, uint256 deltaY) public view returns (uint256 deltaX)

// This version - safer but more constrained
if (remainingSupply < MIN_REMAINING_SUPPLY) {
    revert InsufficientRemainingSupply(remainingSupply, MIN_REMAINING_SUPPLY);
}
```

The original version could be vulnerable to:
- integer overflow attacks
- economic attacks through large transactions
- potential DOS through numerical limitations

Upon trying to solve this, I figured it comes at great costs like:
- max supply must be lowered
- transaction sizes must also be low/restricted
- there's now more gas costs due to the checks being done

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test -vvv
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
