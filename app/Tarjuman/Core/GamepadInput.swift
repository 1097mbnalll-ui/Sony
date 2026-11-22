// SPDX-License-Identifier: AGPL-3.0-only
import CoreHaptics
import Foundation
import GameController

/// Reads the player's controller (DualSense / DualShock / any MFi pad) paired
/// with the iPhone and turns it into console input. Remote Play takes over the
/// console's own controller for the same PSN account, so the player's input
/// has to travel through the phone.
final class GamepadInput: ObservableObject {
    @Published private(set) var controllerName: String?

    /// Called on the main thread whenever the state changes.
    var onChange: ((TrjmControllerInput) -> Void)?

    private var controller: GCController?
    private var hapticEngine: CHHapticEngine?

    init() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] n in
            if let c = n.object as? GCController { self?.attach(c) }
        }
        nc.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] n in
            guard let self, let c = n.object as? GCController, c === self.controller else { return }
            self.controller = nil
            self.hapticEngine = nil
            self.controllerName = nil
            LogStore.shared.info("Controller disconnected")
            self.onChange?(Self.idle)
            if let next = GCController.controllers().first(where: { $0.extendedGamepad != nil }) { self.attach(next) }
        }
        if let c = GCController.controllers().first(where: { $0.extendedGamepad != nil }) { attach(c) }
    }

    var current: TrjmControllerInput {
        guard let pad = controller?.extendedGamepad else { return Self.idle }
        return Self.read(pad)
    }

    static var idle: TrjmControllerInput { TrjmControllerInput() }

    private func attach(_ c: GCController) {
        guard let pad = c.extendedGamepad else { return }
        controller = c
        controllerName = c.vendorName ?? "يد تحكم"
        LogStore.shared.info("Controller connected: \(controllerName ?? "")")
        // Keep PS / Create / Options for the game instead of iOS shortcuts.
        pad.buttonHome?.preferredSystemGestureState = .disabled
        pad.buttonOptions?.preferredSystemGestureState = .disabled
        pad.buttonMenu.preferredSystemGestureState = .disabled
        pad.valueChangedHandler = { [weak self] pad, _ in
            self?.onChange?(Self.read(pad))
        }
        hapticEngine = c.haptics?.createEngine(withLocality: .default)
        try? hapticEngine?.start()
        onChange?(Self.read(pad))
    }

    /// Console rumble → controller haptics.
    func rumble(left: UInt8, right: UInt8) {
        guard let engine = hapticEngine else { return }
        let strength = Float(max(left, right)) / 255
        guard strength > 0.02 else { return }
        let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: strength),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(right) / 255),
        ], relativeTime: 0, duration: 0.12)
        do {
            let player = try engine.makePlayer(with: CHHapticPattern(events: [event], parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            try? engine.start()
        }
    }

    private static func axis(_ v: Float) -> Int16 {
        Int16(max(-32767, min(32767, (v * 32767).rounded())))
    }

    private static func trigger(_ v: Float) -> UInt8 {
        UInt8(max(0, min(255, (v * 255).rounded())))
    }

    static func read(_ p: GCExtendedGamepad) -> TrjmControllerInput {
        var s = TrjmControllerInput()
        var b: UInt32 = 0
        func set(_ pressed: Bool?, _ bit: UInt32) { if pressed == true { b |= bit } }
        set(p.buttonA.isPressed, TRJM_BTN_CROSS)
        set(p.buttonB.isPressed, TRJM_BTN_CIRCLE)
        set(p.buttonX.isPressed, TRJM_BTN_SQUARE)
        set(p.buttonY.isPressed, TRJM_BTN_TRIANGLE)
        set(p.dpad.left.isPressed, TRJM_BTN_DPAD_LEFT)
        set(p.dpad.right.isPressed, TRJM_BTN_DPAD_RIGHT)
        set(p.dpad.up.isPressed, TRJM_BTN_DPAD_UP)
        set(p.dpad.down.isPressed, TRJM_BTN_DPAD_DOWN)
        set(p.leftShoulder.isPressed, TRJM_BTN_L1)
        set(p.rightShoulder.isPressed, TRJM_BTN_R1)
        set(p.leftThumbstickButton?.isPressed, TRJM_BTN_L3)
        set(p.rightThumbstickButton?.isPressed, TRJM_BTN_R3)
        set(p.buttonMenu.isPressed, TRJM_BTN_OPTIONS)
        set(p.buttonOptions?.isPressed, TRJM_BTN_CREATE)
        set(p.buttonHome?.isPressed, TRJM_BTN_PS)

        s.l2 = trigger(p.leftTrigger.value)
        s.r2 = trigger(p.rightTrigger.value)
        // GameController: up is positive. Console: down is positive.
        s.left_x = axis(p.leftThumbstick.xAxis.value)
        s.left_y = axis(-p.leftThumbstick.yAxis.value)
        s.right_x = axis(p.rightThumbstick.xAxis.value)
        s.right_y = axis(-p.rightThumbstick.yAxis.value)

        if let ds = p as? GCDualSenseGamepad {
            set(ds.touchpadButton.isPressed, TRJM_BTN_TOUCHPAD)
            touch(ds.touchpadPrimary, index: 0, into: &s)
            touch(ds.touchpadSecondary, index: 1, into: &s)
        } else if let ds4 = p as? GCDualShockGamepad {
            set(ds4.touchpadButton.isPressed, TRJM_BTN_TOUCHPAD)
            touch(ds4.touchpadPrimary, index: 0, into: &s)
            touch(ds4.touchpadSecondary, index: 1, into: &s)
        }
        s.buttons = b
        return s
    }

    /// Touchpad axes are -1...1 with up positive; a finger is "down" when not exactly 0,0.
    private static func touch(_ pad: GCControllerDirectionPad, index: Int, into s: inout TrjmControllerInput) {
        let x = pad.xAxis.value, y = pad.yAxis.value
        let active = x != 0 || y != 0
        let px = UInt16(max(0, min(1919, ((x + 1) / 2 * 1919).rounded())))
        let py = UInt16(max(0, min(941, ((1 - y) / 2 * 941).rounded())))
        if index == 0 {
            s.touch_active.0 = active; s.touch_x.0 = px; s.touch_y.0 = py
        } else {
            s.touch_active.1 = active; s.touch_x.1 = px; s.touch_y.1 = py
        }
    }
}
