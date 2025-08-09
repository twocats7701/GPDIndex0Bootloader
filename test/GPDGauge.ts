import { expect } from "chai";
import { ethers } from "hardhat";

describe("GPDGauge", function () {
  let owner: any;
  let user: any;
  let other: any;
  let gauge: any;
  let staking: any;
  let reward: any;
  let ve: any;
  let pool: any;

  beforeEach(async function () {
    [owner, user, other] = await ethers.getSigners();
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    staking = await MockERC20.deploy("STK", "STK");
    reward = await MockERC20.deploy("RWD", "RWD");
    ve = await MockERC20.deploy("VE", "VE");
    await staking.deployed();
    await reward.deployed();
    await ve.deployed();

    const MockPool = await ethers.getContractFactory("MockBlackholePool");
    pool = await MockPool.deploy(staking.address);
    await pool.deployed();

    const Gauge = await ethers.getContractFactory("GPDGauge");
    gauge = await Gauge.deploy(staking.address, reward.address, ve.address, pool.address);
    await gauge.deployed();

    await gauge.setRewardDistributor(owner.address);

    await staking.mint(user.address, ethers.utils.parseEther("100"));
    await reward.mint(owner.address, ethers.utils.parseEther("100"));
    await ve.mint(user.address, ethers.utils.parseEther("100"));
  });

  it("handles deposit and withdraw", async function () {
    await staking.connect(user).approve(gauge.address, ethers.utils.parseEther("100"));
    await gauge.connect(user).deposit(ethers.utils.parseEther("50"));
    expect(await gauge.balanceOf(user.address)).to.equal(ethers.utils.parseEther("50"));

    await gauge.connect(user).withdraw(ethers.utils.parseEther("20"));
    expect(await gauge.balanceOf(user.address)).to.equal(ethers.utils.parseEther("30"));
  });

  it("prevents zero deposits", async function () {
    await expect(gauge.connect(user).deposit(0)).to.be.revertedWith("Cannot deposit 0");
  });

  it("reverts withdrawing more than balance", async function () {
    await staking.connect(user).approve(gauge.address, ethers.utils.parseEther("10"));
    await gauge.connect(user).deposit(ethers.utils.parseEther("10"));
    await expect(
      gauge.connect(user).withdraw(ethers.utils.parseEther("11"))
    ).to.be.reverted;
  });

  it("distributes rewards", async function () {
    await staking.connect(user).approve(gauge.address, ethers.utils.parseEther("100"));
    await gauge.connect(user).deposit(ethers.utils.parseEther("100"));

    await reward.connect(owner).approve(gauge.address, ethers.utils.parseEther("70"));
    await gauge.notifyRewardAmount(ethers.utils.parseEther("70"));

    await ethers.provider.send("evm_increaseTime", [7 * 24 * 60 * 60]);
    await ethers.provider.send("evm_mine", []);

    const earned = await gauge.connect(user).callStatic.claim();
    expect(earned).to.be.closeTo(ethers.utils.parseEther("70"), ethers.utils.parseEther("0.0001"));
  });

  it("enforces reward distributor access", async function () {
    await reward.connect(owner).approve(gauge.address, ethers.utils.parseEther("10"));
    await expect(
      gauge.connect(other).notifyRewardAmount(ethers.utils.parseEther("10"))
    ).to.be.revertedWith("Not authorized");
  });

  it("updates boosted balances after voting", async function () {
    await staking.connect(user).approve(gauge.address, ethers.utils.parseEther("100"));
    await gauge.connect(user).deposit(ethers.utils.parseEther("100"));
    await gauge.connect(user).vote();
    expect(await gauge.boostedBalanceOf(user.address)).to.equal(ethers.utils.parseEther("200"));
  });

  it("distributes bribes with rewards", async function () {
    const bribeTokenFactory = await ethers.getContractFactory("MockERC20");
    const bribe = await bribeTokenFactory.deploy("BRB", "BRB");
    await bribe.deployed();

    await staking.connect(user).approve(gauge.address, ethers.utils.parseEther("100"));
    await gauge.connect(user).deposit(ethers.utils.parseEther("100"));

    await reward.connect(owner).approve(gauge.address, ethers.utils.parseEther("10"));
    await gauge.notifyRewardAmount(ethers.utils.parseEther("10"));

    await bribe.mint(owner.address, ethers.utils.parseEther("30"));
    await bribe.connect(owner).approve(gauge.address, ethers.utils.parseEther("30"));
    await gauge.notifyBribe(bribe.address, ethers.utils.parseEther("30"));

    await ethers.provider.send("evm_increaseTime", [7 * 24 * 60 * 60]);
    await ethers.provider.send("evm_mine", []);

    await gauge.connect(user).claim();
    expect(await bribe.balanceOf(user.address)).to.be.closeTo(
      ethers.utils.parseEther("30"),
      ethers.utils.parseEther("0.0001")
    );
  });
});

