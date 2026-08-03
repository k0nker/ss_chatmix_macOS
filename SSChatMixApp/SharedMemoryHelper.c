//
//  SharedMemoryHelper.c
//  Helper functions for POSIX shared memory from Swift
//

#include "SharedMemoryHelper.h"
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

int shm_open_helper(const char *name, int oflag, mode_t mode) {
    return shm_open(name, oflag, mode);
}
