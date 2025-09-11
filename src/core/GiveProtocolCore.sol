// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title GiveProtocolCore
/// @notice Orchestrator holding module addresses and global params; storage + events only
abstract contract GiveProtocolCore {
  // Modules
  address public aclManager;
  address public emergencyController;
  address public strategyManager;
  address public boringVault;
  address public donationRouter;
  address public ngoRegistry;
  address public treasury;

  // Params
  uint16 public protocolFeeBps; // fee taken before split
  uint16 public constant MAX_FEE_BPS = 150; // 1.5%
  uint256 public epochLength; // seconds
  uint256 public harvestWindowBlocks; // deposits paused during window

  // Events
  event ModuleUpdated(bytes32 indexed key, address indexed oldAddr, address indexed newAddr);
  event ProtocolFeeSet(uint16 oldFeeBps, uint16 newFeeBps);
  event EpochParamsSet(uint256 epochLength, uint256 harvestWindowBlocks);

  // Errors
  error InvalidParam();
  error FeeAboveMax();

  // Mutations (to be implemented by concrete contract)
  function setModule(bytes32 key, address addr) external virtual;
  function setProtocolFeeBps(uint16 newFeeBps) external virtual;
  function setEpochParams(uint256 newEpochLength, uint256 newHarvestWindowBlocks) external virtual;

  // Storage gap for upgrades
  uint256[50] private __gap;
}

