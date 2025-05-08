// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FERC20 is Context, IERC20, Ownable {
    uint8 private constant _decimals = 18;

    uint256 private _totalSupply;

    string private _name;

    string private _symbol;

    uint public maxTx;//最大转账百分比

    uint256 private _maxTxAmount;//最大交易金额

    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(address => bool) private isExcludedFromMaxTx;

    event MaxTxUpdated(uint _maxTx);

    constructor(string memory name_, string memory symbol_, uint256 supply, uint _maxTx) Ownable(msg.sender) {
        _name = name_;

        _symbol = symbol_;

        _totalSupply = supply * 10 ** _decimals;

        _balances[_msgSender()] = _totalSupply;

        isExcludedFromMaxTx[_msgSender()] = true;//豁免最高transaction amount

        isExcludedFromMaxTx[address(this)] = true;

        _updateMaxTx(_maxTx);

        emit Transfer(address(0), _msgSender(), _totalSupply);
    }
//regular view 
    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }
//transaction functions
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);

        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);

        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);

        _approve(sender, _msgSender(), _allowances[sender][_msgSender()] - amount);

        return true;
    }

//internals
    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;

        emit Approval(owner, spender, amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        if (!isExcludedFromMaxTx[from]) {//非豁免地址
            require(amount <= _maxTxAmount, "Exceeds MaxTx");//
        }

        _balances[from] = _balances[from] - amount;
        _balances[to] = _balances[to] + amount;

        emit Transfer(from, to, amount);
    }

    function _updateMaxTx(uint _maxTx) internal {
        maxTx = _maxTx;
        _maxTxAmount = (maxTx * _totalSupply) / 100;//最大转账金额 = 百分比 * 总供应量

        emit MaxTxUpdated(_maxTx);
    }

    function _burn(address user, uint256 amount) internal {
        require(user != address(0), "Invalid address");
        _balances[user] = _balances[user] - amount;
    }
//onlyOwner functions
    function updateMaxTx(uint256 _maxTx) public onlyOwner {
        _updateMaxTx(_maxTx);
    }

    function excludeFromMaxTx(address user) public onlyOwner {
        require(user != address(0), "ERC20: Exclude Max Tx from the zero address");

        isExcludedFromMaxTx[user] = true;
    }


    function burnFrom(address user, uint256 amount) public onlyOwner {
        require(user != address(0), "Invalid address");
        _balances[user] = _balances[user] - amount;
        emit Transfer(user, address(0), amount);
    }
}
