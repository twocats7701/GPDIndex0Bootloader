import { expect } from "chai";
import { ethers } from "hardhat";

// Tests rebalancing between two strategies and share accounting

describe("Rebalancer", function () {
  it("moves funds to higher APR strategy and keeps shares", async function () {
    const [owner, user] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("MockERC20");
    const asset = await Token.deploy("Asset", "AST");
    const twocats = await Token.deploy("TWOCATS", "TWO");
    const gerza = await Token.deploy("GERZA", "GER");
    const pussy = await Token.deploy("PUSSY", "PUS");

    const Vault = await ethers.getContractFactory("GPDYieldVault0");
    const vault = await Vault.deploy(
      asset.address,
      twocats.address,
      gerza.address,
      pussy.address,
      owner.address,
      "Vault",
      "VLT"
    );

    const Strat = await ethers.getContractFactory("SimpleStakingStrategy");
    const strat1 = await Strat.deploy(asset.address);
    const strat2 = await Strat.deploy(asset.address);

    await strat1.setVault(vault.address);
    await strat2.setVault(vault.address);

    await vault.setStrategy(strat1.address);
    await vault.setFeeExempt(user.address, true);

    const amount = ethers.utils.parseEther("100");
    await asset.mint(user.address, amount);
    await asset.connect(user).approve(vault.address, amount);

    await vault.connect(user).deposit(amount, user.address);

    const Rebalancer = await ethers.getContractFactory("Rebalancer");
    const rebalancer = await Rebalancer.deploy();

    await vault.rebalance(
      rebalancer.address,
      strat1.address,
      strat2.address,
      amount,
      500,
      1000
    );

    expect(await strat1.totalStaked()).to.equal(0);
    expect(await strat2.totalStaked()).to.equal(amount);
    expect(await vault.totalAssets()).to.equal(amount);
    expect(await vault.balanceOf(user.address)).to.equal(amount);

    await vault.connect(user).withdraw(amount, user.address, user.address);
    expect(await asset.balanceOf(user.address)).to.equal(amount);
    expect(await vault.balanceOf(user.address)).to.equal(0);
  });
});
