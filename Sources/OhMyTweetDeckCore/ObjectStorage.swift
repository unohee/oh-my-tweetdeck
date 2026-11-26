import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// An S3-compatible bucket (Cloudflare R2, AWS S3, MinIO) the app uploads attachments to, so
/// Threads and Instagram can fetch them: their Graph APIs only take a public image URL.
public struct ObjectStorageConfig: Equatable, Sendable {
    /// API endpoint, e.g. `https://<account>.r2.cloudflarestorage.com`. Path-style requests.
    public var endpoint: URL
    /// Signing region: `auto` for R2, the bucket region for S3.
    public var region: String
    public var bucket: String
    public var accessKeyID: String
    public var secretAccessKey: String
    /// Where uploaded keys are publicly readable, e.g. `https://pub-xxx.r2.dev` or a custom domain.
    public var publicBaseURL: URL

    public init(endpoint: URL, region: String, bucket: String, accessKeyID: String,
                secretAccessKey: String, publicBaseURL: URL) {
        self.endpoint = endpoint
        self.region = region
        self.bucket = bucket
        self.accessKeyID = accessKeyID
        self.secretAccessKey = secretAccessKey
        self.publicBaseURL = publicBaseURL
    }
}

public struct ObjectStorageError: Error, Equatable, CustomStringConvertible {
    public var status: Int
    public var message: String
    public var description: String { "Upload failed (HTTP \(status)): \(message)" }
}

/// AWS Signature Version 4 for S3 requests (header auth, signed payload hash).
public enum SigV4 {
    /// Adds `x-amz-date`, `x-amz-content-sha256` and `Authorization` to `request`.
    /// Every header already on the request is signed along with `host`.
    public static func sign(_ request: inout URLRequest, accessKeyID: String, secretAccessKey: String,
                            region: String, service: String = "s3", date: Date = Date()) {
        let body = request.httpBody ?? Data()
        let payloadHash = hex(SHA256.hash(data: body))
        let amzDate = timestamp(date, "yyyyMMdd'T'HHmmss'Z'")
        let day = String(amzDate.prefix(8))
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")

        let url = request.url!
        var headers: [String: String] = [:]
        for (k, v) in request.allHTTPHeaderFields ?? [:] {
            headers[k.lowercased()] = v.trimmingCharacters(in: .whitespaces)
        }
        headers["host"] = url.port.map { "\(url.host!):\($0)" } ?? url.host!
        let names = headers.keys.sorted()
        let canonicalHeaders = names.map { "\($0):\(headers[$0]!)\n" }.joined()
        let signedHeaders = names.joined(separator: ";")

        let canonicalRequest = [
            request.httpMethod ?? "GET",
            canonicalPath(url),
            canonicalQuery(url),
            canonicalHeaders,
            signedHeaders,
            payloadHash,
        ].joined(separator: "\n")

        let scope = "\(day)/\(region)/\(service)/aws4_request"
        let stringToSign = ["AWS4-HMAC-SHA256", amzDate, scope,
                            hex(SHA256.hash(data: Data(canonicalRequest.utf8)))].joined(separator: "\n")
        var key = SymmetricKey(data: Data("AWS4\(secretAccessKey)".utf8))
        for part in [day, region, service, "aws4_request"] { key = SymmetricKey(data: hmac(key, part)) }
        let signature = hex(hmac(key, stringToSign))
        request.setValue(
            "AWS4-HMAC-SHA256 Credential=\(accessKeyID)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)",
            forHTTPHeaderField: "Authorization")
    }

    static func canonicalPath(_ url: URL) -> String {
        let path = url.path(percentEncoded: true)
        return path.isEmpty ? "/" : path
    }

    static func canonicalQuery(_ url: URL) -> String {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQueryItems else { return "" }
        return items.map { "\($0.name)=\($0.value ?? "")" }.sorted().joined(separator: "&")
    }

    private static func hmac(_ key: SymmetricKey, _ string: String) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: Data(string.utf8), using: key))
    }

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func timestamp(_ date: Date, _ format: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = format
        return f.string(from: date)
    }
}

/// Uploads one object with a signed PUT and returns its public URL.
public struct ObjectStorageUploader: Sendable {
    public let config: ObjectStorageConfig
    let transport: HTTPTransport

    public init(config: ObjectStorageConfig, transport: HTTPTransport = URLSession.shared) {
        self.config = config
        self.transport = transport
    }

    public func upload(_ data: Data, key: String, contentType: String, date: Date = Date()) async throws -> URL {
        let encodedKey = key.split(separator: "/").map { Self.encode(String($0)) }.joined(separator: "/")
        var url = config.endpoint
        url.append(path: config.bucket, directoryHint: .notDirectory)
        let target = URL(string: url.absoluteString + "/" + encodedKey)!
        var request = URLRequest(url: target)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        SigV4.sign(&request, accessKeyID: config.accessKeyID, secretAccessKey: config.secretAccessKey,
                   region: config.region, date: date)
        let (body, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw ObjectStorageError(status: response.statusCode,
                                     message: String(decoding: body.prefix(300), as: UTF8.self))
        }
        let base = config.publicBaseURL.absoluteString.hasSuffix("/")
            ? String(config.publicBaseURL.absoluteString.dropLast()) : config.publicBaseURL.absoluteString
        return URL(string: base + "/" + encodedKey)!
    }

    /// Object key for a new attachment: dated prefix plus a random name, so URLs are not guessable.
    public static func attachmentKey(date: Date = Date(), id: UUID = UUID(), ext: String = "jpg") -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy/MM"
        return "omt/\(f.string(from: date))/\(id.uuidString.lowercased()).\(ext)"
    }

    static func encode(_ segment: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return segment.addingPercentEncoding(withAllowedCharacters: allowed)!
    }
}

/// Re-encodes an image file as JPEG (Instagram accepts JPEG only), capping the long edge.
public enum ImageEncoding {
    public static let maxPixelSize = 2048

    public static func jpeg(from file: URL, maxPixelSize: Int = maxPixelSize, quality: Double = 0.9) throws -> Data {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { throw CocoaError(.fileReadCorruptFile) }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,  // apply EXIF orientation
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
        return out as Data
    }
}
