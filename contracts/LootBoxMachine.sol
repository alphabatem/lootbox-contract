// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-solidity/contracts/access/Ownable.sol";
import "openzeppelin-solidity/contracts/security/ReentrancyGuard.sol";
import "openzeppelin-solidity/contracts/utils/Strings.sol";
import "./IFactoryERC1155.sol";
import "./ERC1155Tradable.sol";

/**
 * @title CreatureAccessoryFactory
 * CreatureAccessory - a factory contract for Creature Accessory semi-fungible
 * tokens.
 */
contract LootBoxMachine is FactoryERC1155, ReentrancyGuard, Ownable {
    using Strings for string;
    using SafeMath for uint256;

    event LootboxAdded(uint256 indexed optionId);

    address public proxyRegistryAddress;
    address public lootBoxAddress;
    string
    internal constant baseMetadataURI = "https://app.babilu.online/";
    uint256 constant UINT256_MAX = ~uint256(0);

    /*
     * Optionally set this to a small integer to enforce limited existence per option/token ID
     * (Otherwise rely on sell orders on OpenSea, which can only be made by the factory owner.)
     */
    uint256 constant SUPPLY_PER_TOKEN_ID = 100000; //Max 100k items per token


    uint256 public NUM_OPTIONS = 0;

    constructor(
        address _proxyRegistryAddress,
        address _lootBoxAddress
    ) {
        proxyRegistryAddress = _proxyRegistryAddress;
        lootBoxAddress = _lootBoxAddress;
    }

    // Add a new lootbox saga option
    function addOption() public {
        require(
            _isOwnerOrProxy(_msgSender()),
            "LootBoxMachine#addOption: ONLY OWNER CAN ADD OPTION"
        );

        NUM_OPTIONS = NUM_OPTIONS + 1;

        emit LootboxAdded(NUM_OPTIONS);
    }

    /////
    // FACTORY INTERFACE METHODS
    /////

    function name() override external pure returns (string memory) {
        return "Babilu LootBox Machine";
    }

    function symbol() override external pure returns (string memory) {
        return "LOOTMACHINE";
    }

    function uri(uint256 _optionId) override external pure returns (string memory) {
        return
        string(
            abi.encodePacked(
                baseMetadataURI,
                "saga-items/",
                Strings.toString(_optionId)
            )
        );
    }

    function supportsFactoryInterface() override external pure returns (bool) {
        return true;
    }

    function factorySchemaName() override external pure returns (string memory) {
        return "ERC1155";
    }

    function numOptions() override external view returns (uint256) {
        return NUM_OPTIONS;
    }

    function canMint(uint256 _optionId, uint256 _amount)
    override
    external
    view
    returns (bool)
    {
        return _canMint(_msgSender(), _optionId, _amount);
    }

    function mint(
        uint256 _optionId,
        address _toAddress,
        uint256 _amount,
        bytes calldata _data
    ) override external nonReentrant() {
        return _mint(_optionId, _toAddress, _amount, _data);
    }

    /**
     * @dev Main minting logic implemented here!
     */
    function _mint(
        uint256 _option,
        address _toAddress,
        uint256 _amount,
        bytes memory _data
    ) internal {
        require(
            _canMint(_msgSender(), _option, _amount),
            "LootBoxMachine#_mint: CANNOT_MINT_MORE"
        );
        if (_option < NUM_OPTIONS) {
            require(_isOwnerOrProxy(_msgSender()), "Caller cannot mint boxes");
            // LootBoxes are not premined, so we need to create or mint them.
            // lootBoxOption is used as a token ID here.
            _createOrMint(
                lootBoxAddress,
                _toAddress,
                _option,
                _amount,
                _data
            );
        } else {
            revert("LootBoxMachine#_mint: Unknown _option");
        }
    }

    /*
     * Note: make sure code that calls this is non-reentrant.
     * Note: this is the token _id *within* the ERC1155 contract, not the option
     *       id from this contract.
     */
    function _createOrMint(
        address _erc1155Address,
        address _to,
        uint256 _id,
        uint256 _amount,
        bytes memory _data
    ) internal {
        ERC1155Tradable tradable = ERC1155Tradable(_erc1155Address);
        // Lazily create the token
        if (!tradable.exists(_id)) {
            tradable.create(_to, _id, _amount, "", _data);
        } else {
            tradable.mint(_to, _id, _amount, _data);
        }
    }

    /**
     * Get the factory's ownership of Option.
     * Should be the amount it can still mint.
     * NOTE: Called by `canMint`
     */
    function balanceOf(address _owner, uint256 _optionId)
    override
    public
    view
    returns (uint256)
    {
        if (!_isOwnerOrProxy(_owner)) {
            // Only the factory owner or owner's proxy can have supply
            return 0;
        }
        // We explicitly calculate the token ID here
        ERC1155Tradable lootBox = ERC1155Tradable(lootBoxAddress);
        uint256 currentSupply = lootBox.totalSupply(_optionId);
        // We can mint up to a balance of SUPPLY_PER_TOKEN_ID
        return SUPPLY_PER_TOKEN_ID.sub(currentSupply);
    }

    function _canMint(
        address _fromAddress,
        uint256 _optionId,
        uint256 _amount
    ) internal view returns (bool) {
        return _amount > 0 && balanceOf(_fromAddress, _optionId) >= _amount;
    }

    function _isOwnerOrProxy(address _address) internal view returns (bool) {
        ProxyRegistry proxyRegistry = ProxyRegistry(proxyRegistryAddress);
        return
        owner() == _address ||
        address(proxyRegistry.proxies(owner())) == _address;
    }
}
