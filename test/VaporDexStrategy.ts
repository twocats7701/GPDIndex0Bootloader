import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract } from "ethers";

describe("VaporDexStrategy", function () {
  let lp: Contract;
  let reward: Contract;
  let farm: Contract;
  let router: Contract;
  let strategy: Contract;
  let owner: any;
  let vault: any;
  let user: any;

  beforeEach(async function () {
    [owner, vault, user] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("MockERC20");
    lp = await Token.deploy("LP", "LP");
    reward = await Token.deploy("RWD", "RWD");
    await lp.deployed();
    await reward.deployed();

    const Farm = await ethers.getContractFactory("MockMasterChef");
    farm = await Farm.deploy(lp.address, reward.address);
    await farm.deployed();

    const Router = await ethers.getContractFactory("MockUniswapRouter");
    router = await Router.deploy(reward.address, lp.address);
    await router.deployed();

    const Strategy = await ethers.getContractFactory("VaporDexStrategy");
    strategy = await Strategy.deploy(
      lp.address,
      farm.address,
      0,
      reward.address,
      router.address
    );
    await strategy.deployed();

    await strategy.setVault(vault.address);

    await lp.mint(vault.address, ethers.utils.parseEther("100"));
    await reward.mint(farm.address, ethers.utils.parseEther("100"));
  });

  it("deposits and withdrawals update farm balances", async function () {
    await lp
      .connect(vault)
      .approve(strategy.address, ethers.utils.parseEther("100"));
    await strategy
      .connect(vault)
      ["deposit(uint256)"](ethers.utils.parseEther("40"));
    let info = await farm.userInfo(0, strategy.address);
    expect(info.amount).to.equal(ethers.utils.parseEther("40"));

    await strategy
      .connect(vault)
      ["withdraw(uint256)"](ethers.utils.parseEther("10"));
    info = await farm.userInfo(0, strategy.address);
    expect(info.amount).to.equal(ethers.utils.parseEther("30"));
  });

  it("harvest swaps rewards and returns expected LP", async function () {
    await lp
      .connect(vault)
      .approve(strategy.address, ethers.utils.parseEther("100"));
    await strategy
      .connect(vault)
      ["deposit(uint256)"](ethers.utils.parseEther("50"));

    const pending = ethers.utils.parseEther("20");
    await farm.setPending(pending);
    await reward.mint(farm.address, pending);

    const vaultBefore = await lp.balanceOf(vault.address);
    const expected = await strategy
      .connect(vault)
      .callStatic.harvest(0);
    const tx = await strategy.connect(vault).harvest(0);
    await tx.wait();
    const vaultAfter = await lp.balanceOf(vault.address);

    expect(expected).to.equal(pending);
    expect(vaultAfter.sub(vaultBefore)).to.equal(pending);
    const info = await farm.userInfo(0, strategy.address);
    expect(info.amount).to.equal(ethers.utils.parseEther("50"));
  });

  it("uses global slippage when no override is supplied", async function () {
    await lp
      .connect(vault)
      .approve(strategy.address, ethers.utils.parseEther("100"));
    await strategy
      .connect(vault)
      ["deposit(uint256)"](ethers.utils.parseEther("50"));

    const rewardAmt = ethers.utils.parseEther("10");
    await farm.setPending(rewardAmt);
    await reward.mint(farm.address, rewardAmt);

    await router.setQuoteRate(ethers.utils.parseEther("1"));
    await router.setSwapRate(ethers.utils.parseEther("0.995"));

    const before = await lp.balanceOf(vault.address);
    await strategy.connect(vault).harvest(0);
    const after = await lp.balanceOf(vault.address);

    expect(after.sub(before)).to.equal(ethers.utils.parseEther("9.95"));
  });

  it("allows per-call slippage override", async function () {
    await lp
      .connect(vault)
      .approve(strategy.address, ethers.utils.parseEther("100"));
    await strategy
      .connect(vault)
      ["deposit(uint256)"](ethers.utils.parseEther("50"));

    const rewardAmt = ethers.utils.parseEther("10");
    await farm.setPending(rewardAmt);
    await reward.mint(farm.address, rewardAmt);

    await router.setQuoteRate(ethers.utils.parseEther("1"));
    await router.setSwapRate(ethers.utils.parseEther("0.9"));

    await expect(
      strategy.connect(vault).harvest(0)
    ).to.be.revertedWith("INSUFFICIENT_OUTPUT_AMOUNT");

    const before = await lp.balanceOf(vault.address);
    await strategy.connect(vault).harvest(1000);
    const after = await lp.balanceOf(vault.address);

    expect(after.sub(before)).to.equal(ethers.utils.parseEther("9"));
  });

  it("enforces slippage bounds", async function () {
    const Token = await ethers.getContractFactory("MockERC20");
    const lp2 = await Token.deploy("LP", "LP");
    const reward2 = await Token.deploy("RWD", "RWD");
    await lp2.deployed();
    await reward2.deployed();

    const Router = await ethers.getContractFactory("MockRouter");
    const badRouter = await Router.deploy();
    await badRouter.deployed();

    const Farm = await ethers.getContractFactory("MockMasterChef");
    const farm2 = await Farm.deploy(lp2.address, reward2.address);
    await farm2.deployed();

    const Strategy = await ethers.getContractFactory("VaporDexStrategy");
    const strat = await Strategy.deploy(
      lp2.address,
      farm2.address,
      0,
      reward2.address,
      badRouter.address
    );
    await strat.deployed();
    await strat.setVault(vault.address);

    const rewardAmt = ethers.utils.parseEther("10");
    await reward2.mint(farm2.address, rewardAmt);
    await farm2.setPending(rewardAmt);

    await badRouter.setQuoteRate(ethers.utils.parseEther("2"));
    await badRouter.setSwapRate(ethers.utils.parseEther("1"));

    await expect(
      strat.connect(vault).harvest(0)
    ).to.be.revertedWith("INSUFFICIENT_OUTPUT_AMOUNT");
  });

  it("allows owner to emergency withdraw", async function () {
    await lp
      .connect(vault)
      .approve(strategy.address, ethers.utils.parseEther("100"));
    const depositAmt = ethers.utils.parseEther("60");
    await strategy
      .connect(vault)
      ["deposit(uint256)"](depositAmt);

    const rewardAmt = ethers.utils.parseEther("15");
    await farm.setPending(rewardAmt);
    await reward.mint(farm.address, rewardAmt);

    await strategy.emergencyWithdraw();

    expect(await lp.balanceOf(vault.address)).to.equal(
      ethers.utils.parseEther("100")
    );
    expect(await reward.balanceOf(vault.address)).to.equal(rewardAmt);
    const info = await farm.userInfo(0, strategy.address);
    expect(info.amount).to.equal(0);
  });
});

