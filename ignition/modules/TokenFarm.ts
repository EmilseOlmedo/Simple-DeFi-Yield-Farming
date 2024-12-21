// This setup uses Hardhat Ignition to manage smart contract deployments.
// Learn more about it at https://hardhat.org/ignition

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const TokenFarm = buildModule("TokenFarm", (m) => {

  const account = m.getAccount(0)
  // Desplegar DAppToken con la dirección del deployer
  const dappToken = m.contract("DAppToken", [account]);

  // Desplegar LPToken con la dirección del deployer
  const lpToken = m.contract("LPToken", [account]);

  // Desplegar TokenFarm usando las direcciones de DAppToken y LPToken
  const tokenFarm = m.contract("TokenFarm", [dappToken, lpToken]);

  return { dappToken, lpToken, tokenFarm };
});

module.exports = TokenFarm;

