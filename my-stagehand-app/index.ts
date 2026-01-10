import "dotenv/config";
import { Stagehand } from "@browserbasehq/stagehand";
import * as fs from "fs";
import * as path from "path";

// Task definitions for common workflows
const TASKS = {
  // Research AppLocker documentation
  "applocker-docs": {
    description: "Research Microsoft AppLocker documentation",
    systemPrompt: `You are a security research assistant specializing in Windows AppLocker.
Your goal is to find relevant documentation, best practices, and configuration guidance.
Always extract key technical details, PowerShell commands, and policy configurations.
Save important findings for later reference.`,
    startUrl: "https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/applocker/applocker-overview",
    objective: "Navigate the AppLocker documentation and extract key deployment guidance, policy rule types, and PowerShell commands for managing policies.",
  },

  // Research software publisher information
  "publisher-lookup": {
    description: "Look up software publisher/vendor information",
    systemPrompt: `You are a software verification assistant.
Your goal is to research software publishers, verify their legitimacy, and gather certificate/signing information.
Focus on finding official download sources, publisher certificates, and security reputation.`,
    startUrl: "https://www.google.com",
    objective: null, // Set dynamically based on query
  },

  // Security advisory research
  "security-advisories": {
    description: "Check for security advisories and CVEs",
    systemPrompt: `You are a security analyst researching vulnerabilities and advisories.
Focus on finding CVE details, affected versions, remediation guidance, and patch information.
Prioritize official sources like NVD, Microsoft Security, and vendor advisories.`,
    startUrl: "https://nvd.nist.gov/vuln/search",
    objective: null,
  },

  // LOLBins research
  "lolbins": {
    description: "Research Living Off The Land Binaries",
    systemPrompt: `You are a security researcher specializing in LOLBins (Living Off The Land Binaries).
Your goal is to find information about Windows binaries that can be abused for malicious purposes.
Extract binary names, abuse techniques, detection methods, and mitigation strategies.`,
    startUrl: "https://lolbas-project.github.io/",
    objective: "Browse the LOLBAS project and compile a list of commonly abused Windows binaries with their execution methods and recommended mitigations.",
  },

  // Custom agent mode
  "agent": {
    description: "Run autonomous agent with custom objective",
    systemPrompt: `You are an autonomous web research assistant.
You can navigate websites, fill forms, click buttons, and extract information.
Be thorough and systematic in your research. Save all relevant findings.
If you encounter obstacles, try alternative approaches.`,
    startUrl: null,
    objective: null,
  },
};

interface TaskResult {
  task: string;
  timestamp: string;
  objective: string;
  findings: unknown;
  urls_visited: string[];
}

async function saveResults(results: TaskResult, outputDir: string): Promise<string> {
  const filename = `${results.task}-${Date.now()}.json`;
  const outputPath = path.join(outputDir, filename);

  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  fs.writeFileSync(outputPath, JSON.stringify(results, null, 2));
  return outputPath;
}

async function runTask(taskName: string, customObjective?: string, customUrl?: string) {
  const task = TASKS[taskName as keyof typeof TASKS];
  if (!task) {
    console.error(`Unknown task: ${taskName}`);
    console.log("Available tasks:", Object.keys(TASKS).join(", "));
    process.exit(1);
  }

  console.log(`\n🚀 Starting task: ${task.description}\n`);

  const stagehand = new Stagehand({
    env: "BROWSERBASE",
    verbose: 1,
  });

  await stagehand.init();

  console.log(`📺 Watch live: https://browserbase.com/sessions/${stagehand.browserbaseSessionId}\n`);

  const page = stagehand.context.pages()[0];
  const urlsVisited: string[] = [];

  // Navigate to start URL
  const startUrl = customUrl || task.startUrl || "https://www.google.com";
  await page.goto(startUrl);
  urlsVisited.push(startUrl);

  // Create the agent
  const agent = stagehand.agent({
    systemPrompt: task.systemPrompt,
  });

  // Determine objective
  const objective = customObjective || task.objective || "Explore and extract relevant information from this page.";

  console.log(`🎯 Objective: ${objective}\n`);

  // Execute the agent
  const agentResult = await agent.execute(objective);

  // Extract final findings
  const findings = await stagehand.extract(
    "Extract all key findings, data points, and actionable information from your research."
  );

  const results: TaskResult = {
    task: taskName,
    timestamp: new Date().toISOString(),
    objective,
    findings: {
      agentResult,
      extractedData: findings,
    },
    urls_visited: urlsVisited,
  };

  // Save results
  const outputPath = await saveResults(results, "./results");
  console.log(`\n💾 Results saved to: ${outputPath}`);

  await stagehand.close();
  return results;
}

async function interactiveMode() {
  const stagehand = new Stagehand({
    env: "BROWSERBASE",
    verbose: 1,
  });

  await stagehand.init();

  console.log(`\n🌐 Interactive Stagehand Session`);
  console.log(`📺 Watch live: https://browserbase.com/sessions/${stagehand.browserbaseSessionId}`);
  console.log(`\nThe browser is ready. Use the agent for any task.\n`);

  const agent = stagehand.agent({
    systemPrompt: `You are a versatile web automation assistant.
You can browse websites, fill forms, extract data, and complete complex multi-step tasks.
Be proactive and thorough. If you need clarification, state your assumptions and proceed.
Always summarize what you've accomplished at the end.`,
  });

  // Get objective from command line or use default demo
  const objective = process.argv[3] ||
    "Go to Google and search for 'Windows AppLocker best practices 2024', then summarize the top 3 results.";

  console.log(`🎯 Executing: ${objective}\n`);

  const result = await agent.execute(objective);
  console.log(`\n✅ Result:`, result);

  await stagehand.close();
}

// CLI interface
async function main() {
  const args = process.argv.slice(2);

  if (args.length === 0 || args[0] === "help" || args[0] === "--help") {
    console.log(`
🎭 Stagehand Browser Automation

Usage:
  npm start <task> [objective] [url]
  npm start interactive [objective]
  npm start help

Available Tasks:
${Object.entries(TASKS).map(([name, task]) => `  ${name.padEnd(20)} - ${task.description}`).join("\n")}

Examples:
  npm start applocker-docs
  npm start lolbins
  npm start publisher-lookup "Find official download for 7-Zip"
  npm start security-advisories "CVE-2024-1234"
  npm start agent "Go to github.com and find the top PowerShell security tools" "https://github.com"
  npm start interactive "Search for Windows Defender exclusions best practices"

Environment Variables (in .env):
  BROWSERBASE_PROJECT_ID  - Your Browserbase project ID
  BROWSERBASE_API_KEY     - Your Browserbase API key
  ANTHROPIC_API_KEY       - Claude API key (recommended)
  OPENAI_API_KEY          - OpenAI API key (alternative)
`);
    process.exit(0);
  }

  const taskName = args[0];

  if (taskName === "interactive") {
    await interactiveMode();
  } else {
    const customObjective = args[1];
    const customUrl = args[2];
    await runTask(taskName, customObjective, customUrl);
  }
}

main().catch((err) => {
  console.error("❌ Error:", err.message);
  process.exit(1);
});
