// MIT License
//
// Copyright (c) 2025 Dwarven Yang <prison.yang@gmail.com>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import UIKit

// MARK: - manager

public class UISEManager: NSObject {
    public static var syncGetter: () -> Bool = { true }
    public static var syncSetter: (Bool) -> Void = { _ in }
    @objc public static var sync: Bool {
        get { syncGetter() }
        set {
            if newValue == syncGetter() { return }
            syncSetter(newValue)
            syncUserInterfaceStyleForWindows()
        }
    }
    
    private static var _light: Bool = true
    public static var lightGetter: () -> Bool = { _light }
    public static var lightSetter: (Bool) -> Void = { _light = $0 }
    @objc public static var light: Bool {
        get { lightGetter() }
        set {
            if newValue == lightGetter() { return }
            lightSetter(newValue)
            NSObject.uise_userInterfaceStyleChanged(newValue)
            syncUserInterfaceStyleForWindows()
        }
    }
    
    @objc public static var backgroundSync = false
    
    private static func syncUserInterfaceStyleForWindows() {
        let observerStyle: UIUserInterfaceStyle = sync ? .unspecified : (light ? .light : .dark)
        let style: UIUserInterfaceStyle = backgroundSync ? observerStyle : (light ? .light : .dark)
        Task { @MainActor in
            windows.allObjects.forEach {
                if $0 == Self.observer {
                    if $0.overrideUserInterfaceStyle != observerStyle { $0.overrideUserInterfaceStyle = observerStyle }
                } else {
                    if $0.overrideUserInterfaceStyle != style { $0.overrideUserInterfaceStyle = style }
                }
            }
        }
    }
    
    private static let observer = UISEWindow(frame: UIScreen.main.bounds)
    private static let windows = NSHashTable<UIWindow>.weakObjects()
    @objc public static func addWindow(_ window: UIWindow) {
        windows.add(observer)
        if observer.windowScene == nil {
            observer.windowScene = window.windowScene ?? (UIApplication.shared.connectedScenes.first as? UIWindowScene)
        }
        windows.add(window)
        syncUserInterfaceStyleForWindows()
    }
    @objc public static func removeWindow(_ window: UIWindow) { windows.remove(window) }
}

// MARK: - observer

fileprivate class UISEWindow: UIWindow {
    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        uise_reloadLightIfNeeded()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(uise_reloadLightIfNeeded),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (w: UISEWindow, _) in
                w.uise_reloadLightIfNeeded()
            }
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit { NotificationCenter.default.removeObserver(self) }
    
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        false
    }
    
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        if #available(iOS 17.0, *) { } else { uise_reloadLightIfNeeded() }
        super.traitCollectionDidChange(previousTraitCollection)
    }
    
    @objc private func uise_reloadLightIfNeeded() {
        guard UISEManager.sync, Thread.isMainThread, UIApplication.shared.applicationState != .background else { return }
        switch traitCollection.userInterfaceStyle {
        case .light: UISEManager.light = true
        case .dark: UISEManager.light = false
        default: return
        }
    }
}

// MARK: - extensions

// MARK: -- Foundation --
public extension NSObject {
    @MainActor private static var uise_weakColorHashTable = NSHashTable<NSObject>.weakObjects()
    
    fileprivate static func uise_userInterfaceStyleChanged(_ light: Bool) {
        Task { @MainActor in
            NSObject.uise_weakColorHashTable.allObjects.forEach { $0.uise_blocks.allValues.forEach { ($0 as? (_ light: Bool) -> Void)?(light) } }
        }
    }
    
    @objc func uise_runBlocks() {
        Task { @MainActor in
            uise_blocks.allValues.forEach { ($0 as? (_ light: Bool) -> Void)?(UISEManager.light) }
        }
    }
    
    @objc func uise_removeAllBlocks() {
        Task { @MainActor in
            uise_blocks.removeAllObjects()
        }
    }
    
    private struct UISEAssociatedKeys {
        static var uise_blocks: UInt8 = 0
    }
    
