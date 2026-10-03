/**
 * Daily Finance — Google Sheets backend for an iPhone Shortcut.
 *
 * An iPhone Shortcuts automation sends every bank SMS here. This script reads the
 * amount, merchant, bank etc., adds a row to that month's tab ("Oct 2026", "Nov 2026"…)
 * and replies with a one-line summary ("Spent ₹250 at Swiggy · ₹1,240 today · ₹760 left")
 * that the Shortcut shows as a notification. A new tab is created automatically for
 * each month. The "Dashboard" tab totals up any month you pick.
 *
 * Setup: paste this whole file into a new Apps Script project, run `setup` once,
 * then Deploy → New deployment → Web app (Execute as: Me, Who has access: Anyone).
 * After pasting a newer version, run `setup` again and deploy a New version.
 */

const DASH_SHEET = 'Dashboard';
const OLD_TX_SHEET = 'Transactions'; // single-tab layout used before monthly tabs
const HEADERS = ['Date', 'Type', 'Amount', 'Merchant', 'Category', 'Bank', 'Account', 'Reference', 'SMS'];
const BUDGET_CELL = 'B4';
const MONTH_PICKER_CELL = 'B3';
const LAYOUT_VERSION = 'monthly-3';
const MONTH_NAMES = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const MONEY_FORMAT = '[>=10000000]"₹"#\\,##\\,##\\,##0;[>=100000]"₹"#\\,##\\,##0;"₹"#,##0';
const CATEGORIES = ['Food & Dining', 'Groceries', 'Transport', 'Fuel', 'Shopping', 'Bills & Recharge', 'Health',
  'Entertainment', 'Travel', 'Education', 'Rent', 'Transfers', 'Cash Withdrawal', 'Card Bill Payment', 'Income', 'Other'];
// Paying a credit card bill isn't new spending: the card purchases are already logged.
const CARD_BILL = 'Card Bill Payment';
// Fixed monthly payments: counted in the month's totals but kept out of the daily budget.
const RENT = 'Rent';
// The home-screen app (a separate static site) reads data through this script with a secret key.
const APP_URL = 'https://dr-azygos.github.io/daily-finance-app/';

// ---------------------------------------------------------------------------
// Web app entry points
// ---------------------------------------------------------------------------

/** Called by the Shortcut with the SMS text (JSON {"sms": "..."} or form field sms). */
function doPost(e) {
  let sms = (e && e.parameter && e.parameter.sms) || '';
  if (!sms && e && e.postData && e.postData.contents) {
    try {
      sms = JSON.parse(e.postData.contents).sms || '';
    } catch (err) {
      sms = e.postData.contents;
    }
  }
  // Shortcuts sometimes sends a list or a rich object instead of plain text.
  if (Array.isArray(sms)) sms = sms.join('\n');
  if (sms && typeof sms === 'object') sms = sms.content || sms.text || JSON.stringify(sms);
  return reply_(logSms_(String(sms)));
}

/** Opening the web app URL (or asking Siri via a Shortcut) gives today's summary. */
function doGet(e) {
  const p = (e && e.parameter) || {};
  if (p.key !== undefined) return appData_(p);
  if (p.sms) return reply_(logSms_(String(p.sms)));
  return reply_(todaySummary_());
}

// ---------------------------------------------------------------------------
// Data for the home-screen app
// ---------------------------------------------------------------------------

/** The secret the app must send. Created once; run `setup` to see it. */
function appKey_() {
  const props = PropertiesService.getScriptProperties();
  let key = props.getProperty('APP_KEY');
  if (!key) {
    key = Utilities.getUuid().replace(/-/g, '') + Utilities.getUuid().replace(/-/g, '').slice(0, 8);
    props.setProperty('APP_KEY', key);
  }
  return key;
}

/** JSON: month tabs, the chosen month's rows (plus the month before, for comparison) and the daily budget. */
function appData_(p) {
  if (String(p.key) !== appKey_()) return json_({ error: 'bad_key' });
  if (p.action === 'setCategory') return json_(setCategory_(p));
  const ss = getSpreadsheet_();
  const months = ss.getSheets().map(function (sh) { return sh.getName(); }).filter(isMonthTab_)
    .sort(function (a, b) { return monthIndex_(b) - monthIndex_(a); });
  const month = months.indexOf(String(p.month || '')) >= 0 ? String(p.month) : months[0] || null;
  const prevName = month ? months.filter(function (m) { return monthIndex_(m) === monthIndex_(month) - 1; })[0] : null;
  const budget = Number(ss.getSheetByName(DASH_SHEET).getRange(BUDGET_CELL).getValue()) || 0;
  return json_({
    months: months,
    month: month,
    rows: month ? tabRows_(ss.getSheetByName(month)) : [],
    prevMonth: prevName || null,
    prevRows: prevName ? tabRows_(ss.getSheetByName(prevName)) : [],
    budget: budget,
    monthTotals: months.map(function (name) { return monthTotal_(ss.getSheetByName(name), name); }),
    generatedAt: Date.now(),
  });
}

/** One month's headline numbers for the app's budget chart. */
function monthTotal_(sheet, name) {
  let spent = 0, daily = 0, income = 0;
  tabRows_(sheet).forEach(function (r) {
    if (r[1] === 'Income') income += r[2];
    if (r[1] !== 'Expense' || r[4] === CARD_BILL) return;
    spent += r[2];
    if (r[4] !== RENT) daily += r[2];
  });
  return { month: name, spent: spent, daily: daily, income: income };
}

