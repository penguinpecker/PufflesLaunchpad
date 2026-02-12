// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/// @title PufflesFaucet
/// @notice Testnet faucet for distributing PC tokens to users
/// @dev Users connect wallet and call request() to receive tokens with a cooldown
/// @author Puffles Team

contract PufflesFaucet {

    // ═══════════════════════════════════════════
    //                 STORAGE
    // ═══════════════════════════════════════════

    address public owner;
    uint256 public dripAmount;
    uint256 public cooldown;
    uint256 public totalDrips;
    uint256 public totalDistributed;

    /// @notice Last request timestamp per wallet
    mapping(address => uint256) public lastRequest;

    // ═══════════════════════════════════════════
    //                 EVENTS
    // ═══════════════════════════════════════════

    event Drip(address indexed recipient, uint256 amount, uint256 timestamp);
    event Funded(address indexed funder, uint256 amount);
    event DripAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event CooldownUpdated(uint256 oldCooldown, uint256 newCooldown);
    event Withdrawn(address indexed to, uint256 amount);

    // ═══════════════════════════════════════════
    //                 ERRORS
    // ═══════════════════════════════════════════

    error NotOwner();
    error CooldownActive(uint256 remainingSeconds);
    error InsufficientBalance();
    error TransferFailed();
    error ZeroAmount();

    // ═══════════════════════════════════════════
    //               MODIFIERS
    // ═══════════════════════════════════════════

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    // ═══════════════════════════════════════════
    //              CONSTRUCTOR
    // ═══════════════════════════════════════════

    /// @param _dripAmount Amount of PC (in wei) to send per request
    /// @param _cooldown Cooldown period in seconds between requests
    constructor(uint256 _dripAmount, uint256 _cooldown) {
        owner = msg.sender;
        dripAmount = _dripAmount;
        cooldown = _cooldown;
    }

    // ═══════════════════════════════════════════
    //            USER FUNCTIONS
    // ═══════════════════════════════════════════

    /// @notice Request PC tokens from the faucet
    /// @dev Enforces cooldown per wallet address
    function request() external {
        // Check cooldown
        uint256 timeSinceLast = block.timestamp - lastRequest[msg.sender];
        if (lastRequest[msg.sender] != 0 && timeSinceLast < cooldown) {
            revert CooldownActive(cooldown - timeSinceLast);
        }

        // Check balance
        if (address(this).balance < dripAmount) revert InsufficientBalance();

        // Update state before transfer
        lastRequest[msg.sender] = block.timestamp;
        totalDrips++;
        totalDistributed += dripAmount;

        // Transfer
        (bool success, ) = payable(msg.sender).call{value: dripAmount}("");
        if (!success) revert TransferFailed();

        emit Drip(msg.sender, dripAmount, block.timestamp);
    }

    /// @notice Check how many seconds until a wallet can request again
    /// @param wallet The address to check
    /// @return 0 if eligible, otherwise seconds remaining
    function timeUntilNextRequest(address wallet) external view returns (uint256) {
        if (lastRequest[wallet] == 0) return 0;
        uint256 elapsed = block.timestamp - lastRequest[wallet];
        if (elapsed >= cooldown) return 0;
        return cooldown - elapsed;
    }

    // ═══════════════════════════════════════════
    //            OWNER FUNCTIONS
    // ═══════════════════════════════════════════

    /// @notice Update the drip amount
    function setDripAmount(uint256 _dripAmount) external onlyOwner {
        if (_dripAmount == 0) revert ZeroAmount();
        emit DripAmountUpdated(dripAmount, _dripAmount);
        dripAmount = _dripAmount;
    }

    /// @notice Update the cooldown period
    function setCooldown(uint256 _cooldown) external onlyOwner {
        emit CooldownUpdated(cooldown, _cooldown);
        cooldown = _cooldown;
    }

    /// @notice Withdraw all funds from the faucet
    function withdraw() external onlyOwner {
        uint256 bal = address(this).balance;
        if (bal == 0) revert InsufficientBalance();
        (bool success, ) = payable(owner).call{value: bal}("");
        if (!success) revert TransferFailed();
        emit Withdrawn(owner, bal);
    }

    /// @notice Transfer ownership
    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    /// @notice Accept funding
    receive() external payable {
        emit Funded(msg.sender, msg.value);
    }
}
