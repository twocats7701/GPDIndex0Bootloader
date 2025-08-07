async function main() {
  const GPDIndex0Bootloader = await ethers.getContractFactory("GPDIndex0Bootloader");
  const bootloader = await GPDIndex0Bootloader.deploy();
  await bootloader.deployed();
  console.log("GPDIndex0Bootloader deployed to:", bootloader.address);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
