// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {UniswapV3DecoderAndSanitizer} from "./UniswapV3DecoderAndSanitizer.sol";
import {PendleDecoderAndSanitizer} from "./PendleDecoderAndSanitizer.sol";
import {EulerDecoderAndSanitizer} from "./EulerDecoderAndSanitizer.sol";
import {ERC4626DecoderAndSanitizer} from "./ERC4626DecoderAndSanitizer.sol";

/// @title GiveAggregatorDecoderAndSanitizer (skeleton)
/// @notice Aggregates decoders and resolves selector collisions via overrides in derived contracts
abstract contract GiveAggregatorDecoderAndSanitizer is
  UniswapV3DecoderAndSanitizer,
  PendleDecoderAndSanitizer,
  EulerDecoderAndSanitizer,
  ERC4626DecoderAndSanitizer
{
  // Override duplicate selectors in concrete implementation
}

