import { expect } from "chai";
import { ethers } from "hardhat";

describe("GPDIndex0EmissionSchedule", function () {
  it("aggregates ve balances with dynamic multipliers", async function () {
    const [owner, user] = await ethers.getSigners();

    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const twocats = await MockERC20.deploy("TWOCATS", "TWOCATS");
    await twocats.deployed();
    const gerza = await MockERC20.deploy("GERZA", "GERZA");
    await gerza.deployed();

    await twocats.mint(user.address, ethers.utils.parseEther("100"));
    await gerza.mint(user.address, ethers.utils.parseEther("50"));

    const Emission = await ethers.getContractFactory("GPDIndex0EmissionSchedule");
    const emission = await Emission.deploy();
    await emission.deployed();

    await emission.setGovernanceEnabled(true);

    await emission.setTokenWeight(twocats.address, 20000); // 2x weight
    await emission.setTokenWeight(gerza.address, 15000); // 1.5x weight

    const weight = await emission.getGovernanceWeight(user.address);

    const expected = ethers.utils
      .parseEther("100")
      .mul(20000)
      .div(10000)
      .add(ethers.utils.parseEther("50").mul(15000).div(10000));

    expect(weight).to.equal(expected);
  });
});

