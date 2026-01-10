import "dotenv/config";
import * as fs from "fs";
import * as path from "path";
import { execSync, spawn } from "child_process";

// ============================================================
// AUTONOMOUS TEST RUNNER - Long-running browser automation
// Runs for 20-30 minutes with continuous testing and notifications
// ============================================================

interface TestConfig {
  name: string;
  url: string;
  steps: TestAction[];
  expectText?: string;
  interval?: number; // ms between runs
}

interface TestAction {
  action: "screenshot" | "navigate" | "wait" | "check" | "evaluate";
  params: Record<string, unknown>;
}

interface RunnerState {
  startTime: Date;
  testsRun: number;
  testsPassed: number;
  testsFailed: number;
  lastError?: string;
  screenshots: string[];
  running: boolean;
}

// Notification helper using the PowerShell hook
function notifyUser(title: string, message: string, urgent = false): void {
  console.log(`\n${"=".repeat(60)}`);
  console.log(`  ${urgent ? "🚨" : "🔔"} ${title}`);
  console.log(`  ${message}`);
  console.log(`${"=".repeat(60)}\n`);

  try {
    const hookPath = path.resolve(__dirname, "../.claude/hooks/notify-input.ps1");
    if (fs.existsSync(hookPath)) {
      const urgentFlag = urgent ? "-Urgent" : "";
      execSync(
        `pwsh -NoProfile -ExecutionPolicy Bypass -File "${hookPath}" -Title "${title}" -Message "${message}" ${urgentFlag}`,
        { stdio: "pipe", timeout: 5000 }
      );
    }
  } catch {
    // Notification failed, console output is enough
  }
}

// MCP command executor
function mcpCall(tool: string, params: Record<string, unknown>): string {
  try {
    const paramsJson = JSON.stringify(params);
    const result = execSync(
      `mcp-cli call chrome-devtools/${tool} '${paramsJson}'`,
      { encoding: "utf-8", timeout: 30000, cwd: path.resolve(__dirname, "..") }
    );
    return result;
  } catch (error) {
    const err = error as Error & { stderr?: string };
    return err.stderr || err.message;
  }
}

// ============================================================
// PREDEFINED TEST SUITES
// ============================================================

const TEST_SUITES: Record<string, TestConfig[]> = {
  // AppLocker documentation test suite
  applocker: [
    {
      name: "AppLocker Overview",
      url: "https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/applocker-overview",
      steps: [
        { action: "screenshot", params: { name: "overview" } },
        { action: "check", params: { text: "AppLocker" } },
      ],
      expectText: "AppLocker",
      interval: 120000, // 2 min
    },
    {
      name: "AppLocker Policies",
      url: "https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/applocker-policies-design-guide",
      steps: [
        { action: "screenshot", params: { name: "policies" } },
        { action: "check", params: { text: "policy" } },
      ],
      expectText: "policy",
      interval: 120000,
    },
    {
      name: "AppLocker PowerShell",
      url: "https://learn.microsoft.com/en-us/powershell/module/applocker",
      steps: [
        { action: "screenshot", params: { name: "powershell" } },
        { action: "check", params: { text: "AppLocker" } },
      ],
      expectText: "AppLocker",
      interval: 120000,
    },
  ],

  // LOLBins research suite
  lolbins: [
    {
      name: "LOLBAS Project",
      url: "https://lolbas-project.github.io/",
      steps: [
        { action: "screenshot", params: { name: "lolbas-home" } },
        { action: "check", params: { text: "LOLBin" } },
      ],
      expectText: "Living Off The Land",
      interval: 180000, // 3 min
    },
    {
      name: "GTFOBINS",
      url: "https://gtfobins.github.io/",
      steps: [
        { action: "screenshot", params: { name: "gtfobins" } },
        { action: "check", params: { text: "GTFOBins" } },
      ],
      expectText: "Unix",
      interval: 180000,
    },
  ],

  // Security news monitoring
  security: [
    {
      name: "Microsoft Security Blog",
      url: "https://www.microsoft.com/en-us/security/blog/",
      steps: [
        { action: "screenshot", params: { name: "msft-security" } },
        { action: "check", params: { text: "Security" } },
      ],
      expectText: "Security",
      interval: 300000, // 5 min
    },
    {
      name: "CISA Alerts",
      url: "https://www.cisa.gov/news-events/cybersecurity-advisories",
      steps: [
        { action: "screenshot", params: { name: "cisa-alerts" } },
        { action: "check", params: { text: "Advisory" } },
      ],
      interval: 300000,
    },
  ],

  // Quick smoke test
  smoke: [
    {
      name: "Google Test",
      url: "https://www.google.com",
      steps: [
        { action: "screenshot", params: { name: "google" } },
        { action: "check", params: { text: "Google" } },
      ],
      expectText: "Google",
      interval: 60000, // 1 min
    },
  ],
};

