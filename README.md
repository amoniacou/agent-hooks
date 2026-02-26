# Agent Hook Validator

A pre-commit / post-action hook that uses an AI agent (Claude, Gemini, or Codex) to review your code changes before they land.

When an AI coding assistant (Claude Code, Gemini CLI, Codex CLI) finishes a turn, this hook intercepts the result, runs `git diff` through a second AI reviewer, and either **allows** the change or **blocks** it with actionable feedback.

## How It Works

```
Agent finishes a turn
        │
        ▼
  Hook fires (TaskCompleted / AfterAgent)
        │
        ▼
  git diff HEAD → filter excluded patterns → truncate
        │
        ▼
  Render prompt template (validation.erb)
        │
        ▼
  Pipe prompt to reviewer agent CLI (claude / gemini / codex)
        │
        ▼
  Response starts with "CRITICAL:" ?
       ╱╲
     yes  no
      │    │
      ▼    ▼
   retry  allow
  (block) (pass)
```

**`retry`** feeds the review back to the coding agent so it can fix the issues.
**`allow`** lets the turn through, optionally injecting a review summary.

## Requirements

- Ruby 3.2+
- Bundler
- At least one agent CLI installed:
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`claude`)
  - [Gemini CLI](https://github.com/google-gemini/gemini-cli) (`gemini`)
  - [Codex CLI](https://github.com/openai/codex) (`codex`)
- A git repository

## Installation

```bash
git clone https://github.com/your-org/agent-hooks.git
cd agent-hooks
bundle install
```

### Register the hook automatically

```bash
# Install for Claude Code (writes to .claude/settings.json)
ruby bin/install --target claude

# Install for Gemini CLI (writes to ~/.gemini/settings.json)
ruby bin/install --target gemini

# Install for all supported targets
ruby bin/install --target all

# Use a different agent for reviewing (e.g. Gemini reviews Claude's output)
ruby bin/install --target claude --agent gemini
```

### Install options

```
Usage: install [options]
  --target TARGET       claude | gemini | openai | all  (default: claude)
  --project-dir DIR     Project directory (default: current directory)
  --agent AGENT         Agent for validation: claude | gemini | openai
  -h, --help
```

### Manual configuration

**Claude Code** — add to `.claude/settings.json`:

```json
{
  "hooks": {
    "TaskCompleted": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bundle exec ruby /path/to/agent-hooks/bin/agent-hook-validator -a gemini",
            "timeout": 180
          }
        ]
      }
    ]
  }
}
```

**Gemini CLI** — add to `~/.gemini/settings.json`:

```json
{
  "hooks": {
    "AfterAgent": [
      {
        "name": "agent-hook-validator",
        "type": "command",
        "command": "bundle exec ruby /path/to/agent-hooks/bin/agent-hook-validator -a claude"
      }
    ]
  }
}
```

## Configuration

Configuration is loaded from (in priority order):

1. `--config PATH` CLI flag
2. `AGENT_HOOK_CONFIG` environment variable
3. `config/default.yml`

```yaml
git:
  diff_mode: "head"           # "head" | "cached" | "combined"
  exclude_patterns:           # File patterns to skip (glob syntax)
    - "*.lock"
    - "*.min.js"
    - "vendor/**"

agent:
  name: "gemini"              # Default reviewer agent
  timeout_seconds: 120        # Kill agent after this many seconds

decision:
  block_on_agent_failure: false  # false = fail-open, true = fail-closed
```

### Diff modes

| Mode | Git command | Use case |
|---|---|---|
| `head` | `git diff HEAD` | All uncommitted changes (default) |
| `cached` | `git diff --cached` | Only staged changes |
| `combined` | Both staged + unstaged | Full working tree delta |

## Supported Agents

| Agent name | CLI command | Notes |
|---|---|---|
| `claude` | `claude -p -` | Claude Code headless mode |
| `gemini` | `gemini -p -` | Gemini CLI pipe mode |
| `openai` | `codex exec -` | Codex CLI non-interactive mode |

The agent receives the rendered prompt on stdin and returns its review on stdout.

## Prompt Template

The default template (`templates/validation.erb`) instructs the reviewer to:

- Check for DRY, SOLID, KISS violations
- Detect OWASP Top 10 security vulnerabilities
- Verify test presence and quality (no trivial mocks)
- Apply language-specific guidelines (Ruby, JS/TS) based on changed file extensions
- Only report issues visible in the diff — no speculation
- Cite specific `file:line` for every finding

You can provide a custom template with `--template PATH`. The template has access to two variables:
- `diff` — the git diff string
- `changed_files` — array of changed file paths

## CLI Usage

```
Usage: agent-hook-validator [options]
  -a, --agent NAME      Agent name (claude, openai, gemini)
  -t, --template PATH   Path to ERB template
  -c, --config PATH     Path to YAML config file
  -h, --help
```

The validator reads a JSON payload from stdin and writes a JSON decision to stdout:

```json
{"decision": "allow", "systemMessage": "Gemini Review Summary:\n\n..."}
```

```json
{"decision": "retry", "reason": "AgentHookValidator (gemini) found issues:\n\nCRITICAL: ..."}
```

## Development

```bash
# Run the full suite (RuboCop + RSpec)
bundle exec rake

# Run specs only
bundle exec rspec

# Run a specific spec file
bundle exec rspec spec/agent_hook_validator/runner_spec.rb

# Lint
bundle exec rubocop
```

## Project Structure

```
├── bin/
│   ├── agent-hook-validator    # Main hook entry point
│   └── install                 # Hook installer
├── config/
│   └── default.yml             # Default configuration
├── lib/
│   ├── agent_hook_validator.rb # Runner (orchestrates the flow)
│   └── agent_hook_validator/
│       ├── agents/             # Claude, Gemini, OpenAI agent adapters
│       ├── agent_factory.rb    # Maps agent name → class
│       ├── config.rb           # YAML config loader with deep-merge
│       ├── errors.rb           # Custom error hierarchy
│       ├── installer.rb        # Writes hooks into agent settings files
│       └── template_renderer.rb
├── templates/
│   └── validation.erb          # Prompt template sent to the reviewer
└── spec/                       # RSpec test suite
```

## License

MIT
