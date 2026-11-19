import SnapKit
import UIKit

/// Заглушка экрана, пока у фичи нет настоящего UI.
public final class PlaceholderViewController: UIViewController {
    public init(title: String) {
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    override public func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.background
        let label = UILabel()
        label.text = title
        label.textColor = Palette.textPrimary
        label.font = Typography.screenTitle
        label.numberOfLines = 0
        label.textAlignment = .center
        view.addSubview(label)
        label.snp.makeConstraints {
            $0.center.equalToSuperview()
            $0.leading.trailing.equalToSuperview().inset(20)
        }
    }
}
