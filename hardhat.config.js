require('dotenv').config();
require('@nomiclabs/hardhat-ethers');

module.exports = {
  solidity: "0.8.20",
  networks: {
    rinkeby: {
      url: process.env.RINKEBY_URL,  // Infura or Alchemy se URL lo
      accounts: [process.env.PRIVATE_KEY]  // Apna wallet private key yahan use karo
    }
  }
};
