---
name: gws-sheets-verify
description: "Visual feedback loop for Google Sheets operations. After any write, take a Playwright screenshot and verify data integrity, sort order, and formatting."
paths: ".claude/skills/**,scripts/**"
---

# Google Sheets — Verify After Write

Claude Code is multimodal — it can see screenshots via the `Read` tool. Use this
to close a visual feedback loop after every Google Sheets write operation.

---

## Verify-After-Write Workflow

**Applies to ALL Google Sheets write operations:** update values, sort, insert/delete
rows, format, borders, batchUpdate.

### Steps

1. **Execute** the Sheets API command (update, batchUpdate, sort, etc.)
2. **Open the sheet** in Playwright:
   ```
   browser_navigate to the spreadsheet URL
   ```
   Use the specific tab URL if working on a named tab (append `#gid=SHEET_ID`).
3. **Wait for render:**
   ```
   browser_wait_for selector=".grid-container" or timeout 5000
   ```
4. **Take screenshot:**
   ```
   browser_take_screenshot (full page or element-specific)
   ```
5. **Read the screenshot** with the `Read` tool to visually inspect.
6. **Apply the Self-Review Checklist** (below).
7. **If issues found:** fix the command, re-execute, re-verify (max 2 cycles).
8. If still broken after 3 cycles, report to user with the screenshot.

### Important Notes

- Maximum 3 total verify cycles (initial + 2 fixes)
- The Playwright browser must be authenticated with Google (session cookies)
- For automated skills (cron), screenshot verification may not be possible —
  use API read-back as fallback

---

## Self-Review Checklist

After reading the screenshot, check:

### Data Integrity

- All columns are still aligned — no column was sorted independently
- Row count matches expected (check against pre-write count)
- No blank rows inserted where data should be
- Cell values match what was written (spot-check a few cells)

### Sort Order

- Rows sorted by the correct field
- All columns within each row moved together (no detached columns)
- **Never sort a single column** — always sort entire rows

### Borders and Formatting

- All data rows have visible horizontal divider lines (top/bottom borders)
- Vertical dividers present between columns where expected
- The **last data row** has correct borders (bulk ops often miss it)
- No broken/missing borders anywhere in the data range
- Number format preserved (currency, percentages, dates)

### Layout

- Headers are intact and not shifted
- Frozen rows/columns still in place
- Column widths haven't collapsed
- No overflow text hiding adjacent cell content

---

## Hard Rules for Google Sheets Operations

### Sorting
- **Sort entire rows, NEVER individual columns** — a sort that moves only one column
  detaches it from the rest of the row, corrupting every record

### Borders
- **Use `copyPaste PASTE_FORMAT`** to apply borders — NEVER `updateBorders`.
  `updateBorders` only sets top/bottom/innerHorizontal for the range; it does NOT
  set per-column `left`/`right` entries, resulting in missing vertical dividers
- **Use generous `endRowIndex` buffer** (+10 or 200) for bulk format operations —
  a fixed `endRowIndex` silently misses the last row when rows are added
- After `insertDimension` at index N, copy format from row N+1 (pushed down) to
  the new row at N
- **Always verify the last data row** has correct borders after any bulk operation

---

## API Read-Back Fallback

When Playwright is unavailable (e.g., cron automation), verify via API:

```bash
# Read back the data range after writing
gws sheets spreadsheets.values get \
  --spreadsheetId SHEET_ID \
  --range "TAB_NAME!A1:G100" \
  --json values
```

Check that:
- Row count matches expected
- Column alignment is intact (each row has the same number of values)
- Sort order is correct (compare key fields across rows)

This catches data issues but NOT formatting. Flag formatting as "unverified"
when using API-only fallback.

---

## Requirements

- [Claude Code](https://claude.ai/code) with multimodal `Read` tool
- [Playwright MCP server](https://github.com/anthropics/claude-code/tree/main/plugins/playwright) for screenshots
- Google Sheets API access (via `gws` CLI, Google Apps Script, or direct API)
- Playwright browser authenticated with Google (for screenshot access)
