let deposits = {};
let initialRewards = {};
let _totalRewards = 0;
let sdgs = new Set();

console.clear();

function deposit(sdg, value) {
  deposits[sdg] ??= 0;
  initialRewards[sdg] ??= 0;
  deposits[sdg] += value;
  initialRewards[sdg] = totalRewards();
  sdgs.add(sdg);
}

function totalDeposited() {
  return Object.values(deposits).reduce((a, b) => a + b, 0);
}

function totalSDGDeposited(sdg) {
  return deposits[sdg] ?? 0;
}

function totalRewards() {
  return _totalRewards;
}

function totalSDGRewards(sdg) {
  const sdgInitialRewards = initialRewards[sdg];
  const allDeposits = Object.entries(initialRewards).filter(
    ([_, initialReward]) => initialReward <= sdgInitialRewards
  );
  const _totalDeposited = allDeposits.reduce(
    (val, [_sdg]) => val + totalSDGDeposited(_sdg),
    0
  );

  const sdgRepresentation = totalSDGDeposited(sdg) / _totalDeposited;

  return (
    (totalRewards() - initialRewards[sdg]) * sdgRepresentation
  );
}

function _addRewards(value) {
  _totalRewards += value;
}

function _print() {
  console.log("Total deposited", totalDeposited());
  console.log("Total rewards", totalRewards());
  console.table(
    Object.assign(
      {},
      ...Array.from(sdgs.keys()).map((sdg) => ({
        [sdg]: {
          total_deposited: totalSDGDeposited(sdg),
          total_rewards: totalSDGRewards(sdg),
          total: totalSDGDeposited(sdg) + totalSDGRewards(sdg),
          initial_rewards: initialRewards[sdg],
        },
      }))
    )
  );
  const totalSaved = totalDeposited() + totalRewards();
  const totalComputed = Array.from(sdgs.keys()).reduce(
    (val, sdg) => val + totalSDGDeposited(sdg) + totalSDGRewards(sdg),
    0
  );
  console.log("Total saved", totalSaved);
  console.log("Total computed", totalComputed);
  console.assert(
    totalSaved === totalComputed,
    '\x1b[31m%s\x1b[0m', "Total saved and computed should be equal"
  );
}

deposit("a", 1500);
deposit("b", 1300);
console.log("\n\nDay 0");
_print();

console.log("\n\nDay 1");
_addRewards(100);
_print();
deposit("c", 1000);

console.log("\n\nDay 2");
_print();

console.log("\n\nDay 3");
_addRewards(100);
_print();

console.log("\n\nDay 4");
deposit("d", 1000);
_print();
