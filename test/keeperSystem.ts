import { expect } from "chai";
import { ethers } from "hardhat";

const { parseEther } = ethers.utils;

async function increaseTime(seconds: number) {
  await ethers.provider.send("evm_increaseTime", [seconds]);
  await ethers.provider.send("evm_mine", []);
}

describe("Keeper system", function () {
  it("registers keepers, enforces bans and cooldown", async function () {
    const [owner, keeper] = await ethers.getSigners();
    const Token = await ethers.getContractFactory("MockERC20");
    const tipToken = await Token.deploy("Tip", "TIP");
    await tipToken.deployed();

    const KeeperSlasher = await ethers.getContractFactory("KeeperSlasher");
    const slasher = await KeeperSlasher.deploy();
    await slasher.deployed();
    await slasher.registerKeeper(keeper.address);

    const TipVault = await ethers.getContractFactory("TipVault");
    const tipVault = await TipVault.deploy(tipToken.address, parseEther("1"), 3600, slasher.address);
    await tipVault.deployed();

    await tipToken.mint(owner.address, parseEther("10"));
    await tipToken.approve(tipVault.address, parseEther("10"));
    await tipVault.fundTips(parseEther("10"));

    await tipVault.connect(keeper).claimTip();
    expect(await tipToken.balanceOf(keeper.address)).to.equal(parseEther("1"));
    await expect(tipVault.connect(keeper).claimTip()).to.be.revertedWith("Cooldown active");
    await increaseTime(3600);
    await tipVault.connect(keeper).claimTip();
    expect(await tipToken.balanceOf(keeper.address)).to.equal(parseEther("2"));

    await slasher.banKeeper(keeper.address);
    await increaseTime(3600);
    await expect(tipVault.connect(keeper).claimTip()).to.be.revertedWith("Not allowed");
  });

  it("escrows rewards and allows claim", async function () {
    const [owner, user] = await ethers.getSigners();
    const Token = await ethers.getContractFactory("MockERC20");
    const reward = await Token.deploy("Reward", "RWD");
    await reward.deployed();

    const RewardEscrow = await ethers.getContractFactory("RewardEscrow");
    const escrow = await RewardEscrow.deploy(reward.address);
    await escrow.deployed();

    await reward.mint(owner.address, parseEther("5"));
    await reward.approve(escrow.address, parseEther("5"));
    await escrow.deposit(user.address, parseEther("5"), 1000);
    expect(await escrow.totalEscrowed(user.address)).to.equal(parseEther("5"));
    await increaseTime(1000);
    await escrow.connect(user).claim();
    expect(await reward.balanceOf(user.address)).to.equal(parseEther("5"));
  });

  it("DAO treasury funds tip vault and reward escrow", async function () {
    const [dao, operator] = await ethers.getSigners();
    const Token = await ethers.getContractFactory("MockERC20");
    const token = await Token.deploy("Token", "TOK");
    await token.deployed();

    const DAOTreasury = await ethers.getContractFactory("DAOTreasury");
    const treasury = await DAOTreasury.deploy(dao.address);
    await treasury.deployed();
    await treasury.connect(dao).setOperator(operator.address, true);

    const KeeperSlasher = await ethers.getContractFactory("KeeperSlasher");
    const slasher = await KeeperSlasher.deploy();
    await slasher.deployed();

    const TipVault = await ethers.getContractFactory("TipVault");
    const tipVault = await TipVault.deploy(token.address, parseEther("1"), 0, slasher.address);
    await tipVault.deployed();

    const RewardEscrow = await ethers.getContractFactory("RewardEscrow");
    const escrow = await RewardEscrow.deploy(token.address);
    await escrow.deployed();

    await token.mint(treasury.address, parseEther("5"));
    await treasury.connect(operator).fundTipVault(token.address, tipVault.address, parseEther("3"));
    await treasury.connect(operator).fundRewardEscrow(token.address, escrow.address, parseEther("2"));

    expect(await token.balanceOf(tipVault.address)).to.equal(parseEther("3"));
    expect(await token.balanceOf(escrow.address)).to.equal(parseEther("2"));
  });

  it("keepers trigger compound and harvest", async function () {
    const [owner, keeper] = await ethers.getSigners();
    const Token = await ethers.getContractFactory("MockERC20");
    const asset = await Token.deploy("Asset", "AST");
    const twocats = await Token.deploy("Two", "TWO");
    const gerza = await Token.deploy("Gerza", "GER");
    const ve = await Token.deploy("VE", "VE");
    const reward = asset;
    await asset.deployed();
    await twocats.deployed();
    await gerza.deployed();
    await reward.deployed();
    await ve.deployed();

    const KeeperSlasher = await ethers.getContractFactory("KeeperSlasher");
    const slasher = await KeeperSlasher.deploy();
    await slasher.registerKeeper(keeper.address);

    const TipVault = await ethers.getContractFactory("TipVault");
    const tipVault = await TipVault.deploy(reward.address, parseEther("1"), 0, slasher.address);
    await tipVault.deployed();
    await reward.mint(owner.address, parseEther("80"));
    await reward.approve(tipVault.address, parseEther("20"));
    await tipVault.fundTips(parseEther("20"));

    // ---- GPDYieldVault0 ----
    const MockBoostStrategy = await ethers.getContractFactory("MockBoostStrategy");
    const strategy1 = await MockBoostStrategy.deploy(asset.address, reward.address);
    await strategy1.deployed();

    const GPDYieldVault0 = await ethers.getContractFactory("GPDYieldVault0");
    const vault = await GPDYieldVault0.deploy(asset.address, twocats.address, gerza.address, asset.address, owner.address, "Vault", "vAST");
    await vault.deployed();
    await strategy1.setVault(vault.address);
    await vault.setStrategy(strategy1.address);
    await vault.setKeeperAddresses(slasher.address, tipVault.address);

    await asset.mint(owner.address, parseEther("10"));
    await asset.approve(vault.address, parseEther("10"));
    await vault.deposit(parseEther("10"), owner.address);

    await reward.approve(strategy1.address, parseEther("5"));
    await strategy1.simulateReward(parseEther("5"));

    await vault.connect(keeper).compound();
    expect(await reward.balanceOf(keeper.address)).to.equal(parseEther("1"));

    // ---- GPDBoostVault ----
    const strategyTwocats = await MockBoostStrategy.deploy(twocats.address, reward.address);
    const strategyGerza = await MockBoostStrategy.deploy(gerza.address, reward.address);
    await strategyTwocats.deployed();
    await strategyGerza.deployed();

    const GPDBoostVault = await ethers.getContractFactory("GPDBoostVault");
    const boostVault = await GPDBoostVault.deploy(twocats.address, gerza.address, reward.address, ve.address);
    await boostVault.deployed();
    await strategyTwocats.setVault(boostVault.address);
    await strategyGerza.setVault(boostVault.address);
    await boostVault.setStrategies(strategyTwocats.address, strategyGerza.address);
    await boostVault.setKeeperAddresses(slasher.address, tipVault.address);

    await twocats.mint(owner.address, parseEther("5"));
    await gerza.mint(owner.address, parseEther("5"));
    await twocats.approve(boostVault.address, parseEther("5"));
    await gerza.approve(boostVault.address, parseEther("5"));
    await boostVault.depositTWOCATS(parseEther("5"));
    await boostVault.depositGERZA(parseEther("5"));

    await reward.approve(strategyTwocats.address, parseEther("3"));
    await reward.approve(strategyGerza.address, parseEther("3"));
    await strategyTwocats.simulateReward(parseEther("3"));
    await strategyGerza.simulateReward(parseEther("3"));

    const keeperTipBefore = await reward.balanceOf(keeper.address);
    await boostVault.connect(keeper).harvest();
    const keeperTipAfter = await reward.balanceOf(keeper.address);
    expect(keeperTipAfter.sub(keeperTipBefore)).to.equal(parseEther("1"));
  });

  it("queued governance actions execute only after timelock delay", async function () {
    const [owner] = await ethers.getSigners();

    const Bootloader = await ethers.getContractFactory("GPDIndex0Bootloader");
    const bootloader = await Bootloader.deploy();
    await bootloader.deployed();

    await bootloader.setGovernanceEnabled(true);

    const Timelock = await ethers.getContractFactory("TimelockController");
    const delay = 2;
    const timelock = await Timelock.deploy(delay, [owner.address], [owner.address], owner.address);
    await timelock.deployed();

    await bootloader.beginDecentralization(timelock.address, owner.address);

    const calldata = bootloader.interface.encodeFunctionData("setTargetTVL", [parseEther("100")]);

    await timelock.schedule(
      bootloader.address,
      0,
      calldata,
      ethers.constants.HashZero,
      ethers.constants.HashZero,
      delay
    );

    await expect(
      timelock.execute(
        bootloader.address,
        0,
        calldata,
        ethers.constants.HashZero,
        ethers.constants.HashZero
      )
    ).to.be.revertedWith("TimelockController: operation is not ready");

    await increaseTime(delay + 1);

    await timelock.execute(
      bootloader.address,
      0,
      calldata,
      ethers.constants.HashZero,
      ethers.constants.HashZero
    );

    expect(await bootloader.targetTVL()).to.equal(parseEther("100"));
  });
});

