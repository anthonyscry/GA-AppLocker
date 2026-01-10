# Stagehand Browser Automation for GA-AppLocker

Autonomous browser automation for security research and AppLocker workflows.

## Setup

```bash
cd my-stagehand-app
npm install
cp .env.example .env
# Add your API keys to .env
```

### Required API Keys

Add to `.env`:
```
BROWSERBASE_PROJECT_ID=your_project_id
BROWSERBASE_API_KEY=your_api_key
ANTHROPIC_API_KEY=your_claude_key   # Recommended
```

Get Browserbase keys at: https://browserbase.com

## Usage

### Pre-built Tasks

Run specialized tasks with zero configuration:

```bash
# Research AppLocker documentation
npm start applocker-docs

# Research LOLBins (Living Off The Land Binaries)
npm start lolbins

# Look up software publisher information
npm start publisher-lookup "Verify 7-Zip publisher certificate"

# Check security advisories
npm start security-advisories "CVE-2024-1234"
```

### Custom Agent Mode

Run any browser task with natural language:

```bash
# Custom objective with custom URL
npm start agent "Find all PowerShell security modules" "https://github.com"

# Interactive mode for ad-hoc tasks
npm start interactive "Search for Windows Defender exclusion best practices"
```

### Examples for AppLocker Workflows

```bash
# Research software before adding to whitelist
npm start publisher-lookup "Adobe Acrobat Reader official publisher"

# Find AppLocker GPO configuration guides
npm start agent "Find step-by-step AppLocker GPO deployment guide" "https://learn.microsoft.com"

# Research blocked application
npm start agent "Find information about mshta.exe security risks"

# Check if software has known vulnerabilities
npm start security-advisories "7-Zip vulnerabilities 2024"
```

## Available Tasks

| Task | Description |
|------|-------------|
| `applocker-docs` | Research Microsoft AppLocker documentation |
| `publisher-lookup` | Look up software publisher/vendor information |
| `security-advisories` | Check for security advisories and CVEs |
| `lolbins` | Research Living Off The Land Binaries |
| `agent` | Run autonomous agent with custom objective |
| `interactive` | Interactive mode for ad-hoc tasks |

## Output

Results are saved to `./results/` as JSON files with:
- Task name and timestamp
- Objective executed
- Extracted findings
- URLs visited

## How It Works

1. **Browserbase** provides cloud browser infrastructure
2. **Stagehand** controls the browser with AI
3. **Claude/GPT** interprets objectives and navigates autonomously
4. **Results** are extracted and saved locally

The agent can:
- Navigate websites and click elements
- Fill forms and submit searches
- Extract structured data from pages
- Handle multi-step workflows
- Overcome obstacles and try alternatives
