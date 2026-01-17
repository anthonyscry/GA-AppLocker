# GA-AppLocker Architecture Decision Records

---

## ADR-001: Module Structure

**Date:** 2026-01-17
**Status:** Accepted

### Context
Need to organize code into logical modules that follow PowerShell best practices.

### Decision
Use nested modules with clear separation of concerns:
- Core: No dependencies, provides logging/config/utilities
- Discovery: Depends on Core
- Credentials: Depends on Core
- Scanning: Depends on Core, Discovery, Credentials
- Rules: Depends on Core, Scanning
- Policy: Depends on Core, Rules

### Consequences
- Clear dependency chain
- Modules can be tested independently
- Core module can be reused in other projects

---

## ADR-002: Error Handling Pattern

**Date:** 2026-01-17
**Status:** Accepted

### Context
Need consistent error handling across all functions.

### Decision
All functions return a result object with standard structure:
```powershell
@{
    Success = $false
    Data    = $null
    Error   = $null
}
```

### Consequences
- Predictable return values
- Easy to check for success/failure
- Error messages always available
- Works well with pipeline

---

## ADR-003: Configuration Storage

**Date:** 2026-01-17
**Status:** Accepted

### Context
Need to persist user settings between sessions.

### Decision
Store configuration as JSON in `%LOCALAPPDATA%\GA-AppLocker\Settings\settings.json`

### Consequences
- Human-readable format
- Easy to backup/restore
- Native PowerShell support via ConvertTo/From-Json
- Per-user settings (not machine-wide)

---

## ADR-004: Logging Strategy

**Date:** 2026-01-17
**Status:** Accepted

### Context
Need comprehensive logging for troubleshooting.

### Decision
- Daily log files: `GA-AppLocker_YYYY-MM-DD.log`
- Four levels: Info, Warning, Error, Debug
- Log to both file and console (console can be suppressed)
- Include timestamp with each entry

### Consequences
- Easy to find logs by date
- Automatic log rotation (by day)
- Can grep logs for specific dates/errors
- Console output helps during development

---

## ADR-005: WPF Theme

**Date:** 2026-01-17
**Status:** Accepted

### Context
Need a professional, modern UI appearance.

### Decision
Dark theme with:
- Background: #1E1E1E
- Sidebar: #252526
- Content: #2D2D30
- Primary accent: #0078D4 (Microsoft blue)
- Success/Warning/Error colors for status

### Consequences
- Modern appearance
- Reduced eye strain for long sessions
- Consistent with VS Code / Windows Terminal aesthetic
- Clear visual hierarchy

---

## ADR-006: Function Size Limit

**Date:** 2026-01-17
**Status:** Accepted

### Context
From spec: "Functions < 30 lines"

### Decision
Enforce 30-line limit for all functions. If a function exceeds this, extract helper functions.

### Consequences
- More maintainable code
- Single responsibility per function
- Easier to test
- More readable

---

## ADR-007: Naming Conventions

**Date:** 2026-01-17
**Status:** Accepted

### Context
Need consistent naming across entire codebase.

### Decision
- Functions: `Verb-Noun` (approved PowerShell verbs)
- Variables: `$camelCase`
- Constants: `$UPPER_SNAKE`
- Parameters: `-PascalCase`
- Private functions: No export, still use Verb-Noun

### Consequences
- Predictable naming
- Easy to identify function purpose
- Follows PowerShell conventions
- IDE autocomplete works well
