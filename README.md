# Withdrawal Manager

![Foundry CI](https://github.com/maple-labs/withdrawal-manager/actions/workflows/forge.yml/badge.svg) [![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

## Overview

The `WithdrawalManager` is an upgradable contract used by the Maple V2 protocol to facilitate withdrawals of liquidity from a Maple pool via a cyclical withdrawal mechanism. It also enables pro-rata distribution of cash in the event of insufficient liquidity.

For more information about the `WithdrawalManager` contract in the context of the Maple V2 protocol, please refer to the Withdrawal section of the protocol [wiki](https://github.com/maple-labs/maple-core-v2/wiki/Withdrawal-Mechanism).

## Setup

This project was built using [Foundry](https://book.getfoundry.sh/). Refer to installation instructions [here](https://github.com/foundry-rs/foundry#installation).

```sh
git clone git@github.com:maple-labs/withdrawal-manager.git
cd withdrawal-manager
forge install
```

## Running Tests

- To run all tests: `forge test`
- To run specific tests: `forge test --match <test_name>`

`./scripts/test.sh` is used to enable Foundry profile usage using the `-p` flag. Profiles are used to specify fuzz run depth.

## About Maple

[Maple Finance](https://maple.finance/) is a decentralized corporate credit market. Maple provides capital to institutional borrowers through globally accessible fixed-income yield opportunities.

For all technical documentation related to the Maple V2 protocol, please refer to the GitHub [wiki](https://github.com/maple-labs/maple-core-v2/wiki).

---

<p align="center">
  <img src="https://user-images.githubusercontent.com/44272939/116272804-33e78d00-a74f-11eb-97ab-77b7e13dc663.png" height="100" />
</p>
