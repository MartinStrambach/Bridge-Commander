import AppUI
import ComposableArchitecture
import SwiftUI

/// The console's sign-in card (`app/(auth)/login/page.tsx`): the instance — a field when adding
/// one, its URL otherwise — then username and password.
struct HomerLoginView: View {
	@Bindable
	var store: StoreOf<HomerSignInReducer>

	private enum Field: Hashable {
		case endpoint
		case username
		case password
	}

	@FocusState
	private var focusedField: Field?

	var body: some View {
		ScrollView {
			VStack(spacing: 20) {
				VStack(spacing: 8) {
					Image(systemName: AppSection.homer.systemImage)
						.scaledFont(size: 44)
						.foregroundStyle(.secondary)
					Text(title)
						.scaledFont(.title2)
						.fontWeight(.semibold)
					Text(subtitle)
						.scaledFont(.body)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)
				}

				if store.sessionExpired {
					Label("Your session expired. Please sign in again.", systemImage: "clock.badge.exclamationmark")
						.scaledFont(.callout)
						.frame(maxWidth: .infinity, alignment: .leading)
						.padding(10)
						.background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
				}

				VStack(alignment: .leading, spacing: 14) {
					endpointField

					labeledField("Username") {
						TextField("Enter username", text: $store.username)
							.textContentType(.username)
							.focused($focusedField, equals: .username)
					}

					labeledField("Password") {
						SecureField("Enter password", text: $store.password)
							.textContentType(.password)
							.focused($focusedField, equals: .password)
					}

					if let error = store.loginError {
						Text(error)
							.scaledFont(.callout)
							.foregroundStyle(.red)
							.fixedSize(horizontal: false, vertical: true)
					}
				}
				.textFieldStyle(.roundedBorder)
				.onSubmit { store.send(.signInTapped) }

				HStack {
					if store.canCancel {
						Button("Cancel") { store.send(.cancelTapped) }
							.buttonStyle(.scaledBordered)
							.keyboardShortcut(.cancelAction)
					}
					Spacer()
					if store.isSigningIn {
						ProgressView()
							.controlSize(.small)
					}
					Button(signInTitle) { store.send(.signInTapped) }
						.buttonStyle(.scaledBorderedProminent)
						.keyboardShortcut(.defaultAction)
						.disabled(store.isSigningIn || store.loginCooldown > 0)
				}
			}
			.padding(24)
			.frame(maxWidth: 420)
			.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
			.padding(32)
			.frame(maxWidth: .infinity)
		}
		.onAppear {
			focusedField = store.isAddingInstance && store.endpoint.isEmpty ? .endpoint : .username
		}
	}

	private var title: String {
		if !store.isAddingInstance {
			"Sign In to \(HomerEndpoint.displayName(of: store.endpoint))"
		}
		else if store.canCancel {
			"Add a Homer Instance"
		}
		else {
			"Sign In to Homer"
		}
	}

	private var subtitle: String {
		store.isAddingInstance
			? "Enter an instance and sign in with your Homer console username and password. Every instance you add stays signed in; switch between them from the header."
			: "Sign in with your Homer console username and password."
	}

	private var signInTitle: String {
		store.loginCooldown > 0 ? "Wait \(store.loginCooldown) s" : "Sign In"
	}

	@ViewBuilder
	private var endpointField: some View {
		labeledField("Instance") {
			if store.isAddingInstance {
				TextField("https://homer.example.com", text: $store.endpoint)
					.textContentType(.URL)
					.focused($focusedField, equals: .endpoint)
			}
			else {
				// An instance's form is for its own URL; another one is added from the header's
				// instance menu.
				Text(store.endpoint)
					.foregroundStyle(.secondary)
					.lineLimit(1)
					.truncationMode(.middle)
					.textSelection(.enabled)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(.horizontal, 8)
					.padding(.vertical, 5)
					.background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
					.overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary.opacity(0.3)))
			}
		}
	}

	private func labeledField(_ title: String, @ViewBuilder field: () -> some View) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(title)
				.scaledFont(.callout)
				.fontWeight(.medium)
			field()
		}
	}
}
