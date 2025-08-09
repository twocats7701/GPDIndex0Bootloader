import { expect } from "chai";

describe("script parameter parsing", () => {
  afterEach(() => {
    delete require.cache[require.resolve("../scripts/deploy-new-strategies.js")];
    delete require.cache[require.resolve("../scripts/flash-loan-leveraged-deposit.js")];
    delete require.cache[require.resolve("../scripts/rebalance-strategies.js")];
  });

  it("deploy-new-strategies parses env", () => {
    process.env.UNDERLYING = "0x0000000000000000000000000000000000000001";
    process.env.PLATYPUS_ROUTER = "0x0000000000000000000000000000000000000002";
    process.env.TRADER_JOE_ROUTER = "0x0000000000000000000000000000000000000005";
    process.env.AAVE_POOL = "0x0000000000000000000000000000000000000003";
    process.env.FLASH_LOAN_PROVIDER = "0x0000000000000000000000000000000000000004";
    const { parseArgs } = require("../scripts/deploy-new-strategies.js");
    const args = parseArgs();
    expect(args.underlying).to.equal(process.env.UNDERLYING);
    expect(args.platypusRouter).to.equal(process.env.PLATYPUS_ROUTER);
    expect(args.traderJoeRouter).to.equal(process.env.TRADER_JOE_ROUTER);
    expect(args.aavePool).to.equal(process.env.AAVE_POOL);
    expect(args.flashLoanProvider).to.equal(process.env.FLASH_LOAN_PROVIDER);
    delete process.env.UNDERLYING;
    delete process.env.PLATYPUS_ROUTER;
    delete process.env.TRADER_JOE_ROUTER;
    delete process.env.AAVE_POOL;
    delete process.env.FLASH_LOAN_PROVIDER;
  });

  it("flash-loan-leveraged-deposit parses env", () => {
    process.env.VAULT = "0x0000000000000000000000000000000000000010";
    process.env.FLASH_LOAN_PROVIDER = "0x0000000000000000000000000000000000000011";
    process.env.BORROW_TOKEN = "0x0000000000000000000000000000000000000012";
    process.env.DEPOSIT_AMOUNT = "1000";
    const { parseArgs } = require("../scripts/flash-loan-leveraged-deposit.js");
    const args = parseArgs();
    expect(args.vault).to.equal(process.env.VAULT);
    expect(args.flashLoanProvider).to.equal(process.env.FLASH_LOAN_PROVIDER);
    expect(args.borrowToken).to.equal(process.env.BORROW_TOKEN);
    expect(args.depositAmount).to.equal(process.env.DEPOSIT_AMOUNT);
    delete process.env.VAULT;
    delete process.env.FLASH_LOAN_PROVIDER;
    delete process.env.BORROW_TOKEN;
    delete process.env.DEPOSIT_AMOUNT;
  });

  it("rebalance-strategies parses env", () => {
    process.env.FROM_STRATEGY = "0x00000000000000000000000000000000000000f1";
    process.env.TO_STRATEGY = "0x00000000000000000000000000000000000000f2";
    process.env.AMOUNT = "500";
    const { parseArgs } = require("../scripts/rebalance-strategies.js");
    const args = parseArgs();
    expect(args.fromStrategy).to.equal(process.env.FROM_STRATEGY);
    expect(args.toStrategy).to.equal(process.env.TO_STRATEGY);
    expect(args.amount).to.equal(process.env.AMOUNT);
    delete process.env.FROM_STRATEGY;
    delete process.env.TO_STRATEGY;
    delete process.env.AMOUNT;
  });
});
