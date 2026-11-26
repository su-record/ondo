#include "csensors.h"

#include <IOKit/IOKitLib.h>
#include <string.h>

/* Layout of the AppleSMC user-client structure (80 bytes); it must not change. */
typedef struct { char major, minor, build, reserved; uint16_t release; } smc_version;
typedef struct { uint16_t version, length; uint32_t cpu_limit, gpu_limit, mem_limit; } smc_limits;
typedef struct { uint32_t data_size, data_type; char data_attributes; } smc_key_info;
typedef struct {
    uint32_t key;
    smc_version version;
    smc_limits limits;
    smc_key_info info;
    char result, status, command;
    uint32_t index;
    uint8_t bytes[32];
} smc_message;

enum { SMC_SELECTOR = 2, SMC_READ_BYTES = 5, SMC_READ_INDEX = 8, SMC_READ_KEY_INFO = 9 };

static io_connect_t connection = 0;

static int call(smc_message *in, smc_message *out) {
    size_t size = sizeof *out;
    kern_return_t result = IOConnectCallStructMethod(connection, SMC_SELECTOR, in, sizeof *in, out, &size);
    return (result == KERN_SUCCESS && out->result == 0) ? 0 : -1;
}

int ondo_smc_open(void) {
    if (connection) return 0;
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return -1;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &connection);
    IOObjectRelease(service);
    if (result != KERN_SUCCESS) { connection = 0; return -1; }
    return 0;
}

void ondo_smc_close(void) {
    if (!connection) return;
    IOServiceClose(connection);
    connection = 0;
}

int ondo_smc_read(uint32_t key, uint32_t *type, uint32_t *size, uint8_t bytes[32]) {
    if (ondo_smc_open() != 0) return -1;
    smc_message in = {0}, out = {0};
    in.key = key;
    in.command = SMC_READ_KEY_INFO;
    if (call(&in, &out) != 0) return -1;
    uint32_t data_size = out.info.data_size;
    if (data_size > 32) return -1;
    *type = out.info.data_type;
    *size = data_size;
    in.info.data_size = data_size;
    in.command = SMC_READ_BYTES;
    memset(&out, 0, sizeof out);
    if (call(&in, &out) != 0) return -1;
    memcpy(bytes, out.bytes, 32);
    return 0;
}

int ondo_smc_key_count(uint32_t *count) {
    uint32_t type, size;
    uint8_t bytes[32];
    if (ondo_smc_read('#KEY', &type, &size, bytes) != 0 || size < 4) return -1;
    *count = (uint32_t)bytes[0] << 24 | (uint32_t)bytes[1] << 16 | (uint32_t)bytes[2] << 8 | bytes[3];
    return 0;
}

int ondo_smc_key_at(uint32_t index, uint32_t *key) {
    if (ondo_smc_open() != 0) return -1;
    smc_message in = {0}, out = {0};
    in.command = SMC_READ_INDEX;
    in.index = index;
    if (call(&in, &out) != 0) return -1;
    *key = out.key;
    return 0;
}
