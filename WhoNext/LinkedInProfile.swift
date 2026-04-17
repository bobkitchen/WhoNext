import Foundation

// MARK: - Search Result

struct LinkedInCandidate: Identifiable, Sendable {
    let id = UUID()
    let url: String
    let name: String
    let headline: String
}

// MARK: - Apify Response (harvestapi~linkedin-profile-scraper)

struct LinkedInProfile: Codable, Sendable {
    let firstName: String?
    let lastName: String?
    let headline: String?
    let about: String?
    let publicIdentifier: String?
    let linkedinUrl: String?
    let photo: String?
    let location: LinkedInLocation?
    let experience: [LinkedInExperience]?
    let education: [LinkedInEducation]?
    let skills: [LinkedInSkill]?

    var fullName: String {
        [firstName, lastName].compactMap { $0 }.joined(separator: " ")
    }

    var locationText: String? {
        location?.linkedinText ?? location?.parsed?.text
    }

    /// harvestapi has no explicit `current` flag. Prefer a role whose endDate is
    /// "Present" or missing; fall back to the first one in the array.
    var currentPosition: LinkedInExperience? {
        experience?.first(where: { $0.isCurrent }) ?? experience?.first
    }

    func formattedMarkdown() -> String {
        var lines: [String] = []

        let name = fullName.isEmpty ? "Unknown" : fullName
        lines.append("**\(name)**")
        if let headline = headline {
            lines.append(headline)
        }
        if let loc = locationText {
            lines.append("📍 \(loc)")
        }

        if let about = about, !about.isEmpty {
            lines.append("")
            lines.append("## About")
            lines.append(about)
        }

        if let experience = experience, !experience.isEmpty {
            lines.append("")
            lines.append("## Experience")
            for exp in experience {
                let title = exp.position ?? "Unknown Role"
                let company = exp.companyName ?? "Unknown Company"
                lines.append("**\(title)** — \(company)")

                var range = exp.formattedDateRange()
                if let duration = exp.duration, !duration.isEmpty {
                    if range.isEmpty {
                        range = duration
                    } else {
                        range += " (\(duration))"
                    }
                }
                if !range.isEmpty {
                    lines.append(range)
                }

                if let desc = exp.description, !desc.isEmpty {
                    lines.append(desc)
                }
                lines.append("")
            }
        }

        if let educations = education, !educations.isEmpty {
            lines.append("## Education")
            for edu in educations {
                let school = edu.schoolName ?? "Unknown School"
                var detail = "**\(school)**"
                let qualParts = [edu.degree, edu.fieldOfStudy].compactMap { $0 }
                if !qualParts.isEmpty {
                    detail += " — \(qualParts.joined(separator: ", "))"
                }
                lines.append(detail)

                let range = edu.formattedDateRange()
                if !range.isEmpty {
                    lines.append(range)
                }
                lines.append("")
            }
        }

        if let skills = skills, !skills.isEmpty {
            let names = skills.compactMap { $0.name }.filter { !$0.isEmpty }
            if !names.isEmpty {
                lines.append("## Skills")
                lines.append(names.joined(separator: ", "))
            }
        }

        return lines.joined(separator: "\n")
    }
}

struct LinkedInLocation: Codable, Sendable {
    let linkedinText: String?
    let countryCode: String?
    let parsed: ParsedLocation?

    struct ParsedLocation: Codable, Sendable {
        let text: String?
        let city: String?
        let state: String?
        let country: String?
    }
}

struct LinkedInExperience: Codable, Sendable {
    let position: String?
    let companyName: String?
    let companyLinkedinUrl: String?
    let duration: String?
    let description: String?
    let startDate: LinkedInDate?
    let endDate: LinkedInDate?

    var isCurrent: Bool {
        endDate?.isPresent ?? (endDate == nil && startDate != nil)
    }

    func formattedDateRange() -> String {
        let start = startDate?.formatted() ?? ""
        if start.isEmpty { return "" }
        let end = endDate?.formatted() ?? "Present"
        return "\(start) – \(end)"
    }
}

struct LinkedInEducation: Codable, Sendable {
    let schoolName: String?
    let degree: String?
    let fieldOfStudy: String?
    let startDate: LinkedInDate?
    let endDate: LinkedInDate?

    func formattedDateRange() -> String {
        let start = startDate?.formatted() ?? ""
        let end = endDate?.formatted() ?? ""
        if start.isEmpty && end.isEmpty { return "" }
        if start.isEmpty { return end }
        if end.isEmpty { return start }
        return "\(start) – \(end)"
    }
}

struct LinkedInSkill: Codable, Sendable {
    let name: String?
}

/// harvestapi returns dates as one of several shapes: `{month: Int, year: Int}`
/// for concrete dates, `{text: "Present"}` for ongoing roles, or an empty
/// object. But the actor also sometimes stringifies numeric fields
/// (`"month": "5"` instead of `5`) — observed in `experience[].startDate` —
/// so we decode `month` and `year` flexibly: try Int, fall back to String,
/// parse either into an Int.
struct LinkedInDate: Codable, Sendable {
    let month: Int?
    let year: Int?
    let text: String?

    private static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    var isPresent: Bool {
        (text?.lowercased() ?? "") == "present"
    }

    func formatted() -> String? {
        if let text = text, !text.isEmpty { return text }
        guard let year = year else { return nil }
        if let month = month, (1...12).contains(month) {
            return "\(Self.monthNames[month - 1]) \(year)"
        }
        return String(year)
    }

    private enum CodingKeys: String, CodingKey {
        case month, year, text
    }

    init(month: Int? = nil, year: Int? = nil, text: String? = nil) {
        self.month = month
        self.year = year
        self.text = text
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.month = Self.decodeFlexibleInt(container, forKey: .month)
        self.year = Self.decodeFlexibleInt(container, forKey: .year)
        self.text = try container.decodeIfPresent(String.self, forKey: .text)
    }

    private static func decodeFlexibleInt(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> Int? {
        if let i = try? container.decode(Int.self, forKey: key) { return i }
        if let s = try? container.decode(String.self, forKey: key) { return Int(s) }
        return nil
    }
}
