// End-to-end test: propose -> approve -> claim, using the real Nox JS SDK
// against ConfidentialTreasury deployed on Ethereum Sepolia.

const hre = require("hardhat");
const { createEthersHandleClient } = require("@iexec-nox/handle");

const TREASURY_ADDRESS = process.env.TREASURY_ADDRESS;
const RECIPIENT_ADDRESS = process.env.RECIPIENT_ADDRESS || undefined;

const AMOUNT = 1000n;
const SALT = 424242n;

async function main() {
  if (!TREASURY_ADDRESS) {
    throw new Error("Set TREASURY_ADDRESS in your .env to the deployed ConfidentialTreasury address.");
  }

  const [signer] = await hre.ethers.getSigners();
  const recipient = RECIPIENT_ADDRESS || signer.address;

  console.log("Connecting Nox handle client (Ethereum Sepolia)...");
  const handleClient = await createEthersHandleClient(signer);

  const treasury = await hre.ethers.getContractAt("ConfidentialTreasury", TREASURY_ADDRESS);

  console.log("Encrypting amount and salt off-chain...");
  const amountInput = await handleClient.encryptInput(AMOUNT, "uint256", TREASURY_ADDRESS);
  const saltInput = await handleClient.encryptInput(SALT, "uint256", TREASURY_ADDRESS);

  const commitment = hre.ethers.solidityPackedKeccak256(
    ["uint256", "uint256"],
    [AMOUNT, SALT]
  );

  console.log("Proposing payout...");
  const proposeTx = await treasury.proposePayout(
    recipient,
    amountInput.handle,
    amountInput.handleProof,
    saltInput.handle,
    saltInput.handleProof,
    commitment
  );
  const proposeReceipt = await proposeTx.wait();
  console.log("Proposal created. Tx:", proposeReceipt.hash);

  const proposalId = 1;

  console.log("Approving proposal (quorum = 1, this single approval reaches it)...");
  const approveTx = await treasury.approve(proposalId);
  await approveTx.wait();
  console.log("Approved. Quorum reached, recipient now has decrypt access.");

  console.log("Decrypting amount and salt off-chain (as the recipient)...");
  const proposal = await treasury.proposals(proposalId);
  const decryptedAmount = (await handleClient.decrypt(proposal.amount)).value;
  const decryptedSalt = (await handleClient.decrypt(proposal.salt)).value;
  console.log("Decrypted amount:", decryptedAmount.toString());
  console.log("Decrypted salt:", decryptedSalt.toString());

  console.log("Funding treasury with a small amount so the claim can pay out...");
  const fundTx = await signer.sendTransaction({ to: TREASURY_ADDRESS, value: AMOUNT });
  await fundTx.wait();

  console.log("Claiming payout...");
  const claimTx = await treasury.claim(proposalId, decryptedAmount, decryptedSalt);
  const claimReceipt = await claimTx.wait();
  console.log("Claimed! Tx:", claimReceipt.hash);
  console.log("\nEnd-to-end flow verified: propose -> approve -> decrypt -> claim.");
}

main().catch((error) => {
  console.error("\nTest failed:", error.message || error);
  process.exitCode = 1;
});
