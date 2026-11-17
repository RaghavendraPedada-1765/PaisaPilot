# PaisaPilot AI agent - plan

Decided with Raghav on 16 Nov 2026.

## Update: on-phone first

After seeing the API costs (Claude API is billed separately from a Claude subscription), Raghav chose to start
with an **on-phone model**: Gemma 4 E2B (2.6 GB, one-time download) running on the phone's GPU through
`flutter_edge_ai`. It is free and fully private, and works offline. The tools, confirmation cards and memory
below apply unchanged; only the model differs. Claude (sections below) can be added later as an opt-in choice
in Settings.

Phase 1 on the phone was built and tried on 17 Nov 2026. The model ran, but its answers were wrong, so the
on-phone assistant was removed. The read tools (`lib/agent/agent_tools.dart`) stay for a stronger model later;
the Claude sections below are the starting point if the agent comes back.

## Decisions (for the Claude option)

- **Model in the cloud:** Claude through the Claude API, opt-in. This is a deliberate exception to "all user data
  stays on the device": only what a question needs is sent (see Data sent), and the agent is off until it is
  switched on.
- **Jobs:** answer questions about spending, help sort payees, weekly summary, alerts and budgets, and memory.
- **Write access:** yes. Changes to transactions, categories and budgets are shown as a card and applied after
  one tap (Confirm / Decline). The agent writes its own memory without asking; memory is listed and editable in
  Settings.

## How it works

```
Chat screen ──> Agent loop (Dart, in the app) ──HTTPS──> Claude Messages API
                   │  tool_use                                (claude-opus-5-5)
                   ▼
              Local tools ──> drift / SQLite on the phone (exact numbers)
```

- **No Dart SDK exists**, so the app calls `POST https://api.anthropic.com/v1/messages` with the `http`
  package. Headers: `x-api-key`, `anthropic-version: 2026-10-21`, `content-type: application/json`.
- **Agent loop:** send the conversation and tool list. If `stop_reason` is `tool_use`, run every `tool_use`
  block locally and send all `tool_result` blocks back in one user message (`is_error: true` on failure or
  decline). Repeat until `end_turn`. Also handle `max_tokens` and `refusal`.
- **Streaming (SSE)** so answers appear as they are written.
- **Numbers come from SQL, never from the model.** The model picks tools and explains results.
- **Model:** `claude-opus-5-5` ($4 / $20 per million tokens in / out), effort `medium`. Server-side refusal
  fallbacks are on (`fallbacks: "default"`, beta header `server-side-fallback-2026-07-01`). A cheaper model
  (Claude Sonnet 5.5 or Claude Haiku 5.5) can be picked in Settings.
- **Prompt caching:** the tool definitions and fixed system prompt come first and are marked with
  `cache_control`. Things that change (today's date, memory) come after the cache breakpoint.
- **API key:** entered once in Settings and kept in Android's encrypted keystore (flutter_secure_storage), never
  in the code or the database. Billing is on Raghav's Anthropic Console account.

## Tools

Read (run straight away):

| Tool | What it returns |
|---|---|
| `spending_summary` | Totals for a period, grouped by category, payee, account, day or month; spent and received |
| `list_transactions` | Rows matching filters (period, category, payee, account, amount range, direction), sorted, capped at 200 |
| `payee_history` | One payee's transactions, total and usual category |
| `compare_periods` | Two periods side by side, by category |
| `unusual_spending` | Spends far above the payee's or category's usual amount, and likely duplicates |
| `list_categories` / `get_budgets` | Categories, and budgets with this month's progress |

Write (shown as a card; applied only after Confirm):

| Tool | Effect |
|---|---|
| `set_category` | Label transactions or a whole payee |
| `create_category` | New category |
| `set_budget` | Monthly limit for a category or overall |
| `rename_payee` | Friendly display name for a payee |

Memory (no confirmation; visible and editable in Settings):

| Tool | Effect |
|---|---|
| `remember` | Save a fact or preference ("rent is paid to X on the 5th", "count Family as spending") |
| `forget` | Remove a memory |

## Data sent to Claude

- The question, the conversation so far, the saved memories, and the results of the tools the agent calls:
  dates, amounts, payee names, categories and account names.
- Never sent: raw SMS or email text, full account numbers, UPI IDs, photos, or the whole database.
- On the API, Anthropic does not train on this data by default. It is processed and kept by Anthropic for a
  limited time under its commercial terms, which are separate from the claude.ai privacy toggle.

## Storage on the phone (new tables)

- `agent_memory` (id, text, created_at, updated_at)
- `chat_sessions` and `chat_messages` (full API content blocks, so conversations can be continued)
- `budgets` already exists in the schema.

## Build phases

1. **Foundation:** Settings (switch the agent on, API key, model), the Claude client (HTTP, SSE streaming,
   tool loop, errors, retries), the read tools, and a chat screen. Token use shown per conversation.
2. **Acting:** write tools with confirmation cards, memory (table, tools, Settings list), saved conversations.
3. **Budgets and alerts:** budgets screen; unusual-spend and duplicate alerts computed on the phone, with the
   agent explaining them when tapped.
4. **Weekly summary and sorting help:** a summary generated when the app is opened after a week; batch
   category suggestions for unsorted payees, confirmed in one list.