/**
 * Changes a transaction's category from the app. The row is found by its timestamp and amount,
 * so edits made in the sheet meanwhile (sorting, deleting rows) can't hit the wrong row.
 * With all=1, every non-income payment to the same merchant in that month changes too.
 */
function setCategory_(p) {
  const category = String(p.category || '').trim().slice(0, 40);
  if (!category) return { error: 'no_category' };
  const ss = getSpreadsheet_();
  const name = String(p.month || '');
  const sheet = isMonthTab_(name) ? ss.getSheetByName(name) : null;
  if (!sheet || sheet.getLastRow() < 2) return { error: 'not_found' };

  const lock = LockService.getScriptLock();
  lock.waitLock(15000);
  try {
    const values = sheet.getRange(2, 1, sheet.getLastRow() - 1, HEADERS.length).getValues();
    const ts = Number(p.ts), amount = Number(p.amount);
    const target = values.findIndex(function (r) {
      return r[0] instanceof Date && r[0].getTime() === ts && Math.abs(Number(r[2]) - amount) < 0.005;
    });
    if (target < 0) return { error: 'not_found' };

    const merchant = String(values[target][3]).toLowerCase();
    const rows = [target];
    if (String(p.all) === '1') {
      values.forEach(function (r, i) {
        if (i !== target && String(r[3]).toLowerCase() === merchant && r[1] !== 'Income') rows.push(i);
      });
    }
    rows.forEach(function (i) {
      const r = values[i];
      sheet.getRange(i + 2, 5).setValue(safe_(category));
      // Card bill payments are transfers, not spending; moving out of that category makes them spending again.
      if (r[1] !== 'Income') {
        const type = category === CARD_BILL ? 'Transfer' : (r[1] === 'Transfer' && r[4] === CARD_BILL ? 'Expense' : r[1]);
        if (type !== r[1]) sheet.getRange(i + 2, 2).setValue(type);
      }
    });
    return { ok: true, updated: rows.length };
  } finally {
    lock.releaseLock();
  }
}

function monthIndex_(name) {
  const parts = name.split(' ');
  return Number(parts[1]) * 12 + MONTH_NAMES.indexOf(parts[0]);
}

/** Rows as [epochMs, type, amount, merchant, category, bank, account, reference, sms]. */
function tabRows_(sheet) {
  if (!sheet || sheet.getLastRow() < 2) return [];
  return sheet.getRange(2, 1, sheet.getLastRow() - 1, HEADERS.length).getValues()
    .filter(function (r) { return r[0] instanceof Date && typeof r[2] === 'number'; })
    .map(function (r) {
      return [r[0].getTime(), String(r[1]), r[2], String(r[3]), String(r[4]), String(r[5]), String(r[6]), String(r[7]), String(r[8])];
    });
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}

function reply_(text) {
  return ContentService.createTextOutput(text).setMimeType(ContentService.MimeType.TEXT);
}

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------

function logSms_(sms) {
  const lock = LockService.getScriptLock();
  lock.waitLock(15000);
  try {
    const now = new Date();
    const text = sms.trim();
    if (!text) {
      return 'Nothing received. The Shortcut sent an empty message: set the automation\'s Input to Shortcut Input › Content.';
    }
    const parsed = parseBankSms(text, now);
    if (!parsed) {
      // Echo what arrived, so a message that should have been logged is easy to spot.
      return 'Not a bank transaction, nothing logged. Received: "' + text.slice(0, 70) + (text.length > 70 ? '…' : '') + '"';
    }

    const ss = getSpreadsheet_();
    // This month's and last month's rows, for duplicate checks and learned categories.
    const rows = monthRows_(ss, previousMonth_(parsed.date)).concat(monthRows_(ss, parsed.date));
    const duplicate = rows.some(function (r) {
      return (parsed.referenceNumber && String(r[7]) === parsed.referenceNumber && Number(r[2]) === parsed.amount) ||
        String(r[8]) === text;
    });
    if (duplicate) return 'Already logged.';

    // Reuse the category you last gave this merchant, so your corrections stick.
    if (parsed.kind === 'debit') {
      for (let i = rows.length - 1; i >= 0; i--) {
        if (String(rows[i][3]).toLowerCase() === parsed.merchant.toLowerCase() && rows[i][1] !== 'Income') {
          parsed.category = String(rows[i][4]);
          break;
        }
      }
    }

    monthSheet_(ss, parsed.date).appendRow([
      parsed.date,
      parsed.kind === 'credit' ? 'Income' : (parsed.category === CARD_BILL ? 'Transfer' : 'Expense'),
      parsed.amount,
      safe_(parsed.merchant),
      parsed.category,
      parsed.bank || '',
      parsed.accountLast4 ? "'" + parsed.accountLast4 : '',
      parsed.referenceNumber ? "'" + parsed.referenceNumber : '',
      safe_(text),
    ]);

    if (parsed.kind === 'credit') {
      return 'Received ' + inr_(parsed.amount) + ' from ' + parsed.merchant;
    }
    if (parsed.category === CARD_BILL) {
      return 'Card bill ' + inr_(parsed.amount) + ' paid via ' + parsed.merchant + ' (not counted as spending) · ' + todaySummary_(true);
    }
    return 'Spent ' + inr_(parsed.amount) + ' at ' + parsed.merchant + ' · ' + todaySummary_(true);
  } finally {
    lock.releaseLock();
  }
}