    @MainActor private var uise_blocks: NSMutableDictionary {
        (objc_getAssociatedObject(self, &UISEAssociatedKeys.uise_blocks) as? NSMutableDictionary) ?? {
            let blocks = NSMutableDictionary()
            objc_setAssociatedObject(self, &UISEAssociatedKeys.uise_blocks, blocks, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return blocks
        }()
    }
    
    @objc func uise_runAndSetBlock(_ block: ((_ light: Bool) -> Void)?, forKey key: String?) {
        block?(UISEManager.light)
        uise_setBlock(block, forKey: key)
    }
    
    @objc func uise_setBlock(_ block: ((_ light: Bool) -> Void)?, forKey key: String?) {
        guard let key, key.count > 0 else { return }
        Task { @MainActor in
            NSObject.uise_weakColorHashTable.add(self)
            uise_blocks.setValue(block, forKey: key)
        }
    }
    
    @objc func uise_setValue(_ value: UIColor?, forKey key: String) {
        uise_runAndSetBlock({ [weak self] _ in
            guard let self else { return }
            self.setValue(value?.uise_current, forKey: key)
        }, forKey: #function+"\(key)")
    }
}

// MARK: -- UIKit --
public extension UIView {
    @objc func uise_setAlpha(withLight l: CGFloat, dark d: CGFloat) {
        uise_runAndSetBlock({ [weak self] light in
            guard let self else { return }
            self.alpha = light ? l : d
        }, forKey: #function)
    }
}

public extension UIImage {
    fileprivate static func uise_image(with color: UIColor?, size: CGSize = CGSize(width: 1, height: 1)) -> UIImage? {
        guard let color, size.width > 0, size.height > 0 else { return nil }
        let rect = CGRect(origin: .zero, size: size)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        context.setFillColor(color.cgColor)
        context.fill(rect)
        guard let cgImage = UIGraphicsGetImageFromCurrentImageContext()?.cgImage else { return nil }
        return UIImage(cgImage: cgImage)
    }
    
    private static func uise_imageNamed(_ name: String?, in bundle: Bundle?, withUserInterfaceStyle userInterfaceStyle: UIUserInterfaceStyle) -> UIImage? {
        guard let name else { return nil }
        return UIImage(named: name, in: bundle, compatibleWith: UITraitCollection(userInterfaceStyle: userInterfaceStyle))?.withRenderingMode(.alwaysOriginal)
    }
    
    @objc static func uise_light(_ name: String?) -> UIImage? {
        .uise_light(name, inBundle: nil)
    }
    
    @objc static func uise_light(_ name: String?, inBundle bundle: Bundle?) -> UIImage? {
        uise_imageNamed(name, in: bundle, withUserInterfaceStyle: .light)
    }
    
    @objc static func uise_dark(_ name: String?) -> UIImage? {
        .uise_dark(name, inBundle: nil)
    }
    
    @objc static func uise_dark(_ name: String?, inBundle bundle: Bundle?) -> UIImage? {
        uise_imageNamed(name, in: bundle, withUserInterfaceStyle: .dark)
    }
    
    @objc static func uise_current(_ name: String?) -> UIImage? {
        uise_current(name, inBundle: nil)
    }
    
    @objc static func uise_current(_ name: String?, inBundle bundle: Bundle?) -> UIImage? {
        UISEManager.light ? .uise_light(name, inBundle: bundle) : .uise_dark(name, inBundle: bundle)
    }
}

public extension UIColor {
    @objc var uise_light: UIColor {
        resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
    }
    
    @objc var uise_dark: UIColor {
        resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
    }
    
    @objc var uise_current: UIColor {
        UISEManager.light ? uise_light : uise_dark
    }
    
    @objc func uise_alpha(_ a: CGFloat) -> UIColor {
        withAlphaComponent(a)
    }
    
    @objc func uise_alpha(withLight l: CGFloat, dark d: CGFloat) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? self.uise_dark.uise_alpha(d) : self.uise_light.uise_alpha(l) }
    }
    
    @objc static func uise_color(withLight l: UIColor?, dark d: UIColor?) -> UIColor {
        UIColor { ($0.userInterfaceStyle == .dark ? d : l) ?? .clear }
    }
}

public extension UIButton {
    @objc(uise_setImageWithColor:forState:)
    func uise_setImage(withColor c: UIColor?, for state: UIControl.State) {
        if let c {
            uise_setImage(withLight: .uise_image(with: c.uise_light), dark: .uise_image(with: c.uise_dark), for: state)
        } else {
            uise_setImage(withLight: nil, dark: nil, for: state)
        }
    }
    
