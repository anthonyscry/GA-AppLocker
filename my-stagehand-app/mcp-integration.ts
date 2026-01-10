import "dotenv/config";
import * as fs from "fs";
import * as path from "path";
import { execSync } from "child_process";

// ============================================================
// MCP INTEGRATION - Simplified Chrome DevTools MCP workflow
// Direct integration for quick browser testing
// ============================================================

interface MCPResponse {
  success: boolean;
  data?: unknown;
  error?: string;
}

class MCPClient {
  private cwd: string;
  private verbose: boolean;

  constructor(verbose = true) {
    this.cwd = path.resolve(__dirname, "..");
    this.verbose = verbose;
  }

  private log(message: string): void {
    if (this.verbose) {
      console.log(message);
    }
  }

  private call(tool: string, params: Record<string, unknown> = {}): MCPResponse {
    try {
      const paramsJson = JSON.stringify(params);
      this.log(`📡 MCP: ${tool} ${paramsJson}`);

      const result = execSync(
        `mcp-cli call chrome-devtools/${tool} '${paramsJson}'`,
        { encoding: "utf-8", timeout: 60000, cwd: this.cwd }
      );

      this.log(`   ✓ Success`);
      return { success: true, data: result };
    } catch (error) {
      const err = error as Error & { stderr?: string };
      this.log(`   ✗ Error: ${err.message}`);
      return { success: false, error: err.stderr || err.message };
    }
  }

  // ============================================================
  // NAVIGATION
  // ============================================================

  listPages(): MCPResponse {
    return this.call("list_pages");
  }

  newPage(url: string, timeout = 30000): MCPResponse {
    return this.call("new_page", { url, timeout });
  }

  navigate(url: string, timeout = 30000): MCPResponse {
    return this.call("navigate_page", { type: "url", url, timeout });
  }

  back(): MCPResponse {
    return this.call("navigate_page", { type: "back" });
  }

  forward(): MCPResponse {
    return this.call("navigate_page", { type: "forward" });
  }

  reload(ignoreCache = false): MCPResponse {
    return this.call("navigate_page", { type: "reload", ignoreCache });
  }

  selectPage(pageId: string): MCPResponse {
    return this.call("select_page", { pageId });
  }

  closePage(): MCPResponse {
    return this.call("close_page");
  }

  // ============================================================
  // INTERACTIONS
  // ============================================================

  click(uid: string, dblClick = false): MCPResponse {
    return this.call("click", { uid, dblClick });
  }

  fill(uid: string, value: string): MCPResponse {
    return this.call("fill", { uid, value });
  }

  hover(uid: string): MCPResponse {
    return this.call("hover", { uid });
  }

  pressKey(key: string): MCPResponse {
    return this.call("press_key", { key });
  }

  drag(sourceUid: string, targetUid: string): MCPResponse {
    return this.call("drag", { sourceUid, targetUid });
  }

  // ============================================================
  // CONTENT
  // ============================================================

  screenshot(filePath?: string, fullPage = false): MCPResponse {
    const params: Record<string, unknown> = { format: "png" };
    if (filePath) params.filePath = filePath;
    if (fullPage) params.fullPage = fullPage;
    return this.call("take_screenshot", params);
  }

  snapshot(): MCPResponse {
    return this.call("take_snapshot");
  }

  waitFor(text: string, timeout = 30000): MCPResponse {
    return this.call("wait_for", { text, timeout });
  }

  evaluate(fn: string, args?: Array<{ uid: string }>): MCPResponse {
    const params: Record<string, unknown> = { function: fn };
    if (args) params.args = args;
    return this.call("evaluate_script", params);
  }

  // ============================================================
  // DEBUGGING
  // ============================================================

  listConsoleMessages(): MCPResponse {
    return this.call("list_console_messages");
  }

  listNetworkRequests(): MCPResponse {
    return this.call("list_network_requests");
  }

  // ============================================================
  // UTILITY WORKFLOWS
  // ============================================================

  async testUrl(url: string): Promise<void> {
    console.log(`\n${"=".repeat(50)}`);
    console.log(`🧪 Testing URL: ${url}`);
    console.log(`${"=".repeat(50)}\n`);

    // Navigate
    this.navigate(url);
    await this.sleep(3000);

    // Screenshot
    const screenshotDir = path.resolve(__dirname, "screenshots");
    if (!fs.existsSync(screenshotDir)) {
      fs.mkdirSync(screenshotDir, { recursive: true });
    }
    const screenshotPath = path.join(screenshotDir, `test-${Date.now()}.png`);
    this.screenshot(screenshotPath, true);
    console.log(`\n📸 Screenshot saved: ${screenshotPath}`);

    // Get page title
    const titleResult = this.evaluate("() => document.title");
    if (titleResult.success) {
      console.log(`📄 Page title: ${titleResult.data}`);
    }
  }

