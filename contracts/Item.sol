// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-solidity/contracts/access/Ownable.sol";
import "openzeppelin-solidity/contracts/security/ReentrancyGuard.sol";

import "./ERC1155Tradable.sol";
import "./IFactoryERC1155.sol";
import "./Loot.sol";

/**
 * @title CreatureAccessory
 * CreatureAccessory - a contract for Creature Accessory semi-fungible tokens.
 * On Rinkeby: "0xf57b2c51ded3a29e6891aba85459d600256cf317"
 * On mainnet: "0xa5409ec958c83c3f309868babaca7c86dcb077c1"
 */
contract Item is ERC1155Tradable, Factory, ReentrancyGuard {
    
    constructor(address _proxyRegistryAddress)
    ERC1155Tradable(
        "Babilu Item",
        "BII",
        "https://app.babilu.online/saga-items/{id}",
        _proxyRegistryAddress
    ) {}

    function contractURI() public pure returns (string memory) {
        return "https://app.babilu.online/contract/babilu-lootbox";
    }
    
    function mint(
        uint256 _optionId,
        address _toAddress,
        uint256 _amount,
        bytes calldata _data
    ) override external nonReentrant() {
        require(
            _canMint(_msgSender(), _optionId, _amount),
            "Item#_mint: CANNOT_MINT_MORE"
        );
        
        return _mint(_toAddress, _optionId, _amount, _data);
    }

    function _canMint(
        address _fromAddress,
        uint256 _optionId,
        uint256 _amount
    ) internal view returns (bool) {
        if(!_isOwnerOrProxy(_fromAddress)) //Only the owner proxy can mint from the factory
            return false;
        
        return _amount > 0; //Item max qty unknown until 
    }

    function _isOwnerOrProxy(address _address) internal view returns (bool) {
        ProxyRegistry proxyRegistry = ProxyRegistry(proxyRegistryAddress);
        return
            owner() == _address ||
            address(proxyRegistry.proxies(owner())) == _address;
    }
}
