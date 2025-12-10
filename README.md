# KipuBankV2

## Description
KipuBankV2 is an advanced DeFi banking contract designed to simulate a production-ready environment. Unlike its predecessor, this version introduces multi-token support (ERC-20 and Native ETH), role-based access control, and real-time asset valuation using Chainlink Data Feeds.

The bank enforces a global deposit limit based on the **USD value** of all assets held, ensuring economic stability regardless of the volatility of individual tokens.

## Key Features

* **Multi-Token Support:** Users can deposit and withdraw both Native ETH and whitelisted ERC-20 tokens.
* **Chainlink Oracle Integration:** Uses Chainlink AggregatorV3 to normalize decimals and calculate the real-time USD value of deposits.
* **Role-Based Access Control:** Implements OpenZeppelin's `AccessControl` to separate `DEFAULT_ADMIN_ROLE` from `MANAGER_ROLE` for operational security.
* **Mark-to-Market Accounting:** The total bank capacity is calculated dynamically based on current prices, not just historical deposit values.
* **Safety Measures:** Implements the Checks-Effects-Interactions pattern and protects against Denial of Service (DoS) attacks using a `MAX_TOKENS` limit.

---

## Design Decisions & Trade-offs

### 1. Mark-to-Market Valuation (The Loop)
To calculate the `TotalBankValueInUSD`, the contract iterates through all allowed tokens to fetch their current prices via Chainlink.
* **Why:** This ensures the Bank Cap is respected based on *current* market value, not outdated historical values. If ETH price crashes, the bank "opens up" more space for deposits; if it skyrockets, it protects the bank from over-exposure.
* **Trade-off:** Looping through arrays consumes Gas.
* **Mitigation:** A constant `MAX_TOKENS = 20` was implemented to prevent the loop from exceeding the Block Gas Limit, preventing Denial of Service (DoS) attacks.

### 2. Access Control vs Ownable
Instead of `Ownable`, we used `AccessControl`. This allows granular permission management, enabling a specific `MANAGER_ROLE` to configure tokens and limits without having full administrative control over the contract upgrades or admin management.

---

## Deployment & Setup

### 1. Deploy
To deploy the contract, pass the following constructor arguments:
* `_withdrawLimit`: The limit for a single withdrawal transaction (in wei/units).
* `_bankCapUSD`: The maximum capacity of the bank in USD (with 18 decimal precision).
    * *Example:* For $50,000 Cap, pass `50000000000000000000000`.

### 2. Configuration (Crucial Step)
After deployment, the `MANAGER_ROLE` must configure the allowed tokens and their respective Chainlink Oracles using `setAllowedToken`:

* **For ETH:** Use `address(0)` as the token address.
* **For ERC-20:** Use the contract address of the token.

```solidity
// Example Setup for Sepolia
// 1. Configure ETH
setAllowedToken(address(0), 0x694AA1769357215DE4FAC081bf1f309aDC325306);

// 2. Configure USDC (Example address)
setAllowedToken(0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238, 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E);
```

## 3. Interacting with the Contract

### Deposit Functions

* **`depositETH()`**
    * Deposits native Ether.
    * Automatically calculates the USD value to ensure `bankCapUSD` is not exceeded.
    * Requires `msg.value > 0`.

* **`depositToken(address _token, uint256 _amount)`**
    * Deposits an ERC-20 token.
    * **Requirement:** User must `approve()` the KipuBank contract to spend the tokens beforehand.
    * Normalizes token decimals (6, 8, or 18) to standard 18-decimal precision for the cap check.

### Withdrawal Functions

* **`withdrawETH(uint256 _amount)`**
    * Withdraws native Ether.
    * Checks user balance and global withdrawal limits.

* **`withdrawToken(address _token, uint256 _amount)`**
    * Withdraws a specific ERC-20 token.
    * Follows the **Checks-Effects-Interactions** pattern to prevent reentrancy.

### View / Helper Functions

* **`getTokenValueInUSD(address _token, uint256 _amount)`**
    * Returns the USD value of a specific amount of tokens/ETH based on the latest Chainlink round data.

* **`getTotalBankValueInUSD()`**
    * Iterates through all configured tokens to return the total assets held by the bank in USD.

* **`getBalance(address _token)`**
    * Returns the user's balance for a specific asset.

### Admin Functions

* **`setAllowedToken(address _token, address _oracle)`**
    * Whitelists a new token and assigns its price feed.
    * Restricted to `MANAGER_ROLE`.

* **`setBankCapUSD(uint256 _newBankCapUSD)`**
    * Updates the global bank capacity.

* **`setWithdrawLimit(uint256 _newWithdrawLimit)`**
    * Updates the per-transaction withdrawal limit.