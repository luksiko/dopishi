#!/usr/bin/env swift
import Foundation
import CryptoKit

// Usage: swift scripts/generate-appcast.swift <version> [build-number] <tag> <path-to-universal-zip> [output-path]
// Environment: SPARKLE_PRIVATE_ED_KEY (base64 encoded 32-byte private key)

guard CommandLine.arguments.count >= 4 else {
    print("Usage: swift scripts/generate-appcast.swift <version> [build-number] <tag> <path-to-universal-zip> [output-path]")
    exit(1)
}

let version = CommandLine.arguments[1].replacingOccurrences(of: "^v", with: "", options: .regularExpression)
let buildNumber: String
let tag: String
let zipPath: String
let outputPath: String

if CommandLine.arguments.count >= 5 && !CommandLine.arguments[2].hasPrefix("v") && Int(CommandLine.arguments[2]) != nil {
    buildNumber = CommandLine.arguments[2]
    tag = CommandLine.arguments[3]
    zipPath = CommandLine.arguments[4]
    outputPath = CommandLine.arguments.count > 5 ? CommandLine.arguments[5] : "appcast.xml"
} else {
    tag = CommandLine.arguments[2]
    zipPath = CommandLine.arguments[3]
    outputPath = CommandLine.arguments.count > 4 ? CommandLine.arguments[4] : "appcast.xml"
    buildNumber = version
}

let zipURL = URL(fileURLWithPath: zipPath)
guard FileManager.default.fileExists(atPath: zipPath) else {
    print("Error: Zip file not found at \(zipPath)")
    exit(1)
}

guard let zipData = try? Data(contentsOf: zipURL) else {
    print("Error: Could not read zip data at \(zipPath)")
    exit(1)
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
} else {
    print("Notice: SPARKLE_PRIVATE_ED_KEY not set. Generating unsigned appcast item.")
}

let rfc822Formatter = DateFormatter()
rfc822Formatter.locale = Locale(identifier: "en_US_POSIX")
rfc822Formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
let pubDate = rfc822Formatter.string(from: Date())

let enclosureAttrs = [
    "url=\"https://github.com/luksiko/dopishi/releases/download/\(tag)/\(zipFilename)\"",
    "sparkle:version=\"\(buildNumber)\"",
    "sparkle:shortVersionString=\"\(version)\"",
    "length=\"\(fileSize)\"",
    "type=\"application/octet-stream\"",
    signatureBase64.isEmpty ? "" : "sparkle:edSignature=\"\(signatureBase64)\""
].filter { !$0.isEmpty }.joined(separator: "\n        ")

let appcastXML = """
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Dopishi Updates</title>
    <link>https://github.com/luksiko/dopishi</link>
    <description>Most recent updates for Dopishi</description>
    <language>en</language>
    <item>
      <title>Dopishi \(version)</title>
      <pubDate>\(pubDate)</pubDate>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <enclosure
        \(enclosureAttrs) />
    </item>
  </channel>
</rss>
"""

do {
    try appcastXML.write(toFile: outputPath, atomically: true, encoding: .utf8)
    print("Generated appcast at \(outputPath)")
} catch {
    print("Error writing appcast: \(error)")
    exit(1)
}
