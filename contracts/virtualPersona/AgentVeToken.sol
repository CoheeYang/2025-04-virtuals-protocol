// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20VotesUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {IAgentVeToken} from "./IAgentVeToken.sol";
import {IAgentNft} from "./IAgentNft.sol";
import {ERC20Votes} from "./ERC20Votes.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract AgentVeToken is IAgentVeToken, ERC20Upgradeable, ERC20Votes {
    //继承了ERC20Upgradeable
    //继承了ERC20Votes->ERC20VotesUpgradeable
    //                ->VotesUpgradeable


    using SafeERC20 for IERC20;
    using Checkpoints for Checkpoints.Trace208;

    address public founder;
    address public assetToken; // This is the token that is staked
    address public agentNft;
    uint256 public matureAt; // The timestamp when the founder can withdraw the tokens
    bool public canStake; // To control private/public agent mode
    uint256 public initialLock; // Initial locked amount

    constructor() {
        _disableInitializers();
    }

    mapping(address => Checkpoints.Trace208) private _balanceCheckpoints;

    bool internal locked;

    modifier noReentrant() {
        require(!locked, "cannot reenter");
        locked = true;
        _;
        locked = false;
    }

    function initialize(
        string memory _name,
        string memory _symbol,
        address _founder,
        address _assetToken,
        uint256 _matureAt,
        address _agentNft,
        bool _canStake
    ) external initializer {
        __ERC20_init(_name, _symbol);
        __ERC20Votes_init();

        founder = _founder;
        matureAt = _matureAt;
        assetToken = _assetToken;//factory中是lp token，而非外部token
        agentNft = _agentNft;
        canStake = _canStake;
    }

    // Stakers have to stake their tokens and delegate to a validator
    //在factory新建App时，会将agentToken和assetToken的lp池的lp token在这里stake, 后面输入的两个地址均为proposer
    //stake amount是IERC20(lp).balanceOf(address(this))
    function stake(uint256 amount, address receiver, address delegatee) public {
        require(canStake || totalSupply() == 0, "Staking is disabled for private agent"); // Either public or first staker，first staker会在工厂中创建成为proposer本人

        address sender = _msgSender();
        require(amount > 0, "Cannot stake 0");
        require(IERC20(assetToken).balanceOf(sender) >= amount, "Insufficient asset token balance");
        require(IERC20(assetToken).allowance(sender, address(this)) >= amount, "Insufficient asset token allowance");

        IAgentNft registry = IAgentNft(agentNft);
        uint256 virtualId = registry.stakingTokenToVirtualId(address(this));//ok

        require(!registry.isBlacklisted(virtualId), "Agent Blacklisted");

        if (totalSupply() == 0) {
            initialLock = amount;
        }

        registry.addValidator(virtualId, delegatee);

        IERC20(assetToken).safeTransferFrom(sender, address(this), amount);
        _mint(receiver, amount);//和一般erc20一样


        //ERC20Votes._delegate(address account, address delegatee)->call
        //VotesUpgradeable._delegate(address account, address delegatee)->call
        // 更新了`VotesUpgradeable中的`$._delegatee[account] = delegatee;
        //以及 $._delegateCheckpoints[oldAccount]减少，$._delegateCheckpoints[NewAccount]减少
        _delegate(receiver, delegatee);//这段逻辑是更新votesUpgradeable中的存储，而delegate函数是公共的，也可以改变存储信息



        _balanceCheckpoints[receiver].push(clock(), SafeCast.toUint208(balanceOf(receiver)));
        //非常区奇怪，它改变的是_balanceCheckpoints这里的存储，而在`AgentDao::propose()`中找投票的是使用` uint256 proposerVotes = getVotes(proposer, clock() - 1);`,
        //而这个getVotes最终会call veToken.getPastVotes:这是来自VotesUpgradeable合约的函数，其找的是`0xe8b26c30fad74198956032a3533d903385d56dd795af560196f9c78d4af40d00`存储位置的数据
     
    }

    function setCanStake(bool _canStake) public {
        require(_msgSender() == founder, "Not founder");
        canStake = _canStake;
    }

    function setMatureAt(uint256 _matureAt) public {
        bytes32 ADMIN_ROLE = keccak256("ADMIN_ROLE");
        require(IAccessControl(agentNft).hasRole(ADMIN_ROLE, _msgSender()), "Not admin");
        matureAt = _matureAt;
    }

    function withdraw(uint256 amount) public noReentrant {
        //check 0 attack
        //front run?
        address sender = _msgSender();
        require(balanceOf(sender) >= amount, "Insufficient balance");

        if ((sender == founder) && ((balanceOf(sender) - amount) < initialLock)) {//要求founder的不能提早抽出，但是founder可以通过withdraw 0来更新日期
            require(block.timestamp >= matureAt, "Not mature yet");
        }

        _burn(sender, amount);
        _balanceCheckpoints[sender].push(clock(), SafeCast.toUint208(balanceOf(sender)));

        IERC20(assetToken).safeTransfer(sender, amount);
    }

    function getPastBalanceOf(address account, uint256 timepoint) public view returns (uint256) {
        uint48 currentTimepoint = clock();
        if (timepoint >= currentTimepoint) {
            revert ERC5805FutureLookup(timepoint, currentTimepoint);
        }
        return _balanceCheckpoints[account].upperLookupRecent(SafeCast.toUint48(timepoint));//找到最近的balance
    }

    // This is non-transferable token
    function transfer(address /*to*/, uint256 /*value*/) public override returns (bool) {//@audit 我能通过跨链等手段转移token吗？或者proposal来转移token吗？
        revert("Transfer not supported");
    }

    function transferFrom(address /*from*/, address /*to*/, uint256 /*value*/) public override returns (bool) {
        revert("Transfer not supported");
    }

    function approve(address /*spender*/, uint256 /*value*/) public override returns (bool) {
        revert("Approve not supported");
    }

    // The following functions are overrides required by Solidity.
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20Upgradeable, ERC20VotesUpgradeable) {
        super._update(from, to, value);
    }

    function getPastDelegates(address account, uint256 timepoint) public view returns (address) {
        return super._getPastDelegates(account, timepoint);
    }
}
