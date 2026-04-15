import SwiftUI

// AICodexAccountsSection renders account management controls while the page coordinates the side effects.
struct AICodexAccountsSection: View {
    @ObservedObject private var l10n = L10n.shared
    let codexStatus: CodexAccountManagerStatus?
    let codexAccounts: [CodexManagedAccount]
    let statusMessage: String
    let statusIsError: Bool
    let onSyncCurrentAuth: () -> Void
    let onImportAccount: () -> Void
    let onLaunchLogin: () -> Void
    let onLaunchDeviceLogin: () -> Void
    let onActivateAccount: (CodexManagedAccount) -> Void
    let onRemoveAccount: (CodexManagedAccount) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n["codex_accounts"])
                Text(l10n["codex_accounts_desc"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button {
                    onSyncCurrentAuth()
                } label: {
                    Text(l10n["codex_account_sync_current"])
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    onImportAccount()
                } label: {
                    Text(l10n["codex_account_import"])
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Button {
                    onLaunchLogin()
                } label: {
                    Text(l10n["codex_account_login"])
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    onLaunchDeviceLogin()
                } label: {
                    Text(l10n["codex_account_login_device_auth"])
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if let active = codexStatus?.activeAccount {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(l10n["codex_account_active_label"]): \(active.displayName)")
                    Text(active.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let currentAuth = codexStatus?.currentAuth,
                      let email = currentAuth.email {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(l10n["codex_account_current_auth"]): \(email)")
                    if let plan = currentAuth.planType {
                        Text(plan.uppercased())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !statusMessage.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: statusIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(statusIsError ? .red : .green)
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }
            }

            if codexAccounts.isEmpty {
                Text(l10n["codex_accounts_empty"])
                    .foregroundStyle(.secondary)
            } else {
                ForEach(codexAccounts) { account in
                    CodexManagedAccountRow(
                        account: account,
                        isActive: account.accountKey == codexStatus?.registry.activeAccountKey,
                        onActivate: {
                            onActivateAccount(account)
                        },
                        onRemove: {
                            onRemoveAccount(account)
                        }
                    )
                }
            }
        }
    }
}
