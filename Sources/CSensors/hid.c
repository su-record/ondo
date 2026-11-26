#include "csensors.h"

#include <CoreFoundation/CoreFoundation.h>
#include <string.h>

/* Private IOKit functions, exported by IOKit.framework but absent from its headers. */
typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp);
CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef property);
double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

enum {
    VENDOR_USAGE_PAGE = 0xff00,  /* Apple vendor page */
    TEMPERATURE_USAGE = 5,       /* temperature sensors on that page */
    TEMPERATURE_EVENT = 15,      /* kIOHIDEventTypeTemperature */
};

static IOHIDEventSystemClientRef client = NULL;

static IOHIDEventSystemClientRef temperature_client(void) {
    if (client) return client;
    client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!client) return NULL;
    int page = VENDOR_USAGE_PAGE, usage = TEMPERATURE_USAGE;
    CFNumberRef page_number = CFNumberCreate(NULL, kCFNumberIntType, &page);
    CFNumberRef usage_number = CFNumberCreate(NULL, kCFNumberIntType, &usage);
    const void *keys[] = {CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage")};
    const void *values[] = {page_number, usage_number};
    CFDictionaryRef match = CFDictionaryCreate(NULL, keys, values, 2,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    IOHIDEventSystemClientSetMatching(client, match);
    CFRelease(match);
    CFRelease(page_number);
    CFRelease(usage_number);
    return client;
}

int ondo_hid_read(ondo_hid_reading *out, int max) {
    IOHIDEventSystemClientRef system = temperature_client();
    if (!system) return -1;
    CFArrayRef services = IOHIDEventSystemClientCopyServices(system);
    if (!services) return 0;
    int written = 0;
    CFIndex count = CFArrayGetCount(services);
    for (CFIndex i = 0; i < count && written < max; i++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
        IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, TEMPERATURE_EVENT, 0, 0);
        if (!event) continue;
        ondo_hid_reading *reading = &out[written++];
        reading->celsius = IOHIDEventGetFloatValue(event, TEMPERATURE_EVENT << 16);
        CFRelease(event);
        strcpy(reading->name, "?");
        CFTypeRef name = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
        if (name && CFGetTypeID(name) == CFStringGetTypeID())
            CFStringGetCString((CFStringRef)name, reading->name, sizeof reading->name, kCFStringEncodingUTF8);
        if (name) CFRelease(name);
    }
    CFRelease(services);
    return written;
}
