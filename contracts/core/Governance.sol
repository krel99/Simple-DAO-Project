//SPDX-License-Identifier: free
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Governance {
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
        mapping(address => uint256) votes;
    }

    enum ProposalStatus {
        YES,
        NO,
        InsufficientVotersInterest
    }

    mapping(bytes32 => Proposal) public proposals;

    event VoteCast(msg.sender, proposalId, support, weight);
    event VoteEnded(
        bytes32 indexed proposalId,
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
    modifier didntVoteBefore(address voter) {
        require(votes[voter] == 0, "Already voted");
        _;
    }
    modifier proposalVotingIsActive() {
        require(
            proposal.deadline > block.timestamp,
            "Proposal voting is active"
        );
        _;
    }
    modifier proposalVotingIsEnded() {
        require(
            proposal.deadline < block.timestamp,
            "Proposal voting has ended"
        );
        _;
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

    function propose(
        bytes32 proposalId,
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

        Proposal storage proposal = proposals[proposalId];
        proposal.creator = msg.sender;
        proposal.proposalQuestion = _proposalQuestion;
        proposal.proposalDescription = _proposalDescription;
        proposal.minimumVotes = _minimumVotes;
        proposal.minimumWeight = _minimumWeight;
        proposal.majorityRequiredToPass = _majorityRequiredToPass == 0
            ? 50
            : _majorityRequiredToPass;
        proposal.deadline =
            block.timestamp +
            (_durationInDays == 0 ? 60 : _durationInDays) *
            1 days;
    }

    function vote(
        bytes32 proposalId,
        bool support
    )
        external
        onlyGovernanceTokenHolder
        didntVoteBefore
        proposalVotingIsActive
    {
        uint256 weight = getVotingWeight(msg.sender);
        totalVotes += 1;
        totalWeight += weight;
        if (support) {
            proposal.supportForYes += weight;
            proposal.totalVotesYes += 1;
        } else {
            proposal.supportForNo += weight;
            proposal.totalVotesNo += 1;
        }
        emit VoteCast(msg.sender, proposalId, support, weight);
    }

    function getVotingWeight(address voter) public view returns (uint256) {
        return IERC20(governanceToken).balanceOf(voter);
    }

    function end(
        bytes32 proposalId
    ) external onlyGovernanceTokenHolder proposalVotingIsEnded {
        bool beatsMinimumVotes = proposal.minimumVotes <=
            (proposal.totalVotesYes + proposal.totalVotesNo);
        bool beatsMinimumWeight = proposal.minimumWeight <=
            (proposal.totalWeightYes + proposal.totalWeightNo);
        bool beatsQuorum = (proposal.totalWeightYes - proposal.totalWeightNo) /
            (proposal.totalWeightYes + proposal.totalWeightNo) >
            proposal.majorityRequiredToPass;

        if (!beatsMinimumVotes || !beatsMinimumWeight) {
            emit VoteEnded(
                proposal.proposalId,
                proposal.totalVotesYes,
                proposal.totalWeightYes,
                proposal.totalVotesNo,
                proposal.totalWeightNo,
                InsufficientVotersInterest
            );
        }

        if (!beatsQuorum) {
            emit VoteEnded(
                proposal.proposalId,
                proposal.totalVotesYes,
                proposal.totalWeightYes,
                proposal.totalVotesNo,
                proposal.totalWeightNo,
                No
            );
        } else {
            emit VoteEnded(
                proposal.proposalId,
                proposal.totalVotesYes,
                proposal.totalWeightYes,
                proposal.totalVotesNo,
                proposal.totalWeightNo,
                Yes
            );
        }
    }
}
