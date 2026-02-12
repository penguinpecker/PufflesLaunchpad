// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

contract PufflesRegistry {
    address public owner;
    address public factory;

    mapping(string => address) public slugToCollection;
    mapping(address => string) public collectionToSlug;
    mapping(address => CollectionMeta) public collections;
    address[] public allCollections;

    struct CollectionMeta {
        string name;
        string slug;
        address creator;
        uint256 registeredAt;
        bool verified;
    }

    event CollectionRegistered(address indexed collection, string slug, string name, address indexed creator);
    event SlugUpdated(address indexed collection, string oldSlug, string newSlug);
    event CollectionVerified(address indexed collection, bool verified);
    event CollectionRemoved(address indexed collection, string slug);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event FactoryUpdated(address indexed oldFactory, address indexed newFactory);

    modifier onlyOwner() { require(msg.sender == owner, "Registry: not owner"); _; }
    modifier onlyOwnerOrFactory() { require(msg.sender == owner || msg.sender == factory, "Registry: not authorized"); _; }
    modifier onlyCollectionOwner(address collection) { require(msg.sender == owner || msg.sender == collections[collection].creator, "Registry: not collection owner"); _; }

    constructor(address _factory) { owner = msg.sender; factory = _factory; }

    function register(address collection, string calldata slug, string calldata name) external onlyOwnerOrFactory {
        require(collection != address(0), "Registry: zero address");
        require(bytes(slug).length > 0 && bytes(slug).length <= 64, "Registry: invalid slug length");
        require(_isValidSlug(slug), "Registry: invalid slug chars");
        require(slugToCollection[slug] == address(0), "Registry: slug taken");
        require(bytes(collectionToSlug[collection]).length == 0, "Registry: already registered");
        slugToCollection[slug] = collection;
        collectionToSlug[collection] = slug;
        collections[collection] = CollectionMeta({ name: name, slug: slug, creator: tx.origin, registeredAt: block.timestamp, verified: false });
        allCollections.push(collection);
        emit CollectionRegistered(collection, slug, name, tx.origin);
    }

    function updateSlug(address collection, string calldata newSlug) external onlyCollectionOwner(collection) {
        require(bytes(newSlug).length > 0 && bytes(newSlug).length <= 64, "Registry: invalid slug length");
        require(_isValidSlug(newSlug), "Registry: invalid slug chars");
        require(slugToCollection[newSlug] == address(0), "Registry: slug taken");
        string memory oldSlug = collectionToSlug[collection];
        require(bytes(oldSlug).length > 0, "Registry: not registered");
        delete slugToCollection[oldSlug];
        slugToCollection[newSlug] = collection;
        collectionToSlug[collection] = newSlug;
        collections[collection].slug = newSlug;
        emit SlugUpdated(collection, oldSlug, newSlug);
    }

    function setVerified(address collection, bool verified) external onlyOwner {
        require(bytes(collectionToSlug[collection]).length > 0, "Registry: not registered");
        collections[collection].verified = verified;
        emit CollectionVerified(collection, verified);
    }

    function remove(address collection) external onlyOwner {
        string memory slug = collectionToSlug[collection];
        require(bytes(slug).length > 0, "Registry: not registered");
        delete slugToCollection[slug];
        delete collectionToSlug[collection];
        delete collections[collection];
        uint256 len = allCollections.length;
        for (uint256 i = 0; i < len;) {
            if (allCollections[i] == collection) { allCollections[i] = allCollections[len - 1]; allCollections.pop(); break; }
            unchecked { ++i; }
        }
        emit CollectionRemoved(collection, slug);
    }

    function resolve(string calldata slug) external view returns (address) { return slugToCollection[slug]; }
    function getCollection(address collection) external view returns (CollectionMeta memory) { return collections[collection]; }
    function totalCollections() external view returns (uint256) { return allCollections.length; }

    function getCollections(uint256 offset, uint256 limit) external view returns (address[] memory addrs, CollectionMeta[] memory metas) {
        uint256 total = allCollections.length;
        if (offset >= total) return (new address[](0), new CollectionMeta[](0));
        uint256 end = offset + limit;
        if (end > total) end = total;
        uint256 count = end - offset;
        addrs = new address[](count);
        metas = new CollectionMeta[](count);
        for (uint256 i = 0; i < count;) { address addr = allCollections[offset + i]; addrs[i] = addr; metas[i] = collections[addr]; unchecked { ++i; } }
    }

    function isSlugAvailable(string calldata slug) external view returns (bool) { return slugToCollection[slug] == address(0) && _isValidSlug(slug); }
    function transferOwnership(address newOwner) external onlyOwner { require(newOwner != address(0)); emit OwnershipTransferred(owner, newOwner); owner = newOwner; }
    function setFactory(address _factory) external onlyOwner { emit FactoryUpdated(factory, _factory); factory = _factory; }

    function _isValidSlug(string calldata slug) internal pure returns (bool) {
        bytes memory b = bytes(slug);
        if (b.length == 0) return false;
        if (b[0] == 0x2D || b[b.length - 1] == 0x2D) return false;
        for (uint256 i = 0; i < b.length;) {
            bytes1 c = b[i];
            if (!(c >= 0x61 && c <= 0x7A) && !(c >= 0x30 && c <= 0x39) && c != 0x2D) return false;
            unchecked { ++i; }
        }
        return true;
    }
}
