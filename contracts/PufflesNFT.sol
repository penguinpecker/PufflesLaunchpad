// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

/**
 * @title PufflesNFT
 * @dev Implementation contract for the Puffles NFT Launchpad on Push Chain.
 *      This contract is deployed ONCE as a template. All new collections
 *      are deployed as EIP-1167 minimal proxy clones pointing to this implementation.
 *
 *      DO NOT call initialize() on this implementation directly.
 *      Only clones created by PufflesFactory should be initialized.
 *
 * Features:
 *   - ERC721A for gas-efficient batch minting
 *   - Merkle tree whitelist verification
 *   - Whitelist phase + Public phase + Paused
 *   - Configurable supply, prices, per-wallet limits
 *   - Platform fee (% of mint revenue to Puffles treasury)
 *   - EIP-2981 enforced royalties (configurable recipient + %)
 *   - Metadata reveal mechanism
 *   - Ownable2Step for safe ownership transfers
 */

import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";

/// @notice Struct for collection initialization parameters
struct CollectionConfig {
    string name;
    string symbol;
    address owner;
    string notRevealedURI;
    uint256 maxSupply;
    uint256 maxPerWalletWL;
    uint256 maxPerWalletPublic;
    uint256 maxPerTx;
    uint256 wlPrice;
    uint256 pubPrice;
    address treasury;
    uint256 feeBps;
    address royaltyReceiver;
    uint96 royaltyBps;
}

