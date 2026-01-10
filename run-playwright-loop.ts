#!/usr/bin/env npx tsx
/**
 * PLAYWRIGHT TEST LOOP - Direct browser automation without MCP
 * Runs automated browser tests for 20-30 minutes with keyboard notifications
 * Falls back to Playwright when Chrome DevTools MCP isn't available
 *
 * Usage:
 *   npx tsx run-playwright-loop.ts [suite] [duration_minutes]
 *   npm run loop:playwright       # Quick start
 */

import { chromium, Browser, Page } from "@playwright/test";
import * as fs from "fs";
import * as path from "path";
import { execSync } from "child_process";

// ============================================================
// CONFIGURATION
// ============================================================

interface Config {
  duration: number;
  suite: string;
  screenshotsDir: string;
  resultsDir: string;
  testInterval: number;
  headless: boolean;
}

const CONFIG: Config = {
  duration: parseInt(process.argv[3]) || 25,
  suite: process.argv[2] || "all",
  screenshotsDir: path.join(process.cwd(), "screenshots"),
  resultsDir: path.join(process.cwd(), "test-results"),
  testInterval: 30000,
  headless: true,  // Run headless for automation
};

// ============================================================
// TEST DEFINITIONS
// ============================================================

interface TestCase {
  name: string;
  url: string;
  waitSelector?: string;
  waitText?: string;
}

const TEST_SUITES: Record<string, TestCase[]> = {
  smoke: [
    { name: "Google", url: "https://www.google.com", waitSelector: "input[name='q']" },
    { name: "GitHub", url: "https://github.com", waitSelector: "a[href='/login']" },
  ],
  applocker: [
    { name: "AppLocker Overview", url: "https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/applocker-overview", waitText: "AppLocker" },
    { name: "AppLocker PowerShell", url: "https://learn.microsoft.com/en-us/powershell/module/applocker", waitText: "AppLocker" },
    { name: "WDAC Overview", url: "https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/appcontrol", waitText: "App Control" },
  ],
  security: [
    { name: "LOLBAS", url: "https://lolbas-project.github.io/", waitText: "LOLBAS" },
    { name: "GTFOBins", url: "https://gtfobins.github.io/", waitText: "GTFOBins" },
    { name: "MITRE ATT&CK", url: "https://attack.mitre.org/", waitText: "ATT&CK" },
  ],
  all: [],
};

TEST_SUITES.all = [...TEST_SUITES.smoke, ...TEST_SUITES.applocker, ...TEST_SUITES.security];

// ============================================================
// NOTIFICATION SYSTEM
// ============================================================

function notify(title: string, message: string, urgent = false): void {
  const color = urgent ? "\x1b[31m" : "\x1b[33m";
  const reset = "\x1b[0m";

  console.log(`\n${color}${"═".repeat(60)}${reset}`);
  console.log(`${color}  ${urgent ? "🚨" : "🔔"} ${title}${reset}`);
  console.log(`  ${message}`);
  console.log(`${color}${"═".repeat(60)}${reset}\n`);

  try {
    execSync(`notify-send "${title}" "${message}" ${urgent ? "-u critical" : ""} 2>/dev/null`, { stdio: "pipe" });
  } catch { /* ignore */ }

  if (urgent) {
    try {
      execSync("paplay /usr/share/sounds/freedesktop/stereo/bell.oga 2>/dev/null || true", { stdio: "pipe" });
    } catch { /* ignore */ }
  }
}

function shoutKeyboardNeeded(context: string): void {
  notify("🎹 KEYBOARD INPUT NEEDED", context, true);
  const markerPath = path.join(CONFIG.resultsDir, "INPUT_NEEDED.marker");
  fs.writeFileSync(markerPath, `${new Date().toISOString()}\n${context}`);
}

// ============================================================
// TEST RUNNER
// ============================================================

interface RunnerState {
  startTime: Date;
  testsRun: number;
  passed: number;
  failed: number;
  screenshots: string[];
  running: boolean;
  consecutiveFailures: number;
}

const state: RunnerState = {
  startTime: new Date(),
  testsRun: 0,
  passed: 0,
  failed: 0,
  screenshots: [],
  running: true,
  consecutiveFailures: 0,
};

function getElapsedMinutes(): number {
  return (Date.now() - state.startTime.getTime()) / 60000;
}

function shouldContinue(): boolean {
  return state.running && getElapsedMinutes() < CONFIG.duration;
}

async function runTest(page: Page, test: TestCase): Promise<boolean> {
  console.log(`\n┌${"─".repeat(58)}┐`);
  console.log(`│ 🧪 ${test.name.padEnd(53)}│`);
  console.log(`│    ${test.url.substring(0, 53).padEnd(53)}│`);
  console.log(`└${"─".repeat(58)}┘`);

  try {
    // Navigate
    await page.goto(test.url, { timeout: 30000, waitUntil: "domcontentloaded" });
    console.log("   ✓ Navigated");

    // Wait for selector or text
    if (test.waitSelector) {
      await page.waitForSelector(test.waitSelector, { timeout: 10000 });
      console.log(`   ✓ Found selector: ${test.waitSelector}`);
    } else if (test.waitText) {
      await page.waitForSelector(`text=${test.waitText}`, { timeout: 10000 });
      console.log(`   ✓ Found text: "${test.waitText}"`);
    }

    // Take screenshot
    const screenshotName = `${test.name.replace(/[^a-z0-9]/gi, "-").toLowerCase()}-${Date.now()}.png`;
    const screenshotPath = path.join(CONFIG.screenshotsDir, screenshotName);
    await page.screenshot({ path: screenshotPath, fullPage: false });
    state.screenshots.push(screenshotPath);
    console.log(`   ✓ Screenshot: ${screenshotName}`);

    console.log("   ✅ PASSED");
    state.consecutiveFailures = 0;
    return true;

  } catch (error) {
    const err = error as Error;
    console.log(`   ❌ FAILED: ${err.message.substring(0, 100)}`);
    state.consecutiveFailures++;

    if (state.consecutiveFailures >= 3) {
      shoutKeyboardNeeded(`${state.consecutiveFailures} tests failed in a row. Check network or site availability.`);
      state.consecutiveFailures = 0;
    }

    return false;
  }
}

