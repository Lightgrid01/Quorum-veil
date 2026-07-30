// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

// Quorum Veil — Confidential Treasury
//
// A small team (N approvers) proposes payouts from a shared treasury.
// While a proposal is pending, the payout AMOUNT is encrypted on-chain —
// nobody watching the mempool or scanning the chain can see how much is
// being proposed, only that *a* proposal exists and to *which* recipient
// (Nox provides confidentiality, not anonymity: addresses stay public).
//
// Once quorum is reached, the recipient is granted decrypt access to the
// amount off-chain via the Nox JS SDK. They then claim their payout by
// submitting the plaintext amount on-chain, which is verified against a
// commitment of the original encrypted value before funds move.
//
// This keeps the sensitive part — deliberation and approval — private,
// while settlement (which necessarily requires a plaintext ETH value to
// actually transfer funds) happens only at the very end.

import {Nox, euint256, externalEuint256} from "@iexec-nox/nox-protocol-contracts/contracts/sdk/Nox.sol";

contract ConfidentialTreasury {
    struct Proposal {
        address recipient;
        euint256 amount;       // encrypted during proposal/approval
        euint256 salt;         // encrypted salt — prevents brute-forcing the commitment
        bytes32 commitment;    // keccak256(amount, salt) — checked at claim time
        uint256 approvals;
        bool executed;
    }

    address[] public approvers;
    uint256 public quorum;
    uint256 public proposalCount;

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasApproved;

    event ProposalCreated(uint256 indexed id, address indexed proposer, address indexed recipient);
    event ProposalApproved(uint256 indexed id, address indexed approver, uint256 approvals);
    event QuorumReached(uint256 indexed id);
    event PayoutClaimed(uint256 indexed id, address indexed recipient, uint256 amount);

    modifier onlyApprover() {
        require(isApprover(msg.sender), "not an approver");
        _;
    }

    constructor(address[] memory _approvers, uint256 _quorum) {
        require(_approvers.length > 0, "need at least one approver");
        require(_quorum > 0 && _quorum <= _approvers.length, "invalid quorum");
        approvers = _approvers;
        quorum = _quorum;
    }

    function isApprover(address account) public view returns (bool) {
        for (uint256 i = 0; i < approvers.length; i++) {
            if (approvers[i] == account) return true;
        }
        return false;
    }

    // Fund the treasury. Plain ETH — the treasury's total balance is public
    // (this is a shared pool, not a hidden balance); what's private is the
    // *proposed payout amount* while it's under deliberation.
    receive() external payable {}

    // Propose a payout. The amount AND a random salt are submitted
    // encrypted: the caller encrypts both off-chain with the Nox JS SDK.
    // The salt prevents anyone from brute-forcing the public commitment
    // against plausible round ETH amounts before quorum is reached.
    function proposePayout(
        address recipient,
        externalEuint256 amountHandle,
        bytes calldata amountProof,
        externalEuint256 saltHandle,
        bytes calldata saltProof,
        bytes32 commitment
    ) external onlyApprover returns (uint256 id) {
        require(recipient != address(0), "invalid recipient");

        euint256 amount = Nox.fromExternal(amountHandle, amountProof);
        euint256 salt = Nox.fromExternal(saltHandle, saltProof);

        id = proposalCount++;
        Proposal storage p = proposals[id];
        p.recipient = recipient;
        p.amount = amount;
        p.salt = salt;
        p.commitment = commitment;

        Nox.allowThis(amount);
        Nox.allow(amount, msg.sender);
        Nox.allowThis(salt);
        Nox.allow(salt, msg.sender);

        emit ProposalCreated(id, msg.sender, recipient);
    }

    // Approve a pending proposal. Once quorum is reached, the recipient is
    // granted decrypt access to the amount so they can read it off-chain
    // and prepare their claim.
    function approve(uint256 id) external onlyApprover {
        Proposal storage p = proposals[id];
        require(p.recipient != address(0), "unknown proposal");
        require(!p.executed, "already executed");
        require(!hasApproved[id][msg.sender], "already approved");

        hasApproved[id][msg.sender] = true;
        p.approvals += 1;

        emit ProposalApproved(id, msg.sender, p.approvals);

        if (p.approvals == quorum) {
            Nox.allow(p.amount, p.recipient);
            Nox.allow(p.salt, p.recipient);
            emit QuorumReached(id);
        }
    }

    // Recipient claims their payout once quorum is reached. They decrypt
    // the amount and salt off-chain (Nox JS SDK `decrypt()`, using the ACL
    // access granted in `approve`) and submit both here in plaintext. The
    // contract checks them against the commitment stored at proposal time
    // before releasing real ETH — this is the point where the amount
    // becomes publicly visible on-chain, which is unavoidable for an
    // actual native-token transfer.
    function claim(uint256 id, uint256 revealedAmount, uint256 revealedSalt) external {
        Proposal storage p = proposals[id];
        require(msg.sender == p.recipient, "not the recipient");
        require(!p.executed, "already executed");
        require(p.approvals >= quorum, "quorum not reached");
        require(
            keccak256(abi.encodePacked(revealedAmount, revealedSalt)) == p.commitment,
            "amount/salt mismatch"
        );
        require(address(this).balance >= revealedAmount, "insufficient treasury balance");

        p.executed = true;

        (bool ok, ) = payable(p.recipient).call{value: revealedAmount}("");
        require(ok, "transfer failed");

        emit PayoutClaimed(id, p.recipient, revealedAmount);
    }
}
