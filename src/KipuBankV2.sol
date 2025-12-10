// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title KipuBankV2
/// @author @YuriVictoria
contract KipuBankV2 is AccessControl {

    /// @notice Token(address) to Chainlink oracle(address) 
    mapping(address => address) public tokenToOracle;
    
    /// @notice List of allowed tokens in this contract
    address[] public allowedTokenList;

    /// @notice Map Token to Map User, and user(address) to Token balance(uint256)
    mapping(address => mapping(address => uint256)) private balances;
    
    /// @notice Map user(address) to qttDeposits(uint256)
    mapping(address => uint256) private qttDeposits;

    /// @notice Map user(address) to qttWithdrawals(uint256)
    mapping(address => uint256) private qttWithdrawals;

    /// @notice Limit to withdraw operation.
    uint256 public withdrawLimit;
    
    /// @notice Limit to bankCap in USD
    uint256 public bankCapUSD; 
    
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice The Withdraw event 
    /// @param user who make the withdrawal
    /// @param token the withdraw token
    /// @param value the withdrawal value
    event Withdrew(address indexed user, address indexed token, uint256 value);

    /// @notice The Deposit event 
    /// @param user who make the deposit
    /// @param token the deposit token
    /// @param value the deposit value
    event Deposited(address indexed user, address indexed token, uint256 value);
    
    /// @notice Set new withdrawLimit 
    /// @param value of new withdrawLimit
    event ChangeWithdrawLimit(uint256 value);

    /// @notice Set new bankCapUSD
    /// @param value of new bankCapUSD
    event ChangeBankCapUSD(uint256 value);
    
    /// @notice Set new allowed token
    /// @param token address of new token
    /// @param oracle address of chainlink oracle
    event TokenConfigured(address token, address oracle);

    // ------ Erros ------

    /// @notice Thrown when the withdraw pass the withdrawLimit
    error WithdrawLimit();

    /// @notice Thrown when sender try withdraw a null amount
    error NothingToWithdraw();

    /// @notice Thrown when the withdraw amount is bigger than balance
    error NoBalance();

    /// @notice Thrown when the payment fail
    error FailWithdraw();

    /// @notice Thrown when the contract balance pass the bankCap
    error BankCapLimit();

    /// @notice Thrown when the sender try deposit a null value
    error NothingToDeposit();

    /// @notice Thrown when the sender try deposit a not allowed token
    error TokenNotAllowed();

    /// @notice Thrown when the oracle price is negative or zero
    error InvalidOraclePrice();

    /// @notice Revert if withdraw pass the limit
    /// @param _amount value of withdrawal
    modifier inWithdrawLimit(uint256 _amount) {
        if (_amount > withdrawLimit) revert WithdrawLimit();
        _;
    }

    /// @notice Revert if try withdraw null value
    /// @param _amount value of withdrawal
    modifier validWithdrawAmount(uint256 _amount) {
        if (_amount == 0) revert NothingToWithdraw();
        _;
    }

    /// @notice Revert if insufficient balance of token
    /// @param _amount value of withdraw
    /// @param _token address of contract token
    modifier hasBalance(address _token, uint256 _amount) {
        if (_amount > balances[_token][msg.sender]) revert NoBalance();
        _;
    }

    /// @notice Revert if contract balance in USD pass the bankCap
    modifier inBankCap(address _tokenIncoming, uint256 _amountIncoming) {
        uint256 incomingValueUSD = getTokenValueInUSD(_tokenIncoming, _amountIncoming);
        uint256 currentBankTotalUSD = getTotalBankValueInUSD();

        if (currentBankTotalUSD + incomingValueUSD > bankCapUSD) {
            revert BankCapLimit();
        }
        _;
    }

    /// @notice Revert if try deposit 0
    modifier validDepositValue(uint256 _amount) {                              
        if (_amount == 0) revert NothingToDeposit();
        _;
    }

    /// @notice The deployer defines the withdrawnLimit and bankCap.
    /// @param _withdrawLimit Define the limit to withdraw
    /// @param _bankCapUSD Define bank capacity in USD
    constructor(uint256 _withdrawLimit, uint256 _bankCapUSD) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);

        withdrawLimit = _withdrawLimit;
        bankCapUSD = _bankCapUSD;
    }

    /// @notice Allowed a new address Token with oracle
    /// @param _token address of Token (address(0) to ETH)
    /// @param _oracle address of Chainlink oracle
    function setAllowedToken(address _token, address _oracle) external onlyRole(MANAGER_ROLE) {
        if (tokenToOracle[_token] == address(0)) {
            allowedTokenList.push(_token);
        }   
        tokenToOracle[_token] = _oracle;
        emit TokenConfigured(_token, _oracle);
    }

    /// @notice token to USD token
    /// @param _token address token contract
    /// @param _amount qtt of token
    function getTokenValueInUSD(address _token, uint256 _amount) public view returns (uint256) {
        address oracleAddr = tokenToOracle[_token];
        if (oracleAddr == address(0)) revert TokenNotAllowed();

        AggregatorV3Interface oracle = AggregatorV3Interface(oracleAddr);
        (, int256 price, , , ) = oracle.latestRoundData();
        if (price <= 0) revert InvalidOraclePrice();
        uint256 priceUint = uint256(price);

        uint8 decimalsToken;
        if (_token == address(0)) {
            decimalsToken = 18;
        } else {
            decimalsToken = IERC20Metadata(_token).decimals();
        }

        return (_amount * priceUint * 1e10) / (10 ** decimalsToken);
    }

    /// @notice Calc the contract balance in that moment with loop
    function getTotalBankValueInUSD() public view returns (uint256 totalUSD) {
        for (uint i = 0; i < allowedTokenList.length; i++) {
            address token = allowedTokenList[i];
            uint256 balance;
            
            if (token == address(0)) {
                balance = address(this).balance;
            } else {
                balance = IERC20(token).balanceOf(address(this));
            }

            if (balance > 0) {
                totalUSD += getTokenValueInUSD(token, balance);
            }
        }
    }

    /// @notice Verify conditions and make the deposit of msg.value
    function depositETH() external payable validDepositValue(msg.value) inBankCap(address(0), msg.value) {
        balances[address(0)][msg.sender] += msg.value;
        qttDeposits[msg.sender] += 1;
        emit Deposited(msg.sender, address(0), msg.value);
    }

    /// @notice Deposit Token ERC-20
    /// @param _token address of token contract
    /// @param _amount deposit amount
    function depositToken(address _token, uint256 _amount) external validDepositValue(_amount) inBankCap(_token, _amount) {
        if (_token == address(0)) revert("Try depositETH");
        
        balances[_token][msg.sender] += _amount;
        qttDeposits[msg.sender] += 1;
        
        bool success = IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        require(success, "Transfer failed");

        emit Deposited(msg.sender, _token, _amount);
    }

    /// @notice Verify conditions and make the withdraw ETH of amount
    /// @param _amount value of withdraw
    function withdrawETH(uint256 _amount) external hasBalance(address(0), _amount) validWithdrawAmount(_amount) inWithdrawLimit(_amount) {
        balances[address(0)][msg.sender] -= _amount;
        qttWithdrawals[msg.sender] += 1;
        emit Withdrew(msg.sender, address(0), _amount);
        
        makePayETH(msg.sender, _amount);
    }

    /// @notice Make the payment
    /// @param _to who receive the payment
    /// @param _amount value of payment    
    function makePayETH(address _to, uint256 _amount) private {
        (bool ok,) = payable(_to).call{value: _amount}("");
        if (!ok) revert FailWithdraw();
    }

    /// @notice withdraw token
    /// @param _token the addres of token
    /// @param _amount withdraw value
    function withdrawToken(address _token, uint256 _amount) external hasBalance(_token, _amount) validWithdrawAmount(_amount) inWithdrawLimit(_amount) {
        if (_token == address(0)) revert("Use withdrawETH");

        balances[_token][msg.sender] -= _amount;
        qttWithdrawals[msg.sender] += 1;
        emit Withdrew(msg.sender, _token, _amount);

        bool success = IERC20(_token).transfer(msg.sender, _amount);
        if (!success) revert FailWithdraw();
    }

    /// @notice Get qttDeposits of msg.sender
    function getQttDeposits() external view returns (uint256) {
        return qttDeposits[msg.sender];
    }

    /// @notice Get qttWithdrawals of msg.sender
    function getQttWithdrawals() external view returns (uint256) {
        return qttWithdrawals[msg.sender];
    }

    /// @notice Get token balance of msg.sender
    /// @param _token address of contract token
    function getBalance(address _token) external view returns (uint256) {
        return balances[_token][msg.sender];
    }

    /// @notice Set new bankCapUSD
    /// @param _newBankCapUSD new value of bankCapUSD 
    function setBankCapUSD(uint256 _newBankCapUSD) external onlyRole(MANAGER_ROLE) {
        bankCapUSD = _newBankCapUSD;
        emit ChangeBankCapUSD(bankCapUSD);
    }

    /// @notice Set withdrawLimit
    function setWithdrawLimit(uint256 _newWithdrawLimit) external onlyRole(MANAGER_ROLE) {
        withdrawLimit = _newWithdrawLimit;
        emit ChangeWithdrawLimit(withdrawLimit);
    }

    /// @notice Get bankCapUSD
    function getBankCap() external view returns (uint256) {
        return bankCapUSD;
    }

    /// @notice Get withdrawLimit
    function getWithdrawLimit() external view returns (uint256) {
        return withdrawLimit;
    }

    /// @notice Prevent receiving stray ETH outside the intended flow
    receive() external payable {
        revert("use deposit()");
    }

    /// @notice Prevent receiving stray ETH outside the intended flow
    fallback() external payable {
        revert("invalid call");
    }
}
