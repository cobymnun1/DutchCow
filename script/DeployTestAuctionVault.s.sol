// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {DeployAuctioneer} from "./DeployAuctioneer.s.sol";

/// @dev Legacy name. The test vault is gone; this deploys the auctioneer instead.
contract DeployTestAuctionVault is DeployAuctioneer {}
