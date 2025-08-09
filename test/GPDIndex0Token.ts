import { expect } from "chai";
import { ethers } from "hardhat";

const MAX_LOCK = 52 * 7 * 24 * 60 * 60; // 52 weeks in seconds

describe("GPDIndex0Token", function () {
  it("locks and provides ve balance", async function () {
    const [owner, user, distributor] = await ethers.getSigners();
    const Token = await ethers.getContractFactory("GPDIndex0Token");
    const token = await Token.deploy(ethers.utils.parseEther("1000"));
    await token.deployed();

    // Transfer tokens to user
    await token.transfer(user.address, ethers.utils.parseEther("100"));
    expect(await token.tokenBalanceOf(user.address)).to.equal(
      ethers.utils.parseEther("100")
    );

    // User locks 100 tokens for one week
    const duration = 7 * 24 * 60 * 60;
    await token.connect(user).lock(ethers.utils.parseEther("100"), duration);

    // Tokens moved to contract
    expect(await token.tokenBalanceOf(user.address)).to.equal(0);

    // ve balance should be amount * duration / MAX_LOCK
    const expectedVe = ethers.utils
      .parseEther("100")
      .mul(duration)
      .div(MAX_LOCK);
    const veBalance = await token.balanceOf(user.address);
    expect(veBalance).to.equal(expectedVe);

    // Extend lock by one week
    await token.connect(user).extendLock(duration);

    // Fast-forward time by two weeks and withdraw
    await ethers.provider.send("evm_increaseTime", [duration * 2]);
    await ethers.provider.send("evm_mine", []);
    await token.connect(user).withdraw();
    expect(await token.tokenBalanceOf(user.address)).to.equal(
      ethers.utils.parseEther("100")
    );
    expect(await token.balanceOf(user.address)).to.equal(0);

    // Set reward distributor and call notifyReward
    await token.setRewardDistributor(distributor.address);
    await expect(token.connect(distributor).notifyReward(user.address, 1))
      .to.emit(token, "RewardNotified")
      .withArgs(user.address, 1);
  });
});

