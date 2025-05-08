// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import {IServiceNft} from "contracts/contribution/IServiceNft.sol";
import {IContributionNft} from "contracts/contribution/IContributionNft.sol";

contract ContributionNft  {
    function getAdmin() public view returns (address) {
        return address(0);
    }


}


contract ServiceNft  {

}