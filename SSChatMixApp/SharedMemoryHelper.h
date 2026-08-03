//
//  SharedMemoryHelper.h
//  Helper functions for POSIX shared memory from Swift
//

#ifndef SharedMemoryHelper_h
#define SharedMemoryHelper_h

#include <sys/types.h>

// Non-variadic wrapper for shm_open
int shm_open_helper(const char *name, int oflag, mode_t mode);

#endif /* SharedMemoryHelper_h */
