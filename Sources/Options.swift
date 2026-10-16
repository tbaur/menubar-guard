import CoreGraphics

struct Options: Equatable, Sendable {
    static let DEFAULT_MARGIN: CGFloat = 8
    static let MARGIN_RANGE: ClosedRange<CGFloat> = 1...40

    var margin: CGFloat = DEFAULT_MARGIN
    var isCheck = false
    var isVerbose = false
    var isHelp = false
    var isVersion = false
}

enum OptionsError: Error, Equatable, CustomStringConvertible {
    case unknown(String)
    case missingValue(String)
    case badMargin(String)

    var description: String {
        switch self {
        case .unknown(let arg):
            return "unknown option \(arg)"
        case .missingValue(let arg):
            return "\(arg) needs a value"
        case .badMargin(let value):
            let range = Options.MARGIN_RANGE
            return "--margin must be a number from \(Int(range.lowerBound)) to \(Int(range.upperBound)), got \(value)"
        }
    }
}

/// Parses the arguments after the program name.
func parseOptions(_ args: [String]) throws -> Options {
    var options = Options()
    var remaining = args[...]
    while let arg = remaining.popFirst() {
        switch arg {
        case "--check":
            options.isCheck = true
        case "--verbose":
            options.isVerbose = true
        case "-h", "--help":
            options.isHelp = true
        case "--version":
            options.isVersion = true
        case "--margin":
            guard let value = remaining.popFirst() else { throw OptionsError.missingValue(arg) }
            options.margin = try parseMargin(value)
        default:
            throw OptionsError.unknown(arg)
        }
    }
    return options
}

/// Accepts plain decimals only, such as `8` or `7.5`. Swift's `Double` parser
/// would also take hex and exponents, which nobody means for a point size.
private func parseMargin(_ value: String) throws -> CGFloat {
    let isDecimal = !value.isEmpty
        && value.allSatisfy { $0.isASCII && ($0.isNumber || $0 == ".") }
        && value.filter { $0 == "." }.count <= 1
    guard isDecimal, let number = Double(value), Options.MARGIN_RANGE.contains(CGFloat(number)) else {
        throw OptionsError.badMargin(value)
    }
    return CGFloat(number)
}
