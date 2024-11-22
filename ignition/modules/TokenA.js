const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("TokenAModule", (m) => {
  const tokenA = m.contract("TokenA", [], { force: true });
  return { tokenA };
});
