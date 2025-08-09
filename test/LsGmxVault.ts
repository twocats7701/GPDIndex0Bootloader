import { expect } from "chai";
import { ethers } from "hardhat";
import { computeTrailingApr, shouldTriggerBoost } from "../scripts/optimizer/gmxAprOptimizer";

describe("LsGmxVault", function () {
  it("restricts harvester to keepers", async () => {
    const Keeper = await ethers.getContractFactory("KeeperSlasher");
    const keeperSlasher = await Keeper.deploy();
    const Harvester = await ethers.getContractFactory("GmxHarvester");
    const harvester = await Harvester.deploy(keeperSlasher.address);
    const [, keeper] = await ethers.getSigners();
    await expect(harvester.harvestAll()).to.be.revertedWith("Not keeper");
    await keeperSlasher.registerKeeper(keeper.address);
    await harvester.connect(keeper).harvestAll();
  });

  it("computes APR and boost trigger", async () => {
    const apr = computeTrailingApr([1, 1, 1, 1, 1, 1, 1], 100);
    expect(apr).to.be.gt(0);
    expect(shouldTriggerBoost(apr, apr + 1)).to.equal(true);
  });
});

