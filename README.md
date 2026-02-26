# Agent Hook Validator

A code review tool that uses an AI agent (Claude, Gemini, or Codex) to review your code changes before they land.

When invoked via a `/validate` slash command inside an AI coding assistant (Claude Code, Gemini CLI), this tool runs `git diff` through a second AI reviewer and reports issues with actionable feedback.

## How It Works

```
You type /validate gemini
        │
        ▼
  git diff HEAD → filter excluded patterns
        │
        ▼
  Render prompt template (validation.erb)
        │
        ▼
  Pipe prompt to reviewer agent CLI (claude / gemini / codex)
        │
        ▼
  Parse response → block or allow
```

## Requirements

- Ruby 3.2+
- At least one agent CLI installed:
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`claude`)
  - [Gemini CLI](https://github.com/google-gemini/gemini-cli) (`gemini`)
  - [Codex CLI](https://github.com/openai/codex) (`codex`)
- A git repository

## Installation

```bash
gem install agent_hook_validator
```

Or add to your Gemfile:

```ruby
gem 'agent_hook_validator'
```

### Register the /validate command

```bash
# Install for Claude Code (copies to .claude/commands/)
agent-hook-install --target claude

# Install for Gemini CLI (copies to ~/.gemini/commands/)
agent-hook-install --target gemini

# Install for all supported targets
agent-hook-install --target all
```

### Usage

Inside Claude Code:

```
/validate gemini
```

Inside Gemini CLI:

```
/validate claude
```

The argument is the name of the reviewer agent. For example, use `gemini` to have Gemini review Claude's output, or `claude` to have Claude review Gemini's output.

### Install options

```
Usage: agent-hook-install [options]
  --target TARGET       claude | gemini | openai | all  (default: claude)
  --project-dir DIR     Project directory (default: current directory)
  -h, --help
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
  min_quality_score: 9           # Quality score threshold (1-10)
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
  -a, --agent NAME      Agent name(s), comma-separated (e.g. gemini,claude)
  -t, --template PATH   Path to ERB template
  -c, --config PATH     Path to YAML config file
  -v, --verbose         Print diagnostic messages to stderr
  -h, --help
```

### Multi-agent mode

Run multiple reviewers in parallel via CLI:

```bash
agent-hook-validator -a gemini,claude
```

Or configure in YAML:

```yaml
agents:
  - name: claude
    timeout_seconds: 120
  - name: gemini
    timeout_seconds: 600
```

When multiple agents are used, each runs in parallel and results are merged. If any agent blocks, the overall decision is `block`.

The validator reads a JSON payload from stdin and writes a JSON decision to stdout:

```json
{"decision": "allow", "systemMessage": "Gemini Review Summary:\n\n..."}
```

```json
{"decision": "block", "reason": "AgentHookValidator (gemini) found issues:\n\nCRITICAL: ..."}
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
│   ├── agent-hook-validator    # Main CLI entry point
│   └── agent-hook-install      # Slash command installer
├── commands/
│   ├── claude/
│   │   └── validate.md         # Claude Code /validate command
│   └── gemini/
│       └── validate.toml       # Gemini CLI /validate command
├── config/
│   └── default.yml             # Default configuration
├── lib/
│   ├── agent_hook_validator.rb # Runner (orchestrates the flow)
│   └── agent_hook_validator/
│       ├── agents/             # Claude, Gemini, OpenAI agent adapters
│       ├── agent_factory.rb    # Maps agent name → class
│       ├── config.rb           # YAML config loader with deep-merge
│       ├── errors.rb           # Custom error hierarchy
│       ├── installer.rb        # Copies slash commands into agent config dirs
│       ├── version.rb          # Gem version
│       └── template_renderer.rb
├── templates/
│   └── validation.erb          # Prompt template sent to the reviewer
└── spec/                       # RSpec test suite
```

## License

MIT