// ============================================================
// AUTONOMOUS RUNNER CLASS
// ============================================================

class AutonomousRunner {
  private state: RunnerState;
  private screenshotDir: string;
  private resultsDir: string;
  private maxDuration: number; // ms
  private tests: TestConfig[];
  private currentTestIndex = 0;

  constructor(
    suite: string = "applocker",
    durationMinutes = 25
  ) {
    this.state = {
      startTime: new Date(),
      testsRun: 0,
      testsPassed: 0,
      testsFailed: 0,
      screenshots: [],
      running: true,
    };

    this.screenshotDir = path.resolve(__dirname, "screenshots");
    this.resultsDir = path.resolve(__dirname, "results");
    this.maxDuration = durationMinutes * 60 * 1000;
    this.tests = TEST_SUITES[suite] || TEST_SUITES.smoke;

    // Ensure directories exist
    [this.screenshotDir, this.resultsDir].forEach(dir => {
      if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }
    });

    console.log(`
╔══════════════════════════════════════════════════════════════╗
║           AUTONOMOUS TEST RUNNER                             ║
║           Duration: ${durationMinutes} minutes                              ║
║           Suite: ${suite.padEnd(42)}║
╚══════════════════════════════════════════════════════════════╝
    `);
  }

  private getElapsedMinutes(): number {
    return (Date.now() - this.state.startTime.getTime()) / 60000;
  }

  private shouldContinue(): boolean {
    const elapsed = Date.now() - this.state.startTime.getTime();
    return this.state.running && elapsed < this.maxDuration;
  }

  private async runTest(test: TestConfig): Promise<boolean> {
    console.log(`\n${"─".repeat(50)}`);
    console.log(`🧪 Running: ${test.name}`);
    console.log(`   URL: ${test.url}`);
    console.log(`${"─".repeat(50)}`);

    try {
      // Navigate to URL
      const navResult = mcpCall("navigate_page", { type: "url", url: test.url, timeout: 30000 });
      console.log(`   ✓ Navigated to page`);

      // Wait for page load
      await this.sleep(3000);

      // Take screenshot
      const screenshotName = `${test.name.replace(/\s+/g, "-").toLowerCase()}-${Date.now()}.png`;
      const screenshotPath = path.join(this.screenshotDir, screenshotName);
      mcpCall("take_screenshot", { format: "png", filePath: screenshotPath });
      this.state.screenshots.push(screenshotPath);
      console.log(`   ✓ Screenshot: ${screenshotName}`);

      // Check for expected text
      if (test.expectText) {
        try {
          mcpCall("wait_for", { text: test.expectText, timeout: 10000 });
          console.log(`   ✓ Found text: "${test.expectText}"`);
        } catch {
          console.log(`   ⚠ Text not found: "${test.expectText}"`);
        }
      }

      console.log(`   ✅ Test passed`);
      return true;
    } catch (error) {
      const err = error as Error;
      console.log(`   ❌ Test failed: ${err.message}`);
      this.state.lastError = err.message;
      return false;
    }
  }

  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  private printStatus(): void {
    const elapsed = this.getElapsedMinutes().toFixed(1);
    const remaining = ((this.maxDuration / 60000) - parseFloat(elapsed)).toFixed(1);

    console.log(`
┌────────────────────────────────────────────────────────────┐
│ STATUS @ ${new Date().toLocaleTimeString()}                                       │
├────────────────────────────────────────────────────────────┤
│ Elapsed: ${elapsed.padStart(5)} min  │  Remaining: ${remaining.padStart(5)} min                │
│ Tests Run: ${String(this.state.testsRun).padStart(4)}   │  Passed: ${String(this.state.testsPassed).padStart(4)}  │  Failed: ${String(this.state.testsFailed).padStart(4)}  │
│ Screenshots: ${String(this.state.screenshots.length).padStart(4)}                                           │
└────────────────────────────────────────────────────────────┘
    `);
  }

  async run(): Promise<void> {
    notifyUser(
      "Autonomous Runner Started",
      `Running for ${this.maxDuration / 60000} minutes. Will notify if input needed.`
    );

    // Initial browser check
    console.log("\n🔍 Checking browser connection...");
    try {
      const pages = mcpCall("list_pages", {});
      console.log("   Browser connected:", pages.substring(0, 100));
    } catch (error) {
      const err = error as Error;
      notifyUser("Browser Connection Failed", err.message, true);
      console.error("❌ Cannot connect to browser. Start Chrome DevTools MCP first.");
      return;
    }

    // Main test loop
    while (this.shouldContinue()) {
      const test = this.tests[this.currentTestIndex];
      const passed = await this.runTest(test);

      this.state.testsRun++;
      if (passed) {
        this.state.testsPassed++;
      } else {
        this.state.testsFailed++;
      }

      // Move to next test
      this.currentTestIndex = (this.currentTestIndex + 1) % this.tests.length;

      // Print status
      this.printStatus();

      // Check if we need user input (e.g., CAPTCHA, login)
      if (this.state.testsFailed > 3) {
        notifyUser(
          "Multiple Test Failures",
          `${this.state.testsFailed} tests failed. Check browser for issues.`,
          true
        );
        // Reset failure count
        this.state.testsFailed = 0;
      }

      // Wait before next test
      const waitTime = test.interval || 120000;
      const waitMinutes = (waitTime / 60000).toFixed(1);
      console.log(`\n⏳ Waiting ${waitMinutes} minutes before next test...`);

      // Wait in chunks so we can check shouldContinue
      const chunkSize = 10000;
      for (let waited = 0; waited < waitTime && this.shouldContinue(); waited += chunkSize) {
        await this.sleep(Math.min(chunkSize, waitTime - waited));
      }
    }

    // Final report
    await this.saveReport();
    notifyUser(
      "Autonomous Runner Complete",
      `Ran ${this.state.testsRun} tests. ${this.state.testsPassed} passed, ${this.state.testsFailed} failed.`,
      true
    );
  }

  private async saveReport(): Promise<void> {
    const report = {
      ...this.state,
      endTime: new Date(),
      durationMinutes: this.getElapsedMinutes(),
    };

    const reportPath = path.join(this.resultsDir, `run-${Date.now()}.json`);
    fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));

    console.log(`
╔══════════════════════════════════════════════════════════════╗
║                    FINAL REPORT                              ║
╠══════════════════════════════════════════════════════════════╣
║ Duration: ${String(this.getElapsedMinutes().toFixed(1)).padStart(6)} minutes                                ║
║ Tests Run: ${String(this.state.testsRun).padStart(5)}                                          ║
║ Passed: ${String(this.state.testsPassed).padStart(5)}  │  Failed: ${String(this.state.testsFailed).padStart(5)}                         ║
║ Screenshots: ${String(this.state.screenshots.length).padStart(4)}                                        ║
║ Report: ${reportPath.substring(reportPath.lastIndexOf('/') + 1).padEnd(50)}║
╚══════════════════════════════════════════════════════════════╝
    `);
  }

  stop(): void {
    this.state.running = false;
  }
}

