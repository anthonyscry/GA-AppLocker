# Unified Browser Automation - MCP + Playwright + Stagehand

Streamlined browser automation framework integrating Chrome DevTools MCP, Playwright, and Stagehand for long-running autonomous testing sessions.

## Quick Start

```bash
# Install dependencies
cd my-stagehand-app
npm install

# For Playwright tests (requires Chrome installed)
npx playwright install chromium
```

## Usage Modes

### 1. MCP Integration (Direct Chrome Control)

Uses Chrome DevTools MCP for direct browser control. **Requires Chrome browser running.**

```bash
# List open pages
npm run mcp-test list

# Test a URL with screenshot
npm run mcp-test test https://github.com

# Google search
npm run mcp-test search "AppLocker publisher rules"

# Browse AppLocker documentation
npm run mcp-test applocker

# Take screenshot
npm run mcp-test screenshot

# Execute JavaScript
npm run mcp-test eval "() => document.title"
```

### 2. Autonomous Runner (Long-Running Sessions)

Runs continuously for 20-30 minutes with automatic notifications when input is needed.

```bash
# Run AppLocker docs test suite (25 min default)
npm run test:auto

# Run specific suite for custom duration
npm run test:auto lolbins 30    # LOLBins research for 30 min
npm run test:auto security 20   # Security news for 20 min
npm run test:auto smoke 5       # Quick smoke test for 5 min
```

**Available Test Suites:**
- `applocker` - AppLocker documentation tests (default)
- `lolbins` - LOLBins/LOLBAS research
- `security` - Security news monitoring
- `smoke` - Quick connectivity test

### 3. Unified Orchestrator

Combines MCP, Playwright, and Stagehand in a single workflow.

```bash
# MCP mode (requires Chrome)
npm run orchestrate mcp https://example.com

# Playwright mode (requires browser download)
npm run orchestrate playwright https://example.com

# Stagehand mode (requires Browserbase API keys)
npm run orchestrate stagehand https://example.com
```

### 4. Stagehand AI Tasks (Original)

AI-powered browser automation using Browserbase.

```bash
# Research AppLocker documentation
npm start applocker-docs

# Research LOLBins
npm start lolbins

# Look up software publishers
npm start publisher-lookup "Verify 7-Zip publisher"

# Check security advisories
npm start security-advisories "CVE-2024-1234"

# Custom agent task
npm start agent "Find PowerShell security tools" "https://github.com"

# Interactive mode
npm start interactive "Search for Windows Defender best practices"
```

## Notification System

The automation includes a notification hook that alerts you when:
- Keyboard input is required (CAPTCHA, login, etc.)
- Multiple test failures occur
- Runner completes or crashes

**Notifications are sent via:**
- Console output (always)
- Windows toast notifications (if available)
- System sounds for urgent alerts

## Output Files

```
my-stagehand-app/
├── screenshots/           # Captured screenshots
│   ├── test-*.png
│   └── step-*.png
├── results/              # Test results JSON
│   ├── workflow-*.json
│   └── run-*.json
└── .env                  # API keys (copy from .env.example)
```

## Environment Setup

Copy `.env.example` to `.env` and configure:

```bash
# For Stagehand (Browserbase)
BROWSERBASE_PROJECT_ID=your_project_id
BROWSERBASE_API_KEY=your_api_key

# For AI features
ANTHROPIC_API_KEY=your_claude_key
# or
OPENAI_API_KEY=your_openai_key
```

## Integration with GA-AppLocker

This automation framework supports the GA-AppLocker workflow:

1. **Documentation Research** - Automatically browse and screenshot AppLocker docs
2. **LOLBins Research** - Gather information on Living Off The Land binaries
3. **Security Monitoring** - Track Microsoft Security Blog and CISA alerts
4. **Publisher Verification** - Research software publishers for allowlisting

## Workflow for Long Running Sessions

1. Start Chrome browser with remote debugging enabled:
   ```bash
   google-chrome --remote-debugging-port=9222
   ```

2. Launch the autonomous runner:
   ```bash
   npm run test:auto applocker 25
   ```

3. The runner will:
   - Cycle through test URLs every 2-5 minutes
   - Take screenshots automatically
   - Notify you if something needs attention
   - Save results to `./results/`

4. Check back in 25 minutes, review results and screenshots.

## Scripts Reference

| Script | Description |
|--------|-------------|
| `npm start <task>` | Run Stagehand AI task |
| `npm run mcp-test <cmd>` | Direct MCP Chrome control |
| `npm run test:auto [suite] [min]` | Autonomous test runner |
| `npm run orchestrate <mode> [url]` | Unified orchestrator |
| `npm run build` | Compile TypeScript |

## Available Stagehand Tasks

| Task | Description |
|------|-------------|
| `applocker-docs` | Research Microsoft AppLocker documentation |
| `publisher-lookup` | Look up software publisher/vendor information |
| `security-advisories` | Check for security advisories and CVEs |
| `lolbins` | Research Living Off The Land Binaries |
| `agent` | Run autonomous agent with custom objective |
| `interactive` | Interactive mode for ad-hoc tasks |
