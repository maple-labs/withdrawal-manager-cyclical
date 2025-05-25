# Withdrawal Manager

![Foundry CI](https://github.com/maple-labs/withdrawal-manager-cyclical/actions/workflows/forge.yml/badge.svg)
[![GitBook - Documentation](https://img.shields.io/badge/GitBook-Documentation-orange?logo=gitbook&logoColor=white)](https://maplefinance.gitbook.io/maple/maple-for-developers/protocol-overview)
[![Foundry][foundry-badge]][foundry]
[![License: BUSL 1.1](https://img.shields.io/badge/License-BUSL%201.1-blue.svg)](https://github.com/maple-labs/withdrawal-manager-cyclical/blob/main/LICENSE)

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg

## Overview

The `WithdrawalManager` is an upgradable contract used by the Maple V2 protocol to facilitate withdrawals of liquidity from a Maple pool via a cyclical withdrawal mechanism. It also enables pro-rata distribution of cash in the event of insufficient liquidity.

## Dependencies/Inheritance

Contracts in this repo inherit and import code from:
- [`maple-labs/erc20`](https://github.com/maple-labs/erc20)
- [`maple-labs/erc20-helper`](https://github.com/maple-labs/erc20-helper)
- [`maple-labs/maple-proxy-factory`](https://github.com/maple-labs/maple-proxy-factory)

Contracts inherit and import code in the following ways:
- `WithdrawalManager` uses `ERC20Helper` for token interactions.
- `WithdrawalManager` inherits `MapleProxiedInternals` for proxy logic.
- `WithdrawalManagerFactory` inherits `MapleProxyFactory` for proxy deployment and management.

Versions of dependencies can be checked with `git submodule status`.

## Setup

This project was built using [Foundry](https://book.getfoundry.sh/). Refer to installation instructions [here](https://github.com/foundry-rs/foundry#installation).

```sh
git clone git@github.com:maple-labs/withdrawal-manager-cyclical.git
cd withdrawal-manager-cyclical
forge install
```

## Running Tests

- To run all tests: `forge test`
- To run specific tests: `forge test --match <test_name>`

`./scripts/test.sh` is used to enable Foundry profile usage with the `-p` flag. Profiles are used to specify the number of fuzz runs.

## Audit Reports

| Auditor | Report Link |
|---|---|
| Trail of Bits | [`2022-08-24 - Trail of Bits Report`](https://docs.google.com/viewer?url=https://github.com/maple-labs/maple-v2-audits/files/10246688/Maple.Finance.v2.-.Final.Report.-.Fixed.-.2022.pdf) |
| Spearbit | [`2022-10-17 - Spearbit Report`](https://docs.google.com/viewer?url=https://github.com/maple-labs/maple-v2-audits/files/10223545/Maple.Finance.v2.-.Spearbit.pdf) |
| Three Sigma | [`2022-10-24 - Three Sigma Report`](https://docs.google.com/viewer?url=https://github.com/maple-labs/maple-v2-audits/files/10223541/three-sigma_maple-finance_code-audit_v1.1.1.pdf) |
| Three Sigma | [`2023-11-06 - Three Sigma Report`](https://docs.google.com/viewer?url=https://github.com/maple-labs/maple-v2-audits/files/13707288/Maple-Q4-Three-Sigma-Audit.pdf) |
| 0xMacro | [`2023-11-27 - 0xMacro Report`](https://docs.google.com/viewer?url=https://github.com/maple-labs/maple-v2-audits/files/13707291/Maple-Q4-0xMacro-Audit.pdf) |

## Bug Bounty

For all information related to the ongoing bug bounty for these contracts run by [Immunefi](https://immunefi.com/), please visit this [site](https://immunefi.com/bounty/maple/).

## About Maple

[Maple Finance](https://maple.finance/) is a decentralized corporate credit market. Maple provides capital to institutional borrowers through globally accessible fixed-income yield opportunities.

---

<p align="center">
  <img src="https://github.com/maple-labs/maple-metadata/blob/796e313f3b2fd4960929910cd09a9716688a4410/assets/maplelogo.png" height="100" />
</p>