function todaySummary_(short) {
  const ss = getSpreadsheet_();
  const today = new Date();
  let spent = 0;
  monthRows_(ss, today).forEach(function (r) {
    if (r[1] === 'Expense' && r[4] !== CARD_BILL && r[4] !== RENT && r[0] instanceof Date && sameDay_(r[0], today)) spent += Number(r[2]) || 0;
  });
  const budget = Number(ss.getSheetByName(DASH_SHEET).getRange(BUDGET_CELL).getValue()) || 0;
  let text = short ? inr_(spent) + ' today' : "You've spent " + inr_(spent) + ' today';
  if (budget > 0) {
    text += spent <= budget
      ? (short ? ' · ' + inr_(budget - spent) + ' left' : ', ' + inr_(budget - spent) + ' left of your daily budget.')
      : (short ? ' · ' + inr_(spent - budget) + ' over budget' : ', ' + inr_(spent - budget) + ' over your daily budget.');
  } else if (!short) {
    text += '.';
  }
  return text;
}

/** "Oct 2026". Built by hand (not from the locale) so it always matches the Dashboard formulas. */
function monthName_(date) {
  return MONTH_NAMES[date.getMonth()] + ' ' + date.getFullYear();
}

function previousMonth_(date) {
  return new Date(date.getFullYear(), date.getMonth() - 1, 1);
}

function isMonthTab_(name) {
  return /^(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) \d{4}$/.test(name);
}

/** All rows of a month's tab, or [] if that month has no tab yet. */
function monthRows_(ss, date) {
  const sheet = ss.getSheetByName(monthName_(date));
  if (!sheet || sheet.getLastRow() < 2) return [];
  return sheet.getRange(2, 1, sheet.getLastRow() - 1, HEADERS.length).getValues();
}

/** Stops SMS text that starts with = + - @ from being treated as a formula. */
function safe_(value) {
  return /^[=+\-@]/.test(value) ? "'" + value : value;
}

/** ₹1,20,000.50 style formatting. */
function inr_(value) {
  const fixed = (Math.round(value * 100) / 100).toFixed(2).replace(/\.00$/, '');
  const parts = fixed.split('.');
  let whole = parts[0];
  if (whole.length > 3) {
    const last3 = whole.slice(-3);
    whole = whole.slice(0, -3).replace(/\B(?=(\d{2})+(?!\d))/g, ',') + ',' + last3;
  }
  return '₹' + whole + (parts[1] ? '.' + parts[1] : '');
}

