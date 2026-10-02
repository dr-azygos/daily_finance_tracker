# Daily Finance: iPhone Shortcut + Google Sheets version

This version needs no computer and no paid accounts.

A Shortcuts automation on the iPhone sends each bank SMS to `Code.gs`, deployed as a Google Apps Script web app. The script uses the same rules as the iOS app's parser to read the SMS. It adds a row to a **Daily Finance** Google Sheet and replies with a one-line summary, which the Shortcut shows as a notification:

> Spent ₹250 at Swiggy · ₹1,240 today · ₹760 left

Each month gets its own tab (`Oct 2026`, `Nov 2026`, …), created automatically with the first SMS of the month. An older SMS pasted in later goes to its own month's tab. The **Dashboard** tab shows today vs. the daily budget (B4), the selected month's spending and income, a category chart, day-by-day spending and recent transactions. Pick an earlier month in B3 to look back. If you change a merchant's category in a month tab, the next SMS from that merchant gets the same category. Duplicate SMS are skipped. Credit card bill payments (CRED, "card bill") are logged as `Card Bill Payment` with type `Transfer` and left out of spending totals, since the card purchases are already counted. Merchant order receipts ("Your Swiggy Order #…") are ignored in favour of the bank's own SMS. Rows in the `Rent` category count towards the month's total but are left out of today's spending, the daily budget, the 7-day total and the day-by-day chart. Promotional and reminder SMS (offers, cashback-up-to, recharge/plan expiry, bill generated, loan/limit offers) are ignored, and an SMS must mention an account, card, UPI/IMPS/NEFT, reference or bank to be logged, so triggering the automation on `Rs`, `INR` and `₹` is safe.

Sheets created with the earlier single-tab layout (one "Transactions" tab) are upgraded on the next `setup` run or SMS: rows move into month tabs and the budget is kept.

**Updating the script:** paste the new `Code.gs`, save, run `setup` once, then Deploy → Manage deployments → edit → Version: New version → Deploy. The web app URL does not change.

## Setup (all on iPhone, about 15 minutes)

**1. Google sheet**
1. In Safari, open script.google.com. Tap **aA** → **Request Desktop Website** → **New project**.
2. Replace the sample code with the contents of `Code.gs` and save.
3. Pick `setup` in the function menu → **Run** → allow the permissions. The log shows your new sheet's link.
4. **Deploy → New deployment → Web app**. Set Execute as: **Me**, Who has access: **Anyone**. Copy the URL ending in `/exec`, and keep it private.

**2. Shortcut "Log Bank SMS"**
- **Get Contents of URL**: your URL, Method POST, Request Body JSON, Text field `sms` = Shortcut Input.
- **Show Notification**: Contents of URL.

**3. Automations** (Shortcuts → Automation → + → Message)
- Message Contains `debited`, Run Immediately, action **Run Shortcut → Log Bank SMS**, with Input = Shortcut Input → Content.
- Repeat for `credited`, `spent` and `sent`.

Opening the web app URL in a browser shows today's spending. Adding `?sms=<url-encoded SMS>` logs that message.
