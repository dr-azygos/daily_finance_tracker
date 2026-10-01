# Daily Finance Tracker (iOS)

An iPhone app that logs your daily spending from the transaction SMS your bank sends. It's built for Indian bank, card and UPI alerts, and shows amounts in ₹.

- **Automatic logging.** A bank SMS like "Sent Rs.250.00 From HDFC Bank A/C \*1234 To SWIGGY…" gets saved as an expense of **₹250 at Swiggy** under **Food & Dining**.
- **Today screen.** Shows what you've spent today against a daily budget, this month's spending and income, a breakdown by category, and recent transactions.
- **History.** Transactions are grouped by day. You can search them, filter them, swipe to delete, and tap one to edit it.
- **Insights.** Daily spending chart with your budget line, spending by category, and top merchants (7 days / 30 days / this month).
- **It learns from your corrections.** If you change a merchant's category once, later SMS from that merchant get the new category.
- **Duplicate protection.** The same SMS, or the same UPI reference number, is never logged twice.
- **Siri.** Ask "How much did I spend today in Daily Finance".
- **CSV export** for Numbers, Excel or Google Sheets.
- **Private.** No account, no server, no network access. All data stays on your iPhone in SwiftData.

## Why it needs a Shortcuts automation

Apple doesn't let any App Store app read your SMS inbox. The supported way is a **personal automation in the Shortcuts app**: when a message arrives that contains a word like *debited*, Shortcuts passes its text to the app's **Log Bank SMS** action. Once that's set up, logging happens in the background with no taps. You can also paste an SMS by hand or add an expense manually.

## Build and install

You need a Mac with **Xcode 16 or later** and an iPhone on **iOS 17 or later**.

1. Open `DailyFinanceTracker.xcodeproj` in Xcode.
2. Select the **DailyFinanceTracker** target → **Signing & Capabilities**. Choose your **Team** (a free Apple ID works) and change the **Bundle Identifier** to something unique, e.g. `com.yourname.DailyFinanceTracker`.
3. Connect your iPhone, pick it as the run destination, and press **Run** (⌘R).
4. With a free Apple ID: on the iPhone, go to Settings → General → VPN & Device Management and trust your developer certificate. Apps signed this way expire after 7 days; reinstall from Xcode to renew. A paid developer account avoids this.

To run the parser tests, press ⌘U.

## Set up automatic SMS logging (one time, about 2 minutes)

The app shows these steps on first launch, and later under Settings → Set up SMS logging.

1. Open the **Shortcuts** app → **Automation** tab → **+**.
2. Choose **Message**. Under **Message Contains**, type `debited`. Leave Sender empty.
3. Select **Run Immediately** and turn off **Notify When Run** → **Next**.
4. **New Blank Automation** → **Add Action** → search for **Log Bank SMS** → add it.
5. Tap the **Message** field → **Shortcut Input** → tap it again → **Content** → **Done**.
6. Make the same automation for `credited`, `spent` and `sent`. Overlap is fine because duplicates are ignored.

From then on, each bank SMS is logged when it arrives, and a notification tells you how much you've spent today and how much budget is left.

## Supported SMS formats

The parser (`DailyFinanceTracker/Parsing/BankSMSParser.swift`) uses flexible rules instead of a fixed template for each bank. It has been tested on HDFC, SBI, ICICI, Axis, Kotak and Federal Bank formats, and it recognises about 20 other banks, including South Indian Bank, Canara, CSB, Kerala Gramin and ESAF. It finds:

- the amount (`Rs.`, `INR`, `₹`, Indian comma grouping such as `1,20,000`), while ignoring "Avl Bal" and "Avl Limit"
- whether it's a debit or a credit ("credit card" alone doesn't count as a credit)
- the merchant or payee (from `To …`, `At …`, `VPA …`, `UPI/P2M/…/Name`, `NEFT-…`)
- the bank, the last 4 digits of the account or card, the UPI/reference number, and the date

It ignores OTPs, loan offers, payment-due reminders, "will be debited" notices, collect requests and declined or failed transactions.

If one of your bank's SMS isn't read correctly, paste it into **Settings → Set up SMS logging → Try the reader** to see what was picked up. To fix it, add the SMS as a new case in `DailyFinanceTrackerTests/BankSMSParserTests.swift` and adjust the parser.

## Project layout

```
DailyFinanceTracker/
  DailyFinanceTrackerApp.swift     App entry, SwiftData container
  Models/                          BankTransaction, MerchantRule, categories
  Parsing/                         BankSMSParser, CategoryClassifier
  Services/                        TransactionStore (save + dedupe), notifications, ₹ formatting
  Intents/                         "Log Bank SMS" + "Today's Spending" App Intents (Shortcuts/Siri)
  Views/                           Today, History, Insights, Settings, Add, Detail, Setup guide
DailyFinanceTrackerTests/          Parser unit tests with real-world SMS samples
```
