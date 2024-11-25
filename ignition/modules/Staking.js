const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("StakingModule", (m) => {
  const currentTime = Math.floor(Date.now() / 1000);
  const staking = m.contract("Staking", [
    currentTime,
    process.env.TOKEN_ADDRESS,
  ]);
  return { staking };
});
