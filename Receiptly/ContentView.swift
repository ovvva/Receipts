import SwiftUI
import Vision

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ReceiptItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let price: String
}

struct ReceiptProcessingResult {
    let recognizedText: String
    let parsedItems: [ReceiptItem]
    let totalAmount: Double
}

final class ReceiptProcessor {
    #if os(iOS)
    func recognizeText(from image: UIImage) -> ReceiptProcessingResult {
        guard let cgImage = cgImage(from: image) else {
            return ReceiptProcessingResult(
                recognizedText: "No text recognized",
                parsedItems: [],
                totalAmount: 0.0
            )
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])

            let observations = request.results ?? []
            let lines = groupedRecognizedLines(from: observations)
            let text = lines.joined(separator: "\n")
            let parsingResult = parseReceipt(text: text)

            return ReceiptProcessingResult(
                recognizedText: text.isEmpty ? "No text recognized" : text,
                parsedItems: parsingResult.items,
                totalAmount: parsingResult.totalAmount
            )
        } catch {
            print("Text recognition failed: \(error.localizedDescription)")
            return ReceiptProcessingResult(
                recognizedText: "No text recognized",
                parsedItems: [],
                totalAmount: 0.0
            )
        }
    }
    #elseif os(macOS)
    func recognizeText(from image: NSImage) -> ReceiptProcessingResult {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return ReceiptProcessingResult(
                recognizedText: "No text recognized",
                parsedItems: [],
                totalAmount: 0.0
            )
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])

            let observations = request.results ?? []
            let lines = groupedRecognizedLines(from: observations)
            let text = lines.joined(separator: "\n")
            let parsingResult = parseReceipt(text: text)

            return ReceiptProcessingResult(
                recognizedText: text.isEmpty ? "No text recognized" : text,
                parsedItems: parsingResult.items,
                totalAmount: parsingResult.totalAmount
            )
        } catch {
            print("Text recognition failed: \(error.localizedDescription)")
            return ReceiptProcessingResult(
                recognizedText: "No text recognized",
                parsedItems: [],
                totalAmount: 0.0
            )
        }
    }
    #endif

    func groupedRecognizedLines(from observations: [VNRecognizedTextObservation]) -> [String] {
        let recognizedBlocks = observations.compactMap { observation -> (text: String, box: CGRect)? in
            guard let candidate = observation.topCandidates(1).first else {
                return nil
            }

            let text = candidate.string
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else {
                return nil
            }

            return (text: text, box: observation.boundingBox)
        }
        .sorted { lhs, rhs in
            let lhsY = lhs.box.midY
            let rhsY = rhs.box.midY

            if abs(lhsY - rhsY) > 0.02 {
                return lhsY > rhsY
            }

            return lhs.box.minX < rhs.box.minX
        }

        var rows: [[(text: String, box: CGRect)]] = []

        for block in recognizedBlocks {
            if let rowIndex = rows.firstIndex(where: { row in
                belongsToSameRow(block.box, as: row.map(\.box))
            }) {
                rows[rowIndex].append(block)
                continue
            }

            rows.append([block])
        }

        return rows.map { row in
            row
                .sorted { $0.box.minX < $1.box.minX }
                .map(\.text)
                .joined(separator: " ")
        }
    }

    func parseReceipt(text: String) -> (items: [ReceiptItem], totalAmount: Double) {
        let lines = text.components(separatedBy: "\n")
        let pattern = #"\d+[.,]\d{2}"#
        let excludedKeywords = [
            "total",
            "tax",
            "subtotal",
            "receipt",
            "company",
            "address",
            "date",
            "manager",
            "description",
            "price",
            "thank you"
        ]
        var total = 0.0

        var items: [ReceiptItem] = []
        var pendingName: String?

        for rawLine in lines {
            let line = rawLine
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !line.isEmpty else {
                continue
            }

            let loweredLine = line.lowercased()
            guard !excludedKeywords.contains(where: loweredLine.contains) else {
                pendingName = nil
                continue
            }

            if let priceRange = line.range(of: pattern, options: .regularExpression) {
                let price = String(line[priceRange])
                let normalizedPrice = price.replacingOccurrences(of: ",", with: ".")

                guard let amount = Double(normalizedPrice) else {
                    continue
                }

                total += amount

                let inlineName = cleanedItemName(
                    from: line.replacingCharacters(in: priceRange, with: "")
                )

                let resolvedName = inlineName.isEmpty
                    ? cleanedItemName(from: pendingName ?? "Item")
                    : inlineName

                items.append(ReceiptItem(name: resolvedName.capitalized, price: price))
                pendingName = nil
                continue
            }

            if line.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil {
                pendingName = cleanedItemName(from: line)
            }
        }

        return (items, total)
    }

    private func belongsToSameRow(_ box: CGRect, as rowBoxes: [CGRect]) -> Bool {
        let rowMinY = rowBoxes.map(\.minY).min() ?? 0
        let rowMaxY = rowBoxes.map(\.maxY).max() ?? 0
        let rowHeight = rowMaxY - rowMinY
        let overlap = min(box.maxY, rowMaxY) - max(box.minY, rowMinY)

        guard overlap > 0 else {
            return false
        }

        let minimumHeight = min(box.height, rowHeight)
        guard minimumHeight > 0 else {
            return false
        }

        return overlap / minimumHeight >= 0.45
    }

    private func cleanedItemName(from text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[\s\$\.,:;!]+$"#, with: "", options: .regularExpression)
    }

    #if os(iOS)
    private func cgImage(from image: UIImage) -> CGImage? {
        if let cgImage = image.cgImage {
            return cgImage
        }

        guard let ciImage = image.ciImage else {
            return nil
        }

        let context = CIContext(options: nil)
        return context.createCGImage(ciImage, from: ciImage.extent)
    }
    #endif
}