function sameDay_(a, b) {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

// ---------------------------------------------------------------------------
// Spreadsheet setup
// ---------------------------------------------------------------------------

/** Run from the editor after pasting the script. Creates or upgrades the sheet and prints its link. */
function setup() {
  const ss = getSpreadsheet_();
  Logger.log('Your Daily Finance sheet: ' + ss.getUrl());
  const key = appKey_();
  const service = ScriptApp.getService().getUrl();
  if (service && /\/exec$/.test(service)) {
    Logger.log('Open this link on your iPhone to connect the app (keep it private): ' +
      APP_URL + '#connect=' + encodeURIComponent(service) + '&key=' + key);
  } else {
    Logger.log('App key (keep it private): ' + key + '. Deploy the web app, then run setup again to get a one-tap app link.');
  }
  return ss.getUrl();
}

function getSpreadsheet_() {
  const active = SpreadsheetApp.getActiveSpreadsheet && SpreadsheetApp.getActiveSpreadsheet();
  if (active) return ensureLayout_(active);

  const props = PropertiesService.getScriptProperties();
  const id = props.getProperty('SPREADSHEET_ID');
  if (id) {
    try {
      return ensureLayout_(SpreadsheetApp.openById(id));
    } catch (err) {
      // The sheet was deleted; make a new one below.
    }
  }
  const ss = SpreadsheetApp.create('Daily Finance');
  ss.setSpreadsheetTimeZone(Session.getScriptTimeZone());
  props.setProperty('SPREADSHEET_ID', ss.getId());
  return ensureLayout_(ss);
}

/** Builds the monthly layout once, moving rows over from the older single "Transactions" tab. */
function ensureLayout_(ss) {
  const props = PropertiesService.getScriptProperties();
  const key = 'LAYOUT_' + ss.getId();
  if (props.getProperty(key) === LAYOUT_VERSION && ss.getSheetByName(DASH_SHEET)) return ss;

  // Keep the budget from the old Dashboard (it lived in B3 before the month picker was added).
  let budget = 1000;
  const oldDash = ss.getSheetByName(DASH_SHEET);
  if (oldDash) {
    const cell = props.getProperty(key) ? BUDGET_CELL : 'B3';
    const value = oldDash.getRange(cell).getValue();
    if (typeof value === 'number') budget = value;
  }

  const oldTx = ss.getSheetByName(OLD_TX_SHEET);
  if (oldTx) {
    if (oldTx.getLastRow() >= 2) {
      oldTx.getRange(2, 1, oldTx.getLastRow() - 1, HEADERS.length).getValues().forEach(function (r) {
        if (!(r[0] instanceof Date)) return;
        if (IGNORE_RE.test(String(r[8]))) return; // e.g. merchant order receipts logged by older versions
        if (r[1] === 'Expense' && classify_(String(r[3]), 'debit') === CARD_BILL) {
          r[1] = 'Transfer';
          r[4] = CARD_BILL;
        }
        // Keep account and reference numbers as text.
        if (r[6] !== '') r[6] = "'" + r[6];
        if (r[7] !== '') r[7] = "'" + r[7];
        monthSheet_(ss, r[0]).appendRow(r);
      });
    }
    monthSheet_(ss, new Date());
    ss.deleteSheet(oldTx);
  }
  monthSheet_(ss, new Date());

  if (oldDash) ss.deleteSheet(oldDash);
  buildDashboard_(ss, budget);

  const blank = ss.getSheetByName('Sheet1');
  if (blank && blank.getLastRow() === 0 && ss.getSheets().length > 1) ss.deleteSheet(blank);

  refreshMonthPicker_(ss);
  props.setProperty(key, LAYOUT_VERSION);
  return ss;
}

/** The tab for the month `date` falls in, created (newest first, after the Dashboard) if needed. */
function monthSheet_(ss, date) {
  const name = monthName_(date);
  let sheet = ss.getSheetByName(name);
  if (sheet) return sheet;

  // Place it after the Dashboard and before any older month.
  const sheets = ss.getSheets();
  let index = sheets.length;
  const start = new Date(date.getFullYear(), date.getMonth(), 1);
  for (let i = 0; i < sheets.length; i++) {
    const n = sheets[i].getName();
    if (!isMonthTab_(n)) continue;
    const parts = n.split(' ');
    if (new Date(Number(parts[1]), MONTH_NAMES.indexOf(parts[0]), 1) < start) { index = i; break; }
  }
  sheet = ss.insertSheet(name, index);

  sheet.getRange(1, 1, 1, HEADERS.length).setValues([HEADERS]).setFontWeight('bold').setBackground('#e0f2f1');
  sheet.setFrozenRows(1);
  sheet.getRange('A:A').setNumberFormat('dd mmm yyyy, h:mm am/pm');
  sheet.getRange('C:C').setNumberFormat(MONEY_FORMAT);
  sheet.setColumnWidth(1, 160);
  sheet.setColumnWidth(4, 180);
  sheet.setColumnWidth(9, 400);
  sheet.getRange('E2:E').setDataValidation(
    SpreadsheetApp.newDataValidation().requireValueInList(CATEGORIES, true).setAllowInvalid(true).build());

  refreshMonthPicker_(ss);
  return sheet;
}

/** Fills the Dashboard's "Pick another month" dropdown with the month tabs that exist. */
function refreshMonthPicker_(ss) {
  const dash = ss.getSheetByName(DASH_SHEET);
  if (!dash) return;
  const months = ss.getSheets().map(function (sh) { return sh.getName(); }).filter(isMonthTab_);
  if (!months.length) return;
  dash.getRange(MONTH_PICKER_CELL).setDataValidation(
    SpreadsheetApp.newDataValidation().requireValueInList(months, true).setAllowInvalid(false).build());
}

function buildDashboard_(ss, budget) {
  const dash = ss.insertSheet(DASH_SHEET, 0);

  // Month names are built with CHOOSE so they never depend on the sheet's language settings.
  const name = function (dateExpr) {
    return 'CHOOSE(MONTH(' + dateExpr + '),"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec")&" "&YEAR(' + dateExpr + ')';
  };
  const col = function (tabExpr, c) { return 'INDIRECT("\'"&' + tabExpr + '&"\'!' + c + ':' + c + '")'; };
  const block = function (tabExpr, range) { return '{INDIRECT("\'"&' + tabExpr + '&"\'!' + range + '")}'; };
  const CUR = name('TODAY()');
  const PREV = name('EOMONTH(TODAY(),-1)');
  const SEL = '$B$2';
  const spentSince = function (tab, from) {
    return 'IFERROR(SUMIFS(' + col(tab, 'C') + ',' + col(tab, 'B') + ',"Expense",' + col(tab, 'E') + ',"<>' + CARD_BILL + '",' + col(tab, 'E') + ',"<>' + RENT + '",' + col(tab, 'A') + ',">="&' + from + '),0)';
  };

  dash.getRange('A1').setValue('Daily Finance').setFontSize(18).setFontWeight('bold');
  dash.getRange('A2:B10').setValues([
    ['Showing month', '=IF(B3="",' + CUR + ',B3)'],
    ['Pick another month', ''],
    ['Daily budget (edit me)', budget],
    ['', ''],
    ['Spent today (excl. rent)', '=IFERROR(SUMIFS(' + col(CUR, 'C') + ',' + col(CUR, 'B') + ',"Expense",' + col(CUR, 'E') + ',"<>' + CARD_BILL + '",' + col(CUR, 'E') + ',"<>' + RENT + '",' + col(CUR, 'A') + ',">="&TODAY(),' + col(CUR, 'A') + ',"<"&TODAY()+1),0)'],
    ['Left today', '=IF(B4>0,B4-B6,"")'],
    ['="Spent in "&B2', '=IFERROR(SUMIFS(' + col(SEL, 'C') + ',' + col(SEL, 'B') + ',"Expense",' + col(SEL, 'E') + ',"<>' + CARD_BILL + '"),0)'],
    ['="Received in "&B2', '=IFERROR(SUMIFS(' + col(SEL, 'C') + ',' + col(SEL, 'B') + ',"Income"),0)'],
    ['Spent last 7 days (excl. rent)', '=' + spentSince(CUR, 'TODAY()-6') + '+' + spentSince(PREV, 'TODAY()-6')],
  ]);
  dash.getRange('B2').setFontWeight('bold').setFontSize(12);
  dash.getRange('B3').setBackground('#fff8e1').setNote('Choose an earlier month to look back. Clear it to return to this month.');
  dash.getRange('B4').setBackground('#fff8e1').setNumberFormat(MONEY_FORMAT);
  dash.getRange('B6:B10').setNumberFormat(MONEY_FORMAT).setFontWeight('bold');
  dash.getRange('A6:B6').setFontSize(14);

  dash.getRange('A12').setValue('By category').setFontWeight('bold');
  dash.getRange('A13').setFormula('=IFERROR(QUERY(' + block(SEL, 'A2:E') +
    ',"select Col5, sum(Col3) where Col2 = \'Expense\' and Col5 <> \'' + CARD_BILL + '\' group by Col5 order by sum(Col3) desc label Col5 \'Category\', sum(Col3) \'Spent\'",0),"No spending yet")');
  dash.getRange('B14:B40').setNumberFormat(MONEY_FORMAT);

  dash.getRange('D12').setValue('Day by day (excl. rent)').setFontWeight('bold');
  dash.getRange('D13').setFormula('=IFERROR(QUERY(' + block(SEL, 'A2:E') +
    ',"select toDate(Col1), sum(Col3) where Col2 = \'Expense\' and Col5 <> \'' + CARD_BILL + '\' and Col5 <> \'' + RENT + '\' and Col1 is not null group by toDate(Col1) order by toDate(Col1) label toDate(Col1) \'Day\', sum(Col3) \'Spent\'",0),"")');
  dash.getRange('D14:D45').setNumberFormat('dd mmm');
  dash.getRange('E14:E45').setNumberFormat(MONEY_FORMAT);

  dash.getRange('G12').setValue('Recent').setFontWeight('bold');
  dash.getRange('G13').setFormula('=IFERROR(QUERY(' + block(SEL, 'A2:E') +
    ',"select Col1, Col4, Col3, Col5 where Col1 is not null order by Col1 desc limit 20 label Col1 \'When\', Col4 \'Merchant\', Col3 \'Amount\', Col5 \'Category\'",0),"")');
  dash.getRange('G14:G40').setNumberFormat('dd mmm, h:mm am/pm');
  dash.getRange('I14:I40').setNumberFormat(MONEY_FORMAT);

  dash.setColumnWidth(1, 190);
  dash.setColumnWidth(2, 120);
  dash.setColumnWidth(7, 150);
  dash.setColumnWidth(8, 160);

  const red = SpreadsheetApp.newConditionalFormatRule().whenNumberLessThan(0).setFontColor('#c62828')
    .setRanges([dash.getRange('B7')]).build();
  dash.setConditionalFormatRules([red]);

  dash.insertChart(dash.newChart().setChartType(Charts.ChartType.PIE)
    .addRange(dash.getRange('A13:B27')).setPosition(30, 1, 0, 0)
    .setOption('title', 'Spending by category').setOption('pieHole', 0.5).build());
  dash.insertChart(dash.newChart().setChartType(Charts.ChartType.COLUMN)
    .addRange(dash.getRange('D13:E44')).setPosition(30, 4, 0, 0)
    .setOption('title', 'Daily spending').setOption('legend', { position: 'none' }).build());
  return dash;
}

// ---------------------------------------------------------------------------
// SMS parser (JavaScript copy of BankSMSParser.swift in the iOS app)
// ---------------------------------------------------------------------------

/** Makes a word list case-insensitive inside an otherwise case-sensitive regex: "on" -> "[oO][nN]". */
function ci_(words) {
  return words.replace(/[a-z]/g, function (c) { return '[' + c + c.toUpperCase() + ']'; });
}

const IGNORE_RE = new RegExp([
  '\\b(otp|one[- ]time password|verification code)\\b',
  'has requested|requested (money|rs|inr)|collect request',
  'will be (debited|deducted|charged)',
  '\\bis due\\b|\\bdue (on|date|by)\\b|(minimum|min|total) (amt|amount) due',
  'pre-?approved|loan offer|apply now|insta ?loan|eligible for',
  '\\b(declined|failed|unsuccessful)\\b',
  '\\bpayment (of [^.]{0,30})?(has been |is )?received\\b',
  // Card issuers confirming a bill payment, and statement / due-date reminders.
  'received (as |a |your )?payment|payment (towards|for|against) your [a-z ]{0,25}card|thank you for (the |your )?payment',
  '\\b(total|min|minimum) (amt |amount )?due\\b|\\bstmt\\b|\\bstatement (dt|date|generated|is ready|for)\\b',
  // Merchant receipts ("Your Swiggy Order #… was paid"); the bank's own SMS records the payment.
  '\\byour [a-z]+ order\\b|\\border (#|no\\b|id\\b)',
  // Promotions and reminders that mention an amount (the Shortcut now forwards every SMS with Rs / INR / ₹).
  '\\b(offers?|discount|coupon|voucher|promo ?code|sale|deals?|lucky|congratulations|winner)\\b',
  'cashback (of )?up ?to|get (flat |upto |up to )?(rs|inr|₹)|\\bwin\\b|\\bflat (rs\\.? ?|inr ?|₹ ?)?\\d+ off|\\d+ ?% off',
  '(shop|buy|order|recharge|pay|apply|book|upgrade|renew) now|click (here|on)|t ?& ?c|tnc|limited (period|time)|hurry|last day',
  '\\b(expires?|expiring|validity|data pack|unlimited calls)\\b|plan (of|at|@) (rs|inr|₹)|bill (of|for) (rs|inr|₹)[^.]{0,40}(generated|due)|bill (is )?generated',
  'reward points? (balance|worth|expir|will)|credit limit (has been )?(increased|enhanced)|loan (of|up ?to|amount)|emi (of|starting|as low)|premium (is )?due|insurance cover',
].join('|'), 'i');

const TRANSACTION_CONTEXT_RE = /a\/c|\bacc?t\b|account|\bcard\b|\bupi\b|\bvpa\b|\bref\b|\brefno\b|\bimps\b|\bneft\b|\brtgs\b|\btxn\b|\bwallet\b|\batm\b|\bbank\b/i;
const DEBIT_RE = /\b(debited|spent|sent|paid|withdrawn|withdrawal|purchase|purchased|deducted|used|using|txn of|transaction of|transferred to|payment of|transfer of)\b/i;
const CREDIT_RE = /\b(credited|received|deposited|refund|refunded|reversed|reversal)\b/i;
const CURRENCY_AMOUNT_RE = /(?:(?<![a-z])(?:rs|inr)\.?|₹)\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)/gi;
const VERB_AMOUNT_RE = /\b(?:debited|credited|spent|sent|paid|received)\s+(?:by|for|with|of)?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)/i;

