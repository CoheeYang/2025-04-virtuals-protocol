// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "contracts/fun/Bonding.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract Bonding_launch is Test {

//fun part
    Bonding bonding;
    address fFactory=address(111);
    address fRouter = address(222);
    address agentFactory = address(333);
    
    address ADMIN = address(0x1234);
    address USER = address(0x123456);


    //bonding init params
    uint256 LAUNCH_FEE =100_000; //fee_，launch fee，此为 1000个token(带decimal)
    uint256 INIT_SUPPLY =1_000_000_000; //initial supply，和veToken一致，10亿
    uint256 ASSET_RATE =10_000; //assetRate_
    uint256 MAX_TX = 100; //maxTx for fERC20
    uint256 GRADUAL_THRESHOLD = 85_000_000 * 1e18; //gradual Threshold
    address VAULT = address(123); //// Vault to hold all Virtual NFTs

    uint8[] cores = [1, 2, 3, 4, 5];

    function setUp() public {
         TransparentUpgradeableProxy bondingProxy = new TransparentUpgradeableProxy(
            address(new Bonding()),
            ADMIN,
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,uint256,uint256,uint256,address,uint256)",
                address(fFactory), //factory
                address(fRouter), //router
                VAULT, // feeTo_ 我不确定是不是bondingTax
                LAUNCH_FEE, //fee_，launch fee，此为 1000个token(带decimal)
                INIT_SUPPLY, //initial supply，和veToken一致，10亿
                ASSET_RATE, //assetRate_
                MAX_TX, //maxTx for fERC20
                address(agentFactory), //agentFactory
                GRADUAL_THRESHOLD//gradual Threshold
            )
        );
         bonding = Bonding(address(bondingProxy));
    }


    function test_poc_launch() public {
        
        vm.prank(USER);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        bonding.launch(
            "launch",
            "$ticker",
            cores,
            "description",
            "image",
             ["urls", "", "", ""],
            1000000);
    


    }

}
