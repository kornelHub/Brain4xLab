pragma solidity 0.7.0;

import "./IERC20.sol";
import "./IMintableToken.sol";
import "./IDividends.sol";
import "./SafeMath.sol";

contract Token is IERC20, IMintableToken, IDividends {
    // ------------------------------------------ //
    // ----- BEGIN: DO NOT EDIT THIS SECTION ---- //
    // ------------------------------------------ //
    using SafeMath for uint256;
    uint256 public totalSupply;
    uint256 public decimals = 18;
    string public name = "Test token";
    string public symbol = "TEST";
    mapping(address => uint256) public balanceOf;
    // ------------------------------------------ //
    // ----- END: DO NOT EDIT THIS SECTION ------ //
    // ------------------------------------------ //
    mapping(address => mapping(address => uint256)) private _allowance;

    address[] private _tokenHolders;
    mapping(address => uint256) private _holderIndex;
    mapping(address => uint256) private _withdrawableDividend;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event DividendWithdrawn(address indexed payee, address indexed dest, uint256 amount);
    event NativeTokensWithdrawn(address indexed dest, uint256 amount);
    // IERC20

    /// @notice Get the allowance for a given spender to spend tokens from a given owner
    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowance[owner][spender];
    }

    /// @notice Approve a spender to spend a given amount of tokens
    function approve(address spender, uint256 value) external override returns (bool) {
        require(spender != address(0), "Approve to the zero address");

        _allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    /// @notice Transfer tokens to a given address
    function transfer(address to, uint256 value) external override returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /// @notice Transfer tokens from a given address to a given address
    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        require(from != address(0), "Transfer from the zero address");
        require(
            _allowance[from][msg.sender] >= value,
            "Transfer amount exceeds allowance"
        );

        _allowance[from][msg.sender] = _allowance[from][msg.sender].sub(value);

        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(to != address(0), "Transfer to the zero address");
        require(balanceOf[from] >= value, "Transfer amount exceeds balance");

        balanceOf[from] = balanceOf[from].sub(value);
        balanceOf[to] = balanceOf[to].add(value);

        if (balanceOf[from] == 0) {
            _removeHolder(from);
        }

        _addHolderIfNotExists(to);

        emit Transfer(from, to, value);
    }

    // IMintableToken

    /// @notice Mint new tokens to the caller's address
    function mint() external payable override {
        require(msg.value > 0, "Mint amount must be greater than 0");

        balanceOf[msg.sender] = balanceOf[msg.sender].add(msg.value);
        totalSupply = totalSupply.add(msg.value);

        _addHolderIfNotExists(msg.sender);

        emit Transfer(address(0), msg.sender, msg.value);
    }

    /// @notice Burn caller's token balance and send the equivalent amount of ETH to given destination address
    function burn(address payable dest) external override {
        require(dest != address(0), "Burn to the zero address");
        require(balanceOf[msg.sender] > 0, "Burner has no balance");

        uint256 userBalance = balanceOf[msg.sender];
        balanceOf[msg.sender] = 0;
        totalSupply = totalSupply.sub(userBalance);

        _removeHolder(msg.sender);

        _withdrawnNativeTokens(dest, userBalance);

        emit Transfer(msg.sender, address(0), userBalance);
    }

    // IDividends
    /// @notice Get the number of token holders with non-zero balance
    function getNumTokenHolders() external view override returns (uint256) {
        return _tokenHolders.length;
    }

    /// @notice Get the address at the given index in the list of token holders with a non-zero balance
    function getTokenHolder(uint256 index) external view override returns (address) {
        if (index == 0 || index > _tokenHolders.length) return address(0);
        return _tokenHolders[index - 1];
    }

    function recordDividend() external payable override {
        require(msg.value > 0, "Dividend amount must be greater than 0");
        require(totalSupply > 0, "No active token holders");

        uint256 holdersCount = _tokenHolders.length;
        uint256 totalDividend = msg.value;
        uint256 sumOfDistributedDividend;

        for (uint256 i; i < holdersCount; i++) {
            address holder = _tokenHolders[i];
            uint256 holderBalance = balanceOf[holder];
            uint256 dividendForHolder = totalDividend.mul(holderBalance).div(
                totalSupply
            );
            _withdrawableDividend[holder] = _withdrawableDividend[holder].add(
                dividendForHolder
            );
            sumOfDistributedDividend = sumOfDistributedDividend.add(dividendForHolder);
        }
        
        if (totalDividend > sumOfDistributedDividend) {
            _withdrawnNativeTokens(msg.sender, totalDividend - sumOfDistributedDividend);
        }
    }

    /// @notice Get current withdrawable dividend for given payee
    function getWithdrawableDividend(address payee) external view override returns (uint256) {
        return _withdrawableDividend[payee];
    }

    /// @notice Withdraw dividend assigned to caller to given destination address
    function withdrawDividend(address payable dest) external override {
        require(dest != address(0), "Withdraw to the zero address");
        require(
            _withdrawableDividend[msg.sender] > 0,
            "Withdrawable dividend is 0"
        );
        uint256 amount = _withdrawableDividend[msg.sender];
        _withdrawableDividend[msg.sender] = 0;

        _withdrawnNativeTokens(dest, amount);

        emit DividendWithdrawn(msg.sender, dest, amount);
    }

    /// @dev Remove a holder from the list of token holders
    function _removeHolder(address holder) internal {
        require(holder != address(0), "Holder is the zero address");
        require(_holderIndex[holder] > 0, "Holder not found");

        uint256 holderIndex = _holderIndex[holder] - 1;
        uint256 lastIndex = _tokenHolders.length - 1;
        address lastHolder = _tokenHolders[lastIndex];

        if (holderIndex != lastIndex) {
            _tokenHolders[holderIndex] = lastHolder;
            _holderIndex[lastHolder] = holderIndex + 1;
        }
        _tokenHolders.pop();
        delete _holderIndex[holder];
    }

    /// @dev Add a holder to the list of token holders if they don't exist
    function _addHolderIfNotExists(address holder) internal {
        if (_holderIndex[holder] == 0 && balanceOf[holder] > 0) {
            _tokenHolders.push(holder);
            _holderIndex[holder] = _tokenHolders.length;
        }
    }

    /// @dev Withdraw native tokens to a destination address
    function _withdrawnNativeTokens(address dest, uint256 amount) internal {
        require(dest != address(0), "Withdraw to the zero address");
        require(amount > 0, "Withdraw amount must be greater than 0");

        (bool success, ) = dest.call{value: amount}("");
        require(success, "Transfer failed");

        emit NativeTokensWithdrawn(dest, amount);
    }
}