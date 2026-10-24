import SwiftUI

struct AboutView: View {
    @EnvironmentObject var l10n: LocalizationManager

    private var appIcon: NSImage {
        if let icon = NSApp?.applicationIconImage, icon.isValid {
            return icon
        }
        if let icon = NSImage(named: NSImage.applicationIconName), icon.isValid {
            return icon
        }
        return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: appIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
            
            Text(l10n.t("about.appName"))
                .font(.title)
                .bold()
            
            Text(l10n.t("about.version"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Text(l10n.t("about.tagline"))
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            
            Divider()
            
            VStack(spacing: 8) {
                Text(l10n.t("about.howToUse"))
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 4) {
                    Label(l10n.t("about.step1"), systemImage: "1.circle")
                    Label(l10n.t("about.step2"), systemImage: "2.circle")
                    Label(l10n.t("about.step3"), systemImage: "3.circle")
                }
                .font(.caption)
            }
            
            Divider()
            
            VStack(spacing: 6) {
                HStack {
                    Link(l10n.t("about.github"), destination: URL(string: "https://github.com/luksiko/dopishi")!)
                        .font(.caption)
                    
                    Text("•")
                        .foregroundStyle(.secondary)
                    
                    Text(l10n.t("about.license"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
        .frame(width: 350, height: 400)
    }
}
