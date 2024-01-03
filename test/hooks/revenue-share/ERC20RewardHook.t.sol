// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {Order, OfferItem, ItemType} from "@seaport-types/lib/ConsiderationStructs.sol";

import {
    ERC20RewardHook,
    RevenueShare
} from "@src/examples/revenue-share/ERC20RewardHook.sol";
import {
    Hook,
    OrderType,
    OrderMetadata,
    RentalOrder
} from "@src/libraries/RentalStructs.sol";

import {BaseTest} from "@test/BaseTest.sol";
import {MockERC20} from "@test/mocks/tokens/standard/MockERC20.sol";
import {MockERC1155} from "@test/mocks/tokens/standard/MockERC1155.sol";

contract Hook_ERC20RewardHook_Test is BaseTest {
    // hook contract
    ERC20RewardHook public hook;

    // token that the hook contract will distribute
    MockERC20 public rewardToken;

    // token which will be rented
    MockERC1155 public gameToken;

    function setUp() public override {
        super.setUp();

        // deploy contracts needed for hook
        rewardToken = new MockERC20();
        gameToken = new MockERC1155();
        hook = new ERC20RewardHook(
            address(create),
            address(stop),
            address(gameToken),
            address(rewardToken)
        );

        // admin enables the hook. Use binary 00000110 so that the hook
        // is enabled for `onStart` and `onStop` calls
        vm.prank(deployer.addr);
        guard.updateHookStatus(address(hook), uint8(6));

        // fund the hook contract with some reward tokens
        rewardToken.mint(address(hook), 100e18);

        // fund the lender with some game tokens
        gameToken.mint(alice.addr, 1e18);

        // approve the game token to be spent by the Seaport conduit
        vm.prank(alice.addr);
        gameToken.setApprovalForAll(address(conduit), true);

        // set the token label with the index
        vm.label(address(rewardToken), "MERC20_RewardToken");

        // assert that hook set up was successful
        assertEq(STORE.hookOnStart(address(hook)), true);
        assertEq(STORE.hookOnStop(address(hook)), true);

        // assert that the hook was funded with the reward token
        assertEq(rewardToken.balanceOf(address(hook)), 100e18);
    }

    // Helper function to start a rental using the game token
    function _startRentalWithGameToken()
        internal
        returns (RentalOrder memory rentalOrder)
    {
        // create a BASE order where a lender offers the `gameToken` in
        // exchange for some erc20 tokens
        createOrder({
            offerer: alice,
            orderType: OrderType.BASE,
            erc721Offers: 0,
            erc1155Offers: 1,
            erc20Offers: 0,
            erc721Considerations: 0,
            erc1155Considerations: 0,
            erc20Considerations: 1
        });

        // create a custom offer item that uses the game token
        OfferItem[] memory offers = new OfferItem[](1);
        offers[0] = OfferItem({
            itemType: ItemType.ERC1155,
            token: address(gameToken),
            identifierOrCriteria: 0,
            startAmount: 1e18,
            endAmount: 1e18
        });

        // Define the extra data to be used by the hook
        RevenueShare memory revenueShareData = RevenueShare({
            // lender address which will receive the rewards
            lender: alice.addr,
            // lender wants to take 70% of the revenue
            lenderShare: 70
        });

        // Define the hook for the rental
        Hook[] memory hooks = new Hook[](1);
        hooks[0] = Hook({
            // the hook contract to target
            target: address(hook),
            // index of the item in the order to apply the hook to
            itemIndex: 0,
            // any extra data that the hook will need.
            extraData: abi.encode(revenueShareData)
        });

        // use an amendment to switch the offer item to the game token
        withReplacedOfferItems(offers);

        // use an amendment to add hooks to the metadata
        withOrderMetadata(
            OrderMetadata({
                // the type of order being created
                orderType: OrderType.BASE,
                // the duration of the rental in seconds
                rentDuration: 500,
                // the hooks that will act as middleware for the items in the order
                hooks: hooks,
                // any extra data to be emitted upon order fulfillment
                emittedExtraData: bytes("")
            })
        );

        // finalize the order creation
        (
            Order memory order,
            bytes32 orderHash,
            OrderMetadata memory metadata
        ) = finalizeOrder();

        // create an order fulfillment
        createOrderFulfillment({
            _fulfiller: bob,
            order: order,
            orderHash: orderHash,
            metadata: metadata
        });

        // finalize the base order fulfillment. This executes the token swap
        // and starts the rental.
        rentalOrder = finalizeBaseOrderFulfillment();
    }

    function test_Success_RewardShare() public {
        // start the rental. This should activate the hook and begin
        // accruing rewards while the rental is active.
        RentalOrder memory rentalOrder = _startRentalWithGameToken();

        // roll ahead by 100 blocks so that rewards can accrue
        vm.roll(block.number + 100);

        // speed up in time past the rental expiration
        vm.warp(block.timestamp + 750);

        // stop the rental
        vm.prank(alice.addr);
        stop.stopRent(rentalOrder);

        // owner of the safe can claim tokens
        vm.prank(bob.addr);
        hook.claimRewards(address(bob.safe));

        // lender of the rental can claim tokens
        vm.prank(alice.addr);
        hook.claimRewards(alice.addr);

        // earned rewards should be 100 blocks * 1 gwei reward per block * 1e18 token,
        // which is 100 gwei
        assertEq(rewardToken.balanceOf(bob.addr), 30000000000); // 30 gwei
        assertEq(rewardToken.balanceOf(alice.addr), 70000000000); // 70 gwei
    }
}
