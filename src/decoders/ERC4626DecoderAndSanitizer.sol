// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ERC4626DecoderAndSanitizer
/// @notice Helpers to decode ERC-4626 function calldata and derive sanitized bytes for allow-listing
/// @dev FUTURE: MVP does not require decoder usage; kept for future strategy integrations.
abstract contract ERC4626DecoderAndSanitizer {
  bytes4 internal constant SELECTOR_DEPOSIT = bytes4(keccak256("deposit(uint256,address)"));
  bytes4 internal constant SELECTOR_WITHDRAW = bytes4(keccak256("withdraw(uint256,address,address)"));

  function _decodeERC4626_deposit(bytes calldata data)
    internal
    pure
    returns (uint256 assets, address receiver)
  {
    require(data.length >= 4 + 32 + 32, "bad len");
    // skip selector
    (assets, receiver) = abi.decode(data[4:], (uint256, address));
  }

  function _decodeERC4626_withdraw(bytes calldata data)
    internal
    pure
    returns (uint256 assets, address receiver, address owner)
  {
    require(data.length >= 4 + 32 + 32 + 32, "bad len");
    (assets, receiver, owner) = abi.decode(data[4:], (uint256, address, address));
  }

  /// @notice Produce sanitized bytes for known ERC-4626 selectors.
  /// @dev Example policy: only addresses (receiver/owner) are relevant for allow-listing; asset amounts are runtime.
  function _sanitizedERC4626(bytes4 selector, bytes calldata data) internal pure returns (bytes memory, bool handled) {
    if (selector == SELECTOR_DEPOSIT) {
      (, address receiver) = _decodeERC4626_deposit(data);
      return (abi.encode(receiver), true);
    }
    if (selector == SELECTOR_WITHDRAW) {
      (, address receiver, address owner) = _decodeERC4626_withdraw(data);
      return (abi.encode(receiver, owner), true);
    }
    return (bytes(""), false);
  }
}

