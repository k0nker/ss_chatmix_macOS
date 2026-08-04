//
//  SharedMemoryBridge.h
//  SSChatMix
//
//  C bridge for atomic operations in shared memory
//

#ifndef SharedMemoryBridge_h
#define SharedMemoryBridge_h

#include <stdint.h>
#include <stdatomic.h>

#ifdef __cplusplus
extern "C" {
#endif

// C-compatible ring buffer structure (matches C++ layout)
typedef struct {
    uint32_t capacityFrames;
    uint32_t channelCount;
    uint32_t bytesPerFrame;
    volatile uint32_t writePosition;
    volatile uint32_t readPosition;
} SharedRingBufferC;

// Direct access (volatile ensures memory visibility)
static inline uint32_t atomic_load_write_pos(SharedRingBufferC* rb) {
    return rb->writePosition;
}

static inline uint32_t atomic_load_read_pos(SharedRingBufferC* rb) {
    return rb->readPosition;
}

static inline void atomic_store_read_pos(SharedRingBufferC* rb, uint32_t value) {
    rb->readPosition = value;
}

#ifdef __cplusplus
}
#endif

#endif /* SharedMemoryBridge_h */
