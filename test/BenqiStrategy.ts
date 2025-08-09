import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract } from "ethers";

describe("BenqiStrategy", function () {
  let underlying: Contract;
  let reward: Contract;
  let qiToken: Contract;
  let controller: Contract;
  let router: Contract;
  let strategy: Contract;
  let vault: Contract;
  let owner: any, user: any, dev: any;

  beforeEach(async function () {
    [owner, user, dev] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("MockERC20");
    underlying = await Token.deploy("Token", "TKN");
    await underlying.deployed();
    reward = await Token.deploy("QI", "QI");
    await reward.deployed();

    await underlying.mint(user.address, ethers.utils.parseEther("1000"));
    await underlying.mint(owner.address, ethers.utils.parseEther("1000"));

    const QiToken = await ethers.getContractFactory("MockQiToken");
    qiToken = await QiToken.deploy(underlying.address);
    await qiToken.deployed();

    const Controller = await ethers.getContractFactory("MockQiController");
    controller = await Controller.deploy(reward.address);
    await controller.deployed();

    const Router = await ethers.getContractFactory("MockUniswapRouter");
    router = await Router.deploy(reward.address, underlying.address);
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

    const Vault = await ethers.getContractFactory("GPDYieldVault0");
    vault = await Vault.deploy(
      underlying.address,
      underlying.address,
      underlying.address,
      underlying.address,
      dev.address,
      "Vault",
      "vTKN"
    );
    await vault.deployed();

    await strategy.setVault(vault.address);
    await vault.setStrategy(strategy.address);
    await vault.setFeeExempt(user.address, true);

    const Keeper = await ethers.getContractFactory("MockKeeperSlasher");
    const keeper = await Keeper.deploy();
    await vault.setKeeperAddresses(keeper.address, ethers.constants.AddressZero);
  });

  it("deposits and withdraws via vault", async function () {
    const amount = ethers.utils.parseEther("100");
    await underlying.connect(user).approve(vault.address, amount);
    await vault.connect(user).deposit(amount, user.address);

    expect(await qiToken.balanceOf(strategy.address)).to.equal(amount);
    expect(await strategy.totalSupplied()).to.equal(amount);

    await vault.connect(user).withdraw(amount, user.address, user.address);
    expect(await qiToken.balanceOf(strategy.address)).to.equal(0);
    expect(await strategy.totalSupplied()).to.equal(0);
    expect(await underlying.balanceOf(user.address)).to.equal(
      ethers.utils.parseEther("1000")
    );
  });

  it("harvests rewards and compounds into qi token", async function () {
    const amount = ethers.utils.parseEther("100");
    await underlying.connect(user).approve(vault.address, amount);
    await vault.connect(user).deposit(amount, user.address);

    const rewardAmount = ethers.utils.parseEther("20");
    await reward.mint(controller.address, rewardAmount);
    await controller.setReward(rewardAmount);

    const devBefore = await underlying.balanceOf(dev.address);
    await vault.compound();

    const fee = rewardAmount.mul(500).div(10000);
    expect(await underlying.balanceOf(dev.address)).to.equal(devBefore.add(fee));

    const expected = amount.add(rewardAmount.sub(fee));
    expect(await qiToken.balanceOf(strategy.address)).to.equal(expected);
    expect(await strategy.totalSupplied()).to.equal(expected);
    expect(await reward.balanceOf(strategy.address)).to.equal(0);
  });

  it("withdraws compounded rewards for user", async function () {
    const amount = ethers.utils.parseEther("100");
    await underlying.connect(user).approve(vault.address, amount);
    await vault.connect(user).deposit(amount, user.address);

    const rewardAmount = ethers.utils.parseEther("20");
    await reward.mint(controller.address, rewardAmount);
    await controller.setReward(rewardAmount);

    await vault.compound();

    const shares = await vault.balanceOf(user.address);
    await vault.connect(user).redeem(shares, user.address, user.address);

    const fee = rewardAmount.mul(500).div(10000);
    const expectedBalance = ethers.utils
      .parseEther("1000")
      .add(rewardAmount.sub(fee));

    expect(await underlying.balanceOf(user.address)).to.be.closeTo(
      expectedBalance,
      1
    );
    expect(await qiToken.balanceOf(strategy.address)).to.be.lte(1);
    expect(await strategy.totalSupplied()).to.be.lte(1);
  });

  it("auto compounds on deposit and withdraw when enabled", async function () {
    const amount = ethers.utils.parseEther("100");
    await underlying.connect(user).approve(vault.address, amount.mul(3));

    // deposit with auto-compound enabled
    const rewardAmount = ethers.utils.parseEther("20");
    await reward.mint(controller.address, rewardAmount);
    await controller.setReward(rewardAmount);
    await vault.setAutoCompoundEnabled(true);
    const devBeforeDeposit = await underlying.balanceOf(dev.address);
    await vault.connect(user).deposit(amount, user.address);
    expect(await underlying.balanceOf(dev.address)).to.be.gt(devBeforeDeposit);

    // withdraw with auto-compound enabled
    await reward.mint(controller.address, rewardAmount);
    await controller.setReward(rewardAmount);
    const devBeforeWithdraw = await underlying.balanceOf(dev.address);
    await vault
      .connect(user)
      .withdraw(ethers.utils.parseEther("50"), user.address, user.address);
    expect(await underlying.balanceOf(dev.address)).to.be.gt(devBeforeWithdraw);

    // deposit with auto-compound disabled
    await reward.mint(controller.address, rewardAmount);
    await controller.setReward(rewardAmount);
    await vault.setAutoCompoundEnabled(false);
    const devBeforeDisabled = await underlying.balanceOf(dev.address);
    await vault.connect(user).deposit(amount, user.address);
    expect(await underlying.balanceOf(dev.address)).to.equal(devBeforeDisabled);

    // withdraw with auto-compound disabled
    await reward.mint(controller.address, rewardAmount);
    await controller.setReward(rewardAmount);
    const devBeforeDisabledWithdraw = await underlying.balanceOf(dev.address);
    await vault
      .connect(user)
      .withdraw(ethers.utils.parseEther("50"), user.address, user.address);
    expect(await underlying.balanceOf(dev.address)).to.equal(
      devBeforeDisabledWithdraw
    );
  });

  it("allows owner to emergency withdraw all funds", async function () {
    const amount = ethers.utils.parseEther("100");
    await underlying.connect(user).approve(vault.address, amount);
    await vault.connect(user).deposit(amount, user.address);

    const rewardAmount = ethers.utils.parseEther("10");
    await reward.mint(strategy.address, rewardAmount);

    await strategy.emergencyWithdraw();

    expect(await qiToken.balanceOf(strategy.address)).to.equal(0);
    expect(await strategy.totalSupplied()).to.equal(0);
    expect(await underlying.balanceOf(vault.address)).to.equal(amount);
    expect(await reward.balanceOf(vault.address)).to.equal(rewardAmount);
  });
});

