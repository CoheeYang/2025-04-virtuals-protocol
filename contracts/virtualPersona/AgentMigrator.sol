// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/governance/IGovernor.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import {AgentNftV2} from "./AgentNftV2.sol";
import {IAgentNft} from "./IAgentNft.sol";
import "./IAgentVeToken.sol";
import "./IAgentDAO.sol";
import "./IAgentToken.sol";
//@audit 该合约没有
contract AgentMigrator is Ownable, Pausable {
    AgentNftV2 private _nft;

    bytes private _tokenSupplyParams;
    bytes private _tokenTaxParams;
    address private _tokenAdmin;
    address private _assetToken;
    address private _uniswapRouter;
    uint256 public initialAmount;
    address public tokenImplementation;
    address public daoImplementation;
    address public veTokenImplementation;
    uint256 public maturityDuration;

    mapping(uint256 => bool) public migratedAgents;

    bool internal locked;

    event AgentMigrated(uint256 virtualId, address dao, address token, address lp, address veToken);

    modifier noReentrant() {//ok
        require(!locked, "cannot reenter");
        locked = true;
        _;
        locked = false;
    }

    constructor(address agentNft_) Ownable(_msgSender()) {//ok
        _nft = AgentNftV2(agentNft_);
    }

    function setInitParams(
        address tokenAdmin_,
        address assetToken_,
        address uniswapRouter_,
        uint256 initialAmount_,
        uint256 maturityDuration_
    ) external onlyOwner {
        _tokenAdmin = tokenAdmin_;
        _assetToken = assetToken_;
        _uniswapRouter = uniswapRouter_;
        initialAmount = initialAmount_;
        maturityDuration = maturityDuration_;
    }

    function setTokenSupplyParams(
        uint256 maxSupply,
        uint256 lpSupply,
        uint256 vaultSupply,
        uint256 maxTokensPerWallet,
        uint256 maxTokensPerTxn,
        uint256 botProtectionDurationInSeconds,
        address vault
    ) public onlyOwner {//函数与factory一致
        _tokenSupplyParams = abi.encode(
            maxSupply,
            lpSupply,
            vaultSupply,
            maxTokensPerWallet,
            maxTokensPerTxn,
            botProtectionDurationInSeconds,
            vault
        );
    }

    function setTokenTaxParams(
        uint256 projectBuyTaxBasisPoints,
        uint256 projectSellTaxBasisPoints,
        uint256 taxSwapThresholdBasisPoints,
        address projectTaxRecipient
    ) public onlyOwner {//函数与factory一致
        _tokenTaxParams = abi.encode(
            projectBuyTaxBasisPoints,
            projectSellTaxBasisPoints,
            taxSwapThresholdBasisPoints,
            projectTaxRecipient
        );
    }

    function setImplementations(address token, address veToken, address dao) external onlyOwner {//函数与factory一致
        tokenImplementation = token;
        daoImplementation = dao;
        veTokenImplementation = veToken;
    }

    //⚠️主要出现问题的地方
    //migrate existing agents
    //如果迁移的是原来bonding/genesis的agent，会不会出问题
    //bonding中的supply参数和这里的参数不一样
    function migrateAgent(uint256 id, string memory name, string memory symbol, bool canStake) external noReentrant {
        //prechecks    
            //只允许一次，虽然该检查不能查到无中生有情况，但是后面的msg.sender检查保证了不会创建奇怪的agent
        require(!migratedAgents[id], "Agent already migrated");

        IAgentNft.VirtualInfo memory virtualInfo = _nft.virtualInfo(id);//ok
        address founder = virtualInfo.founder;//ok

            //检查founder与msg.sender一致性，founder是提交propose的人，也是执行prososal的人，不可能出现无中生有，因为founder只会通过mint赋值
        require(founder == _msgSender(), "Not founder");

            // Deploy Agent token & LP
        address token = _createNewAgentToken(name, symbol);//创建新的token，question 但是原来的合约中的钱呢？migrate之后的contributionNFT和serviceNFT还有用吗？
        address lp = IAgentToken(token).liquidityPools()[0];//和facotory一致
        //将assetToken从founder，也是msg.sender中转出（assetToken和initialAmount都被严格管理）
        IERC20(_assetToken).transferFrom(founder, token, initialAmount);//方法和原来factory基本一致IERC20(assetToken).transfer(token, initialAmount);
        IAgentToken(token).addInitialLiquidity(address(this));//和factory一致，但此时改变了lp owner

        // Deploy AgentVeToken
        address veToken = _createNewAgentVeToken(//和facotry一致
            string.concat("Staked ", name),
            string.concat("s", symbol),
            lp,
            founder,
            canStake
        );

        // Deploy DAO
        IGovernor oldDAO = IGovernor(virtualInfo.dao);//完全拷贝原来的内容，创建新的dao
        address payable dao = payable(
            _createNewDAO(oldDAO.name(), IVotes(veToken), uint32(oldDAO.votingPeriod()), oldDAO.proposalThreshold())
        );
        // Update AgentNft
        _nft.migrateVirtual(id, dao, token, lp, veToken);//更新四者内容

        IERC20(lp).approve(veToken, type(uint256).max);
        //bug 
        IAgentVeToken(veToken).stake(IERC20(lp).balanceOf(address(this)), founder, founder);//哥们是一点都没检查能不能stake啊

        migratedAgents[id] = true;

        emit AgentMigrated(id, dao, token, lp, veToken);
    }

//下面三个create函数均无更新factory中的public array，但是逻辑一致
    function _createNewDAO(//没有push
        string memory name,
        IVotes token,
        uint32 daoVotingPeriod,
        uint256 daoThreshold
    ) internal returns (address instance) {
        instance = Clones.clone(daoImplementation);
        IAgentDAO(instance).initialize(name, token, address(_nft), daoThreshold, daoVotingPeriod);
        //没有push
        return instance;
    }

    function _createNewAgentVeToken(//没有push
        string memory name,
        string memory symbol,
        address stakingAsset,
        address founder,
        bool canStake
    ) internal returns (address instance) {
        instance = Clones.clone(veTokenImplementation);
        IAgentVeToken(instance).initialize(
            name,
            symbol,
            founder,
            stakingAsset,
            block.timestamp + maturityDuration,
            address(_nft),
            canStake
        );
        //没有push: allTokens.push(instance);
        return instance;
    }
    //没有push
    function _createNewAgentToken(string memory name, string memory symbol) internal returns (address instance) {
        instance = Clones.clone(tokenImplementation);
        IAgentToken(instance).initialize(
            [_tokenAdmin, _uniswapRouter, _assetToken],
            abi.encode(name, symbol),
            _tokenSupplyParams,
            _tokenTaxParams
        );
        //@audit 没有像agentFacotry一样 allTradingTokens.push(instance);可能对用户会产生影响
        return instance;
    }
//////控制函数pause并没有加入函数控制
    function pause() external onlyOwner {
        super._pause();
    }

    function unpause() external onlyOwner {
        super._unpause();
    }

    function reset(uint256 id) external onlyOwner {
        migratedAgents[id] = false;
    }
}
