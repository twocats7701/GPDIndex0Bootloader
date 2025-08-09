# Booster Flow & Emergency Exit

This repository uses third-party booster protocols such as **Vector** and **Echidna** to farm Platypus (PTP) yields without holding raw PTP or vePTP in the DAO treasury.

## Booster Usage

1. When farming PTP, route deposits through a booster rather than holding PTP/vePTP directly.
2. The booster stakes PTP on behalf of the vault and returns boosted yield.
3. Treasury funds never custody PTP or vePTP; only boosted derivatives are held.

## Position Caps and Monitoring

* Keep booster positions intentionally small to limit risk.
* Off-chain monitors must track booster health and watch for governance or pool changes.
* Immediately withdraw and unwind positions if a booster shows signs of distress or an exploit.

## Emergency Exit

Strategies expose an `emergencyWithdraw` function that bypasses reward harvesting and returns staked assets to the vault. The helper script below can be used to trigger this:

```bash
STRATEGY_ADDRESS=0x... npx hardhat run scripts/emergency-exit.js --network avalanche
```

The script unwinds the affected position and removes all exposure from the booster. Refer to [docs.vectorfinance.io](https://docs.vectorfinance.io/) for additional information on booster mechanics.
