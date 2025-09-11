// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ManagerWithMerkleVerification} from "src/manager/ManagerWithMerkleVerification.sol";

contract TargetMock {
  uint256 public stored;
  event Stored(uint256 v);
  function store(uint256 v) external {
    stored = v;
    emit Stored(v);
  }
}

/// @title Test05_ManagerWithMerkle
/// @notice Unit tests for ManagerWithMerkleVerification base Merkle gating and forwarding
contract Test05_ManagerWithMerkle is Test {
  ManagerWithMerkleVerification mgr;
  TargetMock target;
  address owner = address(0xA11CE);

  function setUp() public {
    target = new TargetMock();
    mgr = new ManagerWithMerkleVerification(address(0x1234), owner);
  }

  function _leaf(address _target, bytes4 selector, bytes memory data) internal pure returns (bytes32) {
    return keccak256(abi.encode(_target, selector, keccak256(data)));
  }

  /// @notice Non-owner cannot set allow-list root
  function test_SetRoot_OnlyOwner() public {
    bytes32 root = bytes32(uint256(1));
    vm.expectRevert(ManagerWithMerkleVerification.NotOwner.selector);
    mgr.setAllowListRoot(root);
    vm.prank(owner);
    mgr.setAllowListRoot(root);
    assertEq(mgr.allowListRoot(), root);
  }

  /// @notice Forward succeeds when the leaf is allowed by the Merkle root and reverts otherwise
  function test_Forward_MerkleGated() public {
    // Prepare calldata for TargetMock.store(uint256)
    bytes memory data = abi.encodeWithSelector(TargetMock.store.selector, uint256(42));
    bytes32 leaf = _leaf(address(target), TargetMock.store.selector, data);
    // Single-leaf tree: root == leaf, proof = []
    vm.prank(owner);
    mgr.setAllowListRoot(leaf);

    // Wrong target should revert
    vm.expectRevert(ManagerWithMerkleVerification.NotAllowed.selector);
    mgr.forward(address(0xDEAD), data, new bytes32[](0));

    // Correct target + data should succeed
    mgr.forward(address(target), data, new bytes32[](0));
    assertEq(target.stored(), 42);

    // Mutated data should revert (proof no longer matches)
    bytes memory bad = abi.encodeWithSelector(TargetMock.store.selector, uint256(43));
    vm.expectRevert(ManagerWithMerkleVerification.NotAllowed.selector);
    mgr.forward(address(target), bad, new bytes32[](0));
  }
}
