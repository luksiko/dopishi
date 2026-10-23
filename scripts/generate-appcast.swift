#!/usr/bin/env swift
import Foundation
import CryptoKit

// Usage: swift scripts/generate-appcast.swift <version> <build-number> <tag> <universal-zip> [arm64-zip] [output-path]
// Environment: SPARKLE_PRIVATE_ED_KEY (base64 encoded 32-byte private key)

guard CommandLine.arguments.count >= 5 else {
    print("Usage: swift scripts/generate-appcast.swift <version> <build-number> <tag> <universal-zip> [arm64-zip] [output-path]")
    exit(1)
}

let version = CommandLine.arguments[1].replacingOccurrences(of: "^v", with: "", options: .regularExpression)
let buildNumber = CommandLine.arguments[2]
let tag = CommandLine.arguments[3]
let universalZipPath = CommandLine.arguments[4]

var arm64ZipPath: String? = nil
var outputPath = "appcast.xml"

if CommandLine.arguments.count == 6 {
    // Either [arm64-zip] or [output-path]
    let arg = CommandLine.arguments[5]
    if arg.hasSuffix(".xml") {
        outputPath = arg
    } else {
        arm64ZipPath = arg
    }
} else if CommandLine.arguments.count >= 7 {
    arm64ZipPath = CommandLine.arguments[5]
    outputPath = CommandLine.arguments[6]
}

func generateItem(
    title: String,
    version: String,
    buildNumber: String,
    tag: String,
    zipPath: String,
    hardwareRequirement: String? = nil,
    pubDate: String
) -> String? {
    let zipURL = URL(fileURLWithPath: zipPath)
    guard FileManager.default.fileExists(atPath: zipPath) else {
        print("Notice: Zip not found at \(zipPath), skipping item")
        return nil
    }
    guard let zipData = try? Data(contentsOf: zipURL) else {
        print("Error: Could not read zip data at \(zipPath)")
        return nil
    }

    let fileSize = zipData.count
    let zipFilename = zipURL.lastPathComponent

    var signatureBase64 = ""
    if let privKeyB64 = ProcessInfo.processInfo.environment["SPARKLE_PRIVATE_ED_KEY"],
       let privKeyData = Data(base64Encoded: privKeyB64) {
        do {
            let privKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privKeyData)
            let sig = try privKey.signature(for: zipData)
            signatureBase64 = sig.base64EncodedString()
            print("Successfully signed \(zipFilename) with Ed25519 (size: \(fileSize) bytes)")
        } catch {
            print("Warning: Failed to sign with SPARKLE_PRIVATE_ED_KEY: \(error)")
        }
    }

    let enclosureAttrs = [
        "url=\"https://github.com/luksiko/dopishi/releases/download/\(tag)/\(zipFilename)\"",
        "sparkle:version=\"\(buildNumber)\"",
        "sparkle:shortVersionString=\"\(version)\"",
        "length=\"\(fileSize)\"",
        "type=\"application/octet-stream\"",
        signatureBase64.isEmpty ? "" : "sparkle:edSignature=\"\(signatureBase64)\""
    ].filter { !$0.isEmpty }.joined(separator: "\n        ")

    var hwLine = ""
    if let hw = hardwareRequirement {
        hwLine = "\n      <sparkle:hardwareRequirements>\(hw)</sparkle:hardwareRequirements>"
    }

    return """
        <item>
          <title>\(title)</title>
          <pubDate>\(pubDate)</pubDate>
          <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>\(hwLine)
          <enclosure
            \(enclosureAttrs) />
        </item>
    """
}

let rfc822Formatter = DateFormatter()
rfc822Formatter.locale = Locale(identifier: "en_US_POSIX")
rfc822Formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
let pubDate = rfc822Formatter.string(from: Date())

var items: [String] = []

// 1. Arm64 item (first in list so Apple Silicon selects it first)
if let armPath = arm64ZipPath,
   let armItem = generateItem(
       title: "Dopishi \(version) (Apple Silicon)",
       version: version,
       buildNumber: buildNumber,
       tag: tag,
       zipPath: armPath,
       hardwareRequirement: "arm64",
       pubDate: pubDate
   ) {
    items.append(armItem)
}

// 2. Universal item (fallback for Intel and general systems)
if let universalItem = generateItem(
    title: "Dopishi \(version)",
    version: version,
    buildNumber: buildNumber,
    tag: tag,
    zipPath: universalZipPath,
    hardwareRequirement: nil,
    pubDate: pubDate
) {
    items.append(universalItem)
}

guard !items.isEmpty else {
    print("Error: No items generated for appcast")
    exit(1)
}

let itemsXML = items.joined(separator: "\n")
let appcastXML = """
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Dopishi Updates</title>
    <link>https://github.com/luksiko/dopishi</link>
    <description>Most recent updates for Dopishi</description>
    <language>en</language>
\(itemsXML)
  </channel>
</rss>
"""

do {
    try appcastXML.write(toFile: outputPath, atomically: true, encoding: .utf8)
    print("Generated appcast with \(items.count) item(s) at \(outputPath)")
} catch {
    print("Error writing appcast: \(error)")
    exit(1)
}
