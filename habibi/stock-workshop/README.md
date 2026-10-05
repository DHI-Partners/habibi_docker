# Stock Workshop

Hands-on documentation for testing the **Stock and Warehouse module** on `erp.habibi-erp.com`. Both files are self-contained HTML — open them by double-clicking, no server and no build step.

| File | What it is |
| --- | --- |
| `stock-role-playbook.html` | Procedure manual. 8 parts, 30 procedures with exact click paths and the ERPNext role each step requires. |
| `stock-shakedown-run.html` | Test card. 8 stages, 40 checks. Tick-box format for verifying the stock flow works end to end. |

Both follow the same fictional scenario — **Habibi Warehouse**, a central distribution hub managing burger buns, patties, and packaging.

Start with the playbook if you are doing the clicking. Use the shakedown run if you are signing off that the module works.

## Notes

- Progress is stored per-browser in `localStorage`; the **Reset** button clears it.
- A theme toggle sits bottom-right (Auto / Light / Dark).
- Typefaces load from Google Fonts. Offline they fall back to system fonts and the pages still read fine.
- Content is written against this instance specifically: company `Habibi Burger`, currency KZT.
