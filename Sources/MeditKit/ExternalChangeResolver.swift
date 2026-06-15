import Foundation

/// Decides how to respond when the open file changes on disk, given the policy
/// and whether the document has unsaved edits. Pure value logic, fully tested.
public enum ExternalChangePolicy: String, CaseIterable {
    case notify       // non-blocking banner; never auto-acts
    case prompt       // modal Reload/Keep; reload silently if clean
    case autoIfClean  // reload silently if clean; prompt if dirty
}

public enum ExternalChangeResolver {

    public enum Action: Equatable {
        case banner          // show the non-blocking banner
        case prompt          // show the modal Reload/Keep alert
        case reloadSilently  // just reload, no UI
    }

    public static func action(policy: ExternalChangePolicy, isDirty: Bool) -> Action {
        switch policy {
        case .notify:
            return .banner
        case .prompt:
            return isDirty ? .prompt : .reloadSilently
        case .autoIfClean:
            return isDirty ? .prompt : .reloadSilently
        }
    }
}
