// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {Raffle} from "src/Raffle.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {HelperConfig} from "script/HelperConfig.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "script/Interactions.s.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract Integration is Test {
    Raffle raffle;
    HelperConfig helperConfig;
    HelperConfig.NetworkConfig config;

    address public PLAYER = makeAddr("player");
    uint256 public constant PLAYER_BALANCE = 1 ether;

    modifier subed() {
        CreateSubscription cs = new CreateSubscription();
        (config.subscriptionId, ) = cs.createSubscription(
            config.vrfCoordinator,
            config.account
        );
        _;
    }

    modifier subedAndFunded() {
        CreateSubscription cs = new CreateSubscription();
        (config.subscriptionId, ) = cs.createSubscription(
            config.vrfCoordinator,
            config.account
        );

        FundSubscription fs = new FundSubscription();
        fs.fundSubscription(
            config.vrfCoordinator,
            config.subscriptionId,
            config.link,
            config.account
        );
        _;
    }

    function setUp() public {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        config = helperConfig.getConfig();
    }

    function testCreateSubscription() public {
        CreateSubscription cs = new CreateSubscription();

        (uint256 subid, address vrfCoordinator) = cs.createSubscriptionConfig();

        assertGt(subid, 0, "Subid must be greater than 0");
        assertTrue(vrfCoordinator != address(0));

        console2.log("creating subscription, subid:", subid);
        console2.log("creating subscription, vrfCoordinator:", vrfCoordinator);
    }

    function testFundSubscription() public subed {
        FundSubscription fs = new FundSubscription();

        uint256 startingBalance = VRFCoordinatorV2_5Mock(config.vrfCoordinator)
            .getSubscriptionBalance(config.subscriptionId);

        fs.fundSubscription(
            config.vrfCoordinator,
            config.subscriptionId,
            config.link,
            config.account
        );

        uint256 finalBalance = VRFCoordinatorV2_5Mock(config.vrfCoordinator)
            .getSubscriptionBalance(config.subscriptionId);

        assertGt(
            finalBalance,
            startingBalance,
            "final balance should greater than starting balance"
        );
    }

    function testAddConsumer() public subedAndFunded {
        AddConsumer ac = new AddConsumer();

        bool beforeAdded = VRFCoordinatorV2_5Mock(config.vrfCoordinator)
            .isConsumerAdded(config.subscriptionId, address(raffle));

        ac.addConsumer(
            address(raffle),
            config.vrfCoordinator,
            config.subscriptionId,
            config.account
        );

        bool afterAdded = VRFCoordinatorV2_5Mock(config.vrfCoordinator)
            .isConsumerAdded(config.subscriptionId, address(raffle));

        assertFalse(beforeAdded, "consumer must not being added first");
        assertTrue(afterAdded, "consumer must have been added after");
    }
}
