//SPDX-License-Identifier: free
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Governance {
    address public governanceToken;
    uint256 public nextProposalId = 1;

    struct Proposal {
        address creator;
        uint256 totalVotesYes;
        uint256 totalVotesNo;
        uint256 totalWeightYes;
        uint256 totalWeightNo;
        uint64 minimumVotes;
        uint64 minimumWeight;
        uint16 majorityRequiredToPass;
        uint256 deadline;
        string proposalQuestion;
        string proposalDescription;
        uint256 totalWeight;
        uint256 totalVotes;
        mapping(address => uint256) votes;
        mapping(address => uint256) snapshotBalances;
        uint256 snapshotBlock;
    }

    enum ProposalStatus {
        YES,
        NO,
        InsufficientVotersInterest
    }

    mapping(uint256 => Proposal) public proposals;
    uint256[] public proposalIds;

    // sets the governance token
    constructor(address _governanceToken) {
        governanceToken = _governanceToken;
    }

    event VoteCast(
        address indexed voter,
        uint256 indexed proposalId,
        bool support,
        uint256 weight
    );
    event VoteEnded(
        uint256 indexed proposalId,
        uint256 totalVotesYes,
        uint256 totalWeightYes,
        uint256 totalVotesNo,
        uint256 totalWeightNo,
        ProposalStatus status
    );

    modifier onlyGovernanceTokenHolder() {
        require(
            IERC20(governanceToken).balanceOf(msg.sender) > 0,
            "Not a governance token holder"
        );
        _;
    }
    modifier didntVoteBefore(uint256 proposalId, address voter) {
        require(proposals[proposalId].votes[voter] == 0, "Already voted");
        _;
    }
    modifier proposalVotingIsActive(uint256 proposalId) {
        require(
            proposals[proposalId].deadline > block.timestamp,
            "Proposal voting is active"
        );
        _;
    }
    modifier proposalVotingIsEnded(uint256 proposalId) {
        require(
            proposals[proposalId].deadline < block.timestamp,
            "Proposal voting has ended"
        );
        _;
    }

    modifier proposalExists(uint256 proposalId) {
        require(
            proposals[proposalId].creator != address(0),
            "Proposal does not exist"
        );
        _;
    }

    function propose(
        string memory _proposalQuestion,
        string memory _proposalDescription,
        uint64 _minimumVotes,
        uint64 _minimumWeight,
        uint16 _majorityRequiredToPass,
        uint16 _durationInDays
    ) external onlyGovernanceTokenHolder {
        require(
            (_majorityRequiredToPass <= 70 && _majorityRequiredToPass >= 50) ||
                _majorityRequiredToPass == 0,
            "Majority must be 50%-70% or 0"
        );
        require(
            (_durationInDays >= 30 && _durationInDays <= 180) ||
                _durationInDays == 0,
            "Duration must be at least 30 days and a maximum of 180 days"
        );
        require(
            bytes(_proposalQuestion).length > 10,
            "Proposal question must be at least 10 characters long"
        );
        uint256 proposalId = nextProposalId++;

        Proposal storage proposal = proposals[proposalId];
        proposalIds.push(proposalId);

        // sets the proposal details
        proposal.creator = msg.sender;
        proposal.proposalQuestion = _proposalQuestion;
        proposal.proposalDescription = _proposalDescription;
        proposal.minimumVotes = _minimumVotes == 0 ? 1 : _minimumVotes;
        proposal.minimumWeight = _minimumWeight == 0 ? 1 : _minimumWeight;
        proposal.majorityRequiredToPass = _majorityRequiredToPass == 0
            ? 50
            : _majorityRequiredToPass;
        proposal.deadline =
            block.timestamp +
            (_durationInDays == 0 ? 60 : _durationInDays) *
            1 days;
        proposal.snapshotBlock = block.number;
    }

    function vote(
        uint256 proposalId,
        bool support
    )
        external
        onlyGovernanceTokenHolder
        proposalExists(proposalId)
        didntVoteBefore(proposalId, msg.sender)
        proposalVotingIsActive(proposalId)
    {
        Proposal storage proposal = proposals[proposalId];
        if (proposal.snapshotBalances[msg.sender] == 0) {
            proposal.snapshotBalances[msg.sender] = IERC20(governanceToken)
                .balanceOf(msg.sender);
        }
        uint256 weight = proposal.snapshotBalances[msg.sender];

        proposal.votes[msg.sender] = weight;

        proposal.totalVotes += 1;
        proposal.totalWeight += weight;
        if (support) {
            proposal.totalWeightYes += weight;
            proposal.totalVotesYes += 1;
        } else {
            proposal.totalWeightNo += weight;
            proposal.totalVotesNo += 1;
        }
        emit VoteCast(msg.sender, proposalId, support, weight);
    }

    function getVotingWeight(
        address voter,
        uint256 proposalId
    ) public view returns (uint256) {
        return proposals[proposalId].snapshotBalances[voter];
    }

    function end(
        uint256 proposalId
    ) external onlyGovernanceTokenHolder proposalVotingIsEnded(proposalId) {
        Proposal storage proposal = proposals[proposalId];

        bool beatsMinimumVotes = proposal.minimumVotes <=
            (proposal.totalVotesYes + proposal.totalVotesNo);
        bool beatsMinimumWeight = proposal.minimumWeight <=
            (proposal.totalWeightYes + proposal.totalWeightNo);
        bool beatsQuorum = false;
        uint256 totalWeight = proposal.totalWeightYes + proposal.totalWeightNo;
        if (totalWeight > 0) {
            uint256 yesPercentage = (proposal.totalWeightYes * 100) /
                totalWeight;
            beatsQuorum = yesPercentage >= proposal.majorityRequiredToPass;
        }

        if (!beatsMinimumVotes || !beatsMinimumWeight) {
            emit VoteEnded(
                proposalId,
                proposal.totalVotesYes,
                proposal.totalWeightYes,
                proposal.totalVotesNo,
                proposal.totalWeightNo,
                ProposalStatus.InsufficientVotersInterest
            );
        } else if (!beatsQuorum) {
            emit VoteEnded(
                proposalId,
                proposal.totalVotesYes,
                proposal.totalWeightYes,
                proposal.totalVotesNo,
                proposal.totalWeightNo,
                ProposalStatus.NO
            );
        } else {
            emit VoteEnded(
                proposalId,
                proposal.totalVotesYes,
                proposal.totalWeightYes,
                proposal.totalVotesNo,
                proposal.totalWeightNo,
                ProposalStatus.YES
            );
        }
    }

    // view functions
    // these don't affect functionality or state

    // ? can this be written in a better way?
    // function getProposal(uint256 proposalId) public view returns (
    //     address creator,
    //     uint256 totalVotesYes,
    //     uint256 totalVotesNo,
    //     uint256 totalWeightYes,
    //     uint256 totalWeightNo,
    //     uint64 minimumVotes,
    //     uint64 minimumWeight,
    //     uint16 majorityRequiredToPass,
    //     uint256 deadline,
    //     string memory proposalQuestion,
    //     string memory proposalDescription,
    //     uint256 totalWeight,
    //     uint256 totalVotes
    // ) {
    //     Proposal storage proposal = proposals[proposalId];
    //     return (
    //         proposal.creator,
    //         proposal.totalVotesYes,
    //         proposal.totalVotesNo,
    //         proposal.totalWeightYes,
    //         proposal.totalWeightNo,
    //         proposal.minimumVotes,
    //         proposal.minimumWeight,
    //         proposal.majorityRequiredToPass,
    //         proposal.deadline,
    //         proposal.proposalQuestion,
    //         proposal.proposalDescription,
    //         proposal.totalWeight,
    //         proposal.totalVotes
    //     );
    // }

    function getProposalStatus(
        uint256 proposalId
    ) public view returns (ProposalStatus) {
        Proposal storage proposal = proposals[proposalId];

        bool beatsMinimumVotes = proposal.minimumVotes <=
            (proposal.totalVotesYes + proposal.totalVotesNo);
        bool beatsMinimumWeight = proposal.minimumWeight <=
            (proposal.totalWeightYes + proposal.totalWeightNo);

        if (!beatsMinimumVotes || !beatsMinimumWeight) {
            return ProposalStatus.InsufficientVotersInterest;
        }

        uint256 totalWeight = proposal.totalWeightYes + proposal.totalWeightNo;
        if (totalWeight > 0) {
            uint256 yesPercentage = (proposal.totalWeightYes * 100) /
                totalWeight;
            return
                yesPercentage >= proposal.majorityRequiredToPass
                    ? ProposalStatus.YES
                    : ProposalStatus.NO;
        }

        return ProposalStatus.NO;
    }

    function hasVoted(
        uint256 proposalId,
        address voter
    ) public view returns (bool) {
        return proposals[proposalId].votes[voter] > 0;
    }

    function getVoteWeight(
        uint256 proposalId,
        address voter
    ) public view returns (uint256) {
        return proposals[proposalId].votes[voter];
    }

    function getRemainingTime(
        uint256 proposalId
    ) public view returns (uint256) {
        return proposals[proposalId].deadline - block.timestamp;
    }

    function getActiveProposals() public view returns (uint256[] memory) {
        uint256 activeCount = 0;
        for (uint256 i = 0; i < proposalIds.length; i++) {
            if (proposals[proposalIds[i]].deadline > block.timestamp) {
                activeCount++;
            }
        }

        uint256[] memory activeProposals = new uint256[](activeCount);
        uint256 count = 0;
        for (uint256 i = 0; i < proposalIds.length; i++) {
            if (proposals[proposalIds[i]].deadline > block.timestamp) {
                activeProposals[count] = proposalIds[i];
                count++;
            }
        }
        return activeProposals;
    }

    function getProposalsByCreator(
        address creator
    ) public view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < proposalIds.length; i++) {
            if (proposals[proposalIds[i]].creator == creator) {
                count++;
            }
        }

        uint256[] memory creatorProposals = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < proposalIds.length; i++) {
            if (proposals[proposalIds[i]].creator == creator) {
                creatorProposals[index] = proposalIds[i];
                index++;
            }
        }
        return creatorProposals;
    }
}

// modifier surpassedMinimumVoteCount() {
//     require(
//         proposal.minimumVotes <=
//             (proposal.totalVotesYes + proposal.totalVotesNo),
//         "Proposal voting has ended"
//     );
//     _;
// }
// modifier surpassedMinimumVoteWeight() {
//     require(
//         proposal.minimumWeight <=
//             (proposal.totalWeightYes + proposal.totalWeightNo),
//         "Proposal voting has ended"
//     );
//     _;
// }

// modifier didntSurpassMinimumVoteCount() {
//     require(
//         proposal.minimumVotes >
//             (proposal.totalVotesYes + proposal.totalVotesNo),
//         "Proposal voting has ended"
//     );
//     _;
// }
// modifier didntSurpassMinimumVoteWeight() {
//     require(
//         proposal.minimumWeight >
//             (proposal.totalWeightYes + proposal.totalWeightNo),
//         "Proposal voting has ended"
//     );
//     _;
// }
