// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.8.0;

import "./Context.sol";
import "./IERC20.sol";
// A modification of OpenZeppelin ERC20
// Original can be found here: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol

// Very slow erc20 implementation. Limits release of the funds with emission rate in _beforeTokenTransfer().
// Even if there will be a vulnerability in upgradeable contracts defined in _beforeTokenTransfer(), it won't be devastating.
// Developers can't simply rug.
// Allowances are booleans now instead of uints and uni v2 router is hardcoded, so it achieves -7100 gas per trade on uni v2 post-Berlin
// _mint() and _burn() functions are removed.
// Token name and symbol can be changed.
// Bulk transfer allows to transact in bulk cheaper by making up to three times less store writes in comparison to regular erc-20 transfers

contract VSRERC20 is Context, IERC20 {
	event BulkTransfer(address indexed from, address[] indexed recipients, uint128[] amounts);
	event BulkTransferFrom(address[] indexed senders, uint128[] amounts, address indexed recipient);
	event NameSymbolChangedTo(string name, string symbol);
	struct Holder {uint128 balance;uint128 lock;}
	mapping (address => mapping (address => bool)) private _allowances;
	mapping (address => Holder) private _holders;

	string private _name;
	string private _symbol;
	address private _governance;
	uint88 private _nextBulkBlock;
	uint8 private _governanceSet;
//// variables for testing purposes. live it should all be hardcoded addresses
	address private _treasury;
	address private _founding;
	bool private _notInit;
	
	constructor (string memory n_, string memory s_) {_name = n_;_symbol = s_;_governance = msg.sender;_notInit = true;_holders[msg.sender].balance = 1e27;emit NameSymbolChangedTo(n_,s_);}
	function init(address c) public {require(msg.sender == _deployer && _notInit == true);delete _notInit; _founding = c;}
	modifier onlyGovernance() {require(msg.sender == _governance);_;}
	function withdrawn() public view returns(uint wthdrwn) {uint withd =  999e24 - _holders[_treasury].balance; return withd;}
	function name() public view returns (string memory) {return _name;}
	function symbol() public view returns (string memory) {return _symbol;}
	function totalSupply() public view override returns (uint) {uint supply = (block.number - 12559000)*42e16+1e24;if (supply > 1e27) {supply = 1e27;}return supply;}
	function decimals() public pure returns (uint) {return 18;}
	function balanceOf(address a) public view override returns (uint) {return _holders[a].balance;}
	function transfer(address recipient, uint amount) public override returns (bool) {_transfer(_msgSender(), recipient, amount);return true;}
	function disallow(address spender) public virtual returns (bool) {delete _allowances[owner][spender];emit Approval(owner, spender, 0);return true;}
	function setNameSymbol(string memory n_, string memory s_) public onlyGovernance {_name = n_;_symbol = s_;emit NameSymbolChangedTo(n_,s_);}
	function setGovernance(address a) public onlyGovernance {require(_governanceSet < 3);_governanceSet += 1;_governance = a;}
	function _isContract(address a) internal view returns(bool) {uint256 s_;assembly {s_ := extcodesize(a)}return s_ > 0;}

	function approve(address spender, uint256 amount) public virtual override returns (bool) { // hardcoded mainnet uniswapv2 router 02, transfer helper library
		if (spender == 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D) {emit Approval(owner, spender, 2**256 - 1);return true;}
		else {_allowances[owner][spender] = true;emit Approval(owner, spender, 2**256 - 1);return true;}
	}

	function allowance(address owner, address spender) public view override returns (uint) { // hardcoded mainnet uniswapv2 router 02, transfer helper library
		if (spender == 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D||_allowances[owner][spender] == true) {return 2**256 - 1;} else {return 0;}
	}

	function transferFrom(address sender, address recipient, uint amount) public override returns (bool) { // hardcoded mainnet uniswapv2 router 02, transfer helper library
		require(_msgSender() == 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D||_allowances[sender][_msgSender()] == true);_transfer(sender, recipient, amount);return true;
	}

	function _transfer(address sender, address recipient, uint amount) internal {
		require(sender != address(0) && recipient != address(0));
		_beforeTokenTransfer(sender, amount);
		uint senderBalance = _holders[sender].balance;
		require(senderBalance >= amount);
		if (senderBalance == amount) {delete _holders[sender].balance;} else {_holders[sender].balance = uint128(senderBalance - amount);}
		_holders[recipient].balance += uint128(amount);
		emit Transfer(sender, recipient, amount);
	}

	function bulkTransfer(address[] memory recipients, uint128[] memory amounts) public returns (bool) { // will be used by the contract, or anybody who wants to use it
		require(recipients.length == amounts.length && amounts.length < 100,"human error");
		require(block.number >= _nextBulkBlock);
		_nextBulkBlock = uint88(block.number + 20);
		uint128 senderBalance = _holders[msg.sender].balance;
		uint128 total;
		for(uint i = 0;i<amounts.length;i++) {if (recipients[i] != address(0) && amounts[i] > 0) {total += amounts[i];_holders[recipients[i]].balance += amounts[i];}else{revert();}}
		require(senderBalance >= total);
		if (msg.sender == _treasury) {_beforeTokenTransfer(msg.sender, total);}
		if (senderBalance == total) {delete _holders[msg.sender].balance;} else {_holders[sender].balance = senderBalance - total;}
		emit BulkTransfer(_msgSender(), recipients, amounts);
		return true;
	}

	function bulkTransferFrom(address[] memory senders, address recipient, uint128[] memory amounts) public returns (bool) {
		require(senders.length == amounts.length && amounts.length < 100,"human error");
		require(block.number >= _nextBulkBlock);
		_nextBulkBlock = uint88(block.number + 20);
		uint128 total;
		uint128 senderBalance;
		for (uint i = 0;i<amounts.length;i++) {
			senderBalance = _holders[senders[i]].balance;
			if (amounts[i] > 0 && senderBalance >= amounts[i] && _allowances[senders[i]][_msgSender()]== true){
				total+= amounts[i];	_holders[senders[i]].balance = senderBalance - total;//does not delete if empty, since it could be just trading
			} else {revert();}
		}
		_holders[_msgSender()].balance += total;
		emit BulkTransferFrom(senders, amounts, recipient);
		return true;
	}

	function _beforeTokenTransfer(address from, uint amount) internal {
		if(block.number < 12559000) {require(msg.sender == _founding || msg.sender == _governance);}
		if (from == _treasury) {// hardcoded address
			require(block.number > 12559000 && block.number > _holders[msg.sender].lock);
			_holders[msg.sender].lock = uint128(block.number+600);
			uint treasury = _holders[_treasury].balance;
			uint withd =  999e24 - treasury;
			uint allowed = (block.number - 12559000)*42e16 - withd;
			require(amount <= allowed && amount <= treasury);
		}
	}
}
