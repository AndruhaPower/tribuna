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
        view.backgroundColor = .systemBackground
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .title2)
        view.addSubview(label)
        label.snp.makeConstraints { $0.center.equalToSuperview() }
    }
}
