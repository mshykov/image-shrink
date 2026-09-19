import AppIntents
import Foundation
import UniformTypeIdentifiers

/// The Shortcuts action. Automator is the old surface; this is the one Apple builds on now.
@available(macOS 13.0, *)
struct ConvertToJPEGIntent: AppIntent {
    static var title: LocalizedStringResource = "Convert Images to JPEG"
    static var description = IntentDescription(
        "Converts HEIC, JPEG or PNG files to JPEG under a size limit, next to the originals.")
    static var openAppWhenRun = false

    // supportedContentTypes on an array parameter needs macOS 15; the engine filters anyway.
    @Parameter(title: "Images")
    var images: [IntentFile]

    @Parameter(title: "Maximum megabytes", default: 2.0,
               inclusiveRange: (0.05, 50))
    var megabytes: Double

    @Parameter(title: "Longest side in pixels, 0 to keep the original", default: 0)
    var longestSide: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Convert \(\.$images) to JPEG under \(\.$megabytes) MB")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        var settings = ConversionSettings(targetBytes: Int(megabytes * 1_000_000),
                                          maxDimension: longestSide > 0 ? longestSide : nil)
        settings.destinationMode = .sameFolder

        let urls = images.compactMap(\.fileURL)
        let reserver = NameReserver(sources: urls)
        var produced: [IntentFile] = []

        for url in urls {
            let result = Converter.convert(url: url, settings: settings, reserver: reserver)
            if let output = result.output {
                produced.append(IntentFile(fileURL: output, filename: output.lastPathComponent))
            }
        }
        return .result(value: produced)
    }
}