    @objc(uise_setImageWithName:forState:)
    func uise_setImage(withName n: String?, for state: UIControl.State) {
        uise_setImage(withLight: .uise_light(n), dark: .uise_dark(n), for: state)
    }
    
    @objc(uise_setImageWithLight:dark:forState:)
    func uise_setImage(withLight l: UIImage?, dark d: UIImage?, for state: UIControl.State) {
        uise_runAndSetBlock({ [weak self] light in
            guard let self else { return }
            self.setImage( light ? l : d, for: state)
        }, forKey: #function+"\(state.rawValue)")
    }
    
    @objc(uise_setBackgroundImageWithColor:forState:)
    func uise_setBackgroundImage(withColor c: UIColor?, for state: UIControl.State) {
        if let c {
            uise_setBackgroundImage(withLight: .uise_image(with: c.uise_light), dark: .uise_image(with: c.uise_dark), for: state)
        } else {
            uise_setBackgroundImage(withLight: nil, dark: nil, for: state)
        }
    }
    
    @objc(uise_setBackgroundImageWithName:forState:)
    func uise_setBackgroundImage(withName n: String?, for state: UIControl.State) {
        uise_setBackgroundImage(withLight: .uise_light(n), dark: .uise_dark(n), for: state)
    }
    
    @objc(uise_setBackgroundImageWithLight:dark:forState:)
    func uise_setBackgroundImage(withLight l: UIImage?, dark d: UIImage?, for state: UIControl.State) {
        uise_runAndSetBlock({ [weak self] light in
            guard let self else { return }
            self.setBackgroundImage( light ? l : d, for: state)
        }, forKey: #function+"\(state.rawValue)")
    }
}

public extension UIImageView {
    @objc func uise_setImage(withColor c: UIColor?) {
        if let c {
            uise_setImage(withLight: .uise_image(with: c.uise_light), dark: .uise_image(with: c.uise_dark))
        } else {
            uise_setImage(withLight: nil, dark: nil)
        }
    }
    
    @objc func uise_setImage(withName n: String?) {
        uise_setImage(withLight: .uise_light(n), dark: .uise_dark(n))
    }
    
    @objc func uise_setImage(withLight l: UIImage?, dark d: UIImage?) {
        uise_runAndSetBlock({ [weak self] light in
            guard let self else { return }
            self.image = light ? l : d
        }, forKey: #function)
    }
}

// MARK: -- QuartzCore --
public extension CALayer {
    private struct UISEAssociatedKeys {
        static var uise_backgroundColor: UInt8 = 0
        static var uise_borderColor: UInt8 = 0
        static var uise_shadowColor: UInt8 = 0
        static var uise_contentsImageName: UInt8 = 0
    }
    
    @objc var uise_backgroundColor: UIColor? {
        get { objc_getAssociatedObject(self, &UISEAssociatedKeys.uise_backgroundColor) as? UIColor }
        set {
            objc_setAssociatedObject(self, &UISEAssociatedKeys.uise_backgroundColor, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            uise_runAndSetBlock({ [weak self] _ in
                guard let self else { return }
                self.backgroundColor = newValue?.uise_current.cgColor
            }, forKey: #function)
        }
    }
    
    @objc var uise_borderColor: UIColor? {
        get { objc_getAssociatedObject(self, &UISEAssociatedKeys.uise_borderColor) as? UIColor }
        set {
            objc_setAssociatedObject(self, &UISEAssociatedKeys.uise_borderColor, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            uise_runAndSetBlock({ [weak self] _ in
                guard let self else { return }
                self.borderColor = newValue?.uise_current.cgColor
            }, forKey: #function)
        }
    }
    
    @objc var uise_shadowColor: UIColor? {
        get { objc_getAssociatedObject(self, &UISEAssociatedKeys.uise_shadowColor) as? UIColor }
        set {
            objc_setAssociatedObject(self, &UISEAssociatedKeys.uise_shadowColor, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            uise_runAndSetBlock({ [weak self] _ in
                guard let self else { return }
                self.shadowColor = newValue?.uise_current.cgColor
            }, forKey: #function)
        }
    }
    
    @objc var uise_contentsImageName: String? {
        get { objc_getAssociatedObject(self, &UISEAssociatedKeys.uise_contentsImageName) as? String }
        set {
            objc_setAssociatedObject(self, &UISEAssociatedKeys.uise_contentsImageName, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            uise_runAndSetBlock({ [weak self] _ in
                guard let self else { return }
                self.contents = UIImage.uise_current(newValue)?.cgImage
            }, forKey: #function)
        }
    }
}

public extension CAShapeLayer {
    private struct UISEAssociatedKeys {
        static var uise_fillColor: UInt8 = 0
        static var uise_strokeColor: UInt8 = 0
    }
    
    @objc var uise_fillColor: UIColor? {
        get { objc_getAssociatedObject(self, &UISEAssociatedKeys.uise_fillColor) as? UIColor }
        set {
            objc_setAssociatedObject(self, &UISEAssociatedKeys.uise_fillColor, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            uise_runAndSetBlock({ [weak self] _ in
                guard let self else { return }
                self.fillColor = newValue?.uise_current.cgColor
            }, forKey: #function)
        }
    }
    
    @objc var uise_strokeColor: UIColor? {
        get { objc_getAssociatedObject(self, &UISEAssociatedKeys.uise_strokeColor) as? UIColor }
        set {
            objc_setAssociatedObject(self, &UISEAssociatedKeys.uise_strokeColor, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            uise_runAndSetBlock({ [weak self] _ in
                guard let self else { return }
                self.strokeColor = newValue?.uise_current.cgColor
            }, forKey: #function)
        }
    }
}

public extension CAGradientLayer {
    private struct UISEAssociatedKeys {
        static var uise_colors: UInt8 = 0
    }
    
    @objc var uise_colors: [UIColor]? {
        get { objc_getAssociatedObject(self, &UISEAssociatedKeys.uise_colors) as? [UIColor] }
        set {
            objc_setAssociatedObject(self, &UISEAssociatedKeys.uise_colors, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            uise_runAndSetBlock({ [weak self] _ in
                guard let self else { return }
                self.colors = newValue?.map { $0.uise_current.cgColor }
            }, forKey: #function)
        }
    }
}

public extension CABasicAnimation {
    private struct UISEAssociatedKeys {
        static var uise_fromValue: UInt8 = 0
        static var uise_toValue: UInt8 = 0
    }
    
    @objc var uise_fromValue: UIColor? {
        get { objc_getAssociatedObject(self, &UISEAssociatedKeys.uise_fromValue) as? UIColor }
        set {
            objc_setAssociatedObject(self, &UISEAssociatedKeys.uise_fromValue, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            uise_runAndSetBlock({ [weak self] _ in
                guard let self else { return }
                self.fromValue = newValue?.uise_current.cgColor
            }, forKey: #function)
        }
    }
    
    @objc var uise_toValue: UIColor? {
        get { objc_getAssociatedObject(self, &UISEAssociatedKeys.uise_toValue) as? UIColor }
        set {
            objc_setAssociatedObject(self, &UISEAssociatedKeys.uise_toValue, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            uise_runAndSetBlock({ [weak self] _ in
                guard let self else { return }
                self.toValue = newValue?.uise_current.cgColor
            }, forKey: #function)
        }
    }
}
