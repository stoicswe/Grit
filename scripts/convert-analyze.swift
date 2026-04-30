import Foundation

let inputData = FileHandle.standardInput.readDataToEndOfFile()

guard let json = try? JSONSerialization.jsonObject(with: inputData) as? [String: Any] else {
    fputs("Error: Could not parse JSON from stdin\n", stderr)
    print("[]")
    exit(0)
}

let cwd = FileManager.default.currentDirectoryPath + "/"

// Warnings live at issues.warningSummaries._values[]
let warningSummaries = ((json["issues"] as? [String: Any])?["warningSummaries"] as? [String: Any])?["_values"] as? [[String: Any]] ?? []

func extractLineNumber(from url: String) -> Int {
    // URL fragment contains StartingLineNumber=N
    guard let fragment = url.components(separatedBy: "#").last else { return 1 }
    for param in fragment.components(separatedBy: "&") {
        let parts = param.components(separatedBy: "=")
        if parts.count == 2, parts[0] == "StartingLineNumber" {
            return Int(parts[1]) ?? 1
        }
    }
    return 1
}

let issues: [[String: Any]] = warningSummaries.compactMap { w in
    guard let msg = (w["message"] as? [String: Any])?["_value"] as? String else { return nil }

    let rawURL = ((w["documentLocationInCreatingWorkspace"] as? [String: Any])?["url"] as? [String: Any])?["_value"] as? String ?? ""
    let urlWithoutFragment = rawURL.components(separatedBy: "#").first ?? ""
    let path = urlWithoutFragment
        .replacingOccurrences(of: "file://", with: "")
        .replacingOccurrences(of: cwd, with: "")

    let line = extractLineNumber(from: rawURL)

    let fingerprint = "\(path)\(line)\(msg)"
        .utf8
        .map { String(format: "%02x", $0) }
        .joined()

    return [
        "type": "issue",
        "check_name": "XcodeAnalyze",
        "description": msg,
        "categories": ["Bug Risk"],
        "location": ["path": path, "lines": ["begin": line]],
        "severity": "major",
        "fingerprint": fingerprint
    ]
}

let output = try! JSONSerialization.data(withJSONObject: issues, options: .prettyPrinted)
print(String(data: output, encoding: .utf8)!)
