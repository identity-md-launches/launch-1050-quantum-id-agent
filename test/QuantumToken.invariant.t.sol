// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {QuantumToken} from "../src/QuantumToken.sol";

/// @dev Restricts destinations to known actors so their balances account for the whole supply.
contract QuantumTokenHandler is Test {
    QuantumToken private immutable token;
    address[4] private actors;

    constructor(QuantumToken token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        amount = bound(amount, 0, fromBefore);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(from), from == to ? fromBefore : fromBefore - amount);
        assertEq(token.balanceOf(to), from == to ? toBefore : toBefore + amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        uint256 allowanceBefore = token.allowance(from, spender);
        uint256 maximum = fromBefore < allowanceBefore ? fromBefore : allowanceBefore;
        amount = bound(amount, 0, maximum);

        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        assertEq(token.balanceOf(from), from == to ? fromBefore : fromBefore - amount);
        assertEq(token.balanceOf(to), from == to ? toBefore : toBefore + amount);
        assertEq(
            token.allowance(from, spender),
            allowanceBefore == type(uint256).max ? allowanceBefore : allowanceBefore - amount
        );
    }
}

contract QuantumTokenInvariantTest is StdInvariant, Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    QuantumToken private token;
    address[4] private actors;

    function setUp() public {
        token = new QuantumToken();
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("actor-", vm.toString(i)));
        }
        token.transfer(actors[0], SUPPLY);

        QuantumTokenHandler handler = new QuantumTokenHandler(token, actors);
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariantSupplyIsFixedAndAllTokensAreAccountedFor() public view {
        uint256 accounted;
        for (uint256 i; i < actors.length; ++i) {
            accounted += token.balanceOf(actors[i]);
        }
        assertEq(accounted, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }
}
