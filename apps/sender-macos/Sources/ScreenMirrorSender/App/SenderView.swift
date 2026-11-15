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
                        Button("Buscar") { model.fetchStatus() }
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
                }
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