function printStatus(): void {
  const elapsed = getElapsedMinutes().toFixed(1);
  const remaining = (CONFIG.duration - parseFloat(elapsed)).toFixed(1);
  const passRate = state.testsRun > 0 ? ((state.passed / state.testsRun) * 100).toFixed(0) : "0";

  console.log(`
┌──────────────────────────────────────────────────────────┐
│ ⏱  ${new Date().toLocaleTimeString()}  │  Elapsed: ${elapsed.padStart(5)} min  │  Remaining: ${remaining.padStart(5)} min │
├──────────────────────────────────────────────────────────┤
│ Tests: ${String(state.testsRun).padStart(3)}  │  ✅ ${String(state.passed).padStart(3)}  │  ❌ ${String(state.failed).padStart(3)}  │  Rate: ${passRate.padStart(3)}%       │
│ Screenshots: ${String(state.screenshots.length).padStart(3)}                                          │
└──────────────────────────────────────────────────────────┘`);
}

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function saveResults(): Promise<void> {
  const results = {
    ...state,
    endTime: new Date(),
    durationMinutes: getElapsedMinutes(),
    suite: CONFIG.suite,
  };

  const resultsPath = path.join(CONFIG.resultsDir, `playwright-run-${Date.now()}.json`);
  fs.writeFileSync(resultsPath, JSON.stringify(results, null, 2));

  console.log(`
╔══════════════════════════════════════════════════════════╗
║                    FINAL RESULTS                         ║
╠══════════════════════════════════════════════════════════╣
║ Duration: ${String(getElapsedMinutes().toFixed(1)).padStart(6)} minutes                              ║
║ Tests:    ${String(state.testsRun).padStart(6)}   Passed: ${String(state.passed).padStart(4)}   Failed: ${String(state.failed).padStart(4)}        ║
║ Screenshots: ${String(state.screenshots.length).padStart(4)}                                        ║
╚══════════════════════════════════════════════════════════╝`);
}

// ============================================================
// MAIN
// ============================================================

async function main(): Promise<void> {
  console.log(`
╔══════════════════════════════════════════════════════════╗
║         PLAYWRIGHT TEST LOOP - Direct Automation         ║
║         Duration: ${String(CONFIG.duration).padStart(2)} minutes  │  Suite: ${CONFIG.suite.padEnd(14)}   ║
╚══════════════════════════════════════════════════════════╝
  `);

  // Ensure directories exist
  [CONFIG.screenshotsDir, CONFIG.resultsDir].forEach(dir => {
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
  });

  // Launch browser
  console.log("🚀 Launching browser...");
  let browser: Browser;

  try {
    browser = await chromium.launch({
      headless: CONFIG.headless,
      args: ["--no-sandbox", "--disable-setuid-sandbox"],
    });
    console.log("   ✓ Browser launched!\n");
  } catch (error) {
    const err = error as Error;
    notify("Browser Launch Failed", err.message, true);
    console.log(`
❌ Cannot launch browser!

Try installing Playwright browsers:
  npx playwright install chromium

Or run with system Chrome:
  npm run loop  (uses MCP with Chrome --remote-debugging-port=9222)
`);
    process.exit(1);
  }

  const context = await browser.newContext();
  const page = await context.newPage();

  notify("Test Loop Started", `Running ${CONFIG.suite} suite for ${CONFIG.duration} minutes`);

  const tests = TEST_SUITES[CONFIG.suite] || TEST_SUITES.smoke;
  let testIndex = 0;

  // Main test loop
  try {
    while (shouldContinue()) {
      const test = tests[testIndex];
      const passed = await runTest(page, test);

      state.testsRun++;
      if (passed) {
        state.passed++;
      } else {
        state.failed++;
      }

      testIndex = (testIndex + 1) % tests.length;
      printStatus();

      if (shouldContinue()) {
        console.log(`\n⏳ Next test in ${CONFIG.testInterval / 1000}s...`);
        for (let waited = 0; waited < CONFIG.testInterval && shouldContinue(); waited += 5000) {
          await sleep(Math.min(5000, CONFIG.testInterval - waited));
        }
      }
    }
  } finally {
    await browser.close();
  }

  await saveResults();
  notify("Test Loop Complete", `Ran ${state.testsRun} tests: ${state.passed} passed, ${state.failed} failed`, true);
}

// Handle graceful shutdown
process.on("SIGINT", () => {
  console.log("\n\n⚠️  Stopping test loop...");
  state.running = false;
});

process.on("SIGTERM", () => {
  console.log("\n\n⚠️  Stopping test loop...");
  state.running = false;
});

// Help
if (process.argv[2] === "help" || process.argv[2] === "--help") {
  console.log(`
PLAYWRIGHT TEST LOOP

Usage:
  npx tsx run-playwright-loop.ts [suite] [duration_minutes]

Suites:
  smoke      - Quick connectivity tests
  applocker  - AppLocker documentation
  security   - Security research sites
  all        - All tests combined (default)

Examples:
  npx tsx run-playwright-loop.ts smoke 5
  npm run loop:playwright
`);
  process.exit(0);
}

main().catch(error => {
  console.error("Fatal error:", error);
  notify("Test Loop Crashed", error.message, true);
  process.exit(1);
});
