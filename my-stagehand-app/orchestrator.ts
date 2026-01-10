import "dotenv/config";
import { Stagehand } from "@browserbasehq/stagehand";
import { chromium, Browser, Page, BrowserContext } from "playwright";
import * as fs from "fs";
import * as path from "path";
import { spawn, execSync } from "child_process";

// ============================================================
// UNIFIED ORCHESTRATOR - MCP + Playwright + Stagehand
// Streamlined workflow for browser automation testing
// ============================================================

interface OrchestratorConfig {
  mode: "mcp" | "playwright" | "stagehand" | "hybrid";
  timeout: number;
  screenshotsDir: string;
  resultsDir: string;
  notifyOnInput: boolean;
  headless: boolean;
}

interface TestStep {
  action: "navigate" | "click" | "fill" | "extract" | "screenshot" | "wait" | "evaluate" | "notify";
  target?: string;
  value?: string;
  timeout?: number;
  description?: string;
}

interface TestResult {
  step: number;
  action: string;
  success: boolean;
  duration: number;
  error?: string;
  data?: unknown;
}

// ============================================================
// NOTIFICATION SYSTEM - Alert when input needed
// ============================================================

class NotificationSystem {
  private static instance: NotificationSystem;

  static getInstance(): NotificationSystem {
    if (!NotificationSystem.instance) {
      NotificationSystem.instance = new NotificationSystem();
    }
    return NotificationSystem.instance;
  }

  async notify(title: string, message: string, urgent = false): Promise<void> {
    console.log(`\n${"=".repeat(60)}`);
    console.log(`🔔 ${urgent ? "URGENT " : ""}NOTIFICATION: ${title}`);
    console.log(`📢 ${message}`);
    console.log(`${"=".repeat(60)}\n`);

    // Try system notification
    try {
      if (process.platform === "linux") {
        execSync(`notify-send "${title}" "${message}" ${urgent ? "-u critical" : ""} 2>/dev/null || true`);
      } else if (process.platform === "darwin") {
        execSync(`osascript -e 'display notification "${message}" with title "${title}"' 2>/dev/null || true`);
      }
    } catch {
      // Fallback to console only
    }

    // Play audio alert for urgent notifications
    if (urgent) {
      try {
        if (process.platform === "linux") {
          execSync("paplay /usr/share/sounds/freedesktop/stereo/bell.oga 2>/dev/null || true");
        }
      } catch {
        // No audio available
      }
    }
  }

  async alertKeyboardNeeded(context: string): Promise<void> {
    await this.notify(
      "🎹 KEYBOARD INPUT NEEDED",
      `${context}\nPlease check the browser and provide input.`,
      true
    );
  }
}

// ============================================================
// MCP INTEGRATION - Chrome DevTools MCP Bridge
// ============================================================

class MCPBridge {
  private workingDir: string;

  constructor() {
    this.workingDir = process.cwd();
  }

  private runMcpCommand(command: string): string {
    try {
      const result = execSync(command, {
        cwd: path.resolve(this.workingDir, ".."),
        encoding: "utf-8",
        timeout: 30000,
      });
      return result;
    } catch (error) {
      const err = error as Error & { stderr?: string };
      console.error(`MCP command failed: ${err.message}`);
      return err.stderr || "";
    }
  }

  async listPages(): Promise<string> {
    return this.runMcpCommand(`mcp-cli call chrome-devtools/list_pages '{}'`);
  }

  async newPage(url: string, timeout = 30000): Promise<string> {
    const params = JSON.stringify({ url, timeout });
    return this.runMcpCommand(`mcp-cli call chrome-devtools/new_page '${params}'`);
  }

  async navigate(url: string, timeout = 30000): Promise<string> {
    const params = JSON.stringify({ type: "url", url, timeout });
    return this.runMcpCommand(`mcp-cli call chrome-devtools/navigate_page '${params}'`);
  }

  async takeScreenshot(filePath?: string): Promise<string> {
    const params = filePath
      ? JSON.stringify({ format: "png", filePath })
      : JSON.stringify({ format: "png" });
    return this.runMcpCommand(`mcp-cli call chrome-devtools/take_screenshot '${params}'`);
  }

