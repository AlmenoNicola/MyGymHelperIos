import SwiftUI
import MyGymHelperCore

/// Riquadro del totale delle calorie bruciate (stima) dell'elenco: in fondo all'elenco attuale (dopo Reset) e nel
/// riepilogo quando si è appena finito l'ultimo esercizio. Titolo "in tutto l'allenamento" se tutti gli esercizi sono
/// fatti, altrimenti "finora". Sotto, l'avviso che è solo una stima e, senza peso corporeo, la nota dei 70 kg.
/// Come CaloriesTotalCard su Android.
struct CaloriesTotalCard: View {
    let items: [WorkoutItem]

    var body: some View {
        let total = CalorieEstimator.display(CalorieEstimator.listKcal(items))
        let allDone = !items.isEmpty && items.allSatisfy(\.done)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "flame.fill").font(.system(size: 26 * AppTextScale)).foregroundStyle(Theme.done)
                VStack(alignment: .leading, spacing: 2) {
                    Text(allDone ? "calories.totalTitle" : "calories.partialTitle")
                        .font(.system(size: 12 * AppTextScale)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                    Text("calories.item \(total)")
                        .font(.system(size: 24 * AppTextScale, weight: .heavy)).lineLimit(1).minimumScaleFactor(16.0 / 24.0)
                }
                Spacer(minLength: 0)
            }
            Text("calories.disclaimer").font(.system(size: 12 * AppTextScale)).foregroundStyle(.secondary)
            if ProfileData.bodyWeightKg() == nil {
                Text("calories.defaultWeight").font(.system(size: 12 * AppTextScale))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.done.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.done.opacity(0.5), lineWidth: 1))
    }
}
