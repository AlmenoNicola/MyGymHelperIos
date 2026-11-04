import SwiftUI
import PhotosUI
import UIKit

/// Foto profilo delle Impostazioni. Resta solo su questo telefono: file in Application Support escluso dal backup
/// iCloud (come gli altri dati personali) e mai caricato sul server. Equivalente di ProfilePhotoStore.kt.
/// La foto scelta viene ritagliata al centro (quadrata) e ridotta a `size` pixel: pesa pochi KB.
@Observable
final class ProfilePhotoStore {
    static let shared = ProfilePhotoStore()
    /// Lato della foto salvata, in pixel.
    static let size: CGFloat = 512

    /// Foto attuale (nil = nessuna: si mostra l'icona).
    private(set) var photo: UIImage?

    private let url: URL = {
        let dir = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("profile-photo.jpg")
    }()

    private init() {
        photo = (try? Data(contentsOf: url)).flatMap(UIImage.init(data:))
    }

    /// Salva la foto scelta con il selettore di sistema. false = immagine non leggibile.
    @MainActor
    func save(_ item: PhotosPickerItem) async -> Bool {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let square = Self.squared(image, side: Self.size),
              let jpeg = square.jpegData(compressionQuality: 0.88) else { return false }
        do {
            try jpeg.write(to: url, options: .atomic)
            var target = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? target.setResourceValues(values)
        } catch {
            return false
        }
        photo = square
        return true
    }

    /// Toglie la foto (torna l'icona). Usata anche da "Elimina tutti i dati".
    func delete() {
        try? FileManager.default.removeItem(at: url)
        photo = nil
    }

    /// Ritaglio quadrato al centro e riduzione; disegnando l'immagine si applica anche la rotazione della foto.
    private static func squared(_ image: UIImage, side: CGFloat) -> UIImage? {
        let w = image.size.width, h = image.size.height
        guard w > 0, h > 0 else { return nil }
        let scale = side / min(w, h)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: (side - w * scale) / 2, y: (side - h * scale) / 2, width: w * scale, height: h * scale))
        }
    }
}

/// Cerchio con la foto profilo (o l'icona su gradiente se non c'e').
struct ProfileAvatar: View {
    var size: CGFloat = 72

    var body: some View {
        Group {
            if let photo = ProfilePhotoStore.shared.photo {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.accentGradient)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// Intestazione delle Impostazioni con la foto profilo: toccando il cerchio si sceglie una foto dalla libreria
/// (selettore di sistema, nessun permesso) o la si toglie. Stesso comportamento dell'app Android.
struct ProfileHeader: View {
    @State private var showPicker = false
    @State private var item: PhotosPickerItem?
    @State private var failed = false
    private var store: ProfilePhotoStore { ProfilePhotoStore.shared }

    private var avatar: some View {
        ProfileAvatar(size: 72)
            .shadow(color: Theme.accent.opacity(0.5), radius: 14, y: 6)
            .overlay(alignment: .bottomTrailing) {
                // Piccola macchina fotografica: fa capire che la foto si puo' cambiare.
                Image(systemName: "camera.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Theme.accent, in: Circle())
                    .overlay(Circle().stroke(Theme.bgTop, lineWidth: 2))
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                // Senza foto il tocco apre subito la libreria; con la foto compare il menu (cambia / togli).
                Group {
                    if store.photo == nil {
                        Button { showPicker = true } label: { avatar }
                    } else {
                        Menu {
                            Button { showPicker = true } label: { Label("profile.photo.choose", systemImage: "photo.on.rectangle") }
                            Button(role: .destructive) { store.delete() } label: { Label("profile.photo.remove", systemImage: "trash") }
                        } label: { avatar }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("profile.photo.change"))
                VStack(alignment: .leading, spacing: 4) {
                    Text("info.title").font(.title.bold()).lineLimit(1)
                    Text("info.subtitle").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if failed { Text("profile.photo.error").font(.footnote).foregroundStyle(.orange) }
        }
        .photosPicker(isPresented: $showPicker, selection: $item, matching: .images)
        .onChange(of: item) { _, new in
            guard let new else { return }
            Task {
                failed = !(await store.save(new))
                item = nil
            }
        }
    }
}