  async waitFor(text: string, timeout = 30000): Promise<string> {
    const params = JSON.stringify({ text, timeout });
    return this.runMcpCommand(`mcp-cli call chrome-devtools/wait_for '${params}'`);
  }

  async click(uid: string): Promise<string> {
    const params = JSON.stringify({ uid });
    return this.runMcpCommand(`mcp-cli call chrome-devtools/click '${params}'`);
  }

  async fill(uid: string, value: string): Promise<string> {
    const params = JSON.stringify({ uid, value });
    return this.runMcpCommand(`mcp-cli call chrome-devtools/fill '${params}'`);
  }

  async evaluate(script: string): Promise<string> {
    const params = JSON.stringify({ function: script });
    return this.runMcpCommand(`mcp-cli call chrome-devtools/evaluate_script '${params}'`);
  }

  async getSnapshot(): Promise<string> {
    return this.runMcpCommand(`mcp-cli call chrome-devtools/take_snapshot '{}'`);
  }
}

// ============================================================
// PLAYWRIGHT RUNNER - Direct browser automation
// ============================================================

class PlaywrightRunner {
  private browser: Browser | null = null;
  private context: BrowserContext | null = null;
  private page: Page | null = null;
  private headless: boolean;

  constructor(headless = true) {
    this.headless = headless;
  }

  async init(): Promise<void> {
    this.browser = await chromium.launch({
      headless: this.headless,
      args: ["--no-sandbox", "--disable-dev-shm-usage"],
    });
    this.context = await this.browser.newContext();
    this.page = await this.context.newPage();
    console.log("🎭 Playwright browser initialized");
  }

  async navigate(url: string): Promise<void> {
    if (!this.page) throw new Error("Browser not initialized");
    await this.page.goto(url, { waitUntil: "networkidle" });
  }

  async click(selector: string): Promise<void> {
    if (!this.page) throw new Error("Browser not initialized");
    await this.page.click(selector);
  }

  async fill(selector: string, value: string): Promise<void> {
    if (!this.page) throw new Error("Browser not initialized");
    await this.page.fill(selector, value);
  }

  async screenshot(path: string): Promise<void> {
    if (!this.page) throw new Error("Browser not initialized");
    await this.page.screenshot({ path, fullPage: true });
  }

  async waitForText(text: string, timeout = 30000): Promise<void> {
    if (!this.page) throw new Error("Browser not initialized");
    await this.page.waitForSelector(`text=${text}`, { timeout });
  }

  async evaluate<T>(script: string): Promise<T> {
    if (!this.page) throw new Error("Browser not initialized");
    return this.page.evaluate(script) as Promise<T>;
  }

  async getPage(): Promise<Page> {
    if (!this.page) throw new Error("Browser not initialized");
    return this.page;
  }

  async close(): Promise<void> {
    if (this.browser) {
      await this.browser.close();
      this.browser = null;
      this.context = null;
      this.page = null;
    }
  }
}

// ============================================================
// STAGEHAND RUNNER - AI-powered automation
// ============================================================

class StagehandRunner {
  private stagehand: Stagehand | null = null;

  async init(): Promise<string> {
    this.stagehand = new Stagehand({
      env: "BROWSERBASE",
      verbose: 1,
    });
    await this.stagehand.init();
    const sessionId = this.stagehand.browserbaseSessionId || "unknown";
    console.log(`🎭 Stagehand initialized: https://browserbase.com/sessions/${sessionId}`);
    return sessionId;
  }

  async executeAgent(objective: string, systemPrompt?: string): Promise<unknown> {
    if (!this.stagehand) throw new Error("Stagehand not initialized");

    const agent = this.stagehand.agent({
      systemPrompt: systemPrompt || "You are a helpful web automation assistant.",
    });

    return agent.execute(objective);
  }

  async extract(instruction: string): Promise<unknown> {
    if (!this.stagehand) throw new Error("Stagehand not initialized");
    return this.stagehand.extract(instruction);
  }

  async navigate(url: string): Promise<void> {
    if (!this.stagehand) throw new Error("Stagehand not initialized");
    const page = this.stagehand.context.pages()[0];
    await page.goto(url);
  }

