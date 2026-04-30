import StoreKit
import Foundation

/// Manages consumable in-app tip purchases using StoreKit 2.
///
/// Before shipping, register six Consumable in-app purchases in App Store Connect
/// with these exact product IDs:
///   - com.grit.tip.small   → $0.99  (High Five!)
///   - com.grit.tip.medium  → $2.99  (Small Coffee)
///   - com.grit.tip.large   → $4.99  (Medium Coffee)
///   - com.grit.tip.xlarge  → $9.99  (Large Coffee)
///   - com.grit.tip.bag     → $14.99 (Bag o' Coffee)
///   - com.grit.tip.crate   → $29.99 (Crate o' Coffee)
@MainActor
final class TipStore: ObservableObject {
    static let shared = TipStore()

    static let productIDs: Set<String> = [
        "com.grit.tip.small",
        "com.grit.tip.medium",
        "com.grit.tip.large",
        "com.grit.tip.xlarge",
        "com.grit.tip.bag",
        "com.grit.tip.crate"
    ]

    @Published var products: [Product] = []
    @Published var isLoading    = false
    @Published var isPurchasing = false
    @Published var lastResult:  TipResult? = nil

    enum TipResult: Equatable {
        case success(Product)
        case failed(String)
    }

    private init() {}

    // MARK: - Load

    /// Fetches products from the App Store. Safe to call multiple times — no-ops after first load.
    func loadProducts() async {
        guard products.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            products = try await Product.products(for: Self.productIDs)
                .sorted { $0.price < $1.price }
        } catch {
            products = []
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    lastResult = .failed("Purchase could not be verified.")
                    return
                }
                await transaction.finish()
                lastResult = .success(product)
            case .userCancelled:
                break   // user backed out — no error needed
            case .pending:
                break   // awaiting parental approval or similar
            @unknown default:
                break
            }
        } catch {
            lastResult = .failed(error.localizedDescription)
        }
    }
}
