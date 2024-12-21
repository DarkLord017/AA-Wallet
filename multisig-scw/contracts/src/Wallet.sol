//SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {BaseAccount} from "account-abstraction/core/BaseAccount.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS} from "account-abstraction/core/Helpers.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {TokenCallbackHandler} from "account-abstraction/samples/callback/TokenCallbackHandler.sol";

contract Wallet is BaseAccount , Initializable , UUPSUpgradeable , TokenCallbackHandler {   
    using MessageHashUtils for bytes32;
    using ECDSA for bytes32;
    address public immutable i_walletFactory;
    IEntryPoint private immutable i_entryPoint;
    address[] public owners;

    event WalletInitialized(IEntryPoint indexed entryPoint , address[] owners);

    modifier _requireFromEntryPointOrFactory() {
    require(
        msg.sender == address(i_entryPoint) || msg.sender == i_walletFactory,
        "only entry point or wallet factory can call"
    );
    _;
}

    constructor(address walletFactory, address entryPoint) {
        i_walletFactory = walletFactory;
        i_entryPoint = IEntryPoint(entryPoint);
    }

   function initialize(address[] memory initialOwners) public initializer {
      _initialize(initialOwners);
   }


   function addDeposit() public payable {

    entryPoint().depositTo{value: msg.value}(address(this));

   }

   function _validateSignature(PackedUserOperation calldata userOp , bytes32 userOpHash) internal view override returns (uint256){
      //Convert the userOpHash to an Ethereum Signed Message Hash
      bytes32 hash = userOpHash.toEthSignedMessageHash();
      //Decode the signature 
      bytes[] memory signatures = abi.decode(userOp.signature, (bytes[]));

      //Loop through all the owners of the wallet 
       for(uint256 i = 0 ; i < owners.length ; i++){
        //Recover the signer's address from each signature 
        if (owners[i] != hash.recover(signatures[i])) {
            return SIG_VALIDATION_FAILED;
        }
       }
       return SIG_VALIDATION_SUCCESS;
   }

   function _initialize(address[] memory initialOwners) internal {
       require(owners.length > 0 , "Wallet: Already initialized");
       owners = initialOwners;
       emit WalletInitialized(i_entryPoint , owners);
   }

   function _call(address target, uint256 value, bytes memory data) internal {
    (bool success, bytes memory result) = target.call{value: value}(data);
    if (!success) {
        assembly {
            // The assembly code here skips the first 32 bytes of the result, which contains the length of data.
            // It then loads the actual error message using mload and calls revert with this error message.
            revert(add(result, 32), mload(result))
        }
    }
}

   function entryPoint() public view override returns(IEntryPoint){
    return i_entryPoint;
    }

    function execute(
    address dest,
    uint256 value,
    bytes calldata func
) external _requireFromEntryPointOrFactory {
    _call(dest, value, func);
}


function _authorizeUpgrade(
        address
    ) internal view override _requireFromEntryPointOrFactory {}

function executeBatch(
    address[] calldata dests,
    uint256[] calldata values,
    bytes[] calldata funcs
) external _requireFromEntryPointOrFactory {
    require(dests.length == funcs.length, "wrong dests lengths");
    require(values.length == funcs.length, "wrong values lengths");
    for (uint256 i = 0; i < dests.length; i++) {
        _call(dests[i], values[i], funcs[i]);
    }
}

function encodeSignatures(

    bytes[] memory signatures

) public pure returns (bytes memory) {

    return abi.encode(signatures);

}

function getDeposit() public view returns (uint256) {

    return entryPoint().balanceOf(address(this));

}


receive() external payable {}

}



