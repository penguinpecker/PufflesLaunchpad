// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

/**
 * @title PufflesFactory
 * @dev Factory contract for the Puffles NFT Launchpad on Push Chain.
 *      Deploys EIP-1167 minimal proxy clones of the PufflesNFT implementation.
 *
 * Architecture:
 *   PufflesNFT (implementation) <- deployed once, never used directly
 *   PufflesFactory              <- creates clones, tracks all collections
 *   Clone N -> delegatecall -> PufflesNFT
 */

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import {CollectionConfig} from "./PufflesNFT.sol";

interface IPufflesNFT {
    function initialize(CollectionConfig calldata cfg) external;
}

contract PufflesFactory is Ownable2Step {

    // ============================================================
    //                     STATE VARIABLES
    // ============================================================

    address public implementation;
    address public platformTreasury;
    uint256 public defaultFeeBps;
    uint256 public creationFee;

    address[] public collections;
    mapping(address => bool) public isCollection;
    mapping(address => address[]) public ownerCollections;

    // ============================================================
    //                          EVENTS
    // ============================================================

    event CollectionCreated(
        address indexed collection,
        address indexed owner,
        string name,
        string symbol,
        uint256 maxSupply,
        uint256 indexed collectionIndex
    );

    event ImplementationUpdated(address oldImpl, address newImpl);
    event TreasuryUpdated(address oldTreasury, address newTreasury);
    event DefaultFeeUpdated(uint256 oldFee, uint256 newFee);
    event CreationFeeUpdated(uint256 oldFee, uint256 newFee);

    // ============================================================
    //                        ERRORS
    // ============================================================

    error ZeroAddress();
    error FeeTooHigh();
    error InsufficientCreationFee();
    error WithdrawFailed();

    // ============================================================
    //                       CONSTRUCTOR
    // ============================================================

    constructor(
        address _implementation,
        address _treasury,
        uint256 _defaultFeeBps,
        uint256 _creationFee
    ) Ownable(msg.sender) {
        if (_implementation == address(0) || _treasury == address(0)) revert ZeroAddress();
        if (_defaultFeeBps > 2500) revert FeeTooHigh();

        implementation = _implementation;
        platformTreasury = _treasury;
        defaultFeeBps = _defaultFeeBps;
        creationFee = _creationFee;
    }

    // ============================================================
    //                   CREATE COLLECTION
    // ============================================================

    /**
     * @notice Deploy a new NFT collection as a minimal proxy clone.
     * @param _name             Collection name
     * @param _symbol           Collection symbol
     * @param _owner            Collection owner
     * @param _notRevealedURI   Pre-reveal metadata URI
     * @param _maxSupply        Maximum token supply
     * @param _maxPerWalletWL   Max mints per wallet (whitelist)
     * @param _maxPerWalletPublic Max mints per wallet (public)
     * @param _maxPerTx         Max mints per transaction
     * @param _wlPrice          Whitelist price in wei
     * @param _pubPrice         Public price in wei
     * @param _royaltyReceiver  Royalty recipient address
     * @param _royaltyBps       Royalty in basis points (e.g. 750 = 7.5%)
     * @return clone            Address of the new collection
     */
    function createCollection(
        string memory _name,
        string memory _symbol,
        address _owner,
        string memory _notRevealedURI,
        uint256 _maxSupply,
        uint256 _maxPerWalletWL,
        uint256 _maxPerWalletPublic,
        uint256 _maxPerTx,
        uint256 _wlPrice,
        uint256 _pubPrice,
        address _royaltyReceiver,
        uint96 _royaltyBps
    ) external payable returns (address clone) {
        if (msg.value < creationFee) revert InsufficientCreationFee();
        if (_owner == address(0)) revert ZeroAddress();

        // Deploy clone
        clone = Clones.clone(implementation);

        // Build config struct and initialize
        CollectionConfig memory cfg = CollectionConfig({
            name: _name,
            symbol: _symbol,
            owner: _owner,
            notRevealedURI: _notRevealedURI,
            maxSupply: _maxSupply,
            maxPerWalletWL: _maxPerWalletWL,
            maxPerWalletPublic: _maxPerWalletPublic,
            maxPerTx: _maxPerTx,
            wlPrice: _wlPrice,
            pubPrice: _pubPrice,
            treasury: platformTreasury,
            feeBps: defaultFeeBps,
            royaltyReceiver: _royaltyReceiver,
            royaltyBps: _royaltyBps
        });

        IPufflesNFT(clone).initialize(cfg);

        // Track
        collections.push(clone);
        isCollection[clone] = true;
        ownerCollections[_owner].push(clone);

        emit CollectionCreated(
            clone,
            _owner,
            _name,
            _symbol,
            _maxSupply,
            collections.length - 1
        );
    }

    // ============================================================
    //                    VIEW FUNCTIONS
    // ============================================================

    function totalCollections() external view returns (uint256) {
        return collections.length;
    }

    function getOwnerCollections(address _owner) external view returns (address[] memory) {
        return ownerCollections[_owner];
    }

    function getCollections(uint256 offset, uint256 limit) 
        external 
        view 
        returns (address[] memory result) 
    {
        uint256 total = collections.length;
        if (offset >= total) return new address[](0);

        uint256 end = offset + limit;
        if (end > total) end = total;

        result = new address[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = collections[i];
        }
    }

    // ============================================================
    //                   ADMIN FUNCTIONS
    // ============================================================

    function setImplementation(address _implementation) external onlyOwner {
        if (_implementation == address(0)) revert ZeroAddress();
        emit ImplementationUpdated(implementation, _implementation);
        implementation = _implementation;
    }

    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert ZeroAddress();
        emit TreasuryUpdated(platformTreasury, _treasury);
        platformTreasury = _treasury;
    }

    function setDefaultFeeBps(uint256 _feeBps) external onlyOwner {
        if (_feeBps > 2500) revert FeeTooHigh();
        emit DefaultFeeUpdated(defaultFeeBps, _feeBps);
        defaultFeeBps = _feeBps;
    }

    function setCreationFee(uint256 _fee) external onlyOwner {
        emit CreationFeeUpdated(creationFee, _fee);
        creationFee = _fee;
    }

    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        (bool success, ) = payable(platformTreasury).call{value: balance}("");
        if (!success) revert WithdrawFailed();
    }

    receive() external payable {}
}
