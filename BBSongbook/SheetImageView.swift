import SwiftUI
import UIKit

/// A request to move the sheet: `delta` steps (±) or back to the top.
struct ScrollCommand: Equatable {
    var id = UUID()
    var delta = 0
    var toTop = false
}

/// Loads a lyric sheet image from the song folder and shows it fit-to-width,
/// pinch to zoom, scrolled by pedal / auto-scroll commands.
struct SheetImageView: View {
    let path: String
    let command: ScrollCommand

    @Environment(FolderLibrary.self) private var library
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                SheetScroll(image: image, command: command)
            } else if failed {
                ContentUnavailableView("เปิดรูปไม่ได้", systemImage: "photo.badge.exclamationmark",
                                       description: Text(path))
            } else {
                ProgressView("กำลังโหลด…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: path) {
            image = await library.loadImage(path)
            failed = image == nil
        }
    }
}

private struct SheetScroll: UIViewRepresentable {
    let image: UIImage
    let command: ScrollCommand

    func makeUIView(context: Context) -> SheetScrollView {
        let view = SheetScrollView()
        view.imageView.image = image
        return view
    }

    func updateUIView(_ view: SheetScrollView, context: Context) {
        if view.imageView.image !== image {
            view.imageView.image = image
            view.resetLayout()
        }
        if view.lastCommand != command.id {
            view.lastCommand = command.id
            command.toTop ? view.scrollToTop() : view.scroll(by: command.delta)
        }
    }
}

final class SheetScrollView: UIScrollView, UIScrollViewDelegate {
    let imageView = UIImageView()
    var lastCommand: UUID?
    private var laidOutWidth: CGFloat = 0

    /// One pedal press / auto-scroll step moves this much of the screen.
    private let stepFraction: CGFloat = 0.3

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 4
        backgroundColor = .systemBackground
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func resetLayout() {
        laidOutWidth = 0
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Fit to width; only redo it at 1x so pinch zoom isn't undone.
        guard zoomScale == 1, bounds.width != laidOutWidth,
              let size = imageView.image?.size, size.width > 0 else { return }
        laidOutWidth = bounds.width
        let height = bounds.width * size.height / size.width
        imageView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: height)
        contentSize = imageView.frame.size
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scroll(by steps: Int) {
        let top = -adjustedContentInset.top
        let bottom = max(contentSize.height - bounds.height + adjustedContentInset.bottom, top)
        let y = contentOffset.y + CGFloat(steps) * bounds.height * stepFraction
        setContentOffset(CGPoint(x: contentOffset.x, y: min(max(y, top), bottom)), animated: true)
    }

    func scrollToTop() {
        setContentOffset(CGPoint(x: contentOffset.x, y: -adjustedContentInset.top), animated: true)
    }
}