  async close(): Promise<void> {
    if (this.stagehand) {
      await this.stagehand.close();
      this.stagehand = null;
    }
  }
}

// ============================================================
// UNIFIED ORCHESTRATOR
// ============================================================

export class Orchestrator {
  private config: OrchestratorConfig;
  private mcp: MCPBridge;
  private playwright: PlaywrightRunner | null = null;
  private stagehand: StagehandRunner | null = null;
  private notifier: NotificationSystem;
  private results: TestResult[] = [];

  constructor(config: Partial<OrchestratorConfig> = {}) {
    this.config = {
      mode: config.mode || "mcp",
      timeout: config.timeout || 30000,
      screenshotsDir: config.screenshotsDir || "./screenshots",
      resultsDir: config.resultsDir || "./results",
      notifyOnInput: config.notifyOnInput !== false,
      headless: config.headless !== false,
    };

    this.mcp = new MCPBridge();
    this.notifier = NotificationSystem.getInstance();

    // Ensure directories exist
    [this.config.screenshotsDir, this.config.resultsDir].forEach(dir => {
      if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }
    });
  }

  async init(): Promise<void> {
    console.log(`\n🚀 Initializing Orchestrator in ${this.config.mode} mode\n`);

    if (this.config.mode === "playwright" || this.config.mode === "hybrid") {
      this.playwright = new PlaywrightRunner(this.config.headless);
      await this.playwright.init();
    }

    if (this.config.mode === "stagehand" || this.config.mode === "hybrid") {
      this.stagehand = new StagehandRunner();
      await this.stagehand.init();
    }

    if (this.config.mode === "mcp") {
      console.log("🔗 MCP Bridge ready - using Chrome DevTools MCP");
    }
  }

  async runStep(step: TestStep): Promise<TestResult> {
    const start = Date.now();
    let result: TestResult = {
      step: this.results.length + 1,
      action: step.action,
      success: false,
      duration: 0,
    };

    console.log(`\n📌 Step ${result.step}: ${step.description || step.action}`);

    try {
      switch (step.action) {
        case "navigate":
          if (this.config.mode === "mcp") {
            await this.mcp.navigate(step.target!, step.timeout);
          } else if (this.playwright) {
            await this.playwright.navigate(step.target!);
          } else if (this.stagehand) {
            await this.stagehand.navigate(step.target!);
          }
          result.success = true;
          break;

        case "click":
          if (this.config.mode === "mcp") {
            await this.mcp.click(step.target!);
          } else if (this.playwright) {
            await this.playwright.click(step.target!);
          }
          result.success = true;
          break;

        case "fill":
          if (this.config.mode === "mcp") {
            await this.mcp.fill(step.target!, step.value!);
          } else if (this.playwright) {
            await this.playwright.fill(step.target!, step.value!);
          }
          result.success = true;
          break;

        case "screenshot":
          const screenshotPath = path.join(
            this.config.screenshotsDir,
            `step-${result.step}-${Date.now()}.png`
          );
          if (this.config.mode === "mcp") {
            await this.mcp.takeScreenshot(screenshotPath);
          } else if (this.playwright) {
            await this.playwright.screenshot(screenshotPath);
          }
          result.success = true;
          result.data = { path: screenshotPath };
          break;

        case "wait":
          if (this.config.mode === "mcp") {
            await this.mcp.waitFor(step.target!, step.timeout);
          } else if (this.playwright) {
            await this.playwright.waitForText(step.target!, step.timeout);
          }
          result.success = true;
          break;

        case "evaluate":
          let evalResult: unknown;
          if (this.config.mode === "mcp") {
            evalResult = await this.mcp.evaluate(step.value!);
          } else if (this.playwright) {
            evalResult = await this.playwright.evaluate(step.value!);
          }
          result.success = true;
          result.data = evalResult;
          break;

        case "extract":
          if (this.stagehand) {
            const extracted = await this.stagehand.extract(step.value!);
            result.success = true;
            result.data = extracted;
          } else {
            throw new Error("Extract requires Stagehand mode");
          }
          break;

        case "notify":
          if (this.config.notifyOnInput) {
            await this.notifier.alertKeyboardNeeded(step.value || "Input needed");
          }
          result.success = true;
          break;

        default:
          throw new Error(`Unknown action: ${step.action}`);
      }

      console.log(`   ✅ Success`);
    } catch (error) {
      const err = error as Error;
      result.error = err.message;
      console.log(`   ❌ Failed: ${err.message}`);

      if (this.config.notifyOnInput) {
        await this.notifier.notify("Step Failed", `${step.action}: ${err.message}`);
      }
    }

    result.duration = Date.now() - start;
    this.results.push(result);
    return result;
  }

  async runWorkflow(steps: TestStep[]): Promise<TestResult[]> {
    console.log(`\n${"=".repeat(60)}`);
    console.log(`🎬 Starting workflow with ${steps.length} steps`);
    console.log(`${"=".repeat(60)}\n`);

    for (const step of steps) {
      await this.runStep(step);
    }

    await this.saveResults();
    return this.results;
  }

  async saveResults(): Promise<string> {
    const filename = `workflow-${Date.now()}.json`;
    const outputPath = path.join(this.config.resultsDir, filename);

    const report = {
      timestamp: new Date().toISOString(),
      mode: this.config.mode,
      totalSteps: this.results.length,
      passed: this.results.filter(r => r.success).length,
      failed: this.results.filter(r => !r.success).length,
      results: this.results,
    };

    fs.writeFileSync(outputPath, JSON.stringify(report, null, 2));
    console.log(`\n💾 Results saved to: ${outputPath}`);
    return outputPath;
  }

  async close(): Promise<void> {
    if (this.playwright) await this.playwright.close();
    if (this.stagehand) await this.stagehand.close();
    console.log("\n🔒 Orchestrator closed");
  }

  // Convenience method for MCP-only quick tests
  async mcpQuickTest(url: string): Promise<void> {
    console.log(`\n🔗 MCP Quick Test: ${url}\n`);

    const pages = await this.mcp.listPages();
    console.log("Current pages:", pages);

    await this.mcp.newPage(url);
    console.log(`Navigated to: ${url}`);

    const screenshotPath = path.join(this.config.screenshotsDir, `mcp-${Date.now()}.png`);
    await this.mcp.takeScreenshot(screenshotPath);
    console.log(`Screenshot saved: ${screenshotPath}`);
  }

  // Convenience method for AI-powered exploration
  async aiExplore(url: string, objective: string): Promise<unknown> {
    if (this.config.mode !== "stagehand" && this.config.mode !== "hybrid") {
      throw new Error("AI exploration requires Stagehand mode");
    }

    console.log(`\n🤖 AI Exploration: ${objective}\n`);
    await this.stagehand!.navigate(url);
    return this.stagehand!.executeAgent(objective);
  }
}

