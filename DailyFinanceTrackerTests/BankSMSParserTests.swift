import XCTest
@testable import DailyFinanceTracker

final class BankSMSParserTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return calendar
    }

    /// 1 Oct 2026, 6 pm IST.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 18))!
    }

    private func parse(_ sms: String) -> ParsedSMS? {
        BankSMSParser.parse(sms, now: now, calendar: calendar)
    }

    // MARK: - Debits

    func testHDFCUPIDebit() throws {
        let sms = """
        Sent Rs.250.00
        From HDFC Bank A/C *1234
        To SWIGGY
        On 01/10/26
        Ref 427512345678
        Not You?
        Call 18002586161/SMS BLOCK UPI to 7308080808
        """
        let result = try XCTUnwrap(parse(sms))
        XCTAssertEqual(result.amount, 250)
        XCTAssertEqual(result.kind, .debit)
        XCTAssertEqual(result.merchant, "Swiggy")
        XCTAssertEqual(result.category, .food)
        XCTAssertEqual(result.bank, "HDFC Bank")
        XCTAssertEqual(result.accountLast4, "1234")
        XCTAssertEqual(result.referenceNumber, "427512345678")
        XCTAssertEqual(result.date, now, "Same-day SMS should use the time it was received")
    }

    func testHDFCCardSpend() throws {
        let sms = "Spent Rs.1,499.00 On HDFC Bank Card 5678 At AMAZON PAY INDIA On 2026-10-01:12:30:45.Not You? To Block+Reissue Call 18002323232/SMS BLOCK CC 5678 to 7308080808"
        let result = try XCTUnwrap(parse(sms))
        XCTAssertEqual(result.amount, 1499)
        XCTAssertEqual(result.kind, .debit)
        XCTAssertEqual(result.merchant, "Amazon Pay India")
        XCTAssertEqual(result.category, .shopping)
        XCTAssertEqual(result.accountLast4, "5678")
    }

    func testSBIUPIDebitWithoutCurrencySymbol() throws {
        let sms = "Dear UPI user A/C X1234 debited by 120.0 on date 01Oct26 trf to ZOMATO LTD Refno 427512345678. If not u? call 1800111109. -SBI"
        let result = try XCTUnwrap(parse(sms))
        XCTAssertEqual(result.amount, 120)
        XCTAssertEqual(result.kind, .debit)
        XCTAssertEqual(result.merchant, "Zomato Ltd")
        XCTAssertEqual(result.category, .food)
        XCTAssertEqual(result.bank, "SBI")
        XCTAssertEqual(result.accountLast4, "1234")
        XCTAssertEqual(result.referenceNumber, "427512345678")
    }

    func testICICIDebitWithPayeeCredited() throws {
        let sms = "ICICI Bank Acct XX123 debited for Rs 450.00 on 01-Oct-26; KSEB credited. UPI:427512345678. Call 18002662 for dispute. SMS BLOCK 123 to 9215676766."
        let result = try XCTUnwrap(parse(sms))
        XCTAssertEqual(result.amount, 450)
        XCTAssertEqual(result.kind, .debit)
        XCTAssertEqual(result.merchant, "KSEB")
        XCTAssertEqual(result.category, .bills)
        XCTAssertEqual(result.referenceNumber, "427512345678")
    }

    func testICICICardIgnoresAvailableLimit() throws {
        let sms = "INR 2,350.00 spent using ICICI Bank Card XX9012 on 01-Oct-26 on APOLLO PHARMACY. Avl Limit: INR 1,20,000.00. If not you, call 1800 2662/SMS BLOCK 9012 to 9215676766"
        let result = try XCTUnwrap(parse(sms))
        XCTAssertEqual(result.amount, 2350)
        XCTAssertEqual(result.merchant, "Apollo Pharmacy")
        XCTAssertEqual(result.category, .health)
        XCTAssertEqual(result.accountLast4, "9012")
    }

    func testFederalBankVPA() throws {
        let sms = "Rs 300.00 debited via UPI on 01-10-2026 13:45:10 to VPA uber.rides@axisbank.Ref No 427512345678.Small txns?Use UPI Lite!-Federal Bank"
        let result = try XCTUnwrap(parse(sms))
        XCTAssertEqual(result.amount, 300)
        XCTAssertEqual(result.merchant, "Uber Rides")
        XCTAssertEqual(result.category, .transport)
        XCTAssertEqual(result.bank, "Federal Bank")
        XCTAssertEqual(result.referenceNumber, "427512345678")
    }

    func testAxisMultiline() throws {
        let sms = """
        INR 560.00 debited
        A/c no. XX7890
        01-10-26, 14:22:05
        UPI/P2M/427512345678/BigBasket
        Not you? SMS BLOCKUPI Cust ID to 919951860002
        Axis Bank
        """
        let result = try XCTUnwrap(parse(sms))
        XCTAssertEqual(result.amount, 560)
        XCTAssertEqual(result.merchant, "BigBasket")
        XCTAssertEqual(result.category, .groceries)
        XCTAssertEqual(result.accountLast4, "7890")
        XCTAssertEqual(result.bank, "Axis Bank")
        XCTAssertEqual(result.referenceNumber, "427512345678")
    }

    func testKotakSubscription() throws {
        let sms = "Sent Rs.99.00 from Kotak Bank AC X1111 to netflix@ybl on 01-10-26.UPI Ref 427512345678. Not you, https://kotak.com/KBANKT/Fraud"
        let result = try XCTUnwrap(parse(sms))
        XCTAssertEqual(result.amount, 99)
        XCTAssertEqual(result.merchant, "Netflix")
        XCTAssertEqual(result.category, .entertainment)
        XCTAssertEqual(result.accountLast4, "1111")
        XCTAssertEqual(result.bank, "Kotak")
    }

    func testPhoneNumberVPAIsTransfer() throws {
        let sms = "Sent Rs.40.00 From HDFC Bank A/C *1234 To 9876543210@ybl On 01/10/26 Ref 427512345678"
        let result = try XCTUnwrap(parse(sms))
        XCTAssertEqual(result.merchant, "UPI ••3210")
        XCTAssertEqual(result.category, .transfer)
    }

    func testCreditCardWordingIsStillADebit() throws {
        let sms = "Thank you for using your Kotak Credit Card XX4321 for Rs 750.00 at DECATHLON on 01-Oct-2026"
        let result = try XCTUnwrap(parse(sms))
        XCTAssertEqual(result.kind, .debit)
        XCTAssertEqual(result.amount, 750)
        XCTAssertEqual(result.merchant, "Decathlon")
        XCTAssertEqual(result.category, .shopping)
    }

    func testATMWithdrawal() throws {
        let sms = "Rs 2000 withdrawn at SBI ATM S1NB000123 from A/cX1234 on 01Oct26. Avl Bal Rs 10,000. -SBI"
        let result = try XCTUnwrap(parse(sms))
        XCTAssertEqual(result.amount, 2000)
        XCTAssertEqual(result.merchant, "ATM Withdrawal")
        XCTAssertEqual(result.category, .cash)
    }

    func testLowercaseInformalSMS() throws {
        let result = try XCTUnwrap(parse("rs 50 paid to tea stall via upi"))
        XCTAssertEqual(result.amount, 50)
        XCTAssertEqual(result.merchant, "Tea Stall")
        XCTAssertEqual(result.category, .food)
    }

    // MARK: - Credits

    func testSBICredit() throws {
        let sms = "Dear SBI User, your A/c X1234-credited by Rs.5000 on 01Oct26 transfer from JOHN DOE Ref No 123456789012 -SBI"
        let result = try XCTUnwrap(parse(sms))
        XCTAssertEqual(result.amount, 5000)
        XCTAssertEqual(result.kind, .credit)
        XCTAssertEqual(result.merchant, "JOHN DOE")
        XCTAssertEqual(result.category, .income)
    }

    func testSalaryCreditIgnoresBalance() throws {
        let sms = "Your A/c XX1234 is credited with INR 85,000.00 on 01-10-2026 by NEFT-SURAJ EYE INSTITUTE. Avl Bal INR 1,02,345.00"
        let result = try XCTUnwrap(parse(sms))
        XCTAssertEqual(result.amount, 85000)
        XCTAssertEqual(result.kind, .credit)
        XCTAssertEqual(result.merchant, "Suraj Eye Institute")
    }

    func testHDFCMoneyReceivedFromVPA() throws {
        let sms = "Money Received - INR 500.00 in your HDFC Bank A/c xx1234 on 01-10-26 by A/c linked to VPA rahul.k@okicici (UPI Ref No 427512345678)"
        let result = try XCTUnwrap(parse(sms))
        XCTAssertEqual(result.amount, 500)
        XCTAssertEqual(result.kind, .credit)
        XCTAssertEqual(result.merchant, "Rahul K")
        XCTAssertEqual(result.referenceNumber, "427512345678")
    }

    func testRefund() throws {
        let sms = "Refund of Rs.349.00 from AMAZON has been credited to your HDFC Bank Card ending 5678 on 01-10-26"
        let result = try XCTUnwrap(parse(sms))
        XCTAssertEqual(result.kind, .credit)
        XCTAssertEqual(result.amount, 349)
        XCTAssertEqual(result.merchant, "Amazon")
    }

    // MARK: - Not transactions

    func testIgnoresNonTransactions() {
        let messages = [
            "123456 is OTP for txn of Rs 500.00 at AMAZON on HDFC Bank card ending 5678. Valid till 12:30. Do not share OTP",
            "Get a pre-approved personal loan of Rs 5,00,000 instantly. Apply now!",
            "Txn of Rs 2,000.00 on HDFC Bank Card 5678 at FLIPKART declined due to insufficient balance",
            "Avl Bal in A/c XX1234 is Rs 12,345.00 as on 01-10-26",
            "Rs 1,999 will be debited from your a/c XX1234 on 05-10-26 for Netflix autopay",
            "Your credit card bill of Rs 12,450 is due on 15-10-26. Minimum amount due Rs 620",
            "RAHUL has requested money from you. Amount: Rs 200. Pay via any UPI app",
            "Hi, see you at the clinic tomorrow",
        ]
        for message in messages {
            XCTAssertNil(parse(message), message)
        }
    }

    // MARK: - Dates

    func testOlderPastedSMSUsesPrintedDate() throws {
        let sms = "Sent Rs.250.00 From HDFC Bank A/C *1234 To SWIGGY On 28/09/26 Ref 427512345678"
        let result = try XCTUnwrap(parse(sms))
        let parts = calendar.dateComponents([.year, .month, .day], from: result.date)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 9)
        XCTAssertEqual(parts.day, 28)
    }

    func testFutureDateFallsBackToNow() throws {
        let sms = "Sent Rs.250.00 From HDFC Bank A/C *1234 To SWIGGY On 28/12/26"
        XCTAssertEqual(try XCTUnwrap(parse(sms)).date, now)
    }
}
