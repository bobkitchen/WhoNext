import Foundation

// MARK: - Search Result

struct LinkedInCandidate: Identifiable, Sendable {
    let id = UUID()
    let url: String
    let name: String
    let headline: String
}

// MARK: - Apify Response

struct LinkedInProfile: Codable, Sendable {
    let firstName: String?
    let lastName: String?
    let headline: String?
    let locationName: String?
    let publicIdentifier: String?
    let positions: [LinkedInPosition]?
    let educations: [LinkedInEducation]?
    let skills: [LinkedInSkill]?
    let summary: String?
    let followerCount: Int?
    let connectionCount: Int?
    let picture: String?

    var fullName: String {
        [firstName, lastName].compactMap { $0 }.joined(separator: " ")
    }

    var currentPosition: LinkedInPosition? {
        positions?.first(where: { $0.current == true }) ?? positions?.first
    }

    func formattedMarkdown() -> String {
        var lines: [String] = []

        // Header
        let name = fullName.isEmpty ? "Unknown" : fullName
        lines.append("**\(name)**")
        if let headline = headline {
            lines.append(headline)
        }
        if let location = locationName {
            lines.append("📍 \(location)")
        }

        // About
        if let summary = summary, !summary.isEmpty {
            lines.append("")
            lines.append("## About")
            lines.append(summary)
        }

        // Experience
        if let positions = positions, !positions.isEmpty {
            lines.append("")
            lines.append("## Experience")
            for pos in positions {
                let title = pos.title ?? "Unknown Role"
                let company = pos.companyName ?? "Unknown Company"
                lines.append("**\(title)** — \(company)")

                var dateRange = pos.formattedDateRange()
                if let duration = pos.formattedDuration() {
                    dateRange += " (\(duration))"
                }
                if !dateRange.isEmpty {
                    lines.append(dateRange)
                }

                if let desc = pos.description, !desc.isEmpty {
                    lines.append(desc)
                }
                lines.append("")
            }
        }

        // Education
        if let educations = educations, !educations.isEmpty {
            lines.append("## Education")
            for edu in educations {
                let school = edu.schoolName ?? "Unknown School"
                var detail = "**\(school)**"
                let qualParts = [edu.degreeName, edu.fieldOfStudy].compactMap { $0 }
                if !qualParts.isEmpty {
                    detail += " — \(qualParts.joined(separator: ", "))"
                }
                lines.append(detail)

                if let start = edu.startYear {
                    let end = edu.endYear.map { String($0) } ?? "Present"
                    lines.append("\(start) – \(end)")
                }
                lines.append("")
            }
        }

        // Skills
        if let skills = skills, !skills.isEmpty {
            lines.append("## Skills")
            lines.append(skills.map(\.skillName).joined(separator: ", "))
        }

        return lines.joined(separator: "\n")
    }
}

struct LinkedInPosition: Codable, Sendable {
    let title: String?
    let companyName: String?
    let companyUrl: String?
    let startYear: Int?
    let startMonth: Int?
    let endYear: Int?
    let endMonth: Int?
    let durationYear: Int?
    let durationMonth: Int?
    let current: Bool?
    let description: String?

    private static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                                      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    func formattedDateRange() -> String {
        guard let startYear = startYear else { return "" }
        let startMonthStr = startMonth.flatMap { m in
            (1...12).contains(m) ? Self.monthNames[m - 1] : nil
        }
        let start = [startMonthStr, String(startYear)].compactMap { $0 }.joined(separator: " ")

        let end: String
        if current == true || endYear == nil {
            end = "Present"
        } else {
            let endMonthStr = endMonth.flatMap { m in
                (1...12).contains(m) ? Self.monthNames[m - 1] : nil
            }
            end = [endMonthStr, endYear.map { String($0) }].compactMap { $0 }.joined(separator: " ")
        }

        return "\(start) – \(end)"
    }

    func formattedDuration() -> String? {
        guard let years = durationYear, let months = durationMonth else { return nil }
        var parts: [String] = []
        if years > 0 { parts.append("\(years) yr\(years == 1 ? "" : "s")") }
        if months > 0 { parts.append("\(months) mo\(months == 1 ? "" : "s")") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

struct LinkedInEducation: Codable, Sendable {
    let schoolName: String?
    let degreeName: String?
    let fieldOfStudy: String?
    let startYear: Int?
    let endYear: Int?
}

struct LinkedInSkill: Codable, Sendable {
    let skillName: String
}
