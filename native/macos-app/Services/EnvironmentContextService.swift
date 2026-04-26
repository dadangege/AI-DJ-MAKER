import Foundation

final class EnvironmentContextService: @unchecked Sendable {
    private var cachedContext: EnvironmentContext?

    func loadEnvironmentContext() async throws -> EnvironmentContext? {
        if let cachedContext {
            return cachedContext
        }

        let location = try await fetchIPLocation()
        guard let latitude = location.latitude, let longitude = location.longitude else {
            throw EnvironmentContextError.message("IP 定位缺少经纬度。")
        }

        let weather = try? await fetchWeather(latitude: latitude, longitude: longitude)
        let context = EnvironmentContext(
            city: location.city,
            region: location.region,
            countryCode: location.countryCode,
            latitude: latitude,
            longitude: longitude,
            temperatureC: weather?.temperatureC,
            weatherCode: weather?.weatherCode,
            weatherLabel: weather?.weatherLabel,
            cloudCover: weather?.cloudCover,
            updatedAt: Date()
        )
        cachedContext = context
        return context
    }

    private func fetchIPLocation() async throws -> IPLocationPayload {
        guard let url = URL(string: "https://ipapi.co/json/") else {
            throw EnvironmentContextError.message("IP 定位 URL 无效。")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("SoulDJ/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw EnvironmentContextError.message("IP 定位失败：HTTP \(http.statusCode)")
        }
        return try JSONDecoder().decode(IPLocationPayload.self, from: data)
    }

    private func fetchWeather(latitude: Double, longitude: Double) async throws -> WeatherPayload {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: "\(latitude)"),
            URLQueryItem(name: "longitude", value: "\(longitude)"),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,precipitation,cloud_cover"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components?.url else {
            throw EnvironmentContextError.message("天气 URL 无效。")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw EnvironmentContextError.message("天气请求失败：HTTP \(http.statusCode)")
        }
        let payload = try JSONDecoder().decode(OpenMeteoPayload.self, from: data)
        return WeatherPayload(
            temperatureC: payload.current.temperature2m,
            weatherCode: payload.current.weatherCode,
            weatherLabel: Self.weatherLabel(for: payload.current.weatherCode),
            cloudCover: payload.current.cloudCover
        )
    }

    private static func weatherLabel(for code: Int?) -> String? {
        guard let code else { return nil }
        switch code {
        case 0: return "晴"
        case 1, 2: return "晴间多云"
        case 3: return "多云"
        case 45, 48: return "雾"
        case 51, 53, 55, 56, 57: return "毛毛雨"
        case 61, 63, 65, 66, 67, 80, 81, 82: return "雨"
        case 71, 73, 75, 77, 85, 86: return "雪"
        case 95, 96, 99: return "雷雨"
        default: return "天气变化中"
        }
    }
}

private struct IPLocationPayload: Decodable {
    let city: String
    let region: String
    let countryCode: String
    let latitude: Double?
    let longitude: Double?

    enum CodingKeys: String, CodingKey {
        case city
        case region
        case countryCode = "country_code"
        case latitude
        case longitude
    }
}

private struct OpenMeteoPayload: Decodable {
    let current: CurrentWeather
}

private struct CurrentWeather: Decodable {
    let temperature2m: Double?
    let weatherCode: Int?
    let cloudCover: Int?

    enum CodingKeys: String, CodingKey {
        case temperature2m = "temperature_2m"
        case weatherCode = "weather_code"
        case cloudCover = "cloud_cover"
    }
}

private struct WeatherPayload {
    let temperatureC: Double?
    let weatherCode: Int?
    let weatherLabel: String?
    let cloudCover: Int?
}

enum EnvironmentContextError: Error, LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): return message
        }
    }
}
