import SwiftUI

/// iOS never lets an app read SMS directly, so logging works through a personal automation
/// in the Shortcuts app that forwards matching messages to the "Log Bank SMS" action.
struct SetupGuideView: View {
    @Environment(\.openURL) private var openURL
    @State private var sample = "Sent Rs.250.00 From HDFC Bank A/C *1234 To SWIGGY On 01/10/26 Ref 427512345678"

    private let steps: [(title: String, detail: String)] = [
        ("Open the Shortcuts app",
         "Go to the Automation tab and tap + (New Automation)."),
        ("Choose “Message”",
         "Under “Message Contains”, type debited. Leave Sender empty — bank senders like AD-HDFCBK aren't contacts."),
        ("Run immediately",
         "Select “Run Immediately” and turn off “Notify When Run”, then tap Next."),
        ("Add the Daily Finance action",
         "Tap “New Blank Automation”, then Add Action, search for “Log Bank SMS” and add it."),
        ("Pass the message in",
         "Tap the “Message” field in the action and choose “Shortcut Input”. Tap it again and pick “Content”. Tap Done."),
        ("Repeat for other words",
         "An automation can only watch for one word, so make the same automation for credited, spent and sent. The app ignores duplicates, so overlap is fine."),
    ]

    var body: some View {
        List {
            Section {
                Text("Apple doesn't let any app read your SMS inbox. Instead, a Shortcuts automation hands each bank SMS to Daily Finance the moment it arrives. It takes about two minutes to set up, once.")
                    .font(.subheadline)
            }

            Section("Steps") {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.accentColor, in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.title).font(.headline)
                            Text(step.detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Button {
                    if let url = URL(string: "shortcuts://") { openURL(url) }
                } label: {
                    Label("Open Shortcuts", systemImage: "arrow.up.forward.app")
                }
            }

            Section {
                TextEditor(text: $sample)
                    .frame(minHeight: 90)
                    .font(.callout)
                if let parsed = BankSMSParser.parse(sample) {
                    ParsedPreview(parsed: parsed)
                } else {
                    Label("No transaction found in this message", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Try the reader")
            } footer: {
                Text("Paste one of your own bank SMS to check it's understood. Nothing here is saved.")
            }

            Section("Ask Siri") {
                Label("“How much did I spend today in Daily Finance”", systemImage: "mic")
                    .font(.subheadline)
            }
        }
        .navigationTitle("Set up SMS logging")
        .navigationBarTitleDisplayMode(.inline)
    }
}
