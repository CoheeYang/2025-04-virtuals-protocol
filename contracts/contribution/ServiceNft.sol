// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/governance/IGovernor.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";//@audit 加了
import {ERC721EnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol"; //@audit 加了
import {ERC721URIStorageUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol"; //@audit 加了
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC5805} from "@openzeppelin/contracts/interfaces/IERC5805.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../virtualPersona/IAgentNft.sol";
import "../virtualPersona/IAgentDAO.sol";
import "./IContributionNft.sol";
import "./IServiceNft.sol";

contract ServiceNft is
    IServiceNft,
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    ERC721URIStorageUpgradeable,
    OwnableUpgradeable
{
    uint256 private _nextTokenId;

    address public personaNft;
    address public contributionNft;

    uint16 public datasetImpactWeight;

    mapping(uint256 tokenId => uint8 coreId) private _cores;
    mapping(uint256 tokenId => uint256 maturity) private _maturities;
    mapping(uint256 tokenId => uint256 impact) private _impacts;

    mapping(uint256 personaId => mapping(uint8 coreId => uint256 serviceId)) private _coreServices; // Latest service NFT id for a core
    mapping(uint256 personaId => mapping(uint8 coreId => uint256[] serviceId)) private _coreDatasets;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address initialAgentNft,
        address initialContributionNft,
        uint16 initialDatasetImpactWeight
    ) public initializer {
        __ERC721_init("Service", "VS");
        __ERC721Enumerable_init();
        __ERC721URIStorage_init();
        __Ownable_init(_msgSender());
        personaNft = initialAgentNft;
        contributionNft = initialContributionNft;
        datasetImpactWeight = initialDatasetImpactWeight;
    }

    function mint(uint256 virtualId, bytes32 descHash) public returns (uint256) {
        IAgentNft.VirtualInfo memory info = IAgentNft(personaNft).virtualInfo(virtualId);
        require(_msgSender() == info.dao, "Caller is not VIRTUAL DAO");//要求是virtualId对应的agentDao来进行mint

        IGovernor personaDAO = IGovernor(info.dao);
        //要求DAO的proposal是按照下面的格式来进行mint的
        bytes memory mintCalldata = abi.encodeWithSignature("mint(uint256,bytes32)", virtualId, descHash);
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        uint256[] memory values = new uint256[](1);//Risk 谁告诉你是0的？但是没用payable，确实也是0
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = mintCalldata;
        uint256 proposalId = personaDAO.hashProposal(targets, values, calldatas, descHash);//本次mint对应的DAO的proposalId

        _mint(info.tba, proposalId);
        _cores[proposalId] = IContributionNft(contributionNft).getCore(proposalId);//proposer在dao执行这个之前mint contribution
        // Calculate maturity
        _maturities[proposalId] = IAgentDAO(info.dao).getMaturity(proposalId);//最低10_000

        bool isModel = IContributionNft(contributionNft).isModel(proposalId);
        if (isModel) {
            emit CoreServiceUpdated(virtualId, _cores[proposalId], proposalId);
            updateImpact(virtualId, proposalId);
            _coreServices[virtualId][_cores[proposalId]] = proposalId;///// Latest service NFT id for a core
        } else {
            _coreDatasets[virtualId][_cores[proposalId]].push(proposalId);// 不是模型就更新data
        }

        emit NewService(proposalId, _cores[proposalId], _maturities[proposalId], _impacts[proposalId], isModel);

        return proposalId;
    }

    function updateImpact(uint256 virtualId, uint256 proposalId) public {
        // Calculate impact
        // Get current service maturity
        uint256 prevServiceId = _coreServices[virtualId][_cores[proposalId]];//之前的serviceId(Nft)
        uint256 rawImpact = (_maturities[proposalId] > _maturities[prevServiceId])
            ? _maturities[proposalId] - _maturities[prevServiceId]
            : 0;
        uint256 datasetId = IContributionNft(contributionNft).getDatasetId(proposalId);//dataId是contributionNft中预先随意输入的

        _impacts[proposalId] = rawImpact;//本次proposal产生impact，比如新的就是10_000
        if (datasetId > 0) {//dataId不是0就更新
            _impacts[datasetId] = (rawImpact * datasetImpactWeight) / 10000; //bug dataId随意输入，那我就可以改掉别人的impact
            _impacts[proposalId] = rawImpact - _impacts[datasetId];
            emit SetServiceScore(datasetId, _maturities[proposalId], _impacts[datasetId]);
            _maturities[datasetId] = _maturities[proposalId];
        }

        emit SetServiceScore(proposalId, _maturities[proposalId], _impacts[proposalId]);
    }

    function getCore(uint256 tokenId) public view returns (uint8) {
        _requireOwned(tokenId);
        return _cores[tokenId];
    }

    function getMaturity(uint256 tokenId) public view returns (uint256) {
        _requireOwned(tokenId);
        return _maturities[tokenId];
    }

    function getImpact(uint256 tokenId) public view returns (uint256) {
        _requireOwned(tokenId);//已经存在的，也就是只有proposalId被mint过才有用，否则没用
        return _impacts[tokenId];
    }

    function getCoreService(uint256 virtualId, uint8 coreType) public view returns (uint256) {
        return _coreServices[virtualId][coreType];
    }

    function getCoreDatasetAt(uint256 virtualId, uint8 coreType, uint256 index) public view returns (uint256) {
        return _coreDatasets[virtualId][coreType][index];
    }

    function totalCoreDatasets(uint256 virtualId, uint8 coreType) public view returns (uint256) {
        return _coreDatasets[virtualId][coreType].length;
    }

    function getCoreDatasets(uint256 virtualId, uint8 coreType) public view returns (uint256[] memory) {
        return _coreDatasets[virtualId][coreType];
    }

    function setDatasetImpactWeight(uint16 weight) public onlyOwner {
        datasetImpactWeight = weight;
        emit DatasetImpactUpdated(weight);
    }

    // The following functions are overrides required by Solidity.

    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721Upgradeable, ERC721URIStorageUpgradeable) returns (string memory) {
        // Service NFT is a mirror of Contribution NFT
        return IContributionNft(contributionNft).tokenURI(tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721Upgradeable, ERC721URIStorageUpgradeable, ERC721EnumerableUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _increaseBalance(
        address account,
        uint128 amount
    ) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
        return super._increaseBalance(account, amount);
    }

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) returns (address) {
        return super._update(to, tokenId, auth);
    }
}
