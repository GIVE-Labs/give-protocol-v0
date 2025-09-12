// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20Decimals is ERC20 {
  uint8 private immutable _dec;
  constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
    _dec = decimals_;
  }
  function mint(address to, uint256 amount) external { _mint(to, amount); }
  function decimals() public view override returns (uint8) { return _dec; }
}

