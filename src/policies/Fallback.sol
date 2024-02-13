// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Safe} from "@safe-contracts/Safe.sol";
import {HandlerContext} from "@safe-contracts/handler/HandlerContext.sol";
import {ISignatureValidator} from "@safe-contracts/interfaces/ISignatureValidator.sol";

import {IERC165} from "@src/interfaces/IERC165.sol";
import {IERC721TokenReceiver} from "@src/interfaces/IERC721TokenReceiver.sol";
import {IERC1155TokenReceiver} from "@src/interfaces/IERC1155TokenReceiver.sol";
import {IERC777TokensRecipient} from "@src/interfaces/IERC777TokensRecipient.sol";
import {Kernel, Policy, Permissions, Keycode} from "@src/Kernel.sol";
import {toKeycode} from "@src/libraries/KernelUtils.sol";
import {Errors} from "@src/libraries/Errors.sol";
import {Storage} from "@src/modules/Storage.sol";

/**
 * @title Fallback
 * @notice Acts as an interface to handle token callbacks, allowing the safe to receive
 *         tokens. In addition, rented assets that support `permit()` functionality will
 *         be prevented from doing so if they are assets that can be rented through the
 *         protocol.
 */
contract Fallback is
    Policy,
    IERC721TokenReceiver,
    IERC1155TokenReceiver,
    IERC165,
    ISignatureValidator,
    HandlerContext
{
    /////////////////////////////////////////////////////////////////////////////////
    //                         Kernel Policy Configuration                         //
    /////////////////////////////////////////////////////////////////////////////////

    // keccak256(SafeMessage(bytes message)");
    bytes32 private constant SAFE_MSG_TYPEHASH =
        0x60b3cbf8b4a223d68d641b3b6ddf9a298e7f33710cf3d3a9d1146b5a6150fbca;

    // bytes4(keccak256("isValidSignature(bytes32,bytes)")
    bytes4 private constant UPDATED_EIP1271_VALUE = 0x1626ba7e;

    // bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))
    bytes4 private constant ERC721_RECEIVED_VALUE = 0x150b7a02;

    // bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))
    bytes4 private constant ERC1155_RECEIVED_VALUE = 0xf23a6e61;

    // bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))
    bytes4 private constant ERC1155_BATCH_RECEIVED_VALUE = 0xbc197c81;

    // Modules that the policy depends on.
    Storage public STORE;

    /**
     * @dev Instantiate this contract as a policy.
     *
     * @param kernel_ Address of the kernel contract.
     */
    constructor(Kernel kernel_) Policy(kernel_) {}

    /**
     * @notice Upon policy activation, configures the modules that the policy depends on.
     *         If a module is ever upgraded that this policy depends on, the kernel will
     *         call this function again to ensure this policy has the current address
     *         of the module.
     *
     * @return dependencies Array of keycodes which represent modules that
     *                      this policy depends on.
     */
    function configureDependencies()
        external
        override
        onlyKernel
        returns (Keycode[] memory dependencies)
    {
        dependencies = new Keycode[](1);

        dependencies[0] = toKeycode("STORE");
        STORE = Storage(getModuleAddress(toKeycode("STORE")));
    }

    /////////////////////////////////////////////////////////////////////////////////
    //                            External Functions                               //
    /////////////////////////////////////////////////////////////////////////////////

    /**
     * @notice Returns the hash of a message that can be signed by safe owners.
     *
     * @param safe    Safe which the message is targeted for.
     * @param message Message which will be signed.
     */
    function getMessageHashForSafe(
        Safe safe,
        bytes memory message
    ) public view returns (bytes32 messageHash) {
        // Add the safe typehash to the message.
        bytes32 messageWithTypehash = keccak256(
            abi.encode(SAFE_MSG_TYPEHASH, keccak256(message))
        );

        // Encode the message with the domain separator.
        messageHash = keccak256(
            abi.encodePacked(
                bytes1(0x19),
                bytes1(0x01),
                safe.domainSeparator(),
                messageWithTypehash
            )
        );
    }

    /**
     * @notice Legacy implementation of `isValidSignature` to be compatible with gnosis
     *         safe. Determines whether the signature provided is valid for the data hash.
     *
     * @param data      Data which was signed.
     * @param signature Signature byte array associated with the data.
     *
     * @return EIP1271_MAGIC_VALUE
     */
    function isValidSignature(
        bytes memory data,
        bytes memory signature
    ) public view override returns (bytes4) {
        // Caller should be a Safe.
        Safe safe = Safe(payable(msg.sender));

        // Convert the data into a safe-compatible hash.
        bytes32 messageHash = getMessageHashForSafe(safe, data);

        // Check if the signature was signed by an owner of the safe.
        if (signature.length == 0 && safe.signedMessages(messageHash) == 0) {
            revert Errors.FallbackPolicy_HashNotSigned(messageHash);
        } else {
            safe.checkSignatures(messageHash, data, signature);
        }

        return EIP1271_MAGIC_VALUE;
    }

    /**
     * @notice Standard EIP-1271 implementation that determines whether the signature
     *         provided is valid for the data hash. Used as a wrapper around the
     *         legacy gnosis safe implementation.
     *
     * @param dataHash  Hash of the data to be signed.
     * @param signature Signature byte array associated with the data hash.
     *
     * @return The EIP-1271 magic value.
     */
    function isValidSignature(
        bytes32 dataHash,
        bytes calldata signature
    ) external view returns (bytes4) {
        // Determine if the signature is valid.
        bytes4 value = ISignatureValidator(msg.sender).isValidSignature(
            abi.encode(dataHash),
            signature
        );

        // To maintain compatibility, pass the updated EIP-1271 value.
        return (value == EIP1271_MAGIC_VALUE) ? UPDATED_EIP1271_VALUE : bytes4(0);
    }

    /**
     * @notice Handles the callback when receiving ERC721 tokens.
     *
     * @return ERC721_RECEIVED_VALUE
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return ERC721_RECEIVED_VALUE;
    }

    /**
     * @notice Handles the callback when receiving ERC1155 tokens.
     *
     * @return ERC1155_RECEIVED_VALUE
     */
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return ERC1155_RECEIVED_VALUE;
    }

    /**
     * @notice Handles the callback when receiving multiple ERC1155 tokens.
     *
     * @return ERC1155_BATCH_RECEIVED_VALUE
     */
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        return ERC1155_BATCH_RECEIVED_VALUE;
    }

    /**
     * @notice Handles the callback when receiving ERC777 tokens.
     */
    function tokensReceived(
        address,
        address,
        address,
        uint256,
        bytes calldata,
        bytes calldata
    ) external {}

    /**
     * @notice Implements support for IERC165, IERC721TokenReceiver, and IERC1155TokenReceiver.
     *
     * @param interfaceId The interface identifier, as specified in ERC-165.
     *
     * @return whether the contract supports `interfaceId`.
     */
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return
            interfaceId == type(IERC721TokenReceiver).interfaceId ||
            interfaceId == type(IERC1155TokenReceiver).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }
}
