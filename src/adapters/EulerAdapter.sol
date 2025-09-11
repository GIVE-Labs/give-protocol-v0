// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAdapter} from "../interfaces/IAdapter.sol";

/// @title EulerAdapter (skeleton)
/// @notice Stateless adapter; no principal custody. Concrete logic to be implemented.
abstract contract EulerAdapter is IAdapter {
  address public immutable vault; // BoringVault target
  constructor(address _vault) { vault = _vault; }

  // IAdapter function to be implemented by concrete contract
  function reportHarvest(uint256 amount) external virtual;
}

