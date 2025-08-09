import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract } from "ethers";

describe("BlackholeDexStrategy", function () {
  let token: Contract;
  let pool: Contract;
  let strategy: Contract;
  let vault: Contract;
  let owner: any, user: any, dev: any;

  beforeEach(async function () {
    [owner, user, dev] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("MockERC20");
    token = await Token.deploy("Token", "TKN");
    await token.deployed();
    await token.mint(user.address, ethers.utils.parseEther("1000"));
    await token.mint(owner.address, ethers.utils.parseEther("1000"));

    const Pool = await ethers.getContractFactory("MockBlackholePool");
    pool = await Pool.deploy(token.address);
    await pool.deployed();

    const Strategy = await ethers.getContractFactory("BlackholeDexStrategy");
    strategy = await Strategy.deploy(token.address, pool.address);
    await strategy.deployed();

    const Vault = await ethers.getContractFactory("GPDYieldVault0");
    vault = await Vault.deploy(
      token.address,
      token.address,
      token.address,
      token.address,
      dev.address,
      "Vault",
      "vTKN"
    );
    await vault.deployed();

    const Keeper = await ethers.getContractFactory("MockKeeperSlasher");
    const keeper = await Keeper.deploy();
    await keeper.deployed();
    await vault.setKeeperAddresses(keeper.address, ethers.constants.AddressZero);

    await strategy.setVault(vault.address);
    await vault.setStrategy(strategy.address);
    await vault.setFeeExempt(user.address, true);
  });

  it("deposits and withdraws via vault", async function () {
    const depositAmount = ethers.utils.parseEther("100");
    await token.connect(user).approve(vault.address, depositAmount);
    await vault.connect(user).deposit(depositAmount, user.address);
    expect(await pool.balanceOf(strategy.address)).to.equal(depositAmount);

    await vault.connect(user).withdraw(depositAmount, user.address, user.address);
    expect(await pool.balanceOf(strategy.address)).to.equal(0);
    expect(await token.balanceOf(user.address)).to.equal(ethers.utils.parseEther("1000"));
  });

  it("only owner can update pool", async function () {
    const Pool2 = await ethers.getContractFactory("MockBlackholePool");
    const pool2 = await Pool2.deploy(token.address);
    await pool2.deployed();

    await expect(
      strategy.connect(user).setPool(pool2.address)
    ).to.be.revertedWith("Ownable: caller is not the owner");

    await strategy.setPool(pool2.address);

    const depositAmount = ethers.utils.parseEther("50");
    await token.connect(user).approve(vault.address, depositAmount);
    await vault.connect(user).deposit(depositAmount, user.address);
    expect(await pool2.balanceOf(strategy.address)).to.equal(depositAmount);
  });

  it("harvests rewards and compounds into pool", async function () {
    const depositAmount = ethers.utils.parseEther("100");
    await token.connect(user).approve(vault.address, depositAmount);
    await vault.connect(user).deposit(depositAmount, user.address);

    const rewardAmount = ethers.utils.parseEther("20");
    await token.connect(owner).approve(pool.address, rewardAmount);
    await pool.connect(owner).notifyReward(strategy.address, rewardAmount);

    const devBalanceBefore = await token.balanceOf(dev.address);
    await vault.compound();
    const fee = rewardAmount.mul(500).div(10000);
    expect(await token.balanceOf(dev.address)).to.equal(devBalanceBefore.add(fee));

    const expected = depositAmount.add(rewardAmount.sub(fee));
    expect(await pool.balanceOf(strategy.address)).to.equal(expected);
  });

  it("claims bribes during harvest", async function () {
    const depositAmount = ethers.utils.parseEther("100");
    await token.connect(user).approve(vault.address, depositAmount);
    await vault.connect(user).deposit(depositAmount, user.address);

    const bribeAmount = ethers.utils.parseEther("15");
    const Bribe = await ethers.getContractFactory("MockBribeManager");
    const bribe = await Bribe.deploy();
    await bribe.deployed();

    await strategy.setBribeManager(bribe.address);

    await token.connect(owner).approve(bribe.address, bribeAmount);
    await bribe.depositBribe(token.address, bribeAmount);

    await vault.compound();

    const expected = depositAmount.add(bribeAmount.mul(95).div(100));
    expect(await pool.balanceOf(strategy.address)).to.equal(expected);
  });

  it("reverts when swap output below amountOutMin", async function () {
    const Token = await ethers.getContractFactory("MockERC20");
    const lp = await Token.deploy("LP", "LP");
    await lp.deployed();
    const reward = await Token.deploy("RWD", "RWD");
    await reward.deployed();

    const Router = await ethers.getContractFactory("MockRouter");
    const router = await Router.deploy();
    await router.deployed();

    const Farm = await ethers.getContractFactory("MockMasterChef");
    const farm = await Farm.deploy(lp.address, reward.address);
    await farm.deployed();

    const Strategy = await ethers.getContractFactory("GPDIndex0LpStrategy");
    const strat = await Strategy.deploy(
      lp.address,
      farm.address,
      0,
      reward.address,
      router.address
    );
    await strat.deployed();
    await strat.setVault(owner.address);

    const rewardAmount = ethers.utils.parseEther("10");
    await reward.mint(farm.address, rewardAmount);
    await farm.setPending(rewardAmount);

    await router.setQuoteRate(ethers.utils.parseEther("2"));
    await router.setSwapRate(ethers.utils.parseEther("1"));

    await expect(strat.connect(owner).harvest(0)).to.be.revertedWith(
      "INSUFFICIENT_OUTPUT_AMOUNT"
    );
  });

  it("allows owner to emergency withdraw", async function () {
    const depositAmount = ethers.utils.parseEther("100");
    await token.connect(user).approve(vault.address, depositAmount);
    await vault.connect(user).deposit(depositAmount, user.address);

    const rewardAmount = ethers.utils.parseEther("30");
    await token.connect(owner).approve(pool.address, rewardAmount);
    await pool.connect(owner).notifyReward(strategy.address, rewardAmount);

    await strategy.emergencyWithdraw();

    expect(await pool.balanceOf(strategy.address)).to.equal(0);
    expect(await token.balanceOf(vault.address)).to.equal(
      depositAmount.add(rewardAmount)
    );
  });
});

