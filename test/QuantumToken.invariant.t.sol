// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {QuantumToken} from "../src/QuantumToken.sol";

/// @dev Restricts destinations to known actors so their balances account for the whole supply.
contract QuantumTokenHandler is Test {
    QuantumToken private immutable token;
    address[4] private actors;
    // Expected state follows requested operations, not reads of the token after a call.
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(QuantumToken token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = 1_000_000_000 * 10 ** 18;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        assertEq(token.balanceOf(from), from == to ? fromBefore : fromBefore - amount);
        assertEq(token.balanceOf(to), from == to ? toBefore : toBefore + amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        // Routinely exercise revocation and infinite approval, as well as finite approvals.
        uint256 mode = amount % 3;
        amount = mode == 0 ? 0 : mode == 1 ? type(uint256).max : bound(amount, 0, 1e27);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        assertEq(token.allowance(owner, spender), amount);
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        uint256 allowanceBefore = token.allowance(from, spender);
        uint256 maximum = expectedBalance[from] < expectedAllowance[from][spender]
            ? expectedBalance[from]
            : expectedAllowance[from][spender];
        amount = bound(amount, 0, maximum);

        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        if (expectedAllowance[from][spender] != type(uint256).max) {
            expectedAllowance[from][spender] -= amount;
        }
        assertEq(token.balanceOf(from), from == to ? fromBefore : fromBefore - amount);
        assertEq(token.balanceOf(to), from == to ? toBefore : toBefore + amount);
        assertEq(
            token.allowance(from, spender),
            allowanceBefore == type(uint256).max ? allowanceBefore : allowanceBefore - amount
        );
    }

    function approveAndSpend(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[from][spender] = amount;
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        expectedAllowance[from][spender] = 0;
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function transferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        amount = bound(amount, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
        // No ghost update: every balance and allowance must remain unchanged.
    }

    function transferFromAboveAllowance(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 approved)
        external
    {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        approved = bound(approved, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.approve(spender, approved));
        expectedAllowance[from][spender] = approved;
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1)
        );
        vm.prank(spender);
        token.transferFrom(from, to, approved + 1);
    }

    function transferFromAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, bool infinite) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount = expectedBalance[from] + 1;
        uint256 approved = infinite ? type(uint256).max : amount;
        vm.prank(from);
        assertTrue(token.approve(spender, approved));
        expectedAllowance[from][spender] = approved;
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, expectedBalance[from], amount)
        );
        vm.prank(spender);
        token.transferFrom(from, to, amount);
        // Finite allowance consumption must roll back when the balance check fails.
    }

    function invalidAddresses(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[owner]);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(owner);
        token.transfer(address(0), amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);

        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(owner, address(0), amount);
    }
}

contract QuantumTokenInvariantTest is StdInvariant, Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    QuantumToken private token;
    address[4] private actors;
    QuantumTokenHandler private handler;

    function setUp() public {
        token = new QuantumToken();
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("actor-", vm.toString(i)));
        }
        token.transfer(actors[0], SUPPLY);

        handler = new QuantumTokenHandler(token, actors);
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.approveAndSpend.selector;
        selectors[4] = handler.transferAboveBalance.selector;
        selectors[5] = handler.transferFromAboveAllowance.selector;
        selectors[6] = handler.transferFromAboveBalance.selector;
        selectors[7] = handler.invalidAddresses.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 128
    /// forge-config: default.invariant.fail-on-revert = true
    function invariantSupplyIsFixedAndAllTokensAreAccountedFor() public view {
        uint256 accounted;
        for (uint256 i; i < actors.length; ++i) {
            accounted += token.balanceOf(actors[i]);
            assertEq(
                token.balanceOf(actors[i]), handler.expectedBalance(actors[i]), "holder balance differs from model"
            );
            assertEq(token.allowance(actors[i], address(0)), 0);
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actors[i], actors[j]),
                    handler.expectedAllowance(actors[i], actors[j]),
                    "approval changed unexpectedly"
                );
            }
        }
        assertEq(accounted, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }

    // Pin handler boundaries so coverage does not depend on the random campaign selecting them.
    function testHandlerBoundarySequence() public {
        handler.transfer(0, 1, 1);
        handler.approveAndSpend(0, 2, 3, SUPPLY - 1);
        invariantSupplyIsFixedAndAllTokensAreAccountedFor();
        handler.transferAboveBalance(0, 1, type(uint256).max);
        handler.transferFromAboveAllowance(2, 1, 3, 1);
        handler.transferFromAboveBalance(2, 1, 3, false);
        invariantSupplyIsFixedAndAllTokensAreAccountedFor();
        handler.transferFromAboveBalance(2, 1, 3, true);
        handler.invalidAddresses(2, 3, 0);
        handler.invalidAddresses(2, 3, SUPPLY);
        invariantSupplyIsFixedAndAllTokensAreAccountedFor();
        handler.approve(2, 3, 1); // Infinite allowance.
        handler.transferFrom(2, 2, 3, SUPPLY); // Self-transfer still exercises spending.
        handler.transferFrom(2, 0, 3, SUPPLY);
        handler.approve(2, 3, 0); // Revoke after spending the balance.
        handler.transfer(0, 0, SUPPLY);
        invariantSupplyIsFixedAndAllTokensAreAccountedFor();
    }
}
