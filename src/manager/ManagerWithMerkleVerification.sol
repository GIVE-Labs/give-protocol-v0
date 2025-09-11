// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @title ManagerWithMerkleVerification
/// @notice Verifies calldata against an allow-list Merkle root before forwarding calls to a target.
/// @dev This is a minimal, concrete base implementing Merkle gating. Decoders/Sanitizers should be layered on top in future work.
contract ManagerWithMerkleVerification {
  /// @notice Merkle root for allowed actions
  bytes32 public allowListRoot;
  /// @notice Target vault that ultimately interacts with protocols
  address public immutable boringVault;
  /// @notice Owner authorized to update the allow-list root
  address public owner;

  /// @dev Emitted when the allow-list root changes
  event AllowListRootSet(bytes32 indexed oldRoot, bytes32 indexed newRoot);
  /// @dev Emitted after a successful forward
  event Forwarded(address indexed target, bytes4 indexed selector, bytes data);

  /// @dev Thrown when a caller is not authorized
  error NotOwner();
  /// @dev Thrown when calldata is not on the allow-list
  error NotAllowed();

  /// @notice Construct the Manager
  /// @param _boringVault The vault address that this manager is associated with
  /// @param _owner The owner allowed to update the allow-list root
  constructor(address _boringVault, address _owner) {
    boringVault = _boringVault;
    owner = _owner;
  }

  /// @notice Transfer ownership
  /// @param newOwner The new owner
  function transferOwnership(address newOwner) external {
    if (msg.sender != owner) revert NotOwner();
    owner = newOwner;
  }

  /// @notice Set the Merkle allow-list root for gated actions
  /// @param newRoot New Merkle root
  function setAllowListRoot(bytes32 newRoot) external {
    if (msg.sender != owner) revert NotOwner();
    bytes32 old = allowListRoot;
    allowListRoot = newRoot;
    emit AllowListRootSet(old, newRoot);
  }

  /// @notice Forward a call to `target` if the `(target, selector, keccak256(data))` leaf is allowed by `allowListRoot`
  /// @param target The target contract to forward the call to
  /// @param data Calldata to forward (selector + encoded args)
  /// @param proof Merkle proof authorizing this call under the current allow-list root
  function forward(address target, bytes calldata data, bytes32[] calldata proof) external payable {
    require(data.length >= 4, "bad data");
    bytes4 selector;
    assembly {
      selector := calldataload(data.offset)
    }

    // Minimal leaf derivation: keccak(target, selector, keccak256(data))
    // Future work: replace keccak(data) with decoder/sanitizer-produced bytes as per AGENTS.md
    bytes32 leaf = keccak256(abi.encode(target, selector, keccak256(data)));
    if (!MerkleProof.verifyCalldata(proof, allowListRoot, leaf)) revert NotAllowed();

    (bool ok, bytes memory ret) = target.call{value: msg.value}(data);
    if (!ok) {
      assembly {
        revert(add(ret, 32), mload(ret))
      }
    }
    emit Forwarded(target, selector, data);
  }

  uint256[50] private __gap;
}