const NAME = "([A-Za-z0-9][A-Za-z0-9&@._'\\- ]{0,60}?)";
const END = '(?=\\s+(?:' + ci_('on|ref|refno|upi|via|avl|bal|info|not|if|thru|using|from|by|at|dated|date|and|has|is|was|credited|debited|to|for|towards|in|with') +
  ')\\b|\\s*[,;:(]|\\.(?=[A-Z\\s])|\\.$|\\s+-|\\s*\\*|$)';

const DEBIT_MERCHANT_PATTERNS = [
  'UPI/[A-Za-z0-9]+/\\d+/([^/]+?)(?=/|\\s+(?:' + ci_('not|ref|avl') + ')\\b|$)',
  '\\b' + ci_('at') + '\\s+' + NAME + END,
  '\\b' + ci_('to') + '\\s+(?:' + ci_('vpa') + '\\s+)?' + NAME + END,
  '[;,.]\\s*' + NAME + '\\s+' + ci_('credited') + '\\b',
  '\\b(?:' + ci_('on|for|towards') + ")\\s+([A-Z][A-Z0-9&' .\\-]{2,40}?)" + END,
  ci_('info') + '[:\\s]+(?:(?:' + ci_('upi|pos|imps|neft|ach') + ')[-/ ]?(?:\\d+[-/ ])?)?' + NAME + END,
];
const CREDIT_MERCHANT_PATTERNS = [
  '\\b(?:' + ci_('from|by') + ')\\s+(?:' + ci_('vpa') + '\\s+)?' + NAME + END,
  '\\b' + ci_('vpa') + '\\s+' + NAME + END,
  ci_('info') + '[:\\s]+(?:(?:' + ci_('upi|imps|neft|ach') + ')[-/ ]?(?:\\d+[-/ ])?)?' + NAME + END,
];
const NOT_MERCHANTS = ['your', 'you', 'a', 'ac', 'acct', 'account', 'bank', 'upi', 'neft', 'imps', 'rtgs', 'card',
  'the', 'block', 'beneficiary', 'vpa', 'mobile', 'net banking', 'netbanking', 'atm'];

