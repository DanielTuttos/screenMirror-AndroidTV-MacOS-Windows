// Dispositivo de audio virtual dinámico «ScreenMirror TV» (AudioServerPlugIn de macOS).
//
// El driver se carga en coreaudiod pero NO expone ningún dispositivo inicialmente.
// Escucha en un socket Unix local (/tmp/screenmirror_audio.sock).
// Cuando la app ScreenMirror se inicia, se conecta al socket y el driver añade el
// dispositivo «ScreenMirror TV» (aparece inmediatamente en el sistema).
// Cuando la app ScreenMirror se cierra (o se cae la conexión), el driver retira
// el dispositivo (desaparece inmediatamente del menú de sonido de macOS).
//
// Construido sobre libASPL (MIT, https://github.com/gavv/libASPL).

#include <aspl/Driver.hpp>
#include <CoreAudio/AudioServerPlugIn.h>

#include <memory>
#include <thread>
#include <atomic>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <unistd.h>
#include <poll.h>

namespace {

constexpr const char* kDeviceUID = "tv.screenmirror.audio.device";
constexpr const char* kSocketPath = "/tmp/screenmirror_audio.sock";
constexpr UInt32 kSampleRate = 48000;
constexpr UInt32 kChannelCount = 2;

class DynamicDeviceManager {
public:
    DynamicDeviceManager(std::shared_ptr<aspl::Context> context, std::shared_ptr<aspl::Plugin> plugin)
        : context_(std::move(context)), plugin_(std::move(plugin)), running_(true)
    {
        worker_ = std::thread(&DynamicDeviceManager::ServerLoop, this);
    }

    ~DynamicDeviceManager() {
        running_ = false;
        if (serverFd_ != -1) {
            close(serverFd_);
            serverFd_ = -1;
        }
        unlink(kSocketPath);
        if (worker_.joinable()) {
            worker_.join();
        }
    }

private:
    std::shared_ptr<aspl::Device> CreateDevice() {
        aspl::DeviceParameters deviceParams;
        deviceParams.Name = "ScreenMirror TV";
        deviceParams.Manufacturer = "ScreenMirror";
        deviceParams.DeviceUID = kDeviceUID;
        deviceParams.ModelUID = "tv.screenmirror.audio.model";
        deviceParams.SampleRate = kSampleRate;
        deviceParams.ChannelCount = kChannelCount;
        deviceParams.EnableMixing = true;
        deviceParams.CanBeDefault = true;
        deviceParams.CanBeDefaultForSystemSounds = false;

        auto device = std::make_shared<aspl::Device>(context_, deviceParams);
        device->AddStreamWithControlsAsync(aspl::Direction::Output);
        return device;
    }

    void ServerLoop() {
        unlink(kSocketPath);

        serverFd_ = socket(AF_UNIX, SOCK_STREAM, 0);
        if (serverFd_ < 0) return;

        sockaddr_un addr{};
        addr.sun_family = AF_UNIX;
        strncpy(addr.sun_path, kSocketPath, sizeof(addr.sun_path) - 1);

        if (bind(serverFd_, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0) {
            close(serverFd_);
            serverFd_ = -1;
            return;
        }

        // Permitir que cualquier usuario/app local pueda conectarse al socket
        chmod(kSocketPath, 0666);

        if (listen(serverFd_, 5) < 0) {
            close(serverFd_);
            serverFd_ = -1;
            return;
        }

        std::shared_ptr<aspl::Device> currentDevice = nullptr;
        int activeClientFd = -1;

        while (running_) {
            pollfd pfd{};
            pfd.fd = (activeClientFd != -1) ? activeClientFd : serverFd_;
            pfd.events = POLLIN | POLLHUP | POLLERR;

            int ret = poll(&pfd, 1, 1000); // 1 segundo timeout para verificar running_
            if (ret <= 0) continue;

            if (activeClientFd == -1) {
                // Hay nueva conexión
                int clientFd = accept(serverFd_, nullptr, nullptr);
                if (clientFd >= 0) {
                    activeClientFd = clientFd;
                    if (!currentDevice) {
                        currentDevice = CreateDevice();
                        plugin_->AddDevice(currentDevice);
                    }
                }
            } else {
                // Monitorizar cliente activo: si manda EOF o se cierra el socket
                char buf[16];
                ssize_t n = recv(activeClientFd, buf, sizeof(buf), MSG_DONTWAIT);
                if (n <= 0) {
                    // Cliente desconectado (la app se cerró o terminó)
                    close(activeClientFd);
                    activeClientFd = -1;
                    if (currentDevice) {
                        plugin_->RemoveDevice(currentDevice);
                        currentDevice = nullptr;
                    }
                }
            }
        }

        if (activeClientFd != -1) {
            close(activeClientFd);
        }
        if (currentDevice) {
            plugin_->RemoveDevice(currentDevice);
        }
    }

    std::shared_ptr<aspl::Context> context_;
    std::shared_ptr<aspl::Plugin> plugin_;
    std::atomic<bool> running_;
    int serverFd_ = -1;
    std::thread worker_;
};

std::shared_ptr<aspl::Driver> CreateDriver()
{
    auto context = std::make_shared<aspl::Context>();
    auto plugin = std::make_shared<aspl::Plugin>(context);

    // Inicializar el gestor dinámico (mantiene viva la escucha del socket)
    static auto manager = std::make_unique<DynamicDeviceManager>(context, plugin);

    return std::make_shared<aspl::Driver>(context, plugin);
}

} // namespace

extern "C" void* ScreenMirrorAudioEntryPoint(CFAllocatorRef allocator, CFUUIDRef typeUUID)
{
    if (!CFEqual(typeUUID, kAudioServerPlugInTypeUUID)) {
        return nullptr;
    }

    static std::shared_ptr<aspl::Driver> driver = CreateDriver();
    return driver->GetReference();
}
