// MIT License
import XCTest
import CoreImage.CIFilterBuiltins
import TerminalTransport

final class QRImageTests: XCTestCase {
    func testActualRenderedQRCodeDecodesAndAuthenticates() throws {
        let text = "TKQR1/AAECAwQFBgcICQoLDA0ODw/1/1/7302a74d3d804695fc6c8945be8bf494e57545414c25b0a95fc747c053de2b0f/VEtRUgEAAQIDBAUGBwgJCgsMDQ4PAAAAAGVT8QAAAAAAZVPyLBAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKisAAAB1dzoxbFc_MKQS5Bnit4hvxnmmPc3Pahy7KDlqGdNoyAFSndpZlvHzzHE1ISzDvGMPnrsW7gg5YuHdCF5HTyqxtCe4lGTKv18WXSrDNghcufJFgQIFtmMkyXMrLJp0rzSd9SdRy3-IhsUZJvYnWmc0WhafMKgsY7rfTZ9Sgh04Twew_Hdscw"
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8); filter.correctionLevel = "M"
        let image = try XCTUnwrap(filter.outputImage).transformed(by: CGAffineTransform(scaleX: 6, y: 6))
        let cg = try XCTUnwrap(CIContext().createCGImage(image, from: image.extent))
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(), options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let decoded = try XCTUnwrap((detector.features(in: CIImage(cgImage: cg)).first as? CIQRCodeFeature)?.messageString)
        XCTAssertEqual(decoded, text)
        var collector = QRTransferCollector()
        let now = Date(timeIntervalSince1970: 1700000000)
        let packet = try XCTUnwrap(collector.append(decoded, now: now))
        let payload = try packet.open(passphrase: "ABCDEFGHIJKLMNOPQRSTUVWX", now: now)
        XCTAssertEqual(payload.name, "日本語 test vector")
        XCTAssertEqual(String(decoding: payload.key, as: UTF8.self), "test-only-not-a-private-key")
    }
}
