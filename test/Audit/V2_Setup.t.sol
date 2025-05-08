// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AgentFactoryV2} from "../../contracts/virtualPersona/AgentFactory.sol";
import {AgentToken} from "../../contracts/virtualPersona/AgentToken.sol";
import {AgentVeToken} from "../../contracts/virtualPersona/AgentVeToken.sol";
import {AgentDAO} from "../../contracts/virtualPersona/AgentDAO.sol";
import {ERC6551Registry} from "./Mocks/ERC6551.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {AgentNftV2} from "../../contracts/virtualPersona/AgentNftV2.sol";
import {UniswapSetup} from "./UniswapSetup.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {MinimalImplementation} from "./Mocks/MinimalImplementation.sol";
import "./Mocks/contributionMock.sol";
import {VirtualToken} from "contracts/token/Virtual.sol";
import "forge-std/Test.sol";

contract V2_SetUp is Test, UniswapSetup {
    AgentFactoryV2 agentFactory;//upgradeable
    AgentToken agentToken;//upgradeable
    AgentVeToken agentVeToken;//upgradeable
    AgentDAO agentDAO;//upgradeable
    ERC6551Registry tbaRegistry= new ERC6551Registry(); //token bound account registry, owned by the owner of nft
    ERC20Mock assetToken = new ERC20Mock();
    AgentNftV2 agentNft;//upgradeable
    VirtualToken virtualToken;

    // Deploy minimal implementation for proxies
    MinimalImplementation minimalImpl = new MinimalImplementation();

    address VAULT = address(123); //// Vault to hold all Virtual NFTs

    //prameters for the test
    uint256 APP_THRESHOLD = 1000* 1e18; // the amount of asset token to apply
    uint256 MATURE_DUR = 1000; // the maturity duration

    // TokenSupplyParams
    uint256 maxSupply = 1_000_000; // max supply of the agent token(max = lp + vault)，不需要乘以decimal
    uint256 lpSupply =500_000; // lp supply of the token
    uint256 vaultSupply = 500_000; // vault supply of the token
    uint256 maxTokensPerWallet = 1000 * 1e18; // max tokens per wallet
    uint256 maxTokensPerTxn = 100 * 1e18; // max tokens per txn
    uint256 botProtectionDurationInSeconds = 1000; // bot protection duration in seconds
    address vault = VAULT;

    //Token tax parameters，bp =10_000
    uint256 projectBuyTaxBasisPoints = 100; // 1% buy tax
    uint256 projectSellTaxBasisPoints = 100; // 1% sell tax
    uint256 taxSwapThresholdBasisPoints = 500;// 5% tax swap threshold
    address projectTaxRecipient = ADMIN;

    //actors
    address ADMIN = address(99999999999); // admin of the contract
    address USER = address(8899); // user


    //
    uint8[] cores = [1, 2, 3, 4, 5];
    
    function _getProxyAdmin(address proxy) internal view returns (address) {
        bytes32 adminSlot = vm.load(proxy, ERC1967Utils.ADMIN_SLOT);
        return address(uint160(uint256(adminSlot)));
    }
    function _getProxyImp(address proxy) internal view returns(address){
        bytes32 ImpSlot = vm.load(proxy,ERC1967Utils.IMPLEMENTATION_SLOT);
        return address(uint160(uint256(ImpSlot)));
    }

    function setUp() public 
{
    //Uniswap functionality test
        testUniswap();
            // //Deploy basic contracts:
            //     vm.startPrank(ADMIN);
            //     virtualToken = new VirtualToken(1000 * 1e18, ADMIN);//uint256 _initialSupply, address initialOwner
        
    vm.startPrank(ADMIN);
    //Deploy the implementations
        
        agentToken = new AgentToken();
        agentVeToken = new AgentVeToken();
        agentDAO = new AgentDAO();

    //Deploy proxies - each will create its own ProxyAdmin contract
        console.log("Deploying proxies...");

        TransparentUpgradeableProxy agentNftProxy = new TransparentUpgradeableProxy(
            address(new AgentNftV2()),
            ADMIN,
            abi.encodeWithSignature(
                "initialize(address)",
                 ADMIN //defaultAdmin
            )
        );  
            //Cast proxy to implementation
        agentNft = AgentNftV2(address(agentNftProxy));
    

        TransparentUpgradeableProxy agentFactoryProxy = new TransparentUpgradeableProxy(
            address(new AgentFactoryV2()),
            ADMIN,
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address,uint256,address,address)",
                address(agentToken), //tokenImplementation_
                address(agentVeToken), //veTokenImplementation_
                address(agentDAO),
                address(tbaRegistry),
                address(assetToken),
                address(agentNft),
                APP_THRESHOLD,
                VAULT,
                ADMIN
            )
        );
        //Cast proxy to implementation
        agentFactory = AgentFactoryV2(address(agentFactoryProxy));

    //set parameters for the agentFactory
         
        agentFactory.setMaturityDuration(MATURE_DUR); // set maturity duration to 10
        agentFactory.setUniswapRouter(address(uniswapRouter));
        agentFactory.setTokenAdmin(ADMIN); // set agent token admin

        agentFactory.setTokenSupplyParams(//set Agent token supply params
            maxSupply,
            lpSupply,
            vaultSupply,
            maxTokensPerWallet,
            maxTokensPerTxn,
            botProtectionDurationInSeconds,
            vault
        );

        agentFactory.setTokenTaxParams(
            projectBuyTaxBasisPoints,
            projectSellTaxBasisPoints,
            taxSwapThresholdBasisPoints,
            projectTaxRecipient
        );

    //NFI grant mint roles to the agentFactory and set params
        agentNft.grantRole(
            agentNft.MINTER_ROLE(),
            address(agentFactory)
        );

        agentNft.setContributionService(
            address(new ContributionNft()),
            address(new ServiceNft())
        );
    vm.stopPrank();
}

   

    function MakeProposal() public returns (uint256 id) {
        assetToken.mint(USER, APP_THRESHOLD);

        vm.startPrank(USER);

        assetToken.approve(address(agentFactory), APP_THRESHOLD);

        //make a proposal
         id = agentFactory.proposeAgent(
            "name",
            "symbol",
            "tokenURI",
            cores,
            bytes32("0x2"), // bytes32 tbaSalt
            address(123123123), //tbaImplementation ADDRESS
            1000, //uint32 daoVotingPeriod(non-zero)
            10 //uint256 daoThreshold 
        );

        //assert the proposal is created
        AgentFactoryV2.Application memory app = agentFactory.getApplication(id);
        assert(keccak256(abi.encodePacked(app.name)) == keccak256(abi.encodePacked("name")));
        vm.stopPrank();
    }


    function test_MakeWithdraw() public {
        uint256 id = MakeProposal();
        vm.startPrank(USER);
        //try  withdraw, and it would revert due to the proposal is not approved yet
        vm.expectRevert("Application is not matured yet");
        agentFactory.withdraw(id);

        //advance the block number to mature the proposal
        uint256 currentblockNumber = block.number;
        vm.roll(currentblockNumber+1);
        agentFactory.withdraw(id);
        assert(assetToken.balanceOf(USER) == APP_THRESHOLD);
        vm.stopPrank();
    }


    function test_ExecuteProposal() public returns(uint256 virtualId, address token, address dao, address tba, address veToken, address lp) {
        uint256 id = MakeProposal();
            
            vm.prank(USER);
                //try to execute the proposal
            (virtualId, token, dao, tba, veToken, lp)  = agentFactory.executeApplication(id,true);

        assert(virtualId == id);
        assert(token== agentFactory.allTradingTokens(0));
        assert(dao == agentFactory.allDAOs(0));

        assert(veToken == agentFactory.allTokens(0));
       


        //测试NFT中的view函数都对上了吗        
            assert(agentNft.virtualInfo(virtualId).tba== tba);
            assert(agentNft.virtualLP(virtualId).pool == lp);
            assert(agentNft.virtualLP(virtualId).veToken == veToken);
            assert(agentNft.stakingTokenToVirtualId(veToken) == virtualId);
            assert(agentNft.totalProposals(virtualId) == 0);//初始没有proposal
        
        //AgentToken中
            assert(lp ==AgentToken(payable(token)).liquidityPools()[0]);//lp是创建的token时创建的流动性池
            console.log(AgentToken(payable(token)).owner());

    }


    function test_DAO_propose() public {
        (,,address dao,,,) = test_ExecuteProposal();
        uint256 currentblockNumber = block.number;



        vm.roll(currentblockNumber+1);

        vm.startPrank(USER);
        //make a proposal,veToken是voting token
        address [] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas =new bytes[](1);
        string memory description;
        AgentDAO(payable(dao)).propose(targets,values,calldatas,description);
        //voteStart: block number:2, voteEnd: 1002

        uint256 proposalId = AgentDAO(payable(dao)).hashProposal(
            targets,
            values,
            calldatas,
            keccak256(bytes(description))
        );

        uint256 state1 = uint256(AgentDAO(payable(dao)).state(proposalId));//when the proposal is created, the state is 0, `snapshot >= currentTimepoint`
        vm.roll(currentblockNumber+2);
        uint256 state2 = uint256(AgentDAO(payable(dao)).state(proposalId));//deadline >= currentTimepoint 则是active，active可以提前投票来提前执行合约
        //         enum ProposalState {
        //     Pending,
        //     Active,
        //     Canceled,
        //     Defeated,
        //     Succeeded,
        //     Queued,
        //     Expired,
        //     Executed
    // }


        // //que--GovernorStorageUpgradeable
        // AgentDAO(payable(dao)).queue(proposalId);
        //[Revert] GovernorUnexpectedProposalState(73289935354017558079201407528452784216240740650700234447014645003792921763461 [7.328e76], 0, 0x0000000000000000000000000000000000000000000000000000000000000010)


        //execute
         AgentDAO(payable(dao)).execute(proposalId);

    }
///
    // function test_veToken_withdraw() public {

    //       (,,,,address veToken,) = ExecuteProposal();
    //       vm.prank(USER);
    //         //WITHDRAW WITH 0 
    //         AgentVeToken(veToken).withdraw(0);

    // }

        


        
}
