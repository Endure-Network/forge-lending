import fs from "fs";
import path from "path";

import { ethers } from "hardhat";

const ADDRESSES_PATH = path.resolve(__dirname, "..", "..", "deploy", "addresses.json");

const COMPTROLLER_ABI = [
  "function comptrollerLens() view returns (address)",
  "function oracle() view returns (address)",
  "function getAllMarkets() view returns (address[])",
  "function markets(address) view returns (bool, uint256, bool)",
  "function closeFactorMantissa() view returns (uint256)",
  "function enterMarkets(address[]) returns (uint256[])",
  "function getAccountLiquidity(address) view returns (uint256, uint256, uint256)",
];

const VTOKEN_ABI = [
  "function symbol() view returns (string)",
  "function underlying() view returns (address)",
  "function totalSupply() view returns (uint256)",
  "function totalBorrows() view returns (uint256)",
  "function totalReserves() view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function getCash() view returns (uint256)",
  "function borrowBalanceStored(address) view returns (uint256)",
  "function mint(uint256) returns (uint256)",
  "function borrow(uint256) returns (uint256)",
  "function repayBorrow(uint256) returns (uint256)",
  "function redeemUnderlying(uint256) returns (uint256)",
  "function liquidateBorrow(address, uint256, address) returns (uint256)",
];

const ERC20_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function approve(address, uint256) returns (bool)",
  "function mint(address, uint256)",
  "function symbol() view returns (string)",
];

const ORACLE_ABI = [
  "function admin() view returns (address)",
  "function setUnderlyingPrice(address, uint256)",
];

const ALICE_PK = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d";
const BOB_PK = "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a";

function fmtUnits(x: ethers.BigNumber, decimals = 18): string {
  return ethers.utils.formatUnits(x, decimals);
}

