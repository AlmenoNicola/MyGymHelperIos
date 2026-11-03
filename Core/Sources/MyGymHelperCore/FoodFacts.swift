import Foundation

/// Valori nutrizionali per 100 g di un prodotto Open Food Facts (dati ODbL: serve l'attribuzione).
public struct FoodProduct: Identifiable, Equatable, Sendable {
    public let id: String            // codice a barre
    public let name: String
    public let brand: String?
    public let kcal100g: Double?
    public let protein100g: Double?
    public let carbs100g: Double?
    public let fat100g: Double?

    public init(id: String, name: String, brand: String? = nil, kcal100g: Double? = nil,
                protein100g: Double? = nil, carbs100g: Double? = nil, fat100g: Double? = nil) {
        self.id = id; self.name = name; self.brand = brand; self.kcal100g = kcal100g
        self.protein100g = protein100g; self.carbs100g = carbs100g; self.fat100g = fat100g
    }
}

/// Numero tollerante: Open Food Facts a volte restituisce numeri come stringhe ("12,5", "12.5") o valori vuoti.
struct LenientDouble: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d.isFinite ? d : nil; return }
        if let s = try? c.decode(String.self) {
            value = Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
            return
        }
        value = nil
    }
}

/// Stringa tollerante: il codice a barre puo' arrivare come numero.
struct LenientString: Decodable {
    let value: String?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s; return }
        if let i = try? c.decode(Int64.self) { value = String(i); return }
        value = nil
    }
}

public enum FoodFactsDecoder {
    struct Nutriments: Decodable {
        let kcal: LenientDouble?
        let energyKJ: LenientDouble?
        let proteins: LenientDouble?
        let carbs: LenientDouble?
        let fat: LenientDouble?
        enum CodingKeys: String, CodingKey {
            case kcal = "energy-kcal_100g"
            case energyKJ = "energy_100g"
            case proteins = "proteins_100g"
            case carbs = "carbohydrates_100g"
            case fat = "fat_100g"
        }
    }
    struct ProductJSON: Decodable {
        let code: LenientString?
        let productName: String?
        let genericName: String?
        let brands: String?
        let nutriments: Nutriments?
        enum CodingKeys: String, CodingKey {
            case code, brands, nutriments
            case productName = "product_name"
            case genericName = "generic_name"
        }
    }
    struct SearchJSON: Decodable { let products: [ProductJSON]? }

    /// Decodifica una risposta di ricerca; scarta i prodotti senza nome o senza codice.
    public static func decodeSearch(_ data: Data) throws -> [FoodProduct] {
        let json = try JSONDecoder().decode(SearchJSON.self, from: data)
        return (json.products ?? []).compactMap { p in
            guard let code = p.code?.value, !code.isEmpty else { return nil }
            let rawName = (p.productName?.isEmpty == false ? p.productName : p.genericName) ?? ""
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let n = p.nutriments
            // Se manca il valore in kcal si converte quello in kJ (1 kcal = 4,184 kJ).
            let kcal = n?.kcal?.value ?? n?.energyKJ?.value.map { $0 / 4.184 }
            let brand = p.brands?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }
            return FoodProduct(id: code, name: name, brand: (brand?.isEmpty ?? true) ? nil : brand,
                               kcal100g: kcal.map(plausible(0...900)) ?? nil,
                               protein100g: n?.proteins?.value.map(plausible(0...100)) ?? nil,
                               carbs100g: n?.carbs?.value.map(plausible(0...100)) ?? nil,
                               fat100g: n?.fat?.value.map(plausible(0...100)) ?? nil)
        }
    }

    private static func plausible(_ range: ClosedRange<Double>) -> (Double) -> Double? {
        { range.contains($0) ? $0 : nil }
    }
}

/// Client minimo di Open Food Facts. L'API chiede uno User-Agent che identifichi l'app e un contatto.
/// Attribuzione obbligatoria: "Dati alimentari da Open Food Facts (ODbL)".
public struct FoodFactsClient: Sendable {
    public let userAgent: String
    public let session: URLSession
    public let baseURL: URL

    public init(userAgent: String, session: URLSession = .shared,
                baseURL: URL = URL(string: "https://world.openfoodfacts.org")!) {
        self.userAgent = userAgent; self.session = session; self.baseURL = baseURL
    }

    public func searchRequest(_ query: String, language: String, pageSize: Int = 20) -> URLRequest? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2,
              var comps = URLComponents(url: baseURL.appendingPathComponent("cgi/search.pl"), resolvingAgainstBaseURL: false)
        else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "search_terms", value: q),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: String(min(max(pageSize, 1), 50))),
            URLQueryItem(name: "lc", value: language),
            URLQueryItem(name: "fields", value: "code,product_name,generic_name,brands,nutriments")
        ]
        guard let url = comps.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    public func search(_ query: String, language: String) async throws -> [FoodProduct] {
        guard let request = searchRequest(query, language: language) else { return [] }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try FoodFactsDecoder.decodeSearch(data)
    }
}
