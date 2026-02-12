// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/// @title PufflesFaucetV2
/// @notice Gasless testnet faucet — relayer calls dripTo() on behalf of users
/// @dev Users sign a message off-chain, backend relayer submits tx
/// @author Puffles Team

contract PufflesFaucetV2 {

    // ═══════════════════════════════════════════
    //                 STORAGE
    // ═══════════════════════════════════════════

    address public owner;
    address public relayer;
    uint256 public dripAmount;
    uint256 public cooldown;
    uint256 public totalDrips;
    uint256 public totalDistributed;

    /// @notice Last request timestamp per recipient wallet
    mapping(address => uint256) public lastRequest;

    // ═══════════════════════════════════════════
    //                 EVENTS
    // ═══════════════════════════════════════════

    event Drip(address indexed recipient, uint256 amount, uint256 timestamp);
    event Funded(address indexed funder, uint256 amount);
    event DripAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event CooldownUpdated(uint256 oldCooldown, uint256 newCooldown);
    event RelayerUpdated(address oldRelayer, address newRelayer);
    event Withdrawn(address indexed to, uint256 amount);

    // ═══════════════════════════════════════════
    //                 ERRORS
    // ═══════════════════════════════════════════

    error NotOwner();
    error NotRelayer();
    error CooldownActive(uint256 remainingSeconds);
    error InsufficientBalance();
    error TransferFailed();
    error ZeroAddress();
    error ZeroAmount();

    // ═══════════════════════════════════════════
    //               MODIFIERS
    // ═══════════════════════════════════════════

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyRelayer() {
        if (msg.sender != relayer && msg.sender != owner) revert NotRelayer();
        _;
    }

    // ═══════════════════════════════════════════
    //              CONSTRUCTOR
    // ═══════════════════════════════════════════

    /// @param _dripAmount Amount of PC (in wei) to send per request
    /// @param _cooldown Cooldown period in seconds between requests
    /// @param _relayer Address of the backend relayer wallet
    constructor(uint256 _dripAmount, uint256 _cooldown, address _relayer) {
        owner = msg.sender;
        relayer = _relayer;
        dripAmount = _dripAmount;
        cooldown = _cooldown;
    }

    // ═══════════════════════════════════════════
    //           RELAYER FUNCTIONS
    // ═══════════════════════════════════════════

    /// @notice Send PC to a recipient (called by relayer on behalf of user)
    /// @param recipient The wallet address to receive tokens
    function dripTo(address recipient) external onlyRelayer {
        if (recipient == address(0)) revert ZeroAddress();

        // Check cooldown for the recipient
        uint256 timeSinceLast = block.timestamp - lastRequest[recipient];
        if (lastRequest[recipient] != 0 && timeSinceLast < cooldown) {
            revert CooldownActive(cooldown - timeSinceLast);
        }

        // Check balance
        if (address(this).balance < dripAmount) revert InsufficientBalance();

        // Update state before transfer
        lastRequest[recipient] = block.timestamp;
        totalDrips++;
        totalDistributed += dripAmount;

        // Transfer to recipient
        (bool success, ) = payable(recipient).call{value: dripAmount}("");
        if (!success) revert TransferFailed();

        emit Drip(recipient, dripAmount, block.timestamp);
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

    function setDripAmount(uint256 _dripAmount) external onlyOwner {
        if (_dripAmount == 0) revert ZeroAmount();
        emit DripAmountUpdated(dripAmount, _dripAmount);
        dripAmount = _dripAmount;
    }

    function setCooldown(uint256 _cooldown) external onlyOwner {
        emit CooldownUpdated(cooldown, _cooldown);
        cooldown = _cooldown;
    }

    function setRelayer(address _relayer) external onlyOwner {
        if (_relayer == address(0)) revert ZeroAddress();
        emit RelayerUpdated(relayer, _relayer);
        relayer = _relayer;
    }

    function withdraw() external onlyOwner {
        uint256 bal = address(this).balance;
        if (bal == 0) revert InsufficientBalance();
        (bool success, ) = payable(owner).call{value: bal}("");
        if (!success) revert TransferFailed();
        emit Withdrawn(owner, bal);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }

    /// @notice Accept funding
    receive() external payable {
        emit Funded(msg.sender, msg.value);
    }
}
