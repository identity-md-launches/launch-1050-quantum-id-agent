// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Quantum ID agent (QUANTUM)
/// @notice A fixed-supply ERC-20 with 18 decimals and no administrative powers.
contract QuantumToken is ERC20 {
    /// @notice One billion tokens expressed in the smallest unit (10^27).
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Mints the entire supply to the immediate deployer, including a deploying factory.
    constructor() ERC20("Quantum ID agent", "QUANTUM") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
