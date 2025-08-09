import { expect } from "chai";
import { ethers } from "hardhat";

const toWei = (value: string) => ethers.utils.parseEther(value);

describe("GPDBoostVault", function () {
  it("stakes assets and distributes boosted rewards", async () => {
    const [deployer, user] = await ethers.getSigners();

    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const twocats = await MockERC20.deploy("TWOCATS", "TWO");
    const gerza = await MockERC20.deploy("GERZA", "GER");
    const reward = await MockERC20.deploy("PUSSY", "PUS");
    const ve = await MockERC20.deploy("veGPINDEX0", "VE");

    const Strategy = await ethers.getContractFactory("MockBoostStrategy");
    const stratTwo = await Strategy.deploy(twocats.address, reward.address);
    const stratGer = await Strategy.deploy(gerza.address, reward.address);

    const Vault = await ethers.getContractFactory("GPDBoostVault");
    const vault = await Vault.deploy(twocats.address, gerza.address, reward.address, ve.address);

    await stratTwo.setVault(vault.address);
    await stratGer.setVault(vault.address);
    await vault.setStrategies(stratTwo.address, stratGer.address);

    await twocats.mint(user.address, toWei("1000"));
    await gerza.mint(user.address, toWei("1000"));

    await twocats.connect(user).approve(vault.address, ethers.constants.MaxUint256);
    await gerza.connect(user).approve(vault.address, ethers.constants.MaxUint256);

    // give vault some ve power
    await ve.mint(vault.address, toWei("300"));

    await vault.connect(user).depositTWOCATS(toWei("100"));
    await vault.connect(user).depositGERZA(toWei("200"));

    // simulate rewards
    await reward.mint(deployer.address, toWei("60"));
    await reward.connect(deployer).approve(stratTwo.address, ethers.constants.MaxUint256);
    await reward.connect(deployer).approve(stratGer.address, ethers.constants.MaxUint256);
    await stratTwo.simulateReward(toWei("30"));
    await stratGer.simulateReward(toWei("30"));

    const before = await reward.balanceOf(user.address);
    await vault.connect(user).claimBoostedRewards();
    const after = await reward.balanceOf(user.address);
    expect(after.sub(before)).to.equal(toWei("60"));

    const stake = await vault.underlyingStake(user.address);
    expect(stake[0]).to.equal(toWei("100"));
    expect(stake[1]).to.equal(toWei("200"));

    const boost = await vault.getBoostPercentage(user.address);
    expect(boost).to.equal(toWei("2")); // 200%
  });

  it("allows DAO to update strategy addresses", async () => {
    const [owner, dao, user] = await ethers.getSigners();

    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const twocats = await MockERC20.deploy("TWOCATS", "TWO");
    const gerza = await MockERC20.deploy("GERZA", "GER");
    const reward = await MockERC20.deploy("PUSSY", "PUS");
    const ve = await MockERC20.deploy("veGPINDEX0", "VE");

    const Strategy = await ethers.getContractFactory("MockBoostStrategy");
    const stratTwo = await Strategy.deploy(twocats.address, reward.address);
    const stratGer = await Strategy.deploy(gerza.address, reward.address);

    const Vault = await ethers.getContractFactory("GPDBoostVault");
    const vault = await Vault.deploy(twocats.address, gerza.address, reward.address, ve.address);

    await stratTwo.setVault(vault.address);
    await stratGer.setVault(vault.address);
    await vault.setStrategies(stratTwo.address, stratGer.address);
    await vault.setDao(dao.address);

    const newStratTwo = await Strategy.deploy(twocats.address, reward.address);
    const newStratGer = await Strategy.deploy(gerza.address, reward.address);
    await newStratTwo.setVault(vault.address);
    await newStratGer.setVault(vault.address);

    await expect(
      vault.connect(user).setStrategies(newStratTwo.address, newStratGer.address)
    ).to.be.revertedWith("Not authorized");

    await vault.connect(dao).setStrategies(newStratTwo.address, newStratGer.address);
    expect(await vault.twocatsStrategy()).to.equal(newStratTwo.address);
    expect(await vault.gerzaStrategy()).to.equal(newStratGer.address);
  });

  it("auto compounds on deposit and withdraw when enabled", async () => {
    const [deployer, user] = await ethers.getSigners();

    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const twocats = await MockERC20.deploy("TWOCATS", "TWO");
    const gerza = await MockERC20.deploy("GERZA", "GER");
    const reward = await MockERC20.deploy("PUSSY", "PUS");
    const ve = await MockERC20.deploy("veGPINDEX0", "VE");

    const Strategy = await ethers.getContractFactory("MockBoostStrategy");
    const stratTwo = await Strategy.deploy(twocats.address, reward.address);

    const Vault = await ethers.getContractFactory("GPDBoostVault");
    const vault = await Vault.deploy(
      twocats.address,
      gerza.address,
      reward.address,
      ve.address
    );

    await stratTwo.setVault(vault.address);
    await vault.setStrategies(stratTwo.address, ethers.constants.AddressZero);

    await twocats.mint(user.address, toWei("1000"));
    await twocats.connect(user).approve(vault.address, ethers.constants.MaxUint256);
    await reward.mint(deployer.address, toWei("100"));
    await reward
      .connect(deployer)
      .approve(stratTwo.address, ethers.constants.MaxUint256);

    // initial deposit to enable withdrawals later
    await vault.connect(user).depositTWOCATS(toWei("100"));

    await stratTwo.simulateReward(toWei("10"));
    await vault.setAutoCompoundEnabled(true);
    const callsBeforeDeposit = await stratTwo.harvestCalls();
    await vault.connect(user).depositTWOCATS(toWei("10"));
    expect(await stratTwo.harvestCalls()).to.equal(callsBeforeDeposit.add(2));

    await stratTwo.simulateReward(toWei("10"));
    await vault.setAutoCompoundEnabled(false);
    const callsBeforeDeposit2 = await stratTwo.harvestCalls();
    await vault.connect(user).depositTWOCATS(toWei("10"));
    expect(await stratTwo.harvestCalls()).to.equal(callsBeforeDeposit2.add(1));

    await stratTwo.simulateReward(toWei("10"));
    await vault.setAutoCompoundEnabled(true);
    const callsBeforeWithdraw = await stratTwo.harvestCalls();
    await vault.connect(user).withdrawTWOCATS(toWei("5"));
    expect(await stratTwo.harvestCalls()).to.equal(callsBeforeWithdraw.add(2));

    await stratTwo.simulateReward(toWei("10"));
    await vault.setAutoCompoundEnabled(false);
    const callsBeforeWithdraw2 = await stratTwo.harvestCalls();
    await vault.connect(user).withdrawTWOCATS(toWei("5"));
    expect(await stratTwo.harvestCalls()).to.equal(callsBeforeWithdraw2.add(1));
  });
});

