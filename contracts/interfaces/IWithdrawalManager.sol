// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.7;

import { IMapleProxied } from "../../modules/maple-proxy-factory/contracts/interfaces/IMapleProxied.sol";

import { IWithdrawalManagerStorage } from "./IWithdrawalManagerStorage.sol";

interface IWithdrawalManager is IMapleProxied, IWithdrawalManagerStorage {

    /******************************************************************************************************************************/
    /*** State Changing Functions                                                                                               ***/
    /******************************************************************************************************************************/

    /**
     * @dev   Add shares to the withdrawal manager.
     * @param shares_ Amount of shares to add.
     * @param owner_  Address of the owner of shares.
     */
    function addShares(uint256 shares_, address owner_) external;

    /**
     * @dev   Process the exit of an account.
     * @param account_          Address of the account process exit from.
     * @param requestedShares_  Amount of initially requested shares.
     */
    function processExit(address account_, uint256 requestedShares_) external returns (uint256 redeemableShares_, uint256 resultingAssets_);

    /**
     * @dev   Remove shares to the withdrawal manager.
     * @param shares_ Amount of shares to remove.
     * @param owner_  Address of the owner of shares.
     */
    function removeShares(uint256 shares_, address owner_) external returns (uint256 sharesReturned_);

    /**
     * @dev   Set ups a new exit configuration.
     * @param cycleDuration_  The total duration, in seconds, of a withdrawal cycle.
     * @param windowDuration_ The duration, in seconds, of the withdrawal window.
     */
    function setExitConfig(uint256 cycleDuration_, uint256 windowDuration_) external;

    /******************************************************************************************************************************/
    /*** View Functions                                                                                                         ***/
    /******************************************************************************************************************************/

    /**
     * @dev    Gets the asset address used in this withdrawal manager.
     * @return asset_ Address of the asset.
     */
    function asset() external view returns (address asset_);

    /**
     *  @dev    Gets the address of the globals.
     *  @return globals_ The address of the globals.
     */
    function globals() external view returns (address globals_);

    /**
     *  @dev    Gets the address of the governor.
     *  @return governor_ The address of the governor.
     */
    function governor() external view returns (address governor_);

    /**
     * @dev    Checks if an account is included in a exit window.
     * @param  owner_          The address of the share owners to check.
     * @return isInExitWindow_ A boolean indicating whether or not the account is in an exit window.
     */
    function isInExitWindow(address owner_) external view returns (bool isInExitWindow_);

    /**
     * @dev    Gets the total amount of funds that need to be locked to fulfill exits.
     * @return lockedLiquidity_ The amount of locked liquidity.
     */
    function lockedLiquidity() external view returns (uint256 lockedLiquidity_);

    /**
     * @dev    Gets the pool delegate address.
     * @return poolDelegate_ Address of the pool delegate.
     */
    function poolDelegate() external view returns (address poolDelegate_);

    /**
     * @dev    Gets the amount of shares that can be redeemed.
     * @param  owner_            The address to check the redemption for.
     * @param  shares_           The aamount of requested shares to redeem.
     * @return redeemableShares_ The amount of shares that can be redeemed.
     * @return resultingAssets_  The amount of assets that will be returned for `redeemableShares`.
     */
    function previewRedeem(address owner_, uint256 shares_) external view returns (uint256 redeemableShares_, uint256 resultingAssets_);

}
