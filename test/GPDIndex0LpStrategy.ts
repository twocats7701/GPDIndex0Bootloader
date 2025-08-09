import { expect } from "chai";
import { ethers } from "hardhat";

describe("GPDIndex0LpStrategy", function () {
  let owner: any;
  let vault: any;
  let other: any;
  let strategy: any;
  let lp: any;
  let reward: any;
  let farm: any;
  let router: any;

  beforeEach(async function () {
    [owner, vault, other] = await ethers.getSigners();
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    lp = await MockERC20.deploy("LP", "LP");
    reward = await MockERC20.deploy("RWD", "RWD");
    await lp.deployed();
    await reward.deployed();

    const MockMasterChef = await ethers.getContractFactory("MockMasterChef");
    farm = await MockMasterChef.deploy(lp.address, reward.address);
    await farm.deployed();

    const MockRouter = await ethers.getContractFactory("MockUniswapRouter");
    router = await MockRouter.deploy(reward.address, lp.address);
    await router.deployed();

    const Strategy = await ethers.getContractFactory("GPDIndex0LpStrategy");
    strategy = await Strategy.deploy(lp.address, farm.address, 0, reward.address, router.address);
    await strategy.deployed();

    await strategy.setVault(vault.address);

    await lp.mint(vault.address, ethers.utils.parseEther("100"));
    await reward.mint(farm.address, ethers.utils.parseEther("100"));
  });

  it("allows vault to deposit and withdraw", async function () {
    await lp.connect(vault).approve(strategy.address, ethers.utils.parseEther("100"));
    await strategy
      .connect(vault)
      ["deposit(uint256)"](ethers.utils.parseEther("50"));
    let info = await farm.userInfo(0, strategy.address);
    expect(info.amount).to.equal(ethers.utils.parseEther("50"));

    await strategy
      .connect(vault)
      ["withdraw(uint256)"](ethers.utils.parseEther("20"));
    info = await farm.userInfo(0, strategy.address);
    expect(info.amount).to.equal(ethers.utils.parseEther("30"));
  });

  it("rejects deposit from non-vault", async function () {
    await expect(
      strategy.connect(other)["deposit(uint256)"](1)
    ).to.be.revertedWith("Not authorized");
  });

  it("rejects withdraw from non-vault", async function () {
    await expect(
      strategy.connect(other)["withdraw(uint256)"](1)
    ).to.be.revertedWith("Not authorized");
  });

  it("harvests rewards and sends to vault", async function () {
    await lp.connect(vault).approve(strategy.address, ethers.utils.parseEther("100"));
    await strategy
      .connect(vault)
      ["deposit(uint256)"](ethers.utils.parseEther("100"));

    await farm.setPending(ethers.utils.parseEther("10"));
    await reward.mint(farm.address, ethers.utils.parseEther("10"));

    await strategy.connect(vault).harvest(0);
    expect(await lp.balanceOf(vault.address)).to.be.gt(ethers.utils.parseEther("0"));
  });

  it("computes total assets including pending", async function () {
    await lp.connect(vault).approve(strategy.address, ethers.utils.parseEther("100"));
    await strategy
      .connect(vault)
      ["deposit(uint256)"](ethers.utils.parseEther("100"));
    await farm.setPending(ethers.utils.parseEther("10"));
    const assets = await strategy.totalAssets();
    expect(assets).to.equal(ethers.utils.parseEther("110"));
  });

  it("enforces harvest access", async function () {
    await expect(strategy.connect(other).harvest(0)).to.be.revertedWith("Not authorized");
  });

  it("validates slippage bps bounds", async function () {
    await expect(strategy.setSlippageBps(0)).to.be.revertedWith("bps too low");
    await expect(strategy.setSlippageBps(10_001)).to.be.revertedWith("bps too high");
    await strategy.setSlippageBps(100);
    expect(await strategy.slippageBps()).to.equal(100);
    await expect(strategy.connect(vault).setSlippageBps(200)).to.be.revertedWith("Ownable: caller is not the owner");
  });

  it("updates reward to LP path with validation", async function () {
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const middle = await MockERC20.deploy("MID", "MID");
    await middle.deployed();

    await strategy.setRewardToLpPath([reward.address, middle.address, lp.address]);
    expect(await strategy.rewardToLpPath(0)).to.equal(reward.address);
    expect(await strategy.rewardToLpPath(1)).to.equal(middle.address);
    expect(await strategy.rewardToLpPath(2)).to.equal(lp.address);

    await expect(
      strategy.setRewardToLpPath([middle.address, lp.address])
    ).to.be.revertedWith("Path must start with reward token");
    await expect(
      strategy.setRewardToLpPath([reward.address, middle.address])
    ).to.be.revertedWith("Path must end with LP token");
    await expect(
      strategy.connect(vault).setRewardToLpPath([reward.address, middle.address, lp.address])
    ).to.be.revertedWith("Ownable: caller is not the owner");
  });

  it("auto compounds via vault based on flag", async function () {
    const [owner, user, dev] = await ethers.getSigners();

    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const lpToken = await MockERC20.deploy("LP", "LP");
    const rewardToken = await MockERC20.deploy("RWD", "RWD");

    const MockMasterChef = await ethers.getContractFactory("MockMasterChef");
    const farm2 = await MockMasterChef.deploy(lpToken.address, rewardToken.address);

    const MockRouter = await ethers.getContractFactory("MockUniswapRouter");
    const router2 = await MockRouter.deploy(rewardToken.address, lpToken.address);

    const Strategy = await ethers.getContractFactory("GPDIndex0LpStrategy");
    const strat = await Strategy.deploy(
      lpToken.address,
      farm2.address,
      0,
      rewardToken.address,
      router2.address
    );

    const Vault = await ethers.getContractFactory("GPDYieldVault0");
    const vault2 = await Vault.deploy(
      lpToken.address,
      lpToken.address,
      lpToken.address,
      lpToken.address,
      dev.address,
      "Vault",
      "vLP"
    );

    await strat.setVault(vault2.address);
    await vault2.setStrategy(strat.address);
    await vault2.setFeeExempt(user.address, true);

    const amount = ethers.utils.parseEther("100");
    await lpToken.mint(user.address, amount.mul(3));
    await lpToken.connect(user).approve(vault2.address, amount.mul(3));

    const rewardAmount = ethers.utils.parseEther("20");

    // deposit with auto-compound enabled
    await rewardToken.mint(farm2.address, rewardAmount);
    await farm2.setPending(rewardAmount);
    await vault2.setAutoCompoundEnabled(true);
    const devBeforeDeposit = await lpToken.balanceOf(dev.address);
    await vault2.connect(user).deposit(amount, user.address);
    expect(await lpToken.balanceOf(dev.address)).to.be.gt(devBeforeDeposit);

    // deposit with auto-compound disabled
    await rewardToken.mint(farm2.address, rewardAmount);
    await farm2.setPending(rewardAmount);
    await vault2.setAutoCompoundEnabled(false);
    const devBeforeDeposit2 = await lpToken.balanceOf(dev.address);
    await vault2.connect(user).deposit(amount, user.address);
    expect(await lpToken.balanceOf(dev.address)).to.equal(devBeforeDeposit2);

    // withdraw with auto-compound enabled
    await rewardToken.mint(farm2.address, rewardAmount);
    await farm2.setPending(rewardAmount);
    await vault2.setAutoCompoundEnabled(true);
    const devBeforeWithdraw = await lpToken.balanceOf(dev.address);
    await vault2
      .connect(user)
      .withdraw(ethers.utils.parseEther("50"), user.address, user.address);
    expect(await lpToken.balanceOf(dev.address)).to.be.gt(devBeforeWithdraw);

    // withdraw with auto-compound disabled
    await rewardToken.mint(farm2.address, rewardAmount);
    await farm2.setPending(rewardAmount);
    await vault2.setAutoCompoundEnabled(false);
    const devBeforeWithdraw2 = await lpToken.balanceOf(dev.address);
    await vault2
      .connect(user)
      .withdraw(ethers.utils.parseEther("50"), user.address, user.address);
    expect(await lpToken.balanceOf(dev.address)).to.equal(devBeforeWithdraw2);
  });

  it("allows owner to perform emergency withdraw", async function () {
    const depositAmt = ethers.utils.parseEther("50");
    await lp.connect(vault).approve(strategy.address, depositAmt);
    await strategy.connect(vault)["deposit(uint256)"](depositAmt);

    const lpBefore = await lp.balanceOf(vault.address);

    const rewardAmt = ethers.utils.parseEther("10");
    await farm.setPending(rewardAmt);
    await reward.mint(farm.address, rewardAmt);

    await strategy.emergencyWithdraw();

    const lpAfter = await lp.balanceOf(vault.address);
    expect(lpAfter.sub(lpBefore)).to.equal(depositAmt);
    expect(await reward.balanceOf(vault.address)).to.equal(rewardAmt);
    const info = await farm.userInfo(0, strategy.address);
    expect(info.amount).to.equal(0);
  });
});

