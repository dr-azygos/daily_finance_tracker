# Daily Finance — iPhone home-screen app

A small web app that shows the spending your iPhone Shortcut logs from bank SMS into the
**Daily Finance** Google Sheet: monthly total, today's budget, a day-by-day chart, categories
and every transaction. Add it to your home screen and it opens full screen like a native app.

This repository holds **only the app's code**. It contains no transactions, sheet links or keys.
The app fetches your data from your own Google Apps Script with a secret key that is stored
only on your phone.

## Connect it

1. Use the latest `Code.gs` in your Apps Script project, **Save**, choose `setup`, tap **Run**.
2. **Deploy → Manage deployments → ✏️ → Version: New version → Deploy.**
3. Run `setup` once more. The log prints a private **connect link**. Open it on your iPhone in Safari.
4. In Safari tap **Share → Add to Home Screen**.

Keep the connect link private: anyone with it can read your transactions.
To disconnect, tap **Disconnect** at the bottom of the app.
