import PDFKit
import AppKit
import UniformTypeIdentifiers

class OrgChartProcessor: ObservableObject {
    @Published var isProcessing = false
    @Published var processingStatus = ""
    @Published var error: String?
    
    private let openAIService = AIService.shared
    
    func processOrgChartFile(_ fileURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        print("🔍 [OrgChart] Starting file processing: \(fileURL.lastPathComponent)")
        
        DispatchQueue.main.async {
            self.isProcessing = true
            self.processingStatus = "Analyzing file..."
            self.error = nil
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let fileExtension = fileURL.pathExtension.lowercased()
            print("🔍 [OrgChart] File extension detected: \(fileExtension)")
            
            do {
                var images: [NSImage] = []
                
                switch fileExtension {
                case "pdf":
                    print("🔍 [OrgChart] Processing as PDF file")
                    self.updateStatus("Converting PDF to images...")
                    images = try self.convertPDFToImages(fileURL)
                    print("🔍 [OrgChart] PDF converted to \(images.count) images")
                    
                case "ppt", "pptx":
                    print("🔍 [OrgChart] PowerPoint file detected - showing error")
                    self.updateStatus("Processing PowerPoint file...")
                    // PowerPoint files need to be converted to images first
                    // For now, we'll provide a helpful error message
                    throw NSError(domain: "OrgChartProcessor", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "PowerPoint files are not directly supported yet.",
                        NSLocalizedRecoverySuggestionErrorKey: "Please export your PowerPoint slide as a PDF or image (PNG/JPEG) and try again."
                    ])
                    
                case "jpg", "jpeg", "png", "tiff", "gif", "bmp":
                    print("🔍 [OrgChart] Processing as image file")
                    self.updateStatus("Loading image...")
                    guard let image = NSImage(contentsOf: fileURL) else {
                        print("❌ [OrgChart] Failed to load image from: \(fileURL)")
                        throw NSError(domain: "OrgChartProcessor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to load image file"])
                    }
                    print("🔍 [OrgChart] Image loaded successfully, size: \(image.size)")
                    images = [image]
                    
                default:
                    print("❌ [OrgChart] Unsupported file type: \(fileExtension)")
                    throw NSError(domain: "OrgChartProcessor", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unsupported file type: \(fileExtension)"])
                }
                
                guard !images.isEmpty else {
                    throw NSError(domain: "OrgChartProcessor", code: 4, userInfo: [NSLocalizedDescriptionKey: "No images could be extracted from the file"])
                }
                
                self.processImagesWithAI(images) { result in
                    DispatchQueue.main.async {
                        self.isProcessing = false
                        self.processingStatus = ""
                        self.error = nil
                    }
                    completion(result)
                }
                
            } catch {
                print("❌ [OrgChart] Error during file processing: \(error)")
                DispatchQueue.main.async {
                    self.error = error.localizedDescription
                    self.isProcessing = false
                    self.processingStatus = ""
                }
                completion(.failure(error))
            }
        }
    }
    
    private func updateStatus(_ status: String) {
        DispatchQueue.main.async {
            self.processingStatus = status
        }
    }
    
    private func convertPDFToImages(_ pdfURL: URL) throws -> [NSImage] {
        guard let pdfDocument = PDFDocument(url: pdfURL) else {
            throw PDFProcessingError.invalidPDF
        }
        
        var images: [NSImage] = []
        let pageCount = pdfDocument.pageCount
        
        for pageIndex in 0..<min(pageCount, 5) { // Limit to first 5 pages
            guard let page = pdfDocument.page(at: pageIndex) else { continue }
            
            let pageRect = page.bounds(for: .mediaBox)
            
            // Create high-resolution image
            let scale: CGFloat = 2.0 // 2x for better quality
            let imageSize = CGSize(
                width: pageRect.width * scale,
                height: pageRect.height * scale
            )
            
            guard let bitmapRep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(imageSize.width),
                pixelsHigh: Int(imageSize.height),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .calibratedRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else {
                continue
            }
            
            let context = NSGraphicsContext(bitmapImageRep: bitmapRep)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            
            // Scale and draw the PDF page
            context?.cgContext.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context!.cgContext)
            
            NSGraphicsContext.restoreGraphicsState()
            
            // Convert to NSImage
            if let cgImage = bitmapRep.cgImage {
                images.append(NSImage(cgImage: cgImage, size: imageSize))
            }
        }
        
        if images.isEmpty {
            throw PDFProcessingError.noImagesExtracted
        }
        
        return images
    }
    
    private func processImagesWithAI(_ images: [NSImage], completion: @escaping (Result<String, Error>) -> Void) {
        print("🔍 [OrgChart] Starting AI processing with \(images.count) images")
        
        updateStatus("Analyzing org chart with AI...")
        
        let prompt = """
        Please analyze this organizational chart image and extract the team member information. 
        Return the data in CSV format with the following columns: Name, Role, Direct Report, Manager, Timezone
        
        Guidelines:
        - Name: Full name of the person
        - Role: Their job title or position
        - Direct Report: true if they report directly to you/the main person, false otherwise
        - Manager: Name of their direct manager (leave empty if unknown)
        - Timezone: Their timezone if mentioned (leave empty if unknown, will default to UTC)
        
        Only return the CSV data, no other text or explanation.
        """
        
        print("🔍 [OrgChart] Converting first image to base64...")
        
        // Process the first image (for now, we'll focus on single image processing)
        guard let firstImage = images.first else {
            print("❌ [OrgChart] No images to process")
            completion(.failure(NSError(domain: "OrgChartProcessor", code: 4, userInfo: [NSLocalizedDescriptionKey: "No images to process"])))
            return
        }
        
        // Convert NSImage to JPEG data and then to base64
        guard let tiffData = firstImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            print("❌ [OrgChart] Failed to convert image to JPEG")
            completion(.failure(NSError(domain: "OrgChartProcessor", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to process image"])))
            return
        }
        
        let base64String = jpegData.base64EncodedString()
        print("🔍 [OrgChart] Image converted to base64, size: \(base64String.count) characters")
        
        print("🔍 [OrgChart] Sending request to OpenAI Vision API...")
        
        openAIService.analyzeImageWithVision(imageData: base64String, prompt: prompt) { result in
            print("🔍 [OrgChart] Received response from OpenAI Vision API")
            
            switch result {
            case .success(let csvContent):
                print("✅ [OrgChart] AI analysis successful")
                print("🔍 [OrgChart] CSV content preview (first 200 chars): \(String(csvContent.prefix(200)))")
                
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.processingStatus = ""
                    self.error = nil
                }
                completion(.success(csvContent))
                
            case .failure(let error):
                print("❌ [OrgChart] AI analysis failed: \(error)")
                
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.processingStatus = ""
                    self.error = "AI analysis failed: \(error.localizedDescription)"
                }
                completion(.failure(error))
            }
        }
    }
}

enum PDFProcessingError: LocalizedError {
    case invalidPDF
    case noImagesExtracted
    case aiProcessingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidPDF:
            return "Invalid PDF file"
        case .noImagesExtracted:
            return "Could not extract images from PDF"
        case .aiProcessingFailed:
            return "AI processing failed"
        }
    }
}
