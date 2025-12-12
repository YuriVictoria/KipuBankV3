// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import {IPermit2} from "https://github.com/Uniswap/permit2/blob/main/src/interfaces/IPermit2.sol";
import {IUniversalRouter} from "./IUniversalRouter.sol";


/// @title KipuBankV3
/// @author @YuriVictoria
contract KipuBankV3 is AccessControl {
    using SafeERC20 for IERC20;


    address public immutable addrUSDC;
    address public immutable addrWETH;
    IPermit2 public immutable permit;
    IUniversalRouter public immutable router;

    uint256 public constant TOLERANCE = 50; // 0.5%
    uint24 public constant POOL = 3000; // 0.3%

    /// @notice Token(address) to Chainlink oracle(address) 
    mapping(address => address) public tokenToOracle;
    
    /// @notice List of allowed tokens in this contract
    address[] public allowedTokenList;

    /// @notice Map User to balance in USDC
    mapping(address => uint256) private balance;
    
    /// @notice Map user(address) to qttDeposits(uint256)
    mapping(address => uint256) private qttDeposits;

    /// @notice Map user(address) to qttWithdrawals(uint256)
    mapping(address => uint256) private qttWithdrawals;

    /// @notice Limit to withdraw operation in USDC.
    uint256 public withdrawLimit;
    uint256 public withdrawLimitInUSDC;
    
    /// @notice Limit to bankCap in USDC
    uint256 public bankCap; 
    uint256 public bankCapInUSDC; 
    
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    /// @notice The Withdraw event 
    /// @param user who make the withdrawal
    /// @param value the withdrawal value
    event Withdrew(address indexed user, uint256 value);

    /// @notice The Deposit event 
    /// @param user who make the deposit
    /// @param token the deposit token
    /// @param value the deposit value
    event Deposited(address indexed user, address indexed token, uint256 value);
    
    /// @notice Set new withdrawLimit 
    /// @param newWithdrawLimit the new withdrawLimit in USDC
    event ChangeWithdrawLimit(uint256 newWithdrawLimit);

    /// @notice Set new bankCap in USDC
    /// @param newBankCap of new bankCap in USDC
    event ChangeBankCap(uint256 newBankCap);
    
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
    modifier hasBalance(uint256 _amount) {
        if (_amount > balance[msg.sender]) revert NoBalance();
        _;
    }

    /// @notice Revert if contract balance pass the bankCap
    /// @param _token The token being deposited
    /// @param _amount The amount of the token being deposited
    modifier inBankCap(address _token, uint256 _amount) {
        uint256 valueInUSDC = getTokenValueInUSDC(_token, _amount);
        if (IERC20(addrUSDC).balanceOf(address(this)) + valueInUSDC > bankCap) { revert BankCapLimit(); }
        _;
    }

    /// @notice Revert if try deposit 0
    modifier validDepositValue(uint256 _amount) {
        if (_amount == 0) revert NothingToDeposit();
        _;
    }

    /// @notice The deployer defines the withdrawnLimit and bankCap.
    /// @param _withdrawLimit Define the limit to withdraw in USDC
    /// @param _bankCap Define bank capacity in USDC
    constructor(
        uint256 _withdrawLimit,
        uint256 _bankCap,
        address _addrUSDC,
        address _permit,
        address _router,
        address _addrWETH
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);

        addrUSDC = _addrUSDC;
        permit = IPermit2(_permit);
        router = IUniversalRouter(_router);
        addrWETH = _addrWETH;
        withdrawLimit = _withdrawLimit;
        bankCap = _bankCap;
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

    /// @notice token to USDC token
    /// @param _token address token contract
    /// @param _amount qtt of token
    function getTokenValueInUSDC(address _token, uint256 _amount) public view returns (uint256) {
        address oracleAddr = tokenToOracle[_token];
        if (oracleAddr == address(0)) revert TokenNotAllowed();

        // Se o token for o próprio USDC, o valor é o próprio _amount.
        if (_token == addrUSDC) {
            return _amount;
        }

        AggregatorV3Interface oracle = AggregatorV3Interface(oracleAddr);
        (, int256 price, , , ) = oracle.latestRoundData();
        if (price <= 0) revert InvalidOraclePrice();

        uint8 tokenDecimals = (_token == address(0)) ? 18 : IERC20Metadata(_token).decimals();
        uint8 usdcDecimals = IERC20Metadata(addrUSDC).decimals();
        uint8 oracleDecimals = oracle.decimals();

        return (_amount * uint256(price) * (10 ** usdcDecimals)) / ((10 ** tokenDecimals) * (10 ** oracleDecimals));
    }

    /// @notice Verify conditions and make the deposit of msg.value
    function depositETH() external payable validDepositValue(msg.value) inBankCap(address(0), msg.value) {
        uint256 priceUSDCInChainlink = getTokenValueInUSDC(address(0), msg.value);
        uint256 minSwap = (priceUSDCInChainlink * (10000 - TOLERANCE)) / 10000;

        bytes memory path = abi.encodePacked(addrWETH, POOL, addrUSDC);

        bytes memory commands = abi.encodePacked(IUniversalRouter.V3_SWAP_EXACT_IN);

        // The input for V3_SWAP_EXACT_IN: (recipient, amountIn, amountOutMinimum, path, payerIsUser)
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(
            address(this),
            msg.value,
            minSwap,
            path,
            false
        );

        uint256 balanceBefore = IERC20(addrUSDC).balanceOf(address(this));

        // The call will revert if the swap produces less than minAmountOut, or if there's another issue.
        router.execute{value: msg.value}(commands, inputs, block.timestamp);

        uint256 balanceAfter = IERC20(addrUSDC).balanceOf(address(this));
        uint256 amountReceivedUSDC = balanceAfter - balanceBefore;

        balance[msg.sender] += amountReceivedUSDC;
        qttDeposits[msg.sender] += 1;
        emit Deposited(msg.sender, address(0), msg.value);
    }

    /// @notice Deposit Token ERC-20
    /// @param _token address of token contract
    /// @param _amount deposit amount
    function depositToken(address _token, uint256 _amount) external validDepositValue(_amount) inBankCap(_token, _amount) {
        if (_token == address(0)) revert("Use depositETH()");
        if (_token == addrUSDC) {
            IERC20(addrUSDC).safeTransferFrom(msg.sender, address(this), _amount);
            balance[msg.sender] += _amount;
            qttDeposits[msg.sender] += 1;
            emit Deposited(msg.sender, _token, _amount);
        } else {
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
            revert("Swap logic for this token is not yet implemented.");
        }
    }

    /// @notice withdrawUSDC
    /// @param _amountUSDC withdraw value
    function withdrawUSDC(uint256 _amountUSDC) external
    hasBalance(_amountUSDC)
    validWithdrawAmount(_amountUSDC)
    inWithdrawLimit(_amountUSDC) {
        balance[msg.sender] -= _amountUSDC;
        qttWithdrawals[msg.sender] += 1;
        emit Withdrew(msg.sender, _amountUSDC);

        IERC20(addrUSDC).safeTransfer(msg.sender, _amountUSDC);
    }

    /// @notice Get qttDeposits of msg.sender
    function getQttDeposits() external view returns (uint256) {
        return qttDeposits[msg.sender];
    }

    /// @notice Get qttWithdrawals of msg.sender
    function getQttWithdrawals() external view returns (uint256) {
        return qttWithdrawals[msg.sender];
    }

    /// @notice Get balance of msg.sender
    function getBalance() external view returns (uint256) {
        return balance[msg.sender];
    }

    /// @notice Set new bankCap
    /// @param _newBankCap new value of bankCap
    function setBankCap(uint256 _newBankCap) external onlyRole(MANAGER_ROLE) {
        bankCap = _newBankCap;
        emit ChangeBankCap(bankCap);
    }

    /// @notice Set withdrawLimit
    function setWithdrawLimit(uint256 _newWithdrawLimit) external onlyRole(MANAGER_ROLE) {
        withdrawLimit = _newWithdrawLimit;
        emit ChangeWithdrawLimit(_newWithdrawLimit);
    }

    /// @notice Get bankCap
    function getBankCap() external view returns (uint256) {
        return bankCap;
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
