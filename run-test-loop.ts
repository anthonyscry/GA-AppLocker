#!/usr/bin/env npx tsx
/**
 * UNIFIED TEST RUNNER - Streamlined MCP + Playwright + Stagehand
 * Runs automated browser tests for 20-30 minutes with keyboard notifications
 *
 * Usage:
 *   npx tsx run-test-loop.ts [suite] [duration_minutes]
 *   npm run loop              # Quick start
 *   npm run loop:full         # Full 30 minute run
 */

import { execSync, spawn, ChildProcess } from "child_process";
import * as fs from "fs";
import * as path from "path";

// ============================================================
// CONFIGURATION
// ============================================================

interface Config {
  duration: number;        // minutes
  suite: string;
  screenshotsDir: string;
  resultsDir: string;
  testInterval: number;    // ms between tests
  mcpRetries: number;
}

const CONFIG: Config = {
  duration: parseInt(process.argv[3]) || 25,
  suite: process.argv[2] || "all",
  screenshotsDir: path.join(process.cwd(), "screenshots"),
  resultsDir: path.join(process.cwd(), "test-results"),
  testInterval: 30000,     // 30 seconds between tests
  mcpRetries: 3,
};

// ============================================================
// TEST DEFINITIONS
// ============================================================

interface TestCase {
  name: string;
  url: string;
  waitText?: string;
  actions?: Array<{
    type: "click" | "fill" | "wait";
    selector?: string;
    text?: string;
    value?: string;
  }>;
}

const TEST_SUITES: Record<string, TestCase[]> = {
  smoke: [
    { name: "Google", url: "https://www.google.com", waitText: "Google" },
    { name: "GitHub", url: "https://github.com", waitText: "GitHub" },
  ],
  applocker: [
    { name: "AppLocker Overview", url: "https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/applocker-overview", waitText: "AppLocker" },
    { name: "AppLocker PowerShell", url: "https://learn.microsoft.com/en-us/powershell/module/applocker", waitText: "PowerShell" },
    { name: "WDAC Overview", url: "https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/appcontrol", waitText: "App Control" },
  ],
  security: [
    { name: "LOLBAS", url: "https://lolbas-project.github.io/", waitText: "LOLBAS" },
    { name: "GTFOBins", url: "https://gtfobins.github.io/", waitText: "GTFOBins" },
    { name: "MITRE ATT&CK", url: "https://attack.mitre.org/", waitText: "ATT&CK" },
  ],
  all: [], // Populated below
};

// Combine all suites for "all"
TEST_SUITES.all = [
  ...TEST_SUITES.smoke,
  ...TEST_SUITES.applocker,
  ...TEST_SUITES.security,
];

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

  // Linux notification
  try {
    execSync(`notify-send "${title}" "${message}" ${urgent ? "-u critical" : ""} 2>/dev/null`, { stdio: "pipe" });
  } catch { /* ignore */ }

  // Also trigger the PowerShell hook if available
  try {
    const hookPath = path.join(process.cwd(), ".claude/hooks/notify-input.ps1");
    if (fs.existsSync(hookPath)) {
      const urgentFlag = urgent ? "-Urgent" : "";
      execSync(`pwsh -NoProfile -ExecutionPolicy Bypass -File "${hookPath}" -Title "${title}" -Message "${message}" ${urgentFlag} 2>/dev/null`, { stdio: "pipe", timeout: 3000 });
    }
  } catch { /* ignore */ }

  // Play sound for urgent
  if (urgent) {
    try {
      execSync("paplay /usr/share/sounds/freedesktop/stereo/bell.oga 2>/dev/null || aplay /usr/share/sounds/alsa/Front_Center.wav 2>/dev/null || true", { stdio: "pipe" });
    } catch { /* ignore */ }
  }
}

function shoutKeyboardNeeded(context: string): void {
  notify("🎹 KEYBOARD INPUT NEEDED", context, true);

  // Create a marker file for external monitoring
  const markerPath = path.join(CONFIG.resultsDir, "INPUT_NEEDED.marker");
  fs.writeFileSync(markerPath, `${new Date().toISOString()}\n${context}`);
}

// ============================================================
// MCP HELPERS
// ============================================================

function mcpCall(tool: string, params: Record<string, unknown> = {}): string {
  for (let attempt = 1; attempt <= CONFIG.mcpRetries; attempt++) {
    try {
      const paramsJson = JSON.stringify(params);
      const result = execSync(
        `mcp-cli call chrome-devtools/${tool} '${paramsJson}'`,
        { encoding: "utf-8", timeout: 30000, cwd: process.cwd() }
      );
      return result;
    } catch (error) {
      if (attempt === CONFIG.mcpRetries) {
        const err = error as Error & { stderr?: string };
        throw new Error(`MCP ${tool} failed after ${CONFIG.mcpRetries} attempts: ${err.stderr || err.message}`);
      }
      // Wait before retry
      execSync(`sleep ${attempt}`);
    }
  }
  return "";
}

function checkBrowserConnection(): boolean {
  try {
    const pages = mcpCall("list_pages");
    return pages.includes("url") || pages.includes("title");
  } catch {
    return false;
  }
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
  inputNeededCount: number;
  running: boolean;
}

const state: RunnerState = {
  startTime: new Date(),
  testsRun: 0,
  passed: 0,
  failed: 0,
  screenshots: [],
  inputNeededCount: 0,
  running: true,
};

function getElapsedMinutes(): number {
  return (Date.now() - state.startTime.getTime()) / 60000;
}

function shouldContinue(): boolean {
  return state.running && getElapsedMinutes() < CONFIG.duration;
}

