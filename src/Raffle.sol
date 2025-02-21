// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/* errors */
library Errors {
    error Raffle__InsufficientBalance(uint256 available, uint256 required);
    error Raffle__UpkeepNotNeeded(
        uint256 balance,
        uint256 participants,
        bool interval,
        uint256 raffleState
    );
    error Raffle__TransferFailed();
    error Raffle__RaffleClosed();
}

/**
 * @title Raffle
 * @author Lagxy
 * @notice A contract for a raffle.
 */

contract Raffle is VRFConsumerBaseV2Plus {
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    /* Type Declaration */
    enum RaffleState {
        OPEN,
        CLOSED
    }

    /* State Variable */
    uint256 private immutable i_entryFee;
    uint256 private immutable i_interval; // Interval in seconds
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    address payable[] private s_participants;
    address private s_recentWinner;
    uint256 private s_lastTimeStamp;
    RaffleState private s_raffleState = RaffleState.OPEN;

    event RaffleEntered(address indexed participant);
    event RaffleWinner(address indexed winner);
    event RaffleRequestedId(uint256 indexed requestId);

    constructor(
        uint256 entryFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entryFee = entryFee;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
    }

    function enterRaffle() external payable {
        if (msg.value < i_entryFee) {
            revert Errors.Raffle__InsufficientBalance({
                available: msg.value,
                required: i_entryFee
            });
        }

        if (s_raffleState == RaffleState.CLOSED) {
            revert Errors.Raffle__RaffleClosed();
        }

        s_participants.push(payable(msg.sender));

        emit RaffleEntered(msg.sender);
    }

    function checkUpkeep(
        bytes memory /*checkData*/
    ) public view returns (bool upkeepNeeded, bytes memory /*performData*/) {
        bool enoughTimePassed = block.timestamp - s_lastTimeStamp >= i_interval;
        bool enoughParticipants = s_participants.length > 0;
        bool hasBalance = address(this).balance > 0;
        bool raffleOpen = s_raffleState == RaffleState.OPEN;

        upkeepNeeded =
            enoughTimePassed &&
            enoughParticipants &&
            hasBalance &&
            raffleOpen;

        return (upkeepNeeded, "");
    }

    function performUpkeep(bytes calldata /* performData */) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Errors.Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_participants.length,
                block.timestamp - s_lastTimeStamp > i_interval,
                uint256(s_raffleState)
            );
        }

        s_raffleState = RaffleState.CLOSED;

        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: i_keyHash,
                subId: i_subscriptionId,
                requestConfirmations: REQUEST_CONFIRMATIONS,
                callbackGasLimit: i_callbackGasLimit,
                numWords: NUM_WORDS,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            });

        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);

        // redundant
        emit RaffleRequestedId(requestId);
    }

    function fulfillRandomWords(
        uint256 /*requestId*/,
        uint256[] calldata randomWords
    ) internal override {
        uint256 winnerIndex = randomWords[0] % s_participants.length;

        address payable winner = s_participants[winnerIndex];
        (bool success, ) = winner.call{value: address(this).balance}("");

        s_recentWinner = winner;
        s_raffleState = RaffleState.OPEN;
        s_participants = new address payable[](0);
        s_lastTimeStamp = block.timestamp;

        emit RaffleWinner(winner);

        if (!success) {
            revert Errors.Raffle__TransferFailed();
        }
    }

    /**
     * @dev Getter function
     */

    function getEntryFee() public view returns (uint256) {
        return i_entryFee;
    }

    function getInterval() public view returns (uint256) {
        return i_interval;
    }

    function getLastTimeStamp() public view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getRaffleState() public view returns (RaffleState) {
        return s_raffleState;
    }

    function getParticipants() public view returns (address payable[] memory) {
        return s_participants;
    }

    function getSingleParticipants(
        uint256 index
    ) public view returns (address) {
        return s_participants[index];
    }

    function getRecentWinner() public view returns (address) {
        return s_recentWinner;
    }
}
