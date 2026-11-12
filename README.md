# Saathi User Dashboard

Usage dashboard for **Saathi**, built from the Saathi conversation data log (Google Sheet shared in the "Saathi Data logs - Monthly" thread).

Live dashboard (claude.ai; viewers need it shared with them): https://claude.ai/artifact/73fBDwkrxDqgsqgADWM9ce

## Live dashboard page (index.html)

Built from every tab, keeping messages from 25 Oct 2026 onward and removing duplicates (same message id, or same conversation, time, speaker and text). It shows: unique users (click for district and role), repeat visits, the drop-off and MIP funnels, language and voice use, time to onboard / answer / plan, tone and warmth examples, query themes with the exact queries, and insights. Names, emails and long numbers in quoted text are masked. Rebuilt hourly by `scripts/sync.ps1` (`dashboard.ps1` then `build-dashboard.ps1`); data in `data/dashboard-live.json`.

## What it shows

- **Total unique users**: distinct `user_id`s across every tab of the log. Click it to open **district-wise** and **role-wise** tabs.
- **Drop-off funnel** (users): logged in → started onboarding (`mapping_status` = Profile found) → completed onboarding (role and district captured) → started a conversation → received an answer or MIP.
- **Micro Improvement Plan funnel** (conversations, with users): asked a school/classroom challenge → reached goal → reached objectives → generated MIP → MIP downloaded.

Current data (1 Oct – 3 Nov 2026, all 3 tabs): 939 users, 1,543 conversations, 17,094 messages.

## How the numbers are counted

| Step | Rule |
|---|---|
| Unique user | Distinct `user_id` with at least one message |
| Started onboarding | `mapping_status` = "Profile found"; "Profile not found" = dropped at login |
| Completed onboarding | Profile found, role and district captured |
| Started a conversation | Any user message that is not an answer to Saathi's onboarding questions (name, role, school, state, district) |
| Received answer / MIP | A Saathi reply that uses the knowledge base (`chunks`), is 400+ characters, or is an improvement plan |
| MIP steps | Detected from Saathi's fixed wording: "Let me understand… build a plan", "here is your Goal", "Objective", "Here is your Improvement Plan", "ready to download" |
| Downloaded MIP | Saathi offered the plan as a download in a conversation that produced a plan. The logs do not record the actual tap, so this is an upper bound |
| District | Matched to Bihar's 38 districts (plus a few outside Bihar) from Hindi or English input, tolerating small typos; unknown names show as "Unrecognised: …" |

Test and internal accounts are not yet excluded.

## Repository layout

```
dashboard/index.html        Dashboard page (runs inside a claude.ai "Data" artifact; uses its dash/d3 runtime)
scripts/sync.ps1            Finds every tab in the sheet, downloads each (read-only), de-duplicates messages, runs analyze.ps1
scripts/analyze.ps1         Classifies messages into funnel steps and writes the three data files
scripts/upload-prompt.md    Steps Claude follows to upload changed data files to the dashboard
data/saathi-users.csv       One row per user: profile, role group, district, 0/1 per funnel step (no names)
data/saathi-mip-sessions.csv Conversations reaching each MIP step
data/saathi-coverage.csv    Period covered, totals, last refresh time
```

## Sync

1. A Windows scheduled task runs `scripts/sync.ps1` hourly. New tabs are picked up automatically; tabs overlap, so each message is counted once.
2. If the user or MIP files changed, Claude uploads them to the dashboard.

The source Google Sheet is **only read, never modified**.

## Privacy

Only derived data is stored here: user IDs, role groups, districts and 0/1 step flags. Raw logs (names, messages) are excluded by `.gitignore` and must never be committed.