const BANKS = [
  ['HDFC Bank', '\\bhdfc'], ['SBI', '\\bsbi\\b|state bank'], ['ICICI Bank', '\\bicici'], ['Axis Bank', '\\baxis\\b'],
  ['Kotak', '\\bkotak'], ['Federal Bank', 'federal\\s*bank|\\bfedbank'], ['South Indian Bank', 'south indian bank|\\bsib\\b'],
  ['Canara Bank', '\\bcanara'], ['Union Bank', 'union bank'], ['Bank of Baroda', 'bank of baroda|\\bbob\\b'],
  ['Punjab National Bank', 'punjab national|\\bpnb\\b'], ['IDFC First', '\\bidfc'], ['Yes Bank', '\\byes bank'],
  ['IndusInd', '\\bindusind'], ['CSB Bank', '\\bcsb\\b|catholic syrian'], ['Kerala Gramin Bank', 'kerala gramin'],
  ['ESAF Bank', '\\besaf'], ['Dhanlaxmi Bank', 'dhanlaxmi'], ['AU Bank', '\\bau small finance|\\bau bank'],
  ['Bank of India', 'bank of india'], ['Indian Overseas Bank', 'indian overseas|\\biob\\b'], ['Indian Bank', 'indian bank'],
  ['Paytm', '\\bpaytm'], ['slice', '\\bslice\\b'],
];

