#ifndef CSENSORS_H
#define CSENSORS_H

#include <stdint.h>

/* SMC (AppleSMC user client). Functions return 0 on success. */
int ondo_smc_open(void);
void ondo_smc_close(void);
int ondo_smc_key_count(uint32_t *count);
int ondo_smc_key_at(uint32_t index, uint32_t *key);
/* Reads up to 32 bytes. `type` is the four-character data type, such as 'flt ' or 'sp78'. */
int ondo_smc_read(uint32_t key, uint32_t *type, uint32_t *size, uint8_t bytes[32]);

/* HID temperature sensors through the private IOHIDEventSystem API (Apple silicon). */
typedef struct {
    char name[64];
    double celsius;
} ondo_hid_reading;

/* Writes up to `max` readings and returns how many were written, or -1 if the event system is unavailable. */
int ondo_hid_read(ondo_hid_reading *out, int max);

#endif
