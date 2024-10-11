const { ethers } = require("hardhat");
require('dotenv').config(); 

async function main() {
    const governanceToken = process.env.GOVERNANCE_TOKEN_ADDRESS;
    const timelock = process.env.TIMELOCK_ADDRESS;
    const feeCollector = process.env.FEE_COLLECTOR; // Corrected this line
    const ownerAddress = process.env.OWNER_ADDRESS;
    const gasPrice = process.env.GAS_PRICE;
    const gasLimit = process.env.GAS_LIMIT;
    const multiSigWallet = process.env.MultiSigWallet; // Adding MultiSigWallet

    const NextBlockXGovernance = await ethers.getContractFactory("NextBlockXGovernance");

    const nextBlockXGovernance = await NextBlockXGovernance.deploy(
        governanceToken,
        timelock,
        feeCollector,
        multiSigWallet, // Adding MultiSigWallet to the deployment
        {
            gasPrice: gasPrice,
            gasLimit: gasLimit,
            from: ownerAddress // Specify the sender address for the transaction
        }
    );

    console.log("NextBlockXGovernance deployed to:", nextBlockXGovernance.address);
}

main().catch((error) => {
    console.error(error);
    process.exit(1);
});
