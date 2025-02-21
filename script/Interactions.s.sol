// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {HelperConfig, ConstantValues} from "script/HelperConfig.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

contract CreateSubscription is Script {
    function createSubscriptionConfig() public returns (uint256, address) {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;
        address account = helperConfig.getConfig().account;

        (uint256 subid, ) = createSubscription(vrfCoordinator, account);

        return (subid, vrfCoordinator);
    }

    function createSubscription(
        address vrfCoordinator,
        address account
    ) public returns (uint256, address) {
        vm.startBroadcast(account);
        uint256 subid = VRFCoordinatorV2_5Mock(vrfCoordinator)
            .createSubscription();
        vm.stopBroadcast();

        return (subid, vrfCoordinator);
    }

    function run() public {
        createSubscriptionConfig();
    }
}

contract FundSubscription is Script, ConstantValues {
    uint256 private constant FUND_AMOUNT = 30 ether;

    function fundSubscriptionConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;
        uint256 subid = helperConfig.getConfig().subscriptionId;
        address link = helperConfig.getConfig().link;
        address account = helperConfig.getConfig().account;

        fundSubscription(vrfCoordinator, subid, link, account);
    }

    function fundSubscription(
        address vrfCoordinator,
        uint256 subid,
        address link,
        address account
    ) public {
        if (block.chainid == LOCAL_CHAINID) {
            vm.startBroadcast();
            VRFCoordinatorV2_5Mock(vrfCoordinator).fundSubscription(
                subid,
                FUND_AMOUNT
            );
            vm.stopBroadcast();
        } else {
            vm.startBroadcast(account);
            LinkToken(link).transferAndCall(
                vrfCoordinator,
                FUND_AMOUNT,
                abi.encode(subid)
            );
            vm.stopBroadcast();
        }
    }

    function run() public {
        fundSubscriptionConfig();
    }
}

contract AddConsumer is Script {
    function addConsumerConfig(address recentDeployment) public {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;
        address account = helperConfig.getConfig().account;
        uint256 subid = helperConfig.getConfig().subscriptionId;

        addConsumer(recentDeployment, vrfCoordinator, subid, account);
    }

    function addConsumer(
        address contractToAdd,
        address vrfCoordinator,
        uint256 subid,
        address account
    ) public {
        vm.startBroadcast(account);
        VRFCoordinatorV2_5Mock(vrfCoordinator).addConsumer(
            subid,
            contractToAdd
        );
        vm.stopBroadcast();
    }

    function run() external {
        address recentDeployment = DevOpsTools.get_most_recent_deployment(
            "Raffle",
            block.chainid
        );

        addConsumerConfig(recentDeployment);
    }
}
