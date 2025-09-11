// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ManagerWithMerkleVerification} from "./ManagerWithMerkleVerification.sol";
import {ERC4626DecoderAndSanitizer} from "../decoders/ERC4626DecoderAndSanitizer.sol";

/// @title GiveManager
/// @notice Manager that derives allow-list leaves using decoder/sanitizer logic for supported selectors.
/// @dev FUTURE: Not required for MVP. Kept for future strategy integrations; not wired to deployment scripts.
contract GiveManager is ManagerWithMerkleVerification, ERC4626DecoderAndSanitizer {
  constructor(address _boringVault, address _owner) ManagerWithMerkleVerification(_boringVault, _owner) {}

  function _sanitizedData(address /*target*/, bytes4 selector, bytes calldata data)
    internal
    pure
    override
    returns (bytes memory)
  {
    (bytes memory san, bool handled) = _sanitizedERC4626(selector, data);
    if (handled) return san;
    // Fallback to default behavior (hash of full calldata) for unsupported selectors
    return abi.encode(keccak256(data));
  }
}
