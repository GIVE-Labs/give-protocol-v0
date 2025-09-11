// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {GiveManager} from "src/manager/GiveManager.sol";
import {MockERC4626Target} from "src/mocks/MockERC4626Target.sol";

contract Test06_Decoder_ERC4626 is Test {
  GiveManager mgr;
  MockERC4626Target target;
  address owner = address(0xA11CE);
  address receiver = address(0xBEEF);

  function setUp() public {
    target = new MockERC4626Target();
    mgr = new GiveManager(address(0x1234), owner);
  }

  function _leaf(address _target, bytes4 selector, bytes memory sanitized) internal pure returns (bytes32) {
    return keccak256(abi.encode(_target, selector, keccak256(sanitized)));
  }

  /// @notice Authorized deposit with sanitized receiver passes; mutated receiver fails
  function test_Decoder_ERC4626_Deposit_Sanitized() public {
    bytes4 sel = MockERC4626Target.deposit.selector; // deposit(uint256,address)
    bytes memory data = abi.encodeWithSelector(sel, uint256(123), receiver);
    // Manager sanitizes to (receiver)
    bytes memory sanitized = abi.encode(receiver);
    bytes32 root = _leaf(address(target), sel, sanitized);
    vm.prank(owner);
    mgr.setAllowListRoot(root);

    // Correct call succeeds
    mgr.forward(address(target), data, new bytes32[](0));
    assertEq(target.lastReceiver(), receiver);
    assertEq(target.lastAssets(), 123);

    // Mutate receiver; proof should fail
    bytes memory bad = abi.encodeWithSelector(sel, uint256(123), address(0xD00D));
    vm.expectRevert(bytes4(keccak256("NotAllowed()")));
    mgr.forward(address(target), bad, new bytes32[](0));
  }
}
