import SwiftUI
import StoreKit

struct TipJarView: View {
    @Environment(\.dismiss)  private var dismiss
    @ObservedObject private var store = TipStore.shared

    @State private var showThankYou   = false
    @State private var thankedProduct: Product? = nil
    @State private var showError      = false
    @State private var errorMessage   = ""

    // Human-readable labels keyed by product ID
    private let meta: [String: (emoji: String, label: String, detail: String)] = [
        "com.grit.tip.small":  ("☕",  "Small Coffee",  "A quick espresso to keep me going"),
        "com.grit.tip.medium": ("☕☕", "Large Coffee",  "A flat white for a longer coding session"),
        "com.grit.tip.large":  ("🎁",  "Custom Amount", "Name your own price — every bit helps!")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {

                    // MARK: - Header

                    VStack(spacing: 10) {
                        Text("☕")
                            .font(.system(size: 64))
                        Text("Buy Me a Coffee")
                            .font(.system(size: 22, weight: .bold))
                        Text("If Grit saves you time or brings a smile, a coffee keeps the wheels turning!")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                            .padding(.horizontal, 28)
                    }
                    .padding(.top, 28)

                    // MARK: - Products

                    if store.isLoading {
                        ProgressView("Loading…")
                            .padding(.vertical, 48)

                    } else if store.products.isEmpty {
                        emptyState

                    } else {
                        VStack(spacing: 12) {
                            ForEach(store.products, id: \.id) { product in
                                productCard(product)
                            }
                        }
                        .padding(.horizontal)
                        .disabled(store.isPurchasing)
                        .opacity(store.isPurchasing ? 0.6 : 1.0)
                        .overlay {
                            if store.isPurchasing {
                                ProgressView()
                                    .scaleEffect(1.3)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    }

                    // MARK: - Footer note

                    Text("Tips are one-time consumable purchases processed entirely through Apple. 100% goes toward development. Thank you 🙏")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 32)
                }
            }
            .navigationTitle("Tip Jar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await store.loadProducts() }
            .onChange(of: store.lastResult) { _, result in
                guard let result else { return }
                switch result {
                case .success(let p):
                    thankedProduct = p
                    showThankYou   = true
                case .failed(let msg):
                    errorMessage = msg
                    showError    = true
                }
                store.lastResult = nil
            }
            .alert("Thank You! ☕", isPresented: $showThankYou) {
                Button("You're Welcome!") { dismiss() }
            } message: {
                if let p = thankedProduct {
                    Text("Your \(p.displayPrice) tip means the world. Cheers! 🎉")
                }
            }
            .alert("Purchase Failed", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Product Card

    @ViewBuilder
    private func productCard(_ product: Product) -> some View {
        let info = meta[product.id] ?? (emoji: "💝", label: product.displayName, detail: product.description)

        Button {
            Task { await store.purchase(product) }
        } label: {
            HStack(spacing: 16) {
                Text(info.emoji)
                    .font(.system(size: 34))
                    .frame(width: 52)

                VStack(alignment: .leading, spacing: 3) {
                    Text(info.label)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(info.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(product.displayPrice)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Color.accentColor.opacity(0.12),
                        in: Capsule()
                    )
            }
            .padding(16)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty / Unavailable State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "cart.badge.questionmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Tips Unavailable")
                .font(.system(size: 16, weight: .semibold))
            Text("The tip jar isn't available right now. Please try again later.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(.vertical, 48)
    }
}
