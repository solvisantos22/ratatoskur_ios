import SwiftUI

enum AppTheme {
    enum Auth {
        static let background = Color(red: 232 / 255, green: 216 / 255, blue: 194 / 255)
        static let logo = Color(red: 108 / 255, green: 63 / 255, blue: 34 / 255)
        static let primary = Color(red: 140 / 255, green: 90 / 255, blue: 46 / 255)
        static let primaryPressed = Color(red: 110 / 255, green: 68 / 255, blue: 34 / 255)
        static let surface = Color(red: 244 / 255, green: 235 / 255, blue: 221 / 255)
        static let surfaceMuted = Color(red: 237 / 255, green: 225 / 255, blue: 205 / 255)
        static let textPrimary = Color(red: 43 / 255, green: 30 / 255, blue: 20 / 255)
        static let textSecondary = Color(red: 108 / 255, green: 88 / 255, blue: 72 / 255)
        static let error = Color(red: 182 / 255, green: 58 / 255, blue: 47 / 255)
        static let border = logo.opacity(0.18)

        static let logoDarkHex = "#5A3018"
        static let logoMidHex = "#83502A"
        static let logoLightHex = "#A96835"

        static let logoColorMap: [String: String] = [
            "rgb(60,29,17)": logoDarkHex,
            "rgb(164,81,36)": logoMidHex,
            "rgb(237,130,40)": logoLightHex
        ]
    }
}
