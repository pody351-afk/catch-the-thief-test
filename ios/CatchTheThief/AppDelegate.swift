import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = GameViewController()
        w.backgroundColor = UIColor(red: 23/255, green: 32/255, blue: 51/255, alpha: 1)
        w.makeKeyAndVisible()
        window = w
        return true
    }
}
