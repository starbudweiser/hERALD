# AI agent in hERALD (optional)

hERALD can chat with an AI agent about your campaign and about each task of your plan. **It is optional and off by default.** Without it, hERALD looks and works exactly as before.

Turn it on in **Settings → AI agent (optional)**, then **Set up the agent…**.

## What you get

| | |
|---|---|
| **A side panel, always at hand** | "AI agent" button in the header, or "Chat with the agent" in a task. The panel stays open while you work on the plan; switch between the campaign and the selected task. Resizable with the mouse, the window widens if needed. |
| **Live progress** | "Reading: file…", "Searching…", elapsed time and a **Stop** button; the chat scrolls to the latest answer by itself; Return sends, ⇧Return adds a line break. |
| **Task awareness** | Each request carries the task sheet: id, title, date, channel, status, link, notes, drafts in four languages, latest statistics. The plan and the campaign notes are added when they changed. |
| **Proposals you apply in one click** | The agent can propose changes to notes, drafts (fr, en, es, it), status, and an addition to the campaign notes. Each field shows its value **before** and **after** with a checkbox: apply everything, or only your selection. **Undo** puts everything back. |
| **Hard limits** | The agent never publishes, never marks a post "Published" (any such proposal is ignored) and cannot change any other field. |
| **Campaign instructions** | *Edit the campaign → Instructions for the agent*: tone, audience, constraints. Sent with every request. |
| **Quick actions** | Buttons above the input (write the draft, improve the hook, translate, check before publishing, what next?). Edit them in the agent settings: one per line, `Title | instruction`. |
| **Formatted answers** | Headings, lists, quotes, code blocks (with a Copy button), tables and rich text display properly. |
| **Usage and cost** | Under each answer: tokens and cost. At the top of the panel: the running total for the chat and the campaign. The cost is shown in your Mac's currency (euro in France), converted at today's European Central Bank rate (free, no personal data sent) or at a rate you set; offline it stays in dollars. With an API (ChatGPT…), enter the prices in dollars (the providers' unit) per million tokens in the agent settings; without prices, only tokens are shown. With Claude Code, the cost (API equivalent, not billed with a subscription) comes from the agent. |
| **Shared context** | Choose whether drafts, statistics and campaign notes are sent. The task sheet is always sent. |

## Why it shines with a local agent (Claude Code)

- **One session for everything.** All requests go to one named Claude Code session (default name "hERALD"). Resume it any time from the terminal (`claude --resume`, the **Copy the resume command** button gives the exact line) or find it in the Claude app. What you ask in hERALD and what you ask in Claude Code share the same memory.
- **Sub-sessions.** For a long job the agent can open a sub-session and tell hERALD, which links it to the task (shown above the chat, copy button to resume it).
- **It reads your files.** The *working folder* is where the agent may read (videos, scripts, press kit, notes). Pick the folder that holds your campaign material. It is also the project under which the session is listed in Claude Code.
- **Use an existing session.** Paste a session ID in the agent settings to make hERALD use a session you already have instead of creating one.
- **Light mode (default).** Claude Code starts with `--safe-mode`: no MCP servers, skills, hooks or CLAUDE.md. A request then costs about a hundred times fewer tokens (measured: about 7,000 tokens for a minimal request instead of several hundred thousand with a large setup). Untick it if you want the agent to use your whole environment.
- **Safe tools.** The agent can only read files (Read, Glob, Grep) and run the `claude` command (to open sub-sessions). Everything else is denied, with no prompt.

### First use on a Mac: removable volumes

If the working folder is on an external disk, macOS asks once: *"hERALD would like to access files on a removable volume"*. Click **Allow**. The **Test the agent** button in the settings checks the program and the folder access without asking the agent anything, and is the right moment to answer macOS. If access is refused, hERALD explains it and says where to allow it (System Settings, Privacy & Security, Files & Folders, hERALD, Removable Volumes).

## Other agents

| Agent | How | Conversation memory |
|---|---|---|
| **Claude Code** | The `claude` command (found automatically in `~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, or give its path). | In Claude Code's own session. |
| **Any command-line agent (Codex, …)** | A command that reads the question on standard input and writes the answer on standard output, e.g. `codex exec -` (button provided). Runs through your login shell. | hERALD resends the history with each question. |
| **ChatGPT / OpenAI-compatible API** | API address (default `https://api.openai.com/v1/chat/completions`), model name, API key (stored in the macOS keychain). Works with any service or local server that speaks the same format. | hERALD resends the history with each question. |

Only Claude Code gives you sessions you can find again in the agent's own application, and the sub-session feature.

## Privacy

Everything stays on your Mac. The only thing sent anywhere is your question and the context you chose to share, to the agent you chose. Conversations are stored in your plan file (`plan.json`), so they are also in a plan you export: use **Clear** in a chat to remove one before sharing a plan.
