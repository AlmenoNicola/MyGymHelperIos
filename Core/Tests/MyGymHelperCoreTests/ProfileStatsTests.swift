import XCTest
@testable import MyGymHelperCore

/// Statistiche della scheda Profilo, storico del peso e avatar. Stessi casi di ProfileStatsTests.kt
/// (tranne il codec di AppData: su iOS le pesate stanno in SwiftData, WeightEntryRecord, e non c'e' un JSON).
final class ProfileStatsTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private func t(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Int64 {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        return ProfileStats.millis(cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!)
    }

    // Mercoledì 4 novembre 2026, ore 15:30 (UTC).
    private lazy var now = t(2026, 11, 4, 15, 30)

    private let bench = CatalogExercise(id: "bench", name: "Panca", primary: [.chest], secondary: [.triceps, .shoulders])
    private let squat = CatalogExercise(id: "squat", name: "Squat", primary: [.quads, .glutes], secondary: [.hamstrings])
    private var catalog: [CatalogExercise] { [bench, squat] }

    private func session(_ at: Int64, _ ex: String, _ reps: [Int], kg: Double = 20) -> StatsSession {
        StatsSession(startedAt: at, exerciseID: ex, sets: reps.map { StatsSet(doneReps: $0, weightKg: kg) })
    }

    func testBucketsOfEachPeriod() {
        let day = ProfileStats.buckets(.day, now: now, zone: utc, firstActivity: nil)
        XCTAssertEqual(day.count, 6)
        XCTAssertEqual(day.first?.start, t(2026, 11, 4))
        XCTAssertEqual(day.last?.end, t(2026, 11, 5))
        XCTAssertEqual(day.map(\.value), [0, 4, 8, 12, 16, 20])
        XCTAssertEqual(day[0].kind, .hours)

        let week = ProfileStats.buckets(.week, now: now, zone: utc, firstActivity: nil)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.first?.start, t(2026, 11, 2))        // lunedì
        XCTAssertEqual(week.last?.end, t(2026, 11, 9))
        XCTAssertEqual(week.map(\.value), Array(1...7))

        let month = ProfileStats.buckets(.month, now: now, zone: utc, firstActivity: nil)
        XCTAssertEqual(month.count, 30)
        XCTAssertEqual(month.first?.start, t(2026, 11, 1))
        XCTAssertEqual(month.last?.end, t(2026, 12, 1))

        let year = ProfileStats.buckets(.year, now: now, zone: utc, firstActivity: nil)
        XCTAssertEqual(year.count, 12)
        XCTAssertEqual(year.first?.start, t(2026, 1, 1))
        XCTAssertEqual(year.last?.end, t(2027, 1, 1))
        XCTAssertEqual(year[0].kind, .month)
    }

    func testTotalUsesMonthsThenYears() {
        let none = ProfileStats.buckets(.all, now: now, zone: utc, firstActivity: nil)
        XCTAssertEqual(none.count, 1)
        XCTAssertEqual(none[0].value, 11)
        let months = ProfileStats.buckets(.all, now: now, zone: utc, firstActivity: t(2025, 3, 15))
        XCTAssertEqual(months.count, 21)                            // da marzo 2025 a novembre 2026
        XCTAssertEqual(months.first?.value, 3); XCTAssertEqual(months.first?.year, 2025)
        let years = ProfileStats.buckets(.all, now: now, zone: utc, firstActivity: t(2023, 6, 1))
        XCTAssertEqual(years.map(\.value), [2023, 2024, 2025, 2026])
        XCTAssertEqual(years[0].kind, .year)
        let r = ProfileStats.range(.all, now: now, zone: utc, firstActivity: t(2023, 6, 1))
        XCTAssertEqual(r.0, t(2023, 1, 1)); XCTAssertEqual(r.1, t(2027, 1, 1))
    }

    func testMuscleSharesWeightPrimaryAndSecondary() {
        let sessions = [
            session(t(2026, 11, 4, 9), "bench", [10, 10, 0]),   // 2 serie svolte (la terza a zero non conta)
            session(t(2026, 11, 4, 10), "squat", [8]),          // 1 serie
            session(t(2026, 11, 4, 11), "sconosciuto", [10]),   // fuori catalogo: non conta per i muscoli
            session(t(2026, 11, 3, 10), "squat", [8, 8])        // ieri: fuori dal giorno
        ]
        let (from, to) = ProfileStats.range(.day, now: now, zone: utc, firstActivity: nil)
        let shares = ProfileStats.muscleShares(sessions, catalog: catalog, from: from, to: to)
        // Petto 2, tricipiti 1, spalle 1, quadricipiti 1, glutei 1, femorali 0,5: totale 6,5.
        XCTAssertEqual(shares.map(\.muscle), [.chest, .shoulders, .triceps, .glutes, .quads, .hamstrings])
        XCTAssertEqual(shares[0].percent, 2.0 / 6.5 * 100, accuracy: 1e-9)
        XCTAssertEqual(shares.last!.percent, 0.5 / 6.5 * 100, accuracy: 1e-9)
        XCTAssertEqual(shares.map(\.percent).reduce(0, +), 100, accuracy: 1e-9)
        let intensity = ProfileStats.intensities(shares)
        XCTAssertEqual(intensity[.chest]!, 1.0, accuracy: 1e-9)
        XCTAssertEqual(intensity[.hamstrings]!, 0.25, accuracy: 1e-9)
        XCTAssertTrue(ProfileStats.muscleShares([], catalog: catalog, from: from, to: to).isEmpty)
    }

    func testPrimaryMuscleIsNotCountedTwiceAsSecondary() {
        let odd = CatalogExercise(id: "odd", name: "Odd", primary: [.chest, .chest], secondary: [.chest, .abs])
        let shares = ProfileStats.muscleShares([session(t(2026, 11, 4, 9), "odd", [5])], catalog: [odd], from: 0, to: Int64.max)
        XCTAssertEqual(shares.first { $0.muscle == .chest }!.score, 1.0, accuracy: 1e-9)
        XCTAssertEqual(shares.first { $0.muscle == .abs }!.score, 0.5, accuracy: 1e-9)
    }

    func testTotalsAndSeries() {
        let sessions = [
            session(t(2026, 11, 2, 9), "bench", [10, 8], kg: 40),
            session(t(2026, 11, 2, 10), "squat", [5], kg: 60),
            session(t(2026, 11, 4, 9), "bench", [10], kg: 42.5),
            session(t(2026, 11, 4, 12), "squat", [0])             // nessuna ripetizione: non è un allenamento
        ]
        let (from, to) = ProfileStats.range(.week, now: now, zone: utc, firstActivity: nil)
        let tot = ProfileStats.totals(sessions, from: from, to: to, zone: utc)
        XCTAssertEqual(tot, StatsTotals(workouts: 2, sessions: 4, sets: 4, reps: 33, volumeKg: 18 * 40.0 + 5 * 60.0 + 10 * 42.5))
        let series = ProfileStats.series(sessions, buckets: ProfileStats.buckets(.week, now: now, zone: utc, firstActivity: nil), zone: utc)
        XCTAssertEqual(series.map(\.workouts), [1, 0, 1, 0, 0, 0, 0])
        XCTAssertEqual(series.map(\.sets), [3, 0, 1, 0, 0, 0, 0])
        XCTAssertEqual(series[1], .zero)
        let day = ProfileStats.series(sessions, buckets: ProfileStats.buckets(.day, now: now, zone: utc, firstActivity: nil), zone: utc)
        XCTAssertEqual(day.map(\.reps), [0, 0, 10, 0, 0, 0])   // 9:00 nella fascia 8-12; 12:00 nella 12-16 (0 ripetizioni)
        XCTAssertEqual(day[3].sessions, 1)
    }

    func testWeightLogKeepsOneEntryPerDay() {
        var log = WeightLog.upsert([], kg: 80.04, now: t(2026, 11, 1, 8), zone: utc)
        log = WeightLog.upsert(log, kg: 79.5, now: t(2026, 11, 3, 8), zone: utc)
        log = WeightLog.upsert(log, kg: 79.26, now: t(2026, 11, 3, 20), zone: utc)     // stesso giorno: sostituisce
        log = WeightLog.upsert(log, kg: 500, now: t(2026, 11, 4, 8), zone: utc)        // limitato a 250
        XCTAssertEqual(log.map(\.kg), [80.0, 79.3, 250.0])
        XCTAssertEqual(log[1].at, t(2026, 11, 3, 20))
        let buckets = ProfileStats.buckets(.week, now: now, zone: utc, firstActivity: nil)
        XCTAssertEqual(ProfileStats.weightSeries(log, buckets: buckets), [nil, 79.3, 250.0, nil, nil, nil, nil])
        XCTAssertEqual(WeightLog.change(log, from: 0, to: Int64.max)!, 170.0, accuracy: 1e-9)
        XCTAssertNil(WeightLog.change(Array(log.prefix(1)), from: 0, to: Int64.max))
    }

    func testAvatarFollowsSexHeightAndBmi() {
        let normal = AvatarFigure.shape(sex: .male, heightCm: 175, weightKg: 70)       // BMI 22,9
        XCTAssertEqual(normal.heightScale, 1.0, accuracy: 1e-9)
        let tall = AvatarFigure.shape(sex: .male, heightCm: 210, weightKg: 70)
        XCTAssertEqual(tall.heightScale, 1.2, accuracy: 1e-9)
        XCTAssertEqual(AvatarFigure.shape(sex: .male, heightCm: 100, weightKg: 70).heightScale, 0.8, accuracy: 1e-9)   // altezza limitata a 140
        let heavy = AvatarFigure.shape(sex: .male, heightCm: 175, weightKg: 120)
        let thin = AvatarFigure.shape(sex: .male, heightCm: 175, weightKg: 50)
        let waist = 175.0
        XCTAssertTrue(AvatarFigure.factorAt(heavy, waist) > AvatarFigure.factorAt(normal, waist))
        XCTAssertTrue(AvatarFigure.factorAt(thin, waist) < AvatarFigure.factorAt(normal, waist))
        let female = AvatarFigure.shape(sex: .female, heightCm: 175, weightKg: 70)
        XCTAssertTrue(AvatarFigure.factorAt(female, 225) > AvatarFigure.factorAt(normal, 225))   // fianchi
        XCTAssertTrue(AvatarFigure.factorAt(female, 90) < AvatarFigure.factorAt(normal, 90))     // spalle
        // Interpolazione a metà tra due altezze di riferimento.
        let mid = (AvatarFigure.knotY[4] + AvatarFigure.knotY[5]) / 2
        XCTAssertEqual(AvatarFigure.factorAt(normal, mid), (normal.factors[4] + normal.factors[5]) / 2, accuracy: 1e-9)
        for f in heavy.factors { XCTAssertTrue((0.7...1.55).contains(f)) }
    }

    func testAvatarPathsStayInsideTheFrameWithFeetOnTheGround() throws {
        let number = try NSRegularExpression(pattern: "-?\\d+(?:\\.\\d+)?")
        let cases: [(BiologicalSex, Double, Double)] = [(.male, 210, 250), (.female, 140, 30), (.male, 175, 70)]
        for (sex, h, w) in cases {
            let paths = AvatarFigure.paths(sex: sex, heightCm: h, weightKg: w)
            XCTAssertEqual(paths.count, BodyFigure.silhouette.count)
            let nums: [Double] = paths.flatMap { p -> [Double] in
                let ns = p as NSString
                return number.matches(in: p, range: NSRange(location: 0, length: ns.length)).map { Double(ns.substring(with: $0.range))! }
            }
            let xs = nums.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
            let ys = nums.enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
            XCTAssertTrue(xs.min()! >= 0 && xs.max()! <= AvatarFigure.width, "\(sex) \(h) \(w) x")
            XCTAssertTrue(ys.min()! >= 0 && ys.max()! <= AvatarFigure.height, "\(sex) \(h) \(w) y")
            XCTAssertTrue(paths.allSatisfy { $0.hasPrefix("M") && $0.hasSuffix("Z") })
            // I tracciati restano leggibili dallo stesso parser della figura dei muscoli.
            XCTAssertTrue(paths.allSatisfy { BodyFigure.commands($0) != nil })
        }
        // Punto di riferimento: la cima della testa (100, 6) dell'avatar di 175 cm sta al centro, a 516 - 426.
        XCTAssertEqual(String(AvatarFigure.paths(sex: .male, heightCm: 175, weightKg: 70)[0].prefix(11)), "M120.0 90.0")
        XCTAssertEqual(AvatarFigure.format1(1.25), "1.3")
        XCTAssertEqual(AvatarFigure.format1(-1.25), "-1.3")
        XCTAssertEqual(AvatarFigure.format1(0.04), "0.0")
    }
}
