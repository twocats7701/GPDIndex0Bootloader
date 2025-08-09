import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract } from "ethers";

describe("BenqiStrategy slippage", function () {
  let strategy: Contract;

  beforeEach(async function () {
    const [owner] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("MockERC20");
    const underlying = await Token.deploy("Token", "TKN");
    const reward = await Token.deploy("QI", "QI");
    await underlying.deployed();
    await reward.deployed();

    const QiToken = await ethers.getContractFactory("MockQiToken");
    const qiToken = await QiToken.deploy(underlying.address);
    await qiToken.deployed();

    const Controller = await ethers.getContractFactory("MockQiController");
    const controller = await Controller.deploy(reward.address);
    await controller.deployed();

    const Router = await ethers.getContractFactory("MockUniswapRouter");
    const router = await Router.deploy(reward.address, underlying.address);
    await router.deployed();

    const Strategy = await ethers.getContractFactory("BenqiStrategy");
    strategy = await Strategy.deploy(
      underlying.address,
      qiToken.address,
      controller.address,
      router.address,
      [reward.address, underlying.address]
    );
    await strategy.deployed();
  });

  it("validates slippage bps bounds", async function () {
    await expect(strategy.setSlippageBps(0)).to.be.revertedWith("bps too low");
    await expect(strategy.setSlippageBps(10_001)).to.be.revertedWith("bps too high");
    await strategy.setSlippageBps(100);
    expect(await strategy.slippageBps()).to.equal(100);
  });
});