/** Checked in order, so more specific groups come first ("swiggy instamart" is groceries, not food). */
const CATEGORY_RULES = [
  ['Groceries', ['instamart', 'bigbasket', 'blinkit', 'zepto', 'dmart', 'grofers', 'supermarket', 'hypermarket',
    'reliance fresh', 'reliance smart', 'more retail', 'jiomart', 'grocery', 'milma', 'vegetable', 'fruits',
    'margin free', 'lulu', 'spencer', 'nilgiris', 'kirana']],
  ['Entertainment', ['netflix', 'prime video', 'hotstar', 'spotify', 'youtube', 'bookmyshow', 'pvr', 'inox', 'cinema',
    'cinepolis', 'zee5', 'sonyliv', 'gaana', 'steam', 'playstation']],
  ['Travel', ['irctc', 'makemytrip', 'goibibo', 'redbus', 'indigo', 'air india', 'akasa', 'vistara', 'spicejet',
    'yatra', 'cleartrip', 'ixigo', 'oyo', 'airbnb', 'booking com', 'railway', 'airport', 'ksrtc']],
  ['Food & Dining', ['swiggy', 'zomato', 'restaurant', 'cafe', 'hotel', 'bakery', 'bakers', 'dominos', 'domino',
    'pizza', 'kfc', 'mcdonald', 'burger', 'starbucks', 'eatsure', 'biryani', 'tea', 'chai', 'juice', 'food',
    'kitchen', 'canteen', 'mess', 'haldiram', 'chaayos', 'subway']],
  ['Fuel', ['petrol', 'fuel', 'hpcl', 'bpcl', 'iocl', 'indian oil', 'bharat petroleum', 'hp pay', 'shell', 'nayara',
    'filling station']],
  ['Health', ['pharmacy', 'pharma', 'apollo', 'medplus', 'netmeds', '1mg', 'pharmeasy', 'hospital', 'clinic',
    'diagnostic', 'lab', 'labs', 'medical', 'medicals', 'aster', 'kims', 'dental', 'optical', 'health', 'lenskart',
    'thyrocare', 'metropolis']],
  ['Transport', ['uber', 'ola', 'rapido', 'metro', 'fastag', 'parking', 'namma yatri', 'blusmart', 'taxi', 'cab', 'toll']],
  ['Education', ['school', 'college', 'university', 'coursera', 'udemy', 'byju', 'unacademy', 'tuition', 'books',
    'exam', 'fees', 'marrow', 'prepladder', 'dams', 'neet', 'nbems']],
  ['Bills & Recharge', ['electricity', 'kseb', 'msedcl', 'mseb', 'mahavitaran', 'bescom', 'tneb', 'water', 'jio',
    'airtel', 'vodafone', 'bsnl', 'recharge', 'broadband', 'fibernet', 'asianet', 'tata play', 'dth', 'indane',
    'bharat gas', 'hp gas', 'insurance', 'lic', 'bill', 'rent', 'emi', 'society', 'maintenance']],
  ['Shopping', ['amazon', 'flipkart', 'myntra', 'ajio', 'meesho', 'nykaa', 'tata cliq', 'croma', 'reliance digital',
    'decathlon', 'ikea', 'lifestyle', 'westside', 'trends', 'mall', 'store', 'stores', 'textiles', 'silks',
    'jewellers', 'fashion']],
];

/**
 * Returns {amount, kind: 'debit'|'credit', merchant, category, bank, accountLast4, referenceNumber, date}
 * or null when the message isn't a completed transaction (OTP, offer, reminder, failed payment…).
 */
function parseBankSms(raw, now) {
  now = now || new Date();
  const text = String(raw || '').replace(/\s+/g, ' ').trim();
  if (!text || IGNORE_RE.test(text)) return null;

  // A real transaction alert names an account, card, UPI/IMPS/NEFT transfer or reference.
  if (!TRANSACTION_CONTEXT_RE.test(text)) return null;

  const kind = detectKind_(text);
  const amount = detectAmount_(text);
  if (!kind || !amount || amount <= 0) return null;

  const isCash = kind === 'debit' && /\b(atm|cash withdrawal|withdrawn)\b/i.test(text);
  const merchant = isCash ? 'ATM Withdrawal'
    : (detectMerchant_(text, kind) || (kind === 'debit' ? 'Bank Debit' : 'Bank Credit'));

  return {
    amount: amount,
    kind: kind,
    merchant: merchant,
    category: isCash ? 'Cash Withdrawal' : classify_(merchant, kind),
    bank: detectBank_(text),
    accountLast4: detectAccount_(text),
    referenceNumber: detectReference_(text),
    date: resolveDate_(detectDate_(text), now),
  };
}

function detectKind_(text) {
  // "Credit card" / "credit limit" say nothing about the direction of money.
  const cleaned = text
    .replace(/\b(credit|debit)\s+card\b/gi, 'card')
    .replace(/\b(avl\.?|available)?\s*(credit|cr\.?)\s*(limit|lmt)\b/gi, 'limit');
  const d = cleaned.search(DEBIT_RE);
  const c = cleaned.search(CREDIT_RE);
  if (d >= 0 && c >= 0) return d < c ? 'debit' : 'credit';
  if (d >= 0) return 'debit';
  if (c >= 0) return 'credit';
  return null;
}

function detectAmount_(text) {
  CURRENCY_AMOUNT_RE.lastIndex = 0;
  let m;
  while ((m = CURRENCY_AMOUNT_RE.exec(text)) !== null) {
    // Skip "Avl Bal Rs 12,345" / "Avl Limit INR 1,20,000".
    const before = text.slice(Math.max(0, m.index - 14), m.index).toLowerCase();
    if (['bal', 'limit', 'lmt', 'avl', 'available', 'outstanding'].some(function (w) { return before.indexOf(w) >= 0; })) continue;
    const value = parseFloat(m[1].replace(/,/g, ''));
    if (!isNaN(value)) return value;
  }
  const v = text.match(VERB_AMOUNT_RE); // SBI: "A/C X1234 debited by 120.0 on date ..."
  return v ? parseFloat(v[1].replace(/,/g, '')) : null;
}

