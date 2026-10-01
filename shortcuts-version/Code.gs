/**
 * Daily Finance — Google Sheets backend for an iPhone Shortcut.
 *
 * An iPhone Shortcuts automation sends every bank SMS here. This script reads the
 * amount, merchant, bank etc., adds a row to the "Transactions" sheet and replies with
 * a one-line summary ("Spent ₹250 at Swiggy · ₹1,240 today · ₹760 left") that the
 * Shortcut shows as a notification. The "Dashboard" sheet totals everything up.
 *
 * Setup: paste this whole file into a new Apps Script project, run `setup` once,
 * then Deploy → New deployment → Web app (Execute as: Me, Who has access: Anyone).
 */

const TX_SHEET = 'Transactions';
const DASH_SHEET = 'Dashboard';
const HEADERS = ['Date', 'Type', 'Amount', 'Merchant', 'Category', 'Bank', 'Account', 'Reference', 'SMS'];
const BUDGET_CELL = 'B3';

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
  return reply_(logSms_(String(sms)));
}

/** Opening the web app URL (or asking Siri via a Shortcut) gives today's summary. */
function doGet(e) {
  if (e && e.parameter && e.parameter.sms) return reply_(logSms_(String(e.parameter.sms)));
  return reply_(todaySummary_());
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
    const parsed = parseBankSms(sms, now);
    if (!parsed) return 'Not a bank transaction, nothing logged.';

    const sheet = getSpreadsheet_().getSheetByName(TX_SHEET);
    const rows = recentRows_(sheet, 1000);
    const text = sms.trim();
    const duplicate = rows.some(function (r) {
      return (parsed.referenceNumber && String(r[7]) === parsed.referenceNumber && Number(r[2]) === parsed.amount) ||
        String(r[8]) === text;
    });
    if (duplicate) return 'Already logged.';

    // Reuse the category you last gave this merchant, so your corrections stick.
    if (parsed.kind === 'debit') {
      for (let i = rows.length - 1; i >= 0; i--) {
        if (String(rows[i][3]).toLowerCase() === parsed.merchant.toLowerCase() && rows[i][1] === 'Expense') {
          parsed.category = String(rows[i][4]);
          break;
        }
      }
    }

    sheet.appendRow([
      parsed.date,
      parsed.kind === 'debit' ? 'Expense' : 'Income',
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
    return 'Spent ' + inr_(parsed.amount) + ' at ' + parsed.merchant + ' · ' + todaySummary_(true);
  } finally {
    lock.releaseLock();
  }
}

function todaySummary_(short) {
  const ss = getSpreadsheet_();
  const rows = recentRows_(ss.getSheetByName(TX_SHEET), 1000);
  const today = new Date();
  let spent = 0;
  rows.forEach(function (r) {
    if (r[1] === 'Expense' && r[0] instanceof Date && sameDay_(r[0], today)) spent += Number(r[2]) || 0;
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

function recentRows_(sheet, limit) {
  const last = sheet.getLastRow();
  if (last < 2) return [];
  const start = Math.max(2, last - limit + 1);
  return sheet.getRange(start, 1, last - start + 1, HEADERS.length).getValues();
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

/** Run once from the editor. Creates the "Daily Finance" spreadsheet and prints its link. */
function setup() {
  const ss = getSpreadsheet_();
  Logger.log('Your Daily Finance sheet: ' + ss.getUrl());
  return ss.getUrl();
}

function getSpreadsheet_() {
  const active = SpreadsheetApp.getActiveSpreadsheet && SpreadsheetApp.getActiveSpreadsheet();
  if (active) return ensureSheets_(active);

  const props = PropertiesService.getScriptProperties();
  const id = props.getProperty('SPREADSHEET_ID');
  if (id) {
    try {
      return ensureSheets_(SpreadsheetApp.openById(id));
    } catch (err) {
      // The sheet was deleted; make a new one below.
    }
  }
  const ss = SpreadsheetApp.create('Daily Finance');
  ss.setSpreadsheetTimeZone(Session.getScriptTimeZone());
  props.setProperty('SPREADSHEET_ID', ss.getId());
  return ensureSheets_(ss);
}

function ensureSheets_(ss) {
  if (ss.getSheetByName(TX_SHEET) && ss.getSheetByName(DASH_SHEET)) return ss;

  const money = '[>=10000000]"₹"#\\,##\\,##\\,##0;[>=100000]"₹"#\\,##\\,##0;"₹"#,##0';

  let tx = ss.getSheetByName(TX_SHEET);
  if (!tx) {
    tx = ss.getSheets().length === 1 && ss.getSheets()[0].getLastRow() === 0
      ? ss.getSheets()[0].setName(TX_SHEET)
      : ss.insertSheet(TX_SHEET);
    tx.getRange(1, 1, 1, HEADERS.length).setValues([HEADERS]).setFontWeight('bold').setBackground('#e0f2f1');
    tx.setFrozenRows(1);
    tx.getRange('A:A').setNumberFormat('dd mmm yyyy, h:mm am/pm');
    tx.getRange('C:C').setNumberFormat(money);
    tx.setColumnWidth(1, 160);
    tx.setColumnWidth(4, 180);
    tx.setColumnWidth(9, 400);
    const categories = ['Food & Dining', 'Groceries', 'Transport', 'Fuel', 'Shopping', 'Bills & Recharge', 'Health',
      'Entertainment', 'Travel', 'Education', 'Transfers', 'Cash Withdrawal', 'Income', 'Other'];
    tx.getRange('E2:E').setDataValidation(
      SpreadsheetApp.newDataValidation().requireValueInList(categories, true).setAllowInvalid(true).build());
  }

  let dash = ss.getSheetByName(DASH_SHEET);
  if (!dash) {
    dash = ss.insertSheet(DASH_SHEET, 0);
    const T = TX_SHEET + '!';
    const expense = T + 'B:B,"Expense"';
    const monthStart = 'EOMONTH(TODAY(),-1)+1';
    dash.getRange('A1').setValue('Daily Finance').setFontSize(18).setFontWeight('bold');
    dash.getRange('A3:B9').setValues([
      ['Daily budget (edit me)', 1000],
      ['', ''],
      ['Spent today', '=SUMIFS(' + T + 'C:C,' + expense + ',' + T + 'A:A,">="&TODAY(),' + T + 'A:A,"<"&TODAY()+1)'],
      ['Left today', '=IF(B3>0,B3-B5,"")'],
      ['Spent this month', '=SUMIFS(' + T + 'C:C,' + expense + ',' + T + 'A:A,">="&' + monthStart + ')'],
      ['Received this month', '=SUMIFS(' + T + 'C:C,' + T + 'B:B,"Income",' + T + 'A:A,">="&' + monthStart + ')'],
      ['Spent last 7 days', '=SUMIFS(' + T + 'C:C,' + expense + ',' + T + 'A:A,">="&TODAY()-6)'],
    ]);
    dash.getRange('B3:B9').setNumberFormat(money).setFontWeight('bold');
    dash.getRange('B3').setBackground('#fff8e1');
    dash.getRange('A5:B5').setFontSize(14);

    dash.getRange('A11').setValue('This month by category').setFontWeight('bold');
    dash.getRange('A12').setFormula(
      '=IFERROR(QUERY(' + T + 'A:E,"select E, sum(C) where B = \'Expense\' and A >= date \'"&TEXT(' + monthStart +
      ',"yyyy-mm-dd")&"\' group by E order by sum(C) desc label E \'Category\', sum(C) \'Spent\'",1),"No spending yet")');
    dash.getRange('B13:B40').setNumberFormat(money);

    dash.getRange('D11').setValue('Last 30 days').setFontWeight('bold');
    dash.getRange('D12').setFormula(
      '=IFERROR(QUERY(' + T + 'A:C,"select toDate(A), sum(C) where B = \'Expense\' and A >= date \'"&TEXT(TODAY()-29' +
      ',"yyyy-mm-dd")&"\' group by toDate(A) order by toDate(A) label toDate(A) \'Day\', sum(C) \'Spent\'",1),"")');
    dash.getRange('D13:D50').setNumberFormat('dd mmm');
    dash.getRange('E13:E50').setNumberFormat(money);

    dash.getRange('G11').setValue('Recent').setFontWeight('bold');
    dash.getRange('G12').setFormula('=IFERROR(QUERY(' + T + 'A:E,"select A, D, C, E where A is not null order by A desc limit 20 label A \'When\', D \'Merchant\', C \'Amount\', E \'Category\'",1),"")');
    dash.getRange('G13:G40').setNumberFormat('dd mmm, h:mm am/pm');
    dash.getRange('I13:I40').setNumberFormat(money);

    dash.setColumnWidth(1, 190);
    dash.setColumnWidth(7, 150);
    dash.setColumnWidth(8, 160);

    const red = SpreadsheetApp.newConditionalFormatRule().whenNumberLessThan(0).setFontColor('#c62828')
      .setRanges([dash.getRange('B6')]).build();
    dash.setConditionalFormatRules([red]);

    dash.insertChart(dash.newChart().setChartType(Charts.ChartType.PIE)
      .addRange(dash.getRange('A12:B26')).setPosition(28, 1, 0, 0)
      .setOption('title', 'This month by category').setOption('pieHole', 0.5).build());
    dash.insertChart(dash.newChart().setChartType(Charts.ChartType.COLUMN)
      .addRange(dash.getRange('D12:E42')).setPosition(28, 4, 0, 0)
      .setOption('title', 'Daily spending').setOption('legend', { position: 'none' }).build());
  }
  return ss;
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
].join('|'), 'i');

const DEBIT_RE = /\b(debited|spent|sent|paid|withdrawn|withdrawal|purchase|purchased|deducted|used|using|txn of|transaction of|transferred to)\b/i;
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
  ['Paytm', '\\bpaytm'],
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
  const m = text.match(/(?:ref(?:erence)?\.?\s*(?:no|num|number)?\.?|rrn|utr|upi(?:\s*ref)?(?:\s*no)?)[\s:.#-]*(\d{6,})/i) ||
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
