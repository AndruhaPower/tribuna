import CoreUI
import SnapKit
import UIKit

/// Шапка: заголовок «Эфир» и поле поиска. Отступы — от верха безопасной зоны, замер по макету.
final class RadioHeaderCell: UICollectionViewCell {
    /// До верха чипов.
    static let height: CGFloat = 128.5

    var onQueryChange: ((String) -> Void)?

    private let field = UITextField()

    override init(frame: CGRect) {
        super.init(frame: frame)
        let titleFont = Typography.screenTitle
        let title = UILabel()
        title.font = titleFont
        title.textColor = Palette.textPrimary
        title.text = "Эфир"
        title.accessibilityTraits = .header

        let box = UIView()
        box.backgroundColor = Palette.surface
        box.layer.cornerRadius = 14
        box.layer.borderWidth = 1
        box.layer.borderColor = Palette.track.cgColor
        let icon = UIImageView(image: UIImage(named: "search", in: .module, compatibleWith: nil))
        icon.tintColor = Palette.textSecondary

        field.font = Typography.text(16)
        field.textColor = Palette.textPrimary
        field.tintColor = Palette.accent
        field.attributedPlaceholder = NSAttributedString(
            string: "Станция или жанр",
            attributes: [.foregroundColor: Palette.placeholder]
        )
        field.returnKeyType = .search
        field.clearButtonMode = .whileEditing
        field.autocorrectionType = .no
        field.addAction(UIAction { [weak self] _ in self?.onQueryChange?(self?.field.text ?? "") }, for: .editingChanged)
        field.addAction(UIAction { [weak self] _ in self?.field.resignFirstResponder() }, for: .editingDidEndOnExit)

        [title, box].forEach(contentView.addSubview)
        [icon, field].forEach(box.addSubview)
        title.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(20)
            $0.firstBaseline.equalTo(contentView.snp.top).offset(15.5 + titleFont.capHeight)
        }
        box.snp.makeConstraints {
            $0.top.equalToSuperview().offset(62.5)
            $0.leading.trailing.equalToSuperview().inset(20)
            $0.height.equalTo(50)
        }
        // Центр лупы в 24.75 pt от края поля, текст с 47.5 pt.
        icon.snp.makeConstraints {
            $0.centerX.equalTo(box.snp.leading).offset(24.75)
            $0.centerY.equalToSuperview()
        }
        field.snp.makeConstraints {
            $0.leading.equalToSuperview().offset(47)
            $0.trailing.equalToSuperview().inset(12)
            $0.top.bottom.equalToSuperview()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    /// Не трогает поле, пока текст совпадает: иначе сбился бы курсор.
    func configure(query: String) {
        if field.text != query { field.text = query }
    }
}