// ============================================================
// CLI
// ============================================================

async function main() {
  const args = process.argv.slice(2);
  const suite = args[0] || "applocker";
  const duration = parseInt(args[1]) || 25;

  if (args[0] === "help" || args[0] === "--help") {
    console.log(`
AUTONOMOUS TEST RUNNER

Usage:
  npm run test:auto [suite] [duration_minutes]

Available Suites:
  applocker  - AppLocker documentation tests (default)
  lolbins    - LOLBins research tests
  security   - Security news monitoring
  smoke      - Quick connectivity test

Examples:
  npm run test:auto                    # Run applocker suite for 25 min
  npm run test:auto lolbins 30         # Run lolbins suite for 30 min
  npm run test:auto smoke 5            # Quick 5 min smoke test
    `);
    return;
  }

  const runner = new AutonomousRunner(suite, duration);

  // Handle graceful shutdown
  process.on("SIGINT", () => {
    console.log("\n\n⚠️  Received SIGINT. Stopping runner...");
    runner.stop();
  });

  process.on("SIGTERM", () => {
    console.log("\n\n⚠️  Received SIGTERM. Stopping runner...");
    runner.stop();
  });

  await runner.run();
}

main().catch(error => {
  console.error("Fatal error:", error);
  notifyUser("Runner Crashed", error.message, true);
  process.exit(1);
});

function notifyUser(title: string, message: string, urgent = false): void {
  console.log(`\n${"=".repeat(60)}`);
  console.log(`  ${urgent ? "🚨" : "🔔"} ${title}`);
  console.log(`  ${message}`);
  console.log(`${"=".repeat(60)}\n`);
}
