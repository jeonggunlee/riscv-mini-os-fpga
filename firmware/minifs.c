/*
 * MiniFS v1: 8 KiB RAM disk, 512-byte blocks.
 *   block 0      superblock (magic/version/geometry)
 *   blocks 1-2   32 fixed-size file entries (32 * 24 = 768 bytes)
 *   blocks 3-15  contiguous file data; no directories or persistence on power loss
 *
 * The disk is a separate MMIO RAM in rv32_soc.v, not part of the 8 KiB
 * program/stack memory. CPU_RESET retains contents; FPGA reconfiguration does
 * not. All callers run in trusted M-mode and must provide valid pointers.
 */
#include "minifs.h"

#define DISK_BASE 0x80100000u
#define DATA_FIRST_BLOCK 3u
#define FS_MAGIC 0x3153464du  /* "MFS1" as a little-endian 32-bit word */
#define FS_VERSION 1u

static volatile fs_u8 *const disk = (volatile fs_u8 *)DISK_BASE;
static volatile struct file_entry *const files =
    (volatile struct file_entry *)(DISK_BASE + FS_BLOCK_SIZE);
static volatile fs_u32 *const header = (volatile fs_u32 *)DISK_BASE;

static int valid_name(const char *name)
{
    fs_u32 i;
    if (!name || !name[0]) return 0;
    for (i = 0; i < FS_NAME_BYTES; i++) {
        if (name[i] == '\0') return 1;
        if (name[i] == '/' || name[i] == ' ') return 0;
    }
    return 0; /* require a NUL within the 16-byte field */
}

static int name_equals(volatile const char *on_disk, const char *name)
{
    fs_u32 i;
    for (i = 0; i < FS_NAME_BYTES; i++) {
        char c = on_disk[i];
        if (c != name[i]) return 0;
        if (c == '\0') return 1;
    }
    return 0;
}

static int find_file(const char *name)
{
    fs_u32 i;
    if (!valid_name(name)) return -1;
    for (i = 0; i < FS_MAX_FILES; i++)
        if (files[i].name[0] && name_equals(files[i].name, name))
            return (int)i;
    return -1;
}

int fs_format(void)
{
    fs_u32 i;
    for (i = 0; i < FS_BLOCK_COUNT * FS_BLOCK_SIZE; i++) disk[i] = 0;
    header[1] = FS_VERSION;
    header[2] = FS_BLOCK_COUNT;
    header[3] = FS_BLOCK_SIZE;
    header[0] = FS_MAGIC; /* commit the superblock last */
    return 0;
}

int fs_init(void)
{
    if (header[0] == FS_MAGIC && header[1] == FS_VERSION &&
        header[2] == FS_BLOCK_COUNT && header[3] == FS_BLOCK_SIZE)
        return 0;
    return fs_format();
}

int fs_create(const char *name)
{
    fs_u32 i, j;
    if (!valid_name(name) || find_file(name) >= 0) return -1;
    for (i = 0; i < FS_MAX_FILES; i++) {
        if (files[i].name[0] == 0) {
            /* Publish name[0] last, after the rest of the entry is ready. */
            files[i].size = 0;
            files[i].start_block = 0;
            for (j = 1; j < FS_NAME_BYTES; j++) {
                /* Do not read past the source string's terminating NUL. */
                char c = name[j];
                files[i].name[j] = c;
                if (c == '\0') break;
            }
            files[i].name[0] = name[0];
            return 0;
        }
    }
    return -1;
}

/* Find a contiguous run. An existing file's own blocks may be reused. */
static int find_extent(fs_u32 needed, int skip_file)
{
    fs_u32 first, i;
    if (needed == 0) return 0;
    if (needed > FS_BLOCK_COUNT - DATA_FIRST_BLOCK) return -1;
    for (first = DATA_FIRST_BLOCK; first + needed <= FS_BLOCK_COUNT; first++) {
        int free_run = 1;
        for (i = 0; i < FS_MAX_FILES; i++) {
            fs_u32 size, blocks, start;
            if ((int)i == skip_file || !files[i].name[0]) continue;
            size = files[i].size;
            blocks = (size + FS_BLOCK_SIZE - 1u) >> 9;
            start = files[i].start_block;
            if (blocks && first < start + blocks && start < first + needed) {
                free_run = 0;
                break;
            }
        }
        if (free_run) return (int)first;
    }
    return -1;
}

int fs_write(const char *name, const void *data, fs_u32 size)
{
    int slot = find_file(name);
    fs_u32 i, blocks, off;
    int first;
    const fs_u8 *src = (const fs_u8 *)data;
    if (slot < 0 || (size && !data) ||
        size > (FS_BLOCK_COUNT - DATA_FIRST_BLOCK) * FS_BLOCK_SIZE) return -1;
    blocks = (size + FS_BLOCK_SIZE - 1u) >> 9;
    first = find_extent(blocks, slot);
    if (first < 0) return -1; /* old file is unchanged when space is unavailable */
    off = (fs_u32)first * FS_BLOCK_SIZE;
    for (i = 0; i < size; i++) disk[off + i] = src[i];
    files[slot].start_block = (fs_u32)first;
    files[slot].size = size;
    return (int)size;
}

int fs_read(const char *name, void *buffer, fs_u32 capacity)
{
    int slot = find_file(name);
    fs_u32 i, size, off;
    fs_u8 *dst = (fs_u8 *)buffer;
    if (slot < 0 || (capacity && !buffer)) return -1;
    size = files[slot].size;
    if (size > capacity) return -1; /* no partial reads in v1 */
    off = files[slot].start_block * FS_BLOCK_SIZE;
    for (i = 0; i < size; i++) dst[i] = disk[off + i];
    return (int)size;
}

/* Chunked read for the shell: 0 means EOF, -1 means missing file/error. */
int fs_read_at(const char *name, void *buffer, fs_u32 capacity, fs_u32 offset)
{
    int slot = find_file(name);
    fs_u32 i, count, size, off;
    fs_u8 *dst = (fs_u8 *)buffer;
    if (slot < 0 || (capacity && !buffer)) return -1;
    size = files[slot].size;
    if (offset >= size) return 0;
    count = size - offset;
    if (count > capacity) count = capacity;
    off = files[slot].start_block * FS_BLOCK_SIZE + offset;
    for (i = 0; i < count; i++) dst[i] = disk[off + i];
    return (int)count;
}

int fs_delete(const char *name)
{
    int slot = find_file(name);
    if (slot < 0) return -1;
    files[slot].name[0] = 0; /* frees the entry and extent; data remains until reused */
    files[slot].size = 0;
    files[slot].start_block = 0;
    return 0;
}

void fs_list(void (*emit)(const char *name, fs_u32 size))
{
    fs_u32 i, j;
    char name[FS_NAME_BYTES];
    if (!emit) return;
    for (i = 0; i < FS_MAX_FILES; i++) {
        if (!files[i].name[0]) continue;
        for (j = 0; j < FS_NAME_BYTES; j++) name[j] = files[i].name[j];
        name[FS_NAME_BYTES - 1u] = '\0';
        emit(name, files[i].size);
    }
}
