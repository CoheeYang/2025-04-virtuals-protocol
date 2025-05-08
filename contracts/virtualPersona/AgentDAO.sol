// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GovernorSettingsUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import {GovernorStorageUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorStorageUpgradeable.sol";
import {GovernorVotesQuorumFractionUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesQuorumFractionUpgradeable.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";//@audit 加了
import {IAgentDAO} from "./IAgentDAO.sol";
import {GovernorCountingSimpleUpgradeable} from "./GovernorCountingSimpleUpgradeable.sol"; //@audit 加了
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IContributionNft} from "../contribution/IContributionNft.sol";
import {IEloCalculator} from "./IEloCalculator.sol";
import {IServiceNft} from "../contribution/IServiceNft.sol";
import {IAgentNft} from "./IAgentNft.sol";
import {GovernorVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {GovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
contract AgentDAO is
    IAgentDAO,
    GovernorSettingsUpgradeable,
    GovernorCountingSimpleUpgradeable,
    GovernorStorageUpgradeable,
    GovernorVotesUpgradeable,
    GovernorVotesQuorumFractionUpgradeable
{
    using Checkpoints for Checkpoints.Trace208;

    mapping(address => Checkpoints.Trace208) private _scores;
    mapping(uint256 => uint256) private _proposalMaturities;

    error ERC5805FutureLookup(uint256 timepoint, uint48 clock);

    uint256 private _totalScore;

    address private _agentNft;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name,
        IVotes token,
        address agentNft,
        uint256 threshold,
        uint32 votingPeriod_
    ) external initializer {
        __Governor_init(name);
        __GovernorSettings_init(0, votingPeriod_, threshold);//initialVotingDelay, initialVotingPeriod, initialProposalThreshold
        __GovernorCountingSimple_init();//no function
        __GovernorVotes_init(token);//veToken
        __GovernorVotesQuorumFraction_init(5100);//`GovernorVotesQuorumFractionUpgradeable`中的存储的QuorumNumerator
        __GovernorStorage_init();//no function

        _agentNft = agentNft;
    }

    // The following functions are overrides required by Solidity.

    function votingDelay() public view override(GovernorUpgradeable, GovernorSettingsUpgradeable) returns (uint256) {
        return super.votingDelay();
    }//初始是0

    function votingPeriod() public view override(GovernorUpgradeable, GovernorSettingsUpgradeable) returns (uint256) {
        return super.votingPeriod();
    }

    function proposalThreshold()
        public
        view
        override(GovernorUpgradeable, GovernorSettingsUpgradeable)
        returns (uint256)
    {
        return super.proposalThreshold();//初始设置的运行提交threshold的值
        //并不清楚这个threshold指代的是哪个？GovernorUpgradeable中会return 0，如果那样会出bug
        //而GovernorSettingsUpgradeable中在initialization中设置好了threshold，这个是正确的
        //结果显示这里可以有效得到正确的threshold，结果正确
    }

    function propose(//是否存在reddundant的propose attack，我大量提交proposal导致社区无法投票或者无法获得奖励
        address[] memory targets,//target length不能为0，否则revert，且需要与calldata/values length一致
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override(GovernorUpgradeable) returns (uint256) {
        address proposer = _msgSender();

        if (!_isValidDescriptionForProposer(proposer, description)) {//没有什么限制，decription够短就可以跳过检查
            revert GovernorRestrictedProposer(proposer);
        }
        //clock()=vetoken.clock()出blockNumber
        uint256 proposerVotes = getVotes(proposer, clock() - 1);//可以正常测试
        //function from votesUpgradeable,会call veToken.getPastVotes:
                    //   function getPastVotes(address account, uint256 timepoint) public view virtual returns (uint256) {
                    //     VotesStorage storage $ = _getVotesStorage();
                    //     uint48 currentTimepoint = clock();
                    //     if (timepoint >= currentTimepoint) {
                    //         revert ERC5805FutureLookup(timepoint, currentTimepoint);
                    //     }
                    //     return $._delegateCheckpoints[account].upperLookupRecent(SafeCast.toUint48(timepoint));
                    // }

        uint256 votesThreshold = proposalThreshold();//ok
        address contributionNft = IAgentNft(_agentNft).getContributionNft();//ok
        if (proposerVotes < votesThreshold && proposer != IContributionNft(contributionNft).getAdmin()) {//ok
            revert GovernorInsufficientProposerVotes(proposer, proposerVotes, votesThreshold);
        }

        return _propose(targets, values, calldatas, description, proposer);
    }

    function _propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        address proposer
    ) internal override(GovernorUpgradeable, GovernorStorageUpgradeable) returns (uint256) {
        return super._propose(targets, values, calldatas, description, proposer);
    }

    function proposalCount() public view override(IAgentDAO, GovernorStorageUpgradeable) returns (uint256) {
        return super.proposalCount();
    }

    function scoreOf(address account) public view returns (uint256) {
        return _scores[account].latest();
    }

    function getPastScore(address account, uint256 timepoint) external view returns (uint256) {
        uint48 currentTimepoint = clock();
        if (timepoint >= currentTimepoint) {
            revert ERC5805FutureLookup(timepoint, currentTimepoint);
        }
        return _scores[account].upperLookupRecent(SafeCast.toUint48(timepoint));
    }
//castVoteWithReasonAndParams
    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal override returns (uint256) {
        bool votedPreviously = hasVoted(proposalId, account);//check whether the account has voted before

        uint256 weight = super._castVote(proposalId, account, support, reason, params);

        if (!votedPreviously && hasVoted(proposalId, account)) {//之前没投过，但是现在cast后投了
            ++_totalScore;
            _scores[account].push(SafeCast.toUint48(block.number), SafeCast.toUint208(scoreOf(account)) + 1);
            if (params.length > 0 && support == 1) {
                _updateMaturity(account, proposalId, weight, params);
            }
        }

        if (support == 1) {
            _tryAutoExecute(proposalId);
        }

        return weight;
    }

    // Auto execute when forVotes == totalSupply
    function _tryAutoExecute(uint256 proposalId) internal {
        (, uint256 forVotes, ) = proposalVotes(proposalId);
        if (forVotes == token().getPastTotalSupply(proposalSnapshot(proposalId))) {
            execute(proposalId);
        }
    }

    function _updateMaturity(address account, uint256 proposalId, uint256 weight, bytes memory params) internal {
        // Check is this a contribution proposal
        address contributionNft = IAgentNft(_agentNft).getContributionNft();
        address owner = IERC721(contributionNft).ownerOf(proposalId);//proposer在此之前有mint contribution nft
        if (owner == address(0)) {
            return;
        }

        bool isModel = IContributionNft(contributionNft).isModel(proposalId);//输入是model
        if (!isModel) {
            return;
        }

        uint8[] memory votes = abi.decode(params, (uint8[]));
        uint256 maturity = _calcMaturity(proposalId, votes);

        _proposalMaturities[proposalId] += (maturity * weight);

        emit ValidatorEloRating(proposalId, account, maturity, votes);
    }

    function _calcMaturity(uint256 proposalId, uint8[] memory votes) internal view returns (uint256) {
        address contributionNft = IAgentNft(_agentNft).getContributionNft();
        address serviceNft = IAgentNft(_agentNft).getServiceNft();
        uint256 virtualId = IContributionNft(contributionNft).tokenVirtualId(proposalId);
        uint8 core = IContributionNft(contributionNft).getCore(proposalId);//proposer在contribution nft中mint后就有，该输入可以被proposer随意输
        uint256 coreService = IServiceNft(serviceNft).getCoreService(virtualId, core);
        // All services start with 100 maturity
        uint256 maturity = 100;
        if (coreService > 0) {
            maturity = IServiceNft(serviceNft).getMaturity(coreService);
            maturity = IEloCalculator(IAgentNft(_agentNft).getEloCalculator()).battleElo(maturity, votes);
        }

        return maturity;
    }

    function getMaturity(uint256 proposalId) public view returns (uint256) {
        (, uint256 forVotes, ) = proposalVotes(proposalId);//赞成票
        return Math.min(10000, _proposalMaturities[proposalId] / forVotes);
    }

    function quorum(
        uint256 blockNumber
    ) public view override(GovernorUpgradeable, GovernorVotesQuorumFractionUpgradeable) returns (uint256) {
        return super.quorum(blockNumber);
    }

    function quorumDenominator() public pure override returns (uint256) {
        return 10000;
    }

    function state(uint256 proposalId) public view override(GovernorUpgradeable) returns (ProposalState) {
        // Allow early execution when reached 100% for votes
        ProposalState currentState = super.state(proposalId);
        if (currentState == ProposalState.Active) {
            (, uint256 forVotes, ) = proposalVotes(proposalId);
            if (forVotes == token().getPastTotalSupply(proposalSnapshot(proposalId))) {
                return ProposalState.Succeeded;
            }
        }
        return currentState;
    }

    function totalScore() public view override returns (uint256) {
        return _totalScore;
    }
}
