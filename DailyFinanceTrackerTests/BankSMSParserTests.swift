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

    func testSliceIMPSPayment() throws {
        let sms = "IMPS payment of Rs. 13,000 from A/c xx6491 done on 02-Oct-26 to SHEETAL SUKHLAL LAVATRE is successful (Ref ID: 627515418066). Not you? Call 08048329999 - slice"
        let result = try XCTUnwrap(parse(sms))
        XCTAssertEqual(result.amount, 13000)
        XCTAssertEqual(result.kind, .debit)
        XCTAssertEqual(result.merchant, "Sheetal Sukhlal Lavatre")
        XCTAssertEqual(result.bank, "slice")
        XCTAssertEqual(result.accountLast4, "6491")
        XCTAssertEqual(result.referenceNumber, "627515418066")
    }

    func testFederalBankUPIToCredIsCardBill() throws {
        let sms = "Debited Rs 1980.00 from a/c X8403 on 02Oct26 01:21 via UPI to CRED Club. Ref 664120776439.Bal Rs 7735.9. Not you?Call 18004251199 -Federal Bank"
        let result = try XCTUnwrap(parse(sms))
        XCTAssertEqual(result.amount, 1980)
        XCTAssertEqual(result.merchant, "CRED Club")
        XCTAssertEqual(result.accountLast4, "8403")
        XCTAssertEqual(result.referenceNumber, "664120776439")
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
            "Get Rs 150 cashback on your first UPI payment of Rs 500 or more via HDFC Bank PayZapp. T&C apply",
            "Your Jio plan of Rs 299 expires tomorrow. Recharge now to continue unlimited calls & data",
            "Flat Rs.200 off on orders above Rs.999! Use code SAVE200. Shop now on Myntra",
            "Congratulations! You are eligible for a credit limit increase on your ICICI Bank Card. Your new limit is Rs 1,50,000",
            "Your Airtel bill of Rs 589.00 for 9876543210 is generated. Pay by 10-Oct-26 to avoid late fee",
            "Your SBI Card reward points worth Rs 450 will expire on 31-Oct-26. Redeem now",
            "Hurry! Personal loan up to Rs 10 lakh at 10.5% from Axis Bank. Apply now",
            "Mom: sent you Rs 500 for the books, check",
            "Thank you Rs.1849.78/- has been received as payment towards your PNB credit card  XX3268 via Online Payment. Your available credit limit is Rs.35515.37. - PNB",
            "Your PNB Card XX3268 stmt dt 16-09-2026 total Due Rs. 1849.78 and Min Due Rs. 1197.66 payable by 06-10-2026 has been sent. Visit www.pnbindia.in. Please ignore if paid. -PNB",
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
