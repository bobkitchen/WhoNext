import Foundation
import PDFKit
import AppKit
import UniformTypeIdentifiers

class LinkedInPDFProcessor: ObservableObject {
    @Published var isProcessing = false
    @Published var processingStatus = ""
    @Published var error: String?
    @Published var processedFiles: [String] = []
    
    private let aiService = AIService.shared
    
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
        var base64Images: [String] = []
        
        for (index, image) in images.enumerated() {
            print("🔍 [LinkedIn] Converting and compressing image \(index + 1)...")
            
            guard let compressedBase64 = compressImageToBase64(image, targetSizeKB: 500) else {
                print("❌ [LinkedIn] Failed to compress image \(index)")
                continue
            }
            
            base64Images.append(compressedBase64)
            print("🔍 [LinkedIn] Image \(index + 1) compressed to base64, size: \(compressedBase64.count) characters (~\(compressedBase64.count / 1024)KB)")
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
        let totalSize = base64Images.reduce(0) { $0 + $1.count }
        print("🔍 [LinkedIn] Total compressed payload size: \(totalSize / 1024)KB (was ~\(images.count * 4000)KB uncompressed)")
        
        // Limit to maximum 8 images to capture more content including education sections
        let imagesToProcess = Array(base64Images.prefix(8))
        if base64Images.count > 8 {
            print("🔍 [LinkedIn] Limiting to first 8 images (was \(base64Images.count))")
        }
        
        // Create professional profile analysis prompt
        let profilePrompt = """
        You are analyzing a LinkedIn profile document. I can see that you're successfully reading work experience details, but you're missing education information that is clearly present.

        CRITICAL: The education section is DEFINITELY present in these images. Look for sections labeled "Education" with university names like:
        - Geneva Graduate Institute
        - University of Leicester
        - Any other schools or institutions

        Please examine EVERY part of ALL images provided and extract information in this format:

        PROFESSIONAL SUMMARY:
        Write 2-3 sentences about the person's professional background based on their current role and experience.

        WORK EXPERIENCE:
        List job titles and companies in this format:
        • Company Name - Job Title (Date Range)

        EDUCATION:
        IMPORTANT: Look specifically for the word "Education" as a section header, then list ALL educational institutions you can see:
        • Institution Name - Degree/Program (Years)
        
        If you cannot find education information, please tell me exactly what sections you CAN see in the images so I can understand what's happening.

        SKILLS & EXPERTISE:
        List any skills, technologies, or areas of expertise mentioned.

        DEBUGGING: If you don't see education information, please list ALL the section headers you can identify in the images (like "Experience", "Education", "Skills", etc.) so I can understand what sections are visible to you.

        Use plain text only - no markdown formatting. Use CAPS for section headers and • for bullet points.
        """
        
        // Use the new multiple images method for better analysis
        if imagesToProcess.count > 1 {
            print("🔍 [LinkedIn] Processing \(imagesToProcess.count) images with multiple image analysis")
            aiService.analyzeMultipleImagesWithVision(imageDataArray: imagesToProcess, prompt: profilePrompt) { result in
                DispatchQueue.main.async {
                    self.isProcessing = false
                }
                completion(result)
            }
        } else {
            print("🔍 [LinkedIn] Processing single image")
            aiService.analyzeImageWithVision(imageData: imagesToProcess[0], prompt: profilePrompt) { result in
                DispatchQueue.main.async {
                    self.isProcessing = false
                }
                completion(result)
            }
        }
    }
    
    private func compressImageToBase64(_ image: NSImage, targetSizeKB: Int) -> String? {
        // First, resize the image to a more reasonable size for AI processing
        let resizedImage = resizeImageForAI(image)
        
        // Start with high quality and progressively reduce if needed
        var compressionQuality: Float = 0.8
        let targetBytes = targetSizeKB * 1024
        
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
                print("🔍 [LinkedIn] Final compressed size: \(currentSizeKB)KB (target: \(targetSizeKB)KB)")
                return base64String
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
        
        return pngData.base64EncodedString()
    }
    
    private func resizeImageForAI(_ image: NSImage) -> NSImage {
        let originalSize = image.size
        
        // Target maximum dimensions that maintain readability for AI
        let maxWidth: CGFloat = 1200
        let maxHeight: CGFloat = 1600
        
        // Calculate scaling factor to fit within max dimensions
        let widthScale = maxWidth / originalSize.width
        let heightScale = maxHeight / originalSize.height
        let scale = min(widthScale, heightScale, 1.0) // Don't upscale
        
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
        }
    }
}
