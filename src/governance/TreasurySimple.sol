// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title TreasurySimple
/// @notice Minimal treasury receiving protocol fees and allowing owner to sweep funds.
contract TreasurySimple {
  using SafeERC20 for IERC20;

  address public owner;

  event OwnerSet(address indexed oldOwner, address indexed newOwner);
  event FeeReceived(address indexed asset, uint256 amount);
  event Swept(address indexed asset, address indexed to, uint256 amount);

  error NotOwner();
  error InvalidParam();

  modifier onlyOwner() { if (msg.sender != owner) revert NotOwner(); _; }

  constructor(address owner_) {
    owner = owner_;
    emit OwnerSet(address(0), owner_);
  }

  function setOwner(address newOwner) external onlyOwner {
    if (newOwner == address(0)) revert InvalidParam();
    emit OwnerSet(owner, newOwner);
    owner = newOwner;
  }

  function receiveFee(address asset, uint256 amount) external {
    IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
    emit FeeReceived(asset, amount);
  }

  function sweep(address asset, address to, uint256 amount) external onlyOwner {
    if (to == address(0) || amount == 0) revert InvalidParam();
    IERC20(asset).safeTransfer(to, amount);
    emit Swept(asset, to, amount);
  }
}

