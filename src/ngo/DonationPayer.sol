// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IAuthorizer {
  function isAuthorized(address caller) external view returns (bool);
}

/// @title DonationPayer
/// @notice Pull-based donation transfer helper. Authorized callers instruct transfers from caller to NGO.
/// @dev Caller (vault) must set allowance to this contract for the donation asset before calling donate.
contract DonationPayer is ReentrancyGuard {
  using SafeERC20 for IERC20;

  address public owner;
  mapping(address => bool) public isAuthorizedCaller;

  event DonationPaid(address indexed ngo, uint256 amount, address indexed asset);
  event OwnerSet(address indexed oldOwner, address indexed newOwner);
  event CallerAuthorized(address indexed caller, bool authorized);

  error NotOwner();
  error NotAuthorized();
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

  function setAuthorizedCaller(address caller, bool authorized) external onlyOwner {
    isAuthorizedCaller[caller] = authorized;
    emit CallerAuthorized(caller, authorized);
  }

  /// @notice Transfer `amount` of `asset` from the caller (vault) to `ngo`.
  /// @dev Requires allowance from caller to this contract. Reverts on zero values/addresses.
  function donate(address asset, address ngo, uint256 amount) external nonReentrant {
    if (!isAuthorizedCaller[msg.sender]) revert NotAuthorized();
    if (asset == address(0) || ngo == address(0) || amount == 0) revert InvalidParam();
    IERC20 token = IERC20(asset);
    // Pull from caller (vault) and forward to NGO
    token.safeTransferFrom(msg.sender, ngo, amount);
    emit DonationPaid(ngo, amount, asset);
  }
}

