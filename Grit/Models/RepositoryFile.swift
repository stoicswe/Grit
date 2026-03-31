import Foundation

struct RepositoryFile: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let type: FileType
    let path: String
    let mode: String

    enum FileType: String, Codable {
        case blob   // regular file
        case tree   // directory
        case commit // submodule
    }

    var isDirectory: Bool { type == .tree }

    var systemImage: String {
        switch type {
        case .tree:   return "folder.fill"
        case .commit: return "arrow.triangle.branch"
        case .blob:   return iconForExtension
        }
    }

    private var iconForExtension: String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift":                                 return "swift"
        case "js", "ts", "jsx", "tsx", "mjs":        return "doc.text"
        case "py", "rb", "go", "rs", "java", "kt":   return "doc.text"
        case "md", "txt", "rst":                      return "doc.plaintext"
        case "json", "yaml", "yml", "toml", "xml":   return "doc.badge.gearshape"
        case "png", "jpg", "jpeg", "gif", "svg",
             "webp", "ico", "bmp":                    return "photo"
        case "pdf":                                   return "doc.richtext"
        case "sh", "bash", "zsh", "fish":            return "terminal"
        case "html", "css", "scss", "sass":           return "globe"
        case "gitignore", "gitattributes":            return "character.cursor.ibeam"
        case "lock", "sum":                           return "lock.doc"
        default:                                      return "doc"
        }
    }
}

/// Full file metadata + base64 content returned by the files endpoint
struct FileContent: Codable {
    let fileName: String
    let filePath: String
    let size: Int
    let encoding: String
    let content: String
    let ref: String
    let blobId: String
    let lastCommitId: String

    var decodedContent: String? {
        guard encoding == "base64" else { return content }
        let stripped = content.replacingOccurrences(of: "\n", with: "")
        guard let data = Data(base64Encoded: stripped, options: .ignoreUnknownCharacters) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    var isTextFile: Bool {
        decodedContent != nil
    }

    enum CodingKeys: String, CodingKey {
        case fileName = "file_name"
        case filePath = "file_path"
        case size, encoding, content, ref
        case blobId = "blob_id"
        case lastCommitId = "last_commit_id"
    }
}

/// Wrapper used for NavigationLink values inside the file browser
struct FileNavigation: Hashable {
    let projectID: Int
    let ref: String
    let file: RepositoryFile
}

/// Search result blob (repo search)
struct SearchBlob: Codable, Identifiable {
    let id: String?
    let basename: String
    let data: String
    let path: String
    let filename: String
    let ref: String
    let startline: Int
    let projectID: Int

    var displayID: String { path + ref }

    enum CodingKeys: String, CodingKey {
        case id, basename, data, path, filename, ref, startline
        case projectID = "project_id"
    }
}

/// Global search project result
struct SearchProject: Codable, Identifiable {
    let id: Int
    let name: String
    let nameWithNamespace: String
    let description: String?
    let webURL: String
    let starCount: Int
    let visibility: String

    enum CodingKeys: String, CodingKey {
        case id, name, description, visibility
        case nameWithNamespace = "name_with_namespace"
        case webURL = "web_url"
        case starCount = "star_count"
    }
}
