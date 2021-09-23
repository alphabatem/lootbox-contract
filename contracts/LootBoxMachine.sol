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
    event LootboxWon(uint256 indexed optionId, address indexed _address);

    address public proxyRegistryAddress;
    address public lootBoxAddress;
    string
    internal constant baseMetadataURI = "https://app.babilu.online/";
    uint256 constant UINT256_MAX = ~uint256(0);

    uint16 constant HOURS_IN_WEEK = 168;
    uint16 constant GENERATION_CHANCE = 10000;

    /*
     * Optionally set this to a small integer to enforce limited existence per option/token ID
     * (Otherwise rely on sell orders on OpenSea, which can only be made by the factory owner.)
     */
    uint256 constant SUPPLY_PER_TOKEN_ID = 100000; //Max 100k items per token

    mapping(address => uint16) ticketsOwned;
    mapping(address => uint64) ticketLastClaimTime;

    uint256 public NUM_OPTIONS = 0;
    uint256 seed = 0;

    constructor(
        address _proxyRegistryAddress,
        address _lootBoxAddress,
        uint256 _seed
    ) {
        proxyRegistryAddress = _proxyRegistryAddress;
        lootBoxAddress = _lootBoxAddress;
        seed = _seed;
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


    //Pseudo-random number for determining the amount of tickets needed to grant a mint
    function random() private view returns (uint) {
        return uint(keccak256(abi.encodePacked(block.difficulty, block.timestamp, seed)));
    }

    //Win condition for generating a lootbox outside of weekly chance
    //More tickets the user has the better chance a lootbox is generated
    function isWinner(address _address) public {
        return (random() % GENERATION_CHANCE) - ticketModifier(_address) == 1;
    }

    function ticketModifier(address _address) returns (uint) {
        uint16 maxTickets = ticketsOwned[msg.sender];
        if (maxTickets > GENERATION_CHANCE)
            return uint(GENERATION_CHANCE / 3);

        return uint(maxTickets / 3);
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
                "sagas/",
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
        return _claimTicket(_optionId);
    }


    function _claimTicket(uint256 _optionId) external nonReentrant() {
        require(_optionId < NUM_OPTIONS, "LootBoxMachine#_claimTicket: Unknown _option");
        require(!_hasClaimedToday(_toAddress), "LootBoxMachine#_claimTicket: Ticket already claimed today");

        ticketsOwned[_msgSender()] = ticketsOwned[_msgSender()] + 1;
        ticketLastClaimTime[_msgSender()] = now;

        //Run chance to gen lootBox

        //100% chance to receive a lootbox once a week
        if (ticketsOwned[_msgSender()] > HOURS_IN_WEEK && balanceOf(_msgSender(), _optionId) == 0) {
            return mint(_optionId, _msgSender(), 1);
        }

        //Pseudo random chance of generating a lootbox based on tickets
        //Must have less than 10 lootboxes to trigger
        if (isWinner() && balanceOf(_msgSender(), _optionId) < 10) {
            return mint(_optionId, _msgSender(), 1);
        }
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


            //Reset the recipients tickets
            ticketsOwned[_msgSender()] = 0;

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

    function _hasClaimedToday(address _address) internal view returns (bool) {
        return ticketLastClaimTime[_address] + 1 hours < now;
    }
}