contract PufflesNFT is ERC721A, ERC2981, Ownable2Step, ReentrancyGuard {

    // ============================================================
    //                     INITIALIZATION
    // ============================================================

    bool private _initialized;

    modifier initializer() {
        require(!_initialized, "Already initialized");
        _initialized = true;
        _;
    }

    // ============================================================
    //                   COLLECTION CONFIG
    // ============================================================

    uint256 public maxSupply;
    uint256 public maxPerWalletWL;
    uint256 public maxPerWalletPublic;
    uint256 public maxPerTx;

    // ============================================================
    //                     STATE VARIABLES
    // ============================================================

    enum SalePhase { PAUSED, WHITELIST, PUBLIC }

    SalePhase public salePhase;

    uint256 public whitelistPrice;
    uint256 public publicPrice;

    bytes32 public merkleRoot;

    string private _baseTokenURI;
    string private _contractURI;
    bool public revealed;
    string public notRevealedURI;

    mapping(address => uint256) public whitelistMinted;
    mapping(address => uint256) public publicMinted;

    // ============================================================
    //                    PLATFORM (PUFFLES)
    // ============================================================

    address public factory;
    address public platformTreasury;
    uint256 public platformFeeBps;

    // ============================================================
    //                          EVENTS
    // ============================================================

    event Initialized(string name, string symbol, address owner, uint256 maxSupply);
    event PhaseChanged(SalePhase newPhase);
    event MerkleRootUpdated(bytes32 newRoot);
    event PriceUpdated(string priceType, uint256 newPrice);
    event Revealed(bool status);
    event Withdrawn(address owner, uint256 ownerAmount, address platform, uint256 platformAmount);

    // ============================================================
    //                        ERRORS
    // ============================================================

    error SaleNotActive();
    error ExceedsMaxSupply();
    error ExceedsWalletLimit();
    error ExceedsPerTxLimit();
    error InsufficientPayment();
    error InvalidProof();
    error WithdrawFailed();
    error ZeroQuantity();

    // ============================================================
    //                       CONSTRUCTOR
    // ============================================================

    constructor() ERC721A("", "") Ownable(msg.sender) {
        _initialized = true;
    }

    // ============================================================
    //                      INITIALIZER
    // ============================================================

    /**
     * @notice Initialize a new collection clone. Called once by PufflesFactory.
     * @param cfg CollectionConfig struct with all parameters
     */
    function initialize(CollectionConfig calldata cfg) external initializer {
        _initializeERC721A(cfg.name, cfg.symbol);
        _transferOwnership(cfg.owner);

        maxSupply = cfg.maxSupply;
        maxPerWalletWL = cfg.maxPerWalletWL;
        maxPerWalletPublic = cfg.maxPerWalletPublic;
        maxPerTx = cfg.maxPerTx;

        whitelistPrice = cfg.wlPrice;
        publicPrice = cfg.pubPrice;

        notRevealedURI = cfg.notRevealedURI;
        salePhase = SalePhase.PAUSED;

        factory = msg.sender;
        platformTreasury = cfg.treasury;
        platformFeeBps = cfg.feeBps;

        _setDefaultRoyalty(cfg.royaltyReceiver, cfg.royaltyBps);

        emit Initialized(cfg.name, cfg.symbol, cfg.owner, cfg.maxSupply);
    }

    // ============================================================
    //                  ERC721A NAME/SYMBOL INIT
    // ============================================================

    string private _cloneName;
    string private _cloneSymbol;
    bool private _isClone;

    function _initializeERC721A(string memory name_, string memory symbol_) internal {
        _cloneName = name_;
        _cloneSymbol = symbol_;
        _isClone = true;
    }

    function name() public view virtual override returns (string memory) {
        if (_isClone) return _cloneName;
        return super.name();
    }

    function symbol() public view virtual override returns (string memory) {
        if (_isClone) return _cloneSymbol;
        return super.symbol();
    }

    // ============================================================
    //                     MINT FUNCTIONS
    // ============================================================

    function whitelistMint(uint256 quantity, bytes32[] calldata proof)
        external
        payable
        nonReentrant
    {
        if (salePhase != SalePhase.WHITELIST) revert SaleNotActive();
        if (quantity == 0) revert ZeroQuantity();
        if (quantity > maxPerTx) revert ExceedsPerTxLimit();
        if (_totalMinted() + quantity > maxSupply) revert ExceedsMaxSupply();
        if (whitelistMinted[msg.sender] + quantity > maxPerWalletWL) revert ExceedsWalletLimit();
        if (msg.value < whitelistPrice * quantity) revert InsufficientPayment();

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        if (!MerkleProof.verify(proof, merkleRoot, leaf)) revert InvalidProof();

        whitelistMinted[msg.sender] += quantity;
        _mint(msg.sender, quantity);
    }

    function publicMint(uint256 quantity)
        external
        payable
        nonReentrant
    {
        if (salePhase != SalePhase.PUBLIC) revert SaleNotActive();
        if (quantity == 0) revert ZeroQuantity();
        if (quantity > maxPerTx) revert ExceedsPerTxLimit();
        if (_totalMinted() + quantity > maxSupply) revert ExceedsMaxSupply();
        if (publicMinted[msg.sender] + quantity > maxPerWalletPublic) revert ExceedsWalletLimit();
        if (msg.value < publicPrice * quantity) revert InsufficientPayment();

        publicMinted[msg.sender] += quantity;
        _mint(msg.sender, quantity);
    }

    function ownerMint(address to, uint256 quantity) external onlyOwner {
        if (quantity == 0) revert ZeroQuantity();
        if (_totalMinted() + quantity > maxSupply) revert ExceedsMaxSupply();
        _mint(to, quantity);
    }

    // ============================================================
    //                    ADMIN FUNCTIONS
    // ============================================================

    function setSalePhase(SalePhase _phase) external onlyOwner {
        salePhase = _phase;
        emit PhaseChanged(_phase);
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
        emit MerkleRootUpdated(_merkleRoot);
    }

    function setWhitelistPrice(uint256 _price) external onlyOwner {
        whitelistPrice = _price;
        emit PriceUpdated("whitelist", _price);
    }

    function setPublicPrice(uint256 _price) external onlyOwner {
        publicPrice = _price;
        emit PriceUpdated("public", _price);
    }

    function setBaseURI(string calldata baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
    }

    function setNotRevealedURI(string calldata _uri) external onlyOwner {
        notRevealedURI = _uri;
    }

    function setContractURI(string calldata _uri) external onlyOwner {
        _contractURI = _uri;
    }

    function reveal() external onlyOwner {
        revealed = true;
        emit Revealed(true);
    }

    function setDefaultRoyalty(address receiver, uint96 feeBps) external onlyOwner {
        _setDefaultRoyalty(receiver, feeBps);
    }

    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeBps) external onlyOwner {
        _setTokenRoyalty(tokenId, receiver, feeBps);
    }

    function deleteDefaultRoyalty() external onlyOwner {
        _deleteDefaultRoyalty();
    }

    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        
        uint256 platformAmount = (balance * platformFeeBps) / 10000;
        uint256 ownerAmount = balance - platformAmount;

        if (platformAmount > 0) {
            (bool s1, ) = payable(platformTreasury).call{value: platformAmount}("");
            if (!s1) revert WithdrawFailed();
        }

        (bool s2, ) = payable(owner()).call{value: ownerAmount}("");
        if (!s2) revert WithdrawFailed();

        emit Withdrawn(owner(), ownerAmount, platformTreasury, platformAmount);
    }

    // ============================================================
    //                      VIEW FUNCTIONS
    // ============================================================

    function totalMinted() external view returns (uint256) {
        return _totalMinted();
    }

    function numberMinted(address _owner) external view returns (uint256) {
        return _numberMinted(_owner);
    }

    function remainingSupply() external view returns (uint256) {
        return maxSupply - _totalMinted();
    }

    function contractURI() external view returns (string memory) {
        return _contractURI;
    }

    // ============================================================
    //                       OVERRIDES
    // ============================================================

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();

        if (!revealed) {
            return notRevealedURI;
        }

        string memory baseURI = _baseURI();
        return bytes(baseURI).length != 0
            ? string(abi.encodePacked(baseURI, _toString(tokenId), ".json"))
            : "";
    }

    function _startTokenId() internal pure virtual override returns (uint256) {
        return 1;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721A, ERC2981)
        returns (bool)
    {
        return ERC721A.supportsInterface(interfaceId) || ERC2981.supportsInterface(interfaceId);
    }

    receive() external payable {}
}
