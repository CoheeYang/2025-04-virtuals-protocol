// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "forge-std/Test.sol";
import "contracts/virtualPersona/AgentFactoryV3.sol";
import "contracts/virtualPersona/AgentFactoryV4.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract v4_migration is Test {
    AgentFactoryV3 agentFactoryV3;
    AgentFactoryV4 agentFactoryV4;
    TransparentUpgradeableProxy agentFactoryProxy;
    address ADMIN = address(0x1234);
    address proxyAdmin;
    //params
    address tokenImplementation_;
    address veTokenImplementation_;
    address daoImplementation_;
    address tbaRegistry_;
    address assetToken_;
    address nft_;
    uint256 applicationThreshold_;
    address vault_;
    uint256 nextId_;
    //helper function to get the proxy admin contract from TransparentUpgradeableProxy
    function _getProxyAdmin(address proxy) internal view returns (address) {
        bytes32 adminSlot = vm.load(proxy, ERC1967Utils.ADMIN_SLOT);
        return address(uint160(uint256(adminSlot)));
    }

    function setUp() public {
        vm.startPrank(ADMIN);
    //start from v3    
        //Deploy implementation
         agentFactoryProxy = new TransparentUpgradeableProxy(
            address(new AgentFactoryV3()),
            ADMIN,
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address,uint256,address,uint256)",
                tokenImplementation_,
                veTokenImplementation_,
                daoImplementation_,
                tbaRegistry_,
                assetToken_,
                nft_,
                applicationThreshold_,
                vault_,
                nextId_
            )
        );
        //Cast proxy to implementation
        agentFactoryV3 = AgentFactoryV3(address(agentFactoryProxy));
        agentFactoryV3.setTokenSupplyParams(0, 0, 0, 0, 0, 0, address(0));

    //upgrade to v4
                   //get upgrade admin
         proxyAdmin = _getProxyAdmin(address(agentFactoryProxy));

        /// the following code will revert with InvalidInitialization, note vm.expectRevert cannot catch this revert.
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(payable(address(agentFactoryProxy))),
            address(new AgentFactoryV4()),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address,uint256,address,uint256)",
                tokenImplementation_,
                veTokenImplementation_,
                daoImplementation_,
                tbaRegistry_,
                assetToken_,
                nft_,
                applicationThreshold_,
                vault_,
                nextId_
            )
        );
        //Cast proxy to implementation
        agentFactoryV4 = AgentFactoryV4(address(agentFactoryProxy));

        vm.stopPrank();
       
       
    }


        function test_invalidInitialization() public {

  
        }



    // function test_getTokenApplication() public {
     // agentFactoryV3.setTokenSupplyParams(0, 0, 0, 0, 0, 0, address(0));
    //     // Test the getTokenApplication function
    //     uint256 token = agentFactoryV4.getTokenApplication(address(0x123));
    //     console.log("Token Application: ", token);
    // }
}
