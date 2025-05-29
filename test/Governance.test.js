import { expect } from "chai";
import hardhat from "hardhat";
const { ethers } = hardhat;

import "@nomiclabs/hardhat-waffle";

describe("Governance Contract", function () {
  let governance;
  let mockToken;
  let owner;
  let voter1;
  let voter2;
  let voter3;
  let nonTokenHolder;

  const proposalId = ethers.utils.formatBytes32String("proposal1");
  const proposalQuestion = "Should we implement feature X?";
  const proposalDescription = "This proposal asks whether we should implement feature X to improve user experience.";
  const minimumVotes = 2;
  const minimumWeight = 1000;
  const majorityRequired = 60;
  const durationInDays = 60;

  beforeEach(async function () {
    // Get signers
    [owner, voter1, voter2, voter3, nonTokenHolder] = await ethers.getSigners();

    // Deploy mock ERC20 token, then contract(s), then distribute tokens
    const MockToken = await ethers.getContractFactory("MockERC20");
    mockToken = await MockToken.deploy("GovernanceToken", "GOV", ethers.utils.parseEther("10000"));
    await mockToken.deployed();

    const Governance = await ethers.getContractFactory("Governance");
    governance = await Governance.deploy(mockToken.address);
    await governance.deployed();

    await mockToken.transfer(voter1.address, ethers.utils.parseEther("1000")); // 1000 tokens
    await mockToken.transfer(voter2.address, ethers.utils.parseEther("500")); // 500 tokens
    await mockToken.transfer(voter3.address, ethers.utils.parseEther("300")); // 300 tokens
    // nonTokenHolder gets 0 tokens
  });

  describe("Deployment", function () {
    it("Should set the correct governance token", async function () {
      expect(await governance.governanceToken()).to.equal(mockToken.address);
    });
  });

  describe("Proposal Creation", function () {
    it("Should allow token holders to create proposals", async function () {
      await governance
        .connect(voter1)
        .propose(proposalId, proposalQuestion, proposalDescription, minimumVotes, minimumWeight, majorityRequired, durationInDays);

      const proposal = await governance.proposals(proposalId);
      expect(proposal.creator).to.equal(voter1.address);
      expect(proposal.proposalQuestion).to.equal(proposalQuestion);
      expect(proposal.proposalDescription).to.equal(proposalDescription);
      expect(proposal.minimumVotes.toNumber()).to.equal(minimumVotes);
      expect(proposal.minimumWeight.toNumber()).to.equal(minimumWeight);
      expect(proposal.majorityRequiredToPass.toNumber()).to.equal(majorityRequired);
    });

    it("Should reject proposals from non-token holders", async function () {
      await expect(
        governance
          .connect(nonTokenHolder)
          .propose(proposalId, proposalQuestion, proposalDescription, minimumVotes, minimumWeight, majorityRequired, durationInDays),
      ).to.be.revertedWith("Not a governance token holder");
    });

    it("Should reject proposals with invalid majority percentage", async function () {
      await expect(
        governance.connect(voter1).propose(
          proposalId,
          proposalQuestion,
          proposalDescription,
          minimumVotes,
          minimumWeight,
          80, // Invalid --- > 70%
          durationInDays,
        ),
      ).to.be.revertedWith("Majority must be 50%-70% or 0");

      await expect(
        governance.connect(voter1).propose(
          proposalId,
          proposalQuestion,
          proposalDescription,
          minimumVotes,
          minimumWeight,
          40, // Invalid ---< 50%
          durationInDays,
        ),
      ).to.be.revertedWith("Majority must be 50%-70% or 0");
    });

    it("Should reject proposals with invalid duration", async function () {
      await expect(
        governance.connect(voter1).propose(
          proposalId,
          proposalQuestion,
          proposalDescription,
          minimumVotes,
          minimumWeight,
          majorityRequired,
          20, // Invalid 30 days minimum
        ),
      ).to.be.revertedWith("Duration must be at least 30 days and a maximum of 180 days");

      await expect(
        governance.connect(voter1).propose(
          proposalId,
          proposalQuestion,
          proposalDescription,
          minimumVotes,
          minimumWeight,
          majorityRequired,
          200, // Invalid 180 days maximum
        ),
      ).to.be.revertedWith("Duration must be at least 30 days and a maximum of 180 days");
    });

    it("Should reject proposals with short questions", async function () {
      await expect(
        governance.connect(voter1).propose(
          proposalId,
          "Short", // Invalid - must be 10 characters+
          proposalDescription,
          minimumVotes,
          minimumWeight,
          majorityRequired,
          durationInDays,
        ),
      ).to.be.revertedWith("Proposal question must be at least 10 characters long");
    });

    it("Should use default values when 0 is passed", async function () {
      await governance.connect(voter1).propose(
        proposalId,
        proposalQuestion,
        proposalDescription,
        minimumVotes,
        minimumWeight,
        0, // Should default to 50
        0, // Should default to 60 days
      );

      const proposal = await governance.proposals(proposalId);
      expect(proposal.majorityRequiredToPass.toNumber()).to.equal(50);
      const currentTime = await ethers.provider.getBlock("latest").then((b) => b.timestamp);
      const expectedDeadline = currentTime + 60 * 24 * 60 * 60;
      expect(proposal.deadline.toNumber()).to.be.closeTo(expectedDeadline, 10);
    });
  });

  describe("Voting", function () {
    beforeEach(async function () {
      await governance
        .connect(voter1)
        .propose(proposalId, proposalQuestion, proposalDescription, minimumVotes, minimumWeight, majorityRequired, durationInDays);
    });

    it("Should allow token holders to vote", async function () {
      await expect(governance.connect(voter1).vote(proposalId, true))
        .to.emit(governance, "VoteCast")
        .withArgs(voter1.address, proposalId, true, ethers.utils.parseEther("1000"));

      expect(await governance.hasVoted(proposalId, voter1.address)).to.be.true;
      expect(await governance.getVoteWeight(proposalId, voter1.address)).to.equal(ethers.utils.parseEther("1000"));
    });

    it("Should reject votes from non-token holders", async function () {
      await expect(governance.connect(nonTokenHolder).vote(proposalId, true)).to.be.revertedWith("Not a governance token holder");
    });

    it("Should reject double voting", async function () {
      await governance.connect(voter1).vote(proposalId, true);

      await expect(governance.connect(voter1).vote(proposalId, false)).to.be.revertedWith("Already voted");
    });

    it("Should properly track vote counts and weights", async function () {
      await governance.connect(voter1).vote(proposalId, true); // 1000 tokens YES
      await governance.connect(voter2).vote(proposalId, false); // 500 tokens NO

      const proposal = await governance.proposals(proposalId);
      expect(proposal.totalVotesYes.toNumber()).to.equal(1);
      expect(proposal.totalVotesNo.toNumber()).to.equal(1);
      expect(proposal.totalVotes.toNumber()).to.equal(2);
      expect(proposal.totalWeightYes).to.equal(ethers.utils.parseEther("1000"));
      expect(proposal.totalWeightNo).to.equal(ethers.utils.parseEther("500"));
      expect(proposal.totalWeight).to.equal(ethers.utils.parseEther("1500"));
    });

    it("Should reject votes on expired proposals", async function () {
      // Fast forward time past the deadline
      await ethers.provider.send("evm_increaseTime", [61 * 24 * 60 * 60]); // 61 days
      await ethers.provider.send("evm_mine");

      await expect(governance.connect(voter1).vote(proposalId, true)).to.be.revertedWith("Proposal voting is active");
    });
  });

  describe("View Functions", function () {
    beforeEach(async function () {
      await governance
        .connect(voter1)
        .propose(proposalId, proposalQuestion, proposalDescription, minimumVotes, minimumWeight, majorityRequired, durationInDays);
      await governance.connect(voter1).vote(proposalId, true);
      await governance.connect(voter2).vote(proposalId, false);
    });

    it("Should return correct proposal status for active proposal", async function () {
      const status = await governance.getProposalStatus(proposalId);
      expect(status).to.equal(0); // ProposalStatus.YES
    });

    it("Should return insufficient interest when minimums not met", async function () {
      // Create proposal with high minimums
      const highMinProposalId = ethers.utils.formatBytes32String("highmin");
      await governance.connect(voter1).propose(
        highMinProposalId,
        proposalQuestion,
        proposalDescription,
        10, // minimumVotes = 10 (too high)
        5000, // minimumWeight = 5000 too high
        majorityRequired,
        durationInDays,
      );

      const status = await governance.getProposalStatus(highMinProposalId);
      expect(status).to.equal(2); // ProposalStatus.InsufficientVotersInterest
    });

    it("Should correctly identify if address has voted", async function () {
      expect(await governance.hasVoted(proposalId, voter1.address)).to.be.true;
      expect(await governance.hasVoted(proposalId, voter3.address)).to.be.false;
    });

    it("Should return correct vote weight for voter", async function () {
      expect(await governance.getVoteWeight(proposalId, voter1.address)).to.equal(ethers.utils.parseEther("1000"));
      expect(await governance.getVoteWeight(proposalId, voter3.address)).to.equal(0);
    });

    it("Should return remaining time correctly", async function () {
      const remainingTime = await governance.getRemainingTime(proposalId);
      const expectedTime = 60 * 24 * 60 * 60; // 60 days
      expect(remainingTime.toNumber()).to.be.closeTo(expectedTime, 100);
    });

    it("Should list active proposals", async function () {
      const activeProposals = await governance.getActiveProposals();
      expect(activeProposals).to.include(proposalId);
      expect(activeProposals.length).to.equal(1);
    });

    it("Should list proposals by creator", async function () {
      const voter1Proposals = await governance.getProposalsByCreator(voter1.address);
      expect(voter1Proposals).to.include(proposalId);
      expect(voter1Proposals.length).to.equal(1);

      const voter2Proposals = await governance.getProposalsByCreator(voter2.address);
      expect(voter2Proposals.length).to.equal(0);
    });
  });

  describe("Proposal Ending", function () {
    beforeEach(async function () {
      await governance
        .connect(voter1)
        .propose(proposalId, proposalQuestion, proposalDescription, minimumVotes, minimumWeight, majorityRequired, durationInDays);
    });

    it("Should reject ending before deadline", async function () {
      await expect(governance.connect(voter1).end(proposalId)).to.be.revertedWith("Proposal voting has ended");
    });

    it("Should emit VoteEnded with YES status for passed proposal", async function () {
      // Vote to pass the proposal
      await governance.connect(voter1).vote(proposalId, true); // 1000 tokens
      await governance.connect(voter2).vote(proposalId, true); // 500 toks
      await governance.connect(voter3).vote(proposalId, false); // 300 toks

      await ethers.provider.send("evm_increaseTime", [61 * 24 * 60 * 60]);
      await ethers.provider.send("evm_mine");

      await expect(governance.connect(voter1).end(proposalId)).to.emit(governance, "VoteEnded").withArgs(
        proposalId,
        2, // totalVotesYes
        ethers.utils.parseEther("1500"), // totalWeightYes
        1, // totalVotesNo
        ethers.utils.parseEther("300"), // totalWeightNo
        0, // ProposalStatus.YES
      );
    });

    it("Should emit VoteEnded with NO status for failed proposal", async function () {
      // Vote to fail the proposal
      await governance.connect(voter1).vote(proposalId, false); // 1000 NO
      await governance.connect(voter2).vote(proposalId, true); // 500 YES

      await ethers.provider.send("evm_increaseTime", [61 * 24 * 60 * 60]);
      await ethers.provider.send("evm_mine");

      await expect(governance.connect(voter1).end(proposalId)).to.emit(governance, "VoteEnded").withArgs(
        proposalId,
        1, // totalVotesYes
        ethers.utils.parseEther("500"), // totalWeightYes
        1, // totalVotesNo
        ethers.utils.parseEther("1000"), // totalWeightNo
        1, // ProposalStatus.NO
      );
    });

    it("Should emit InsufficientVotersInterest when minimums not met", async function () {
      // Only one person votes
      await governance.connect(voter1).vote(proposalId, true);

      await ethers.provider.send("evm_increaseTime", [61 * 24 * 60 * 60]);
      await ethers.provider.send("evm_mine");

      await expect(governance.connect(voter1).end(proposalId)).to.emit(governance, "VoteEnded").withArgs(
        proposalId,
        1, // totalVotesYes
        ethers.utils.parseEther("1000"), // totalWeightYes
        0, // totalVotesNo
        0, // totalWeightNo
        2, // ProposalStatus.InsufficientVotersInterest
      );
    });
  });

  describe("Edge Cases", function () {
    it("Should handle proposals with zero total weight", async function () {
      // Create proposal where no one votes
      await governance.connect(voter1).propose(
        proposalId,
        proposalQuestion,
        proposalDescription,
        0, // minimumVotes = 0
        0, // minimumWeight = 0
        majorityRequired,
        durationInDays,
      );

      const status = await governance.getProposalStatus(proposalId);
      expect(status).to.equal(1); // Should be NO when no votes
    });

    it("Should handle exact percentage matches", async function () {
      // Test with exactly 60% YES votes
      await governance.connect(voter1).propose(
        proposalId,
        proposalQuestion,
        proposalDescription,
        2,
        1000,
        60, // Exactly 60% required
        durationInDays,
      );

      // voter1: 600 tokens YES, voter2: 400 tokens NO = exactly 60% YES
      await mockToken.transfer(voter1.address, ethers.utils.parseEther("100")); // Give voter1 600 total
      await mockToken.transfer(voter2.address, ethers.utils.parseEther("100")); // Give voter2 400 total

      await governance.connect(voter1).vote(proposalId, true);
      await governance.connect(voter2).vote(proposalId, false);

      const status = await governance.getProposalStatus(proposalId);
      expect(status).to.equal(0); // Should be YES (>= 60%)
    });
  });
});