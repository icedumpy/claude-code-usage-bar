import AppKit
import UsageCore

/// The Claude sunburst, embedded as a small alpha mask (extracted from
/// Claude-ai-icon.svg) and tinted to the severity color at runtime. Non-template
/// so the menu bar keeps our specific green/yellow/red instead of auto-tinting.
enum ClaudeMark {
    private static let base64 =
        "iVBORw0KGgoAAAANSUhEUgAAADYAAAA2CAYAAACMRWrdAAAABmJLR0QA/wD/AP+gvaeTAAAEo0lEQVRoge2Za4hVVRTHf7ecUtNx7DFp76BsiiBJhECKGBITe0hl9BL7EFaTZvRw+tKDPvRQmyQKelKNRUzJEApRRmApfRjxQeWMVKg0PiZxHLXyNbd7+7D24ayz7z7nnjtzzulD5w+be869Y+f8z65kZ2ufvfba+0KOHDly5MgRGy1AF7ASuDJmnYtSY5MQrgUGgbIpPwOFCPsC8IWxfTZ1dsPAcnynvDI9wn66sisCo9MgdVICbfzkkD0WYa+dHgCOJMAhFTQChwiOWAm4PMT+Y2W3PqLdG4D5wBWJMR0CFlA5Hd8JsV2jbN4PsXka+ThlYBswKkmyteBkYAtBx44io2lD2z3u0Ls+UkvylIOYA9wOnO7QXe8g9JLDbo/SN1u6O4B/HO1MGz71cCxSHf0OXOOw+dwi9BfBUSsAJ/DX4Xilm4qMsu1UNzIjUsO7VoeDQKtlcz7wt2W3TOknKPl2JW8Eeql06k8yCB73OjouAysI7kUvWvojwESjm6LknUZWB6x1tFtCpn0meAI45iDxI9BkbOqBfZb+daObrWRe1uHa4MvAq+m6UomrkHnvmjbzjI0d2Y4C5wEPK9ktwG34YV2X9chIZo7TkH3K9aU/QoLCL5a8DXhGvTcjmYddvx+4IDtX3LgRiZA2uR7gNUu2g+C0s7MVb13dmqkHERgHvId7StlldxV9WLbiYQSSqk2sYpcoZuAO2XHLAHCWaq8BSZifBNqBzfiB6xhwf8r+BNBgSAzFsQ7gEWSN9lB9BiyIIhJ1IAQ4B9lL+oEDyFc9oJ5LIfVmA2/jzhWHg+PISX0tsvEfDjOs5tinwF0R+oOIg4fN7y5gL7KW6oClcRk7UEIi60ZVNiBbx7AxCdjJ0NdNLeUE8AOwBLgZd6IdG9VGzMNoYKwp48zvKeZ5FDASSVTrjX09cCGShsVBN/AZsiX0I1POwyFgv5GHTr2scAmwinRGdSdwZ2aeGDQgi/p4jYSXIFFuJfBHzDr3ZOFQnSG23+q8E/gqBslBi2gT8AAS+reH1GlP2SdmIfuO7rQPOW0/qmRdIQS9UgQeDOnjXOBu4A1gHeJ0aklyE/CNg+AK4AwkyS0aWQ/wkHk+iAQBe+14z//ZJWoBWIgcIDW5XmT0QHK5Pvz0ZzLwsnn/FnjKqrsY+FW9v0kyd56x0UjlKJWAt/BD/QiCJ+JFRt5p3j9BtoptymYPcCnwnZJ1GLtM4H11r/yG3E5pvKL0q/H3yq1G1mbeZ1pttSOOfKhkX5LSFbiNucgI7UOO7nan+kTci6w1jJ33x8ViZd9B0LmbkA/xgmpnHZIIpI6RIfLL8A+PReA6pZuGT36ekjcS3CJ2I3shSCLtnbA3kXxCHQtj8KeaK7LpO8kZlu4+gqP2gdJdjCS+ZeC5xFlXQYHglFpD5QWnPqNNdrSxmqBzM5XuVOB54OokScdBiyLUhSTINvSt1gSH/myCqdTXqTCtER6hbuBMh34s/n18kfDr6ln4AWNr8jRrRxvwPXJv6EIzwVQrCq2mrfmJsUsRrfiObcmq0yzSlo3qeVcG/QEp/z1jsAM5n/UhozeQQZ85cuTIkeP/gX8By9JCCmLPqKgAAAAASUVORK5CYII="

    private static let mask: NSImage? = {
        guard let data = Data(base64Encoded: base64), let img = NSImage(data: data) else { return nil }
        img.size = NSSize(width: 18, height: 18)
        return img
    }()

    private static var cache: [Severity: NSImage] = [:]

    /// A sunburst filled with the severity color on a transparent background.
    static func tinted(_ severity: Severity) -> NSImage? {
        if let cached = cache[severity] { return cached }
        guard let mask else { return nil }
        let size = mask.size
        let out = NSImage(size: size)
        out.lockFocus()
        nsColor(severity).set()
        NSRect(origin: .zero, size: size).fill()
        // Keep the fill only where the sunburst mask is opaque.
        mask.draw(in: NSRect(origin: .zero, size: size), from: .zero,
                  operation: .destinationIn, fraction: 1.0)
        out.unlockFocus()
        out.isTemplate = false
        cache[severity] = out
        return out
    }

    static func nsColor(_ s: Severity) -> NSColor {
        switch s {
        case .normal: return .systemGreen
        case .warning: return .systemYellow
        case .severe, .critical: return .systemRed
        case .unknown: return .secondaryLabelColor
        }
    }
}
