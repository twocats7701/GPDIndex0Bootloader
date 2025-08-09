import { expect } from "chai";
import { ethers } from "hardhat";

describe("PlatypusSwapRoute", function () {
  let tokenA: any;
  let tokenB: any;
  let platypus: any;
  let joe: any;
  let pangolin: any;
  let route: any;
  let owner: any;
  let user: any;

  beforeEach(async function () {
    [owner, user] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("MockERC20");
    tokenA = await Token.deploy("TokenA", "A");
    tokenB = await Token.deploy("TokenB", "B");
    await tokenA.deployed();
    await tokenB.deployed();

    const UniRouter = await ethers.getContractFactory("MockUniswapRouter");
    joe = await UniRouter.deploy(tokenA.address, tokenB.address);
    pangolin = await UniRouter.deploy(tokenA.address, tokenB.address);
    await joe.deployed();
    await pangolin.deployed();

    const PlatRouter = await ethers.getContractFactory("MockPlatypusRouter");
    platypus = await PlatRouter.deploy(tokenA.address, tokenB.address);
    await platypus.deployed();

    const Route = await ethers.getContractFactory("PlatypusSwapRoute");
    route = await Route.deploy(platypus.address, [joe.address, pangolin.address]);
    await route.deployed();

    await platypus.setCoverageRatio(tokenA.address, ethers.utils.parseEther("1"));
    await platypus.setCoverageRatio(tokenB.address, ethers.utils.parseEther("1"));
    await route.setMinCoverageRatio(ethers.utils.parseEther("0.9"));
  });

  it("routes to Platypus when it offers the best quote", async function () {
    await platypus.setQuoteRate(ethers.utils.parseEther("1.05"));
    await platypus.setSwapRate(ethers.utils.parseEther("1.05"));
    await joe.setQuoteRate(ethers.utils.parseEther("1"));
    await joe.setSwapRate(ethers.utils.parseEther("1"));
    await pangolin.setQuoteRate(ethers.utils.parseEther("1.02"));
    await pangolin.setSwapRate(ethers.utils.parseEther("1.02"));

    const amountIn = ethers.utils.parseEther("10");
    await tokenA.mint(user.address, amountIn);
    await tokenA.connect(user).approve(route.address, amountIn);

    await route.connect(user).swap(
      tokenA.address,
      tokenB.address,
      amountIn,
      0,
      user.address
    );

    const expected = amountIn.mul(105).div(100);
    expect(await tokenB.balanceOf(user.address)).to.equal(expected);
    expect(await tokenA.balanceOf(platypus.address)).to.equal(amountIn);
    expect(await tokenA.balanceOf(joe.address)).to.equal(0);
    expect(await tokenA.balanceOf(pangolin.address)).to.equal(0);
  });

  it("selects the best quote among routers", async function () {
    await platypus.setQuoteRate(ethers.utils.parseEther("1.04"));
    await platypus.setSwapRate(ethers.utils.parseEther("1.04"));
    await joe.setQuoteRate(ethers.utils.parseEther("1.03"));
    await joe.setSwapRate(ethers.utils.parseEther("1.03"));
    await pangolin.setQuoteRate(ethers.utils.parseEther("1.06"));
    await pangolin.setSwapRate(ethers.utils.parseEther("1.06"));

    const amountIn = ethers.utils.parseEther("8");
    await tokenA.mint(user.address, amountIn);
    await tokenA.connect(user).approve(route.address, amountIn);

    await route.connect(user).swap(
      tokenA.address,
      tokenB.address,
      amountIn,
      0,
      user.address
    );

    expect(await tokenA.balanceOf(pangolin.address)).to.equal(amountIn);
    expect(await tokenA.balanceOf(joe.address)).to.equal(0);
    expect(await tokenA.balanceOf(platypus.address)).to.equal(0);
  });

  it("falls back to best router when Platypus is disabled", async function () {
    await route.setPlatypusEnabled(false);
    await platypus.setQuoteRate(ethers.utils.parseEther("1.05"));
    await platypus.setSwapRate(ethers.utils.parseEther("1.05"));
    await joe.setQuoteRate(ethers.utils.parseEther("1"));
    await joe.setSwapRate(ethers.utils.parseEther("1"));
    await pangolin.setQuoteRate(ethers.utils.parseEther("1.02"));
    await pangolin.setSwapRate(ethers.utils.parseEther("1.02"));

    const amountIn = ethers.utils.parseEther("5");
    await tokenA.mint(user.address, amountIn);
    await tokenA.connect(user).approve(route.address, amountIn);

    await route.connect(user).swap(
      tokenA.address,
      tokenB.address,
      amountIn,
      0,
      user.address
    );

    expect(await tokenA.balanceOf(pangolin.address)).to.equal(amountIn);
    expect(await tokenA.balanceOf(joe.address)).to.equal(0);
    expect(await tokenA.balanceOf(platypus.address)).to.equal(0);
  });

  it("respects per-trade size cap", async function () {
    await route.setPlatypusTradeCap(ethers.utils.parseEther("2"));
    await platypus.setQuoteRate(ethers.utils.parseEther("1.1"));
    await platypus.setSwapRate(ethers.utils.parseEther("1.1"));
    await joe.setQuoteRate(ethers.utils.parseEther("1"));
    await joe.setSwapRate(ethers.utils.parseEther("1"));
    await pangolin.setQuoteRate(ethers.utils.parseEther("1"));
    await pangolin.setSwapRate(ethers.utils.parseEther("1"));

    const amountIn = ethers.utils.parseEther("3"); // exceeds cap
    await tokenA.mint(user.address, amountIn);
    await tokenA.connect(user).approve(route.address, amountIn);

    await route.connect(user).swap(
      tokenA.address,
      tokenB.address,
      amountIn,
      0,
      user.address
    );

    expect(await tokenA.balanceOf(joe.address)).to.equal(amountIn);
    expect(await tokenA.balanceOf(pangolin.address)).to.equal(0);
    expect(await tokenA.balanceOf(platypus.address)).to.equal(0);
  });

  it("triggers kill switch when coverage drops", async function () {
    await platypus.setCoverageRatio(tokenA.address, ethers.utils.parseEther("0.8"));
    await platypus.setQuoteRate(ethers.utils.parseEther("1.2"));
    await platypus.setSwapRate(ethers.utils.parseEther("1.2"));
    await joe.setQuoteRate(ethers.utils.parseEther("1"));
    await joe.setSwapRate(ethers.utils.parseEther("1"));

    const amountIn = ethers.utils.parseEther("4");
    await tokenA.mint(user.address, amountIn);
    await tokenA.connect(user).approve(route.address, amountIn);

    await expect(
      route.connect(user).swap(
        tokenA.address,
        tokenB.address,
        amountIn,
        0,
        user.address
      )
    ).to.emit(route, "KillSwitchActivated");

    expect(await tokenA.balanceOf(joe.address)).to.equal(amountIn);
    expect(await tokenA.balanceOf(platypus.address)).to.equal(0);
    expect(await route.platypusEnabled()).to.equal(false);
  });
});

