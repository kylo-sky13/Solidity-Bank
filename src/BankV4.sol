// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title IStrategy
 * @notice Minimal vault-controlled strategy interface
 * @dev Strategy MUST:
 *  - Use the same asset as the vault
 *  - Have no users or shares
 *  - Only be callable by the vault
 */
interface IStrategy {
    function deposit(uint256 assets) external;
    function withdraw(uint256 assets) external;
    function totalAssets() external view returns (uint256);
}
