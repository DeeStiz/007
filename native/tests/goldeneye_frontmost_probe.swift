import AppKit

guard let application = NSWorkspace.shared.frontmostApplication else {
    print("frontmost=none bundle=none active=0")
    exit(1)
}

print(
    "frontmost=\(application.localizedName ?? "unknown") "
        + "bundle=\(application.bundleIdentifier ?? "unknown") "
        + "active=\(application.isActive ? 1 : 0)"
)
