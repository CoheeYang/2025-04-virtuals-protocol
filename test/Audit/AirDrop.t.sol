// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;
import "contracts/token/Airdrop.sol";
import {ERC20Mock} from "./Mocks/ERC20Mock.sol";
import "forge-std/Test.sol";

contract AidropTest is Test {
    ERC20Mock token = new ERC20Mock();
    Airdrop aidrop;
    address SENDER=address(1);
    address USER1=address(2);
    address USER2=address(3);

    function setUp() public {
        aidrop = new Airdrop();
        token.mint(SENDER, 10000 * 1e18);
    }

    function test_Airdrop() public {
        // Create dynamic arrays with size 2
        address[] memory users = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        // Assign values individually
        users[0] = USER1;
        users[1] = USER2;
        amounts[0] = 5000 * 1e18;
        amounts[1] = 5000 * 1e18;

        vm.startPrank(SENDER);
        token.approve(address(aidrop),type(uint256).max);


        aidrop.airdrop(IERC20(address(token)), users, amounts, 10000 * 1e18);

        vm.stopPrank();
        assertEq(token.balanceOf(USER1), 5000 * 1e18);
        assertEq(token.balanceOf(USER2), 5000 * 1e18);
        assertEq(token.balanceOf(SENDER), 0);
    }
}
