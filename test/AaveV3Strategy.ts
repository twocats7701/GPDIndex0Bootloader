import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract } from "ethers";

describe("AaveV3Strategy", function () {
  let underlying: Contract;
  let reward: Contract;
  let pool: Contract;
  let rewards: Contract;
  let router: Contract;
  let executor: Contract;
  let strategy: Contract;
  let vault: Contract;
  let owner: any, user: any, dev: any;

  beforeEach(async function () {
    [owner, user, dev] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("MockERC20");
    underlying = await Token.deploy("Token", "TKN");
    await underlying.deployed();
    reward = await Token.deploy("RWD", "RWD");
    await reward.deployed();

    await underlying.mint(user.address, ethers.utils.parseEther("1000"));
    await underlying.mint(owner.address, ethers.utils.parseEther("1000"));

    const Pool = await ethers.getContractFactory("MockAaveV3Pool");
    pool = await Pool.deploy(underlying.address);
    await pool.deployed();

    const Rewards = await ethers.getContractFactory("MockRewardsController");
    rewards = await Rewards.deploy(reward.address);
    await rewards.deployed();

    const Router = await ethers.getContractFactory("MockUniswapRouter");
    router = await Router.deploy(reward.address, underlying.address);
    await router.deployed();

    const Executor = await ethers.getContractFactory("FlashLoanExecutor");
    executor = await Executor.deploy();
    await executor.deployed();

    const Strategy = await ethers.getContractFactory("AaveV3Strategy");
    strategy = await Strategy.deploy(
      underlying.address,
      pool.address,
      rewards.address,
      router.address,
      [reward.address, underlying.address],
      executor.address
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

    expect(await pool.balance(strategy.address)).to.equal(amount);
    expect(await strategy.totalSupplied()).to.equal(amount);

    await vault.connect(user).withdraw(amount, user.address, user.address);
    expect(await pool.balance(strategy.address)).to.equal(0);
    expect(await strategy.totalSupplied()).to.equal(0);
    expect(await underlying.balanceOf(user.address)).to.equal(
      ethers.utils.parseEther("1000")
    );
  });

  it("harvests rewards and swaps to underlying", async function () {
    const amount = ethers.utils.parseEther("100");
    await underlying.connect(user).approve(vault.address, amount);
    await vault.connect(user).deposit(amount, user.address);

    const rewardAmount = ethers.utils.parseEther("20");
    await reward.mint(rewards.address, rewardAmount);

    const devBefore = await underlying.balanceOf(dev.address);
    await vault.compound();

    const fee = rewardAmount.mul(500).div(10000);
    expect(await underlying.balanceOf(dev.address)).to.equal(devBefore.add(fee));

    const expected = amount.add(rewardAmount.sub(fee));
    expect(await pool.balance(strategy.address)).to.equal(expected);
    expect(await strategy.totalSupplied()).to.equal(expected);
    expect(await reward.balanceOf(strategy.address)).to.equal(0);
  });

  describe("flash loan leverage", function () {
    const depositAmt = ethers.utils.parseEther("100");
    beforeEach(async function () {
      await underlying.connect(user).approve(vault.address, depositAmt);
      await vault.connect(user).deposit(depositAmt, user.address);
      await strategy.setVault(owner.address);
    });

    it("executes leverage loop", async function () {
      const flashAmt = ethers.utils.parseEther("50");
      await strategy.connect(owner).leverage(flashAmt);

      const premium = flashAmt.mul(9).div(10000);
      expect(await pool.balance(strategy.address)).to.equal(depositAmt.add(flashAmt));
      expect(await strategy.totalSupplied()).to.equal(depositAmt.add(flashAmt));
      expect(await pool.debt(strategy.address)).to.equal(flashAmt.add(premium));
    });

    it("reverts on executor failure", async function () {
      await executor.setShouldFail(true);
      const flashAmt = ethers.utils.parseEther("50");
      await expect(
        strategy.connect(owner).leverage(flashAmt)
      ).to.be.revertedWith("exec fail");

      expect(await pool.balance(strategy.address)).to.equal(depositAmt);
      expect(await strategy.totalSupplied()).to.equal(depositAmt);
    });
  });
});

