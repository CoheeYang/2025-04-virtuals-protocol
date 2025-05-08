// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// import {AgentFactoryV2} from "../../contracts/virtualPersona/AgentFactory.sol";
// import {AgentToken} from "../../contracts/virtualPersona/AgentToken.sol";
// import {AgentVeToken} from "../../contracts/virtualPersona/AgentVeToken.sol";
// import {AgentDAO} from "../../contracts/virtualPersona/AgentDAO.sol";
// import {ERC6551Registry} from "./Mocks/ERC6551.sol";
// import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
// import {AgentNftV2} from "../../contracts/virtualPersona/AgentNftV2.sol";
// import {UniswapSetup} from "./UniswapSetup.sol";
 import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
 import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
// import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
// import {VirtualToken} from "contracts/token/Virtual.sol";
// import {Genesis} from "contracts/genesis/Genesis.sol";
import "contracts/genesis/FGenesis.sol";
import "forge-std/Test.sol";






contract GenesisSetup {
    FGenesis fGenesis;

    FGenesis.Params params;

    function genesisSetup(
        address _virtualToken,
        uint256 _reserve,
        uint256 _maxContribution,
        address _feeAddr,
        uint256 _feeAmt,
        uint256 _duration,
        bytes32 _tbaSalt,
        address _tbaImpl,
        uint32 _votePeriod,
        uint256 _threshold,
        address _agentFactory,
        uint256 _agentTokenTotalSupply,
        uint256 _agentTokenLpSupply
    ) public returns(address){
        params = 
        FGenesis.Params({
            virtualToken: _virtualToken,
            reserve: _reserve,
            maxContribution: _maxContribution,
            feeAddr: _feeAddr,
            feeAmt: _feeAmt,
            duration: _duration,
            tbaSalt: _tbaSalt,
            tbaImpl: _tbaImpl,
            votePeriod: _votePeriod,
            threshold: _threshold,
            agentFactory: _agentFactory,
            agentTokenTotalSupply: _agentTokenTotalSupply,
            agentTokenLpSupply: _agentTokenLpSupply
        });
    
    
     TransparentUpgradeableProxy FGenesisProxy = new TransparentUpgradeableProxy(
            address(new FGenesis()),
            msg.sender,
            abi.encodeWithSignature(
                "initialize(Params)",
                  params
            )
        );  

    return address(FGenesisProxy);
    
    }

    

   

    
    

}