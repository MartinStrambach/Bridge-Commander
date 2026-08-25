import Foundation

// MARK: - Tuist Clean Category

/// A single category accepted by `tuist clean`.
///
/// The raw values match the tokens the Tuist CLI parses. Running `tuist clean` with no
/// category cleans every category, which is modelled here as a `nil` category.
public nonisolated enum TuistCleanCategory: String, Equatable, CaseIterable, Sendable {
	case binaries
	case selectiveTests
	case dependencies
	case manifests
	case plugins
	case projectDescriptionHelpers
	case editProjects
	case generatedAutomationProjects
	case runs
	case generationMetadata

	public var displayName: String {
		switch self {
		case .binaries:
			"Binaries"

		case .selectiveTests:
			"Selective Tests"

		case .dependencies:
			"Dependencies"

		case .manifests:
			"Manifests"

		case .plugins:
			"Plugins"

		case .projectDescriptionHelpers:
			"Project Description Helpers"

		case .editProjects:
			"Edit Projects"

		case .generatedAutomationProjects:
			"Generated Automation Projects"

		case .runs:
			"Runs"

		case .generationMetadata:
			"Generation Metadata"
		}
	}

	public var systemImage: String {
		switch self {
		case .binaries:
			"shippingbox"

		case .selectiveTests:
			"checkmark.diamond"

		case .dependencies:
			"shippingbox.and.arrow.backward"

		case .manifests:
			"doc.text"

		case .plugins:
			"puzzlepiece.extension"

		case .projectDescriptionHelpers:
			"doc.badge.gearshape"

		case .editProjects:
			"pencil.and.outline"

		case .generatedAutomationProjects:
			"gearshape.2"

		case .runs:
			"clock.arrow.circlepath"

		case .generationMetadata:
			"tag"
		}
	}
}
