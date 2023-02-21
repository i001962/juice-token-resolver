//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct JB721TierDefifa {
  uint256 id;
  uint256 contributionFloor;
  uint256 lockedUntil;
  uint256 remainingQuantity;
  uint256 initialQuantity;
  uint256 votingUnits;
  uint256 reservedRate;
  address reservedTokenBeneficiary;
  uint256 royaltyRate;
  address royaltyBeneficiary;
  bytes32 encodedIPFSUri;
  uint256 category;
  bool allowManualMint;
  bool transfersPausable;
}