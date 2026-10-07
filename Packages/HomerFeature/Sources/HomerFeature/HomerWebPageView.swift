import AppUI
import SwiftUI
import WebKit

/// A page of the web console in a sheet — the process detail, with its logs, artifacts and
/// workflow graph, which the native list leaves to the console. The app's session cookies are
/// copied into the instance's own web data store (`HomerWebDataStore`) before the page loads, so
/// it opens signed in; if they are missing or stale the console shows its own sign-in page,
/// which works as well.
///
/// Loaded as the top-level page, not in a frame: the console sends `X-Frame-Options: DENY` and
/// `frame-ancestors 'none'`, which only an embedding `<iframe>` would trip over.
struct HomerWebPageView: View {
	let page: HomerWebPage

	@State
	private var webPage: WebPage

	@Environment(\.dismiss)
	private var dismiss

	@Environment(\.openURL)
	private var openURL

	init(page: HomerWebPage) {
		self.page = page
		var configuration = WebPage.Configuration()
		configuration.websiteDataStore = HomerWebDataStore.store(id: page.dataStoreID)
		_webPage = State(initialValue: WebPage(configuration: configuration))
	}

	var body: some View {
		VStack(spacing: 0) {
			HStack(spacing: 10) {
				Text(page.title)
					.scaledFont(.headline)
				if webPage.isLoading {
					ProgressView()
						.controlSize(.small)
				}
				Spacer()
				Button("Open in Browser") {
					openURL(webPage.url ?? page.url)
				}
				.buttonStyle(.scaledBordered)
				Button("Done") { dismiss() }
					.buttonStyle(.scaledBorderedProminent)
					.keyboardShortcut(.cancelAction)
			}
			.padding(12)

			Divider()

			WebView(webPage)
		}
		.frame(minWidth: 900, idealWidth: 1200, minHeight: 600, idealHeight: 800)
		.task {
			let cookieStore = HomerWebDataStore.store(id: page.dataStoreID).httpCookieStore
			for cookie in page.cookies {
				await cookieStore.setCookie(cookie)
			}
			webPage.load(URLRequest(url: page.url))
		}
	}
}

/// The embedded web console's data store of each instance (`HomerEndpoint.webDataStoreID`):
/// apart from one another, like the instances' cookie jars, so two instances on one host do not
/// sign each other's pages out.
@MainActor
enum HomerWebDataStore {
	static func store(id: UUID) -> WKWebsiteDataStore {
		WKWebsiteDataStore(forIdentifier: id)
	}

	/// Signs the embedded console out with the app: its copy of the session cookie would
	/// otherwise stay valid there until it expires.
	static func removeCookies(baseURL: String) async {
		await store(id: HomerEndpoint.webDataStoreID(baseURL: baseURL))
			.removeData(ofTypes: [WKWebsiteDataTypeCookies], modifiedSince: .distantPast)
	}
}
