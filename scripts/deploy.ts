// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `yarn exec hardhat run scripts/<script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.

import { ethers } from "hardhat";

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

  // Deploy the swap and claim contract.
  const SwapContract = await ethers.getContractFactory("SwapAndClaim");
  const swapContract = await SwapContract.deploy();
  
  // Wait for contract to deploy.
  await swapContract.deployed();

  // Log swap contract address to the console if successful
  console.log(`Swap contract deployed at ${swapContract.address}`);

  console.log(`Deploy script finished succesfully.`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
