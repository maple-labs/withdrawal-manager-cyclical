// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

import { MockPool } from "./MockPool.sol";

contract MockPoolManager {

    MockPool _pool;

    constructor(MockPool pool_) {
        _pool = pool_;
    }

    function redeem(uint256 shares_, address receiver_, address owner_) external returns (uint256 assets_) {
        assets_ = _pool.redeem(shares_, receiver_, owner_);
    }

}
