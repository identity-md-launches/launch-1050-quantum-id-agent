// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {QuantumToken} from "../src/QuantumToken.sol";

/// @dev Local deployment/transfer harness; this is not a launch factory implementation.
contract TokenFactoryHarness {
    function deploy(bytes32 salt) external returns (QuantumToken) {
        return new QuantumToken{salt: salt}();
    }

    function move(QuantumToken token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

/// @dev A transfer must not invoke arbitrary receiver code.
contract RejectingReceiver {
    fallback() external {
        revert("receiver must not be called");
    }
}

contract QuantumTokenTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    QuantumToken private token;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new QuantumToken();
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
    }

    function testMetadataAndInitialSupply() public view {
        assertEq(token.name(), "Quantum ID agent");
        assertEq(token.symbol(), "QUANTUM");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function testConstructorEmitsMintEvent() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), SUPPLY);
        QuantumToken deployed = new QuantumToken();
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function testCreate2MintsAllSupplyToFactory() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        QuantumToken deployed = factory.deploy(keccak256("local deployment"));
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(address(this)), 0);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function testFactoryDistributionAndClaimAreExact() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        QuantumToken deployed = factory.deploy(keccak256("local distribution"));
        address distributor = makeAddr("distributor");
        uint256 swarmShare = SUPPLY / 10;

        assertTrue(factory.move(deployed, distributor, swarmShare));
        assertEq(deployed.balanceOf(distributor), swarmShare);
        assertTrue(factory.move(deployed, bob, SUPPLY - swarmShare));
        vm.prank(distributor);
        assertTrue(deployed.transfer(alice, swarmShare));

        assertEq(deployed.balanceOf(address(factory)), 0);
        assertEq(deployed.balanceOf(distributor), 0);
        assertEq(deployed.balanceOf(alice), swarmShare);
        assertEq(deployed.balanceOf(bob), SUPPLY - swarmShare);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function testTransferEmitsEventAndDeliversExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 123 ether);
        assertTrue(token.transfer(alice, 123 ether));
        assertEq(token.balanceOf(alice), 123 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 123 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testTransferEntireBalance() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, SUPPLY));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testSelfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testTransferDoesNotCallReceiver() public {
        RejectingReceiver receiver = new RejectingReceiver();
        assertTrue(token.transfer(address(receiver), 1 ether));
        assertEq(token.balanceOf(address(receiver)), 1 ether);
    }

    function testTransferAboveBalanceRevertsWithoutChanges() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(alice, SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzTransferToZeroReverts(uint256 amount) public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testApproveEmitsEventAndCanReplaceAndRevokeAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 50 ether);
        assertTrue(token.approve(spender, 50 ether));
        assertEq(token.allowance(address(this), spender), 50 ether);
        assertTrue(token.approve(spender, 3 ether));
        assertEq(token.allowance(address(this), spender), 3 ether);
        assertTrue(token.approve(spender, 0));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testApproveDoesNotRequireBalance() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, type(uint256).max));
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 0);
    }

    function testApproveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function testTransferFromConsumesFiniteAllowanceAndEmitsTransfer() public {
        token.approve(spender, 10 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 4 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 4 ether));
        assertEq(token.allowance(address(this), spender), 6 ether);
        assertEq(token.balanceOf(alice), 4 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 4 ether);
    }

    function testTransferFromCanExhaustAllowance() public {
        token.approve(spender, 10 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 10 ether));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 10 ether);
    }

    function testInfiniteAllowanceIsNotReduced() public {
        token.approve(spender, type(uint256).max);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, 10 ether));
        assertTrue(token.transferFrom(address(this), bob, 20 ether));
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 20 ether);
    }

    function testRevokedAllowanceCannotBeSpent() public {
        token.approve(spender, 10 ether);
        token.approve(spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 0);
    }

    function testTransferFromAboveAllowanceRevertsWithoutChanges() public {
        token.approve(spender, 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 10 ether, 11 ether)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, 11 ether);
        assertEq(token.allowance(address(this), spender), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testTransferFromFailureRestoresAllowanceOnInsufficientBalance() public {
        token.approve(spender, SUPPLY + 1);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, SUPPLY + 1);
        assertEq(token.allowance(address(this), spender), SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function testTransferFromFailureRestoresAllowanceOnZeroRecipient() public {
        token.approve(spender, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 10 ether);
        assertEq(token.allowance(address(this), spender), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testTransferFromZeroSenderRevertsEvenForZeroAmount() public {
        // Allowance validation rejects the zero owner before attempting the transfer.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), alice, 0);
        assertEq(token.balanceOf(alice), 0);
    }

    function testZeroTransferFromRequiresNoAllowance() public {
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function testSelfTransferFromConsumesAllowanceWithoutMovingBalance() public {
        token.approve(spender, 5 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 5 ether));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testDeployerCannotSpendHolderBalanceWithoutApproval() public {
        token.transfer(alice, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, address(this), 1);
        assertEq(token.balanceOf(alice), 100 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100 ether));
        assertEq(token.balanceOf(bob), 100 ether);
    }

    function testMintBurnAndAdministrativeSelectorsAreUnavailable() public {
        token.transfer(alice, 100 ether);
        bytes[] memory calls = new bytes[](17);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, 1 ether);
        calls[1] = abi.encodeWithSignature("mint(uint256)", 1 ether);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("issue(uint256)", 1 ether);
        calls[4] = abi.encodeWithSignature("initialize(address)", bob);
        calls[5] = abi.encodeWithSignature("setMinter(address)", bob);
        calls[6] = abi.encodeWithSignature("setOwner(address)", bob);
        calls[7] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[8] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[9] = abi.encodeWithSignature("pause()");
        calls[10] = abi.encodeWithSignature("unpause()");
        calls[11] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[12] = abi.encodeWithSignature("freeze(address)", alice);
        calls[13] = abi.encodeWithSignature("lock(address)", alice);
        calls[14] = abi.encodeWithSignature("seize(address)", alice);
        calls[15] = abi.encodeWithSignature("burn(uint256)", 1 ether);
        calls[16] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1 ether);

        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertFalse(deployerSucceeded, "deployer accessed an unsupported function");
            vm.prank(bob);
            (bool strangerSucceeded,) = address(token).call(calls[i]);
            assertFalse(strangerSucceeded, "stranger accessed an unsupported function");
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(alice), 100 ether);
            assertEq(token.balanceOf(bob), 0);
        }

        vm.prank(alice);
        assertTrue(token.transfer(bob, 100 ether));
        assertEq(token.balanceOf(bob), 100 ether);
    }

    function testRuntimeContainsNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
                continue;
            }
            assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff, "forbidden opcode");
        }
    }

    function testFuzzTransferConservesSupply(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzDelegatedTransferConservesSupply(uint256 approved, uint256 amount) public {
        approved = bound(approved, 0, SUPPLY);
        amount = bound(amount, 0, approved);
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(address(this), spender), approved - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzzTransferAboveBalanceAlwaysReverts(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(alice, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }
}
