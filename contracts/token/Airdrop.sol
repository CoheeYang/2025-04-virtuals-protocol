pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Airdrop {
    /**
     *
     * @param _token ERC20 token to airdrop
     * @param _recipients list of recipients
     * @param _amounts list of amounts to send each recipient
     * @param _total total amount to transfer from caller
     */
    function airdrop(
        IERC20 _token,
        address[] calldata _recipients,
        uint256[] calldata _amounts,
        uint256 _total
    ) external {
        // bytes selector for transferFrom(address,address,uint256)
        bytes4 transferFrom = 0x23b872dd;
        // bytes selector for transfer(address,uint256)
        bytes4 transfer = 0xa9059cbb;

        assembly {
        ///call->transferFrom(msg.sender, address(this), _total)
            // store transferFrom selector
            let transferFromData := add(0x20, mload(0x40))//读取空闲指针指的后32字节的格子
            mstore(transferFromData, transferFrom)//存入transferFrom的selector
            // store caller address
            mstore(add(transferFromData, 0x04), caller())//selector后的位置存入caller地址
            // store address
            mstore(add(transferFromData, 0x24), address())//后面再存入这个合约的地址
            // store _total
            mstore(add(transferFromData, 0x44), _total)//总量
            // call transferFrom for _total
        ///return true
            if iszero(
                and(//要求返回true
                    // The arguments of `and` are evaluated from right to left.
                    or(eq(mload(0x00), 1), iszero(returndatasize())), // Returned 1 or nothing.
                    call(gas(), _token, 0, transferFromData, 0x64, 0x00, 0x20)//三个值加一个selector 所以是0x64
                )
            ) {
                revert(0, 0)
            }
        ///call->transfer(_recipients[i], _amounts[i])
            // store transfer selector
            let transferData := add(0x20, mload(0x40))//@audit 未更新空闲指针，最后还在原来的地方，可能会出问题
            mstore(transferData, transfer)

            // store length of _recipients
            let sz := _amounts.length

            // loop through _recipients
            for {
                let i := 0
            } lt(i, sz) {
                // increment i
                i := add(i, 1)
            } {
                // store offset for _amounts[i]
                let offset := mul(i, 0x20)
                // store _amounts[i]
                let amt := calldataload(add(_amounts.offset, offset))
                // store _recipients[i]
                let recp := calldataload(add(_recipients.offset, offset))
                // store _recipients[i] in transferData
                mstore(add(transferData, 0x04), recp)
                // store _amounts[i] in transferData
                mstore(add(transferData, 0x24), amt)
                // call transfer for _amounts[i] to _recipients[i]
                // Perform the transfer, reverting upon failure.
                if iszero(
                    and(
                        // The arguments of `and` are evaluated from right to left.
                        or(eq(mload(0x00), 1), iszero(returndatasize())), // Returned 1 or nothing.
                        call(gas(), _token, 0, transferData, 0x44, 0x00, 0x20)///call了之后会把数据返回到0x00的位置，
                    )
                ) {
                    revert(0, 0)
                }
            }
        }
    }
}
