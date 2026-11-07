// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import {PlaceLocalForkOrder} from "./PlaceLocalForkOrder.s.sol";

/// @dev Legacy name. Places an auction through the current auctioneer.
contract CreateLocalForkOrder is PlaceLocalForkOrder {}
