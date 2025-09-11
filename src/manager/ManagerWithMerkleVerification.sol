// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ManagerWithMerkleVerification (storage skeleton)
/// @notice Verifies sanitized calldata against an allow-list Merkle root before forwarding calls
abstract contract ManagerWithMerkleVerification {
  bytes32 public allowListRoot; // Merkle root for allowed actions
  address public boringVault; // target vault that ultimately interacts with protocols

  event AllowListRootSet(bytes32 indexed oldRoot, bytes32 indexed newRoot);
  event Forwarded(address indexed target, bytes4 indexed selector, bytes data);

  error NotAllowed();
  error InvalidCalldata();

  function setAllowListRoot(bytes32 newRoot) external virtual;
  function forward(address target, bytes calldata data, bytes32[] calldata proof) external payable virtual;

  uint256[50] private __gap;
}

