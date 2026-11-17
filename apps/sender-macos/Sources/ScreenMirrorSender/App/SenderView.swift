import AppKit
import SwiftUI

struct SenderView: View {
    @StateObject private var model = SenderViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ScreenMirror").font(.headline)
                Spacer()
                if model.isStreaming {
                    Text("● EMITIENDO")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            GroupBox("TV") {
                VStack(alignment: .leading, spacing: 6) {
                    if model.receivers.isEmpty {
                        Text("Buscando TVs en la red…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.receivers) { receiver in
                        Button {
                            model.select(receiver)
                        } label: {
                            HStack {
                                Image(systemName: model.host == receiver.host
                                    ? "checkmark.circle.fill"
                                    : "circle")
                                Text(receiver.name)
                                Spacer()
                                Text(receiver.needsPairing ? "emparejar" : "lista")
                                    .font(.caption)
                                    .foregroundStyle(receiver.needsPairing ? Color.orange : Color.green)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    HStack {
                        TextField("IP de la TV", text: $model.host)
                            .textFieldStyle(.roundedBorder)
                        Button("Buscar") {
                            model.loadStoredToken()
                            model.fetchStatus()
                        }
                    }
                    if let name = model.receiverName {
                        Text("\(name) · máximo \(model.maxResolution ?? "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        TextField("PIN", text: $model.pin)
                            .textFieldStyle(.roundedBorder)
                        Button("Emparejar") { model.pair() }
                    }
                }
            }

            GroupBox("Pantalla") {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: Binding(
                        get: { model.virtualDisplay != nil },
                        set: { model.setVirtualDisplay(enabled: $0) }
                    )) {
                        Text("Pantalla virtual (extender)")
                    }
                    .toggleStyle(.switch)
                    if model.virtualDisplay != nil {
                        Text("Escritorio vacío en la TV: se crea una 2ª pantalla en este Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if model.displays.isEmpty {
                        Text("Sin pantallas: pulsa «Actualizar».")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.displays) { display in
                        Button {
                            model.selectedDisplayID = display.id
                        } label: {
                            HStack {
                                Image(systemName: model.selectedDisplayID == display.id
                                    ? "checkmark.circle.fill"
                                    : "circle")
                                Text(display.name)
                                Spacer()
                                Text(display.isMain ? "Espejo" : "Extender")
                                    .font(.caption)
                                    .foregroundStyle(display.isMain ? Color.secondary : Color.green)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Button("Actualizar pantallas") { model.refreshDisplays() }
                        .font(.caption)

                    Divider()

                    HStack {
                        Text("Fluidez:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $model.targetFps) {
                            Text("30 fps").tag(30)
                            Text("60 fps").tag(60)
                        }
                        .pickerStyle(.segmented)
                        .disabled(model.isStreaming)
                    }

                    HStack {
                        Text("Calidad:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $model.targetResolutionHeight) {
                            Text("720p").tag(Optional(720))
                            Text("1080p").tag(Optional(1080))
                            Text("1440p (2K)").tag(Optional(1440))
                        }
                        .pickerStyle(.segmented)
                        .disabled(model.isStreaming)
                    }
                }
            }

            GroupBox("Sonido") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Para oír en la TV, elige «ScreenMirror TV» en la salida de sonido del Mac.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let error = model.errorText {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let stats = model.statsText {
                Text(stats)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Salir") { NSApplication.shared.terminate(nil) }
                Button(model.isStreaming ? "Detener" : "Emitir") { model.toggleStream() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 340)
        .onAppear { model.refreshDisplays() }
    }
}
