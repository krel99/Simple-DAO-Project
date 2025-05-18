//SPDX-License-Identifier: free

pragma solidity 0.8.7;

contract Governance {
    address public creator;
    uint256 public totalVotesYes;
    uint256 public totalVotesNo;
    uint256 public totalWeightYes;
    uint256 public totalWeightNo;

    // optional inputs when creating the proposal (use 0 for defaults)
    uint64 public minimumVotes;
    uint64 public minimumWeight;
    uint16 public majorityRequiredToPass; // 50% by default, 70% maximum
    uint16 public durationInDays;

    // required inputs when creating the proposal
    string public proposalQuestion;
    string public proposalDescription;

    mapping(address => uint256) public votes;

    event newVote(address voter, uint256 weight, bool option);

    constructor(
        string memory _proposalQuestion,
        string memory _proposalDescription,
        uint64 _minimumVotes,
        uint64 _minimumWeight,
        uint16 _majorityRequiredToPass,
        uint16 _durationInDays
    ) {
        require(
            (_majorityRequiredToPass <= 70 && _majorityRequiredToPass >= 50) ||
                _majorityRequiredToPass == 0,
            "Majority must be 50%-70% or 0"
        );
        require(
            (_durationInDays >= 30 && _durationInDays <= 180) ||
                _majorityRequiredToPass == 0,
            "Duration must be at least 30 days and a maximum of 180 days"
        );
        require(
            bytes(_proposalQuestion).length > 10,
            "Proposal question must be at least 10 characters long"
        );
        proposalQuestion = _proposalQuestion;
        proposalDescription = _proposalDescription;
        minimumVotes = _minimumVotes;
        minimumWeight = _minimumWeight;
        majorityRequiredToPass = _majorityRequiredToPass == 0
            ? 50
            : _majorityRequiredToPass;
        durationInDays = _durationInDays;
    }

    function propose(
        bytes32 proposalId,
        address target,
        uint256 value,
        bytes memory data
    ) external {
        // Propose a new action
    }

    function vote(bytes32 proposalId, bool support) external {
        // Vote on a proposal
    }

    function execute(bytes32 proposalId) external {
        // Execute a proposal
    }

    function cancel(bytes32 proposalId) external {
        // Cancel a proposal
    }
}
