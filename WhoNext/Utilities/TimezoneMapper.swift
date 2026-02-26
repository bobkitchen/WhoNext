import Foundation

enum TimezoneMapper {
    static func mapLocationToTimezone(_ location: String) -> String {
        let lowercased = location.lowercased()

        let timezoneMap: [(keywords: [String], timezone: String)] = [
            // Africa
            (["kenya", "nairobi"], "Africa/Nairobi"),
            (["ethiopia", "addis"], "Africa/Addis_Ababa"),
            (["nigeria", "lagos"], "Africa/Lagos"),
            (["south africa", "johannesburg", "cape town"], "Africa/Johannesburg"),
            (["egypt", "cairo"], "Africa/Cairo"),
            (["morocco", "casablanca"], "Africa/Casablanca"),
            (["ghana", "accra"], "Africa/Accra"),
            (["tanzania", "dar es salaam"], "Africa/Dar_es_Salaam"),
            (["uganda", "kampala"], "Africa/Kampala"),
            (["rwanda", "kigali"], "Africa/Kigali"),
            (["senegal", "dakar"], "Africa/Dakar"),
            (["democratic republic of congo", "kinshasa", "drc"], "Africa/Kinshasa"),

            // Europe
            (["london", "uk", "united kingdom", "england", "britain"], "Europe/London"),
            (["paris", "france"], "Europe/Paris"),
            (["berlin", "germany"], "Europe/Berlin"),
            (["amsterdam", "netherlands"], "Europe/Amsterdam"),
            (["madrid", "spain"], "Europe/Madrid"),
            (["rome", "italy"], "Europe/Rome"),
            (["zurich", "switzerland", "geneva"], "Europe/Zurich"),
            (["stockholm", "sweden"], "Europe/Stockholm"),
            (["oslo", "norway"], "Europe/Oslo"),
            (["copenhagen", "denmark"], "Europe/Copenhagen"),
            (["dublin", "ireland"], "Europe/Dublin"),
            (["brussels", "belgium"], "Europe/Brussels"),
            (["vienna", "austria"], "Europe/Vienna"),
            (["warsaw", "poland"], "Europe/Warsaw"),
            (["prague", "czech"], "Europe/Prague"),

            // Americas
            (["new york", "nyc", "eastern"], "America/New_York"),
            (["los angeles", "la", "california", "pacific"], "America/Los_Angeles"),
            (["chicago", "central"], "America/Chicago"),
            (["denver", "mountain"], "America/Denver"),
            (["seattle", "washington"], "America/Los_Angeles"),
            (["san francisco", "sf", "bay area"], "America/Los_Angeles"),
            (["boston", "massachusetts"], "America/New_York"),
            (["miami", "florida"], "America/New_York"),
            (["atlanta", "georgia"], "America/New_York"),
            (["dallas", "texas", "houston", "austin"], "America/Chicago"),
            (["phoenix", "arizona"], "America/Phoenix"),
            (["toronto", "ontario", "canada"], "America/Toronto"),
            (["vancouver", "british columbia"], "America/Vancouver"),
            (["mexico city", "mexico"], "America/Mexico_City"),
            (["sao paulo", "brazil", "rio"], "America/Sao_Paulo"),
            (["buenos aires", "argentina"], "America/Argentina/Buenos_Aires"),
            (["bogota", "colombia"], "America/Bogota"),
            (["lima", "peru"], "America/Lima"),
            (["santiago", "chile"], "America/Santiago"),

            // Asia
            (["tokyo", "japan"], "Asia/Tokyo"),
            (["beijing", "china", "shanghai"], "Asia/Shanghai"),
            (["hong kong"], "Asia/Hong_Kong"),
            (["singapore"], "Asia/Singapore"),
            (["india", "mumbai", "delhi", "bangalore", "chennai"], "Asia/Kolkata"),
            (["dubai", "uae", "abu dhabi"], "Asia/Dubai"),
            (["seoul", "korea", "south korea"], "Asia/Seoul"),
            (["bangkok", "thailand"], "Asia/Bangkok"),
            (["jakarta", "indonesia"], "Asia/Jakarta"),
            (["manila", "philippines"], "Asia/Manila"),
            (["kuala lumpur", "malaysia"], "Asia/Kuala_Lumpur"),
            (["vietnam", "ho chi minh", "hanoi"], "Asia/Ho_Chi_Minh"),
            (["pakistan", "karachi", "lahore"], "Asia/Karachi"),
            (["bangladesh", "dhaka"], "Asia/Dhaka"),
            (["israel", "tel aviv", "jerusalem"], "Asia/Jerusalem"),
            (["turkey", "istanbul", "ankara"], "Europe/Istanbul"),
            (["saudi arabia", "riyadh"], "Asia/Riyadh"),
            (["jordan", "amman"], "Asia/Amman"),
            (["lebanon", "beirut"], "Asia/Beirut"),
            (["iraq", "baghdad"], "Asia/Baghdad"),
            (["iran", "tehran"], "Asia/Tehran"),
            (["afghanistan", "kabul"], "Asia/Kabul"),
            (["nepal", "kathmandu"], "Asia/Kathmandu"),
            (["sri lanka", "colombo"], "Asia/Colombo"),
            (["myanmar", "yangon"], "Asia/Yangon"),

            // Oceania
            (["sydney", "australia", "melbourne", "brisbane"], "Australia/Sydney"),
            (["perth", "western australia"], "Australia/Perth"),
            (["auckland", "new zealand", "wellington"], "Pacific/Auckland"),

            // US States
            (["washington dc", "dc", "virginia", "maryland"], "America/New_York"),
        ]

        for (keywords, timezone) in timezoneMap {
            for keyword in keywords {
                if lowercased.contains(keyword) {
                    return timezone
                }
            }
        }

        return "UTC"
    }
}
