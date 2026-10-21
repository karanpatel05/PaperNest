// Writes the synthetic sample documents in Samples/ (see Samples/README.md).
// Usage: swift run papernest-samples [output-directory]
import Foundation
import PaperNestTestSupport
import UniformTypeIdentifiers

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Samples", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let samples: [(String, Data)] = [
    ("multilingual-letter.pdf", SyntheticDocuments.textPDF(pages: [
        "Synthetic sample — page 1\nQuarterly statement for testing only.\nTotal: $1,234.56",
        "Échantillon synthétique — page 2\nRelevé trimestriel à des fins de test.\nTotal : 1 234,56 $",
        "Muestra sintética — página 3\nEstado trimestral solo para pruebas.\nAño, señal, ¿qué tal?",
    ])),
    ("rotated-page.pdf", SyntheticDocuments.rotatedPDF(degrees: 90, text: "This page has /Rotate 90")),
    ("password-protected.pdf", SyntheticDocuments.encryptedPDF(text: "Password is: sample", password: "sample")),
    ("receipt-portrait-exif6.jpg", SyntheticDocuments.image(width: 600, height: 900, type: .jpeg, exifOrientation: 6)),
    ("whiteboard-300dpi.png", SyntheticDocuments.image(width: 1275, height: 1650, type: .png, dpi: 300)),
    ("transparent-ink.png", SyntheticDocuments.image(width: 800, height: 600, type: .png, transparentBackground: true)),
]

for (name, data) in samples {
    try data.write(to: output.appendingPathComponent(name))
    print("wrote \(name) (\(data.count) bytes)")
}
