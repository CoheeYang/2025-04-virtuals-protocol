const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { parseEther } = require("ethers/utils");

describe("POC: Bonding Launch Reentrancy", function () {
  ///bonding params, the values are not important
  const LAUNCH_FEE = 100_000;
  const INIT_SUPPLY = 1_000_000_000;
  const ASSET_RATE = 10_000;
  const MAX_TX = 100;
  const GRADUAL_THRESHOLD = parseEther("85000000");

  const getAccounts = async () => {
    const [deployer, admin, user, fFactory,fRouter,vault,agentFactory] = await ethers.getSigners();
    return { deployer, admin,fFactory,fRouter, user, vault,agentFactory };
  };

  async function deployBondingFixture() {
    const { deployer, admin,fFactory,fRouter, user, vault,agentFactory } = await getAccounts();

 

    // Deploy Bonding
    const bonding = await upgrades.deployProxy(
      await ethers.getContractFactory("Bonding"),
      [
        fFactory.address,
        fRouter.address,
        vault.address,
        LAUNCH_FEE,
        INIT_SUPPLY,
        ASSET_RATE,
        MAX_TX,
        agentFactory.address,
        GRADUAL_THRESHOLD
      ]
    );

  
    return { bonding };
  }

  it("POC: Reentrancy error in launch function", async function () {
    const { bonding } = await loadFixture(deployBondingFixture);
    const { user } = await getAccounts();

    const cores = [1, 2, 3, 4, 5];

    // Try to trigger reentrancy
    await expect(
      bonding.connect(user).launch(
        "launch",
        "$ticker",
        cores,
        "description",
        "image",
        ["urls", "", "", ""],
        parseEther("1")
      )
    ).to.be.revertedWithCustomError(
      bonding,
      "ReentrancyGuardReentrantCall"
    );
  });
});