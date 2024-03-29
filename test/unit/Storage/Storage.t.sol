// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {RentalId} from "@src/libraries/RentalStructs.sol";
import {Errors} from "@src/libraries/Errors.sol";
import {RentalUtils, RentalAssetUpdate} from "@src/libraries/RentalUtils.sol";

import {BaseTestWithoutEngine} from "@test/BaseTest.sol";
import {MockHook_Success} from "@test/mocks/MockHook.sol";
import {MockTarget} from "@test/mocks/MockTarget.sol";

contract Storage_Unit_Test is BaseTestWithoutEngine {
    bytes32 constant RENTAL_ORDER_HASH = keccak256(abi.encode("someRentalOrderHash"));

    // Mock hook contract that successfully executes
    MockHook_Success public mockHook;

    // Mock target contract that a hook will be placed between
    MockTarget public mockTarget;

    function setUp() public override {
        super.setUp();

        // deploy a mock hook contract
        mockHook = new MockHook_Success();

        // set up a mock target contract
        mockTarget = new MockTarget();
    }

    function test_Success_AddRentals() public {
        // Create a rental asset array
        RentalAssetUpdate[] memory rentalAssets = new RentalAssetUpdate[](1);

        // create the rental ID
        RentalId rentalId = RentalUtils.getItemPointer(
            address(alice.safe),
            address(erc721s[0]),
            0
        );

        // populate the array
        rentalAssets[0] = RentalAssetUpdate(rentalId, 1);

        // mark rental asset as active
        vm.prank(address(create));
        STORE.addRentals(RENTAL_ORDER_HASH, rentalAssets);

        // assert that the rental order is in storage
        assertEq(STORE.orders(RENTAL_ORDER_HASH), true);

        // assert that the rental ID is in storage
        assertEq(STORE.rentedAssets(rentalAssets[0].rentalId), rentalAssets[0].amount);

        // assert that the item is rented out
        assertGt(STORE.isRentedOut(address(alice.safe), address(erc721s[0]), 0), 0);
    }

    function test_Reverts_AddRentals_NotAdmin() public {
        // Create a rental asset array
        RentalAssetUpdate[] memory rentalAssets = new RentalAssetUpdate[](1);

        // create the rental ID
        RentalId rentalId = RentalUtils.getItemPointer(
            address(alice.safe),
            address(erc721s[0]),
            0
        );

        // populate the array
        rentalAssets[0] = RentalAssetUpdate(rentalId, 1);

        // impersonate an address without permissions
        vm.prank(alice.addr);

        // Expect revert because the caller does not have permissions
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Module_PolicyNotAuthorized.selector, alice.addr)
        );
        STORE.addRentals(RENTAL_ORDER_HASH, rentalAssets);
    }

    function test_Success_RemoveRentals() public {
        // Create a rental asset array
        RentalAssetUpdate[] memory rentalAssets = new RentalAssetUpdate[](1);

        // create the rental ID
        RentalId rentalId = RentalUtils.getItemPointer(
            address(alice.safe),
            address(erc721s[0]),
            0
        );

        // populate the array
        rentalAssets[0] = RentalAssetUpdate(rentalId, 1);

        // impersonate an address with permissions
        vm.prank(address(create));

        // add rentals to storage
        STORE.addRentals(RENTAL_ORDER_HASH, rentalAssets);

        // impersonate an address with permissions
        vm.prank(address(stop));

        // remove rentals from storage
        STORE.removeRentals(RENTAL_ORDER_HASH, rentalAssets);

        // assert that the rental order is not storage
        assertEq(STORE.orders(RENTAL_ORDER_HASH), false);

        // assert that the rental ID is not in storage
        assertEq(STORE.rentedAssets(rentalAssets[0].rentalId), 0);

        // assert that the item is not rented out
        assertEq(STORE.isRentedOut(address(alice.safe), address(erc721s[0]), 0), 0);
    }

    function test_Reverts_RemoveRentals_NoPermissions() public {
        // Create a rental asset array
        RentalAssetUpdate[] memory rentalAssets = new RentalAssetUpdate[](1);

        // create the rental ID
        RentalId rentalId = RentalUtils.getItemPointer(
            address(alice.safe),
            address(erc721s[0]),
            0
        );

        // populate the array
        rentalAssets[0] = RentalAssetUpdate(rentalId, 1);

        // impersonate an address with permissions
        vm.prank(address(create));

        // add rentals to storage
        STORE.addRentals(RENTAL_ORDER_HASH, rentalAssets);

        // impersonate an address without permissions
        vm.prank(alice.addr);

        // Expect revert because the caller does not have permissions
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Module_PolicyNotAuthorized.selector, alice.addr)
        );
        STORE.removeRentals(RENTAL_ORDER_HASH, rentalAssets);
    }

    function test_Success_RemoveRentalsBatch() public {
        // create some rental IDs
        RentalId rentalIdFirst = RentalUtils.getItemPointer(
            address(alice.safe),
            address(erc721s[0]),
            0
        );
        RentalId rentalIdSecond = RentalUtils.getItemPointer(
            address(alice.safe),
            address(erc721s[0]),
            1
        );

        // Create a rental asset arrays
        RentalAssetUpdate[] memory rentalAssetsFirstOrder = new RentalAssetUpdate[](1);
        RentalAssetUpdate[] memory rentalAssetsSecondOrder = new RentalAssetUpdate[](1);
        RentalAssetUpdate[] memory rentalAssetsCombined = new RentalAssetUpdate[](2);

        // populate the arrays
        rentalAssetsFirstOrder[0] = RentalAssetUpdate(rentalIdFirst, 1);
        rentalAssetsSecondOrder[0] = RentalAssetUpdate(rentalIdSecond, 1);

        // populate the comnbined array
        rentalAssetsCombined[0] = RentalAssetUpdate(rentalIdFirst, 1);
        rentalAssetsCombined[1] = RentalAssetUpdate(rentalIdSecond, 1);

        // Create a rental order hash array
        bytes32[] memory rentalOrderHashes = new bytes32[](2);
        rentalOrderHashes[0] = RENTAL_ORDER_HASH;
        rentalOrderHashes[1] = keccak256(abi.encode("someOtherRentalOrderHash"));

        // impersonate an address with permissions
        vm.startPrank(address(create));

        // add rentals to storage
        STORE.addRentals(rentalOrderHashes[0], rentalAssetsFirstOrder);
        STORE.addRentals(rentalOrderHashes[1], rentalAssetsSecondOrder);

        // stop impersonating
        vm.stopPrank();

        // impersonate an address with permissions
        vm.prank(address(stop));

        // remove rentals from storage
        STORE.removeRentalsBatch(rentalOrderHashes, rentalAssetsCombined);

        // assert that the rental order is not storage
        for (uint256 i = 0; i < rentalOrderHashes.length; i++) {
            assertEq(STORE.orders(rentalOrderHashes[i]), false);
        }

        // assert that the rental ID is not in storage
        for (uint256 i = 0; i < rentalAssetsCombined.length; i++) {
            assertEq(STORE.rentedAssets(rentalAssetsCombined[i].rentalId), 0);
        }

        // assert that the item is not rented out
        for (uint256 i = 0; i < 2; i++) {
            assertEq(STORE.isRentedOut(address(alice.safe), address(erc721s[0]), i), 0);
        }
    }

    function test_Reverts_RemoveRentalsBatch_NoPermissions() public {
        // create some rental IDs
        RentalId rentalIdFirst = RentalUtils.getItemPointer(
            address(alice.safe),
            address(erc721s[0]),
            0
        );
        RentalId rentalIdSecond = RentalUtils.getItemPointer(
            address(alice.safe),
            address(erc721s[0]),
            1
        );

        // Create a rental asset arrays
        RentalAssetUpdate[] memory rentalAssetsFirstOrder = new RentalAssetUpdate[](1);
        RentalAssetUpdate[] memory rentalAssetsSecondOrder = new RentalAssetUpdate[](1);
        RentalAssetUpdate[] memory rentalAssetsCombined = new RentalAssetUpdate[](2);

        // populate the arrays
        rentalAssetsFirstOrder[0] = RentalAssetUpdate(rentalIdFirst, 1);
        rentalAssetsSecondOrder[0] = RentalAssetUpdate(rentalIdSecond, 1);

        // populate the comnbined array
        rentalAssetsCombined[0] = RentalAssetUpdate(rentalIdFirst, 1);
        rentalAssetsCombined[1] = RentalAssetUpdate(rentalIdSecond, 1);

        // Create a rental order hash array
        bytes32[] memory rentalOrderHashes = new bytes32[](2);
        rentalOrderHashes[0] = RENTAL_ORDER_HASH;
        rentalOrderHashes[1] = keccak256(abi.encode("someOtherRentalOrderHash"));

        // impersonate an address with permissions
        vm.startPrank(address(create));

        // add rentals to storage
        STORE.addRentals(rentalOrderHashes[0], rentalAssetsFirstOrder);
        STORE.addRentals(rentalOrderHashes[1], rentalAssetsSecondOrder);

        // stop impersonating
        vm.stopPrank();

        // impersonate an address without permissions
        vm.prank(alice.addr);

        // Expect revert because the caller does not have permissions
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Module_PolicyNotAuthorized.selector, alice.addr)
        );
        STORE.removeRentalsBatch(rentalOrderHashes, rentalAssetsCombined);
    }

    function test_Success_AddRentalSafe() public {
        // impersonate an address with permissions
        vm.prank(address(factory));

        // add the rental safe
        STORE.addRentalSafe(TEST_ADDR_1);

        // get the updated total safe count
        uint256 totalSafes = STORE.totalSafes();

        // assert the nonce was incremented
        assertEq(STORE.totalSafes(), totalSafes);

        // assert the safe was assigned the nonce
        assertEq(STORE.deployedSafes(TEST_ADDR_1), totalSafes);
    }

    function test_Reverts_AddRentalSafe_NoPermissions() public {
        // impersonate an address without permissions
        vm.prank(alice.addr);

        // Expect revert because the caller does not have permissions
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Module_PolicyNotAuthorized.selector, alice.addr)
        );
        STORE.addRentalSafe(TEST_ADDR_1);
    }

    function test_Success_UpdateHookPath() public {
        // impersonate an address with permissions
        vm.prank(address(guard));

        // update the hook path by putting it between the caller and the target
        STORE.updateHookPath(address(mockTarget), address(mockHook));

        // assert that the path hasnt updated because the status
        // hasnt changed
        assertEq(STORE.contractToHook(address(mockTarget)), address(0));

        // impersonate an address with permissions
        vm.prank(address(guard));

        // update the hook status to 0x00000101 which enables `onTransaction` and `onStop` hooks
        STORE.updateHookStatus(address(mockHook), uint8(5));

        // assert that the path has updated
        assertEq(STORE.contractToHook(address(mockTarget)), address(mockHook));
    }

    function test_Reverts_UpdateHookPath_ToAddressNotContract() public {
        // impersonate an address with permissions
        vm.prank(address(guard));

        // Expect revert because the `to` address is not a contract
        vm.expectRevert(
            abi.encodeWithSelector(Errors.StorageModule_NotContract.selector, TEST_ADDR_1)
        );
        STORE.updateHookPath(TEST_ADDR_1, address(mockHook));
    }

    function test_Reverts_UpdateHookPath_HookAddressNotContract() public {
        // impersonate an address with permissions
        vm.prank(address(guard));

        // Expect revert because the `hook` address is not a contract
        vm.expectRevert(
            abi.encodeWithSelector(Errors.StorageModule_NotContract.selector, TEST_ADDR_2)
        );
        STORE.updateHookPath(address(mockTarget), TEST_ADDR_2);
    }

    function test_Reverts_UpdateHookPath_NoPermissions() public {
        // impersonate an address without permissions
        vm.prank(alice.addr);

        // Expect revert because the caller does not have permissions
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Module_PolicyNotAuthorized.selector, alice.addr)
        );
        STORE.updateHookPath(TEST_ADDR_1, TEST_ADDR_2);
    }

    function test_Success_UpdateHookStatus() public {
        // impersonate an address with permissions
        vm.prank(address(guard));

        // update the hook status to 0x00000101 which enables `onTransaction` and `onStop` hooks
        STORE.updateHookStatus(address(mockHook), uint8(5));

        // assert that the status has changed
        assertEq(STORE.hookStatus(address(mockHook)), uint8(5));

        // assert that the `onTransaction` hook is enabled
        assertEq(STORE.hookOnTransaction(address(mockHook)), true);

        // assert that the `onStop` hook is enabled
        assertEq(STORE.hookOnStop(address(mockHook)), true);

        // assert that the `onStart` hook is disabled
        assertEq(STORE.hookOnStart(address(mockHook)), false);
    }

    function test_Reverts_UpdateHookStatus_NoPermissions() public {
        // impersonate an address without permissions
        vm.prank(alice.addr);

        // Expect revert because the caller does not have permissions
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Module_PolicyNotAuthorized.selector, alice.addr)
        );
        STORE.updateHookStatus(address(mockHook), uint8(3));
    }

    function test_Reverts_UpdateHookStatus_NotContract() public {
        // impersonate an address with permissions
        vm.prank(address(guard));

        // Expect revert because the hook address is not a contract
        vm.expectRevert(
            abi.encodeWithSelector(Errors.StorageModule_NotContract.selector, address(0))
        );
        STORE.updateHookStatus(address(0), uint8(3));
    }

    function test_Reverts_UpdateHookStatus_InvalidHookStatusBitmap() public {
        // impersonate an address with permissions
        vm.prank(address(guard));

        // Expect revert because the hook bitmap is greater than 0x00000111
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.StorageModule_InvalidHookStatusBitmap.selector,
                uint8(50)
            )
        );
        STORE.updateHookStatus(address(mockHook), uint8(50));
    }

    function test_Success_ToggleWhitelistDelegate() public {
        // impersonate an address with permissions
        vm.prank(address(admin));

        // enable this address to be delegate called by rental safes
        STORE.toggleWhitelistDelegate(TEST_ADDR_1, true);

        // assert the address is whitelisted
        assertTrue(STORE.whitelistedDelegates(TEST_ADDR_1));
    }

    function test_Reverts_ToggleWhitelistDelegate_NoPermissions() public {
        // impersonate an address without permissions
        vm.prank(alice.addr);

        // Expect revert because the caller does not have permissions
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Module_PolicyNotAuthorized.selector, alice.addr)
        );
        STORE.toggleWhitelistDelegate(TEST_ADDR_1, true);
    }

    function test_Success_ToggleWhitelistExtension() public {
        // impersonate an address with permissions
        vm.prank(address(admin));

        // update the hook status to 0x11 which allows the extension to be
        // enabled and disabled.
        STORE.toggleWhitelistExtension(address(this), uint8(3));

        // assert that the extension can be enabled
        assertEq(STORE.extensionEnableAllowed(address(this)), true);

        // assert that the extension can be disabled
        assertEq(STORE.extensionDisableAllowed(address(this)), true);
    }

    function test_Reverts_ToggleWhitelistExtension_NoPermissions() public {
        // impersonate an address without permissions
        vm.prank(alice.addr);

        // Expect revert because the caller does not have permissions
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Module_PolicyNotAuthorized.selector, alice.addr)
        );
        STORE.toggleWhitelistExtension(TEST_ADDR_1, uint8(1));
    }

    function test_Reverts_ToggleWhitelistExtension_NotContract() public {
        // impersonate an address with permissions
        vm.prank(address(admin));

        // Expect revert because the hook address is not a contract
        vm.expectRevert(
            abi.encodeWithSelector(Errors.StorageModule_NotContract.selector, address(0))
        );
        STORE.toggleWhitelistExtension(address(0), uint8(2));
    }

    function test_Reverts_ToggleWhitelistExtension_InvalidBitmap() public {
        // impersonate an address with permissions
        vm.prank(address(admin));

        // Expect revert because the extension bitmap is greater than 0x11
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.StorageModule_InvalidWhitelistBitmap.selector,
                uint8(4)
            )
        );
        STORE.toggleWhitelistExtension(address(this), uint8(4));
    }

    function test_Success_ToggleWhitelistAsset_EnableRent_RestrictPermit() public {
        // impersonate an address with permissions
        vm.prank(address(admin));

        // enable this address to be used as a rented asset
        STORE.toggleWhitelistAsset(TEST_ADDR_1, uint8(3));

        // assert the address is whitelisted
        assertTrue(STORE.assetEnabledForRent(TEST_ADDR_1));
        assertTrue(STORE.assetRestrictedForPermit(TEST_ADDR_1));
    }

    function test_Success_ToggleWhitelistAsset_DisableRent_RestrictPermit() public {
        // impersonate an address with permissions
        vm.prank(address(admin));

        // enable this address to be used as a rented asset
        STORE.toggleWhitelistAsset(TEST_ADDR_1, uint8(1));

        // assert the address is whitelisted
        assertFalse(STORE.assetEnabledForRent(TEST_ADDR_1));
        assertTrue(STORE.assetRestrictedForPermit(TEST_ADDR_1));
    }

    function test_Reverts_ToggleWhitelistAsset_EnableRent_RestrictPermit() public {
        // impersonate an address with permissions
        vm.prank(address(admin));

        // enable this address to be used as a rented asset
        STORE.toggleWhitelistAsset(TEST_ADDR_1, uint8(3));

        // assert the address is whitelisted
        assertTrue(STORE.assetEnabledForRent(TEST_ADDR_1));
        assertTrue(STORE.assetRestrictedForPermit(TEST_ADDR_1));
    }

    function test_Reverts_ToggleWhitelistAsset_InvalidBitmap() public {
        // impersonate an address with permissions
        vm.prank(address(admin));

        // Expect revert because the bitmap is greater than 0x11
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.StorageModule_InvalidWhitelistBitmap.selector,
                uint8(4)
            )
        );
        STORE.toggleWhitelistAsset(TEST_ADDR_1, uint8(4));
    }

    function test_Success_ToggleWhitelistAssetBatch() public {
        // impersonate an address with permissions
        vm.prank(address(admin));

        // Plan to whitelist 3 assets
        address[] memory assets = new address[](3);
        uint8[] memory bitmaps = new uint8[](3);

        // build up the asset batch
        for (uint256 i; i < assets.length; ++i) {
            assets[i] = address(erc721s[i]);
            bitmaps[i] = uint8(3);
        }

        // whitelist the batch of tokens
        STORE.toggleWhitelistAssetBatch(assets, bitmaps);

        // assert each address is whitelisted
        for (uint256 i; i < assets.length; ++i) {
            assertTrue(STORE.assetEnabledForRent(assets[i]));
            assertTrue(STORE.assetRestrictedForPermit(assets[i]));
        }
    }

    function test_Reverts_ToggleWhitelistAssetBatch_LengthMismatch() public {
        // impersonate an address with permissions
        vm.prank(address(admin));

        // Expect revert because the arrays have a length mismatch
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.StorageModule_WhitelistBatchLengthMismatch.selector,
                uint256(2),
                uint256(3)
            )
        );
        STORE.toggleWhitelistAssetBatch(new address[](2), new uint8[](3));
    }

    function test_Reverts_ToggleWhitelistAssetBatch_InvalidBitmap() public {
        // impersonate an address with permissions
        vm.prank(address(admin));

        // Plan to whitelist 3 assets
        address[] memory assets = new address[](3);
        uint8[] memory bitmaps = new uint8[](3);

        // build up the asset batch
        for (uint256 i; i < assets.length; ++i) {
            assets[i] = address(erc721s[i]);
            bitmaps[i] = uint8(4);
        }

        // Expect revert because the bitmap is greater than 0x11
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.StorageModule_InvalidWhitelistBitmap.selector,
                uint8(4)
            )
        );
        STORE.toggleWhitelistAssetBatch(assets, bitmaps);
    }

    function test_Reverts_ToggleWhitelistAssetBatch_NoPermissions() public {
        // impersonate an address without permissions
        vm.prank(alice.addr);

        // Expect revert because the caller does not have permissions
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Module_PolicyNotAuthorized.selector, alice.addr)
        );
        STORE.toggleWhitelistAssetBatch(new address[](0), new uint8[](0));
    }

    function test_Success_ToggleWhitelistPayment() public {
        // impersonate an address with permissions
        vm.prank(address(admin));

        // enable this address to be used as a rented asset
        STORE.toggleWhitelistPayment(TEST_ADDR_1, true);

        // assert the address is whitelisted
        assertTrue(STORE.whitelistedPayments(TEST_ADDR_1));
    }

    function test_Reverts_ToggleWhitelistPayment_NoPermissions() public {
        // impersonate an address without permissions
        vm.prank(alice.addr);

        // Expect revert because the caller does not have permissions
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Module_PolicyNotAuthorized.selector, alice.addr)
        );
        STORE.toggleWhitelistPayment(TEST_ADDR_1, true);
    }

    function test_Success_ToggleWhitelistPaymentBatch() public {
        // impersonate an address with permissions
        vm.prank(address(admin));

        // Plan to whitelist 3 payments
        address[] memory payments = new address[](3);
        bool[] memory enabled = new bool[](3);

        // build up the payment batch
        for (uint256 i; i < payments.length; ++i) {
            payments[i] = address(erc20s[i]);
            enabled[i] = true;
        }

        // whitelist the batch of tokens
        STORE.toggleWhitelistPaymentBatch(payments, enabled);

        // assert each address is whitelisted
        for (uint256 i; i < payments.length; ++i) {
            assertTrue(STORE.whitelistedPayments(payments[i]));
        }
    }

    function test_Reverts_ToggleWhitelistPaymentBatch_LengthMismatch() public {
        // impersonate an address with permissions
        vm.prank(address(admin));

        // Expect revert because the arrays have a length mismatch
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.StorageModule_WhitelistBatchLengthMismatch.selector,
                uint256(2),
                uint256(3)
            )
        );
        STORE.toggleWhitelistPaymentBatch(new address[](2), new bool[](3));
    }

    function test_Reverts_ToggleWhitelistPaymentBatch_NoPermissions() public {
        // impersonate an address without permissions
        vm.prank(alice.addr);

        // Expect revert because the caller does not have permissions
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Module_PolicyNotAuthorized.selector, alice.addr)
        );
        STORE.toggleWhitelistPaymentBatch(new address[](0), new bool[](0));
    }

    function test_Success_SetMaxRentDuration() public {
        // impersonate an address with permissions
        vm.prank(address(admin));

        // set the max rent duration
        STORE.setMaxRentDuration(22 days);

        // assert the max rent duration changed
        assertEq(STORE.maxRentDuration(), 22 days);
    }

    function test_Reverts_SetMaxRentDuration_NoPermissions() public {
        // impersonate an address without permissions
        vm.prank(alice.addr);

        // Expect revert because the caller does not have permissions
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Module_PolicyNotAuthorized.selector, alice.addr)
        );
        STORE.setMaxRentDuration(22 days);
    }

    function test_Success_SetMaxOfferItems() public {
        // impersonate an address with permissions
        vm.prank(address(admin));

        // set the max offer items
        STORE.setMaxOfferItems(15);

        // expect the max offer items to have changed
        assertEq(STORE.maxOfferItems(), 15);
    }

    function test_Reverts_SetMaxOfferItems_NoPermissions() public {
        // impersonate an address without permissions
        vm.prank(alice.addr);

        // Expect revert because the caller does not have permissions
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Module_PolicyNotAuthorized.selector, alice.addr)
        );
        STORE.setMaxOfferItems(15);
    }

    function test_Success_SetMaxConsiderationItems() public {
        // impersonate an address with permissions
        vm.prank(address(admin));

        // set the max consideration items
        STORE.setMaxConsiderationItems(15);

        // expect the max consideration items to have changed
        assertEq(STORE.maxConsiderationItems(), 15);
    }

    function test_Reverts_SetMaxConsiderationItems_NoPermissions() public {
        // impersonate an address without permissions
        vm.prank(alice.addr);

        // Expect revert because the caller does not have permissions
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Module_PolicyNotAuthorized.selector, alice.addr)
        );
        STORE.setMaxConsiderationItems(15);
    }

    function test_Success_SetGuardEmergencyUpgrade() public {
        // impersonate an address with permissions
        vm.prank(address(admin));

        // set the guard's emergency upgrade contract
        STORE.setGuardEmergencyUpgrade(address(this));

        // expect the guard's emergency upgrade contract to have changed
        assertEq(STORE.guardEmergencyUpgrade(), address(this));
    }

    function test_Reverts_SetGuardEmergencyUpgrade_NoPermissions() public {
        // impersonate an address without permissions
        vm.prank(alice.addr);

        // Expect revert because the caller does not have permissions
        vm.expectRevert(
            abi.encodeWithSelector(Errors.Module_PolicyNotAuthorized.selector, alice.addr)
        );
        STORE.setGuardEmergencyUpgrade(address(this));
    }
}
