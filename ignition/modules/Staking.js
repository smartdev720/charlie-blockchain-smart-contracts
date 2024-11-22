const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("StakingModule", (m) => {
  const currentTime = Math.floor(Date.now() / 1000);
  // const tokenAddress = "0xBde71bB4593C4964dad1A685CbE9Cf6a2cDBDca7";
  const staking = m.contract("Staking", [
    currentTime,
    process.env.TOKEN_ADDRESS,
  ]);
  return { staking };
});
