import { expect } from "chai";
import { ethers } from "hardhat";

describe("GPDIndex0Bootloader", function () {
  let owner: any;
  let dao: any;
  let other: any;
  let bootloader: any;
  let token: any;
  let oracle: any;

  beforeEach(async function () {
    [owner, dao, other] = await ethers.getSigners();
    const Bootloader = await ethers.getContractFactory("GPDIndex0Bootloader");
    bootloader = await Bootloader.deploy();
    await bootloader.deployed();
    await bootloader.setGovernanceEnabled(true);

    const MockERC20 = await ethers.getContractFactory("MockERC20");
    token = await MockERC20.deploy("Token", "TKN");
    await token.deployed();

    const MockOracle = await ethers.getContractFactory("MockOracle");
    oracle = await MockOracle.deploy(ethers.utils.parseEther("1"));
    await oracle.deployed();

    await bootloader
      .connect(owner)
      .setTokenAddresses(token.address, token.address, token.address, token.address);
    await bootloader.connect(owner).setPriceOracle(token.address, oracle.address);
    await bootloader.connect(owner).setMarketPrice(token.address, ethers.utils.parseEther("1"));
    await bootloader.connect(owner).setExecutionPrice(token.address, ethers.utils.parseEther("1"));
    await bootloader.connect(owner).setRiskParams(1000, 1000); // 10%

    // decentralize governance to dao after initial setup
    await bootloader.beginDecentralization(dao.address, dao.address);
  });

  it("allows governance to set token addresses", async function () {
    await bootloader
      .connect(dao)
      .setTokenAddresses(token.address, token.address, token.address, token.address);
    expect(await bootloader.twocatsToken()).to.equal(token.address);
  });

  it("rejects zero token addresses", async function () {
    await expect(
      bootloader
        .connect(dao)
        .setTokenAddresses(ethers.constants.AddressZero, token.address, token.address, token.address)
    ).to.be.revertedWith("TWOCATS token address cannot be zero");
  });

  it("enforces only governance on emissions", async function () {
    await expect(bootloader.connect(other).setEmissionsPerEpoch(1)).to.be.revertedWith("Not authorized");
    await bootloader.connect(dao).setEmissionsPerEpoch(1);
    expect(await bootloader.emissionsPerEpoch()).to.equal(1);
    await expect(bootloader.connect(dao).setEmissionsPerEpoch(0)).to.be.revertedWith("Emissions must be greater than zero");
  });

  it("withdraws AVAX and tokens", async function () {
    // deposit AVAX and token
    await owner.sendTransaction({ to: bootloader.address, value: ethers.utils.parseEther("1") });
    await token.mint(bootloader.address, ethers.utils.parseEther("5"));

    // withdraw AVAX
    await bootloader.connect(dao).withdrawAVAX(ethers.utils.parseEther("0.5"));
    // withdraw token
    await bootloader.connect(dao).withdrawToken(token.address, ethers.utils.parseEther("5"));

    expect(await ethers.provider.getBalance(bootloader.address)).to.equal(ethers.utils.parseEther("0.5"));
    expect(await token.balanceOf(dao.address)).to.equal(ethers.utils.parseEther("5"));
  });

  it("rejects non-governance withdrawals", async function () {
    await owner.sendTransaction({ to: bootloader.address, value: ethers.utils.parseEther("1") });
    await expect(
      bootloader.connect(other).withdrawAVAX(ethers.utils.parseEther("1"))
    ).to.be.revertedWith("Not authorized");
  });

  it("processes deposits gradually and triggers when target TVL met", async function () {
    await bootloader.connect(dao).setBuyPortionBps(5000);
    await bootloader.connect(dao).setMinLotSize(ethers.utils.parseEther("0.1"));
    await bootloader.connect(dao).setTargetTVL(ethers.utils.parseEther("3"));

    await bootloader.deposit({ value: ethers.utils.parseEther("1") });
    expect(await bootloader.liquidReserve()).to.equal(ethers.utils.parseEther("0.5"));
    expect(await bootloader.investedReserve()).to.equal(ethers.utils.parseEther("0.5"));
    expect(await bootloader.triggered()).to.equal(false);

    await bootloader.deposit({ value: ethers.utils.parseEther("1") });
    expect(await bootloader.liquidReserve()).to.equal(ethers.utils.parseEther("1"));
    expect(await bootloader.investedReserve()).to.equal(ethers.utils.parseEther("1"));
    expect(await bootloader.triggered()).to.equal(false);

    await bootloader.deposit({ value: ethers.utils.parseEther("1") });
    expect(await bootloader.liquidReserve()).to.equal(0);
    expect(await bootloader.investedReserve()).to.equal(ethers.utils.parseEther("3"));
    expect(await bootloader.triggered()).to.equal(true);
  });

  it("reverts when price impact exceeds limit", async function () {
    await bootloader.connect(dao).setBuyPortionBps(10000);
    await bootloader.connect(dao).setMinLotSize(ethers.utils.parseEther("0.1"));
    await bootloader.connect(dao).setRiskParams(100, 1000); // 1% price impact limit
    await bootloader.connect(dao).setMarketPrice(token.address, ethers.utils.parseEther("1.2"));
    await expect(
      bootloader.deposit({ value: ethers.utils.parseEther("1") })
    ).to.be.revertedWith("Price impact too high");
  });

  it("reverts when slippage exceeds limit", async function () {
    await bootloader.connect(dao).setBuyPortionBps(10000);
    await bootloader.connect(dao).setMinLotSize(ethers.utils.parseEther("0.1"));
    await bootloader.connect(dao).setRiskParams(1000, 100); // 1% slippage limit
    await bootloader.connect(dao).setExecutionPrice(token.address, ethers.utils.parseEther("1.2"));
    await expect(
      bootloader.deposit({ value: ethers.utils.parseEther("1") })
    ).to.be.revertedWith("Slippage too high");
  });
});

