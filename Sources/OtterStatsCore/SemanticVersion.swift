import Foundation

/// Minimal semver: `MAJOR.MINOR.PATCH[-prerelease]`, with an optional leading `v`.
/// Build metadata (`+…`) is ignored. A release is newer than any prerelease of the same core.
public struct SemanticVersion: Comparable, Hashable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: [String]

    public init(major: Int, minor: Int, patch: Int, prerelease: [String] = []) {
        self.major = major; self.minor = minor; self.patch = patch; self.prerelease = prerelease
    }

    public init?(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        if let plus = s.firstIndex(of: "+") { s = String(s[..<plus]) }
        var pre: [String] = []
        if let dash = s.firstIndex(of: "-") {
            pre = s[s.index(after: dash)...].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            s = String(s[..<dash])
            guard pre.allSatisfy(Self.isIdentifier) else { return nil }
        }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts.allSatisfy(Self.isNumeric),
              let a = Int(parts[0]), let b = Int(parts[1]), let c = Int(parts[2]) else { return nil }
        self.init(major: a, minor: b, patch: c, prerelease: pre)
    }

    private static func isNumeric(_ s: String) -> Bool {
        !s.isEmpty && isDigits(s) && (s == "0" || !s.hasPrefix("0"))
    }

    private static func isIdentifier(_ s: String) -> Bool {
        guard !s.isEmpty, s.allSatisfy({ $0.isASCIIDigit || $0 == "-" || ($0.isASCII && $0.isLetter) }) else { return false }
        return !isDigits(s) || isNumeric(s)
    }

    private static func isDigits(_ s: String) -> Bool { s.allSatisfy(\.isASCIIDigit) }

    public var description: String {
        let core = "\(major).\(minor).\(patch)"
        return prerelease.isEmpty ? core : core + "-" + prerelease.joined(separator: ".")
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, true): return false
        case (true, false): return false
        case (false, true): return true
        case (false, false): break
        }
        for (l, r) in zip(lhs.prerelease, rhs.prerelease) where l != r {
            switch (isDigits(l), isDigits(r)) {
            case (true, true): return l.count != r.count ? l.count < r.count : l < r
            case (true, false): return true
            case (false, true): return false
            case (false, false): return l < r
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
