import Cocoa
@preconcurrency import Vision
import CoreGraphics
import Foundation
import CoreImage

@MainActor
class OCRService {
    private let settingsManager: SettingsManager
    private let geminiService: GeminiService

    init(settingsManager: SettingsManager, geminiService: GeminiService) {
        self.settingsManager = settingsManager
        self.geminiService = geminiService
    }

    /// Extracts text from an image using Cloud OCR (Gemini) or Vision framework
    func extractText(from image: CGImage, completion: @escaping (String?) -> Void) {
        if settingsManager.useCloudOCR {
            print("☁️ Using Cloud OCR (Gemini 1.5 Flash)...")
            // CRITICAL FIX: Run image preprocessing on background thread to prevent UI freeze
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                // Preprocess image for better cloud recognition (heavy operation - runs on background)
                let processedImage = self.preprocessImage(image) ?? image
                
                // Return to main thread for Gemini service call (if needed)
                Task { @MainActor in
                    self.geminiService.performOCR(image: processedImage) { [weak self] text in
                        if let text = text, !text.isEmpty {
                            print("✓ Cloud OCR Success!")
                            completion(text)
                        } else {
                            // Check if failure was due to rate limit (already shown alert in GeminiService)
                            // If not rate limit, silently fallback to local OCR
                            print("⚠️ Cloud OCR failed, falling back to local OCR...")
                            // Fallback to local OCR
                            self?.extractTextWithVision(from: image, completion: completion)
                        }
                    }
                }
            }
        } else {
            // Use local Vision OCR
            extractTextWithVision(from: image, completion: completion)
        }
    }

    /// Extracts text from an image using Vision framework
    /// Performs both text recognition and barcode/QR code detection in parallel
    /// VNImageRequestHandler is created inside the background queue to avoid Sendable warnings
    private func extractTextWithVision(from image: CGImage, completion: @escaping (String?) -> Void) {
        // Create text recognition request
        let textRequest = VNRecognizeTextRequest { request, error in
            if let error = error {
                print("❌ OCR Error: \(error.localizedDescription)")
            }
        }
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        textRequest.recognitionLanguages = ["en-US", "he-IL"]
        
        // Create barcode detection request
        let barcodeRequest = VNDetectBarcodesRequest { request, error in
            if let error = error {
                print("❌ Barcode Detection Error: \(error.localizedDescription)")
            }
        }
        // Configure barcode request to detect all supported symbologies
        barcodeRequest.symbologies = [
            .qr, .aztec, .code128, .code39, .code93,
            .dataMatrix, .ean13, .ean8, .i2of5, .itf14, .pdf417,
            .upce
        ]
        
        // Process both requests in parallel on background thread
        // Vision framework processes multiple requests efficiently in a single pass
        DispatchQueue.global(qos: .userInitiated).async {
            // Preprocess image to improve local OCR accuracy (contrast/grayscale)
            let processedCGImage = self.preprocessImage(image) ?? image
            
            let requestHandler = VNImageRequestHandler(cgImage: processedCGImage, options: [:])
            
            var recognizedText: String?
            var barcodePayload: String?
            var barcodeType: String?
            
            // Perform both requests in a single call (Vision processes them efficiently)
            do {
                try requestHandler.perform([textRequest, barcodeRequest])
                
                // Process text recognition results
                if let observations = textRequest.results as? [VNRecognizedTextObservation] {
                    let recognizedStrings = observations.compactMap {
                        observation in
                        observation.topCandidates(1).first?.string
                    }
                    recognizedText = recognizedStrings.joined(separator: "\n")
                    
                    if !(recognizedText?.isEmpty ?? true) {
                        print("✓ OCR Success! Recognized \(recognizedStrings.count) lines")
                    }
                }
                
                // Process barcode detection results
                if let observations = barcodeRequest.results as? [VNBarcodeObservation] {
                    // Get the first detected barcode (prioritize QR codes)
                    let qrCodes = observations.filter { $0.symbology == .qr }
                    let otherBarcodes = observations.filter { $0.symbology != .qr }
                    
                    let priorityBarcode = (qrCodes.first ?? otherBarcodes.first)
                    
                    if let barcode = priorityBarcode, let payload = barcode.payloadStringValue {
                        barcodePayload = payload
                        barcodeType = barcode.symbology == .qr ? "QR" : "Barcode"
                        print("✓ \(barcodeType!): \(payload.prefix(50))...")
                    }
                }
            } catch {
                print("❌ Failed to perform Vision requests: \(error.localizedDescription)")
            }
            
            // Combine results: append barcode to text if found
            var finalResult: String?
            
            // Start with recognized text (if any)
            var result = recognizedText ?? ""
            
            // Append barcode/QR code payload if detected
            if let barcode = barcodePayload {
                let prefix = barcodeType == "QR" ? "[QR]: " : "[Barcode]: "
                if result.isEmpty {
                    result = prefix + barcode
                } else {
                    result += "\n" + prefix + barcode
                }
            }
            
            // Only return result if we have content
            if !result.isEmpty {
                finalResult = result
            }
            
            // Return result on main thread
            DispatchQueue.main.async {
                if finalResult == nil {
                    print("📝 No text or barcode recognized")
                }
                completion(finalResult)
            }
        }
    }
    
    // MARK: - Image Preprocessing
    
    /// Preprocesses the image to improve OCR accuracy
    /// Applies dynamic upscaling for small images based on source resolution,
    /// grayscale conversion, contrast enhancement, and noise reduction.
    nonisolated private func preprocessImage(_ image: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: image)
        let imageWidth = ciImage.extent.width
        let imageHeight = ciImage.extent.height
        let minDimension = min(imageWidth, imageHeight)
        let maxDimension = max(imageWidth, imageHeight)
        
        var processedCIImage = ciImage
        
        // Dynamic upscaling: Only upscale if image is below threshold
        // Calculate scale factor based on source resolution to avoid over-processing
        if minDimension < JoyaFixConstants.ocrMinDimensionThreshold {
            // Calculate dynamic scale factor to reach target minimum dimension
            // Scale factor is based on how much we need to scale the smallest dimension
            let targetScale = JoyaFixConstants.ocrTargetMinDimension / minDimension
            
            // Clamp scale factor to reasonable bounds
            let scaleFactor = min(max(targetScale, JoyaFixConstants.ocrMinScaleFactor), JoyaFixConstants.ocrMaxScaleFactor)
            
            // Only upscale if it makes sense (scale factor > 1.0)
            if scaleFactor > 1.0 {
                let originalSize = ciImage.extent.size
                print("🚀 Preprocessing: Upscaling small image (from \(originalSize) with \(String(format: "%.2f", scaleFactor))x scale)")
                
                let scaleFilter = CIFilter(name: "CILanczosScaleTransform")!
                scaleFilter.setValue(ciImage, forKey: kCIInputImageKey)
                scaleFilter.setValue(scaleFactor, forKey: kCIInputScaleKey)
                scaleFilter.setValue(1.0, forKey: kCIInputAspectRatioKey)
                
                if let scaledImage = scaleFilter.outputImage {
                    processedCIImage = scaledImage
                    let newSize = scaledImage.extent.size
                    print("   Upscaled to: \(newSize) (effective scale: \(String(format: "%.2f", newSize.width / originalSize.width))x)")
                }
            }
        } else {
            // Image is already large enough - no upscaling needed
            // This avoids over-processing large captures
            print("ℹ️ Preprocessing: Image size (\(Int(imageWidth))×\(Int(imageHeight))) is sufficient, skipping upscaling")
        }

        // 1. Convert to Monochrome (Grayscale)
        // This removes color noise which can confuse OCR
        let grayFilter = CIFilter(name: "CIPhotoEffectMono")
        grayFilter?.setValue(processedCIImage, forKey: kCIInputImageKey) // Use upscaled image
        
        guard let grayOutput = grayFilter?.outputImage else { return nil }
        
        // 2. Increase Contrast (Binarization-like effect)
        // Makes text stand out against the background
        let contrastFilter = CIFilter(name: "CIColorControls")
        contrastFilter?.setValue(grayOutput, forKey: kCIInputImageKey)
        // Bump contrast a bit more for potentially clearer text
        contrastFilter?.setValue(2.0, forKey: kCIInputContrastKey) // Increased from 1.5 to 2.0
        contrastFilter?.setValue(0.0, forKey: kCIInputBrightnessKey)
        contrastFilter?.setValue(0.0, forKey: kCIInputSaturationKey)
        
        guard let outputImage = contrastFilter?.outputImage else { return nil }
        
        // Render back to CGImage
        let context = CIContext(options: nil)
        if let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
            return cgImage
        }
        
        return nil
    }
}
