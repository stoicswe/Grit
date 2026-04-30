import Foundation

/// GitLab commit signature details — returned by
/// `GET /projects/:id/repository/commits/:sha/signature`.
///
/// GitLab supports three signature types: PGP, X.509, and SSH.
/// All three share `signatureType` and `verificationStatus`;
/// the remaining fields are type-specific and will be nil for other types.
struct CommitSignature: Codable {
    let signatureType: String?
    let verificationStatus: String?

    // MARK: PGP
    let gpgKeyId: Int?
    let gpgKeyPrimaryKeyid: String?
    let gpgKeyUserName: String?
    let gpgKeyUserEmail: String?
    let gpgKeySubkeyId: String?

    // MARK: X.509
    let x509Certificate: X509CertificateDetail?

    // MARK: SSH
    let key: String?

    enum CodingKeys: String, CodingKey {
        case signatureType        = "signature_type"
        case verificationStatus   = "verification_status"
        case gpgKeyId             = "gpg_key_id"
        case gpgKeyPrimaryKeyid   = "gpg_key_primary_keyid"
        case gpgKeyUserName       = "gpg_key_user_name"
        case gpgKeyUserEmail      = "gpg_key_user_email"
        case gpgKeySubkeyId       = "gpg_key_subkey_id"
        case x509Certificate      = "x509_certificate"
        case key
    }

    /// `true` when the signature has been cryptographically verified by GitLab
    /// against a known, trusted key in the project's namespace.
    var isVerified: Bool { verificationStatus == "verified" }

    /// Human-readable verification status.
    var statusLabel: String {
        switch verificationStatus {
        case "verified":              return "Verified"
        case "unverified_key":        return "Unverified Key"
        case "unknown_key":           return "Unknown Key"
        case "other_user":            return "Other User"
        case "unverified":            return "Unverified"
        case "revoked_key":           return "Revoked Key"
        case "multiple_signatures":   return "Multiple Signatures"
        default:
            return verificationStatus?
                .replacingOccurrences(of: "_", with: " ")
                .capitalized ?? "Unknown"
        }
    }

    /// Human-readable signature type label.
    var typeLabel: String {
        switch signatureType?.uppercased() {
        case "PGP":  return "PGP"
        case "X509": return "X.509"
        case "SSH":  return "SSH"
        default:     return signatureType ?? "Unknown"
        }
    }
}

// MARK: - X.509 Certificate sub-struct

struct X509CertificateDetail: Codable {
    let id: Int?
    let subject: String?
    let subjectKeyIdentifier: String?

    enum CodingKeys: String, CodingKey {
        case id
        case subject
        case subjectKeyIdentifier = "subject_key_identifier"
    }
}
