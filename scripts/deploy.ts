// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `yarn exec hardhat run scripts/<script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.

import { ethers } from "hardhat";
import { MerkleTree } from "merkletreejs";
import keccak256 from "keccak256";

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // QFI token address we use for testing.
  const tokenAddr = "0x6fe88a211863d0d818608036880c9a4b0ea86795";

  // We get the contract to deploy.
  const MinnowPond = await ethers.getContractFactory("MinnowPond");
  const minnowPond = await MinnowPond.deploy(tokenAddr);

  // Wait for deploy.
  await minnowPond.deployed();

  // Log the pond contract address to the console if successful
  console.log(`Pond contract deployed at ${minnowPond.address}`);

  // Get sender addresses.
  const senders = await ethers.getSigners();

  // Make three deposits. Since this pushes total amount over 1 ETH (1.2 ETH), the period should close.
  await minnowPond.connect(senders[0]).functions.makeDeposit({ value: ethers.utils.parseEther("0.4") });
  await minnowPond.connect(senders[1]).functions.makeDeposit({ value: ethers.utils.parseEther("0.4") });
  await minnowPond.connect(senders[2]).functions.makeDeposit({ value: ethers.utils.parseEther("0.4") });

  // Get list of depositors (returns list of structs, which we parse as tuples).
  const depositors = await minnowPond.functions.getDepositors(1);

  // Parse list of depositors.
  const items = depositors.map((d: any[]) => {
    return d.map(d2 => d2.toString().split(','));
  });

  // We want to encode the list items so we can validate on-chain.
  const elements = items[0].map((item: any[]) => {
    return ethers.utils.solidityKeccak256(['uint', 'address'], [item[0], item[1]]);
  });

  // Pass leaves of merkle tree to create root.
  const merkle = new MerkleTree(elements, keccak256, { hashLeaves: false, sortPairs: true });
  const root = merkle.getHexRoot();

  // Get proofs for each of the deposits to send in claim transaction.
  const proof = merkle.getHexProof(merkle.getHexLeaves()[0]);
  const proof2 = merkle.getHexProof(merkle.getHexLeaves()[1]);
  const proof3 = merkle.getHexProof(merkle.getHexLeaves()[2]);

  // Deploy the swap and claim contract.
  const SwapContract = await ethers.getContractFactory("SwapAndClaim");
  const swapContract = await SwapContract.deploy();
  
  // Wait for contract to deploy.
  await swapContract.deployed();

  // Log swap contract address to the console if successful
  console.log(`Swap contract deployed at ${swapContract.address}`);

  // Send ETH to swap and claim contract so it has enough to facilitate swaps.
  await senders[0].sendTransaction({to: swapContract.address, value: ethers.utils.parseEther("5") });

  // Get period data. We do this so we know how much ETH was deposited in period.
  const periodData = await minnowPond.functions.getPastPeriod(1);

  // Call makeSwap function on the swap contract. This contract makes the swap and sets the merkle root in one tx.
  const tx = await swapContract.functions.makeSwap(
    tokenAddr,
    periodData[2],
    0,
    1,
    false,
    root
  );

  // Wait for tx to be mined.
  await tx.wait();

  // Claim tokens for each user. Must provide the correct proof or tx will revert.
  await swapContract.functions.claimTokens(tokenAddr, 1, proof, items[0][0][0]);
  await swapContract.connect(senders[1]).claimTokens(tokenAddr, 1, proof2, items[0][1][0]);
  await swapContract.connect(senders[2]).claimTokens(tokenAddr, 1, proof3, items[0][2][0]);

  console.log(`Deploy script finished succesfully.`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
