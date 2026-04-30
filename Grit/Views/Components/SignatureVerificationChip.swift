import SwiftUI

// MARK: - Chip

/// A compact capsule badge that shows whether a commit carries a cryptographic
/// signature and whether GitLab considers it verified.
///
/// Tapping the chip presents `SignatureDetailSheet` with the full key metadata.
struct SignatureVerificationChip: View {
    let signature: CommitSignature
    @State private var showDetail = false

    private var isVerified: Bool { signature.isVerified }

    var body: some View {
        Button { showDetail = true } label: {
            HStack(spacing: 4) {
                Image(systemName: isVerified
                      ? "checkmark.seal.fill"
                      : "exclamationmark.shield")
                    .font(.system(size: 10, weight: .semibold))
                Text(isVerified ? "Verified" : "Unverified")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(chipColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(chipColor.opacity(0.12), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(chipColor.opacity(0.35), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            SignatureDetailSheet(signature: signature)
        }
    }

    private var chipColor: Color {
        isVerified ? .green : .orange
    }
}

// MARK: - Detail Sheet

struct SignatureDetailSheet: View {
    let signature: CommitSignature
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    statusHero
                    detailsCard
                    Spacer(minLength: 0)
                }
                .padding()
                .padding(.bottom, 24)
            }
            .navigationTitle("\(signature.typeLabel) Signature")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Status hero

    private var statusHero: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(heroColor.opacity(0.12))
                    .frame(width: 76, height: 76)
                Image(systemName: signature.isVerified
                      ? "checkmark.seal.fill"
                      : "exclamationmark.shield.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(heroColor)
            }

            VStack(spacing: 4) {
                Text(signature.statusLabel)
                    .font(.title3.weight(.semibold))
                Text(signature.typeLabel + " Signature")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var heroColor: Color {
        signature.isVerified ? .green : .orange
    }

    // MARK: - Type-specific details card

    @ViewBuilder
    private var detailsCard: some View {
        switch signature.signatureType?.uppercased() {
        case "PGP":  pgpCard
        case "X509": x509Card
        case "SSH":  sshCard
        default:     EmptyView()
        }
    }

    // MARK: PGP

    private var pgpCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                GlassSectionHeader(title: "PGP Key Details")
                if let name = signature.gpgKeyUserName {
                    row(label: "Key Owner", value: name, icon: "person.fill")
                }
                if let email = signature.gpgKeyUserEmail {
                    row(label: "Key Email", value: email, icon: "envelope.fill")
                }
                if let primary = signature.gpgKeyPrimaryKeyid {
                    row(label: "Primary Key ID", value: primary,
                        icon: "key.fill", mono: true)
                }
                if let sub = signature.gpgKeySubkeyId {
                    row(label: "Subkey ID", value: sub,
                        icon: "key", mono: true)
                }
                if let id = signature.gpgKeyId {
                    row(label: "GitLab Key ID", value: "#\(id)",
                        icon: "number", mono: true)
                }
            }
        }
    }

    // MARK: X.509

    private var x509Card: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                GlassSectionHeader(title: "X.509 Certificate")
                if let cert = signature.x509Certificate {
                    if let subject = cert.subject {
                        row(label: "Subject", value: subject,
                            icon: "building.2", mono: true)
                    }
                    if let ski = cert.subjectKeyIdentifier {
                        row(label: "Key Identifier", value: ski,
                            icon: "key.fill", mono: true)
                    }
                    if let id = cert.id {
                        row(label: "GitLab Cert ID", value: "#\(id)",
                            icon: "number", mono: true)
                    }
                }
            }
        }
    }

    // MARK: SSH

    private var sshCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                GlassSectionHeader(title: "SSH Key")
                if let key = signature.key {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Public Key", systemImage: "key.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(key)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .lineLimit(8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Row helper

    private func row(
        label: String,
        value: String,
        icon: String,
        mono: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(mono
                          ? .system(size: 13, design: .monospaced)
                          : .system(size: 13))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
