import { expect } from "chai";
import { ethers } from "hardhat";

const toWei = (v: string) => ethers.utils.parseEther(v);

describe("GPDVeToken", function () {
  it("locks, extends and withdraws with time weighted balance", async () => {
    const [user] = await ethers.getSigners();

    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const token = await MockERC20.deploy("TOKEN", "TKN");

    const Ve = await ethers.getContractFactory("GPDVeToken");
    const ve = await Ve.deploy(token.address);

    await token.mint(user.address, toWei("100"));
    await token.connect(user).approve(ve.address, ethers.constants.MaxUint256);

    // lock 10 tokens for 1 year
    await ve.connect(user).lock(toWei("10"), 365 * 24 * 60 * 60);

    const bal1 = await ve.balanceOf(user.address);
    expect(bal1).to.equal(toWei("10"));

    // advance half a year
    await ethers.provider.send("evm_increaseTime", [182 * 24 * 60 * 60]);
    await ethers.provider.send("evm_mine", []);

    const balHalf = await ve.balanceOf(user.address);
    // roughly half the original voting power remains
    expect(balHalf).to.closeTo(toWei("5"), toWei("0.02"));

    // extend by 6 months
    await ve.connect(user).increaseLock(0, 182 * 24 * 60 * 60);
    const balExtended = await ve.balanceOf(user.address);
    expect(balExtended).to.be.gt(balHalf);

    // fast forward to unlock
    await ethers.provider.send("evm_increaseTime", [365 * 24 * 60 * 60]);
    await ethers.provider.send("evm_mine", []);

    await expect(ve.connect(user).withdraw()).to.emit(ve, "Withdrawn");
    expect(await token.balanceOf(user.address)).to.equal(toWei("100"));
  });
});
