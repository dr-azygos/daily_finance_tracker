# Daily Finance: iPhone Shortcut + Google Sheets version

This version needs no computer and no paid accounts.

A Shortcuts automation on the iPhone sends each bank SMS to `Code.gs`, deployed as a Google Apps Script web app. The script uses the same rules as the iOS app's parser to read the SMS. It adds a row to a **Daily Finance** Google Sheet and replies with a one-line summary, which the Shortcut shows as a notification:

> Spent ₹250 at Swiggy · ₹1,240 today · ₹760 left

The sheet has a **Dashboard** tab: today vs. daily budget (cell B3), this month's spending and income, spending by category with a chart, daily spending for the last 30 days, and recent transactions. If you change a merchant's category in the Transactions tab, the next SMS from that merchant gets the same category. Duplicate SMS are skipped.

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
