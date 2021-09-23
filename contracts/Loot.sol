// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-solidity/contracts/utils/math/SafeMath.sol";

import "openzeppelin-solidity/contracts/access/Ownable.sol";
import "openzeppelin-solidity/contracts/security/ReentrancyGuard.sol";

import "./ERC1155Tradable.sol";


abstract contract Factory {
    function mint(uint256 _optionId, address _toAddress, uint256 _amount, bytes calldata _data) virtual external;
}

contract LootBox is ERC1155Tradable {
    using SafeMath for uint256;
    
    uint256 constant INVERSE_BASIS_POINT = 10000;

    //Items address
    address itemFactoryAddress;

    uint256 seed;

    mapping(uint256 => OptionSettings) optionToSettings;
    mapping(uint256 => uint256[]) classToTokenIds;

    mapping(uint256 => bool) public usedTokenIDs;

    mapping(uint256 => uint256) public maxSupply;

    event LootBoxOpened(uint256 indexed optionId, address indexed buyer, uint256 boxesPurchased, uint256[] itemsMinted);
    event ClassItemChosen(uint256 indexed classId, uint256 itemId);

    struct OptionSettings {
        bool exists;
        // Number of items to send per open.
        // Set to 0 to disable this Option.
        uint256 maxQuantityPerOpen;
        // Probability in basis points (out of 10,000) of receiving each class (descending)
        uint16[] classProbabilities;
        // Whether to enable `guarantees` below
        bool hasGuaranteedClasses;
        // Number of items you're guaranteed to get, for each class
        uint16[] guarantees;

        //Start ID of the classes for this lootbox
        uint256 classStart;
        //Number of items in this option (lootbox)
        uint256 numClasses;
    }


    /**
     * @dev Example constructor. Sets minimal configuration.
     * @param _proxyRegistryAddress The address of the OpenSea/Wyvern proxy registry
     *                              On Rinkeby: "0xf57b2c51ded3a29e6891aba85459d600256cf317"
     *                              On mainnet: "0xa5409ec958c83c3f309868babaca7c86dcb077c1"
     */
    constructor(address _proxyRegistryAddress, address _itemNFTAddress, uint256 _seed)
    ERC1155Tradable(
        "Babilu LootBox",
        "BILOOT",
        "https://app.babilu.online/sagas/{id}",
        _proxyRegistryAddress
    ) {
        itemFactoryAddress = _itemNFTAddress;
        seed = _seed;
    }

    function contractURI() public pure returns (string memory) {
        return "https://app.babilu.online/contract/lootbox_factory";
    }

    /**
     * Add a new lootbox option
     * Once added token classses should be assigned
     */
    function addOption(
        uint256 _option,
        uint256 _maxSupply,
        uint256 _maxQuantityPerOpen,
        uint256 _classStartId,
        uint256 _classCount,
        uint16[] memory _classProbabilities,
        uint256[] memory _commonItems,
        uint256[] memory _rareItems,
        uint256[] memory _epicItems,
        uint16[] memory _guarantees) public {

        maxSupply[_option] = _maxSupply;
        //Max amount of lootboxes that can exist for this option/saga

        _setOptionSettings(_option, _maxQuantityPerOpen, _classStartId, _classCount, _classProbabilities, _guarantees);

        //Set token IDs for lootbox classes
        _setTokenIdsForClass(_option, 0, _commonItems);
        _setTokenIdsForClass(_option, 1, _rareItems);
        _setTokenIdsForClass(_option, 2, _epicItems);


        //Lock items to not be available in any new chests
        _addUsedItemTokens(_commonItems);
        _addUsedItemTokens(_rareItems);
        _addUsedItemTokens(_epicItems);
    }


    /**
    * Add a list of tokens to the usedToken array blocking it from being used in a chest ever again
    */
    function _addUsedItemTokens(uint256[] memory  _usedItemTokens)  internal {
        for (uint256 _i = 0; _i < _usedItemTokens.length; _i++) {
            _addUsedItemToken(_usedItemTokens[_i]);
        }
    }

    /**
    * Add a token to the usedToken array blocking it from being used in a chest ever again
    */
    function _addUsedItemToken(uint256 _usedItemToken) internal {
        usedTokenIDs[_usedItemToken] = true;
    }

    /**
     * @dev Alternate way to add token ids to a class
     * Note: resets the full list for the class instead of adding each token id
     */
    function _setTokenIdsForClass(
        uint256 _optionId,
        uint256 _classId,
        uint256[] memory _tokenIds
    ) internal {
        OptionSettings memory s = _getOptionSettings(_optionId);
        require(s.exists, "Loot#_getOptionSettings: Option settings do not exist");

        require(_classId >= s.classStart && _classId < s.classStart + s.numClasses, "_class out of range");
        classToTokenIds[_classId] = _tokenIds;
    }



    /**
     * @dev Set the settings for a particular lootbox option
     * @param _option The Option to set settings for
     * @param _maxQuantityPerOpen Maximum number of items to mint per open.
     *                            Set to 0 to disable this option.
     * @param _classProbabilities Array of probabilities (basis points, so integers out of 10,000)
     *                            of receiving each class (the index in the array).
     *                            Should add up to 10k and be descending in value.
     * @param _guarantees         Array of the number of guaranteed items received for each class
     *                            (the index in the array).
     */
    function _setOptionSettings(
        uint256 _option,
        uint256 _maxQuantityPerOpen,
        uint256 _classStartId,
        uint256 _classCount,
        uint16[] memory _classProbabilities,
        uint16[] memory _guarantees
    ) internal {
        // Allow us to skip guarantees and save gas at mint time
        // if there are no classes with guarantees
        bool hasGuaranteedClasses = false;
        for (uint256 i = 0; i < _guarantees.length; i++) {
            if (_guarantees[i] > 0) {
                hasGuaranteedClasses = true;
            }
        }

        OptionSettings memory settings = OptionSettings({
            exists: true,
            maxQuantityPerOpen : _maxQuantityPerOpen,
            classProbabilities : _classProbabilities,
            hasGuaranteedClasses : hasGuaranteedClasses,
            numClasses : _classCount,
            classStart : _classStartId,
            guarantees : _guarantees
            });

        optionToSettings[uint256(_option)] = settings;
    }


    function _getOptionSettings(uint256  _option) internal view returns (OptionSettings memory settings) {
        return optionToSettings[_option];
    }


    function open(uint256 _option,
        address _toAddress,
        uint256 _amount
        ) public {
        // This will underflow if _msgSender() does not own enough tokens.
        _burn(_msgSender(), _option, _amount);
        _mint(_option, _toAddress, _amount, "");
    }

    ///////
    // MAIN FUNCTIONS
    //////

    /**
     * @dev Main minting logic for lootboxes
     * This is called via safeTransferFrom when CreatureAccessoryLootBox extends
     * CreatureAccessoryFactory.
     * NOTE: prices and fees are determined by the sell order on OpenSea.
     * WARNING: Make sure msg.sender can mint!
     */
    function _mint(
        uint256 _optionId,
        address _toAddress,
        uint256 _amount,
        bytes memory _data
    ) internal {
        // Load settings for this box option
        OptionSettings memory settings = _getOptionSettings(_optionId);
        require(settings.exists, "Loot#_mint: Option settings do not exist");

        uint256 totalMinted = 0;
        uint256 itemsGenerated = 0;
        uint256[] memory itemsMinted = new uint256[](_amount*settings.maxQuantityPerOpen);
        
        // Iterate over the quantity of boxes specified
        for (uint256 i = 0; i < _amount; i++) {
            // Iterate over the box's set quantity
            uint256 quantitySent = 0;
            if (settings.hasGuaranteedClasses) {
                // Process guaranteed token ids
                for (uint256 classId = 0; classId < settings.guarantees.length; classId++) {
                    uint256 quantityOfGuaranteed = settings.guarantees[classId];
                    if (quantityOfGuaranteed > 0) {
                        uint256 item = _sendTokenWithClass(settings, classId, _toAddress, 1);
                        itemsMinted[itemsGenerated] = item;
                        itemsGenerated++;
                        
                        quantitySent += quantityOfGuaranteed;
                    }
                }
            }

            // Process non-guaranteed ids
            while (quantitySent < settings.maxQuantityPerOpen) {
                uint256 quantityOfRandomized = 1;
                uint256 class = _pickRandomClass(settings.classProbabilities);
                uint256 item = _sendTokenWithClass(settings, class, _toAddress, 1);
                itemsMinted[itemsGenerated] = item;
                itemsGenerated++;
                
                quantitySent += quantityOfRandomized;
            }

            totalMinted += quantitySent;
        }

        // Event emissions
        emit LootBoxOpened(_optionId, _toAddress, _amount, itemsMinted);
    }

    /////
    // HELPER FUNCTIONS
    /////

    // Returns the tokenId sent to _toAddress
    function _sendTokenWithClass(
        OptionSettings memory s,
        uint256 _classId,
        address _toAddress,
        uint256 _amount
    ) internal returns (uint256) {
        require(_classId >= s.classStart && _classId < s.classStart + s.numClasses, "_class out of range");
        
        Factory factory = Factory(itemFactoryAddress);
        
        uint256 tokenId = _pickRandomAvailableTokenIdForClass(_classId);
        // This may mint, create or transfer. We don't handle that here.
        // We use tokenId as an option ID here.
        factory.mint(tokenId, _toAddress, _amount, "");
        return tokenId;
    }

    function _pickRandomClass(
        uint16[] memory _classProbabilities
    ) internal view returns (uint256) {
        uint16 value = uint16(_random().mod(INVERSE_BASIS_POINT));
        // Start at top class (length - 1)
        // skip common (0), we default to it
        for (uint256 i = _classProbabilities.length - 1; i > 0; i--) {
            uint16 probability = _classProbabilities[i];
            if (value < probability) {
                return i;
            } else {
                value = value - probability;
            }
        }
        //FIXME: assumes zero is common!
        return 0;
    }

    function _pickRandomAvailableTokenIdForClass(
        uint256 _classId
    ) internal returns (uint256) {
        uint256[] memory tokenIds = classToTokenIds[_classId];
        require(tokenIds.length > 0, "No token ids for _classId");
        uint256 randIndex = _random().mod(tokenIds.length);
        // Make sure owner() owns or can mint enough
        
        uint256 tokenId = tokenIds[randIndex % tokenIds.length];

        emit ClassItemChosen(_classId, tokenId);
        return tokenId;
    }

    /**
     * @dev Pseudo-random number generator
     * NOTE: to improve randomness, generate it with an oracle
     */
    function _random() internal view returns (uint256) {
        uint256 randomNumber = uint256(keccak256(abi.encodePacked(blockhash(block.number - 1), msg.sender, seed)));
        //TODO STATE
        return randomNumber;
    }

    function _addTokenIdToClass(uint256 _classId, uint256 _tokenId) internal {
        // This is called by code that has already checked this, sometimes in a
        // loop, so don't pay the gas cost of checking this here.
        //require(_classId < numClasses, "_class out of range");
        classToTokenIds[_classId].push(_tokenId);
    }
    
    
  /**
   * @dev Returns a URL specifying some metadata about the option. This metadata can be of the
   * same structure as the ERC721 metadata.
   */
  function tokenURI(uint256 _optionId) public view returns (string memory) {
      return "https://app.babilu.online/sagas/{id}";
  }
}