  async searchGoogle(query: string): Promise<void> {
    console.log(`\n🔍 Searching Google: "${query}"\n`);

    this.navigate("https://www.google.com");
    await this.sleep(2000);

    // Get snapshot to find search box
    const snapshot = this.snapshot();
    console.log("Page snapshot:", String(snapshot.data).substring(0, 500));

    // Type search query using evaluate
    this.evaluate(`() => {
      const input = document.querySelector('textarea[name="q"]') || document.querySelector('input[name="q"]');
      if (input) {
        input.value = "${query.replace(/"/g, '\\"')}";
        input.form?.submit();
      }
    }`);

    await this.sleep(3000);

    // Screenshot results
    const screenshotPath = path.join(__dirname, "screenshots", `search-${Date.now()}.png`);
    this.screenshot(screenshotPath, true);
    console.log(`\n📸 Results screenshot: ${screenshotPath}`);
  }

  async browseAppLockerDocs(): Promise<void> {
    const pages = [
      "https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/applocker-overview",
      "https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/applocker-policies-design-guide",
      "https://learn.microsoft.com/en-us/powershell/module/applocker",
    ];

    console.log(`\n📚 Browsing AppLocker Documentation\n`);

    for (let i = 0; i < pages.length; i++) {
      console.log(`\n--- Page ${i + 1}/${pages.length} ---`);
      await this.testUrl(pages[i]);
      await this.sleep(2000);
    }

    console.log(`\n✅ Completed browsing ${pages.length} pages`);
  }

  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}

// ============================================================
// CLI
// ============================================================

async function main() {
  const args = process.argv.slice(2);
  const command = args[0] || "help";
  const client = new MCPClient();

  switch (command) {
    case "list":
      console.log("📋 Current Pages:");
      console.log(client.listPages().data);
      break;

    case "new":
      const newUrl = args[1] || "https://www.google.com";
      client.newPage(newUrl);
      break;

    case "goto":
      const gotoUrl = args[1];
      if (!gotoUrl) {
        console.error("Usage: npm run mcp-test goto <url>");
        return;
      }
      client.navigate(gotoUrl);
      break;

    case "test":
      const testUrl = args[1] || "https://www.google.com";
      await client.testUrl(testUrl);
      break;

    case "search":
      const query = args.slice(1).join(" ") || "Windows AppLocker best practices";
      await client.searchGoogle(query);
      break;

    case "applocker":
      await client.browseAppLockerDocs();
      break;

    case "screenshot":
      const ssDir = path.resolve(__dirname, "screenshots");
      if (!fs.existsSync(ssDir)) {
        fs.mkdirSync(ssDir, { recursive: true });
      }
      const ssPath = path.join(ssDir, `manual-${Date.now()}.png`);
      client.screenshot(ssPath, true);
      console.log(`📸 Screenshot saved: ${ssPath}`);
      break;

    case "snapshot":
      console.log("📄 Page Snapshot:");
      const snapshotResult = client.snapshot();
      console.log(String(snapshotResult.data).substring(0, 2000));
      break;

    case "eval":
      const script = args.slice(1).join(" ") || "() => document.title";
      const evalResult = client.evaluate(script);
      console.log("Result:", evalResult.data);
      break;

    case "help":
    default:
      console.log(`
MCP INTEGRATION - Chrome DevTools MCP Client

Usage:
  npm run mcp-test <command> [args]

Commands:
  list              List all open pages
  new [url]         Open new page (default: google.com)
  goto <url>        Navigate current page to URL
  test [url]        Test URL with screenshot
  search <query>    Google search
  applocker         Browse AppLocker documentation
  screenshot        Take screenshot of current page
  snapshot          Get page content snapshot
  eval <script>     Evaluate JavaScript

Examples:
  npm run mcp-test list
  npm run mcp-test test https://github.com
  npm run mcp-test search "AppLocker publisher rules"
  npm run mcp-test applocker
  npm run mcp-test eval "() => document.title"
      `);
  }
}

main().catch(console.error);
