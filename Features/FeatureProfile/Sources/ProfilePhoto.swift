import AVFoundation
import PhotosUI
import UIKit

/// Фото профиля (D43): квадрат 512 px из середины, JPEG — так файл всегда влезает в лимит хранилища (1 МБ).
enum AvatarImage {
    static let side: CGFloat = 512

    static func jpeg(from image: UIImage) -> Data? {
        let size = image.size
        let crop = min(size.width, size.height)
        guard crop > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let scale = side / crop
        let data = renderer.jpegData(withCompressionQuality: 0.8) { _ in
            image.draw(in: CGRect(x: -(size.width - crop) / 2 * scale, y: -(size.height - crop) / 2 * scale,
                                  width: size.width * scale, height: size.height * scale))
        }
        return data
    }
}

/// Откуда берём фото: камера (своё разрешение) или системное окно выбора — оно разрешения не требует,
/// приложение получает только выбранное фото.
@MainActor
final class PhotoSource: NSObject, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let onImage: (UIImage) -> Void
    private weak var host: UIViewController?

    init(host: UIViewController, onImage: @escaping (UIImage) -> Void) {
        self.host = host
        self.onImage = onImage
    }

    static var hasCamera: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    /// Камера: спросить разрешение при первом разе; отказ (сейчас или раньше, в т.ч. отозванный в Настройках) —
    /// объяснить и предложить Настройки.
    func openCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            presentCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor [weak self] in if granted { self?.presentCamera() } else { self?.offerSettings() } }
            }
        default:
            offerSettings()
        }
    }

    func openLibrary() {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        host?.present(picker, animated: true)
    }

    private func presentCamera() {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .front
        picker.allowsEditing = true // системная рамка — сразу квадрат
        picker.delegate = self
        host?.present(picker, animated: true)
    }

    private func offerSettings() {
        let alert = UIAlertController(title: "Нет доступа к камере",
                                      message: "Чтобы сделать фото для профиля, разрешите Tribuna доступ к камере в Настройках.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Не сейчас", style: .cancel))
        alert.addAction(UIAlertAction(title: "Настройки", style: .default) { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        })
        host?.present(alert, animated: true)
    }

    nonisolated func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        // Делегат зовут на главном потоке; провайдер нужен только здесь же, до loadObject.
        nonisolated(unsafe) let provider = results.first?.itemProvider
        Task { @MainActor in
            picker.dismiss(animated: true)
            guard let provider, provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                guard let image = object as? UIImage else { return }
                nonisolated(unsafe) let picked = image
                Task { @MainActor [weak self] in self?.onImage(picked) }
            }
        }
    }

    nonisolated func imagePickerController(_ picker: UIImagePickerController,
                                           didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        nonisolated(unsafe) let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage
        Task { @MainActor in
            picker.dismiss(animated: true)
            if let image { onImage(image) }
        }
    }

    nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        Task { @MainActor in picker.dismiss(animated: true) }
    }
}
