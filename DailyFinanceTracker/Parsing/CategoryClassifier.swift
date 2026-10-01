import Foundation

/// Guesses a category from the merchant name. The user's own corrections (MerchantRule)
/// take priority over this; see TransactionStore.
enum CategoryClassifier {

    /// Checked in order, so more specific groups come first ("swiggy instamart" is groceries, not food).
    static let rules: [(category: SpendingCategory, keywords: [String])] = [
        (.groceries, ["instamart", "bigbasket", "blinkit", "zepto", "dmart", "grofers", "supermarket",
                      "hypermarket", "reliance fresh", "reliance smart", "more retail", "jiomart", "grocery",
                      "milma", "vegetable", "fruits", "margin free", "lulu", "spencer", "nilgiris", "kirana"]),
        (.entertainment, ["netflix", "prime video", "hotstar", "spotify", "youtube", "bookmyshow", "pvr",
                          "inox", "cinema", "cinepolis", "zee5", "sonyliv", "gaana", "steam", "playstation"]),
        (.travel, ["irctc", "makemytrip", "goibibo", "redbus", "indigo", "air india", "akasa", "vistara",
                   "spicejet", "yatra", "cleartrip", "ixigo", "oyo", "airbnb", "booking com", "railway",
                   "airport", "ksrtc"]),
        (.food, ["swiggy", "zomato", "restaurant", "cafe", "hotel", "bakery", "bakers", "dominos", "domino",
                 "pizza", "kfc", "mcdonald", "burger", "starbucks", "eatsure", "biryani", "tea", "chai",
                 "juice", "food", "kitchen", "canteen", "mess", "haldiram", "chaayos", "subway"]),
        (.fuel, ["petrol", "fuel", "hpcl", "bpcl", "iocl", "indian oil", "bharat petroleum", "hp pay",
                 "shell", "nayara", "filling station"]),
        (.health, ["pharmacy", "pharma", "apollo", "medplus", "netmeds", "1mg", "pharmeasy", "hospital",
                   "clinic", "diagnostic", "lab", "labs", "medical", "medicals", "aster", "kims", "dental",
                   "optical", "health", "lenskart", "thyrocare", "metropolis"]),
        (.transport, ["uber", "ola", "rapido", "metro", "fastag", "parking", "namma yatri", "blusmart",
                      "taxi", "cab", "toll"]),
        (.education, ["school", "college", "university", "coursera", "udemy", "byju", "unacademy",
                      "tuition", "books", "exam", "fees", "marrow", "prepladder", "dams", "neet", "nbems"]),
        (.bills, ["electricity", "kseb", "msedcl", "mseb", "mahavitaran", "bescom", "tneb", "water",
                  "jio", "airtel", "vodafone", "bsnl", "recharge", "broadband", "fibernet", "asianet",
                  "tata play", "dth", "indane", "bharat gas", "hp gas", "insurance", "lic", "bill",
                  "rent", "emi", "society", "maintenance"]),
        (.shopping, ["amazon", "flipkart", "myntra", "ajio", "meesho", "nykaa", "tata cliq", "croma",
                     "reliance digital", "decathlon", "ikea", "lifestyle", "westside", "trends", "mall",
                     "store", "stores", "textiles", "silks", "jewellers", "fashion"]),
    ]

    static func classify(merchant: String, kind: TransactionKind) -> SpendingCategory {
        if kind == .credit { return .income }
        let haystack = " " + merchant.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression) + " "

        for rule in rules where rule.keywords.contains(where: { matches($0, in: haystack) }) {
            return rule.category
        }
        if merchant.hasPrefix("UPI ••") { return .transfer }
        return .other
    }

    /// Long keywords match anywhere ("swiggyinstamart"); short ones must be whole words
    /// so that "tea" doesn't match "steam" and "lab" doesn't match "kalabhavan".
    private static func matches(_ keyword: String, in haystack: String) -> Bool {
        keyword.count >= 5 ? haystack.contains(keyword) : haystack.contains(" \(keyword) ")
    }
}
