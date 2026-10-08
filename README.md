# Quantum ID agent (QUANTUM)

An immutable, fixed-supply ERC-20 implemented in `src/QuantumToken.sol` using
OpenZeppelin Contracts v5.1.0. The constructor mints the entire supply once to
`msg.sender`, the immediate deployer.

| Parameter | Value |
| --- | --- |
| Contract | `src/QuantumToken.sol:QuantumToken` |
| Name | `Quantum ID agent` |
| Symbol | `QUANTUM` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Constructor transaction value | `0` |
| Initial recipient | Immediate deployer (`msg.sender`) |

## Build and test

Install Foundry and make Solidity **0.8.26** available in its compiler cache.
All Solidity dependencies and their licenses are included as ordinary files in
`lib/`; no package installation, submodules, RPC, or network is needed to build
and test once the toolchain is present.

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, the Cancun EVM target, optimization at 200
runs, and `bytecode_hash = "none"`. FFI and filesystem cheatcode access are
disabled. Deploy only to a chain supporting the configured EVM target. No
compiler binary is included in this repository.

`DEPENDENCIES.json` records the source archives, versions, and SHA-256 hashes of
every vendored file. The production dependency is the ERC-20 subset of
OpenZeppelin v5.1.0; forge-std v1.9.7 is used only by tests. Vendored sources are
unmodified and excluded from local formatting.

## Behavior and assumptions

The brief specifies standard ERC-20 behavior with fixed metadata and supply.
There are no fees, rebases, transfer limits, burns, post-deployment minting,
owner roles, blacklist, pause, seizure, upgrade, or initialization functions.
Every valid transfer delivers the exact requested amount. Factory, distributor,
and pool addresses need no exemptions or configuration.

Transfers and approvals return `true` on success and use OpenZeppelin ERC-20
custom errors on failure. Transfers reject a zero sender or recipient;
approvals reject a zero spender. Zero-amount transfers between valid addresses
are allowed and emit `Transfer`. Self-transfers preserve balances. Transfers
do not call receiver contracts.

`approve` replaces the caller's allowance. `transferFrom` requires sufficient
allowance even when the caller is the deployer, or is transferring its own
tokens. Finite allowances decrease when spent; a maximum `uint256` allowance
is unlimited and is not reduced. An approval grants spending authority, so
holders must trust their chosen spenders. When changing an existing allowance,
holders should revoke it first and wait for confirmation before granting a new
amount to mitigate the usual ERC-20 allowance replacement race. A spender can
still use an outstanding allowance before revocation confirms.

The constructor emits `Transfer` from the zero address for the entire supply.
Transfers emit `Transfer`, and explicit approvals emit `Approval`. As in
OpenZeppelin v5.1.0, spending an allowance does not emit another `Approval`;
integrations should query `allowance` for its current value.

## Deployment and operational responsibilities

Use the creation bytecode for `src/QuantumToken.sol:QuantumToken` with no encoded
constructor arguments and zero native currency value. The build artifact is
`out/QuantumToken.sol/QuantumToken.json`; this read-only command also returns the
creation bytecode:

```sh
forge inspect src/QuantumToken.sol:QuantumToken bytecode
```

The deploying account receives all tokens on a direct deployment. With factory
deployment, the factory receives all tokens; it must perform the intended
distribution. A wrapper that creates the token becomes its initial holder, so
the deployment operator must check that the chosen factory can forward tokens.
The token itself implements no pool, distributor, or launch economics. Those
belong to the surrounding launch system and require its own supplied parameters.

The deployment operator is responsible for choosing the target chain and
deployment caller, reviewing the artifact and distribution, paying gas, and
verifying the deployed source and compiler settings on the chain's explorer.
Check the name, symbol, decimals, total supply, mint event, and recipient balance
at deployment. Subsequent factory transfers may distribute the initial balance
within the same transaction. This project does not require an owner address,
oracle, service ID, or external contract address to construct the token.

### After launch

There are no settings, privileged keys, administrative actions, or keepers to
maintain. Holders are responsible for custody, transfers, and approvals. The
initial holder controls the initially minted supply but gains no authority over
other holders. Lost tokens and mistaken transfers cannot be recovered by an
administrator. Sending tokens to the token contract itself or to a recipient
unable to transfer them may make them inaccessible. Native currency deposits
are not supported, and there is no asset rescue function.

## Validation and review scope

The local tests cover metadata, constructor supply and mint event, CREATE2
factory ownership, exact distribution and claim transfers, event emission,
self-transfers, zero amounts, finite and unlimited allowances, replacement and
revocation, invalid addresses, insufficient balances and allowances, atomic
rollback on failed delegated transfers, absent mint/admin/burn functions, and
absence of `DELEGATECALL`, `CALLCODE`, and `SELFDESTRUCT` in runtime bytecode.

Fuzz tests exercise valid and invalid amounts and arbitrary transfer recipients.
A stateful invariant runs 128 sequences of 64 calls through four holders,
checking transfers, approvals, delegated transfers, fixed supply, and balance
conservation. Test setup is isolated; tests do not read or modify environment
variables and require no fork or external service.

The supplied protected launch test was read as an acceptance reference. Its
full Uniswap v4 seed/swap scenario needs the surrounding launch contracts and
resolved launch configuration, which are not inputs to this token assignment.
The local factory harness verifies constructor ownership and exact transfers;
it does not claim to exercise the real launch factory or pool.

Source review focuses on the one-time constructor mint, ordinary ERC-20 access
rules, no external calls, and the absence of privileged or upgrade paths. Local
Foundry checks are not an independent security audit. The launch operator should
arrange the separate adversarial review before release. Slither and Mythril
were not run, and no on-chain deployment or transaction was performed.
