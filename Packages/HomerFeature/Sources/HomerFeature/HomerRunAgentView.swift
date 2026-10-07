import AppKit
import AppUI
import ComposableArchitecture
import SwiftUI

/// The Run sheet (the console's `run-agent-dialog.tsx`): "Configure & Run" with a field per
/// input, or "Export curl" with the same call as a command.
struct HomerRunAgentView: View {
	@Bindable
	var store: StoreOf<HomerRunAgentReducer>

	@State
	private var copied = false

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			VStack(alignment: .leading, spacing: 4) {
				Text("Run Agent: \(store.agent.name)")
					.scaledFont(.title3)
					.fontWeight(.semibold)
				Text(store.agent.description.flatMap { $0.isEmpty ? nil : $0 } ?? "Provide parameters to start a new run.")
					.scaledFont(.callout)
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}

			Picker("Mode", selection: $store.mode) {
				Text("Configure & Run").tag(HomerRunAgentReducer.State.Mode.configure)
				Text("Export curl").tag(HomerRunAgentReducer.State.Mode.curl)
			}
			.pickerStyle(.segmented)
			.labelsHidden()

			switch store.mode {
			case .configure:
				configure
			case .curl:
				curl
			}

			HStack {
				if store.isRunning {
					ProgressView()
						.controlSize(.small)
					Text("Executing…")
						.scaledFont(.callout)
						.foregroundStyle(.secondary)
				}
				Spacer()
				Button("Cancel") { store.send(.cancelTapped) }
					.buttonStyle(.scaledBordered)
					.keyboardShortcut(.cancelAction)
				if store.mode == .configure {
					Button {
						store.send(.runTapped)
					} label: {
						Label("Run Agent", systemImage: "play.fill")
					}
					.buttonStyle(.scaledBorderedProminent)
					.keyboardShortcut(.defaultAction)
					.disabled(!store.canRun || store.isRunning)
				}
			}
		}
		.padding(20)
		.frame(width: 560)
	}

	// MARK: - Configure & Run

	@ViewBuilder
	private var configure: some View {
		if store.inputs.isEmpty {
			Text("This agent has no parameters")
				.scaledFont(.callout)
				.foregroundStyle(.secondary)
				.frame(maxWidth: .infinity)
				.padding(.vertical, 24)
		}
		else {
			// A plain stack, not a lazy one: an agent declares a handful of inputs, and a lazy
			// stack's changing ideal height makes a sheet re-measure itself (AppUI's README).
			ScrollView {
				VStack(alignment: .leading, spacing: 20) {
					section("Query Parameters", store.agent.queryInputs)
					section("Body (JSON)", store.agent.bodyInputs)
					section("Headers", store.agent.headerInputs)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.trailing, 8)
			}
			.frame(maxHeight: 400)
			.fixedSize(horizontal: false, vertical: true)
		}

		if let error = store.runError {
			Text("Failed to execute agent: \(error)")
				.scaledFont(.callout)
				.foregroundStyle(.red)
				.textSelection(.enabled)
				.padding(10)
				.frame(maxWidth: .infinity, alignment: .leading)
				.background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
		}
	}

	@ViewBuilder
	private func section(_ title: String, _ inputs: [HomerAgent.Input]) -> some View {
		if !inputs.isEmpty {
			VStack(alignment: .leading, spacing: 12) {
				Text(title)
					.scaledFont(.callout)
					.fontWeight(.semibold)
				ForEach(inputs) { input in
					field(input)
				}
			}
		}
	}

	private func field(_ input: HomerAgent.Input) -> some View {
		let error = store.errors[input.paramName]
		return VStack(alignment: .leading, spacing: 5) {
			HomerAgentInputHeader(input: input)
			TextField(
				"Enter \(input.paramName)",
				text: Binding(
					get: { store.values[input.paramName] ?? "" },
					set: { store.send(.valueChanged(paramName: input.paramName, value: $0)) }
				)
			)
			.textFieldStyle(.roundedBorder)
			.overlay(
				RoundedRectangle(cornerRadius: 5)
					.strokeBorder(error == nil ? Color.clear : Color.red)
			)
			.onSubmit {
				if store.canRun {
					store.send(.runTapped)
				}
			}
			if let error {
				Text(error)
					.scaledFont(.callout)
					.foregroundStyle(.red)
			}
			HomerAgentInputDetails(input: input)
		}
		.disabled(store.isRunning)
	}

	// MARK: - Export curl

	private var curl: some View {
		VStack(alignment: .leading, spacing: 10) {
			ScrollView([.horizontal, .vertical]) {
				Text(store.curlCommand)
					.scaledFont(.callout, design: .monospaced)
					.textSelection(.enabled)
					.fixedSize()
					.padding(10)
					.frame(maxWidth: .infinity, alignment: .leading)
			}
			.frame(height: 200)
			.background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
			.overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3)))

			Text("The command carries no credentials: add your own, e.g. `-H 'Authorization: Bearer …'`.")
				.scaledFont(.caption)
				.foregroundStyle(.secondary)

			Button {
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(store.curlCommand, forType: .string)
				copied = true
			} label: {
				Label(copied ? "Copied!" : "Copy to Clipboard", systemImage: "doc.on.doc")
					.frame(maxWidth: .infinity)
			}
			.buttonStyle(.scaledBordered)
			.task(id: copied) {
				guard copied else {
					return
				}
				try? await Task.sleep(for: .seconds(2))
				copied = false
			}
		}
	}
}
