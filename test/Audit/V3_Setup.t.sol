// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AgentFactoryV3} from "contracts/virtualPersona/AgentFactoryV3.sol";
import {AgentToken} from "contracts/virtualPersona/AgentToken.sol";
import {AgentVeToken} from "../../contracts/virtualPersona/AgentVeToken.sol";
import {AgentDAO} from "../../contracts/virtualPersona/AgentDAO.sol";
import {ERC6551Registry} from "./Mocks/ERC6551.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {AgentNftV2} from "../../contracts/virtualPersona/AgentNftV2.sol";
import "./UniswapSetup.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {AgentMigrator} from "contracts/virtualPersona/AgentMigrator.sol";
import {ContributionNft} from "contracts/contribution/ContributionNft.sol";
import {ServiceNft} from "contracts/contribution/ServiceNft.sol";
import "contracts/fun/Bonding.sol";
import "contracts/tax/BondingTax.sol";
import {VirtualToken} from "contracts/token/Virtual.sol";
import "forge-std/Test.sol";

contract V3_SetUp is Test, UniswapSetup {
    //actors
    address ADMIN = address(99999999999); // admin of the contract
    address USER = address(8899); // user

//factory & nft
    AgentFactoryV3 agentFactory; //upgradeable
    AgentToken agentToken; //upgradeable
    AgentVeToken agentVeToken; //upgradeable
    AgentDAO agentDAO; //upgradeable
    ERC6551Registry tbaRegistry = new ERC6551Registry(); //token bound account registry, owned by the owner of nft
    VirtualToken assetToken;
    AgentNftV2 agentNft; //upgradeable
    AgentMigrator migrator; //migrator contract
    address VAULT = address(123); //// Vault to hold all Virtual NFTs

    //prameters for the test
    uint256 APP_THRESHOLD = 1000 * 1e18; // the amount of asset token to apply
    uint256 MATURE_DUR = 1000; // the maturity duration

    // TokenSupplyParams
    uint256 maxSupply = 1_000_000; // max supply of the agent token(max = lp + vault)，不需要乘以decimal
    uint256 lpSupply = 500_000; // lp supply of the token
    uint256 vaultSupply = 500_000; // vault supply of the token
    uint256 maxTokensPerWallet = 1000 * 1e18; // max tokens per wallet
    uint256 maxTokensPerTxn = 100 * 1e18; // max tokens per txn
    uint256 botProtectionDurationInSeconds = 1000; // bot protection duration in seconds
    address vault = VAULT;

    //Token tax parameters，bp =10_000
    uint256 projectBuyTaxBasisPoints = 100; // 1% buy tax
    uint256 projectSellTaxBasisPoints = 100; // 1% sell tax
    uint256 taxSwapThresholdBasisPoints = 500; // 5% tax swap threshold
    address projectTaxRecipient = ADMIN;

    //
    uint8[] cores = [1, 2, 3, 4, 5];

//fun part
    Bonding bonding;
    FFactory fFactory;
    FRouter fRouter;
    BondingTax bondingTax;
    ERC20Mock mockERC20; //mock token bonding tax 
    //bonding init params
    uint256 LAUNCH_FEE =100_000; //fee_，launch fee，此为 1000个token(带decimal)
    uint256 INIT_SUPPLY =1_000_000_000; //initial supply，和veToken一致，10亿
    uint256 ASSET_RATE =10_000; //assetRate_
    uint256 MAX_TX = 100; //maxTx for fERC20
    uint256 GRADUAL_THRESHOLD = 85_000_000 * 1e18; //gradual Threshold
    event Numbers(uint256,uint256,uint256);

//setUp
    function setUp() public {
        //Uniswap functionality test
        testUniswap();
       
        

        vm.startPrank(ADMIN);
        //pool for bonding tax 
        assetToken = new VirtualToken(1000 * 1e18, ADMIN); //mint 1000代币的assetToken给ADMIN，同时ADMIN是virtual的owner，可以随意mint token，总高供应量上限为10亿
        mockERC20 = new ERC20Mock();
        mockERC20.mint(ADMIN, 1000 * 1e18); //mint 1000代币的mock给ADMIN
        
        assetToken.approve(address(uniswapRouter), type(uint256).max); //approve给uniswapRouter
        mockERC20.approve(address(uniswapRouter), type(uint256).max); //approve给uniswapRouter

        createUniswapPool(address(assetToken), address(mockERC20)); 
        (uint256 amountA, uint256 amountB, uint256 lpTokens) = uniswapRouter.addLiquidity(
            address(assetToken),//tokenA
            address(mockERC20),//token B
            assetToken.balanceOf(ADMIN),//amountADesired
            mockERC20.balanceOf(ADMIN),//amountBDesired
            0,//min
            0,//min
            ADMIN,//swap token to this address 
            block.timestamp//deadline
        );




//v3 factory        
        console.log("Deploying factory...");
        //Deploy the implementations

        agentToken = new AgentToken();
        agentVeToken = new AgentVeToken();
        agentDAO = new AgentDAO();

        //Deploy proxies - each will create its own ProxyAdmin contract

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
            address(new AgentFactoryV3()),
            ADMIN,
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address,uint256,address,uint256)",
                address(agentToken), //tokenImplementation_
                address(agentVeToken), //veTokenImplementation_
                address(agentDAO),
                address(tbaRegistry),
                address(assetToken),
                address(agentNft),
                APP_THRESHOLD,
                VAULT,
                0 //nextId
            )
        );
        //Cast proxy to implementation
        agentFactory = AgentFactoryV3(address(agentFactoryProxy));

        //set parameters for the agentFactory
        agentFactory.setMaturityDuration(MATURE_DUR); // set maturity duration to 10
        agentFactory.setUniswapRouter(address(uniswapRouter));
        agentFactory.setTokenAdmin(ADMIN); // set agent token admin

        agentFactory.setTokenSupplyParams( //set Agent token supply params
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

        //NFT grant mint roles to the agentFactory and set params
        agentNft.grantRole(agentNft.MINTER_ROLE(), address(agentFactory));

     
//contributions
        TransparentUpgradeableProxy contributionNftProxy = new TransparentUpgradeableProxy(
            address(new ContributionNft()),
            ADMIN,
            abi.encodeWithSignature(
                "initialize(address)",
                address(agentNft) //the agentNft
            )
        );
        //Cast proxy to implementation
        ContributionNft contributionNft = ContributionNft(address(contributionNftProxy));

        TransparentUpgradeableProxy serviceNftProxy = new TransparentUpgradeableProxy(
            address(new ServiceNft()),
            ADMIN,
            abi.encodeWithSignature(
                "initialize(address,address,uint16)",
                address(agentNft), //initialAgentNft,
                address(contributionNft), ///initialContributionNft,
                    0//initialDatasetImpactWeight
            )
        );
        //cast proxy
        ServiceNft  serviceNft = ServiceNft(address(serviceNftProxy));

        agentNft.setContributionService(address(contributionNft), address(serviceNft));

//Migrator
        migrator = new AgentMigrator(address(agentNft));
        
        migrator.setInitParams(ADMIN,address(assetToken),address(uniswapRouter),agentFactory.applicationThreshold(),agentFactory.maturityDuration());    
        migrator.setTokenSupplyParams(maxSupply,
            lpSupply,
            vaultSupply,
            maxTokensPerWallet,
            maxTokensPerTxn,
            botProtectionDurationInSeconds,
            vault);
        migrator.setTokenTaxParams(
            projectBuyTaxBasisPoints,
            projectSellTaxBasisPoints,
            taxSwapThresholdBasisPoints,
            projectTaxRecipient
        );
        migrator.setImplementations(
            address(agentToken),
            address(agentDAO),
            address(agentVeToken)
        );
        agentNft.grantRole(agentNft.ADMIN_ROLE(), address(migrator));

//bondings
        console.log("Deploying bonding...");
    //fFactory
        TransparentUpgradeableProxy fFactoryProxy = new TransparentUpgradeableProxy(
            address(new FFactory()),
            ADMIN,
            abi.encodeWithSignature(
                "initialize(address,uint256,uint256)",
                VAULT, //tax vault, vault to receive tax
                1, // buyTax，在FRouter中被call，作为fERC20的buy/sell tax
                1 // sellTax，
            )
        );
        //Cast proxy to implementation
        fFactory = FFactory(address(fFactoryProxy));
        //setParam
        fFactory.grantRole(fFactory.ADMIN_ROLE(), ADMIN);

    //FRouter
        TransparentUpgradeableProxy fRouterProxy = new TransparentUpgradeableProxy(
            address(new FRouter()),
            ADMIN,
            abi.encodeWithSignature(
                "initialize(address,address)",
                address(fFactory), //facotry
                address(assetToken) //asset token
            )
        );
        //Cast proxy to implementation
        fRouter = FRouter(address(fRouterProxy));
        //setParam
        fFactory.setRouter(address(fRouter));
        fRouter.grantRole(fRouter.ADMIN_ROLE(), ADMIN);

    //Bonding tax
        TransparentUpgradeableProxy bondingTaxProxy = new TransparentUpgradeableProxy(
            address(new BondingTax()),
            ADMIN,
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address,uint256,uint256)",
                address(ADMIN), //default admin
                address(mockERC20), //asset token in Bonding tax(这里用这个mock假装一下)
                address(assetToken), //taxToken，不知道是不是assetToken
                address(uniswapRouter), //uniswap router
                address(fRouter), //bonding router
                address(VAULT), //treasury
                type(uint256).max-1, //minSwapThreshold
                type(uint256).max //maxSwapThreshold
            )
        );
        //Cast proxy to implementation
        bondingTax = BondingTax(address(bondingTaxProxy));
        //setParam
        fFactory.setTaxParams(address(bondingTax), 1, 1);
        //tax vault 和buy/sell tax，
        //当router的buy和sell函数查询fFactory的taxVault与fRouter的taxManager同为一个bondingTax就会call bondingTax的swapForAsset函数
        fRouter.setTaxManager(address(bondingTax));

    //Bonding
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



        //Cast proxy to implementation
        bonding = Bonding(address(bondingProxy));
        //setParam
        bonding.setDeployParams(
            Bonding.DeployParams({
                tbaSalt :keccak256(abi.encodePacked("salt")),
                tbaImplementation:address(tbaRegistry),
                daoVotingPeriod:100,
                daoThreshold:20
            })
        );
        ///call流程
        //Bonding:launchFor ->fFactory.createPair需要CREATOR_ROLE
        //                  ->fRouter.addInitialLiquidity等需要EXECUTOR_ROLE
        fFactory.grantRole(fFactory.CREATOR_ROLE(), address(bonding));
        fRouter.grantRole(fRouter.EXECUTOR_ROLE(), address(bonding));
        agentFactory.grantRole(agentFactory.BONDING_ROLE(),address(bonding));
   
        vm.stopPrank();
}


