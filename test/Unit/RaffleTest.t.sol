// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Raffle, Errors} from "src/Raffle.sol";
import {HelperConfig, ConstantValues} from "script/HelperConfig.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract RaffleTest is Test, ConstantValues {
    Raffle public raffle;
    HelperConfig public helperConfig;
    HelperConfig.NetworkConfig public config;

    uint256 public entryFee;

    address public PLAYER = makeAddr("participant");
    uint256 public constant STARTING_BALANCE = 10 ether;

    event RaffleEntered(address indexed participant);
    event RaffleWinner(address indexed winner);

    modifier funded() {
        vm.deal(PLAYER, STARTING_BALANCE);
        _;
    }

    modifier upkeepNeeded() {
        vm.startPrank(PLAYER);
        raffle.enterRaffle{value: entryFee}();
        vm.warp(block.timestamp + raffle.getInterval() + 1);
        vm.roll(block.number + 1);
        vm.stopPrank();
        _;
    }

    modifier skipFork() {
        if (block.chainid == LOCAL_CHAINID) {
            return;
        }
        _;
    }

    function setUp() public {
        DeployRaffle deployer = new DeployRaffle();

        (raffle, helperConfig) = deployer.run();
        entryFee = raffle.getEntryFee();
        config = helperConfig.getConfig();
    }

    function testRaffleDeployed() public view {
        assert(address(raffle) != address(0));
    }

    /**
     * @notice Test initial state of the raffle
     */

    function testInitialRaffleState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    /**
     * @notice Test enterRaffle Function
     */

    function testEnterRaffleRevertWhenParticipantEnoughBalance() public {
        vm.prank(PLAYER);
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Raffle__InsufficientBalance.selector,
                PLAYER.balance,
                entryFee
            )
        );
        raffle.enterRaffle();
    }

    function testEnterRaffleRecordParticipantWhenEnterRaffle()
        public
        funded
        upkeepNeeded
    {
        assert(raffle.getParticipants().length == 1);
        assert(raffle.getSingleParticipants(0) == address(PLAYER));
    }

    function testEnterRaffleEmitParticipant() public funded {
        vm.startPrank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(PLAYER);

        raffle.enterRaffle{value: entryFee}();
        vm.stopPrank();
    }

    function testEnterRafflePreventPlayerToEnterWhileRaffleClosed()
        public
        funded
        upkeepNeeded
    {
        raffle.performUpkeep("");
        vm.expectRevert(Errors.Raffle__RaffleClosed.selector);
        raffle.enterRaffle{value: entryFee}();
        vm.stopPrank();
    }

    /**
     * @notice Test checkUpkeep Function
     */

    function testUpkeepNotNeededWhenNotEnoughParticipants() public funded {
        vm.warp(block.timestamp + raffle.getInterval() + 1);
        vm.roll(block.number + 1);

        (bool needUpkeep, ) = raffle.checkUpkeep("");

        assert(needUpkeep == false);
    }

    function testUpkeepNotNeededWhenRaffleClose() public funded upkeepNeeded {
        raffle.performUpkeep("");
        (bool needUpkeep, ) = raffle.checkUpkeep("");
        assert(needUpkeep == false);
    }

    /*
     * @notice Test performUpkeep Function
     */

    function testPerformUpkeepRevertWhenUpkeepNotNeeded() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                Errors.Raffle__UpkeepNotNeeded.selector,
                address(raffle).balance,
                raffle.getParticipants().length,
                block.timestamp - raffle.getLastTimeStamp() >
                    raffle.getInterval(),
                raffle.getRaffleState()
            )
        );
        raffle.performUpkeep("");
    }

    function testPerformUpkeepEmitRequestIdAndChangeRaffleState()
        public
        funded
        upkeepNeeded
    {
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // bytes32 requestId = logs[0].topics[1];
        bytes32 requestId2 = logs[1].topics[1];

        // console.log("vrf requestId: ", uint256(requestId));
        // console.log("custom event requestId: ", uint256(requestId2));

        assert(raffle.getRaffleState() == Raffle.RaffleState.CLOSED);
        assert(requestId2 > 0);
    }

    /**
     * @notice Test fulfillRandomWords Function
     */

    function testfulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 requestId
    ) public skipFork {
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(config.vrfCoordinator).fulfillRandomWords(
            requestId,
            address(raffle)
        );
    }

    function testfulfillRandomWordsPickWinnerAndResetRaffle()
        public
        funded
        upkeepNeeded
        skipFork
    {
        uint256 additionalParticipants = 4;
        address expectedWinner = address(1);

        for (uint256 i = 1; i <= additionalParticipants; i++) {
            hoax(address(uint160(i)), 1 ether);
            raffle.enterRaffle{value: entryFee}();
        }

        // check last timestamp
        uint256 lastTimeStamp = raffle.getLastTimeStamp();
        uint256 winnerStartingBalance = expectedWinner.balance; // refac

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 requestId = logs[1].topics[1];

        VRFCoordinatorV2_5Mock(config.vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = entryFee * (additionalParticipants + 1);

        assert(recentWinner == expectedWinner);
        assert(uint256(raffleState) == 0);
        assert(winnerBalance == winnerStartingBalance + prize);
        assert(endingTimeStamp > lastTimeStamp);
    }
}