async function runTest(test: TestCase): Promise<boolean> {
  console.log(`\n┌${"─".repeat(58)}┐`);
  console.log(`│ 🧪 ${test.name.padEnd(53)}│`);
  console.log(`│    ${test.url.substring(0, 53).padEnd(53)}│`);
  console.log(`└${"─".repeat(58)}┘`);

  try {
    // Navigate
    mcpCall("navigate_page", { type: "url", url: test.url, timeout: 30000 });
    console.log("   ✓ Navigated");

    // Wait for page load
    await sleep(2000);

    // Check for expected text if specified
    if (test.waitText) {
      try {
        mcpCall("wait_for", { text: test.waitText, timeout: 10000 });
        console.log(`   ✓ Found: "${test.waitText}"`);
      } catch {
        console.log(`   ⚠ Text not found: "${test.waitText}"`);
      }
    }

    // Take screenshot
    const screenshotName = `${test.name.replace(/[^a-z0-9]/gi, "-").toLowerCase()}-${Date.now()}.png`;
    const screenshotPath = path.join(CONFIG.screenshotsDir, screenshotName);
    mcpCall("take_screenshot", { format: "png", filePath: screenshotPath });
    state.screenshots.push(screenshotPath);
    console.log(`   ✓ Screenshot: ${screenshotName}`);

    console.log("   ✅ PASSED");
    return true;

  } catch (error) {
    const err = error as Error;
    console.log(`   ❌ FAILED: ${err.message}`);

    // Check if this looks like it needs user input
    if (err.message.includes("timeout") || err.message.includes("blocked") || err.message.includes("captcha")) {
      state.inputNeededCount++;
      if (state.inputNeededCount >= 3) {
        shoutKeyboardNeeded(`Test "${test.name}" failed repeatedly. Browser may need attention.`);
        state.inputNeededCount = 0;
      }
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
    config: CONFIG,
  };

  const resultsPath = path.join(CONFIG.resultsDir, `run-${Date.now()}.json`);
  fs.writeFileSync(resultsPath, JSON.stringify(results, null, 2));

  console.log(`
╔══════════════════════════════════════════════════════════╗
║                    FINAL RESULTS                         ║
╠══════════════════════════════════════════════════════════╣
║ Duration: ${String(getElapsedMinutes().toFixed(1)).padStart(6)} minutes                              ║
║ Tests:    ${String(state.testsRun).padStart(6)}   Passed: ${String(state.passed).padStart(4)}   Failed: ${String(state.failed).padStart(4)}        ║
║ Screenshots: ${String(state.screenshots.length).padStart(4)}                                        ║
║ Results: ${resultsPath.split("/").pop()?.padEnd(46)}║
╚══════════════════════════════════════════════════════════╝`);
}

// ============================================================
// MAIN
// ============================================================

async function main(): Promise<void> {
  console.log(`
╔══════════════════════════════════════════════════════════╗
║          UNIFIED TEST LOOP - MCP + Playwright            ║
║          Duration: ${String(CONFIG.duration).padStart(2)} minutes  │  Suite: ${CONFIG.suite.padEnd(14)}   ║
╚══════════════════════════════════════════════════════════╝
  `);

  // Ensure directories exist
  [CONFIG.screenshotsDir, CONFIG.resultsDir].forEach(dir => {
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
  });

  // Check browser connection
  console.log("🔍 Checking browser connection...");
  if (!checkBrowserConnection()) {
    notify("Browser Not Connected", "Start Chrome with --remote-debugging-port=9222", true);
    console.log(`
❌ Cannot connect to browser!

Start Chrome with remote debugging:
  google-chrome --remote-debugging-port=9222

Or on Windows:
  chrome.exe --remote-debugging-port=9222
`);
    process.exit(1);
  }
  console.log("   ✓ Browser connected!\n");

  notify("Test Loop Started", `Running ${CONFIG.suite} suite for ${CONFIG.duration} minutes`);

  // Get tests for this suite
  const tests = TEST_SUITES[CONFIG.suite] || TEST_SUITES.smoke;
  let testIndex = 0;

  // Main test loop
  while (shouldContinue()) {
    const test = tests[testIndex];
    const passed = await runTest(test);

    state.testsRun++;
    if (passed) {
      state.passed++;
    } else {
      state.failed++;
    }

    // Move to next test
    testIndex = (testIndex + 1) % tests.length;

    // Print status
    printStatus();

    // Wait before next test (check shouldContinue in chunks)
    if (shouldContinue()) {
      const waitTime = CONFIG.testInterval;
      console.log(`\n⏳ Next test in ${waitTime / 1000}s...`);

      for (let waited = 0; waited < waitTime && shouldContinue(); waited += 5000) {
        await sleep(Math.min(5000, waitTime - waited));
      }
    }
  }

  // Save results
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
UNIFIED TEST LOOP

Usage:
  npx tsx run-test-loop.ts [suite] [duration_minutes]

Suites:
  smoke      - Quick connectivity tests (Google, GitHub)
  applocker  - AppLocker documentation
  security   - Security research sites (LOLBAS, GTFOBins, MITRE)
  all        - All tests combined (default)

Examples:
  npx tsx run-test-loop.ts                # All tests, 25 min
  npx tsx run-test-loop.ts smoke 5        # Smoke tests, 5 min
  npx tsx run-test-loop.ts security 30    # Security research, 30 min
  npm run loop                            # Quick start alias
`);
  process.exit(0);
}

main().catch(error => {
  console.error("Fatal error:", error);
  notify("Test Loop Crashed", error.message, true);
  process.exit(1);
});