//Bonding生命周期测试
//1.launch
//2.buy/sell交互
//3.graduate
//4.graduate后的行动，比如migration
    function test_Launch() public {
    //precondtion
        vm.startPrank(ADMIN);//mint assetToken
        assetToken.mint(USER, INIT_SUPPLY*1e18 - GRADUAL_THRESHOLD); //mint USER 2备的fee，足够graduate
        //915000000000000000000000000
        vm.stopPrank();

    //action
        vm.startPrank(USER);
        assetToken.approve(address(bonding), type(uint256).max); //approve给bonding
        
        uint256 Purchase_Amount = bonding.fee()*2 ;//purchase Amount，太少了手续费归0，bondingTax转入0会revert

       (address fERC20,
       address pairAddress,// the address for fERC20 & assetToken 
       uint256 tokenId//the n th token that is launched in the bonding contract
       ) = bonding.launchFor(
            "launch",
            "$ticker",
            cores,
            "description",
            "image",
             ["urls", "", "", ""],
            Purchase_Amount,
            USER
        );

    //assertion
    assert(tokenId == 1); //the first token launched
    (uint256 rA,uint256 rB) = IFPair(pairAddress).getReserves();
    emit Numbers(IFPair(pairAddress).kLast(),rA,rB);
    vm.stopPrank();
    }

    function test_buyZero_sellZero() public {//通过
          test_Launch();
        vm.startPrank(USER);
        uint256 fTokenBalance_0 =FERC20(bonding.tokenInfos(0)).balanceOf(USER);
        uint256 assetTokenBalance_0 = assetToken.balanceOf(USER);
        // //sell 0，由于fERC20卖出，其transfer函数输入值必须大于0，不可
        /////buy 0由于也有amountIn>0的限制，不可
        //但是这不意味着用户不能frpmtRun，比如有人刚买了FERC20,我在它之前买然后再卖掉获得更多的vetoken
        bonding.buy(0, bonding.tokenInfos(0));
        uint256 fTokenBalance_1 =FERC20(bonding.tokenInfos(0)).balanceOf(USER);
        uint256 assetTokenBalance_1 = assetToken.balanceOf(USER);
        
        assert(fTokenBalance_0 == fTokenBalance_1);
        assert(assetTokenBalance_0 == assetTokenBalance_1);
        vm.stopPrank();
    }   


    function test_buyAndSell(uint256 amount) public {//通过
        test_Launch();
        vm.startPrank(USER);

        //preconditon
        uint256 fTokenBalance_0 =FERC20(bonding.tokenInfos(0)).balanceOf(USER);
        uint256 assetTokenBalance_0 = assetToken.balanceOf(USER);
           assetToken.approve(address(fRouter), type(uint256).max);
           FERC20(bonding.tokenInfos(0)).approve(address(fRouter), type(uint256).max);
        
        amount=bound(amount,1,99);//不会有tax
        //action
        //先买在卖
        bonding.buy(amount, bonding.tokenInfos(0));//拿assetToken买fToken
        uint256 fTokenIncreased = FERC20(bonding.tokenInfos(0)).balanceOf(USER) - fTokenBalance_0;
        bonding.sell(fTokenIncreased, bonding.tokenInfos(0));//拿fToken卖assetToken

        
        
        uint256 fTokenBalance_1 =FERC20(bonding.tokenInfos(0)).balanceOf(USER);
        uint256 assetTokenBalance_1 = assetToken.balanceOf(USER);
        //assertion
        assert(fTokenBalance_0 == fTokenBalance_1);
        assert(assetTokenBalance_0 == assetTokenBalance_1);
        vm.stopPrank();
    }

    // function test_sandwich() public{
    //     //TODO 
    //     三明治攻击，但是要考虑税的影响，税是固定1%，其实这也没多大影响，只是在卖（即卖出fToken以买入assetToken时）
    //     用户可能有个大额单，而其他人可以狙击这个大额单，让它换回的assetToken减少
    //     具体攻击路径就是我先买入fToken，它交易完我再卖，我就能获得更多的assetToken

    //     mitigation:给个minimal out的数值限制
    // }


    function test_sellAndBuy(uint256 amount) public {//通过
        test_Launch();
        vm.startPrank(USER);
         //preconditon
        uint256 fTokenBalance_0 =FERC20(bonding.tokenInfos(0)).balanceOf(USER);
        uint256 assetTokenBalance_0 = assetToken.balanceOf(USER);
           assetToken.approve(address(fRouter), type(uint256).max);
           FERC20(bonding.tokenInfos(0)).approve(address(fRouter), type(uint256).max);
          
        
        amount=bound(amount,1,99);//不会有tax
        
        //action
        //先卖再买
        bonding.sell(amount, bonding.tokenInfos(0));//拿assetToken买fToken
        uint256 assetIncreased = assetToken.balanceOf(USER) - assetTokenBalance_0;
        bonding.buy(assetIncreased, bonding.tokenInfos(0));//拿fToken卖assetToken

        uint256 fTokenBalance_1 =FERC20(bonding.tokenInfos(0)).balanceOf(USER);
        uint256 assetTokenBalance_1 = assetToken.balanceOf(USER);

        assert(fTokenBalance_0 == fTokenBalance_1);
        assert(assetTokenBalance_0 == assetTokenBalance_1);
        vm.stopPrank();
    }



    function test_graduate() public {
        test_Launch();
        vm.startPrank(USER);
         assetToken.approve(address(fRouter), type(uint256).max);
        //BUY TO graduate
        bonding.buy(assetToken.balanceOf(USER),bonding.tokenInfos(0));//所有的assetToken都买入fToken，此时正好毕业
    /*
    ///assetToken走向
        //此时买完，应该一部分全部付给bonding，之后转移给了pair
        //         另外一部分会作为tax转给bondingTax
        //买完默认graduate，这时候会将pair中的assetToken转给bonding
        //bonding call->`initFromBondingCurve`将这部分assetToken作为threshold转给AgentFactory，最终成为流动性池的流动性

    ///fToken
        //fToken在买的时候会转入pair，当graduate后这部分会全部被burn，
        //其他的在用户手中的通过unwrapToken一比一转化为agentToken，这部分转化的agentToken从pair中出
    ///AgentToken
        //总supply和fToken一致，一部分lp拿（gradual_Threshold部分）另外的所有都在pair中
    */



        console.log("current fToken in users' hand:",IERC20(bonding.tokenInfos(0)).balanceOf(USER));
        //999996688204015587736137305
        
        //unwrap fERC20 token for agent token
        address [] memory account  = new address[](1);
        account[0] = USER;
        bonding.unwrapToken(bonding.tokenInfos(0),account);
        
        
        
        
        //将手中的所有的fToken转化为agentToken,此时应该有（总供应-gradual）这么多的agentToke balance
        //此时id应该为1
        agentToken = AgentToken(payable(agentFactory.allTradingTokens(0)));//currentAgentToken address
        
        
        // assert(agentToken.balanceOf(USER) ==INIT_SUPPLY*1e18 - GRADUAL_THRESHOLD);
        //999996688204015587736137305//agentToken
        //915000000000000000000000000//assetToken，总共mint过的，但是实际上还有部分是给tax了
        //我操，只有这么点


        (address _vault, address token, address dao, address veToken) = agentNft.virtualInfos(1);
        
        assertEq(token, address(agentToken));
        vm.stopPrank();
    }   

    function test_migration() public {
        test_graduate();
        vm.startPrank(USER);
        //关于migration可能的问题：
        //Bonding方面：
        //1.原来的bonding中的supply参数和migrated的参数不一样
        //2. unwarp token那unwarp了个啥

        //contribution NFT相关的问题

        //由于改了nft中的virtualInfo导致的问题



    }




//helper functions
    function createUniswapPool(address token0, address token1) internal returns (address uniswapV2Pair_) {

        uniswapV2Pair_ = uniswapFactory.getPair(token0, token1);

        if (uniswapV2Pair_ == address(0)) {
            uniswapV2Pair_ = uniswapFactory.createPair(token0, token1);
        }
        
    }


}
