import Foundation
import PDFKit
import AppKit
import UniformTypeIdentifiers
import Vision

/// Result of LinkedIn PDF processing containing extracted profile data
struct LinkedInExtractedData {
    let markdown: String
}

class LinkedInPDFProcessor: ObservableObject {
    @Published var isProcessing = false
    @Published var processingStatus = ""
    @Published var error: String?
    @Published var processedFiles: [String] = []

    private let aiService = AIService.shared

    // MARK: - OCR-Based Processing (New Method)

    /// Process LinkedIn PDFs using Apple Vision OCR + AI parsing
    /// This approach extracts text via OCR first, then uses AI to structure it
    func processLinkedInPDFsWithOCR(_ fileURLs: [URL], completion: @escaping (Result<LinkedInExtractedData, Error>) -> Void) {
        print("📄 [LinkedInPDF] Starting OCR-based processing with \(fileURLs.count) files")

        DispatchQueue.main.async {
            self.isProcessing = true
            self.processingStatus = "Reading PDF files..."
            self.error = nil
            self.processedFiles = []
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var allText: [String] = []

                // Process each PDF file
                for (index, fileURL) in fileURLs.enumerated() {
                    let fileName = fileURL.lastPathComponent
                    print("📄 [LinkedInPDF] Processing file \(index + 1)/\(fileURLs.count): \(fileName)")

                    self.updateStatus("Reading \(fileName)...")

                    guard fileURL.pathExtension.lowercased() == "pdf" else {
                        throw LinkedInProcessingError.invalidFileType
                    }

                    guard let pdfDocument = PDFDocument(url: fileURL) else {
                        throw LinkedInProcessingError.invalidPDF
                    }

                    // Convert PDF pages to images and OCR
                    self.updateStatus("Extracting text from \(fileName)...")
                    let images = try self.convertPDFToImages(pdfDocument)

                    for (pageIndex, image) in images.enumerated() {
                        self.updateStatus("OCR page \(pageIndex + 1) of \(images.count)...")
                        if let text = try self.performOCR(on: image) {
                            allText.append(text)
                        }
                    }

                    DispatchQueue.main.async {
                        self.processedFiles.append(fileName)
                    }

                    print("📄 [LinkedInPDF] Extracted text from \(images.count) pages in \(fileName)")
                }

                // Combine all extracted text
                let combinedText = allText.joined(separator: "\n\n---PAGE BREAK---\n\n")
                print("📄 [LinkedInPDF] Total OCR text length: \(combinedText.count) characters")

                if combinedText.isEmpty {
                    throw LinkedInProcessingError.noTextExtracted
                }

                // Use AI to parse the text into structured markdown
                self.updateStatus("Structuring profile data...")
                self.parseTextWithAI(combinedText) { result in
                    DispatchQueue.main.async {
                        self.isProcessing = false
                    }

                    switch result {
                    case .success(let markdown):
                        completion(.success(LinkedInExtractedData(markdown: markdown)))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }

            } catch {
                print("❌ [LinkedInPDF] Processing failed: \(error)")
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.error = error.localizedDescription
                }
                completion(.failure(error))
            }
        }
    }

    // MARK: - OCR

    private func performOCR(on image: NSImage) throws -> String? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        var recognizedText = ""
        let semaphore = DispatchSemaphore(value: 0)
        var ocrError: Error?

        let request = VNRecognizeTextRequest { request, error in
            defer { semaphore.signal() }

            if let error = error {
                ocrError = error
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }

            // Sort observations by Y position (top to bottom), then X (left to right)
            let sortedObservations = observations.sorted { obs1, obs2 in
                // VNRecognizedTextObservation uses normalized coordinates (0-1, origin bottom-left)
                // Higher Y means higher on the page
                if abs(obs1.boundingBox.midY - obs2.boundingBox.midY) > 0.01 {
                    return obs1.boundingBox.midY > obs2.boundingBox.midY
                }
                return obs1.boundingBox.midX < obs2.boundingBox.midX
            }

            for observation in sortedObservations {
                if let topCandidate = observation.topCandidates(1).first {
                    recognizedText += topCandidate.string + "\n"
                }
            }
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            throw error
        }

        semaphore.wait()

        if let error = ocrError {
            throw error
        }

        return recognizedText.isEmpty ? nil : recognizedText
    }

    // MARK: - AI Parsing

    private func parseTextWithAI(_ ocrText: String, completion: @escaping (Result<String, Error>) -> Void) {
        let prompt = """
        Parse this LinkedIn profile text (extracted via OCR from a PDF) and return structured markdown.

        TEXT FROM LINKEDIN PDF:
        ---
        \(ocrText.prefix(15000))
        ---

        Return markdown in this EXACT format:

        **{Full Name}**
        {Headline/Current Title}

        📍 {Location}

        ## About
        {About section text if present - keep it concise}

        ## Experience
        **{Job Title}**
        {Company Name}
        {Date Range}

        **{Job Title 2}**
        {Company Name}
        {Date Range}

        (Continue for ALL jobs found...)

        ## Education
        **{School Name}**
        {Degree} - {Field of Study}
        {Years}

        ## Skills
        • {Skill 1}
        • {Skill 2}
        • {Skill 3}
        ...

        IMPORTANT RULES:
        1. Extract ALL work experience, not just the first few jobs
        2. Keep exact company and school names from the OCR text
        3. Use bullet points (•) for skills
        4. If a section is missing or empty in the OCR text, omit it entirely
        5. Don't add information that isn't in the OCR text
        6. Keep the markdown clean and well-formatted
        7. Respond ONLY with the formatted markdown, no explanations
        """

        Task {
            do {
                let response = try await aiService.sendMessage(prompt)
                completion(.success(response))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    func processLinkedInPDFs(_ fileURLs: [URL], completion: @escaping (Result<String, Error>) -> Void) {
        print("🔍 [LinkedIn] Starting LinkedIn PDF processing with \(fileURLs.count) files")
        
        DispatchQueue.main.async {
            self.isProcessing = true
            self.processingStatus = "Processing LinkedIn PDFs..."
            self.error = nil
            self.processedFiles = []
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                var allImages: [NSImage] = []
                
                // Process each PDF file
                for (index, fileURL) in fileURLs.enumerated() {
                    let fileName = fileURL.lastPathComponent
                    print("🔍 [LinkedIn] Processing file \(index + 1)/\(fileURLs.count): \(fileName)")
                    
                    self.updateStatus("Processing \(fileName)...")
                    
                    guard fileURL.pathExtension.lowercased() == "pdf" else {
                        throw LinkedInProcessingError.invalidFileType
                    }
                    
                    let images = try self.convertPDFToImages(fileURL)
                    allImages.append(contentsOf: images)
                    
                    DispatchQueue.main.async {
                        self.processedFiles.append(fileName)
                    }
                    
                    print("🔍 [LinkedIn] Converted \(fileName) to \(images.count) images")
                }
                
                print("🔍 [LinkedIn] Total images extracted: \(allImages.count)")
                
                // Process all images with AI
                self.processImagesWithAI(allImages, completion: completion)
                
            } catch {
                print("❌ [LinkedIn] PDF processing failed: \(error)")
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.error = error.localizedDescription
                }
                completion(.failure(error))
            }
        }
    }
    
    private func convertPDFToImages(_ pdfURL: URL) throws -> [NSImage] {
        guard let pdfDocument = PDFDocument(url: pdfURL) else {
            throw LinkedInProcessingError.invalidPDF
        }
        
        return try convertPDFToImages(pdfDocument)
    }
    
    private func convertPDFToImages(_ pdfDocument: PDFDocument) throws -> [NSImage] {
        var images: [NSImage] = []
        
        for pageIndex in 0..<pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }
            
            let pageRect = page.bounds(for: .mediaBox)
            
            // Use a higher resolution for better text recognition
            let scale: CGFloat = 3.0
            let scaledSize = NSSize(width: pageRect.width * scale, height: pageRect.height * scale)
            
            let image = NSImage(size: scaledSize)
            
            image.lockFocus()
            
            // Set up the graphics context for proper rendering
            if let context = NSGraphicsContext.current?.cgContext {
                // Fill with white background
                context.setFillColor(CGColor.white)
                context.fill(CGRect(origin: .zero, size: scaledSize))
                
                // Scale the context
                context.scaleBy(x: scale, y: scale)
                
                // Render the PDF page
                page.draw(with: .mediaBox, to: context)
            }
            
            image.unlockFocus()
            
            images.append(image)
            print("🔍 [LinkedIn] Converted page \(pageIndex + 1) to image, size: \(image.size)")
        }
        
        if images.isEmpty {
            throw LinkedInProcessingError.noImagesExtracted
        }
        
        return images
    }
    
    private func correctImageOrientation(_ image: NSImage) -> NSImage {
        // For now, return the image as-is since we've improved the PDF rendering
        // If orientation issues persist, we can add rotation logic here
        return image
    }
    
    private func processImagesWithAI(_ images: [NSImage], completion: @escaping (Result<String, Error>) -> Void) {
        print("🔍 [LinkedIn] Starting AI processing with \(images.count) images")
        
        updateStatus("Analyzing professional profile with AI...")
        
        // Convert images to compressed base64
        var base64Images: [(base64: String, format: String)] = []
        
        for (index, image) in images.enumerated() {
            print("🔍 [LinkedIn] Converting and compressing image \(index + 1)...")
            
            guard let compressedImage = compressImageToBase64(image) else {
                print("❌ [LinkedIn] Failed to compress image \(index)")
                continue
            }
            
            base64Images.append(compressedImage)
            print("🔍 [LinkedIn] Image \(index + 1) compressed to base64, size: \(compressedImage.base64.count) characters (~\(compressedImage.base64.count / 1024)KB)")
        }
        
        if base64Images.isEmpty {
            let error = LinkedInProcessingError.imageConversionFailed
            DispatchQueue.main.async {
                self.isProcessing = false
                self.error = error.localizedDescription
            }
            completion(.failure(error))
            return
        }
        
        // Calculate total compressed size
        let totalSize = base64Images.reduce(0) { $0 + $1.base64.count }
        print("🔍 [LinkedIn] Total compressed payload size: \(totalSize / 1024)KB (was ~\(images.count * 4000)KB uncompressed)")
        
        // Create professional profile analysis prompt
        let profilePrompt = """
        IMPORTANT: Please respond in English only.
        
        You are analyzing a LinkedIn profile document. These images show pages from a LinkedIn profile PDF export.
        
        Your task is to extract professional information from these LinkedIn profile pages and create a comprehensive summary.
        
        Please examine ALL the images provided and extract information in this format:

        PROFESSIONAL SUMMARY:
        Write 2-3 sentences about the person's professional background based on their current role and experience.

        WORK EXPERIENCE:
        List job titles and companies in this format:
        • Company Name - Job Title (Date Range)

        EDUCATION:
        Look for the "Education" section and list ALL educational institutions:
        • Institution Name - Degree/Program (Years)
        
        SKILLS & EXPERTISE:
        List any skills, technologies, or areas of expertise mentioned.

        DEBUGGING:
        Visible sections include: [List all section headers you can see like "About", "Experience", "Education", "Skills", etc.]

        IMPORTANT INSTRUCTIONS:
        - Respond in English only
        - Use plain text only - no markdown formatting
        - Use CAPS for section headers and • for bullet points
        - If you see multiple pages, analyze ALL of them
        - Education information is typically on later pages (pages 5-8)
        - Look carefully for university names, degrees, and graduation years
        """
        
        // OpenRouter free tier doesn't support vision - use OpenAI/Claude for LinkedIn PDFs
        if aiService.currentProvider == .openrouter {
            // Check if OpenAI is configured as fallback
            if !aiService.openaiApiKey.isEmpty {
                print("ℹ️ [LinkedIn] OpenRouter doesn't support vision analysis")
                print("🔄 [LinkedIn] Using OpenAI for LinkedIn PDF processing")
                
                // Temporarily switch to OpenAI for this request
                let originalProvider = aiService.currentProvider
                aiService.currentProvider = .openai
                
                // Use OpenAI's multi-image processing with full resolution images
                let fullResImages = Array(base64Images.prefix(5)) // Use more images with OpenAI
                print("🔍 [LinkedIn] Processing \(fullResImages.count) images with OpenAI vision")
                
                aiService.analyzeMultipleImagesWithVision(imageDataArray: fullResImages, prompt: profilePrompt) { [self] result in
                    // Restore original provider
                    aiService.currentProvider = originalProvider
                    
                    DispatchQueue.main.async {
                        self.isProcessing = false
                    }
                    completion(result)
                }
                return
            } else {
                // No OpenAI fallback available
                let errorMessage = """
                ⚠️ OpenRouter doesn't support vision analysis for LinkedIn PDFs.
                
                For reliable LinkedIn processing, please:
                1. Go to Settings → AI & Prompts
                2. Add your OpenAI API key
                3. Select "OpenAI (GPT-4)" as AI Provider
                4. Try processing again
                
                OpenAI's vision models are specifically optimized for document analysis.
                """
                
                DispatchQueue.main.async {
                    self.isProcessing = false
                }
                completion(.failure(NSError(domain: "LinkedInProcessor", code: 1, userInfo: [NSLocalizedDescriptionKey: errorMessage])))
                return
            }
        }
        
        // If we reach here, we're using OpenAI or Claude - proceed normally
        let imagesToProcess = Array(base64Images.prefix(5)) // Use more images for cloud providers
        print("🔍 [LinkedIn] Processing \(imagesToProcess.count) images with \(aiService.currentProvider)")
        
        aiService.analyzeMultipleImagesWithVision(imageDataArray: imagesToProcess, prompt: profilePrompt) { result in
            DispatchQueue.main.async {
                self.isProcessing = false
            }
            completion(result)
        }
    }
    
    private func compressImageToBase64(_ image: NSImage) -> (base64: String, format: String)? {
        // All providers now use high-quality images since we removed local processing
        let targetSize = 500_000  // 500KB for all cloud providers
        let maxDimension: CGFloat = 1200  // 1200px max for all providers
        print("🔍 [LinkedIn] Using high-quality images for cloud processing: \(targetSize/1000)KB max, \(maxDimension)px max")
        
        // First, resize the image to a more reasonable size for AI processing
        let resizedImage = resizeImageForAI(image, maxDimension: maxDimension)
        
        // Start with high quality and progressively reduce if needed
        var compressionQuality: Float = 0.8
        let targetBytes = targetSize
        
        guard let tiffData = resizedImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        
        // Try different compression levels until we reach target size
        for attempt in 1...5 {
            let properties: [NSBitmapImageRep.PropertyKey: Any] = [
                .compressionFactor: compressionQuality
            ]
            
            guard let jpegData = bitmap.representation(using: .jpeg, properties: properties) else {
                continue
            }
            
            let base64String = jpegData.base64EncodedString()
            let currentSizeKB = jpegData.count / 1024
            
            print("🔍 [LinkedIn] Compression attempt \(attempt): \(currentSizeKB)KB at quality \(compressionQuality)")
            
            // If we're under target size or this is our last attempt, use this version
            if jpegData.count <= targetBytes || attempt == 5 {
                print("🔍 [LinkedIn] Final compressed size: \(currentSizeKB)KB (target: \(targetSize/1000)KB)")
                return (base64: base64String, format: "jpeg")
            }
            
            // Reduce quality for next attempt
            compressionQuality -= 0.15
            compressionQuality = max(0.1, compressionQuality) // Don't go below 10% quality
        }
        
        // Fallback to PNG if JPEG compression fails
        print("🔍 [LinkedIn] JPEG compression failed, falling back to PNG")
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        return (base64: pngData.base64EncodedString(), format: "png")
    }
    
    private func resizeImageForAI(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let originalSize = image.size
        
        // Calculate scaling factor to fit within max dimensions
        let widthScale = min(maxDimension / originalSize.width, 1.0)
        let heightScale = min(maxDimension / originalSize.height, 1.0)
        let scale = min(widthScale, heightScale) // Don't upscale
        
        let newSize = NSSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )
        
        print("🔍 [LinkedIn] Resizing image from \(originalSize) to \(newSize) (scale: \(scale))")
        
        // If no resizing needed, return original
        if scale >= 1.0 {
            return image
        }
        
        let resizedImage = NSImage(size: newSize)
        resizedImage.lockFocus()
        
        // Draw the original image scaled to the new size
        image.draw(in: NSRect(origin: .zero, size: newSize))
        
        resizedImage.unlockFocus()
        
        return resizedImage
    }
    
    private func updateStatus(_ status: String) {
        DispatchQueue.main.async {
            self.processingStatus = status
        }
    }
}

enum LinkedInProcessingError: LocalizedError {
    case invalidPDF
    case invalidFileType
    case noImagesExtracted
    case imageConversionFailed
    case noTextExtracted

    var errorDescription: String? {
        switch self {
        case .invalidPDF:
            return "Invalid PDF file"
        case .invalidFileType:
            return "Only PDF files are supported"
        case .noImagesExtracted:
            return "No images could be extracted from the PDF"
        case .imageConversionFailed:
            return "Failed to convert images for AI processing"
        case .noTextExtracted:
            return "No text could be extracted from the PDF. Please ensure the PDF is not password-protected."
        }
    }
}
