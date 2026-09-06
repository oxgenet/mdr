import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NSLog("[mdr-ios] core version %@", MdrCore.version)
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        let browser = DocumentBrowserViewController()
        window.rootViewController = browser
        self.window = window
        window.makeKeyAndVisible()

        // Opened from Files / share sheet / another app at launch.
        if let url = connectionOptions.urlContexts.first?.url {
            browser.open(url: url, presentImmediately: true)
        } else if let path = Self.launchFileArgument() {
            // e2e hook: `-openFile <path>` (absolute, or relative to the app's Documents dir)
            let url = path.hasPrefix("/")
                ? URL(fileURLWithPath: path)
                : FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(path)
            NSLog("[mdr-ios] launch argument -openFile %@", url.path)
            browser.open(url: url, presentImmediately: true)
        }
    }

    /// Files dropped by the Share Extension into the App Group Inbox are moved
    /// into Documents (so they show in the browser) and the newest one is opened.
    func sceneDidBecomeActive(_ scene: UIScene) {
        guard let browser = window?.rootViewController as? DocumentBrowserViewController,
              let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.net.oxge.mdr") else { return }
        let inbox = group.appendingPathComponent("Inbox", isDirectory: true)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let files = try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: [.contentModificationDateKey]),
              !files.isEmpty else { return }
        var newest: URL?
        for f in files.sorted(by: { ($0.lastPathComponent) < ($1.lastPathComponent) }) {
            var dest = docs.appendingPathComponent(f.lastPathComponent)
            var n = 1
            while FileManager.default.fileExists(atPath: dest.path) {
                n += 1
                dest = docs.appendingPathComponent("\(f.deletingPathExtension().lastPathComponent) \(n).\(f.pathExtension)")
            }
            if (try? FileManager.default.moveItem(at: f, to: dest)) != nil {
                NSLog("[mdr-ios] imported from share inbox: %@", dest.lastPathComponent)
                newest = dest
            }
        }
        if let url = newest, browser.presentedViewController == nil {
            browser.open(url: url, presentImmediately: false)
        }
    }

    /// Opened from Files / share sheet while already running.
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url,
              let browser = window?.rootViewController as? DocumentBrowserViewController else { return }
        browser.open(url: url, presentImmediately: true)
    }

    private static func launchFileArgument() -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-openFile"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
