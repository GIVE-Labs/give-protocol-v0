// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {EpochTypes} from "./EpochTypes.sol";
import {IBoringVault4626} from "../interfaces/IBoringVault4626.sol";

/// @title BoringVault4626 (storage skeleton)
/// @notice ERC-4626-like vault with epoch & Merkle accounting. Storage, events, and function declarations.
/// @dev Concrete implementations (e.g., GiveVault4626) must implement the declared functions and enforce invariants.
abstract contract BoringVault4626 is IBoringVault4626 {
  // Donation asset (i.e., the vault's underlying)
  address internal _asset;

  // Protocol fee in bps; charged before split
  uint16 public protocolFeeBps;
  uint16 public constant MAX_FEE_BPS = 150; // 1.5%

  // Epoch state
  uint256 public currentEpoch; // E
  mapping(uint256 => bytes32) internal _epochRoot; // epoch => Merkle root
  mapping(uint256 => EpochTypes.EpochTotals) internal _epochTotals; // epoch => totals

  // Donation shares {5000, 7500, 10000}; next-epoch effective
  mapping(address => uint16) internal _currentDonationShareBps;
  mapping(address => uint16) internal _pendingDonationShareBps;
  mapping(address => uint256) internal _pendingDonationShareEffectiveEpoch;

  // Claims: bitmap per user keyed by epoch / word index (implementation specific)
  mapping(address => mapping(uint256 => uint256)) internal _claimBitmap;

  // Harvest window (deposits/mints paused only)
  uint256 public harvestWindowOpenBlock;
  uint256 public harvestWindowCloseBlock;

  // Events from interface are inherited

  // Errors
  error OnlyActiveAdapter();
  error HarvestWindowOpen();
  error InvalidDonationShare();
  error RootAlreadyFinalized();
  error InvalidMerkleProof();
  error AlreadyClaimed();

  // IBoringVault4626 interface (function bodies to be implemented in concrete contract)
  function rollEpoch() external virtual override;
  function reportHarvest(uint256 harvested) external virtual override;
  function finalizeEpochRoot(uint256 epoch, bytes32 root, EpochTypes.EpochTotals calldata totals)
    external
    virtual
    override;

  function setDonationShareBps(uint16 bps) external virtual override;
  function claimUserYield(uint256 epoch, uint256 amount, bytes32[] calldata proof) external virtual override;

  function donationAsset() external view virtual override returns (address);
  function donationAmountForEpoch(uint256 epoch) external view virtual override returns (uint256);
  function epochRoot(uint256 epoch) external view virtual override returns (bytes32);

  uint256[50] private __gap;
}