// ============================================================
// CLI INTERFACE
// ============================================================

async function main() {
  const args = process.argv.slice(2);
  const mode = (args[0] as OrchestratorConfig["mode"]) || "mcp";
  const url = args[1] || "https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/applocker-overview";

  console.log(`
╔══════════════════════════════════════════════════════════════╗
║       UNIFIED ORCHESTRATOR - MCP + Playwright + Stagehand    ║
╚══════════════════════════════════════════════════════════════╝
`);

  const orchestrator = new Orchestrator({
    mode,
    notifyOnInput: true,
    headless: mode === "playwright",
  });

  try {
    await orchestrator.init();

    if (mode === "mcp") {
      // Quick MCP test
      await orchestrator.mcpQuickTest(url);
    } else {
      // Run sample workflow
      const workflow: TestStep[] = [
        { action: "navigate", target: url, description: "Navigate to target URL" },
        { action: "screenshot", description: "Take initial screenshot" },
        { action: "wait", target: "AppLocker", timeout: 10000, description: "Wait for page content" },
        { action: "screenshot", description: "Take final screenshot" },
      ];

      await orchestrator.runWorkflow(workflow);
    }
  } catch (error) {
    const err = error as Error;
    console.error(`\n❌ Error: ${err.message}`);

    const notifier = NotificationSystem.getInstance();
    await notifier.notify("Orchestrator Error", err.message, true);
  } finally {
    await orchestrator.close();
  }
}

main().catch(console.error);
