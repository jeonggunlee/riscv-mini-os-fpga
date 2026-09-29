#ifndef MINIFS_H
#define MINIFS_H

typedef unsigned int fs_u32;
typedef unsigned char fs_u8;

#define FS_BLOCK_SIZE 512u
#define FS_BLOCK_COUNT 16u
#define FS_MAX_FILES 32u
#define FS_NAME_BYTES 16u

/* On-disk entry: 24 bytes, little-endian RV32. Empty name[0] means free. */
struct file_entry {
    char name[FS_NAME_BYTES];
    fs_u32 size;
    fs_u32 start_block;
};

/* 0 on success, -1 for invalid input / missing file / no space. */
int fs_init(void);
int fs_format(void);
int fs_create(const char *name);
int fs_write(const char *name, const void *data, fs_u32 size);
int fs_read(const char *name, void *buffer, fs_u32 capacity);
int fs_read_at(const char *name, void *buffer, fs_u32 capacity, fs_u32 offset);
int fs_delete(const char *name);
void fs_list(void (*emit)(const char *name, fs_u32 size));

#endif
