// Deploy script for ConfidentialTreasury.
//
// For the fastest first test: leave APPROVERS unset in .env and it will
// default to just your own deployer wallet with quorum = 1. Once that
// works end-to-end, add real approver addresses and raise the quorum for
// your actual demo (a quorum of 1 doesn't demonstrate the multi-approver
// privacy flow — you want at least 2-of-3 for the video).

const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  const approversEnv = process.env.APPROVERS; // comma-separated addresses, optional
  const quorumEnv = process.env.QUORUM;        // optional

  const approvers = approversEnv
    ? approversEnv.split(",").map((a) => a.trim())
    : [deployer.address];

  const quorum = quorumEnv ? parseInt(quorumEnv, 10) : 1;

  console.log("Deploying ConfidentialTreasury with:");
  console.log("  Approvers:", approvers);
  console.log("  Quorum:", quorum);

  const Treasury = await hre.ethers.getContractFactory("ConfidentialTreasury");
  const treasury = await Treasury.deploy(approvers, quorum);
  await treasury.waitForDeployment();

  const address = await treasury.getAddress();
  console.log("\nConfidentialTreasury deployed to:", address);
  console.log("Save this address — you'll need it for the frontend and for testing propose/approve/claim.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