async function main() {
  const network = await ethers.provider.getNetwork();
  if (network.chainId !== 31337) {
    throw new Error(`smoke-local: requires chainId 31337, got ${network.chainId}`);
  }

  const a = JSON.parse(fs.readFileSync(ADDRESSES_PATH, "utf8"));
  const provider = ethers.provider;

  const [deployer] = await ethers.getSigners();
  const alice = new ethers.Wallet(ALICE_PK, provider);
  const bob = new ethers.Wallet(BOB_PK, provider);

  const comptroller = new ethers.Contract(a.unitroller, COMPTROLLER_ABI, provider);
  const oracle = new ethers.Contract(a.resilientOracle, ORACLE_ABI, provider);
  const wtao = new ethers.Contract(a.wtao, ERC20_ABI, provider);
  const alpha30 = new ethers.Contract(a.mockAlpha30, ERC20_ABI, provider);
  const vWTAO = new ethers.Contract(a.vWTAO, VTOKEN_ABI, provider);
  const vAlpha30 = new ethers.Contract(a.vAlpha30, VTOKEN_ABI, provider);

  const ONE = ethers.utils.parseEther("1");
  const HUNDRED = ethers.utils.parseEther("100");
  const TEN = ethers.utils.parseEther("10");
  const FIVE = ethers.utils.parseEther("5");
  const THOUSAND = ethers.utils.parseEther("1000");

  console.log("=== Endure Hardhat-side E2E smoke ===");
  console.log(`RPC chainId: ${network.chainId}`);

  console.log("\n--- Venus state verification ---");
  const lens = await comptroller.comptrollerLens();
  if (lens.toLowerCase() !== a.comptrollerLens.toLowerCase()) {
    throw new Error(`comptrollerLens mismatch`);
  }
  console.log(`  ✅ comptrollerLens() = ${lens}`);

  const oracleAddr = await comptroller.oracle();
  if (oracleAddr.toLowerCase() !== a.resilientOracle.toLowerCase()) {
    throw new Error(`oracle mismatch`);
  }
  console.log(`  ✅ oracle() = ${oracleAddr}`);

  const [isListed] = await comptroller.markets(a.vWTAO);
  if (!isListed) throw new Error(`vWTAO not listed`);
  console.log(`  ✅ vWTAO isListed=true`);

  console.log("\n--- Supply-side setup ---");
  await (await alpha30.connect(deployer).mint(alice.address, HUNDRED)).wait();
  console.log(`  ✅ mint 100 Alpha30 to Alice`);
  await (await wtao.connect(deployer).mint(deployer.address, THOUSAND)).wait();
  console.log(`  ✅ mint 1000 WTAO to Deployer`);
  await (await wtao.connect(deployer).approve(a.vWTAO, HUNDRED)).wait();
  console.log(`  ✅ Deployer approves vWTAO`);
  await (await vWTAO.connect(deployer).mint(HUNDRED)).wait();
  console.log(`  ✅ Deployer supplies 100 WTAO`);
  await (await alpha30.connect(alice).approve(a.vAlpha30, HUNDRED)).wait();
  console.log(`  ✅ Alice approves vAlpha30`);
  await (await vAlpha30.connect(alice).mint(HUNDRED)).wait();
  console.log(`  ✅ Alice supplies 100 Alpha30`);
  await (await comptroller.connect(alice).enterMarkets([a.vAlpha30])).wait();
  console.log(`  ✅ Alice enters Alpha30 market`);

  const cash = await vWTAO.getCash();
  if (cash.lt(HUNDRED)) throw new Error(`vWTAO cash too low: ${cash.toString()}`);
  console.log(`  ✅ vWTAO cash sufficient: ${cash.toString()}`);

  console.log("\n--- Borrow lifecycle ---");
  await (await vWTAO.connect(alice).borrow(TEN)).wait();
  const aliceWtao = await wtao.balanceOf(alice.address);
  if (!aliceWtao.eq(TEN)) {
    throw new Error(`Alice WTAO expected 10e18, got ${aliceWtao.toString()}`);
  }
  console.log(`  ✅ Alice borrowed and received 10 WTAO`);

  await (await wtao.connect(alice).approve(a.vWTAO, ethers.utils.parseEther("15"))).wait();
  await (await vWTAO.connect(alice).repayBorrow(TEN)).wait();
  const aliceDebt = await vWTAO.borrowBalanceStored(alice.address);
  const dustCap = ethers.BigNumber.from("1000000000000");
  if (aliceDebt.gte(dustCap)) {
    throw new Error(`Alice post-repay debt too high: ${aliceDebt.toString()}`);
  }
  console.log(`  ✅ Alice repaid; residual debt dust ${aliceDebt.toString()}`);

  console.log("\n--- Solvency invariant ---");
  const [tb, cash2, resv] = await Promise.all([
    vWTAO.totalBorrows(),
    vWTAO.getCash(),
    vWTAO.totalReserves(),
  ]);
  console.log(`  vWTAO cash:          ${cash2.toString()}`);
  console.log(`  vWTAO totalBorrows:  ${tb.toString()}`);
  console.log(`  vWTAO totalReserves: ${resv.toString()}`);
  if (cash2.add(resv).lt(tb)) {
    throw new Error(`SOLVENCY VIOLATED: cash + reserves < borrows`);
  }
  console.log(`  ✅ Solvency holds`);

  console.log("\n--- Redeem lifecycle ---");
  const aliceAlphaPre = await alpha30.balanceOf(alice.address);
  await (await vAlpha30.connect(alice).redeemUnderlying(TEN)).wait();
  const aliceAlphaPost = await alpha30.balanceOf(alice.address);
  if (aliceAlphaPost.lte(aliceAlphaPre)) {
    throw new Error(`Alice Alpha30 balance did not increase on redeem`);
  }
  console.log(`  ✅ Alice Alpha30 balance increased after redeem (${fmtUnits(aliceAlphaPre)} → ${fmtUnits(aliceAlphaPost)})`);

  console.log("\n--- Liquidation lifecycle ---");
  await (await alpha30.connect(deployer).mint(bob.address, HUNDRED)).wait();
  await (await alpha30.connect(bob).approve(a.vAlpha30, HUNDRED)).wait();
  await (await vAlpha30.connect(bob).mint(HUNDRED)).wait();
  await (await comptroller.connect(bob).enterMarkets([a.vAlpha30])).wait();
  await (await vWTAO.connect(bob).borrow(TEN)).wait();
  const bobWtao = await wtao.balanceOf(bob.address);
  if (!bobWtao.eq(TEN)) throw new Error(`Bob WTAO expected 10e18, got ${bobWtao.toString()}`);
  console.log(`  ✅ Bob borrowed 10 WTAO`);

  const oracleAdmin = await oracle.admin();
  if (oracleAdmin === ethers.constants.AddressZero) {
    throw new Error(`oracle admin is zero address`);
  }

  await provider.send("hardhat_impersonateAccount", [oracleAdmin]);
  await provider.send("hardhat_setBalance", [oracleAdmin, "0x3635C9ADC5DEA00000"]);
  const oracleAdminSigner = provider.getSigner(oracleAdmin);
  await (await oracle
    .connect(oracleAdminSigner)
    .setUnderlyingPrice(a.vAlpha30, ethers.utils.parseEther("0.1"))).wait();
  console.log(`  ✅ Oracle dropped Alpha30 price to 0.1 (impersonated admin)`);

  const [, , bobShortfall] = await comptroller.getAccountLiquidity(bob.address);
  if (bobShortfall.isZero()) {
    throw new Error(`Bob should be underwater after price drop`);
  }
  console.log(`  ✅ Bob shortfall: ${bobShortfall.toString()}`);

  await (await wtao.connect(deployer).approve(a.vWTAO, FIVE)).wait();
  const seizedPre = await vAlpha30.balanceOf(deployer.address);
  await (await vWTAO.connect(deployer).liquidateBorrow(bob.address, FIVE, a.vAlpha30)).wait();
  const seizedPost = await vAlpha30.balanceOf(deployer.address);
  if (seizedPost.lte(seizedPre)) {
    throw new Error(`Liquidator seized collateral did not increase`);
  }
  console.log(`  ✅ Liquidator seized vAlpha30 (${seizedPre.toString()} → ${seizedPost.toString()})`);

  await provider.send("hardhat_stopImpersonatingAccount", [oracleAdmin]);

  console.log("\n=== Hardhat-side E2E smoke PASSED ===");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