function detectMerchant_(text, kind) {
  const patterns = kind === 'debit' ? DEBIT_MERCHANT_PATTERNS : CREDIT_MERCHANT_PATTERNS;
  for (let p = 0; p < patterns.length; p++) {
    const re = new RegExp(patterns[p], 'g');
    let m;
    while ((m = re.exec(text)) !== null) {
      if (m[0] === '') { re.lastIndex++; continue; }
      if (m[1] === undefined) continue;
      const cleaned = cleanMerchant_(m[1]);
      if (cleaned) return cleaned;
    }
  }
  return null;
}

function cleanMerchant_(raw) {
  let value = raw.replace(/^[ .\-,:*]+|[ .\-,:*]+$/g, '');
  value = value.replace(/^(upi|neft|imps|rtgs|pos|vpa|ach|mmt|trf)[-/: ]+/i, '');

  const at = value.indexOf('@');
  if (at >= 0) {
    // A VPA such as "swiggy.instamart@icici" or "9876543210@ybl".
    const handle = value.slice(0, at);
    if (/^\d+$/.test(handle)) return handle.length >= 4 ? 'UPI ••' + handle.slice(-4) : null;
    value = handle.replace(/[._\-]+/g, ' ');
  }

  value = value.trim();
  const lower = value.toLowerCase();
  if (value.length < 2 || NOT_MERCHANTS.indexOf(lower) >= 0 || lower.indexOf('your ') === 0 ||
      lower.indexOf('a/c') === 0 || /^(rs|inr)\.?\s*\d/.test(lower) || !/[A-Za-z]/.test(value)) return null;
  return prettify_(value.slice(0, 40));
}

/** "AMAZON PAY INDIA" -> "Amazon Pay India", "netflix" -> "Netflix". Short all-caps names ("KSEB") stay. */
function prettify_(value) {
  const letters = value.replace(/[^A-Za-z]/g, '');
  const titleCase = function (s) {
    return s.toLowerCase().replace(/(^|[^A-Za-z0-9])([a-z])/g, function (_, p, c) { return p + c.toUpperCase(); });
  };
  const hasLongWord = value.split(' ').some(function (w) { return w.length >= 5; });
  if (letters === letters.toUpperCase() && hasLongWord) return titleCase(value);
  if (letters === letters.toLowerCase()) return titleCase(value);
  return value;
}

function classify_(merchant, kind) {
  if (kind === 'credit') return 'Income';
  const hay = ' ' + merchant.toLowerCase().replace(/[^a-z0-9]+/g, ' ') + ' ';
  if (/ cred | dreamplug|credit ?card|card bill| cc bill|card payment/.test(hay)) return CARD_BILL;
  if (/ (rent|house rent|nobroker|nestaway) /.test(hay)) return RENT;
  for (let i = 0; i < CATEGORY_RULES.length; i++) {
    const hit = CATEGORY_RULES[i][1].some(function (k) {
      // Short keywords must be whole words so "tea" doesn't match "steam".
      return k.length >= 5 ? hay.indexOf(k) >= 0 : hay.indexOf(' ' + k + ' ') >= 0;
    });
    if (hit) return CATEGORY_RULES[i][0];
  }
  return merchant.indexOf('UPI ••') === 0 ? 'Transfers' : 'Other';
}

function detectAccount_(text) {
  const m = text.match(/(?:a\/c|acct|account|\bac|card)(?:\s*no\.?)?(?:\s*ending(?:\s*with)?)?[\s:]*[x*#.]*\s*(\d{3,6})\b/i);
  return m ? m[1].slice(-4) : null;
}

function detectReference_(text) {
  const m = text.match(/(?:ref(?:erence)?\.?\s*(?:no|num|number|id)?\.?|rrn|utr|upi(?:\s*ref)?(?:\s*no)?)[\s:.#-]*(\d{6,})/i) ||
    text.match(/UPI\/[A-Za-z0-9]+\/(\d{6,})\//);
  return m ? m[1] : null;
}

function detectBank_(text) {
  for (let i = 0; i < BANKS.length; i++) {
    if (new RegExp(BANKS[i][1], 'i').test(text)) return BANKS[i][0];
  }
  return null;
}

const MONTHS = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

function detectDate_(text) {
  let m = text.match(/(?<!\d)(\d{4})-(\d{1,2})-(\d{1,2})(?!\d)/);
  if (m) return validDate_(+m[1], +m[2], +m[3]);
  m = text.match(/(?<!\d)(\d{1,2})[- ]?(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*[-, ]*(\d{2,4})(?!\d)/i);
  if (m) return validDate_(+m[3], MONTHS.indexOf(m[2].toLowerCase()) + 1, +m[1]);
  m = text.match(/(?<!\d)(\d{1,2})[/-](\d{1,2})[/-](\d{2}|\d{4})(?!\d)/); // Indian day-first order
  if (m) return validDate_(+m[3], +m[2], +m[1]);
  return null;
}

function validDate_(year, month, day) {
  const y = year < 100 ? 2000 + year : year;
  if (month < 1 || month > 12 || day < 1 || day > 31 || y < 2000 || y > 2100) return null;
  const d = new Date(y, month - 1, day, 12, 0, 0);
  return d.getDate() === day ? d : null; // rejects 31 Feb etc.
}

/** The SMS arrives seconds after the payment, so "now" is most accurate unless it's clearly an older message. */
function resolveDate_(date, now) {
  if (!date || sameDay_(date, now) || date > now) return now;
  return date;
}

if (typeof module !== 'undefined') module.exports = { parseBankSms: parseBankSms, inr_: inr_ };
