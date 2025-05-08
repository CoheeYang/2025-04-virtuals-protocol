// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {UniswapV2Router02} from "lib/v2-periphery/contracts/UniswapV2Router02.sol";
import {UniswapV2Factory} from "lib/v2-core/contracts/UniswapV2Factory.sol";


contract UniswapSetup {
    address FEE_TO_SETTER = address(9111);
    address WETH = address(77111);
    UniswapV2Factory public uniswapFactory = new UniswapV2Factory(FEE_TO_SETTER);
    UniswapV2Router02 public uniswapRouter= new UniswapV2Router02(address(uniswapFactory), WETH);

    function testUniswap() internal view {
        assert(uniswapFactory.allPairsLength()==0);//test factory 
        assert(uniswapRouter.factory() == address(uniswapFactory));//test router
        assert(uniswapFactory.allPairsLength() == 0);//test factory
    }
}