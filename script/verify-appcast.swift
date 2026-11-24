// Verify the archive offered to Sparkle against the public key in the signed app.
import CryptoKit
import Foundation

func fail(_ reason: String) -> Never {
    print("FAIL \(reason)")
    exit(1)
}

guard CommandLine.arguments.count == 3 else { fail("expected an archive path and an Info.plist path") }
let archive = URL(fileURLWithPath: CommandLine.arguments[1])
let plistURL = URL(fileURLWithPath: CommandLine.arguments[2])
let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), format: nil) as? [String: Any]
guard let version = plist?["CFBundleShortVersionString"] as? String,
      let minimum = plist?["LSMinimumSystemVersion"] as? String,
      let build = plist?["CFBundleVersion"] as? String,
      let encodedKey = plist?["SUPublicEDKey"] as? String,
      let key = Data(base64Encoded: encodedKey) else { fail("missing app version or update verification key") }

let feedURL = archive.deletingLastPathComponent().appendingPathComponent("appcast.xml")
let feed = try XMLDocument(contentsOf: feedURL, options: [.nodeLoadExternalEntitiesNever])
let namespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"
let items = try feed.nodes(forXPath: "/rss/channel/item").compactMap { $0 as? XMLElement }
let item = items.first { $0.elements(forLocalName: "version", uri: namespace).first?.stringValue == build }
let expectedURL = "https://github.com/lu-zhengda/fold/releases/download/v\(version)/\(archive.lastPathComponent)"
guard item?.elements(forLocalName: "shortVersionString", uri: namespace).first?.stringValue == version,
      item?.elements(forLocalName: "minimumSystemVersion", uri: namespace).first?.stringValue == minimum,
      let enclosure = item?.elements(forName: "enclosure").first,
      enclosure.attribute(forName: "url")?.stringValue == expectedURL,
      let encodedSignature = enclosure.attribute(forLocalName: "edSignature", uri: namespace)?.stringValue,
      let signature = Data(base64Encoded: encodedSignature) else { fail("missing or incorrect Sparkle feed entry") }

let bytes = try Data(contentsOf: archive, options: .mappedIfSafe)
let signingKey = try Curve25519.Signing.PublicKey(rawRepresentation: key)
guard enclosure.attribute(forName: "length")?.stringValue == String(bytes.count),
      signingKey.isValidSignature(signature, for: bytes) else { fail("update archive length or EdDSA signature") }
print("PASS Sparkle feed and signed update archive")
