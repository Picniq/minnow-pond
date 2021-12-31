import { expect } from "chai";
import { ethers } from "hardhat";
import { MerkleTree } from "merkletreejs";
import keccak256 from "keccak256";

const TOKEN_ADDR = "0x6fe88a211863d0d818608036880c9a4b0ea86795";

const TOKEN_ABI = [
    {
        constant: true,
        inputs: [
            {
                name: "_owner",
                type: "address",
            },
        ],
        name: "balanceOf",
        outputs: [
            {
                name: "balance",
                type: "uint256",
            },
        ],
        payable: false,
        type: "function",
    },
];

describe("Minnow", async function () {
    it("Should allow deposits and close at 1 ETH", async function () {
        // We get the contract to deploy.
        const MinnowPond = await ethers.getContractFactory("MinnowPond");
        const minnowPond = await MinnowPond.deploy(TOKEN_ADDR);

        // Wait for deploy.
        await minnowPond.deployed();

        // Get sender addresses.
        const senders = await ethers.getSigners();

        // Make three deposits. Since this pushes total amount over 1 ETH (1.2 ETH), the period should close.
        await minnowPond
            .connect(senders[0])
            .functions.makeDeposit({ value: ethers.utils.parseEther("0.4") });
        await minnowPond
            .connect(senders[1])
            .functions.makeDeposit({ value: ethers.utils.parseEther("0.4") });
        await minnowPond
            .connect(senders[2])
            .functions.makeDeposit({ value: ethers.utils.parseEther("0.4") });

        const currentPeriod = await minnowPond.getCurrentPeriod();
        const pastPeriod = await minnowPond.getPastPeriod(1);

        // Test that 1 period was closed and 1 was opened = 2 total
        expect(await minnowPond.getTotalPeriods()).to.equal(2);
        // Test that new period was created and remains open
        expect(currentPeriod[1]).to.equal(0);
        // Test that new period has 0 deposits
        expect(currentPeriod[2]).to.equal("0");
        // Test that past period of index 1 has closed timestamp
        expect(pastPeriod[1]).to.greaterThan(0);
        // Test that past period has deposits in excess of 1 ETH
        expect(
            Number(ethers.utils.formatEther(pastPeriod[2]))
        ).to.greaterThanOrEqual(1);
    });

    it("Should verify proofs from merkle root", async function () {
        // We get the contract to deploy.
        const MinnowPond = await ethers.getContractFactory("MinnowPond");
        const minnowPond = await MinnowPond.deploy(TOKEN_ADDR);

        // Wait for deploy.
        await minnowPond.deployed();

        // Get sender addresses.
        const senders = await ethers.getSigners();

        // Make three deposits. Since this pushes total amount over 1 ETH (1.2 ETH), the period should close.
        await minnowPond
            .connect(senders[0])
            .functions.makeDeposit({ value: ethers.utils.parseEther("0.4") });
        await minnowPond
            .connect(senders[1])
            .functions.makeDeposit({ value: ethers.utils.parseEther("0.4") });
        await minnowPond
            .connect(senders[2])
            .functions.makeDeposit({ value: ethers.utils.parseEther("0.4") });

        // Get list of depositors (returns list of structs, which we parse as tuples).
        const depositors = await minnowPond.functions.getDepositors(1);

        // Parse list of depositors.
        const items = depositors.map((d: any[]) => {
            return d.map((d2) => d2.toString().split(","));
        });

        // We want to encode the list items so we can validate on-chain.
        const elements = items[0].map((item: any[]) => {
            return ethers.utils.solidityKeccak256(
                ["uint", "address"],
                [item[0], item[1]]
            );
        });

        // Pass leaves of merkle tree to create root.
        const merkle = new MerkleTree(elements, keccak256, {
            hashLeaves: false,
            sortPairs: true,
        });
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

        // Send ETH to swap and claim contract so it has enough to facilitate swaps.
        await senders[0].sendTransaction({
            to: swapContract.address,
            value: ethers.utils.parseEther("5"),
        });

        // Get period data. We do this so we know how much ETH was deposited in period.
        const periodData = await minnowPond.functions.getPastPeriod(1);

        // Call makeSwap function on the swap contract. This contract makes the swap and sets the merkle root in one tx.
        const tx = await swapContract.functions.makeSwap(
            TOKEN_ADDR,
            periodData[2],
            0,
            1,
            false,
            root
        );

        // Wait for tx to be mined.
        await tx.wait();

        // Claim tokens for each user. Must provide the correct proof or tx will revert.
        await swapContract.functions.claimTokens(
            TOKEN_ADDR,
            1,
            proof,
            items[0][0][0]
        );
        await swapContract
            .connect(senders[1])
            .claimTokens(TOKEN_ADDR, 1, proof2, items[0][1][0]);

        await swapContract
            .connect(senders[2])
            .claimTokens(TOKEN_ADDR, 1, proof3, items[0][2][0]);

        // Create token contract and get each depositor's balance.
        const token = new ethers.Contract(TOKEN_ADDR, TOKEN_ABI, ethers.provider);
        const balance1 = await token.functions.balanceOf(senders[0].address);
        const balance2 = await token.functions.balanceOf(senders[1].address);
        const balance3 = await token.functions.balanceOf(senders[2].address);

        // Check balances are equal to each other since initial deposit was equal.
        expect(balance1.toString()).to.equal(balance2.toString());
        expect(balance2.toString()).to.equal(balance3.toString());
    });
});
