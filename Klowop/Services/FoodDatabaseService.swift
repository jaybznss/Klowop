import Foundation

/// Open Food Facts integration — a free, open nutrition database with millions
/// of products. No API key required. Used for food search, barcode lookup, and
/// by the assistant's search_food_database tool.
enum FoodDatabaseService {

    struct FoodItem: Identifiable, Hashable {
        let id: String              // barcode or USDA fdcId
        let name: String
        let brand: String?
        let caloriesPer100g: Double
        let proteinPer100g: Double
        let carbsPer100g: Double
        let fatPer100g: Double
        let servingDescription: String?   // e.g. "30 g"
        let servingGrams: Double?
        let source: String                // "USDA" or "Open Food Facts"

        var displayName: String { brand.map { "\(name) — \($0)" } ?? name }
    }

    enum FoodDBError: LocalizedError {
        case network(String)
        case notFound

        var errorDescription: String? {
            switch self {
            case .network(let message): return "Food database: \(message)"
            case .notFound: return "Product not found in the food database."
            }
        }
    }

    // Open Food Facts asks API users to identify themselves.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = ["User-Agent": "Klowop iOS - personal nutrition app"]
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()

    private static let fields = "code,product_name,brands,nutriments,serving_size,serving_quantity"

    /// Combined search: USDA FoodData Central (authoritative for generic foods)
    /// merged with Open Food Facts (strong on branded products). Either source
    /// failing is tolerated as long as the other answers.
    static func search(_ query: String) async throws -> [FoodItem] {
        async let usdaTask = searchUSDA(query)
        async let offTask = searchOpenFoodFacts(query)
        let usda = (try? await usdaTask) ?? []
        let off = (try? await offTask) ?? []
        guard !(usda.isEmpty && off.isEmpty) else {
            // Distinguish "both unreachable" from "genuinely no matches".
            _ = try await searchOpenFoodFacts(query) // rethrows the real error if OFF failed
            return []
        }
        return usda + off
    }

    // MARK: - USDA FoodData Central

    /// https://fdc.nal.usda.gov — free API key (DEMO_KEY works out of the box
    /// with low rate limits; set a personal key in Settings).
    private static func searchUSDA(_ query: String) async throws -> [FoodItem] {
        let key = AppSettings.shared.usdaAPIKey.isEmpty ? "DEMO_KEY" : AppSettings.shared.usdaAPIKey
        var components = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        components.queryItems = [
            .init(name: "api_key", value: key),
            .init(name: "query", value: query),
            .init(name: "pageSize", value: "12"),
            .init(name: "dataType", value: "Foundation,SR Legacy,Branded"),
        ]
        let (data, response) = try await session.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let foods = json["foods"] as? [[String: Any]] else {
            throw FoodDBError.network("USDA search failed")
        }
        return foods.compactMap(parseUSDA).filter { $0.caloriesPer100g > 0 }
    }

    private static func parseUSDA(_ food: [String: Any]) -> FoodItem? {
        guard let description = food["description"] as? String,
              let nutrients = food["foodNutrients"] as? [[String: Any]] else { return nil }

        func nutrient(_ id: Int) -> Double {
            for entry in nutrients where (entry["nutrientId"] as? Int) == id {
                if let value = entry["value"] as? Double { return value }
                if let value = entry["value"] as? Int { return Double(value) }
            }
            return 0
        }

        let brand = (food["brandOwner"] as? String) ?? (food["brandName"] as? String)
        var servingGrams: Double?
        var servingDescription: String?
        if let size = food["servingSize"] as? Double,
           let unit = (food["servingSizeUnit"] as? String)?.lowercased(),
           unit == "g" || unit == "grm" || unit == "gram" {
            servingGrams = size
            servingDescription = "\(Int(size)) g"
        }

        let fdcID = (food["fdcId"] as? Int).map(String.init) ?? UUID().uuidString
        return FoodItem(
            id: "usda-\(fdcID)",
            name: description.sentenceCased,
            brand: brand,
            caloriesPer100g: nutrient(1008),   // Energy (kcal)
            proteinPer100g: nutrient(1003),
            carbsPer100g: nutrient(1005),
            fatPer100g: nutrient(1004),
            servingDescription: servingDescription,
            servingGrams: servingGrams,
            source: "USDA")
    }

    // MARK: - Open Food Facts

    /// Text search, sorted by Open Food Facts relevance/popularity.
    static func searchOpenFoodFacts(_ query: String) async throws -> [FoodItem] {
        var components = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        components.queryItems = [
            .init(name: "search_terms", value: query),
            .init(name: "search_simple", value: "1"),
            .init(name: "action", value: "process"),
            .init(name: "json", value: "1"),
            .init(name: "page_size", value: "25"),
            .init(name: "sort_by", value: "unique_scans_n"),
            .init(name: "fields", value: fields),
        ]
        let (data, response) = try await session.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let products = json["products"] as? [[String: Any]] else {
            throw FoodDBError.network("search failed — check your connection")
        }
        return products.compactMap(parse).filter { $0.caloriesPer100g > 0 }
    }

    /// Exact product lookup by barcode (EAN/UPC).
    static func product(barcode: String) async throws -> FoodItem {
        let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=\(fields)")!
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let product = json["product"] as? [String: Any],
              let item = parse(product) else {
            throw FoodDBError.notFound
        }
        return item
    }

    private static func parse(_ product: [String: Any]) -> FoodItem? {
        guard let rawName = product["product_name"] as? String else { return nil }
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let nutriments = product["nutriments"] as? [String: Any] else { return nil }

        func value(_ key: String) -> Double {
            if let number = nutriments[key] as? Double { return number }
            if let number = nutriments[key] as? Int { return Double(number) }
            if let string = nutriments[key] as? String { return Double(string) ?? 0 }
            return 0
        }

        // Prefer kcal; fall back to converting kJ.
        var kcal = value("energy-kcal_100g")
        if kcal == 0 {
            let kj = value("energy_100g")
            if kj > 0 { kcal = kj / 4.184 }
        }

        let brand = (product["brands"] as? String)?
            .split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }

        var servingGrams: Double?
        if let quantity = product["serving_quantity"] as? Double { servingGrams = quantity }
        else if let string = product["serving_quantity"] as? String { servingGrams = Double(string) }

        return FoodItem(
            id: (product["code"] as? String) ?? UUID().uuidString,
            name: name,
            brand: brand,
            caloriesPer100g: kcal,
            proteinPer100g: value("proteins_100g"),
            carbsPer100g: value("carbohydrates_100g"),
            fatPer100g: value("fat_100g"),
            servingDescription: product["serving_size"] as? String,
            servingGrams: servingGrams,
            source: "Open Food Facts"
        )
    }
}

private extension String {
    /// USDA names are often ALL CAPS — normalize those to sentence case.
    var sentenceCased: String {
        guard self == uppercased(), count > 1 else { return self }
        return prefix(1).uppercased() + dropFirst().lowercased()
    }
}
