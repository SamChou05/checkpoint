import Foundation

struct LegalLinks {
    static let privacyPolicyInfoKey = "CheckpointPrivacyPolicyURL"
    static let supportInfoKey = "CheckpointSupportURL"
    static let termsOfUseURL = URL(
        string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    )!

    var privacyPolicyURL: URL?
    var supportURL: URL?

    static var current: LegalLinks {
        LegalLinks(bundle: .main)
    }

    init(bundle: Bundle) {
        privacyPolicyURL = Self.configuredURL(
            bundle.object(forInfoDictionaryKey: Self.privacyPolicyInfoKey) as? String
        )
        supportURL = Self.configuredURL(
            bundle.object(forInfoDictionaryKey: Self.supportInfoKey) as? String
        )
    }

    init(privacyPolicyURL: URL?, supportURL: URL?) {
        self.privacyPolicyURL = privacyPolicyURL
        self.supportURL = supportURL
    }

    var missingConfigurationMessage: String? {
        var missingNames: [String] = []
        if privacyPolicyURL == nil {
            missingNames.append("Privacy Policy")
        }
        if supportURL == nil {
            missingNames.append("Support")
        }
        guard !missingNames.isEmpty else { return nil }
        return "\(missingNames.joined(separator: " and ")) URL\(missingNames.count == 1 ? " is" : "s are") not configured in this build."
    }

    static func configuredURL(_ rawValue: String?) -> URL? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              !value.contains("$("),
              let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              url.host != nil else {
            return nil
        }
        return url
    }
}