#if os(iOS)
struct ContentView: View {
    @State private var showSourceDialog = false
    @State private var showImagePicker = false
    @State private var pickerSourceType: UIImagePickerController.SourceType = .photoLibrary
    @State private var selectedImage: UIImage?
    @State private var imageLoadingError: String?
    @State private var recognizedText = ""
    @State private var parsedItems: [ReceiptItem] = []
    @State private var totalAmount = 0.0

    private let receiptProcessor = ReceiptProcessor()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Receiptly")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Button {
                    showSourceDialog = true
                } label: {
                    Text("Scan Receipt")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                .padding(.horizontal)

                if let selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 320, maxHeight: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)

                    ScrollView {
                        Text(recognizedText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .frame(maxHeight: 200)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)

                    if !parsedItems.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Parsed Items")
                                .font(.headline)

                            List(parsedItems) { item in
                                HStack {
                                    Text(item.name)
                                    Spacer()
                                    Text(item.price)
                                }
                            }
                            .frame(height: min(CGFloat(parsedItems.count) * 52 + 20, 360))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                            HStack {
                                Text("Total")
                                    .font(.headline)
                                Spacer()
                                Text(String(format: "$%.2f", totalAmount))
                                    .font(.headline)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal)
                    }
                } else if let imageLoadingError {
                    Text(imageLoadingError)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .confirmationDialog("Select Image Source", isPresented: $showSourceDialog, titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo") {
                    pickerSourceType = .camera
                    showImagePicker = true
                }
            }

            Button("Choose Photo") {
                pickerSourceType = .photoLibrary
                showImagePicker = true
            }

            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(sourceType: pickerSourceType) { image in
                processSelectedImage(image)
            }
        }
    }

    private func processSelectedImage(_ image: UIImage?) {
        guard let image else {
            imageLoadingError = "Could not load the image."
            selectedImage = nil
            recognizedText = ""
            parsedItems = []
            totalAmount = 0.0
            return
        }

        selectedImage = image
        imageLoadingError = nil

        let result = receiptProcessor.recognizeText(from: image)
        recognizedText = result.recognizedText
        parsedItems = result.parsedItems
        totalAmount = result.totalAmount
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onImagePicked: (UIImage?) -> Void

        init(onImagePicked: @escaping (UIImage?) -> Void) {
            self.onImagePicked = onImagePicked
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            onImagePicked(nil)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            picker.dismiss(animated: true)
            onImagePicked(image)
        }
    }
}
#else
struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Receiptly")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Open this target on an iOS destination to use photo and camera receipt scanning.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
        .padding()
    }
}
#endif

#Preview {
    ContentView()
}
