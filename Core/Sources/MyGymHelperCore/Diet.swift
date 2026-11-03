import Foundation

enum FoodTag { case meat, fish, eggs, dairy, lactose, gluten }

struct Food {
    let key: String                 // chiave di localizzazione, es. "food.chicken"
    let category: FoodCategory
    let tags: Set<FoodTag>
}

public enum FoodCategory: String, Codable, Sendable { case protein, carbs, fats, produce }

public struct MealPlan: Equatable, Sendable {
    public let nameKey: String
    public let calories: Int
    public let proteinG: Int
    public let carbsG: Int
    public let fatG: Int
    /// Chiavi di localizzazione di alimenti adatti alla dieta scelta (solo indicazioni, niente ricette).
    public let suggestions: [String]
}

public struct DayNutrition: Equatable, Sendable {
    public let calories: Int
    public let proteinG: Int
    public let carbsG: Int
    public let fatG: Int
    public let meals: [MealPlan]
}

/// Piano alimentare generale per dieta e giorno di allenamento. Non contiene ricette (copyright)
/// e non sostituisce un nutrizionista: non considera allergie, intolleranze cliniche o patologie.
public enum DietPlanner {
    static let foods: [Food] = [
        Food(key: "food.chicken", category: .protein, tags: [.meat]),
        Food(key: "food.turkey", category: .protein, tags: [.meat]),
        Food(key: "food.leanBeef", category: .protein, tags: [.meat]),
        Food(key: "food.whiteFish", category: .protein, tags: [.fish]),
        Food(key: "food.tuna", category: .protein, tags: [.fish]),
        Food(key: "food.eggs", category: .protein, tags: [.eggs]),
        Food(key: "food.greekYogurt", category: .protein, tags: [.dairy, .lactose]),
        Food(key: "food.cottageCheese", category: .protein, tags: [.dairy, .lactose]),
        Food(key: "food.lactoseFreeYogurt", category: .protein, tags: [.dairy]),
        Food(key: "food.legumes", category: .protein, tags: []),
        Food(key: "food.tofu", category: .protein, tags: []),
        Food(key: "food.tempeh", category: .protein, tags: []),
        Food(key: "food.seitan", category: .protein, tags: [.gluten]),
        Food(key: "food.rice", category: .carbs, tags: []),
        Food(key: "food.potatoes", category: .carbs, tags: []),
        Food(key: "food.quinoa", category: .carbs, tags: []),
        Food(key: "food.polenta", category: .carbs, tags: []),
        Food(key: "food.oats", category: .carbs, tags: [.gluten]),
        Food(key: "food.pasta", category: .carbs, tags: [.gluten]),
        Food(key: "food.bread", category: .carbs, tags: [.gluten]),
        Food(key: "food.oliveOil", category: .fats, tags: []),
        Food(key: "food.nuts", category: .fats, tags: []),
        Food(key: "food.avocado", category: .fats, tags: []),
        Food(key: "food.seeds", category: .fats, tags: []),
        Food(key: "food.butter", category: .fats, tags: [.dairy, .lactose]),
        Food(key: "food.cheese", category: .fats, tags: [.dairy, .lactose]),
        Food(key: "food.vegetables", category: .produce, tags: []),
        Food(key: "food.fruit", category: .produce, tags: [])
    ]

    static func excluded(for diets: Set<DietType>) -> Set<FoodTag> {
        var out = Set<FoodTag>()
        if diets.contains(.vegetarian) { out.formUnion([.meat, .fish]) }
        if diets.contains(.vegan) { out.formUnion([.meat, .fish, .eggs, .dairy, .lactose]) }
        if diets.contains(.glutenFree) { out.insert(.gluten) }
        if diets.contains(.lactoseFree) { out.insert(.lactose) }
        return out
    }

    /// Alimenti ammessi dalla dieta (piu' diete insieme: valgono tutte le esclusioni).
    public static func allowedFoods(for diets: Set<DietType>, category: FoodCategory) -> [String] {
        let ex = excluded(for: diets)
        return foods.filter { $0.category == category && $0.tags.isDisjoint(with: ex) }.map(\.key)
    }

    public static func plan(targets: DailyTargets, diets: Set<DietType>, trainingDay: Bool) -> DayNutrition {
        var calories = Double(targets.calories)
        var carbs = Double(targets.carbsGrams)
        let protein = Double(targets.proteinGrams)
        let fat = Double(targets.fatGrams)
        if trainingDay {
            let extra = calories * 0.08
            calories += extra
            carbs += extra / 4
        }
        let shares: [(String, Double)] = [("meal.breakfast", 0.25), ("meal.snack1", 0.10), ("meal.lunch", 0.30),
                                          ("meal.snack2", 0.10), ("meal.dinner", 0.25)]
        let proteins = allowedFoods(for: diets, category: .protein)
        let carbSources = allowedFoods(for: diets, category: .carbs)
        let fats = allowedFoods(for: diets, category: .fats)
        let produce = allowedFoods(for: diets, category: .produce)
        func pick(_ list: [String], _ i: Int) -> String? { list.isEmpty ? nil : list[i % list.count] }

        let meals: [MealPlan] = shares.enumerated().map { i, item in
            let suggestions = [pick(proteins, i), pick(carbSources, i), pick(fats, i), pick(produce, i)].compactMap { $0 }
            return MealPlan(nameKey: item.0,
                            calories: Int((calories * item.1).rounded()),
                            proteinG: Int((protein * item.1).rounded()),
                            carbsG: Int((carbs * item.1).rounded()),
                            fatG: Int((fat * item.1).rounded()),
                            suggestions: suggestions)
        }
        return DayNutrition(calories: Int(calories.rounded()), proteinG: Int(protein.rounded()),
                            carbsG: Int(carbs.rounded()), fatG: Int(fat.rounded()), meals: meals)
    }
}
