const fs = require('fs');
const path = require('path');
const vm = require('vm');

const htmlPath = path.join(__dirname, '..', 'singwallet_preview.html');
const htmlContent = fs.readFileSync(htmlPath, 'utf-8');

console.log("Loaded HTML: " + htmlContent.length + " bytes");

// Check 1: 0 native <select> tags
const selectTagMatches = htmlContent.match(/<select\b[^>]*>/gi);
if (selectTagMatches) {
  console.error("FAIL: Found native <select> tags:", selectTagMatches);
  process.exit(1);
} else {
  console.log("PASS: 0 native <select> tags found in singwallet_preview.html");
}

// Check 2: All 8 custom dropdown containers exist
const expectedIds = [
  'quick-date-dropdown',
  'select-channel',
  'select-account',
  'rule-match-type',
  'rule-target-cat',
  'manual-category',
  'manual-account',
  'acc-add-type'
];

for (const id of expectedIds) {
  if (!htmlContent.includes(`id="dropdown-wrap-${id}"`)) {
    console.error(`FAIL: Missing dropdown wrap for ${id}`);
    process.exit(1);
  }
  if (!htmlContent.includes(`id="${id}"`)) {
    console.error(`FAIL: Missing hidden input for ${id}`);
    process.exit(1);
  }
  if (!htmlContent.includes(`id="label-${id}"`)) {
    console.error(`FAIL: Missing label span for ${id}`);
    process.exit(1);
  }
  if (!htmlContent.includes(`id="menu-${id}"`)) {
    console.error(`FAIL: Missing menu for ${id}`);
    process.exit(1);
  }
  console.log(`PASS: All elements present for #${id}`);
}

console.log("All static structure checks PASSED!");
