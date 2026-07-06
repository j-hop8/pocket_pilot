# T-001: README roadmap refresh

**Goal:** Move the three shipped roadmap items (smart auto-categorization, budgets,
trips/foreign currency) into the Features section of both READMEs and fix stale
hosting references.

**Files in scope:** README.md, README.zh-TW.md

**Do NOT touch:** app/server code, workflows, any other docs

**Acceptance criteria:**
- [x] Roadmap lists only unshipped items (payment methods, reconciliation, native apps)
- [x] Shipped features described under Features in both languages, matching what landed
      in PRs #12/#13/#14
- [x] zh-TW demo link and both tech-stack Hosting rows say Cloudflare Workers

**Verify:** `curl -sf https://pocketpilot.pocketpilot.workers.dev/ >/dev/null`

**Owner:** claude
