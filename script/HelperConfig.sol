// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";

error HelperConfig__InvalidChainId(uint256 chainId);

abstract contract ConstantValues {
    uint96 public constant MOCK_BASE_FEE = 0.1 ether;
    uint96 public constant MOCK_GAS_PRICE = 1e9;
    int256 public constant MOCK_WEI_PER_UNIT_LINK = 4e15;

    uint256 public constant LOCAL_CHAINID = 31337;
    uint256 public constant SEPOLIA_ETH_CHAINID = 11155111;
}

contract HelperConfig is ConstantValues, Script {
    struct NetworkConfig {
        uint256 entryFee;
        uint256 interval;
        address vrfCoordinator;
        bytes32 keyHash;
        uint256 subscriptionId;
        uint32 callbackGasLimit;
        address link;
        address account;
    }

    NetworkConfig private s_networkConfig;
    mapping(uint256 chainId => NetworkConfig) public network;

    constructor() {
        network[SEPOLIA_ETH_CHAINID] = getSepoliaEthConfig();
        network[LOCAL_CHAINID] = getLocalAnvilEthConfig();
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        if (s_networkConfig.vrfCoordinator != address(0)) {
            return s_networkConfig;
        }

        return
            NetworkConfig({
                entryFee: 0.01 ether,
                interval: 30 seconds,
                vrfCoordinator: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B,
                keyHash: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
                subscriptionId: 0,
                callbackGasLimit: 500000,
                link: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
                account: 0x47d43602F7216Ba62c6a5c47C130AA605c66A083 // this is Public Key
            });
    }

    function getLocalAnvilEthConfig() public returns (NetworkConfig memory) {
        if (s_networkConfig.vrfCoordinator != address(0)) {
            return s_networkConfig;
        }

        vm.startBroadcast();
        VRFCoordinatorV2_5Mock mockVRF = new VRFCoordinatorV2_5Mock(
            MOCK_BASE_FEE,
            MOCK_GAS_PRICE,
            MOCK_WEI_PER_UNIT_LINK
        );

        LinkToken linkToken = new LinkToken();
        vm.stopBroadcast();

        return
            NetworkConfig({
                entryFee: 0.01 ether,
                interval: 30 seconds,
                vrfCoordinator: address(mockVRF),
                keyHash: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
                subscriptionId: 0,
                callbackGasLimit: 500000,
                link: address(linkToken),
                account: 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38 // this is default msg.sender
            });
    }

    function getNetworkByChainId(
        uint256 chainId
    ) public returns (NetworkConfig memory) {
        if (network[chainId].vrfCoordinator != address(0)) {
            return network[chainId];
        } else if (chainId == LOCAL_CHAINID) {
            return getLocalAnvilEthConfig();
        } else {
            revert HelperConfig__InvalidChainId(chainId);
        }
    }

    function getConfig() public returns (NetworkConfig memory) {
        return getNetworkByChainId(block.chainid);
    }

    function setConfig(
        uint256 chainId,
        NetworkConfig memory networkConfig
    ) public {
        network[chainId] = networkConfig;
    }
}
